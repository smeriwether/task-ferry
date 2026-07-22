import Foundation

@MainActor
protocol ReminderService: AnyObject {
    func execute(_ request: RPCRequest) async throws -> ReminderSnapshot
}
