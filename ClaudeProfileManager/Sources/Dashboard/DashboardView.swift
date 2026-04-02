import SwiftUI

struct DashboardView: View {
    @ObservedObject var appState: AppState
    @State private var dailyUsage: [DailyModelTokens] = []
    @State private var overallBreakdown: [String: Int] = [:]
    @State private var weeklyTotal = 0
    @State private var totalAll = 0
    @State private var profileUsages: UsageDatabase = [:]

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
                VStack(spacing: 20) {
                    UsageChartView(dailyUsage: dailyUsage)

                    HStack(alignment: .top, spacing: 20) {
                        ModelBreakdownView(breakdown: overallBreakdown)
                            .frame(maxWidth: .infinity)

                        // Summary
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

                    // Token Keeper status
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
        .frame(minWidth: 750, minHeight: 480)
        .onAppear { loadData() }
    }

    private func loadData() {
        dailyUsage = (try? appState.usageTracker.parseDailyUsage()) ?? []
        // Overall model breakdown (all time, not just today)
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
