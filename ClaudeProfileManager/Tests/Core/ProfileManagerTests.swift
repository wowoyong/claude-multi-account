import XCTest
@testable import ClaudeProfileManagerCore

final class ProfileManagerTests: XCTestCase {

    var tempDir: URL!
    var profilesDir: URL!
    var mockBackend: MockCredentialBackend!
    var manager: ProfileManager!

    override func setUp() {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cpm-test-\(UUID().uuidString)")
        profilesDir = tempDir.appendingPathComponent("profiles")
        try! FileManager.default.createDirectory(at: profilesDir, withIntermediateDirectories: true)

        mockBackend = MockCredentialBackend()
        manager = ProfileManager(profilesDirectory: profilesDir, backend: mockBackend)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testListProfilesEmpty() throws {
        let profiles = try manager.listProfiles()
        XCTAssertTrue(profiles.isEmpty)
    }

    func testSaveAndListProfile() throws {
        // Create a profile directory with credentials + meta
        let profileDir = profilesDir.appendingPathComponent("test-account")
        try FileManager.default.createDirectory(at: profileDir, withIntermediateDirectories: true)

        let oauth = OAuthCredential(
            accessToken: "at", refreshToken: "rt", expiresAt: 9999999999999,
            scopes: ["user:inference"], subscriptionType: "max", rateLimitTier: "20x"
        )
        let wrapper = CredentialWrapper(claudeAiOauth: oauth, mcpOAuth: nil)
        try JSONEncoder().encode(wrapper).write(to: profileDir.appendingPathComponent(".credentials.json"))

        let meta = ProfileMeta(
            subscriptionType: "max", rateLimitTier: "20x",
            email: "test@example.com", scopes: ["user:inference"], savedAt: Date()
        )
        try JSONEncoder().encode(meta).write(to: profileDir.appendingPathComponent("meta.json"))

        let profiles = try manager.listProfiles()
        XCTAssertEqual(profiles.count, 1)
        XCTAssertEqual(profiles[0].id, "test-account")
        XCTAssertEqual(profiles[0].meta.email, "test@example.com")
    }

    func testIdentifyByRefreshToken() throws {
        // Setup profile
        let profileDir = profilesDir.appendingPathComponent("my-account")
        try FileManager.default.createDirectory(at: profileDir, withIntermediateDirectories: true)

        let oauth = OAuthCredential(
            accessToken: "at", refreshToken: "unique-rt-123", expiresAt: 9999999999999,
            scopes: [], subscriptionType: "max", rateLimitTier: "20x"
        )
        try JSONEncoder().encode(CredentialWrapper(claudeAiOauth: oauth, mcpOAuth: nil))
            .write(to: profileDir.appendingPathComponent(".credentials.json"))
        try JSONEncoder().encode(ProfileMeta(
            subscriptionType: "max", rateLimitTier: "20x",
            email: "me@test.com", scopes: [], savedAt: Date()
        )).write(to: profileDir.appendingPathComponent("meta.json"))

        // Set active credential to same refreshToken
        mockBackend.stored = CredentialWrapper(claudeAiOauth: oauth, mcpOAuth: nil)

        let identified = try manager.identifyActiveProfile()
        XCTAssertEqual(identified?.id, "my-account")
    }

    func testIdentifyByEmail() throws {
        let profileDir = profilesDir.appendingPathComponent("email-account")
        try FileManager.default.createDirectory(at: profileDir, withIntermediateDirectories: true)

        let savedOAuth = OAuthCredential(
            accessToken: "at", refreshToken: "old-rt", expiresAt: 9999999999999,
            scopes: [], subscriptionType: "pro", rateLimitTier: "default"
        )
        try JSONEncoder().encode(CredentialWrapper(claudeAiOauth: savedOAuth, mcpOAuth: nil))
            .write(to: profileDir.appendingPathComponent(".credentials.json"))
        try JSONEncoder().encode(ProfileMeta(
            subscriptionType: "pro", rateLimitTier: "default",
            email: "unique@test.com", scopes: [], savedAt: Date()
        )).write(to: profileDir.appendingPathComponent("meta.json"))

        // Active has different refreshToken but we know the email
        let activeOAuth = OAuthCredential(
            accessToken: "new-at", refreshToken: "new-rt-rotated", expiresAt: 9999999999999,
            scopes: [], subscriptionType: "pro", rateLimitTier: "default"
        )
        mockBackend.stored = CredentialWrapper(claudeAiOauth: activeOAuth, mcpOAuth: nil)

        let identified = try manager.identifyActiveProfile(activeEmail: "unique@test.com")
        XCTAssertEqual(identified?.id, "email-account")
    }

    func testSwitchProfile() throws {
        let profileDir = profilesDir.appendingPathComponent("target")
        try FileManager.default.createDirectory(at: profileDir, withIntermediateDirectories: true)

        let oauth = OAuthCredential(
            accessToken: "target-at", refreshToken: "target-rt", expiresAt: 9999999999999,
            scopes: [], subscriptionType: "max", rateLimitTier: "20x"
        )
        try JSONEncoder().encode(CredentialWrapper(claudeAiOauth: oauth, mcpOAuth: nil))
            .write(to: profileDir.appendingPathComponent(".credentials.json"))
        try JSONEncoder().encode(ProfileMeta(
            subscriptionType: "max", rateLimitTier: "20x",
            email: "t@test.com", scopes: [], savedAt: Date()
        )).write(to: profileDir.appendingPathComponent("meta.json"))

        // Set current active
        let currentOAuth = OAuthCredential(
            accessToken: "old", refreshToken: "old-rt", expiresAt: 1,
            scopes: [], subscriptionType: nil, rateLimitTier: nil
        )
        mockBackend.stored = CredentialWrapper(claudeAiOauth: currentOAuth, mcpOAuth: nil)

        try manager.switchTo(profileId: "target")

        // Verify new credential was written to backend
        XCTAssertEqual(mockBackend.stored?.claudeAiOauth.accessToken, "target-at")
        XCTAssertEqual(mockBackend.writeCallCount, 1)

        // Verify _previous backup was created
        let backupPath = profilesDir.appendingPathComponent("_previous/.credentials.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: backupPath.path))
    }

    func testDeleteProfile() throws {
        let profileDir = profilesDir.appendingPathComponent("to-delete")
        try FileManager.default.createDirectory(at: profileDir, withIntermediateDirectories: true)
        try "{}".data(using: .utf8)!.write(to: profileDir.appendingPathComponent(".credentials.json"))

        try manager.deleteProfile(id: "to-delete")
        XCTAssertFalse(FileManager.default.fileExists(atPath: profileDir.path))
    }

    func testCannotDeletePrevious() {
        XCTAssertThrowsError(try manager.deleteProfile(id: "_previous"))
    }
}
