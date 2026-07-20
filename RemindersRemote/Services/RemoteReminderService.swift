import Foundation

@MainActor
final class RemoteReminderService: ReminderService {
    private let endpoint: URL
    private let accessClientID: String
    private let accessClientSecret: String
    private let bridgeToken: String
    private let session: URLSession

    init(endpoint: URL, accessClientID: String, accessClientSecret: String, bridgeToken: String) {
        self.endpoint = endpoint
        self.accessClientID = accessClientID
        self.accessClientSecret = accessClientSecret
        self.bridgeToken = bridgeToken
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: configuration)
    }

    func execute(_ rpc: RPCRequest) async throws -> ReminderSnapshot {
        let url = endpoint.appending(path: "v1/rpc")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(bridgeToken)", forHTTPHeaderField: "Authorization")
        if !accessClientID.isEmpty {
            request.setValue(accessClientID, forHTTPHeaderField: "CF-Access-Client-Id")
        }
        if !accessClientSecret.isEmpty {
            request.setValue(accessClientSecret, forHTTPHeaderField: "CF-Access-Client-Secret")
        }
        request.httpBody = try JSONEncoder().encode(rpc)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ReminderServiceError.message("The bridge returned an invalid response.")
        }
        guard http.statusCode == 200 else {
            throw ReminderServiceError.message("The bridge returned HTTP \(http.statusCode).")
        }
        let decoded = try JSONDecoder().decode(RPCResponse.self, from: data)
        if let error = decoded.error {
            throw ReminderServiceError.message(error)
        }
        guard let snapshot = decoded.snapshot else {
            throw ReminderServiceError.message("The bridge response did not include reminders.")
        }
        return snapshot
    }
}
