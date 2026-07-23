import Foundation

struct RemoteConfiguration: Equatable, Sendable {
    let endpoint: URL
    let accessClientID: String
    let accessClientSecret: String
    let bridgeToken: String

    init(endpoint: String, accessClientID: String, accessClientSecret: String, bridgeToken: String) throws {
        let endpoint = endpoint.trimmed
        let accessClientID = accessClientID.trimmed
        let accessClientSecret = accessClientSecret.trimmed
        let bridgeToken = bridgeToken.trimmed

        guard var components = URLComponents(string: endpoint),
              components.scheme?.lowercased() == "https",
              let host = components.host,
              !host.isEmpty,
              components.user == nil,
              components.password == nil,
              components.query == nil,
              components.fragment == nil else {
            throw ReminderServiceError.message("Enter a complete HTTPS server URL without credentials, a query, or a fragment.")
        }
        guard !bridgeToken.isEmpty else {
            throw ReminderServiceError.message("Enter the bridge token from the Reminders bridge Mac.")
        }
        guard accessClientID.isEmpty == accessClientSecret.isEmpty else {
            throw ReminderServiceError.message("Enter both Cloudflare Access credentials, or leave both blank.")
        }

        components.scheme = "https"
        while components.path.count > 1 && components.path.hasSuffix("/") {
            components.path.removeLast()
        }
        guard let normalizedEndpoint = components.url else {
            throw ReminderServiceError.message("The server URL could not be normalized.")
        }

        self.endpoint = normalizedEndpoint
        self.accessClientID = accessClientID
        self.accessClientSecret = accessClientSecret
        self.bridgeToken = bridgeToken
    }
}
