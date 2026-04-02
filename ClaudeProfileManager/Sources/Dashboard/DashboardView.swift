import SwiftUI
import Charts

enum ChartPeriod: String, CaseIterable {
    case week = "7D"
    case month = "30D"
    case all = "All"
}

enum ChartMode: String, CaseIterable {
    case tokens = "Tokens"
    case activity = "Activity"
    case hourly = "Hourly"
}

struct DashboardView: View {
    @ObservedObject var appState: AppState
    @State private var dailyUsage: [DailyModelTokens] = []
    @State private var dailyActivity: [DailyActivity] = []
    @State private var hourCounts: [String: Int] = [:]
    @State private var overallBreakdown: [String: Int] = [:]
    @State private var weeklyTotal = 0
    @State private var totalAll = 0
    @State private var profileUsages: UsageDatabase = [:]

    @State private var selectedPeriod: ChartPeriod = .all
    @State private var selectedMode: ChartMode = .tokens

    var body: some View {
        HSplitView {
            // Left: Profiles
            ScrollView {
                VStack(spacing: 8) {
                    Text("Profiles")
                        .font(.title2.bold())
                        .frame(maxWidth: .infinity, alignment: .leading)

                    ForEach(appState.profiles) { profile in
                        ProfileCardView(
                            profile: profile,
                            isActive: profile.id == appState.activeProfile?.id,
                            usage: profileUsages[profile.id],
                            onSwitch: { appState.switchProfile(to: profile.id) }
                        )
                    }
                }
                .padding()
            }
            .frame(minWidth: 220, maxWidth: 280)

            // Right: Charts
            ScrollView {
                VStack(spacing: 16) {
                    // Toggle bar
                    HStack {
                        Picker("Mode", selection: $selectedMode) {
                            ForEach(ChartMode.allCases, id: \.self) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 250)

                        Spacer()

                        if selectedMode != .hourly {
                            Picker("Period", selection: $selectedPeriod) {
                                ForEach(ChartPeriod.allCases, id: \.self) { period in
                                    Text(period.rawValue).tag(period)
                                }
                            }
                            .pickerStyle(.segmented)
                            .frame(maxWidth: 180)
                        }
                    }

                    // Chart
                    switch selectedMode {
                    case .tokens:
                        tokensChart
                    case .activity:
                        activityChart
                    case .hourly:
                        hourlyChart
                    }

                    HStack(alignment: .top, spacing: 20) {
                        ModelBreakdownView(breakdown: overallBreakdown)
                            .frame(maxWidth: .infinity)

                        VStack(alignment: .leading, spacing: 12) {
                            Text("Summary")
                                .font(.headline)

                            VStack(alignment: .leading, spacing: 4) {
                                Text("This Week")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(formatTokens(weeklyTotal))
                                    .font(.title2.bold().monospacedDigit())
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text("All Time")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(formatTokens(totalAll))
                                    .font(.title2.bold().monospacedDigit())
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }

                    if let lastRefresh = appState.lastRefreshTime {
                        HStack {
                            Image(systemName: "arrow.clockwise")
                            Text("Last refresh: \(lastRefresh, style: .relative) ago")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding()
            }
        }
        .frame(minWidth: 750, minHeight: 500)
        .onAppear { loadData() }
    }

    // MARK: - Token Chart

    private var tokensChart: some View {
        VStack(alignment: .leading) {
            Text("Daily Token Usage (Estimated)")
                .font(.headline)

            let filtered = filteredDailyUsage
            if filtered.isEmpty {
                Text("No data for this period")
                    .foregroundColor(.secondary)
                    .frame(height: 200)
            } else {
                Chart {
                    ForEach(tokenChartData(from: filtered), id: \.id) { entry in
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
                .frame(height: 220)
            }
        }
    }

    // MARK: - Activity Chart

    private var activityChart: some View {
        VStack(alignment: .leading) {
            Text("Daily Activity")
                .font(.headline)

            let filtered = filteredDailyActivity
            if filtered.isEmpty {
                Text("No activity data for this period")
                    .foregroundColor(.secondary)
                    .frame(height: 200)
            } else {
                Chart {
                    ForEach(filtered, id: \.date) { day in
                        BarMark(
                            x: .value("Date", shortDate(day.date)),
                            y: .value("Messages", day.messageCount)
                        )
                        .foregroundStyle(Color.blue)
                    }
                }
                .frame(height: 220)

                HStack(spacing: 20) {
                    statBadge("Sessions", value: filtered.reduce(0) { $0 + $1.sessionCount })
                    statBadge("Messages", value: filtered.reduce(0) { $0 + $1.messageCount })
                    statBadge("Tool Calls", value: filtered.reduce(0) { $0 + $1.toolCallCount })
                }
                .font(.caption)
            }
        }
    }

    // MARK: - Hourly Chart

    private var hourlyChart: some View {
        VStack(alignment: .leading) {
            Text("Activity by Hour of Day")
                .font(.headline)

            if hourCounts.isEmpty {
                Text("No hourly data")
                    .foregroundColor(.secondary)
                    .frame(height: 200)
            } else {
                Chart {
                    ForEach(0..<24, id: \.self) { hour in
                        let count = hourCounts[String(hour)] ?? 0
                        BarMark(
                            x: .value("Hour", "\(hour):00"),
                            y: .value("Sessions", count)
                        )
                        .foregroundStyle(hour >= 9 && hour <= 18 ? Color.blue : Color.blue.opacity(0.4))
                    }
                }
                .frame(height: 220)
            }
        }
    }

    // MARK: - Helpers

    private var filteredDailyUsage: [DailyModelTokens] {
        filterByPeriod(dailyUsage, dateKeyPath: \.date)
    }

    private var filteredDailyActivity: [DailyActivity] {
        filterByPeriod(dailyActivity, dateKeyPath: \.date)
    }

    private func filterByPeriod<T>(_ items: [T], dateKeyPath: KeyPath<T, String>) -> [T] {
        switch selectedPeriod {
        case .all:
            return items
        case .week:
            let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
            return items.filter { item in
                guard let date = UsageTracker.parseDate(item[keyPath: dateKeyPath]) else { return false }
                return date >= cutoff
            }
        case .month:
            let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date())!
            return items.filter { item in
                guard let date = UsageTracker.parseDate(item[keyPath: dateKeyPath]) else { return false }
                return date >= cutoff
            }
        }
    }

    private func tokenChartData(from data: [DailyModelTokens]) -> [ChartEntry] {
        data.flatMap { day in
            day.tokensByModel.map { model, tokens in
                ChartEntry(date: shortDate(day.date), model: modelShortName(model), tokens: tokens)
            }
        }
    }

    private func shortDate(_ dateStr: String) -> String {
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

    private func statBadge(_ label: String, value: Int) -> some View {
        VStack {
            Text("\(value)")
                .font(.title3.bold().monospacedDigit())
            Text(label)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(8)
    }

    private func loadData() {
        dailyUsage = (try? appState.usageTracker.parseDailyUsage()) ?? []
        dailyActivity = (try? appState.usageTracker.parseDailyActivity()) ?? []
        hourCounts = (try? appState.usageTracker.parseHourCounts()) ?? [:]
        overallBreakdown = (try? appState.usageTracker.modelBreakdown()) ?? [:]
        weeklyTotal = (try? appState.usageTracker.weeklySummary()) ?? 0
        totalAll = (try? appState.usageTracker.totalSummary()) ?? 0
        profileUsages = appState.usageTracker.loadProfileUsages()
    }

    private func formatTokens(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM tokens", Double(n) / 1_000_000) }
        if n >= 1_000 { return String(format: "%.1fK tokens", Double(n) / 1_000) }
        return "\(n) tokens"
    }
}

private struct ChartEntry: Identifiable {
    let id = UUID()
    let date: String
    let model: String
    let tokens: Int
}
