import AppKit
import SwiftUI

@main
struct RemindersRemoteApp: App {
    @State private var state = AppState()

    init() {
        UpdateManager.start()
    }

    var body: some Scene {
        WindowGroup("Reminders Remote") {
            MenuRootView(state: state)
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Reminders Remote") {
                    NSApplication.shared.orderFrontStandardAboutPanel()
                }
            }
        }

        MenuBarExtra {
            MenuRootView(state: state)
        } label: {
            Label("Reminders Remote", systemImage: menuIcon)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(state: state)
        }
    }

    private var menuIcon: String {
        guard state.mode == .remote else { return "antenna.radiowaves.left.and.right" }
        return state.todayReminders.isEmpty ? "checkmark.circle" : "checklist"
    }
}
