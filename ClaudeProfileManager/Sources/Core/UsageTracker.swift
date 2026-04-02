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
        let today = Self.todayString()
        let daily = try parseDailyUsage()
        return daily.first(where: { $0.date == today })?.totalTokens ?? 0
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
