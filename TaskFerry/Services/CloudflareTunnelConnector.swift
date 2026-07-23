import Foundation

@MainActor
final class CloudflareTunnelConnector {
    var onStateChange: ((CloudflareConnectorState) -> Void)?

    private(set) var state = CloudflareConnectorState.notConfigured
    private var process: Process?
    private var outputPipe: Pipe?
    private var restartTask: Task<Void, Never>?
    private var tunnelToken: String?
    private var shouldRestart = false
    private var restartAttempt = 0
    private let executableURL: URL?

    init(executableURL: URL? = Bundle.main.url(forAuxiliaryExecutable: "cloudflared")) {
        self.executableURL = executableURL
    }

    func start(token: String) {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            stop(nextState: .notConfigured)
            return
        }
        if tunnelToken == trimmed, process?.isRunning == true { return }
        stop(nextState: .stopped)
        tunnelToken = trimmed
        shouldRestart = true
        restartAttempt = 0
        launch()
    }

    func stop() {
        stop(nextState: tunnelToken == nil ? .notConfigured : .stopped)
        tunnelToken = nil
    }

    static var arguments: [String] {
        [
            "tunnel",
            "--no-autoupdate",
            "--metrics", "127.0.0.1:0",
            "--loglevel", "info",
            "--output", "json",
            "run"
        ]
    }

    private func launch() {
        guard shouldRestart, let tunnelToken else { return }
        guard let executableURL, FileManager.default.isExecutableFile(atPath: executableURL.path) else {
            shouldRestart = false
            updateState(.failed("This build does not include the Cloudflare connector."))
            return
        }

        updateState(.starting)
        let process = Process()
        let pipe = Pipe()
        process.executableURL = executableURL
        process.arguments = Self.arguments
        var environment = ProcessInfo.processInfo.environment
        environment["TUNNEL_TOKEN"] = tunnelToken
        environment["NO_AUTOUPDATE"] = "true"
        process.environment = environment
        process.standardOutput = pipe
        process.standardError = pipe

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let output = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor [weak self] in
                self?.observe(output)
            }
        }
        process.terminationHandler = { [weak self] terminatedProcess in
            Task { @MainActor [weak self] in
                self?.processDidTerminate(status: terminatedProcess.terminationStatus)
            }
        }

        do {
            try process.run()
            self.process = process
            outputPipe = pipe
        } catch {
            pipe.fileHandleForReading.readabilityHandler = nil
            updateState(.failed("The Cloudflare connector could not start."))
            scheduleRestart()
        }
    }

    private func observe(_ output: String) {
        if output.localizedCaseInsensitiveContains("registered tunnel connection") {
            restartAttempt = 0
            updateState(.connected)
        }
    }

    private func processDidTerminate(status: Int32) {
        outputPipe?.fileHandleForReading.readabilityHandler = nil
        outputPipe = nil
        process = nil
        guard shouldRestart else { return }
        updateState(.failed("The Cloudflare connector stopped (status \(status)). Retrying…"))
        scheduleRestart()
    }

    private func scheduleRestart() {
        guard shouldRestart else { return }
        restartTask?.cancel()
        restartAttempt += 1
        let delay = min(30, 1 << min(restartAttempt - 1, 5))
        restartTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .seconds(delay))
            } catch {
                return
            }
            self?.launch()
        }
    }

    private func stop(nextState: CloudflareConnectorState) {
        shouldRestart = false
        restartTask?.cancel()
        restartTask = nil
        outputPipe?.fileHandleForReading.readabilityHandler = nil
        outputPipe = nil
        if process?.isRunning == true {
            process?.terminate()
        }
        process = nil
        updateState(nextState)
    }

    private func updateState(_ state: CloudflareConnectorState) {
        guard self.state != state else { return }
        self.state = state
        onStateChange?(state)
    }
}
