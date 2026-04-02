import SwiftUI

struct DashboardView: View {
    @ObservedObject var appState: AppState
    @State private var profileUsages: UsageDatabase = [:]
    @State private var hourlyData: [(label: String, tokens: Int)] = []
    @State private var dailyData: [(label: String, tokens: Int)] = []
    @State private var monthlyData: [(label: String, tokens: Int)] = []
    @State private var selectedProfileId: String? = nil
    @State private var selectedTab: ChartTab = .daily

    enum ChartTab: String, CaseIterable {
        case hourly = "Hourly"
        case daily = "Daily"
        case monthly = "Monthly"
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            detailPane
        }
        .frame(minWidth: 560, minHeight: 420)
        .onAppear { loadData() }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Accounts")
                .font(.headline)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

            Divider()

            sidebarRow(
                title: "All Accounts",
                tokens: allTodayTotal,
                isActive: false,
                isSelected: selectedProfileId == nil,
                onTap: { selectedProfileId = nil }
            )

            Divider()

            ForEach(appState.profiles) { profile in
                let todayKey = UsageTracker.todayString()
                let todayTokens = profileUsages[profile.id]?.daily[todayKey] ?? 0
                sidebarRow(
                    title: profile.id,
                    tokens: todayTokens,
                    isActive: profile.id == appState.activeProfile?.id,
                    isSelected: selectedProfileId == profile.id,
                    onTap: { selectedProfileId = profile.id }
                )
            }

            Spacer()
        }
        .frame(width: 190)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func sidebarRow(title: String, tokens: Int, isActive: Bool, isSelected: Bool, onTap: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(isActive ? Color.green : Color.clear)
                .frame(width: 6, height: 6)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.bold())
                    .lineLimit(1)
                Text(formatTokens(tokens) + " today")
                    .font(.caption2.monospacedDigit())
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
    }

    // MARK: - Detail Pane

    private var detailPane: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let profileId = selectedProfileId {
                    profileDetail(profileId: profileId)
                } else {
                    globalDetail
                }
            }
            .padding()
        }
    }

    // MARK: - Global Detail

    private var globalDetail: some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                statCard(title: "Today", value: formatTokens(allTodayTotal))
                statCard(title: "All Time", value: formatTokens(allTimeTotal))
            }
            chartSection
        }
    }

    // MARK: - Profile Detail

    @ViewBuilder
    private func profileDetail(profileId: String) -> some View {
        let usage = profileUsages[profileId]
        let todayKey = UsageTracker.todayString()
        let todayTokens = usage?.daily[todayKey] ?? 0
        let totalTokens = usage?.total ?? 0

        VStack(spacing: 16) {
            HStack(spacing: 12) {
                statCard(title: "Today", value: formatTokens(todayTokens))
                statCard(title: "Total", value: formatTokens(totalTokens))
            }

            chartSection

            if let profile = appState.profiles.first(where: { $0.id == profileId }),
               let cred = profile.credential {
                HStack {
                    Circle()
                        .fill(tokenColor(cred))
                        .frame(width: 8, height: 8)
                    Text("Token expires in \(String(format: "%.1f", cred.remainingHours))h")
                        .font(.subheadline)
                    Spacer()
                    if profile.id != appState.activeProfile?.id {
                        Button("Switch") {
                            appState.switchProfile(to: profileId)
                        }
                        .font(.caption)
                    }
                }
                .padding()
                .background(Color(nsColor: .windowBackgroundColor))
                .cornerRadius(12)
            }
        }
    }

    // MARK: - Chart Section (tabbed)

    private var chartSection: some View {
        VStack(spacing: 0) {
            Picker("", selection: $selectedTab) {
                ForEach(ChartTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.bottom, 12)

            Group {
                switch selectedTab {
                case .hourly:
                    TokenBarChart(
                        title: "By Hour — Today",
                        entries: hourlyData.filter { $0.tokens > 0 }
                    )
                case .daily:
                    TokenBarChart(
                        title: "By Day — Last 7",
                        entries: dailyData.filter { $0.tokens > 0 }
                    )
                case .monthly:
                    TokenBarChart(
                        title: "By Month",
                        entries: monthlyData.filter { $0.tokens > 0 }
                    )
                }
            }
            .padding()
            .background(Color(nsColor: .windowBackgroundColor))
            .cornerRadius(12)
        }
    }

    // MARK: - Stat Card

    private func statCard(title: String, value: String) -> some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.title2.bold().monospacedDigit())
            Text("tokens")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(Color(nsColor: .windowBackgroundColor))
        .cornerRadius(12)
    }

    // MARK: - Computed Totals

    private var allTodayTotal: Int {
        let todayKey = UsageTracker.todayString()
        return profileUsages.values.compactMap { $0.daily[todayKey] }.reduce(0, +)
    }

    private var allTimeTotal: Int {
        profileUsages.values.map(\.total).reduce(0, +)
    }

    // MARK: - Load Data

    private func loadData() {
        profileUsages = appState.usageTracker.loadProfileUsages()

        // Hourly: today, hours 0-23
        let rawHourly = appState.usageTracker.realtimeHourlyToday()
        hourlyData = (0..<24).compactMap { h in
            let t = rawHourly[h] ?? 0
            guard t > 0 else { return nil }
            return (label: String(format: "%02d:00", h), tokens: t)
        }

        // Daily: last 7 days
        let rawDaily = appState.usageTracker.realtimeDailyUsage(lastDays: 7)
        let calendar = Calendar.current
        dailyData = (0..<7).map { offset -> (label: String, tokens: Int) in
            let date = calendar.date(byAdding: .day, value: -(6 - offset), to: Date())!
            let dateStr = UsageTracker.dateToString(date)
            let parts = dateStr.split(separator: "-")
            let label = parts.count == 3 ? "\(parts[1])/\(parts[2])" : dateStr
            return (label: label, tokens: rawDaily[dateStr] ?? 0)
        }

        // Monthly: all available
        let rawMonthly = appState.usageTracker.realtimeMonthlyUsage()
        monthlyData = rawMonthly
            .map { (label: $0.key, tokens: $0.value) }
            .sorted { $0.label < $1.label }
    }

    // MARK: - Helpers

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
