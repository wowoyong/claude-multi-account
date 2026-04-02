import Foundation

/// Matches stats-cache.json dailyModelTokens entry
public struct DailyModelTokens: Codable {
    public let date: String            // "2026-04-02"
    public let tokensByModel: [String: Int]

    public var totalTokens: Int {
        tokensByModel.values.reduce(0, +)
    }

    public init(date: String, tokensByModel: [String: Int]) {
        self.date = date
        self.tokensByModel = tokensByModel
    }
}

/// Matches stats-cache.json dailyActivity entry
public struct DailyActivity: Codable {
    public let date: String
    public let messageCount: Int
    public let sessionCount: Int
    public let toolCallCount: Int

    public init(date: String, messageCount: Int, sessionCount: Int, toolCallCount: Int) {
        self.date = date
        self.messageCount = messageCount
        self.sessionCount = sessionCount
        self.toolCallCount = toolCallCount
    }
}

/// Matches stats-cache.json top-level
public struct StatsCache: Codable {
    public let dailyModelTokens: [DailyModelTokens]
    public let dailyActivity: [DailyActivity]?
    public let hourCounts: [String: Int]?
    public let totalSessions: Int?
    public let totalMessages: Int?

    public init(dailyModelTokens: [DailyModelTokens], dailyActivity: [DailyActivity]? = nil, hourCounts: [String: Int]? = nil, totalSessions: Int? = nil, totalMessages: Int? = nil) {
        self.dailyModelTokens = dailyModelTokens
        self.dailyActivity = dailyActivity
        self.hourCounts = hourCounts
        self.totalSessions = totalSessions
        self.totalMessages = totalMessages
    }
}

/// Per-profile usage stored in .usage.json
public struct ProfileUsage: Codable {
    public var daily: [String: Int]    // date -> tokens
    public var total: Int
    public var lastUsed: String?

    public init(daily: [String: Int], total: Int, lastUsed: String?) {
        self.daily = daily
        self.total = total
        self.lastUsed = lastUsed
    }
}

public typealias UsageDatabase = [String: ProfileUsage]  // profileName -> usage
