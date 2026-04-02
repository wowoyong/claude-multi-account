import XCTest
@testable import ClaudeProfileManagerCore

final class OAuthCredentialTests: XCTestCase {

    func testDecodeKeychainJSON() throws {
        let json = """
        {
            "claudeAiOauth": {
                "accessToken": "sk-ant-oat01-test",
                "refreshToken": "sk-ant-ort01-test",
                "expiresAt": 1775127167770,
                "scopes": ["user:inference", "user:profile", "user:sessions:claude_code"],
                "subscriptionType": "max",
                "rateLimitTier": "default_claude_max_20x"
            }
        }
        """.data(using: .utf8)!

        let wrapper = try JSONDecoder().decode(CredentialWrapper.self, from: json)
        let oauth = wrapper.claudeAiOauth
        XCTAssertEqual(oauth.accessToken, "sk-ant-oat01-test")
        XCTAssertEqual(oauth.refreshToken, "sk-ant-ort01-test")
        XCTAssertEqual(oauth.expiresAt, 1775127167770)
        XCTAssertEqual(oauth.subscriptionType, "max")
        XCTAssertEqual(oauth.scopes.count, 3)
    }

    func testTokenExpiry() {
        let expired = OAuthCredential(
            accessToken: "t", refreshToken: "r",
            expiresAt: 0, scopes: [],
            subscriptionType: "max", rateLimitTier: "20x"
        )
        XCTAssertTrue(expired.isExpired)
        XCTAssertTrue(expired.isExpiringSoon(thresholdHours: 6))

        let future = OAuthCredential(
            accessToken: "t", refreshToken: "r",
            expiresAt: Int64(Date().timeIntervalSince1970 * 1000) + 24 * 3600 * 1000,
            scopes: [], subscriptionType: "pro", rateLimitTier: "default"
        )
        XCTAssertFalse(future.isExpired)
        XCTAssertFalse(future.isExpiringSoon(thresholdHours: 6))
    }

    func testRemainingHours() {
        let sixHoursFromNow = Int64(Date().timeIntervalSince1970 * 1000) + 6 * 3600 * 1000
        let cred = OAuthCredential(
            accessToken: "t", refreshToken: "r",
            expiresAt: sixHoursFromNow, scopes: [],
            subscriptionType: nil, rateLimitTier: nil
        )
        let remaining = cred.remainingHours
        XCTAssertGreaterThan(remaining, 5.9)
        XCTAssertLessThan(remaining, 6.1)
    }
}
