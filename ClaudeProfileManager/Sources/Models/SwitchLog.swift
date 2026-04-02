import Foundation

public struct SwitchLogEntry: Codable, Equatable {
    public let timestamp: Date
    public let fromProfile: String?
    public let toProfile: String

    public init(timestamp: Date, fromProfile: String?, toProfile: String) {
        self.timestamp = timestamp
        self.fromProfile = fromProfile
        self.toProfile = toProfile
    }
}
