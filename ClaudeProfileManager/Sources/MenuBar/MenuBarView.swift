import SwiftUI

struct MenuBarView: View {
    @ObservedObject var appState: AppState
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Active profile header
            if let active = appState.activeProfile {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Active: \(active.displayName)")
                        .font(.headline)
                    HStack(spacing: 4) {
                        Text(active.meta.subscriptionType)
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.2))
                            .cornerRadius(4)
                        if let cred = active.credential {
                            Text(tokenStatusText(cred))
                                .font(.caption)
                                .foregroundColor(tokenStatusColor(cred))
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

                Divider()
            }

            // Profile list
            ForEach(appState.profiles) { profile in
                Button(action: {
                    if profile.id != appState.activeProfile?.id {
                        appState.switchProfile(to: profile.id)
                    }
                }) {
                    HStack {
                        Image(systemName: profile.id == appState.activeProfile?.id
                              ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(profile.id == appState.activeProfile?.id ? .green : .secondary)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(profile.id)
                                .font(.body)
                            HStack(spacing: 4) {
                                Text(profile.meta.subscriptionType)
                                    .font(.caption2)
                                if let cred = profile.credential {
                                    Text(tokenStatusText(cred))
                                        .font(.caption2)
                                        .foregroundColor(tokenStatusColor(cred))
                                }
                            }
                        }

                        Spacer()
                    }
                    .contentShape(Rectangle())
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
            }

            Divider()

            // Actions
            Button(action: { appState.balanceNow() }) {
                Label("Balance Now", systemImage: "arrow.triangle.2.circlepath")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .buttonStyle(.plain)

            Button(action: {
                NSApplication.shared.setActivationPolicy(.regular)
                openWindow(id: "dashboard")
                NSApplication.shared.activate(ignoringOtherApps: true)
                // Revert to accessory after a delay so dock icon goes away
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    NSApplication.shared.setActivationPolicy(.accessory)
                }
            }) {
                Label("Open Dashboard", systemImage: "chart.bar")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .buttonStyle(.plain)

            Divider()

            Button(action: {
                NSApplication.shared.terminate(nil)
            }) {
                Text("Quit")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .buttonStyle(.plain)
        }
        .frame(width: 280)
        .padding(.vertical, 4)
    }

    private func tokenStatusText(_ cred: OAuthCredential) -> String {
        let hours = cred.remainingHours
        if hours <= 0 { return "Expired" }
        return String(format: "%.1fh", hours)
    }

    private func tokenStatusColor(_ cred: OAuthCredential) -> Color {
        let hours = cred.remainingHours
        if hours <= 0 { return .red }
        if hours <= 6 { return .orange }
        return .green
    }
}
