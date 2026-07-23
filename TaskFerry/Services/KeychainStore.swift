import Foundation
import Security

struct KeychainStore: CredentialStore {
    private static let service = "com.merimerimeri.TaskFerry"
    private static let tokenAlphabet = Array("23456789ABCDEFGHJKMNPQRSTVWXYZ")

    func string(for account: String) -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return ""
        }
        return value
    }

    func set(_ value: String, for account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: account
        ]
        if value.isEmpty {
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw ReminderServiceError.message("Could not remove the credential from Keychain.")
            }
            return
        }

        let attributes = [kSecValueData as String: Data(value.utf8)]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw ReminderServiceError.message("Could not update the credential in Keychain.")
        }

        var item = query
        item[kSecValueData as String] = Data(value.utf8)
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw ReminderServiceError.message("Could not save the credential in Keychain.")
        }
    }

    func randomToken() throws -> String {
        var characters: [Character] = []
        while characters.count < 24 {
            var bytes = [UInt8](repeating: 0, count: 32)
            guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
                throw ReminderServiceError.message("Could not create a secure bridge token.")
            }
            for byte in bytes where byte < 240 {
                characters.append(Self.tokenAlphabet[Int(byte) % Self.tokenAlphabet.count])
                if characters.count == 24 { break }
            }
        }
        return stride(from: 0, to: characters.count, by: 4)
            .map { String(characters[$0..<min($0 + 4, characters.count)]) }
            .joined(separator: "-")
    }
}
