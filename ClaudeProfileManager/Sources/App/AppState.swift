import SwiftUI
import Combine

@MainActor
final class AppState: ObservableObject {
    @Published var profiles: [Profile] = []
    @Published var activeProfile: Profile?
    @Published var isLoading = true
    @Published var error: String?
    @Published var lastRefreshTime: Date?
    @Published var showOnboarding = false

    let profileManager: ProfileManager
    let tokenKeeper: TokenKeeper
    let usageTracker: UsageTracker
    let sessionGuard: SessionGuard

    private let backend: CredentialBackend

    init(backend: CredentialBackend? = nil) {
        let b = backend ?? KeychainBackend()
        self.backend = b
        self.profileManager = ProfileManager(backend: b)
        self.tokenKeeper = TokenKeeper(backend: b)
        self.usageTracker = UsageTracker()
        self.sessionGuard = SessionGuard()
    }

    func loadProfiles() {
        Task {
            do {
                let loaded = try profileManager.listProfiles()
                profiles = loaded

                if profiles.isEmpty {
                    // Check if Keychain has credentials but no profiles saved
                    if (try? backend.read()) != nil {
                        showOnboarding = true
                    }
                }

                activeProfile = try profileManager.identifyActiveProfile()

                // Record usage for active profile
                usageTracker.recordAllProfileUsages(
                    activeProfileName: activeProfile?.id,
                    allProfileNames: loaded.map { $0.id }
                )

                isLoading = false
            } catch {
                self.error = error.localizedDescription
                isLoading = false
            }
        }
    }

    func switchProfile(to profileId: String) {
        Task {
            do {
                // Snapshot current profile's usage before switching
                if let current = activeProfile {
                    usageTracker.recordUsage(forProfile: current.id)
                }

                try profileManager.switchTo(profileId: profileId)
                activeProfile = profiles.first(where: { $0.id == profileId })
                loadProfiles()  // Refresh
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    func balanceNow() {
        // Pick profile with lowest usage today
        guard profiles.count >= 2 else { return }

        // Pick the first non-active profile with valid token
        let candidates = profiles.filter {
            $0.id != activeProfile?.id && $0.credential?.isExpired != true
        }
        guard let best = candidates.first else { return }
        switchProfile(to: best.id)
    }

    func startTokenKeeper() {
        tokenKeeper.onRefreshComplete = { [weak self] name, result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    self?.lastRefreshTime = Date()
                    self?.loadProfiles()
                case .failure(let error):
                    self?.error = "Token refresh failed for \(name): \(error.localizedDescription)"
                }
            }
        }
        tokenKeeper.startPeriodicRefresh()
    }
}
