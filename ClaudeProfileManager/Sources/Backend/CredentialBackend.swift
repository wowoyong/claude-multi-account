import Foundation

public protocol CredentialBackend {
    func read() throws -> CredentialWrapper?
    func write(_ credential: CredentialWrapper) throws
    func delete() throws
}
