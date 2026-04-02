import SwiftUI

struct ModelBreakdownView: View {
    let breakdown: [String: Int]

    var body: some View {
        VStack(alignment: .leading) {
            Text("Model Breakdown")
                .font(.headline)

            if breakdown.isEmpty {
                Text("No data")
                    .foregroundColor(.secondary)
            } else {
                // Horizontal segmented bar using GeometryReader
                GeometryReader { geo in
                    HStack(spacing: 2) {
                        ForEach(pieData, id: \.model) { entry in
                            Rectangle()
                                .fill(modelColor(entry.model))
                                .frame(width: max(geo.size.width * CGFloat(entry.percentage) / 100, 2))
                        }
                    }
                }
                .frame(height: 24)
                .cornerRadius(12)

                // Legend with percentages
                ForEach(pieData, id: \.model) { entry in
                    HStack {
                        Circle().fill(modelColor(entry.model)).frame(width: 8, height: 8)
                        Text(entry.model)
                            .font(.caption)
                        Spacer()
                        Text("\(entry.percentage)%")
                            .font(.caption.monospacedDigit())
                        Text("(\(formatTokens(entry.tokens)))")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    private var pieData: [PieEntry] {
        let total = breakdown.values.reduce(0, +)
        guard total > 0 else { return [] }
        return breakdown.map { model, tokens in
            let shortName: String
            if model.contains("opus") { shortName = "Opus" }
            else if model.contains("sonnet") { shortName = "Sonnet" }
            else if model.contains("haiku") { shortName = "Haiku" }
            else { shortName = "Other" }
            return PieEntry(model: shortName, tokens: tokens, percentage: tokens * 100 / total)
        }.sorted { $0.tokens > $1.tokens }
    }

    private func modelColor(_ model: String) -> Color {
        switch model {
        case "Opus": return .purple
        case "Sonnet": return .blue
        case "Haiku": return .gray
        default: return .secondary
        }
    }

    private func formatTokens(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000 { return String(format: "%.1fK", Double(n) / 1_000) }
        return "\(n)"
    }
}

private struct PieEntry {
    let model: String
    let tokens: Int
    let percentage: Int
}
