import Foundation
import XCTest

final class CredentialStoreTests: XCTestCase {
    func testAtomicSetRollsBackEarlierValuesAfterFailure() {
        let store = FailingCredentialStore(
            values: ["first": "old-first", "second": "old-second"],
            failingAccount: "second"
        )

        XCTAssertThrowsError(try store.setAtomically([
            ("first", "new-first"),
            ("second", "new-second")
        ]))
        XCTAssertEqual(store.string(for: "first"), "old-first")
        XCTAssertEqual(store.string(for: "second"), "old-second")
    }
}

private final class FailingCredentialStore: CredentialStore, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: String]
    private let failingAccount: String
    private var hasFailed = false

    init(values: [String: String], failingAccount: String) {
        self.values = values
        self.failingAccount = failingAccount
    }

    func string(for account: String) -> String {
        lock.withLock { values[account] ?? "" }
    }

    func set(_ value: String, for account: String) throws {
        try lock.withLock {
            if account == failingAccount, !hasFailed {
                hasFailed = true
                throw ReminderServiceError.message("Expected write failure")
            }
            values[account] = value
        }
    }

    func randomToken() throws -> String {
        "TEST-TOKEN"
    }
}
