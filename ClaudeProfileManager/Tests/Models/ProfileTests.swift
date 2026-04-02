import XCTest
@testable import ClaudeProfileManagerCore

final class ProfileTests: XCTestCase {

    func testDecodeMetaJSON() throws {
        let json = """
        {
            "subscriptionType": "max",
            "rateLimitTier": "default_claude_max_20x",
            "email": "user@example.com",
            "scopes": ["user:inference", "user:profile"],
            "savedAt": "2026-04-02T13:52:06.249316"
        }
        """.data(using: .utf8)!

        let profile = try JSONDecoder.profileDecoder.decode(ProfileMeta.self, from: json)
        XCTAssertEqual(profile.email, "user@example.com")
        XCTAssertEqual(profile.subscriptionType, "max")
        XCTAssertEqual(profile.rateLimitTier, "default_claude_max_20x")
        XCTAssertEqual(profile.scopes.count, 2)
    }

    func testProfileIdentity() {
        let a = Profile(id: "account-a", meta: ProfileMeta(
            subscriptionType: "max", rateLimitTier: "20x",
            email: "a@test.com", scopes: [], savedAt: Date()
        ))
        let b = Profile(id: "account-b", meta: ProfileMeta(
            subscriptionType: "max", rateLimitTier: "20x",
            email: "b@test.com", scopes: [], savedAt: Date()
        ))
        XCTAssertNotEqual(a.id, b.id)
        XCTAssertNotEqual(a.meta.email, b.meta.email)
    }

    func testProfileWithEmptyEmail() {
        let profile = Profile(id: "test", meta: ProfileMeta(
            subscriptionType: "pro", rateLimitTier: "default",
            email: "", scopes: [], savedAt: Date()
        ))
        XCTAssertTrue(profile.meta.email.isEmpty)
    }
}
