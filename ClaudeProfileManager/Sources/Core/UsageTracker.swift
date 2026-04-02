import Foundation

public final class UsageTracker {

    public let statsCachePath: URL
    public let profilesDirectory: URL

    public init(
        statsCachePath: URL? = nil,
        profilesDirectory: URL? = nil
    ) {
        let home = FileManager.default.homeDirectoryForCurrentUser
        self.statsCachePath = statsCachePath ?? home.appendingPathComponent(".claude/stats-cache.json")
        self.profilesDirectory = profilesDirectory ?? home.appendingPathComponent(".claude/profiles")
    }

    // MARK: - Parse

    public func parseStatsCache() throws -> StatsCache {
        let data = try Data(contentsOf: statsCachePath)
        return try JSONDecoder().decode(StatsCache.self, from: data)
    }

    public func parseDailyUsage() throws -> [DailyModelTokens] {
        return try parseStatsCache().dailyModelTokens
    }

    public func parseDailyActivity() throws -> [DailyActivity] {
        return try parseStatsCache().dailyActivity ?? []
    }

    public func parseHourCounts() throws -> [String: Int] {
        return try parseStatsCache().hourCounts ?? [:]
    }

    public func modelBreakdown(forDate date: String? = nil) throws -> [String: Int] {
        let daily = try parseDailyUsage()
        if let date = date, let entry = daily.first(where: { $0.date == date }) {
            return entry.tokensByModel
        }
        // Fallback: aggregate all data for overall breakdown
        var total: [String: Int] = [:]
        for day in daily {
            for (model, tokens) in day.tokensByModel {
                total[model, default: 0] += tokens
            }
        }
        return total
    }

    public func todayUsage() throws -> Int {
        // First try stats-cache
        let today = Self.todayString()
        let daily = try parseDailyUsage()
        if let entry = daily.first(where: { $0.date == today }), entry.totalTokens > 0 {
            return entry.totalTokens
        }

        // Fallback: sum today's individual session token-stats files
        return todayUsageFromSessionFiles()
    }

    /// Sum tokens from individual session files modified today
    public func todayUsageFromSessionFiles() -> Int {
        let claudeDir = profilesDirectory.deletingLastPathComponent() // ~/.claude/
        let fm = FileManager.default
        let today = Self.todayString()

        guard let files = try? fm.contentsOfDirectory(atPath: claudeDir.path) else {
            print("[UsageTracker] Cannot read \(claudeDir.path)")
            return 0
        }

        var total = 0
        for file in files where file.hasPrefix("token-stats") && file.hasSuffix(".json") {
            let path = claudeDir.appendingPathComponent(file)
            guard let attrs = try? fm.attributesOfItem(atPath: path.path),
                  let modDate = attrs[.modificationDate] as? Date else { continue }

            let modDay = Self.dateToString(modDate)
            if modDay == today {
                if let data = try? Data(contentsOf: path),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let tokens = json["totalTokens"] as? Int {
                    total += tokens
                }
            }
        }
        return total
    }

    private static func dateToString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    public func weeklySummary() throws -> Int {
        let daily = try parseDailyUsage()
        let calendar = Calendar.current
        let weekAgo = calendar.date(byAdding: .day, value: -7, to: Date())!

        return daily.filter { entry in
            guard let date = Self.parseDate(entry.date) else { return false }
            return date >= weekAgo
        }.reduce(0) { $0 + $1.totalTokens }
    }

    public func monthlySummary() throws -> Int {
        let daily = try parseDailyUsage()
        let calendar = Calendar.current
        let monthAgo = calendar.date(byAdding: .month, value: -1, to: Date())!

        return daily.filter { entry in
            guard let date = Self.parseDate(entry.date) else { return false }
            return date >= monthAgo
        }.reduce(0) { $0 + $1.totalTokens }
    }

    public func totalSummary() throws -> Int {
        let daily = try parseDailyUsage()
        return daily.reduce(0) { $0 + $1.totalTokens }
    }

    /// Load per-profile usage from .usage.json
    public func loadProfileUsages() -> UsageDatabase {
        let usagePath = profilesDirectory.appendingPathComponent(".usage.json")
        guard let data = try? Data(contentsOf: usagePath),
              let db = try? JSONDecoder().decode(UsageDatabase.self, from: data) else {
            return [:]
        }
        return db
    }

    /// Record current stats-cache usage for the active profile
    public func recordUsage(forProfile profileName: String) {
        let today = Self.todayString()
        let todayTokens = (try? todayUsage()) ?? 0

        let usagePath = profilesDirectory.appendingPathComponent(".usage.json")
        var db = loadProfileUsages()

        if db[profileName] == nil {
            db[profileName] = ProfileUsage(daily: [:], total: 0, lastUsed: nil)
        }

        var entry = db[profileName]!
        entry.daily[today] = todayTokens
        entry.total = entry.daily.values.reduce(0, +)
        entry.lastUsed = ISO8601DateFormatter().string(from: Date())
        db[profileName] = entry

        if let data = try? JSONEncoder().encode(db) {
            try? data.write(to: usagePath)
        }
    }

    /// Record usage for ALL profiles based on stats-cache total allocation
    /// Since stats-cache is global, we split total proportionally or attribute all to active
    public func recordAllProfileUsages(activeProfileName: String?, allProfileNames: [String]) {
        let usagePath = profilesDirectory.appendingPathComponent(".usage.json")
        var db = loadProfileUsages()

        // Get total tokens from stats-cache by date
        guard let daily = try? parseDailyUsage() else { return }

        // Initialize missing profiles
        for name in allProfileNames {
            if db[name] == nil {
                db[name] = ProfileUsage(daily: [:], total: 0, lastUsed: nil)
            }
        }

        // Attribute today's tokens to active profile
        let today = Self.todayString()
        var todayTokens = daily.first(where: { $0.date == today })?.totalTokens ?? 0
        // Fallback: read from individual session files if stats-cache has no today entry
        if todayTokens == 0 {
            todayTokens = todayUsageFromSessionFiles()
        }

        if let active = activeProfileName {
            db[active]?.daily[today] = todayTokens
            db[active]?.lastUsed = ISO8601DateFormatter().string(from: Date())
        }

        // Recalculate totals
        for name in allProfileNames {
            if var entry = db[name] {
                entry.total = entry.daily.values.reduce(0, +)
                db[name] = entry
            }
        }

        if let data = try? JSONEncoder().encode(db) {
            try? data.write(to: usagePath)
        }
    }

    /// Filter daily usage to dates when a specific profile was active
    public func profileDailyUsage(profileId: String) -> [DailyModelTokens] {
        let usages = loadProfileUsages()
        guard let profileUsage = usages[profileId] else { return [] }
        let activeDates = Set(profileUsage.daily.keys)
        guard let allDaily = try? parseDailyUsage() else { return [] }
        return allDaily.filter { activeDates.contains($0.date) }
    }

    // MARK: - Helpers

    public static func todayString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    public static func parseDate(_ string: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: string)
    }
}
