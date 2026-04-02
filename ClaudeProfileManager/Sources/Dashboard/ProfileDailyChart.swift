import SwiftUI

/// Simple bar chart showing daily token usage for a single profile.
struct ProfileDailyChart: View {
    let daily: [String: Int]  // date -> tokens

    private var sortedEntries: [(date: String, tokens: Int)] {
        daily.map { (date: $0.key, tokens: $0.value) }
            .sorted { $0.date < $1.date }
            .suffix(30)
            .map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Daily Usage")
                .font(.headline)

            if sortedEntries.isEmpty {
                Text("No data")
                    .foregroundColor(.secondary)
            } else {
                GeometryReader { geo in
                    let maxTokens = sortedEntries.map(\.tokens).max() ?? 1
                    let barWidth = max((geo.size.width - CGFloat(sortedEntries.count - 1) * 2) / CGFloat(sortedEntries.count), 4)

                    HStack(alignment: .bottom, spacing: 2) {
                        ForEach(sortedEntries, id: \.date) { entry in
                            let ratio = CGFloat(entry.tokens) / CGFloat(maxTokens)
                            let barHeight = max(ratio * (geo.size.height - 20), 2)

                            VStack(spacing: 2) {
                                Spacer()
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color.accentColor.opacity(0.7))
                                    .frame(width: barWidth, height: barHeight)
                                Text(shortDate(entry.date))
                                    .font(.system(size: 7))
                                    .foregroundColor(.secondary)
                                    .frame(width: barWidth)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
                .frame(height: 100)

                // Max label
                HStack {
                    Spacer()
                    Text("Max: " + formatTokens(sortedEntries.map(\.tokens).max() ?? 0))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    private func shortDate(_ date: String) -> String {
        let parts = date.split(separator: "-")
        guard parts.count == 3 else { return date }
        return "\(parts[1])/\(parts[2])"
    }

    private func formatTokens(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000 { return String(format: "%.1fK", Double(n) / 1_000) }
        return "\(n)"
    }
}
