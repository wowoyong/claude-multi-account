import Foundation

public struct ProfileMeta: Codable, Equatable {
    public var subscriptionType: String
    public var rateLimitTier: String
    public var email: String
    public var scopes: [String]
    public var savedAt: Date

    public init(subscriptionType: String, rateLimitTier: String, email: String, scopes: [String], savedAt: Date) {
        self.subscriptionType = subscriptionType
        self.rateLimitTier = rateLimitTier
        self.email = email
        self.scopes = scopes
        self.savedAt = savedAt
    }
}

public struct Profile: Identifiable, Equatable {
    public let id: String          // directory name (e.g. "max-account")
    public var meta: ProfileMeta
    public var credential: OAuthCredential?

    public var displayName: String {
        meta.email.isEmpty ? id : meta.email
    }

    public init(id: String, meta: ProfileMeta, credential: OAuthCredential? = nil) {
        self.id = id
        self.meta = meta
        self.credential = credential
    }
}

extension JSONEncoder {
    public static let profileEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
}

extension JSONDecoder {
    public static let profileDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            // Try ISO8601 with fractional seconds first, then without
            if let date = formatter.date(from: string) { return date }
            let fallbackFormatter = ISO8601DateFormatter()
            fallbackFormatter.formatOptions = [.withInternetDateTime]
            if let date = fallbackFormatter.date(from: string) { return date }
            // Try plain datetime without timezone (e.g. "2026-04-02T13:52:06.249316")
            let df = DateFormatter()
            df.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSS"
            df.locale = Locale(identifier: "en_US_POSIX")
            if let date = df.date(from: string) { return date }
            df.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
            if let date = df.date(from: string) { return date }
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "Cannot decode date: \(string)"
            )
        }
        return decoder
    }()
}
