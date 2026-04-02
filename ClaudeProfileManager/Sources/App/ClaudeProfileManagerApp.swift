import SwiftUI

@main
struct ClaudeProfileManagerApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        MenuBarExtra("Claude Profile Manager", systemImage: "person.2.circle") {
            MenuBarView(appState: appState)
                .onAppear {
                    if appState.isLoading {
                        appState.loadProfiles()
                        appState.startTokenKeeper()
                    }
                }
        }
        .menuBarExtraStyle(.window)

        Window("Dashboard", id: "dashboard") {
            DashboardView(appState: appState)
        }

        Window("Onboarding", id: "onboarding") {
            OnboardingView(appState: appState)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 450, height: 500)
    }

    init() {
        DispatchQueue.main.async {
            NSApplication.shared.setActivationPolicy(.accessory)
        }
    }
}
