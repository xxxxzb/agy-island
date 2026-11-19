import Foundation
import Combine
import SQLite3

private final class LocalhostTLSDelegate: NSObject, URLSessionDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        let host = challenge.protectionSpace.host
        if (host == "127.0.0.1" || host == "localhost"),
           challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let trust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
            return
        }
        completionHandler(.performDefaultHandling, nil)
    }
}

@MainActor
final class CapsuleService: ObservableObject {
    @Published var context: CapsuleContext?
    @Published var isConnected: Bool = false
    @Published var currentPort: Int?
    @Published var now: Date = Date()
    @Published var pollInterval: TimeInterval = {
        let saved = UserDefaults.standard.double(forKey: "pollInterval")
        return saved > 0 ? saved : 1.5
    }()

    private static let pollIntervals: [TimeInterval] = [1.0, 1.5, 3.0, 5.0, 10.0]

    private let dbPath: String
    private var csrfToken: String?
    private var pollTimer: Timer?
    private var clockTimer: Timer?
    private var isFetching = false

    private let tlsDelegate = LocalhostTLSDelegate()
    private lazy var session: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 2.0
        cfg.timeoutIntervalForResource = 3.0
        return URLSession(configuration: cfg, delegate: tlsDelegate, delegateQueue: nil)
    }()

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        self.dbPath = "\(home)/.gemini/antigravity/conversation_summaries.db"
    }

    func start() {
        Task { await fetchOnce() }
        schedulePollTimer()

        clockTimer?.invalidate()
        clockTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.now = Date()
            }
        }
    }

    func cyclePollInterval() {
        let idx = Self.pollIntervals.firstIndex(where: { abs($0 - pollInterval) < 0.05 }) ?? 1
        let next = Self.pollIntervals[(idx + 1) % Self.pollIntervals.count]
        pollInterval = next
        UserDefaults.standard.set(next, forKey: "pollInterval")
        schedulePollTimer()
        Task { await fetchOnce() }
    }

    private func schedulePollTimer() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.fetchOnce()
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
        currentPort = nil
        csrfToken = nil
        Task { await fetchOnce() }
    }

    // MARK: - Direct Antigravity Language Server Discovery

    private func discoverLanguageServer() async -> (port: Int, csrf: String)? {
        let candidates: (pid: String, csrf: String, ports: [Int])? = await Task.detached(priority: .utility) {
            guard let psOut = Self.runProcess("/bin/ps", args: ["-eo", "pid,args"]) else { return nil }
            var foundPid: String?
            var foundCsrf: String?
            for rawLine in psOut.split(separator: "\n") {
                let line = String(rawLine)
                if line.contains("language_server"), line.contains("--csrf_token ") {
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    if let firstSpace = trimmed.firstIndex(of: " ") {
                        foundPid = String(trimmed[..<firstSpace])
                    }
                    if let range = line.range(of: "--csrf_token ") {
                        let rest = line[range.upperBound...]
                        foundCsrf = String(rest.prefix(while: { !$0.isWhitespace }))
                    }
                    if foundPid != nil && foundCsrf != nil { break }
                }
            }
            guard let pid = foundPid, let csrf = foundCsrf else { return nil }

            guard let lsofOut = Self.runProcess("/usr/sbin/lsof", args: ["-nP", "-a", "-iTCP", "-sTCP:LISTEN", "-p", pid]) else {
                return nil
            }
            var ports: [Int] = []
            for rawLine in lsofOut.split(separator: "\n") {
                let line = String(rawLine)
                if let colonIdx = line.range(of: "127.0.0.1:")?.upperBound {
                    let after = line[colonIdx...]
                    let portDigits = after.prefix(while: { $0.isNumber })
                    if let p = Int(portDigits), !ports.contains(p) {
                        ports.append(p)
                    }
                }
            }
            return (pid, csrf, ports)
        }.value

        guard let candidates else { return nil }

        for port in candidates.ports {
            if let _ = await callRPC(
                port: port,
                csrf: candidates.csrf,
                method: "GetUserStatus",
                body: ["metadata": ["ideName": "antigravity", "extensionName": "antigravity", "locale": "en"]]
            ) {
                return (port, candidates.csrf)
            }
        }
        return nil
    }

    nonisolated private static func runProcess(_ launchPath: String, args: [String]) -> String? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: launchPath)
        proc.arguments = args
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        do {
            try proc.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            proc.waitUntilExit()
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }

    // MARK: - SQLite Latest Conversation Query

    nonisolated private func latestConversationId() -> String? {
        var db: OpaquePointer?
        guard sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            if db != nil { sqlite3_close(db) }
            return nil
        }
        defer { sqlite3_close(db) }

        let sql = "SELECT conversation_id FROM conversation_summaries ORDER BY last_modified_time DESC LIMIT 1;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            return nil
        }
        defer { sqlite3_finalize(stmt) }

        if sqlite3_step(stmt) == SQLITE_ROW, let cStr = sqlite3_column_text(stmt, 0) {
            return String(cString: cStr)
        }
        return nil
    }

    // MARK: - RPC & Data Assembly

    private func callRPC(port: Int, csrf: String, method: String, body: [String: Any]) async -> [String: Any]? {
        guard let url = URL(string: "https://127.0.0.1:\(port)/exa.language_server_pb.LanguageServerService/\(method)") else {
            return nil
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(csrf, forHTTPHeaderField: "X-Codeium-Csrf-Token")
        req.setValue("1", forHTTPHeaderField: "Connect-Protocol-Version")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await session.data(for: req)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return nil
            }
            return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        } catch {
            return nil
        }
    }

    private func fetchOnce() async {
        if isFetching { return }
        isFetching = true
        defer { isFetching = false }

        if currentPort == nil || csrfToken == nil {
            if let discovered = await discoverLanguageServer() {
                currentPort = discovered.port
                csrfToken = discovered.csrf
            } else {
                isConnected = false
                return
            }
        }

        guard let port = currentPort, let csrf = csrfToken else {
            isConnected = false
            return
        }

        async let quotaSummaryTask = callRPC(
            port: port,
            csrf: csrf,
            method: "RetrieveUserQuotaSummary",
            body: [:]
        )
        let convId = await Task.detached(priority: .utility) { [dbPath = self.dbPath] () -> String? in
            var db: OpaquePointer?
            guard sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
                if db != nil { sqlite3_close(db) }
                return nil
            }
            defer { sqlite3_close(db) }
            let sql = "SELECT conversation_id FROM conversation_summaries ORDER BY last_modified_time DESC LIMIT 1;"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
            defer { sqlite3_finalize(stmt) }
            if sqlite3_step(stmt) == SQLITE_ROW, let cStr = sqlite3_column_text(stmt, 0) {
                return String(cString: cStr)
            }
            return nil
        }.value

        let trajDict: [String: Any]?
        if let convId {
            trajDict = await callRPC(
                port: port,
                csrf: csrf,
                method: "GetCascadeTrajectory",
                body: ["cascadeId": convId]
            )
        } else {
            trajDict = nil
        }

        let quotaSummary = await quotaSummaryTask
        var fallbackUserStatus: [String: Any]? = nil
        if quotaSummary == nil {
            fallbackUserStatus = await callRPC(
                port: port,
                csrf: csrf,
                method: "GetUserStatus",
                body: ["metadata": ["ideName": "antigravity", "extensionName": "antigravity", "locale": "en"]]
            )
            if fallbackUserStatus == nil {
                // Port or token may have changed after Antigravity restart
                currentPort = nil
                csrfToken = nil
                isConnected = false
                return
            }
        }

        let built = buildContext(quotaSummary: quotaSummary, fallbackUserStatus: fallbackUserStatus, trajectoryResponse: trajDict)
        self.context = built
        self.isConnected = true
        self.now = Date()
    }

    private func buildContext(
        quotaSummary: [String: Any]?,
        fallbackUserStatus: [String: Any]?,
        trajectoryResponse: [String: Any]?
    ) -> CapsuleContext {
        let quotaGroups = parseQuotaGroups(quotaSummary: quotaSummary, fallbackUserStatus: fallbackUserStatus)

        let steps = ((trajectoryResponse?["trajectory"] as? [String: Any])?["steps"] as? [[String: Any]]) ?? []
        var hasActiveStep = false
        if let last = steps.last, let status = last["status"] as? String {
            hasActiveStep = status.contains("RUNNING") || status.contains("GENERATING") || status.contains("PENDING")
        }

        var turn0Tokens = 0
        var totalOutputTokens = 0
        var totalThinkingTokens = 0

        var lastCachedIn = 0
        var lastUncachedIn = 0
        var lastOutput = 0
        var lastThinking = 0
        var lastReply = 0
        var lastDuration: Double?
        var lastTps: Double?
        var lastStepEpochMs: Double?
        var lastModelId = ""
        var errorInfo = RequestErrorInfo(kind: "none", diagnostic: nil, retryAfterSec: nil)

        for step in steps {
            let md = step["metadata"] as? [String: Any]
            if let usage = md?["modelUsage"] as? [String: Any] {
                let inTok = parseInt(usage["inputTokens"])
                let cacheTok = parseInt(usage["cacheReadTokens"])
                let outTok = parseInt(usage["outputTokens"])
                let thinkTok = parseInt(usage["thinkingOutputTokens"])
                let replyTok = parseInt(usage["responseOutputTokens"])

                if turn0Tokens == 0 && (inTok + cacheTok) > 0 {
                    turn0Tokens = inTok + cacheTok
                }
                totalOutputTokens += outTok
                totalThinkingTokens += thinkTok

                lastCachedIn = cacheTok
                lastUncachedIn = inTok
                lastOutput = outTok
                lastThinking = thinkTok
                lastReply = replyTok
                lastModelId = (usage["model"] as? String) ?? lastModelId

                let created = parseISO(md?["createdAt"] as? String)
                let completed = parseISO(md?["completedAt"] as? String)
                if let c = completed {
                    lastStepEpochMs = c.timeIntervalSince1970 * 1000.0
                } else if let s = created {
                    lastStepEpochMs = s.timeIntervalSince1970 * 1000.0
                }
                if let s = created, let c = completed {
                    let dur = max(0.05, c.timeIntervalSince(s))
                    lastDuration = dur
                    if outTok > 0 {
                        lastTps = Double(outTok) / dur
                    }
                }
            }
        }

        if let last = steps.last,
           let status = last["status"] as? String,
           status.contains("ERROR") {
            errorInfo = RequestErrorInfo(kind: "请求失败", diagnostic: status, retryAfterSec: nil)
        }

        let contextTokens = lastCachedIn + lastUncachedIn + lastOutput
        let maxContextTokens = inferMaxContextTokens(modelId: lastModelId)

        let gen = GenerationInfo(
            ttft: nil,
            streaming: lastDuration,
            duration: lastDuration,
            output: lastOutput,
            reply: lastReply,
            thinking: lastThinking,
            tps: lastTps
        )
        let turnSpeed = TurnSpeedInfo(
            hasActiveStep: hasActiveStep,
            completedAtMs: lastStepEpochMs,
            generation: gen
        )

        return CapsuleContext(
            contextTokens: contextTokens,
            maxContextTokens: maxContextTokens,
            cachedIn: lastCachedIn,
            uncachedIn: lastUncachedIn,
            turn0Tokens: turn0Tokens,
            totalOutputTokens: totalOutputTokens,
            totalThinkingTokens: totalThinkingTokens,
            lastStepEpochMs: lastStepEpochMs,
            generation: gen,
            turnSpeed: turnSpeed,
            requestError: errorInfo,
            quotaGroups: quotaGroups,
            cloudPaygo: false
        )
    }

    private func parseQuotaGroups(quotaSummary: [String: Any]?, fallbackUserStatus: [String: Any]?) -> [QuotaGroup] {
        if let summary = quotaSummary,
           let resp = summary["response"] as? [String: Any],
           let rawGroups = resp["groups"] as? [[String: Any]] {
            var groups: [QuotaGroup] = []
            for g in rawGroups {
                guard let displayName = g["displayName"] as? String else { continue }
                let rawBuckets = (g["buckets"] as? [[String: Any]]) ?? []
                var buckets: [QuotaBucket] = []
                for b in rawBuckets {
                    guard let bucketId = b["bucketId"] as? String else { continue }
                    let bName = b["displayName"] as? String
                    let window = b["window"] as? String
                    let frac = b["remainingFraction"] as? Double
                    let reset = b["resetTime"] as? String
                    buckets.append(QuotaBucket(
                        bucketId: bucketId,
                        displayName: bName,
                        window: window,
                        remainingFraction: frac,
                        resetTime: reset
                    ))
                }
                if !buckets.isEmpty {
                    groups.append(QuotaGroup(displayName: displayName, buckets: buckets))
                }
            }
            if !groups.isEmpty {
                return groups
            }
        }

        guard let userStatus = fallbackUserStatus,
              let us = userStatus["userStatus"] as? [String: Any],
              let cm = us["cascadeModelConfigData"] as? [String: Any],
              let configs = cm["clientModelConfigs"] as? [[String: Any]] else {
            return []
        }

        var geminiBucket: QuotaBucket?
        var claudeBucket: QuotaBucket?

        for cfg in configs {
            guard let label = cfg["label"] as? String,
                  let qi = cfg["quotaInfo"] as? [String: Any],
                  let frac = qi["remainingFraction"] as? Double else {
                continue
            }
            let reset = qi["resetTime"] as? String
            let lower = label.lowercased()
            if lower.contains("gemini") || lower.contains("orchestrator") {
                if geminiBucket == nil {
                    geminiBucket = QuotaBucket(
                        bucketId: "gemini-5h",
                        displayName: "Five Hour Limit Remaining",
                        window: "5h",
                        remainingFraction: frac,
                        resetTime: reset
                    )
                }
            } else if lower.contains("claude") || lower.contains("gpt") {
                if claudeBucket == nil {
                    claudeBucket = QuotaBucket(
                        bucketId: "3p-5h",
                        displayName: "Five Hour Limit Remaining",
                        window: "5h",
                        remainingFraction: frac,
                        resetTime: reset
                    )
                }
            }
        }

        var groups: [QuotaGroup] = []
        if let g = geminiBucket {
            groups.append(QuotaGroup(displayName: "Gemini Models", buckets: [g]))
        }
        if let c = claudeBucket {
            groups.append(QuotaGroup(displayName: "Claude and GPT models", buckets: [c]))
        }
        return groups
    }

    private func inferMaxContextTokens(modelId: String) -> Int {
        let upper = modelId.uppercased()
        if upper.contains("CLAUDE") || upper.contains("M35") || upper.contains("M26") || upper.contains("GPT") {
            return 200_000
        }
        return 512_000
    }

    private func parseInt(_ value: Any?) -> Int {
        if let i = value as? Int { return i }
        if let s = value as? String, let i = Int(s) { return i }
        if let d = value as? Double { return Int(d) }
        return 0
    }

    private func parseISO(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }
        let p1 = ISO8601DateFormatter()
        p1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = p1.date(from: value) { return d }
        let p2 = ISO8601DateFormatter()
        p2.formatOptions = [.withInternetDateTime]
        return p2.date(from: value)
    }
}
