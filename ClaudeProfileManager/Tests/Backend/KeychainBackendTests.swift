import XCTest
@testable import ClaudeProfileManagerCore

final class KeychainBackendTests: XCTestCase {

    // Use a test-specific service name to avoid touching real Keychain
    let testService = "ClaudeProfileManager-Test-\(UUID().uuidString)"
    var backend: KeychainBackend!

    override func setUp() {
        backend = KeychainBackend(serviceName: testService)
    }

    override func tearDown() {
        try? backend.delete()
    }

    func testReadNonexistent() throws {
        let result = try backend.read()
        XCTAssertNil(result)
    }

    func testWriteAndRead() throws {
        let oauth = OAuthCredential(
            accessToken: "test-at", refreshToken: "test-rt",
            expiresAt: 9999999999999, scopes: ["user:inference"],
            subscriptionType: "max", rateLimitTier: "20x"
        )
        let wrapper = CredentialWrapper(claudeAiOauth: oauth, mcpOAuth: nil)

        try backend.write(wrapper)
        let read = try backend.read()

        XCTAssertNotNil(read)
        XCTAssertEqual(read?.claudeAiOauth.accessToken, "test-at")
        XCTAssertEqual(read?.claudeAiOauth.refreshToken, "test-rt")
        XCTAssertEqual(read?.claudeAiOauth.subscriptionType, "max")
    }

    func testOverwrite() throws {
        let oauth1 = OAuthCredential(
            accessToken: "old", refreshToken: "old-rt",
            expiresAt: 1, scopes: [], subscriptionType: nil, rateLimitTier: nil
        )
        try backend.write(CredentialWrapper(claudeAiOauth: oauth1, mcpOAuth: nil))

        let oauth2 = OAuthCredential(
            accessToken: "new", refreshToken: "new-rt",
            expiresAt: 2, scopes: [], subscriptionType: nil, rateLimitTier: nil
        )
        try backend.write(CredentialWrapper(claudeAiOauth: oauth2, mcpOAuth: nil))

        let read = try backend.read()
        XCTAssertEqual(read?.claudeAiOauth.accessToken, "new")
    }

    func testDelete() throws {
        let oauth = OAuthCredential(
            accessToken: "t", refreshToken: "r",
            expiresAt: 1, scopes: [], subscriptionType: nil, rateLimitTier: nil
        )
        try backend.write(CredentialWrapper(claudeAiOauth: oauth, mcpOAuth: nil))
        try backend.delete()
        XCTAssertNil(try backend.read())
    }
}
