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

    func testRejectsReminderForUnknownListLikeEventKitService() async throws {
        let service = DemoReminderService()

        do {
            _ = try await service.execute(RPCRequest(
                operation: .upsertReminder,
                title: "Orphaned reminder",
                listID: "missing-list"
            ))
            XCTFail("Expected the demo service to reject an unknown list")
        } catch {
            XCTAssertEqual(error.localizedDescription, "A reminder needs a title and editable list.")
        }
    }

    func testRejectsUpdateForMissingReminderLikeEventKitService() async throws {
        let service = DemoReminderService()
        let snapshot = try await service.execute(.snapshot)
        let listID = try XCTUnwrap(snapshot.lists.first?.id)

        do {
            _ = try await service.execute(RPCRequest(
                operation: .upsertReminder,
                id: "missing-reminder",
                title: "Updated reminder",
                listID: listID
            ))
            XCTFail("Expected the demo service to reject a missing reminder")
        } catch {
            XCTAssertEqual(error.localizedDescription, "That reminder changed elsewhere. Refresh and try again.")
        }
    }
}
