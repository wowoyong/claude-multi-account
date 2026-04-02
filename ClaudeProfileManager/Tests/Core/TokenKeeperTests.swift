import XCTest
@testable import ClaudeProfileManagerCore

final class TokenKeeperTests: XCTestCase {

    func testBuildRefreshRequestBody() throws {
        let keeper = TokenKeeper(backend: MockCredentialBackend())
        let body = keeper.buildRefreshBody(
            refreshToken: "test-rt",
            clientID: "test-client-id",
            scopes: ["user:inference", "user:profile"]
        )

        let parsed = try JSONSerialization.jsonObject(with: body) as! [String: Any]
        XCTAssertEqual(parsed["grant_type"] as? String, "refresh_token")
        XCTAssertEqual(parsed["refresh_token"] as? String, "test-rt")
        XCTAssertEqual(parsed["client_id"] as? String, "test-client-id")
        XCTAssertEqual(parsed["scope"] as? String, "user:inference user:profile")
    }

    func testParseRefreshResponse() throws {
        let keeper = TokenKeeper(backend: MockCredentialBackend())
        let responseJSON = """
        {
            "access_token": "new-at",
            "refresh_token": "new-rt",
            "expires_in": 21600,
            "scope": "user:inference user:profile"
        }
        """.data(using: .utf8)!

        let result = try keeper.parseRefreshResponse(responseJSON)
        XCTAssertEqual(result.accessToken, "new-at")
        XCTAssertEqual(result.refreshToken, "new-rt")
        XCTAssertEqual(result.expiresIn, 21600)
    }

    func testCheckProfileNeedsRefresh() {
        let expiringSoon = OAuthCredential(
            accessToken: "t", refreshToken: "r",
            expiresAt: Int64(Date().timeIntervalSince1970 * 1000) + 2 * 3600 * 1000,
            scopes: [], subscriptionType: nil, rateLimitTier: nil
        )
        XCTAssertTrue(expiringSoon.isExpiringSoon(thresholdHours: 6))

        let fresh = OAuthCredential(
            accessToken: "t", refreshToken: "r",
            expiresAt: Int64(Date().timeIntervalSince1970 * 1000) + 20 * 3600 * 1000,
            scopes: [], subscriptionType: nil, rateLimitTier: nil
        )
        XCTAssertFalse(fresh.isExpiringSoon(thresholdHours: 6))
    }
}
