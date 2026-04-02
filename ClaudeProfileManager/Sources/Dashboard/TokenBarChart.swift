import SwiftUI

/// Generic horizontal-label bar chart for token usage.
struct TokenBarChart: View {
    let title: String
    let entries: [(label: String, tokens: Int)]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)

            if entries.isEmpty {
                Text("No data")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 60)
            } else {
                let maxTokens = entries.map(\.tokens).max() ?? 1

                GeometryReader { geo in
                    let barH: CGFloat = 16
                    let rowH: CGFloat = 22
                    let labelW: CGFloat = 44
                    let valueW: CGFloat = 52
                    let barAreaW = geo.size.width - labelW - valueW - 12

                    VStack(spacing: 4) {
                        ForEach(entries, id: \.label) { entry in
                            HStack(spacing: 4) {
                                Text(entry.label)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .frame(width: labelW, alignment: .trailing)

                                let ratio = CGFloat(entry.tokens) / CGFloat(maxTokens)
                                let barW = max(ratio * barAreaW, entry.tokens > 0 ? 2 : 0)

                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(Color.secondary.opacity(0.08))
                                        .frame(width: barAreaW, height: barH)
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(Color.accentColor.opacity(0.75))
                                        .frame(width: barW, height: barH)
                                }

                                Text(formatTokens(entry.tokens))
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .frame(width: valueW, alignment: .leading)
                            }
                            .frame(height: rowH)
                        }
                    }
                }
                .frame(height: CGFloat(entries.count) * 26 + 4)
            }
        }
    }

    private func formatTokens(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000 { return String(format: "%.0fK", Double(n) / 1_000) }
        return "\(n)"
    }
}
