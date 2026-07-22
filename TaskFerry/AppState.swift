import AppKit
import Foundation
import Observation

enum AppPreferences {
    static let mode = "mode"
    static let endpoint = "endpoint"
    static let port = "port"
    static let runsInBackground = "runs-in-background"
}

@MainActor
@Observable
final class AppState {
    struct StoredCredentials: Sendable {
        let accessClientID: String
        let accessClientSecret: String
        let bridgeToken: String
    }

    enum ConnectionState: Equatable {
        case idle
        case loading
        case connected
        case failed(String)
    }

    private enum SecretKey {
        static let accessClientID = "access-client-id"
        static let accessClientSecret = "access-client-secret"
        static let bridgeToken = "bridge-token"
    }

    private enum ErrorSource: Equatable {
        case refresh
        case mutation
        case configuration
    }

    var mode: AppMode?
    var snapshot = ReminderSnapshot.empty
    var selectedView = SmartView.today
    var connectionState = ConnectionState.idle
    var bridgeState = BridgeServer.State.stopped
    var errorMessage: String?
    var runsInBackground: Bool

    @ObservationIgnored private let operations = ReminderOperationCoordinator()
    @ObservationIgnored private var bridge: BridgeServer?
    @ObservationIgnored private var isStarted = false
    @ObservationIgnored private var isRefreshing = false
    @ObservationIgnored private var startTask: Task<Void, Never>?
    @ObservationIgnored private var startGeneration = 0
    @ObservationIgnored private let isDemo: Bool
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let credentialStore: any CredentialStore
    @ObservationIgnored private let serviceFactory: ReminderServiceFactory
    @ObservationIgnored private var errorSource: ErrorSource?
    @ObservationIgnored private var demoEndpoint = "https://reminders.merimerimeri.com"
    @ObservationIgnored private var credentialsLoaded = false
    private var cachedCredentials = StoredCredentials(accessClientID: "", accessClientSecret: "", bridgeToken: "")

    var endpoint: String {
        get { isDemo ? demoEndpoint : defaults.string(forKey: AppPreferences.endpoint) ?? "https://reminders.merimerimeri.com" }
        set {
            if isDemo {
                demoEndpoint = newValue
            } else {
                defaults.set(newValue, forKey: AppPreferences.endpoint)
            }
        }
    }

    var port: UInt16 {
        get {
            let stored = defaults.integer(forKey: AppPreferences.port)
            return stored > 0 ? UInt16(exactly: stored) ?? 8788 : 8788
        }
        set { defaults.set(Int(newValue), forKey: AppPreferences.port) }
    }

    var accessClientID: String { cachedCredentials.accessClientID }
    var accessClientSecret: String { cachedCredentials.accessClientSecret }
    var bridgeToken: String { cachedCredentials.bridgeToken }

    init(
        isDemo: Bool? = nil,
        defaults: UserDefaults = .standard,
        credentialStore: any CredentialStore = KeychainCredentialStore(),
        serviceFactory: ReminderServiceFactory = .live
    ) {
        let demoMode = isDemo ?? (ProcessInfo.processInfo.environment["TASK_FERRY_DEMO"] == "1")
        self.isDemo = demoMode
        self.defaults = defaults
        self.credentialStore = credentialStore
        self.serviceFactory = serviceFactory
        runsInBackground = demoMode ? false : defaults.bool(forKey: AppPreferences.runsInBackground)
        if demoMode {
            cachedCredentials = StoredCredentials(
                accessClientID: "",
                accessClientSecret: "",
                bridgeToken: "DEMO-DEMO-DEMO-DEMO-DEMO-DEMO"
            )
            credentialsLoaded = true
            mode = ProcessInfo.processInfo.environment["TASK_FERRY_DEMO_ROLE"] == "bridge" ? .bridge : .remote
            operations.replaceService(DemoReminderService())
            isStarted = true
            connectionState = .connected
            if mode == .bridge {
                bridgeState = .running(8788)
            }
        } else if let value = defaults.string(forKey: AppPreferences.mode),
                  let savedMode = AppMode(rawValue: value) {
            mode = savedMode
        }
    }

    var todayReminders: [ReminderRecord] {
        snapshot.reminders.filter { reminder in
            guard let due = reminder.due else { return false }
            return due.isBeforeDay(Date()) || due.isSameDay(as: Date())
        }.sorted(by: sortReminders)
    }

    var tomorrowReminders: [ReminderRecord] {
        guard let tomorrow = Calendar.autoupdatingCurrent.date(byAdding: .day, value: 1, to: Date()) else { return [] }
        return snapshot.reminders.filter { $0.due?.isSameDay(as: tomorrow) == true }.sorted(by: sortReminders)
    }

    var visibleReminders: [ReminderRecord] {
        selectedView == .today ? todayReminders : tomorrowReminders
    }

    var defaultListID: String? {
        if let id = snapshot.defaultListID, snapshot.lists.contains(where: { $0.id == id }) {
            return id
        }
        return snapshot.lists.first?.id
    }

    func reminders(in listID: String) -> [ReminderRecord] {
        snapshot.reminders.filter { $0.listID == listID }.sorted(by: sortReminders)
    }

    func list(for id: String) -> ReminderListRecord? {
        snapshot.lists.first { $0.id == id }
    }

    func chooseMode(_ mode: AppMode) async {
        self.mode = mode
        defaults.set(mode.rawValue, forKey: AppPreferences.mode)
        applyActivationPolicy()
        await start()
    }

    func start() async {
        guard !isStarted, let mode else { return }
        if let startTask {
            await startTask.value
            return
        }

        startGeneration += 1
        let generation = startGeneration
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.prepareService(for: mode, generation: generation)
        }
        startTask = task
        await task.value
        if startGeneration == generation {
            startTask = nil
        }
    }

    func resetMode() {
        startGeneration += 1
        startTask?.cancel()
        startTask = nil
        bridge?.stop()
        bridge = nil
        bridgeState = .stopped
        operations.replaceService(nil)
        isStarted = false
        mode = nil
        snapshot = .empty
        connectionState = .idle
        clearError()
        defaults.removeObject(forKey: AppPreferences.mode)
        applyActivationPolicy()
    }

    @discardableResult
    func refresh(showLoadingIndicator: Bool = true) async -> Bool {
        guard !isRefreshing else { return connectionState == .connected }
        isRefreshing = true
        defer { isRefreshing = false }
        await start()
        if showLoadingIndicator || snapshot == .empty {
            connectionState = .loading
        }
        let outcome = await operations.execute(.snapshot) { [weak self] outcome in
            self?.apply(outcome, source: .refresh, clearAllErrorsOnSuccess: showLoadingIndicator)
        }
        return outcome.succeeded
    }

    @discardableResult
    func createReminder(title: String, listID: String, due: ReminderDue?) async -> Bool {
        await perform(RPCRequest(operation: .upsertReminder, title: title, listID: listID, due: due))
    }

    @discardableResult
    func updateReminder(_ reminder: ReminderRecord, title: String, listID: String, due: ReminderDue?) async -> Bool {
        await perform(RPCRequest(operation: .upsertReminder, id: reminder.id, title: title, listID: listID, due: due))
    }

    @discardableResult
    func complete(_ reminder: ReminderRecord) async -> Bool {
        await perform(RPCRequest(operation: .setCompleted, id: reminder.id, completed: true))
    }

    @discardableResult
    func deleteReminder(_ reminder: ReminderRecord) async -> Bool {
        await perform(RPCRequest(operation: .deleteReminder, id: reminder.id))
    }

    @discardableResult
    func createList(title: String) async -> Bool {
        await perform(RPCRequest(operation: .upsertList, title: title))
    }

    @discardableResult
    func renameList(_ list: ReminderListRecord, title: String) async -> Bool {
        await perform(RPCRequest(operation: .upsertList, id: list.id, title: title))
    }

    @discardableResult
    func deleteList(_ list: ReminderListRecord) async -> Bool {
        await perform(RPCRequest(operation: .deleteList, id: list.id))
    }

    func saveRemoteConfiguration(endpoint: String, clientID: String, clientSecret: String, bridgeToken: String) async throws {
        let configuration = try RemoteConfiguration(
            endpoint: endpoint,
            accessClientID: clientID,
            accessClientSecret: clientSecret,
            bridgeToken: bridgeToken
        )
        if !isDemo {
            let store = credentialStore
            try await Task.detached(priority: .userInitiated) {
                try store.setAtomically([
                    (SecretKey.accessClientID, configuration.accessClientID),
                    (SecretKey.accessClientSecret, configuration.accessClientSecret),
                    (SecretKey.bridgeToken, configuration.bridgeToken)
                ])
            }.value
        }
        cachedCredentials = StoredCredentials(
            accessClientID: configuration.accessClientID,
            accessClientSecret: configuration.accessClientSecret,
            bridgeToken: configuration.bridgeToken
        )
        credentialsLoaded = true
        self.endpoint = configuration.endpoint.absoluteString
        if mode == .remote { configureService(for: .remote) }
    }

    func loadStoredCredentials() async -> StoredCredentials {
        if isDemo || credentialsLoaded { return cachedCredentials }
        let store = credentialStore
        let credentials = await Task.detached(priority: .utility) {
            StoredCredentials(
                accessClientID: store.string(for: SecretKey.accessClientID),
                accessClientSecret: store.string(for: SecretKey.accessClientSecret),
                bridgeToken: store.string(for: SecretKey.bridgeToken)
            )
        }.value
        cachedCredentials = credentials
        credentialsLoaded = true
        return credentials
    }

    @discardableResult
    func regenerateBridgeToken() async throws -> String {
        if isDemo { return bridgeToken }
        let store = credentialStore
        let token = try await Task.detached(priority: .userInitiated) {
            let token = try store.randomToken()
            try store.set(token, for: SecretKey.bridgeToken)
            return token
        }.value
        cachedCredentials = StoredCredentials(
            accessClientID: accessClientID,
            accessClientSecret: accessClientSecret,
            bridgeToken: token
        )
        credentialsLoaded = true
        if mode == .bridge { configureService(for: .bridge, bridgeTokenOverride: token) }
        return token
    }

    func setRunsInBackground(_ enabled: Bool) {
        runsInBackground = enabled
        if !isDemo {
            defaults.set(enabled, forKey: AppPreferences.runsInBackground)
        }
        applyActivationPolicy()
    }

    func dismissError() {
        clearError()
    }

    func applyActivationPolicy() {
        guard !isDemo else { return }
        let policy: NSApplication.ActivationPolicy = mode == .bridge && runsInBackground ? .accessory : .regular
        NSApplication.shared.setActivationPolicy(policy)
    }

    private func prepareService(for mode: AppMode, generation: Int) async {
        _ = await loadStoredCredentials()
        guard startGeneration == generation, self.mode == mode, !Task.isCancelled else { return }

        if mode == .bridge, bridgeToken.isEmpty {
            do {
                try await ensureBridgeToken()
            } catch {
                guard startGeneration == generation, self.mode == mode, !Task.isCancelled else { return }
                configureService(for: mode)
                setError(error.localizedDescription, source: .configuration)
                isStarted = true
                return
            }
        }

        guard startGeneration == generation, self.mode == mode, !Task.isCancelled else { return }
        configureService(for: mode)
        isStarted = true
    }

    private func ensureBridgeToken() async throws {
        guard bridgeToken.isEmpty else { return }
        let store = credentialStore
        let token = try await Task.detached(priority: .userInitiated) {
            let token = try store.randomToken()
            try store.set(token, for: SecretKey.bridgeToken)
            return token
        }.value
        cachedCredentials = StoredCredentials(
            accessClientID: accessClientID,
            accessClientSecret: accessClientSecret,
            bridgeToken: token
        )
        credentialsLoaded = true
    }

    private func configureService(for mode: AppMode, bridgeTokenOverride: String? = nil) {
        bridge?.stop()
        bridge = nil
        switch mode {
        case .bridge:
            let localService = serviceFactory.makeBridgeService()
            operations.replaceService(localService)
            let token = bridgeTokenOverride ?? bridgeToken
            guard !token.isEmpty else {
                setError("Could not create a bridge token in Keychain.", source: .configuration)
                return
            }
            let server = serviceFactory.makeBridgeServer(localService, token)
            server.onStateChange = { [weak self] newState in
                self?.bridgeState = newState
            }
            server.start(port: port)
            bridge = server
            if errorSource == .configuration { clearError() }
        case .remote:
            do {
                let configuration = try RemoteConfiguration(
                    endpoint: endpoint,
                    accessClientID: accessClientID,
                    accessClientSecret: accessClientSecret,
                    bridgeToken: bridgeToken
                )
                operations.replaceService(serviceFactory.makeRemoteService(configuration))
                connectionState = .idle
                if errorSource == .configuration { clearError() }
            } catch {
                operations.replaceService(nil)
                connectionState = .idle
                setError(error.localizedDescription, source: .configuration)
            }
        }
    }

    private func perform(_ request: RPCRequest) async -> Bool {
        let outcome = await operations.execute(request) { [weak self] outcome in
            self?.apply(outcome, source: .mutation, clearAllErrorsOnSuccess: true)
        }
        return outcome.succeeded
    }

    private func apply(
        _ outcome: ReminderOperationCoordinator.Outcome,
        source: ErrorSource,
        clearAllErrorsOnSuccess: Bool
    ) {
        switch outcome {
        case .success(let snapshot):
            self.snapshot = snapshot
            connectionState = .connected
            if clearAllErrorsOnSuccess || errorSource == source {
                clearError()
            }
        case .failure(let message):
            connectionState = .failed(message)
            setError(message, source: source)
        case .unavailable:
            connectionState = .idle
            setError("Finish configuring the remote connection in Settings.", source: .configuration)
        case .superseded:
            break
        }
    }

    private func setError(_ message: String, source: ErrorSource) {
        connectionState = .failed(message)
        errorMessage = message
        errorSource = source
    }

    private func clearError() {
        errorMessage = nil
        errorSource = nil
    }

    private func sortReminders(_ lhs: ReminderRecord, _ rhs: ReminderRecord) -> Bool {
        switch (lhs.due?.date(), rhs.due?.date()) {
        case let (left?, right?) where left != right:
            return left < right
        default:
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }
}
