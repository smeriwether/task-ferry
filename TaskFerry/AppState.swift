import Foundation
import Observation

@MainActor
@Observable
final class AppState {
    enum ConnectionState: Equatable {
        case idle
        case loading
        case connected
        case failed(String)
    }

    private enum DefaultsKey {
        static let mode = "mode"
        static let endpoint = "endpoint"
        static let port = "port"
    }

    private enum SecretKey {
        static let accessClientID = "access-client-id"
        static let accessClientSecret = "access-client-secret"
        static let bridgeToken = "bridge-token"
    }

    var mode: AppMode?
    var snapshot = ReminderSnapshot.empty
    var selectedView = SmartView.today
    var connectionState = ConnectionState.idle
    var bridgeState = BridgeServer.State.stopped
    var errorMessage: String?

    @ObservationIgnored private var service: (any ReminderService)?
    @ObservationIgnored private var bridge: BridgeServer?
    @ObservationIgnored private var isStarted = false
    @ObservationIgnored private let isDemo: Bool

    var endpoint: String {
        get { UserDefaults.standard.string(forKey: DefaultsKey.endpoint) ?? "https://reminders.merimerimeri.com" }
        set { UserDefaults.standard.set(newValue, forKey: DefaultsKey.endpoint) }
    }

    var port: UInt16 {
        get {
            let stored = UserDefaults.standard.integer(forKey: DefaultsKey.port)
            return stored > 0 ? UInt16(stored) : 8788
        }
        set { UserDefaults.standard.set(Int(newValue), forKey: DefaultsKey.port) }
    }

    var accessClientID: String { KeychainStore.string(for: SecretKey.accessClientID) }
    var accessClientSecret: String { KeychainStore.string(for: SecretKey.accessClientSecret) }
    var bridgeToken: String { KeychainStore.string(for: SecretKey.bridgeToken) }

    init() {
        isDemo = ProcessInfo.processInfo.environment["TASK_FERRY_DEMO"] == "1"
        if isDemo {
            mode = .remote
            service = DemoReminderService()
            isStarted = true
            connectionState = .connected
        } else if let value = UserDefaults.standard.string(forKey: DefaultsKey.mode),
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

    var defaultListID: String? { snapshot.lists.first?.id }

    func reminders(in listID: String) -> [ReminderRecord] {
        snapshot.reminders.filter { $0.listID == listID }.sorted(by: sortReminders)
    }

    func list(for id: String) -> ReminderListRecord? {
        snapshot.lists.first { $0.id == id }
    }

    func chooseMode(_ mode: AppMode) {
        self.mode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: DefaultsKey.mode)
        isStarted = true
        configureService(for: mode)
    }

    func start() {
        guard !isStarted, let mode else { return }
        isStarted = true
        configureService(for: mode)
    }

    func resetMode() {
        bridge?.stop()
        bridge = nil
        bridgeState = .stopped
        service = nil
        isStarted = false
        mode = nil
        snapshot = .empty
        connectionState = .idle
        UserDefaults.standard.removeObject(forKey: DefaultsKey.mode)
    }

    func refresh() async {
        start()
        guard let service else { return }
        connectionState = .loading
        do {
            snapshot = try await service.execute(.snapshot)
            connectionState = .connected
        } catch {
            connectionState = .failed(error.localizedDescription)
            errorMessage = error.localizedDescription
        }
    }

    func createReminder(title: String, listID: String, due: ReminderDue?) async {
        await perform(RPCRequest(operation: .upsertReminder, title: title, listID: listID, due: due))
    }

    func updateReminder(_ reminder: ReminderRecord, title: String, listID: String, due: ReminderDue?) async {
        await perform(RPCRequest(operation: .upsertReminder, id: reminder.id, title: title, listID: listID, due: due))
    }

    func complete(_ reminder: ReminderRecord) async {
        await perform(RPCRequest(operation: .setCompleted, id: reminder.id, completed: true))
    }

    func deleteReminder(_ reminder: ReminderRecord) async {
        await perform(RPCRequest(operation: .deleteReminder, id: reminder.id))
    }

    func createList(title: String) async {
        await perform(RPCRequest(operation: .upsertList, title: title))
    }

    func renameList(_ list: ReminderListRecord, title: String) async {
        await perform(RPCRequest(operation: .upsertList, id: list.id, title: title))
    }

    func deleteList(_ list: ReminderListRecord) async {
        await perform(RPCRequest(operation: .deleteList, id: list.id))
    }

    func saveRemoteConfiguration(endpoint: String, clientID: String, clientSecret: String, bridgeToken: String) throws {
        self.endpoint = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        try KeychainStore.set(clientID.trimmingCharacters(in: .whitespacesAndNewlines), for: SecretKey.accessClientID)
        try KeychainStore.set(clientSecret.trimmingCharacters(in: .whitespacesAndNewlines), for: SecretKey.accessClientSecret)
        try KeychainStore.set(bridgeToken.trimmingCharacters(in: .whitespacesAndNewlines), for: SecretKey.bridgeToken)
        if mode == .remote { configureService(for: .remote) }
    }

    func regenerateBridgeToken() throws {
        try KeychainStore.set(KeychainStore.randomToken(), for: SecretKey.bridgeToken)
        if mode == .bridge { configureService(for: .bridge) }
    }

    private func configureService(for mode: AppMode) {
        bridge?.stop()
        bridge = nil
        switch mode {
        case .bridge:
            let localService = EventKitReminderService()
            service = localService
            do {
                var token = bridgeToken
                if token.isEmpty {
                    token = try KeychainStore.randomToken()
                    try KeychainStore.set(token, for: SecretKey.bridgeToken)
                }
                let server = BridgeServer(service: localService, token: token)
                server.onStateChange = { [weak self] newState in
                    Task { @MainActor in self?.bridgeState = newState }
                }
                server.start(port: port)
                bridge = server
            } catch {
                connectionState = .failed(error.localizedDescription)
                errorMessage = error.localizedDescription
            }
        case .remote:
            guard let url = URL(string: endpoint), !bridgeToken.isEmpty else {
                service = nil
                connectionState = .idle
                return
            }
            service = RemoteReminderService(
                endpoint: url,
                accessClientID: accessClientID,
                accessClientSecret: accessClientSecret,
                bridgeToken: bridgeToken
            )
        }
    }

    private func perform(_ request: RPCRequest) async {
        guard let service else {
            errorMessage = "Finish configuring the remote connection in Settings."
            return
        }
        do {
            snapshot = try await service.execute(request)
            connectionState = .connected
        } catch {
            connectionState = .failed(error.localizedDescription)
            errorMessage = error.localizedDescription
        }
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
