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
            QuickEntryView(state: state)
        } label: {
            Label("Quick Reminder", systemImage: "plus.circle")
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(state: state)
        }
    }

}
