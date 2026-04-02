import XCTest
@testable import ClaudeProfileManagerCore

final class UsageTrackerTests: XCTestCase {

    var tempDir: URL!

    override func setUp() {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cpm-usage-test-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testParseStatsCache() throws {
        let statsJSON = """
        {
            "dailyModelTokens": [
                {"date": "2026-04-01", "tokensByModel": {"claude-opus-4-6": 5000, "claude-sonnet-4-6": 3000}},
                {"date": "2026-04-02", "tokensByModel": {"claude-opus-4-6": 8000}}
            ]
        }
        """.data(using: .utf8)!
        let statsPath = tempDir.appendingPathComponent("stats-cache.json")
        try statsJSON.write(to: statsPath)

        let tracker = UsageTracker(
            statsCachePath: statsPath,
            profilesDirectory: tempDir
        )
        let daily = try tracker.parseDailyUsage()
        XCTAssertEqual(daily.count, 2)
        XCTAssertEqual(daily[0].totalTokens, 8000)
        XCTAssertEqual(daily[1].totalTokens, 8000)
    }

    func testModelBreakdown() throws {
        let statsJSON = """
        {
            "dailyModelTokens": [
                {"date": "2026-04-02", "tokensByModel": {"claude-opus-4-6": 7200, "claude-sonnet-4-6": 2500, "claude-haiku-4-5": 300}}
            ]
        }
        """.data(using: .utf8)!
        let statsPath = tempDir.appendingPathComponent("stats-cache.json")
        try statsJSON.write(to: statsPath)

        let tracker = UsageTracker(statsCachePath: statsPath, profilesDirectory: tempDir)
        let breakdown = try tracker.modelBreakdown(forDate: "2026-04-02")

        XCTAssertEqual(breakdown["claude-opus-4-6"], 7200)
        XCTAssertEqual(breakdown["claude-sonnet-4-6"], 2500)
        XCTAssertEqual(breakdown["claude-haiku-4-5"], 300)
    }

    func testWeeklySummary() throws {
        // 7 days of data
        var entries: [[String: Any]] = []
        for i in 0..<7 {
            let date = Calendar.current.date(byAdding: .day, value: -i, to: Date())!
            let dateStr = ISO8601DateFormatter.string(from: date, timeZone: .current, formatOptions: [.withFullDate])
            entries.append(["date": dateStr, "tokensByModel": ["claude-opus-4-6": 1000 * (i + 1)]])
        }

        let statsJSON = try JSONSerialization.data(withJSONObject: ["dailyModelTokens": entries])
        let statsPath = tempDir.appendingPathComponent("stats-cache.json")
        try statsJSON.write(to: statsPath)

        let tracker = UsageTracker(statsCachePath: statsPath, profilesDirectory: tempDir)
        let weekly = try tracker.weeklySummary()
        XCTAssertGreaterThan(weekly, 0)
    }

    func testMissingStatsFile() {
        let tracker = UsageTracker(
            statsCachePath: tempDir.appendingPathComponent("nonexistent.json"),
            profilesDirectory: tempDir
        )
        let daily = try? tracker.parseDailyUsage()
        XCTAssertNil(daily)
    }
}
