import Foundation

public struct OAuthCredential: Codable, Equatable {
    public var accessToken: String
    public var refreshToken: String
    public var expiresAt: Int64        // milliseconds since epoch
    public var scopes: [String]
    public var subscriptionType: String?
    public var rateLimitTier: String?

    public init(accessToken: String, refreshToken: String, expiresAt: Int64, scopes: [String], subscriptionType: String?, rateLimitTier: String?) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.scopes = scopes
        self.subscriptionType = subscriptionType
        self.rateLimitTier = rateLimitTier
    }

    public var isExpired: Bool {
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        return expiresAt <= nowMs
    }

    public func isExpiringSoon(thresholdHours: Double = 6) -> Bool {
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let thresholdMs = Int64(thresholdHours * 3600 * 1000)
        return expiresAt <= nowMs + thresholdMs
    }

    public var remainingHours: Double {
        let nowMs = Double(Date().timeIntervalSince1970 * 1000)
        return (Double(expiresAt) - nowMs) / 1000 / 3600
    }
}

/// Top-level wrapper matching Keychain JSON: { "claudeAiOauth": {...}, "mcpOAuth": {...} }
public struct CredentialWrapper: Codable {
    public var claudeAiOauth: OAuthCredential
    public var mcpOAuth: RawJSON?

    public init(claudeAiOauth: OAuthCredential, mcpOAuth: RawJSON? = nil) {
        self.claudeAiOauth = claudeAiOauth
        self.mcpOAuth = mcpOAuth
    }
}

/// Opaque pass-through for mcpOAuth — preserve but don't parse deeply
public struct RawJSON: Codable, Equatable {
    public let data: Data

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        // Decode as generic JSON and re-encode to Data
        if let dict = try? container.decode([String: String].self) {
            self.data = try JSONSerialization.data(withJSONObject: dict)
        } else if let str = try? container.decode(String.self) {
            self.data = str.data(using: .utf8) ?? Data()
        } else {
            self.data = Data()
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let obj = try? JSONSerialization.jsonObject(with: data),
           let dict = obj as? [String: String] {
            try container.encode(dict)
        } else if let str = String(data: data, encoding: .utf8) {
            try container.encode(str)
        }
    }
}
