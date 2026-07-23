import Foundation
import XCTest

@MainActor
final class AppStateTests: XCTestCase {
    func testFailedMutationReturnsFalseAndBackgroundRefreshPreservesItsError() async {
        let suiteName = "TaskFerryTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(AppMode.remote.rawValue, forKey: AppPreferences.mode)
        defaults.set("https://example.com", forKey: AppPreferences.endpoint)
        let credentials = InMemoryCredentialStore(values: ["bridge-token": "TEST-TOKEN"])
        let service = MutationFailingService()
        let factory = ReminderServiceFactory(
            makeBridgeService: { service },
            makeRemoteService: { _ in service },
            makeBridgeServer: { BridgeServer(operations: $0, token: $1) }
        )
        let state = AppState(
            isDemo: false,
            defaults: defaults,
            credentialStore: credentials,
            serviceFactory: factory
        )
        await state.start()

        let mutationSucceeded = await state.createList(title: "Will fail")
        XCTAssertFalse(mutationSucceeded)
        XCTAssertEqual(state.errorMessage, "Mutation failed")

        let refreshSucceeded = await state.refresh(showLoadingIndicator: false)
        XCTAssertTrue(refreshSucceeded)
        XCTAssertEqual(state.errorMessage, "Mutation failed")
    }

    func testCredentialReadsAreDeferredOffTheMainThread() async {
        let suiteName = "TaskFerryTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(AppMode.remote.rawValue, forKey: AppPreferences.mode)
        defaults.set("https://example.com", forKey: AppPreferences.endpoint)
        let credentials = InMemoryCredentialStore(values: ["bridge-token": "TEST-TOKEN"])
        let service = MutationFailingService()
        let factory = ReminderServiceFactory(
            makeBridgeService: { service },
            makeRemoteService: { _ in service },
            makeBridgeServer: { BridgeServer(operations: $0, token: $1) }
        )
        let state = AppState(
            isDemo: false,
            defaults: defaults,
            credentialStore: credentials,
            serviceFactory: factory
        )

        XCTAssertEqual(state.bridgeToken, "")
        XCTAssertEqual(credentials.readCount, 0)

        await state.start()

        XCTAssertEqual(state.bridgeToken, "TEST-TOKEN")
        XCTAssertEqual(credentials.readCount, 3)
        XCTAssertFalse(credentials.readOccurredOnMainThread)
    }
}

@MainActor
private final class MutationFailingService: ReminderService {
    func execute(_ request: RPCRequest) async throws -> ReminderSnapshot {
        if request.operation != .snapshot {
            throw ReminderServiceError.message("Mutation failed")
        }
        return .empty
    }
}

private final class InMemoryCredentialStore: CredentialStore, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: String]
    private var reads = 0
    private var mainThreadRead = false

    init(values: [String: String]) {
        self.values = values
    }

    func string(for account: String) -> String {
        lock.withLock {
            reads += 1
            mainThreadRead = mainThreadRead || Thread.isMainThread
            return values[account] ?? ""
        }
    }

    func set(_ value: String, for account: String) throws {
        lock.withLock { values[account] = value }
    }

    func randomToken() throws -> String {
        "TEST-TOKEN"
    }

    var readCount: Int {
        lock.withLock { reads }
    }

    var readOccurredOnMainThread: Bool {
        lock.withLock { mainThreadRead }
    }
}
