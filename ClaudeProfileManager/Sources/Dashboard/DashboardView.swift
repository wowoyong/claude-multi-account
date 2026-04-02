import SwiftUI

struct DashboardView: View {
    @ObservedObject var appState: AppState
    @State private var dailyUsage: [DailyModelTokens] = []
    @State private var overallBreakdown: [String: Int] = [:]
    @State private var todayTotal = 0
    @State private var weeklyTotal = 0
    @State private var monthlyTotal = 0
    @State private var profileUsages: UsageDatabase = [:]
    @State private var selectedProfileId: String? = nil

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // MARK: - Profile Selector (horizontal)
                profileSelector

                // MARK: - Filter banner
                if let profileId = selectedProfileId,
                   let profile = appState.profiles.first(where: { $0.id == profileId }) {
                    HStack {
                        Text("Showing: \(profile.id)")
                            .font(.subheadline.bold())
                            .foregroundColor(.orange)
                        Spacer()
                        Button(action: { selectedProfileId = nil }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(8)
                }

                // MARK: - Stats Cards
                statsCards

                // MARK: - Heatmap
                HeatmapView(dailyUsage: filteredDailyUsage)
                    .padding()
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(12)

                // MARK: - Model Breakdown
                ModelBreakdownView(breakdown: filteredBreakdown)
                    .padding()
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(12)

                // MARK: - Token Status
                tokenStatus

                // MARK: - Last refresh
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
        .frame(minWidth: 600, minHeight: 500)
        .onAppear { loadData() }
    }

    // MARK: - Profile Selector

    private var profileSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(appState.profiles) { profile in
                    ProfileCardView(
                        profile: profile,
                        isActive: profile.id == appState.activeProfile?.id,
                        usage: profileUsages[profile.id],
                        onSwitch: { appState.switchProfile(to: profile.id) },
                        isSelected: profile.id == selectedProfileId,
                        onSelect: {
                            selectedProfileId = selectedProfileId == profile.id ? nil : profile.id
                        },
                        compact: true
                    )
                }
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 4)
        }
    }

    // MARK: - Stats Cards

    private var statsCards: some View {
        HStack(spacing: 12) {
            statCard(title: "Today", value: displayTodayTotal)
            statCard(title: "This Week", value: displayWeeklyTotal)
            statCard(title: "This Month", value: displayMonthlyTotal)
        }
    }

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
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(12)
    }

    // MARK: - Token Status

    private var tokenStatus: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Token Status")
                .font(.headline)

            ForEach(appState.profiles) { profile in
                if let cred = profile.credential {
                    HStack {
                        Circle()
                            .fill(tokenColor(cred))
                            .frame(width: 8, height: 8)
                        Text(profile.id)
                            .font(.subheadline)
                        Spacer()
                        Text(String(format: "%.1fh remaining", cred.remainingHours))
                            .font(.subheadline.monospacedDigit())
                            .foregroundColor(tokenColor(cred))
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(12)
    }

    // MARK: - Filtered Data

    private var filteredDailyUsage: [DailyModelTokens] {
        if let profileId = selectedProfileId {
            return appState.usageTracker.profileDailyUsage(profileId: profileId)
        }
        return dailyUsage
    }

    private var filteredBreakdown: [String: Int] {
        if let profileId = selectedProfileId {
            // Build breakdown from profile's daily usage
            var total: [String: Int] = [:]
            for day in appState.usageTracker.profileDailyUsage(profileId: profileId) {
                for (model, tokens) in day.tokensByModel {
                    total[model, default: 0] += tokens
                }
            }
            return total
        }
        return overallBreakdown
    }

    private var displayTodayTotal: String {
        if let profileId = selectedProfileId,
           let usage = profileUsages[profileId] {
            let todayKey = UsageTracker.todayString()
            return formatTokens(usage.daily[todayKey] ?? 0)
        }
        return formatTokens(todayTotal)
    }

    private var displayWeeklyTotal: String {
        if let profileId = selectedProfileId {
            let days = appState.usageTracker.profileDailyUsage(profileId: profileId)
            let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
            let total = days.filter { entry in
                guard let date = UsageTracker.parseDate(entry.date) else { return false }
                return date >= cutoff
            }.reduce(0) { $0 + $1.totalTokens }
            return formatTokens(total)
        }
        return formatTokens(weeklyTotal)
    }

    private var displayMonthlyTotal: String {
        if let profileId = selectedProfileId {
            let days = appState.usageTracker.profileDailyUsage(profileId: profileId)
            let cutoff = Calendar.current.date(byAdding: .month, value: -1, to: Date())!
            let total = days.filter { entry in
                guard let date = UsageTracker.parseDate(entry.date) else { return false }
                return date >= cutoff
            }.reduce(0) { $0 + $1.totalTokens }
            return formatTokens(total)
        }
        return formatTokens(monthlyTotal)
    }

    // MARK: - Helpers

    private func loadData() {
        dailyUsage = (try? appState.usageTracker.parseDailyUsage()) ?? []
        overallBreakdown = (try? appState.usageTracker.modelBreakdown()) ?? [:]
        todayTotal = (try? appState.usageTracker.todayUsage()) ?? 0
        weeklyTotal = (try? appState.usageTracker.weeklySummary()) ?? 0
        monthlyTotal = (try? appState.usageTracker.monthlySummary()) ?? 0
        profileUsages = appState.usageTracker.loadProfileUsages()
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
