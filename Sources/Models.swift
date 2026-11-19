import Foundation

struct CapsuleContext: Decodable {
    let contextTokens: Int?
    let maxContextTokens: Int?
    let cachedIn: Int?
    let uncachedIn: Int?
    let turn0Tokens: Int?
    let totalOutputTokens: Int?
    let totalThinkingTokens: Int?
    let lastStepEpochMs: Double?
    let generation: GenerationInfo?
    let turnSpeed: TurnSpeedInfo?
    let requestError: RequestErrorInfo?
    let quotaGroups: [QuotaGroup]?
    let cloudPaygo: Bool?
}

struct GenerationInfo: Decodable {
    let ttft: Double?
    let streaming: Double?
    let duration: Double?
    let output: Int?
    let reply: Int?
    let thinking: Int?
    let tps: Double?
}

struct TurnSpeedInfo: Decodable {
    let hasActiveStep: Bool?
    let completedAtMs: Double?
    let generation: GenerationInfo?
}

struct RequestErrorInfo: Decodable {
    let kind: String?
    let diagnostic: String?
    let retryAfterSec: Int?
}

struct QuotaGroup: Decodable, Identifiable {
    let displayName: String
    let buckets: [QuotaBucket]?

    var id: String { displayName }

    var shortName: String {
        let lower = displayName.lowercased()
        if lower.contains("gemini") { return "Gemini" }
        if lower.contains("claude") { return "Claude" }
        return displayName
    }
}

struct QuotaBucket: Decodable, Identifiable {
    let bucketId: String
    let displayName: String?
    let window: String?
    let remainingFraction: Double?
    let resetTime: String?

    var id: String { bucketId }
}

enum IslandFormatters {
    static func formatTokens(_ value: Int) -> String {
        if value >= 1_000_000 {
            return String(format: "%.1fM", Double(value) / 1_000_000.0)
        }
        if value >= 1_000 {
            return String(format: "%.1fk", Double(value) / 1_000.0)
        }
        return "\(value)"
    }

    static func formatCountdown(isoString: String?) -> String {
        guard let isoString, !isoString.isEmpty else { return "--" }
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var target = parser.date(from: isoString)
        if target == nil {
            let fallback = ISO8601DateFormatter()
            fallback.formatOptions = [.withInternetDateTime]
            target = fallback.date(from: isoString)
        }
        guard let date = target else { return "--" }
        let diff = Int(date.timeIntervalSinceNow)
        if diff <= 0 { return "now" }
        let days = diff / 86400
        let hours = (diff % 86400) / 3600
        let mins = (diff % 3600) / 60
        if days > 0 { return "\(days)d\(hours)h" }
        if hours > 0 { return "\(hours)h\(mins)m" }
        return "\(max(1, mins))m"
    }

    static func formatDuration(_ seconds: Double?) -> String {
        guard let seconds, seconds > 0 else { return "--" }
        if seconds >= 60 {
            return String(format: "%.1fm", seconds / 60.0)
        }
        return String(format: "%.1fs", seconds)
    }

    static func cacheIdleSeconds(lastStepEpochMs: Double?) -> TimeInterval? {
        guard let ms = lastStepEpochMs, ms > 0 else { return nil }
        let nowMs = Date().timeIntervalSince1970 * 1000.0
        return max(0, (nowMs - ms) / 1000.0)
    }
}
