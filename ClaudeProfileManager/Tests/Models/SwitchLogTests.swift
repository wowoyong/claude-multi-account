import XCTest
@testable import ClaudeProfileManagerCore

final class SwitchLogTests: XCTestCase {

    func testEncodeDecodeSwitchLog() throws {
        let entry = SwitchLogEntry(
            timestamp: Date(timeIntervalSince1970: 1712000000),
            fromProfile: "pro-account",
            toProfile: "max-account"
        )
        let data = try JSONEncoder().encode([entry])
        let decoded = try JSONDecoder().decode([SwitchLogEntry].self, from: data)
        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(decoded[0].fromProfile, "pro-account")
        XCTAssertEqual(decoded[0].toProfile, "max-account")
    }

    func testSwitchLogWithNilFrom() throws {
        let entry = SwitchLogEntry(
            timestamp: Date(), fromProfile: nil, toProfile: "first-account"
        )
        let data = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(SwitchLogEntry.self, from: data)
        XCTAssertNil(decoded.fromProfile)
        XCTAssertEqual(decoded.toProfile, "first-account")
    }

    func testEmptyLog() throws {
        let data = "[]".data(using: .utf8)!
        let log = try JSONDecoder().decode([SwitchLogEntry].self, from: data)
        XCTAssertTrue(log.isEmpty)
    }
}
