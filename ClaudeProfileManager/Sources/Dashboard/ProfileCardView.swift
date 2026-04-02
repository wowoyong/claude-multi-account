import SwiftUI

struct ProfileCardView: View {
    let profile: Profile
    let isActive: Bool
    let onSwitch: () -> Void

    var body: some View {
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
                .stroke(isActive ? Color.accentColor : Color.gray.opacity(0.3), lineWidth: 1)
        )
    }

    private func tokenColor(_ cred: OAuthCredential) -> Color {
        if cred.isExpired { return .red }
        if cred.isExpiringSoon() { return .orange }
        return .green
    }
}
