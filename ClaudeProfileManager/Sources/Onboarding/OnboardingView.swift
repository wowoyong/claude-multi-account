import SwiftUI

struct OnboardingView: View {
    @ObservedObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var keychainStatus: KeychainCheckStatus = .checking
    @State private var profileName = ""

    enum KeychainCheckStatus {
        case checking, success, failed
    }

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "person.2.circle.fill")
                .font(.system(size: 60))
                .foregroundColor(.accentColor)

            Text("Welcome to Claude Profile Manager")
                .font(.title2.bold())

            Text("Manage multiple Claude Code accounts from your menu bar.")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Divider()

            // Keychain status
            HStack {
                switch keychainStatus {
                case .checking:
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Checking Keychain access...")
                case .success:
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Keychain access granted")
                case .failed:
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.red)
                    VStack(alignment: .leading) {
                        Text("Keychain access denied")
                        Text("When prompted by macOS, click 'Always Allow'")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            if keychainStatus == .success {
                if appState.profiles.isEmpty {
                    VStack(spacing: 12) {
                        Text("Save your current account as the first profile:")
                            .font(.callout)

                        TextField("Profile name (e.g. personal)", text: $profileName)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 250)

                        Button("Save Profile") {
                            saveFirstProfile()
                        }
                        .disabled(profileName.isEmpty)
                        .buttonStyle(.borderedProminent)
                    }
                } else {
                    VStack(spacing: 8) {
                        Text("Found \(appState.profiles.count) existing profile(s):")
                            .font(.callout)
                        ForEach(appState.profiles) { p in
                            Text("  \(p.id) — \(p.meta.email)")
                                .font(.caption.monospaced())
                        }
                    }

                    Button("Get Started") {
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            if keychainStatus == .failed {
                Button("Retry") {
                    checkKeychain()
                }
            }
        }
        .padding(40)
        .frame(width: 450)
        .onAppear { checkKeychain() }
    }

    private func checkKeychain() {
        keychainStatus = .checking
        let backend = KeychainBackend()
        do {
            _ = try backend.read()
            keychainStatus = .success
            appState.loadProfiles()
        } catch {
            keychainStatus = .failed
        }
    }

    private func saveFirstProfile() {
        Task {
            do {
                // Get email from claude auth status
                let email = getEmailFromCLI() ?? ""
                try appState.profileManager.saveCurrent(as: profileName, email: email)
                appState.loadProfiles()
                dismiss()
            } catch {
                appState.error = error.localizedDescription
            }
        }
    }

    private func getEmailFromCLI() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["claude", "auth", "status", "--json"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            return json?["email"] as? String
        } catch {
            return nil
        }
    }
}
