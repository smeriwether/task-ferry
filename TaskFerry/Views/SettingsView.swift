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
    @State private var connectionSaving = false
    @State private var tokenGenerating = false
    @State private var message: String?
    @State private var cloudflareSheet: CloudflareSheet?

    private enum CloudflareSheet: Identifiable {
        case setup
        case remove(CloudflareProvisioning)

        var id: String {
            switch self {
            case .setup: "setup"
            case .remove: "remove"
            }
        }
    }

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
                        .disabled(connectionSaving)
                    TextField("Cloudflare client ID", text: $clientID)
                        .disabled(connectionSaving)
                    SecureField("Cloudflare client secret", text: $clientSecret)
                        .disabled(connectionSaving)
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
                    .disabled(connectionSaving)
                    HStack {
                        Button(connectionSaving ? "Saving…" : "Save") {
                            Task { _ = await saveRemote() }
                        }
                        .disabled(connectionSaving)
                        Button("Save & Test") {
                            Task {
                                if await saveRemote() {
                                    await state.refresh()
                                }
                            }
                        }
                        .disabled(connectionSaving)
                        Button("Paste Connection Code") {
                            pasteConnectionCode()
                        }
                        .disabled(connectionSaving)
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
                    Button(tokenGenerating ? "Generating…" : "Generate New Token") {
                        guard !tokenGenerating else { return }
                        tokenGenerating = true
                        Task {
                            do {
                                bridgeToken = try await state.regenerateBridgeToken()
                                message = "A new easy-to-type bridge token is ready."
                            } catch {
                                message = error.localizedDescription
                            }
                            tokenGenerating = false
                        }
                    }
                    .disabled(tokenGenerating)
                }

                Section("Remote Access") {
                    if let hostname = state.cloudflareHostname {
                        LabeledContent("Public address", value: hostname)
                        LabeledContent("Cloudflare connector", value: connectorDetail)
                        HStack {
                            Button("Copy Connection Code") {
                                copyConnectionCode()
                            }
                            Button("Remove Cloudflare Setup…", role: .destructive) {
                                guard let provisioning = state.cloudflareProvisioning else { return }
                                cloudflareSheet = .remove(provisioning)
                            }
                        }
                        Text("The connection code contains passwords. Share it only with the Mac that will connect to this bridge.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Let Task Ferry create a tunnel, DNS record, and protected Access connection in your own Cloudflare account.")
                            .foregroundStyle(.secondary)
                        Button("Set Up with Cloudflare…") {
                            cloudflareSheet = .setup
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
        .frame(width: 500, height: 540)
        .navigationTitle("Task Ferry")
        .sheet(item: $cloudflareSheet) { sheet in
            switch sheet {
            case .setup:
                CloudflareSetupView(state: state, purpose: .create)
            case .remove(let provisioning):
                CloudflareSetupView(state: state, purpose: .remove(provisioning))
            }
        }
        .task {
            endpoint = state.endpoint
            async let storedCredentials = state.loadStoredCredentials()
            async let launchAtLoginStatus = Task.detached(priority: .utility) {
                SMAppService.mainApp.status == .enabled
            }.value
            let currentLaunchAtLogin = await launchAtLoginStatus
            if !launchAtLoginUpdating {
                launchAtLogin = currentLaunchAtLogin
            }
            launchAtLoginLoaded = true
            let credentials = await storedCredentials
            clientID = credentials.accessClientID
            clientSecret = credentials.accessClientSecret
            bridgeToken = credentials.bridgeToken
        }
    }

    private func saveRemote() async -> Bool {
        guard !connectionSaving else { return false }
        connectionSaving = true
        defer { connectionSaving = false }
        do {
            try await state.saveRemoteConfiguration(
                endpoint: endpoint,
                clientID: clientID,
                clientSecret: clientSecret,
                bridgeToken: bridgeToken
            )
            message = "Connection saved securely."
            return true
        } catch {
            message = error.localizedDescription
            return false
        }
    }

    private func pasteConnectionCode() {
        guard let value = NSPasteboard.general.string(forType: .string) else {
            message = "The clipboard is empty."
            return
        }
        do {
            let connection = try TaskFerryConnectionCode.decode(value)
            endpoint = connection.endpoint
            clientID = connection.accessClientID
            clientSecret = connection.accessClientSecret
            bridgeToken = connection.bridgeToken
            message = "Connection code loaded. Choose Save & Test to finish."
        } catch {
            message = error.localizedDescription
        }
    }

    private func copyConnectionCode() {
        do {
            let code = try state.connectionCode()
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(code, forType: .string)
            message = "Connection code copied. It contains passwords, so share it securely."
        } catch {
            message = error.localizedDescription
        }
    }

    private var connectorDetail: String {
        switch state.cloudflareConnectorState {
        case .notConfigured: "Not configured"
        case .stopped: "Stopped"
        case .starting: "Connecting…"
        case .connected: "Connected"
        case .failed(let message): message
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
