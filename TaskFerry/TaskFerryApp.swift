import AppKit
import SwiftUI

@main
struct TaskFerryApp: App {
    @State private var state = AppState()

    init() {
        UpdateManager.start()
    }

    var body: some Scene {
        WindowGroup("Task Ferry") {
            MenuRootView(state: state)
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Task Ferry") {
                    NSApplication.shared.orderFrontStandardAboutPanel()
                }
            }
            CommandGroup(after: .help) {
                Link("Task Ferry Source & License", destination: URL(string: "https://github.com/smeriwether/task-ferry")!)
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
