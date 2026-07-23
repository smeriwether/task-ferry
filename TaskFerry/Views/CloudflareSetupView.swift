import SwiftUI

struct CloudflareSetupView: View {
    enum Purpose {
        case create
        case remove(CloudflareProvisioning)
    }

    @Environment(\.dismiss) private var dismiss
    @Bindable var state: AppState
    let purpose: Purpose

    @State private var zones: [CloudflareZone] = []
    @State private var selectedZoneID = ""
    @State private var subdomain = "task-ferry"
    @State private var accessToken: String?
    @State private var oauthClient: CloudflareOAuthClient?
    @State private var isWorking = false
    @State private var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text(isRemoval ? "Remove Cloudflare setup" : "Set up Cloudflare")
                    .font(.title2.weight(.semibold))
                Text(explanation)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if isRemoval {
                removalContent
            } else if accessToken == nil {
                authorizationContent
            } else {
                provisioningContent
            }

            if let message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            HStack {
                Button("Cancel") { dismiss() }
                    .disabled(isWorking)
                Spacer()
                actionButton
            }
        }
        .padding(24)
        .frame(width: 500, height: 410)
        .interactiveDismissDisabled(isWorking)
        .onDisappear {
            guard let token = accessToken, let oauthClient else { return }
            Task { await oauthClient.revoke(token) }
        }
    }

    private var authorizationContent: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Label("Your browser opens Cloudflare's sign-in page.", systemImage: "safari")
                Label("You choose the Cloudflare account and approve limited access.", systemImage: "person.crop.circle.badge.checkmark")
                Label("Task Ferry creates only its own tunnel, DNS record, and Access credentials.", systemImage: "lock.shield")
                Label("The temporary Cloudflare authorization is revoked when setup finishes.", systemImage: "clock.arrow.circlepath")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(4)
        }
    }

    private var provisioningContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            if zones.isEmpty {
                ContentUnavailableView(
                    "No active domains",
                    systemImage: "globe.badge.chevron.backward",
                    description: Text("Add an active domain to this Cloudflare account, then try again.")
                )
            } else {
                Picker("Domain", selection: $selectedZoneID) {
                    ForEach(zones) { zone in
                        Text("\(zone.name) — \(zone.accountName)").tag(zone.id)
                    }
                }
                TextField("Subdomain", text: $subdomain)
                if let selectedZone {
                    LabeledContent("Public address", value: previewHostname(for: selectedZone))
                }
                Text("Cloudflare Zero Trust must already be activated for the selected account. Its free plan is sufficient.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var removalContent: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                if case .remove(let provisioning) = purpose {
                    LabeledContent("Public address", value: provisioning.hostname)
                }
                Text("Task Ferry will ask Cloudflare for permission, then remove the exact DNS record, Access application, service token, and tunnel it created.")
                    .fixedSize(horizontal: false, vertical: true)
                Text("Your other Cloudflare resources are left alone.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(4)
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        if isRemoval {
            Button(isWorking ? "Removing…" : "Authorize & Remove", role: .destructive) {
                Task { await remove() }
            }
            .disabled(isWorking)
        } else if accessToken == nil {
            Button(isWorking ? "Connecting…" : "Continue in Browser") {
                Task { await connect() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isWorking)
        } else {
            Button(isWorking ? "Setting Up…" : "Create Private Connection") {
                Task { await provision() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isWorking || selectedZone == nil)
        }
    }

    private var isRemoval: Bool {
        if case .remove = purpose { return true }
        return false
    }

    private var explanation: String {
        if isRemoval {
            return "This removes Task Ferry's resources from your own Cloudflare account."
        }
        return "Use your own Cloudflare account without installing or running the Cloudflare CLI yourself."
    }

    private var selectedZone: CloudflareZone? {
        zones.first { $0.id == selectedZoneID }
    }

    private func previewHostname(for zone: CloudflareZone) -> String {
        (try? CloudflareAPIClient.hostname(subdomain: subdomain, zoneName: zone.name)) ?? "—"
    }

    private func connect() async {
        guard !isWorking else { return }
        isWorking = true
        message = nil
        do {
            let configuration = try CloudflareOAuthConfiguration.current()
            let oauthClient = CloudflareOAuthClient(configuration: configuration)
            self.oauthClient = oauthClient
            let token = try await oauthClient.authorize()
            accessToken = token
            zones = try await CloudflareAPIClient().listActiveZones(accessToken: token)
            selectedZoneID = zones.first?.id ?? ""
        } catch {
            await revokeAuthorization()
            message = error.localizedDescription
        }
        isWorking = false
    }

    private func provision() async {
        guard !isWorking, let token = accessToken, let selectedZone else { return }
        isWorking = true
        message = nil
        let api = CloudflareAPIClient()
        do {
            let result = try await api.provision(
                zone: selectedZone,
                subdomain: subdomain,
                localPort: state.port,
                accessToken: token
            )
            do {
                try await state.saveCloudflareProvisioning(result)
            } catch {
                try? await api.deleteProvisioning(result.provisioning, accessToken: token)
                throw error
            }
            await revokeAuthorization()
            dismiss()
        } catch {
            message = error.localizedDescription
            await revokeAuthorization()
        }
        isWorking = false
    }

    private func remove() async {
        guard !isWorking, case .remove(let provisioning) = purpose else { return }
        isWorking = true
        message = nil
        do {
            let configuration = try CloudflareOAuthConfiguration.current()
            let oauthClient = CloudflareOAuthClient(configuration: configuration)
            self.oauthClient = oauthClient
            let token = try await oauthClient.authorize()
            accessToken = token
            state.stopCloudflareConnector()
            try await CloudflareAPIClient().deleteProvisioning(provisioning, accessToken: token)
            try await state.removeStoredCloudflareProvisioning()
            await revokeAuthorization()
            dismiss()
        } catch {
            message = error.localizedDescription
            state.startCloudflareConnector()
            await revokeAuthorization()
        }
        isWorking = false
    }

    private func revokeAuthorization() async {
        guard let token = accessToken, let oauthClient else { return }
        accessToken = nil
        self.oauthClient = nil
        await oauthClient.revoke(token)
    }
}
