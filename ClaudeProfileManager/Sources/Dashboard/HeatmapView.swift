import SwiftUI

struct HeatmapView: View {
    let dailyUsage: [DailyModelTokens]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Usage Heatmap")
                .font(.headline)

            if dailyUsage.isEmpty {
                Text("No usage data")
                    .foregroundColor(.secondary)
                    .frame(height: 100)
            } else {
                let grid = buildHeatmapGrid()
                let maxTokens = dailyUsage.map(\.totalTokens).max() ?? 1

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 3) {
                        // Day-of-week labels
                        VStack(spacing: 3) {
                            ForEach(dayLabels, id: \.self) { label in
                                Text(label)
                                    .font(.system(size: 9))
                                    .foregroundColor(.secondary)
                                    .frame(width: 24, height: 12)
                            }
                        }

                        // Week columns
                        ForEach(Array(grid.enumerated()), id: \.offset) { _, week in
                            VStack(spacing: 3) {
                                ForEach(Array(week.enumerated()), id: \.offset) { _, value in
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(heatmapColor(value: value, max: maxTokens))
                                        .frame(width: 12, height: 12)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(height: 108)

                // Legend
                HStack(spacing: 4) {
                    Text("Less").font(.caption2).foregroundColor(.secondary)
                    ForEach(0..<5) { level in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(heatmapColorForLevel(level))
                            .frame(width: 12, height: 12)
                    }
                    Text("More").font(.caption2).foregroundColor(.secondary)
                }
            }
        }
    }

    private var dayLabels: [String] {
        ["", "Mon", "", "Wed", "", "Fri", ""]
    }

    /// Build a grid of weeks (columns) x 7 days (rows).
    /// Each cell holds token count (-1 = future/empty).
    private func buildHeatmapGrid() -> [[Int]] {
        var tokensByDate: [String: Int] = [:]
        for day in dailyUsage {
            tokensByDate[day.date] = day.totalTokens
        }

        let calendar = Calendar.current
        let today = Date()

        // Go back 90 days, then align to start of that week (Sunday)
        let ninetyDaysAgo = calendar.date(byAdding: .day, value: -90, to: today)!
        let weekday = calendar.component(.weekday, from: ninetyDaysAgo)
        let adjustedStart = calendar.date(byAdding: .day, value: -(weekday - 1), to: ninetyDaysAgo)!

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"

        var weeks: [[Int]] = []
        var currentDate = adjustedStart

        while currentDate <= today {
            var week: [Int] = []
            for _ in 0..<7 {
                if currentDate > today {
                    week.append(-1)
                } else {
                    let dateStr = formatter.string(from: currentDate)
                    week.append(tokensByDate[dateStr] ?? 0)
                }
                currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate)!
            }
            weeks.append(week)
        }

        return weeks
    }

    private func heatmapColor(value: Int, max: Int) -> Color {
        if value < 0 { return .clear }
        if value == 0 { return Color.secondary.opacity(0.1) }
        let ratio = Double(value) / Double(max)
        if ratio < 0.25 { return Color.green.opacity(0.3) }
        if ratio < 0.50 { return Color.green.opacity(0.5) }
        if ratio < 0.75 { return Color.green.opacity(0.7) }
        return Color.green.opacity(0.9)
    }

    private func heatmapColorForLevel(_ level: Int) -> Color {
        switch level {
        case 0: return Color.secondary.opacity(0.1)
        case 1: return Color.green.opacity(0.3)
        case 2: return Color.green.opacity(0.5)
        case 3: return Color.green.opacity(0.7)
        case 4: return Color.green.opacity(0.9)
        default: return .clear
        }
    }
}
