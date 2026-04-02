import XCTest
@testable import ClaudeProfileManagerCore

final class ClientIDResolverTests: XCTestCase {

    func testFallbackClientID() {
        let resolver = ClientIDResolver()
        let clientID = resolver.resolve()
        // Should always return something (at minimum the fallback)
        XCTAssertFalse(clientID.isEmpty)
    }

    func testFallbackIsValidUUID() {
        let fallback = ClientIDResolver.fallbackClientID
        XCTAssertNotNil(UUID(uuidString: fallback))
    }

    func testExtractFromInvalidPath() {
        let resolver = ClientIDResolver()
        let result = resolver.extractFromCLI(at: "/nonexistent/path")
        XCTAssertNil(result)
    }
}
