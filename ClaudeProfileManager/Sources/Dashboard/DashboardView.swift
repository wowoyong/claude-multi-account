import SwiftUI

struct DashboardView: View {
    @ObservedObject var appState: AppState
    @State private var dailyUsage: [DailyModelTokens] = []
    @State private var todayBreakdown: [String: Int] = [:]
    @State private var weeklyTotal = 0
    @State private var monthlyTotal = 0

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
                            onSwitch: { appState.switchProfile(to: profile.id) }
                        )
                    }
                }
                .padding()
            }
            .frame(minWidth: 200, maxWidth: 250)

            // Right: Charts
            ScrollView {
                VStack(spacing: 20) {
                    UsageChartView(dailyUsage: dailyUsage)

                    HStack(alignment: .top, spacing: 20) {
                        ModelBreakdownView(breakdown: todayBreakdown)
                            .frame(maxWidth: .infinity)

                        // Weekly/Monthly summary
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
                                Text("This Month")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(formatTokens(monthlyTotal))
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
        .frame(minWidth: 700, minHeight: 450)
        .onAppear { loadData() }
    }

    private func loadData() {
        dailyUsage = (try? appState.usageTracker.parseDailyUsage()) ?? []
        todayBreakdown = (try? appState.usageTracker.modelBreakdown(
            forDate: UsageTracker.todayString()
        )) ?? [:]
        weeklyTotal = (try? appState.usageTracker.weeklySummary()) ?? 0
        monthlyTotal = (try? appState.usageTracker.monthlySummary()) ?? 0
    }

    private func formatTokens(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM tokens", Double(n) / 1_000_000) }
        if n >= 1_000 { return String(format: "%.1fK tokens", Double(n) / 1_000) }
        return "\(n) tokens"
    }
}
