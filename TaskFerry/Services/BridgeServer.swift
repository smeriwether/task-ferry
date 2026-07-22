import Foundation
import Network

final class BridgeServer {
    enum State: Equatable {
        case stopped
        case starting
        case running(UInt16)
        case failed(String)
    }

    private let service: any ReminderService
    private let token: String
    private let queue = DispatchQueue(label: "TaskFerry.Bridge")
    private var listener: NWListener?
    var onStateChange: ((State) -> Void)?
    private(set) var state: State = .stopped {
        didSet { onStateChange?(state) }
    }

    init(service: any ReminderService, token: String) {
        self.service = service
        self.token = token
    }

    func start(port: UInt16) {
        stop()
        do {
            let parameters = NWParameters.tcp
            parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port) ?? 8788)
            let listener = try NWListener(using: parameters)
            listener.newConnectionHandler = { [weak self] connection in
                self?.receive(connection: connection, data: Data())
                connection.start(queue: self?.queue ?? .global())
            }
            listener.stateUpdateHandler = { [weak self] newState in
                switch newState {
                case .ready:
                    self?.state = .running(port)
                case .failed(let error):
                    self?.state = .failed(error.localizedDescription)
                default:
                    break
                }
            }
            state = .starting
            listener.start(queue: queue)
            self.listener = listener
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        state = .stopped
    }

    private func receive(connection: NWConnection, data: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] chunk, _, isComplete, error in
            guard let self else { return }
            var accumulated = data
            if let chunk { accumulated.append(chunk) }
            if accumulated.count > 128 * 1024 {
                self.respond(connection, status: 413, response: RPCResponse(error: "Request too large."))
                return
            }
            if let request = HTTPRequest.parse(accumulated) {
                self.handle(request, connection: connection)
            } else if error != nil || isComplete {
                self.respond(connection, status: 400, response: RPCResponse(error: "Malformed request."))
            } else {
                self.receive(connection: connection, data: accumulated)
            }
        }
    }

    private func handle(_ request: HTTPRequest, connection: NWConnection) {
        guard request.method == "POST", request.path == "/v1/rpc" else {
            respond(connection, status: 404, response: RPCResponse(error: "Not found."))
            return
        }
        guard request.headers["content-type"]?.lowercased().hasPrefix("application/json") == true else {
            respond(connection, status: 415, response: RPCResponse(error: "JSON required."))
            return
        }
        guard request.headers["authorization"] == "Bearer \(token)" else {
            respond(connection, status: 401, response: RPCResponse(error: "Unauthorized."))
            return
        }

        do {
            let rpc = try JSONDecoder().decode(RPCRequest.self, from: request.body)
            Task { @MainActor [weak self] in
                guard let self else { return }
                do {
                    let snapshot = try await service.execute(rpc)
                    respond(connection, status: 200, response: RPCResponse(snapshot: snapshot))
                } catch {
                    respond(connection, status: 400, response: RPCResponse(error: error.localizedDescription))
                }
            }
        } catch {
            respond(connection, status: 400, response: RPCResponse(error: "Invalid JSON."))
        }
    }

    private func respond(_ connection: NWConnection, status: Int, response: RPCResponse) {
        let body = (try? JSONEncoder().encode(response)) ?? Data("{}".utf8)
        let reason = status == 200 ? "OK" : "Error"
        let header = "HTTP/1.1 \(status) \(reason)\r\nContent-Type: application/json\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        var data = Data(header.utf8)
        data.append(body)
        connection.send(content: data, completion: .contentProcessed { _ in connection.cancel() })
    }
}

struct HTTPRequest {
    var method: String
    var path: String
    var headers: [String: String]
    var body: Data

    static func parse(_ data: Data) -> HTTPRequest? {
        let delimiter = Data("\r\n\r\n".utf8)
        guard let range = data.range(of: delimiter),
              let head = String(data: data[..<range.lowerBound], encoding: .utf8) else {
            return nil
        }
        let lines = head.components(separatedBy: "\r\n")
        guard let first = lines.first else { return nil }
        let requestLine = first.split(separator: " ")
        guard requestLine.count == 3 else { return nil }

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            let parts = line.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { return nil }
            headers[String(parts[0]).lowercased()] = parts[1].trimmingCharacters(in: .whitespaces)
        }
        guard headers["transfer-encoding"] == nil,
              let lengthText = headers["content-length"],
              let length = Int(lengthText),
              length >= 0,
              length <= 64 * 1024 else {
            return nil
        }
        let bodyStart = range.upperBound
        guard data.count >= bodyStart + length else { return nil }
        return HTTPRequest(
            method: String(requestLine[0]),
            path: String(requestLine[1]),
            headers: headers,
            body: Data(data[bodyStart..<(bodyStart + length)])
        )
    }
}
