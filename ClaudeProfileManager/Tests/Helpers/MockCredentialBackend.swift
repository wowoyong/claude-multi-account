import Foundation
@testable import ClaudeProfileManagerCore

final class MockCredentialBackend: CredentialBackend {
    var stored: CredentialWrapper?
    var readCallCount = 0
    var writeCallCount = 0
    var shouldThrowOnRead = false
    var shouldThrowOnWrite = false

    func read() throws -> CredentialWrapper? {
        readCallCount += 1
        if shouldThrowOnRead { throw NSError(domain: "Mock", code: -1) }
        return stored
    }

    func write(_ credential: CredentialWrapper) throws {
        writeCallCount += 1
        if shouldThrowOnWrite { throw NSError(domain: "Mock", code: -1) }
        stored = credential
    }

    func delete() throws {
        stored = nil
    }
}
