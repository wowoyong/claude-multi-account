import SwiftUI
import Charts

struct UsageChartView: View {
    let dailyUsage: [DailyModelTokens]

    var body: some View {
        VStack(alignment: .leading) {
            Text("Daily Usage (Estimated)")
                .font(.headline)

            if dailyUsage.isEmpty {
                Text("No usage data yet")
                    .foregroundColor(.secondary)
                    .frame(height: 200)
            } else {
                Chart {
                    ForEach(chartData, id: \.id) { entry in
                        BarMark(
                            x: .value("Date", entry.date),
                            y: .value("Tokens", entry.tokens)
                        )
                        .foregroundStyle(by: .value("Model", entry.model))
                    }
                }
                .chartForegroundStyleScale([
                    "Opus": Color.purple,
                    "Sonnet": Color.blue,
                    "Haiku": Color.gray,
                    "Other": Color.secondary,
                ])
                .frame(height: 200)
            }
        }
    }

    private var chartData: [ChartEntry] {
        // Last 30 days
        let recent = dailyUsage.suffix(30)
        return recent.flatMap { day in
            day.tokensByModel.map { model, tokens in
                ChartEntry(
                    date: Self.shortDate(day.date),
                    model: modelShortName(model),
                    tokens: tokens
                )
            }
        }
    }

    /// "2026-01-15" → "1/15"
    private static func shortDate(_ dateStr: String) -> String {
        let parts = dateStr.split(separator: "-")
        guard parts.count == 3,
              let month = Int(parts[1]),
              let day = Int(parts[2]) else { return dateStr }
        return "\(month)/\(day)"
    }

    private func modelShortName(_ model: String) -> String {
        if model.contains("opus") { return "Opus" }
        if model.contains("sonnet") { return "Sonnet" }
        if model.contains("haiku") { return "Haiku" }
        return "Other"
    }
}

private struct ChartEntry: Identifiable {
    let id = UUID()
    let date: String
    let model: String
    let tokens: Int
}
