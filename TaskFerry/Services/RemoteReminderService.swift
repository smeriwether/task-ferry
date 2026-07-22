import Foundation

@MainActor
final class RemoteReminderService: ReminderService {
    private let configuration: RemoteConfiguration
    private let session: URLSession

    init(configuration: RemoteConfiguration, session: URLSession? = nil) {
        self.configuration = configuration
        self.session = session ?? Self.makeSession()
    }

    func execute(_ rpc: RPCRequest) async throws -> ReminderSnapshot {
        let url = configuration.endpoint.appending(path: "v1/rpc")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(configuration.bridgeToken)", forHTTPHeaderField: "Authorization")
        if !configuration.accessClientID.isEmpty {
            request.setValue(configuration.accessClientID, forHTTPHeaderField: "CF-Access-Client-Id")
        }
        if !configuration.accessClientSecret.isEmpty {
            request.setValue(configuration.accessClientSecret, forHTTPHeaderField: "CF-Access-Client-Secret")
        }
        request.httpBody = try JSONEncoder().encode(rpc)

        let (data, response) = try await session.data(for: request)
        return try Self.decode(data: data, response: response)
    }

    static func decode(data: Data, response: URLResponse) throws -> ReminderSnapshot {
        guard let http = response as? HTTPURLResponse else {
            throw ReminderServiceError.message("The bridge returned an invalid response.")
        }
        let decoded = try? JSONDecoder().decode(RPCResponse.self, from: data)
        if let error = decoded?.error {
            throw ReminderServiceError.message(error)
        }
        guard http.statusCode == 200 else {
            throw ReminderServiceError.message("The bridge returned HTTP \(http.statusCode).")
        }
        guard let decoded else {
            throw ReminderServiceError.message("The bridge returned invalid JSON.")
        }
        guard let snapshot = decoded.snapshot else {
            throw ReminderServiceError.message("The bridge response did not include reminders.")
        }
        return snapshot
    }

    private static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        configuration.httpMaximumConnectionsPerHost = 2
        return URLSession(configuration: configuration)
    }
}
