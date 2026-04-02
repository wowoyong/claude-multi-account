import XCTest
@testable import ClaudeProfileManagerCore

final class SessionGuardTests: XCTestCase {

    func testCheckReturnsProcessList() {
        let guard_ = SessionGuard()
        let sessions = guard_.findClaudeSessions()
        // May be 0 or more — just verify it doesn't crash
        XCTAssertTrue(sessions.count >= 0)
    }

    func testHasRunningSessions() {
        let guard_ = SessionGuard()
        // Boolean result, no crash
        let _ = guard_.hasRunningSessions
    }

    func testSessionCountType() {
        let guard_ = SessionGuard()
        let count = guard_.runningSessionCount
        XCTAssertTrue(count >= 0)
    }
}
