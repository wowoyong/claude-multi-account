import Foundation

public final class TokenKeeper {

    public static let tokenURL = URL(string: "https://platform.claude.com/v1/oauth/token")!
    public static let defaultScopes = [
        "user:inference", "user:profile", "user:sessions:claude_code",
        "user:mcp_servers", "user:file_upload"
    ]

    private let backend: CredentialBackend
    private let clientIDResolver: ClientIDResolver
    private var timer: DispatchSourceTimer?

    public var onRefreshComplete: ((String, Result<Void, Error>) -> Void)?  // profileName, result

    public init(backend: CredentialBackend, clientIDResolver: ClientIDResolver = ClientIDResolver()) {
        self.backend = backend
        self.clientIDResolver = clientIDResolver
    }

    // MARK: - Timer

    public func startPeriodicRefresh(intervalHours: Double = 4) {
        let queue = DispatchQueue(label: "com.claude.tokenkeeper", qos: .utility)
        timer = DispatchSource.makeTimerSource(queue: queue)
        timer?.schedule(
            deadline: .now(),  // Run immediately on start
            repeating: intervalHours * 3600
        )
        timer?.setEventHandler { [weak self] in
            self?.checkAndRefreshAll()
        }
        timer?.resume()
    }

    public func stopPeriodicRefresh() {
        timer?.cancel()
        timer = nil
    }

    // MARK: - Refresh Logic

    public func checkAndRefreshAll() {
        let profilesDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/profiles")

        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: profilesDir.path) else { return }

        for name in contents where !name.hasPrefix(".") && name != "_previous" {
            let credPath = profilesDir.appendingPathComponent(name).appendingPathComponent(".credentials.json")
            guard let data = try? Data(contentsOf: credPath),
                  let wrapper = try? JSONDecoder().decode(CredentialWrapper.self, from: data) else { continue }

            if wrapper.claudeAiOauth.isExpiringSoon(thresholdHours: 6) {
                refreshProfile(name: name, wrapper: wrapper, credPath: credPath)
            }
        }
    }

    public func refreshProfile(name: String, wrapper: CredentialWrapper, credPath: URL) {
        var mutableWrapper = wrapper
        let clientID = clientIDResolver.resolve()
        let scopes = mutableWrapper.claudeAiOauth.scopes.isEmpty
            ? Self.defaultScopes
            : mutableWrapper.claudeAiOauth.scopes

        let body = buildRefreshBody(
            refreshToken: mutableWrapper.claudeAiOauth.refreshToken,
            clientID: clientID,
            scopes: scopes
        )

        var request = URLRequest(url: Self.tokenURL)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("claude-code/2.1.90", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 30

        let semaphore = DispatchSemaphore(value: 0)
        var refreshError: Error?

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            defer { semaphore.signal() }

            if let error = error {
                refreshError = error
                return
            }

            guard let data = data,
                  let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
                refreshError = TokenKeeperError.httpError(statusCode)
                return
            }

            do {
                let result = try self?.parseRefreshResponse(data)

                // Update credential
                mutableWrapper.claudeAiOauth.accessToken = result?.accessToken ?? mutableWrapper.claudeAiOauth.accessToken
                if let newRT = result?.refreshToken {
                    mutableWrapper.claudeAiOauth.refreshToken = newRT
                }
                if let expiresIn = result?.expiresIn {
                    mutableWrapper.claudeAiOauth.expiresAt = Int64(Date().timeIntervalSince1970 * 1000) + Int64(expiresIn) * 1000
                }

                // Save to file
                let encoded = try JSONEncoder().encode(mutableWrapper)
                try encoded.write(to: credPath)

                // Update Keychain if this is the active profile
                self?.updateKeychainIfActive(wrapper: mutableWrapper)

            } catch {
                refreshError = error
            }
        }.resume()

        semaphore.wait()

        let result: Result<Void, Error> = refreshError.map { .failure($0) } ?? .success(())
        onRefreshComplete?(name, result)
    }

    // MARK: - Request/Response

    public func buildRefreshBody(refreshToken: String, clientID: String, scopes: [String]) -> Data {
        let body: [String: String] = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": clientID,
            "scope": scopes.joined(separator: " "),
        ]
        return try! JSONSerialization.data(withJSONObject: body)
    }

    public struct RefreshResponse {
        public let accessToken: String
        public let refreshToken: String?
        public let expiresIn: Int?
    }

    public func parseRefreshResponse(_ data: Data) throws -> RefreshResponse {
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        guard let accessToken = json["access_token"] as? String else {
            throw TokenKeeperError.invalidResponse
        }
        return RefreshResponse(
            accessToken: accessToken,
            refreshToken: json["refresh_token"] as? String,
            expiresIn: json["expires_in"] as? Int
        )
    }

    // MARK: - Keychain Sync

    private func updateKeychainIfActive(wrapper: CredentialWrapper) {
        guard let active = try? backend.read() else { return }

        let activeRT = active.claudeAiOauth.refreshToken
        let profileRT = wrapper.claudeAiOauth.refreshToken
        let activeSub = active.claudeAiOauth.subscriptionType
        let profileSub = wrapper.claudeAiOauth.subscriptionType
        let activeTier = active.claudeAiOauth.rateLimitTier
        let profileTier = wrapper.claudeAiOauth.rateLimitTier

        if activeRT == profileRT || (activeSub == profileSub && activeTier == profileTier) {
            try? backend.write(wrapper)
        }
    }
}

public enum TokenKeeperError: LocalizedError {
    case httpError(Int)
    case invalidResponse

    public var errorDescription: String? {
        switch self {
        case .httpError(let code): return "Token refresh failed: HTTP \(code)"
        case .invalidResponse: return "Invalid token refresh response"
        }
    }
}
