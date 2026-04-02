import Foundation

public final class ProfileManager {

    public let profilesDirectory: URL
    private let backend: CredentialBackend

    public init(profilesDirectory: URL? = nil, backend: CredentialBackend? = nil) {
        self.profilesDirectory = profilesDirectory ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/profiles")
        self.backend = backend ?? KeychainBackend()
    }

    // MARK: - List

    public func listProfiles() throws -> [Profile] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: profilesDirectory.path) else { return [] }

        let contents = try fm.contentsOfDirectory(atPath: profilesDirectory.path)
        return contents.compactMap { name -> Profile? in
            guard !name.hasPrefix("."), name != "_previous" else { return nil }
            let dir = profilesDirectory.appendingPathComponent(name)
            let credPath = dir.appendingPathComponent(".credentials.json")
            let metaPath = dir.appendingPathComponent("meta.json")

            guard fm.fileExists(atPath: credPath.path),
                  fm.fileExists(atPath: metaPath.path) else { return nil }

            do {
                let metaData = try Data(contentsOf: metaPath)
                let meta = try JSONDecoder.profileDecoder.decode(ProfileMeta.self, from: metaData)
                let credData = try Data(contentsOf: credPath)
                let cred = try JSONDecoder().decode(CredentialWrapper.self, from: credData)
                return Profile(id: name, meta: meta, credential: cred.claudeAiOauth)
            } catch {
                return nil
            }
        }.sorted { $0.id < $1.id }
    }

    // MARK: - Identify Active (3-stage chain)

    public func identifyActiveProfile(activeEmail: String? = nil) throws -> Profile? {
        guard let active = try backend.read() else { return nil }
        let profiles = try listProfiles()

        // Stage 1: refreshToken match
        if let match = profiles.first(where: {
            $0.credential?.refreshToken == active.claudeAiOauth.refreshToken
        }) { return match }

        // Stage 2: email match
        if let email = activeEmail, !email.isEmpty,
           let match = profiles.first(where: { $0.meta.email == email }) {
            return match
        }

        // Stage 3: subscriptionType + rateLimitTier fallback
        let activeSub = active.claudeAiOauth.subscriptionType
        let activeTier = active.claudeAiOauth.rateLimitTier
        let fallbackMatches = profiles.filter {
            $0.credential?.subscriptionType == activeSub &&
            $0.credential?.rateLimitTier == activeTier
        }
        // Only use fallback if exactly 1 match (avoid ambiguity)
        if fallbackMatches.count == 1 { return fallbackMatches[0] }

        return nil
    }

    // MARK: - Switch

    public func switchTo(profileId: String) throws {
        let profileDir = profilesDirectory.appendingPathComponent(profileId)
        let credPath = profileDir.appendingPathComponent(".credentials.json")

        guard FileManager.default.fileExists(atPath: credPath.path) else {
            throw ProfileError.profileNotFound(profileId)
        }

        // Backup current to _previous
        if let current = try backend.read() {
            let backupDir = profilesDirectory.appendingPathComponent("_previous")
            try FileManager.default.createDirectory(at: backupDir, withIntermediateDirectories: true)
            let backupData = try JSONEncoder().encode(current)
            try backupData.write(to: backupDir.appendingPathComponent(".credentials.json"))
        }

        // Load target and write to Keychain
        let data = try Data(contentsOf: credPath)
        let wrapper = try JSONDecoder().decode(CredentialWrapper.self, from: data)
        try backend.write(wrapper)

        // Log switch
        appendSwitchLog(toProfile: profileId)
    }

    // MARK: - Save Current

    public func saveCurrent(as name: String, email: String) throws {
        guard let current = try backend.read() else {
            throw ProfileError.noActiveCredential
        }

        let profileDir = profilesDirectory.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: profileDir, withIntermediateDirectories: true)

        // Save credentials
        let credData = try JSONEncoder().encode(current)
        let credPath = profileDir.appendingPathComponent(".credentials.json")
        try credData.write(to: credPath)

        // Set file permissions to 600
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600], ofItemAtPath: credPath.path
        )

        // Save meta
        let meta = ProfileMeta(
            subscriptionType: current.claudeAiOauth.subscriptionType ?? "unknown",
            rateLimitTier: current.claudeAiOauth.rateLimitTier ?? "unknown",
            email: email,
            scopes: current.claudeAiOauth.scopes,
            savedAt: Date()
        )
        let metaData = try JSONEncoder.profileEncoder.encode(meta)
        try metaData.write(to: profileDir.appendingPathComponent("meta.json"))
    }

    // MARK: - Delete

    public func deleteProfile(id: String) throws {
        guard id != "_previous" else {
            throw ProfileError.cannotDeleteBackup
        }
        let dir = profilesDirectory.appendingPathComponent(id)
        try FileManager.default.removeItem(at: dir)
    }

    // MARK: - Switch Log

    private func appendSwitchLog(toProfile: String) {
        let logPath = profilesDirectory.appendingPathComponent("switch_log.json")
        var entries: [SwitchLogEntry] = []

        if let data = try? Data(contentsOf: logPath),
           let existing = try? JSONDecoder().decode([SwitchLogEntry].self, from: data) {
            entries = existing
        }

        entries.append(SwitchLogEntry(
            timestamp: Date(), fromProfile: nil, toProfile: toProfile
        ))

        // Keep last 1000 entries
        if entries.count > 1000 { entries = Array(entries.suffix(1000)) }

        if let data = try? JSONEncoder().encode(entries) {
            try? data.write(to: logPath)
        }
    }
}

public enum ProfileError: LocalizedError {
    case profileNotFound(String)
    case noActiveCredential
    case cannotDeleteBackup

    public var errorDescription: String? {
        switch self {
        case .profileNotFound(let id): return "Profile '\(id)' not found"
        case .noActiveCredential: return "No active credential in Keychain"
        case .cannotDeleteBackup: return "'_previous' is an auto-backup and cannot be deleted"
        }
    }
}
