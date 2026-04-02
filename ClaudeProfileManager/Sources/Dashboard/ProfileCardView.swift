import SwiftUI

struct ProfileCardView: View {
    let profile: Profile
    let isActive: Bool
    var usage: ProfileUsage?
    let onSwitch: () -> Void
    var isSelected: Bool = false
    var onSelect: (() -> Void)? = nil
    var compact: Bool = false

    var body: some View {
        if compact {
            compactBody
        } else {
            fullBody
        }
    }

    // MARK: - Compact layout (horizontal profile selector)

    private var compactBody: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                if isActive {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 6, height: 6)
                }
                Text(profile.id)
                    .font(.subheadline.bold())
                    .lineLimit(1)
            }

            Text(profile.meta.subscriptionType.uppercased())
                .font(.caption2.bold())
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(Color.blue.opacity(0.15))
                .cornerRadius(3)

            if let usage = usage {
                let todayKey = UsageTracker.todayString()
                let todayTokens = usage.daily[todayKey] ?? 0
                Text(formatTokens(todayTokens) + " today")
                    .font(.caption2.monospacedDigit())
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(isActive ? Color.accentColor.opacity(0.05) : Color(nsColor: .controlBackgroundColor))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(
                    isSelected ? Color.orange : (isActive ? Color.accentColor : Color.gray.opacity(0.3)),
                    lineWidth: isSelected ? 2 : 1
                )
        )
        .onTapGesture { onSelect?() }
    }

    // MARK: - Full layout (original sidebar style)

    private var fullBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(profile.id)
                    .font(.headline)
                Spacer()
                if isActive {
                    Text("Active")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.green.opacity(0.2))
                        .foregroundColor(.green)
                        .cornerRadius(4)
                }
            }

            if !profile.meta.email.isEmpty {
                Text(profile.meta.email)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            HStack {
                Text(profile.meta.subscriptionType.uppercased())
                    .font(.caption.bold())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.blue.opacity(0.15))
                    .cornerRadius(4)

                Text(profile.meta.rateLimitTier)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            if let cred = profile.credential {
                HStack {
                    Circle()
                        .fill(tokenColor(cred))
                        .frame(width: 8, height: 8)
                    Text(String(format: "%.1fh remaining", cred.remainingHours))
                        .font(.caption)
                }
            }

            // Per-profile usage
            if let usage = usage {
                Divider()
                VStack(alignment: .leading, spacing: 2) {
                    let todayKey = UsageTracker.todayString()
                    let todayTokens = usage.daily[todayKey] ?? 0
                    HStack {
                        Text("Today:")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text(formatTokens(todayTokens))
                            .font(.caption2.monospacedDigit().bold())
                    }
                    HStack {
                        Text("Total:")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text(formatTokens(usage.total))
                            .font(.caption2.monospacedDigit().bold())
                    }
                }
            }

            if !isActive {
                Button("Switch") { onSwitch() }
                    .font(.caption)
            }
        }
        .padding()
        .background(isActive ? Color.accentColor.opacity(0.05) : Color.clear)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(
                    isSelected ? Color.orange : (isActive ? Color.accentColor : Color.gray.opacity(0.3)),
                    lineWidth: isSelected ? 2 : 1
                )
        )
        .onTapGesture { onSelect?() }
    }

    private func tokenColor(_ cred: OAuthCredential) -> Color {
        if cred.isExpired { return .red }
        if cred.isExpiringSoon() { return .orange }
        return .green
    }

    private func formatTokens(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000 { return String(format: "%.1fK", Double(n) / 1_000) }
        return "\(n)"
    }
}
