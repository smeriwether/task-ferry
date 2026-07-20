import AppKit
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @Bindable var state: AppState
    @State private var endpoint = ""
    @State private var clientID = ""
    @State private var clientSecret = ""
    @State private var bridgeToken = ""
    @State private var launchAtLogin = false
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
                    SecureField("Bridge token", text: $bridgeToken)
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
                        LabeledContent("Bridge token", value: "••••••••••••")
                        Button("Copy") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(state.bridgeToken, forType: .string)
                            message = "Bridge token copied."
                        }
                    }
                    Button("Generate New Token") {
                        do {
                            try state.regenerateBridgeToken()
                            bridgeToken = state.bridgeToken
                            message = "A new bridge token is ready."
                        } catch {
                            message = error.localizedDescription
                        }
                    }
                }
            }

            Section("General") {
                Toggle("Launch at Login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        updateLaunchAtLogin(enabled)
                    }
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
        .navigationTitle("Reminders Remote")
        .onAppear(perform: load)
        .task {
            launchAtLogin = await Task.detached(priority: .utility) {
                SMAppService.mainApp.status == .enabled
            }.value
        }
    }

    private func load() {
        endpoint = state.endpoint
        clientID = state.accessClientID
        clientSecret = state.accessClientSecret
        bridgeToken = state.bridgeToken
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

    private func updateLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
            message = error.localizedDescription
        }
    }
}
