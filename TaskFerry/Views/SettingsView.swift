import AppKit
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @Bindable var state: AppState
    @State private var endpoint = ""
    @State private var clientID = ""
    @State private var clientSecret = ""
    @State private var bridgeToken = ""
    @State private var bridgeTokenRevealed = false
    @State private var launchAtLogin = false
    @State private var launchAtLoginLoaded = false
    @State private var launchAtLoginUpdating = false
    @State private var message: String?

    var body: some View {
        Form {
            Section("Role") {
                LabeledContent("This Mac") {
                    Text(state.mode == .bridge ? "Reminders bridge" : state.mode == .remote ? "Remote client" : "Not configured")
                }
                Button("Choose a Different Role…") {
                    state.resetMode()
                    NSApplication.shared.keyWindow?.close()
                }
            }

            if state.mode == .remote {
                Section("Connection") {
                    TextField("Server URL", text: $endpoint)
                    TextField("Cloudflare client ID", text: $clientID)
                    SecureField("Cloudflare client secret", text: $clientSecret)
                    HStack {
                        if bridgeTokenRevealed {
                            TextField("Bridge token", text: $bridgeToken)
                        } else {
                            SecureField("Bridge token", text: $bridgeToken)
                        }
                        Button {
                            bridgeTokenRevealed.toggle()
                        } label: {
                            Image(systemName: bridgeTokenRevealed ? "eye.slash" : "eye")
                        }
                        .buttonStyle(.borderless)
                        .help(bridgeTokenRevealed ? "Hide bridge token" : "Show bridge token")
                    }
                    HStack {
                        Button("Save") { saveRemote() }
                        Button("Save & Test") {
                            saveRemote()
                            Task { await state.refresh() }
                        }
                    }
                }
            } else if state.mode == .bridge {
                Section("Bridge") {
                    LabeledContent("Local address", value: "127.0.0.1:\(state.port)")
                    HStack {
                        Text("Bridge token")
                        Spacer()
                        Button(bridgeTokenRevealed ? "Hide" : "Show") {
                            bridgeTokenRevealed.toggle()
                        }
                        Button("Copy") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(bridgeToken, forType: .string)
                            message = "Bridge token copied."
                        }
                    }
                    if bridgeTokenRevealed {
                        Text(bridgeToken)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                    }
                    Text("New tokens use six short, unambiguous groups for easier typing.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Generate New Token") {
                        do {
                            bridgeToken = try state.regenerateBridgeToken()
                            message = "A new easy-to-type bridge token is ready."
                        } catch {
                            message = error.localizedDescription
                        }
                    }
                }

                Section("Background") {
                    Toggle("Run in Background", isOn: runsInBackgroundBinding)
                    Text("Hides the Dock icon while the bridge keeps running. Open Task Ferry again from Applications whenever you need its window.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Sync") {
                Button("Refresh Reminders") {
                    Task { await state.refresh() }
                }
                .keyboardShortcut("r", modifiers: .command)
                Text(state.mode == .remote
                    ? "Task Ferry also checks automatically every 15 seconds and whenever the app becomes active."
                    : "Reminders access and data are checked automatically when the bridge starts.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("General") {
                Toggle("Launch at Login", isOn: launchAtLoginBinding)
                    .disabled(!launchAtLoginLoaded || launchAtLoginUpdating)
                if UpdateManager.isSupported {
                    Button("Check for Updates…") {
                        UpdateManager.checkForUpdates()
                    }
                    .disabled(!UpdateManager.canCheckForUpdates)
                }
                if let message {
                    Text(message).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 420)
        .navigationTitle("Task Ferry")
        .task {
            endpoint = state.endpoint
            async let storedCredentials = state.loadStoredCredentials()
            async let launchAtLoginStatus = Task.detached(priority: .utility) {
                SMAppService.mainApp.status == .enabled
            }.value
            launchAtLoginLoaded = true
            let currentLaunchAtLogin = await launchAtLoginStatus
            if !launchAtLoginUpdating {
                launchAtLogin = currentLaunchAtLogin
            }
            let credentials = await storedCredentials
            clientID = credentials.accessClientID
            clientSecret = credentials.accessClientSecret
            bridgeToken = credentials.bridgeToken
        }
    }

    private func saveRemote() {
        do {
            try state.saveRemoteConfiguration(
                endpoint: endpoint,
                clientID: clientID,
                clientSecret: clientSecret,
                bridgeToken: bridgeToken
            )
            message = "Connection saved securely."
        } catch {
            message = error.localizedDescription
        }
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { launchAtLogin },
            set: { enabled in
                launchAtLogin = enabled
                launchAtLoginUpdating = true
                Task { await updateLaunchAtLogin(enabled) }
            }
        )
    }

    private var runsInBackgroundBinding: Binding<Bool> {
        Binding(
            get: { state.runsInBackground },
            set: { state.setRunsInBackground($0) }
        )
    }

    private func updateLaunchAtLogin(_ enabled: Bool) async {
        let result = await Task.detached(priority: .userInitiated) {
            var errorMessage: String?
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                errorMessage = error.localizedDescription
            }
            return (SMAppService.mainApp.status == .enabled, errorMessage)
        }.value

        launchAtLogin = result.0
        launchAtLoginUpdating = false
        if let errorMessage = result.1 {
            message = errorMessage
        }
    }
}
