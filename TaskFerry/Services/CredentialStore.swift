import Foundation

protocol CredentialStore: Sendable {
    func string(for account: String) -> String
    func set(_ value: String, for account: String) throws
    func randomToken() throws -> String
}

extension CredentialStore {
    func setAtomically(_ values: [(account: String, value: String)]) throws {
        let originals = values.map { (account: $0.account, value: string(for: $0.account)) }
        do {
            for value in values {
                try set(value.value, for: value.account)
            }
        } catch {
            var rollbackFailed = false
            for original in originals.reversed() {
                do {
                    try set(original.value, for: original.account)
                } catch {
                    rollbackFailed = true
                }
            }
            if rollbackFailed {
                throw ReminderServiceError.message("Could not save or fully restore the previous Keychain credentials.")
            }
            throw error
        }
    }
}
