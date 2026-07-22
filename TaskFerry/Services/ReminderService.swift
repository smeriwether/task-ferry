import Foundation

@MainActor
protocol ReminderService: AnyObject {
    func execute(_ request: RPCRequest) async throws -> ReminderSnapshot
}

@MainActor
struct ReminderServiceFactory {
    var makeBridgeService: () -> any ReminderService
    var makeRemoteService: (RemoteConfiguration) -> any ReminderService
    var makeBridgeServer: (any ReminderService, String) -> BridgeServer

    static let live = ReminderServiceFactory(
        makeBridgeService: { EventKitReminderService() },
        makeRemoteService: { RemoteReminderService(configuration: $0) },
        makeBridgeServer: { BridgeServer(service: $0, token: $1) }
    )
}
