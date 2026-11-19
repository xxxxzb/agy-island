import Foundation
import Combine

@MainActor
final class CapsuleService: ObservableObject {
    @Published var context: CapsuleContext?
    @Published var isConnected: Bool = false
    @Published var currentPort: Int?
    @Published var now: Date = Date()

    private let logPath: String
    private var pollTimer: Timer?
    private var clockTimer: Timer?
    private var isFetching = false

    private let session: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 1.2
        cfg.timeoutIntervalForResource = 1.5
        return URLSession(configuration: cfg)
    }()

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        self.logPath = "\(home)/.gemini/antigravity/sidecar_data/agy-capsule/agy_capsule/logs/sidecar.log"
    }

    func start() {
        refreshPortFromLog()
        Task { await fetchOnce() }

        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.fetchOnce()
            }
        }

        clockTimer?.invalidate()
        clockTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.now = Date()
            }
        }
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
        clockTimer?.invalidate()
        clockTimer = nil
    }

    func refreshNow() {
        refreshPortFromLog()
        Task { await fetchOnce() }
    }

    private func refreshPortFromLog() {
        guard let content = try? String(contentsOfFile: logPath, encoding: .utf8) else {
            return
        }
        let lines = content.split(separator: "\n", omittingEmptySubsequences: true)
        for line in lines.reversed() {
            if let range = line.range(of: "listening on 127.0.0.1:") {
                let portStr = line[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
                if let port = Int(portStr), port > 0 {
                    currentPort = port
                    return
                }
            }
        }
    }

    private func fetchOnce() async {
        if isFetching { return }
        isFetching = true
        defer { isFetching = false }

        if currentPort == nil {
            refreshPortFromLog()
        }
        guard let port = currentPort,
              let url = URL(string: "http://127.0.0.1:\(port)/api/context") else {
            isConnected = false
            return
        }

        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                isConnected = false
                refreshPortFromLog()
                return
            }
            let decoded = try JSONDecoder().decode(CapsuleContext.self, from: data)
            self.context = decoded
            self.isConnected = true
            self.now = Date()
        } catch {
            self.isConnected = false
            refreshPortFromLog()
        }
    }
}
