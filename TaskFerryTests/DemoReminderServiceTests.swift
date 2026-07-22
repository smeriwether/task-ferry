import XCTest
@MainActor
final class DemoReminderServiceTests: XCTestCase {
    func testMutationReturnsAuthoritativeSnapshot() async throws {
        let service = DemoReminderService()
        let original = try await service.execute(.snapshot)
        let listID = try XCTUnwrap(original.lists.first?.id)

        let updated = try await service.execute(RPCRequest(
            operation: .upsertReminder,
            title: "A newly added reminder",
            listID: listID
        ))

        XCTAssertTrue(updated.reminders.contains { $0.title == "A newly added reminder" })
    }

    func testCompletingReminderRemovesItFromSnapshot() async throws {
        let service = DemoReminderService()
        let original = try await service.execute(.snapshot)
        let reminder = try XCTUnwrap(original.reminders.first)

        let updated = try await service.execute(RPCRequest(
            operation: .setCompleted,
            id: reminder.id,
            completed: true
        ))

        XCTAssertFalse(updated.reminders.contains { $0.id == reminder.id })
    }
}
