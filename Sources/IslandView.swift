import SwiftUI

@MainActor
final class IslandState: ObservableObject {
    @Published var isExpanded: Bool = false
    @Published var isPinned: Bool = false
    @Published var hasNotch: Bool = false
    @Published var notchWidth: CGFloat = 185
    @Published var notchHeight: CGFloat = 32
    @Published var isBarMode: Bool = UserDefaults.standard.object(forKey: "quotaBarMode") as? Bool ?? true
}

struct IslandView: View {
    @ObservedObject var service: CapsuleService
    @ObservedObject var state: IslandState

    var onTogglePin: () -> Void
    var onRefresh: () -> Void
    var onQuit: () -> Void
    var onToggleQuotaMode: (() -> Void)? = nil

    private var notchFlareRadius: CGFloat {
        state.hasNotch ? 6 : 0
    }

    private var unifiedNotchWidth: CGFloat {
        max(400, state.notchWidth + 212)
    }

    private var compactWidth: CGFloat {
        state.hasNotch ? unifiedNotchWidth : 228
    }

    private var compactHeight: CGFloat {
        state.hasNotch ? state.notchHeight : 28
    }

    private var expandedWidth: CGFloat {
        state.hasNotch ? unifiedNotchWidth : 388
    }

    private var expandedHeight: CGFloat {
        let contentDelta: CGFloat = state.isBarMode ? 244 : 214
        let base: CGFloat = state.hasNotch ? (state.notchHeight + contentDelta) : (contentDelta + 12)
        return hasRequestError ? (base + 28) : base
    }

    private var hasRequestError: Bool {
        guard let kind = service.context?.requestError?.kind else { return false }
        return !kind.isEmpty && kind != "none"
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.clear

            ZStack(alignment: .top) {
                if state.isExpanded {
                    expandedContent
                        .transition(.opacity)
                } else {
                    compactContent
                        .transition(.opacity)
                }
            }
            .frame(
                width: state.isExpanded ? expandedWidth : compactWidth,
                height: state.isExpanded ? expandedHeight : compactHeight,
                alignment: .top
            )
            .background(
                IslandBackgroundShape(
                    topCornerRadius: state.hasNotch ? 0 : 14,
                    bottomCornerRadius: state.isExpanded ? 20 : (state.hasNotch ? 12 : 14),
                    topFlareRadius: notchFlareRadius
                )
                .fill(Color(red: 0.02, green: 0.02, blue: 0.03))
            )
            .overlay(
                IslandBackgroundShape(
                    topCornerRadius: state.hasNotch ? 0 : 14,
                    bottomCornerRadius: state.isExpanded ? 20 : (state.hasNotch ? 12 : 14),
                    topFlareRadius: notchFlareRadius
                )
                .strokeBorder(Color.white.opacity(state.isExpanded ? 0.14 : 0.08), lineWidth: 1)
            )
            .clipShape(
                IslandBackgroundShape(
                    topCornerRadius: state.hasNotch ? 0 : 14,
                    bottomCornerRadius: state.isExpanded ? 20 : (state.hasNotch ? 12 : 14),
                    topFlareRadius: notchFlareRadius
                )
            )
            .animation(.spring(response: 0.28, dampingFraction: 0.92), value: state.isExpanded)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: - Compact View

    @ViewBuilder
    private var compactContent: some View {
        if state.hasNotch {
            HStack(spacing: 0) {
                // Left ear
                HStack(spacing: 6) {
                    statusDot
                    Text(contextPercentText)
                        .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                        .foregroundColor(contextColor)
                }
                .frame(maxWidth: .infinity, maxHeight: compactHeight)
                .padding(.leading, 10)

                // Hardware notch spacer
                Spacer()
                    .frame(width: state.notchWidth)

                // Right ear
                HStack(spacing: 6) {
                    Text(speedOrQuotaCompactText)
                        .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                        .foregroundColor(speedColor)
                    if let g5h = primary5hPercent {
                        Text(g5h)
                            .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                            .foregroundColor(.white.opacity(0.75))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: compactHeight)
                .padding(.trailing, 10)
            }
        } else {
            HStack(spacing: 8) {
                statusDot
                Text(contextPercentText)
                    .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                    .foregroundColor(contextColor)
                Text("·")
                    .foregroundColor(.white.opacity(0.35))
                Text(speedOrQuotaCompactText)
                    .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                    .foregroundColor(speedColor)
                if let g5h = primary5hPercent {
                    Text("·")
                        .foregroundColor(.white.opacity(0.35))
                    Text("G \(g5h)")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.78))
                }
            }
            .padding(.horizontal, 12)
            .frame(height: compactHeight)
        }
    }

    // MARK: - Expanded View

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            if state.hasNotch {
                // Top bar flanking the notch
                HStack {
                    HStack(spacing: 6) {
                        statusDot
                        Text("AgyIsland")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundColor(.white.opacity(0.92))
                    }
                    .frame(width: 96, alignment: .leading)
                    .padding(.leading, 12)

                    Spacer()

                    HStack(spacing: 8) {
                        headerButtons
                    }
                    .frame(width: 96, alignment: .trailing)
                    .padding(.trailing, 12)
                }
                .frame(height: state.notchHeight)
            } else {
                HStack {
                    HStack(spacing: 6) {
                        statusDot
                        Text("AgyIsland")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white.opacity(0.92))
                        if let port = service.currentPort {
                            Text(":\(port)")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.white.opacity(0.4))
                        }
                    }
                    Spacer()
                    headerButtons
                }
                .padding(.top, 10)
                .padding(.horizontal, 14)
            }

            VStack(alignment: .leading, spacing: 10) {
                if !service.isConnected && service.context == nil {
                    offlineBanner
                } else {
                    contextSection
                    if hasRequestError, let err = service.context?.requestError {
                        errorBanner(err)
                    }
                    quotaSection
                    footerModeToggleRow
                }
            }
            .padding(.horizontal, 14 + notchFlareRadius)
            .padding(.bottom, 12)
        }
    }

    private var headerButtons: some View {
        HStack(spacing: 8) {
            Button(action: onTogglePin) {
                Image(systemName: state.isPinned ? "pin.fill" : "pin")
                    .font(.system(size: 11))
                    .foregroundColor(state.isPinned ? Color.orange : Color.white.opacity(0.65))
            }
            .buttonStyle(.plain)
            .help(state.isPinned ? "取消固定" : "固定展开")

            Button(action: onRefresh) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.65))
            }
            .buttonStyle(.plain)
            .help("刷新数据")

            Button(action: onQuit) {
                Image(systemName: "xmark.circle")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.55))
            }
            .buttonStyle(.plain)
            .help("退出 AgyIsland")
        }
    }

    private var offlineBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "bolt.slash.fill")
                .foregroundColor(.yellow)
            VStack(alignment: .leading, spacing: 2) {
                Text("未检测到运行中的 Antigravity")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white)
                Text("请打开 Antigravity 并开始任意对话")
                    .font(.system(size: 10.5))
                    .foregroundColor(.white.opacity(0.6))
            }
            Spacer()
        }
        .padding(10)
        .background(Color.white.opacity(0.06))
        .cornerRadius(10)
    }

    private var contextSection: some View {
        let ctx = service.context
        let used = ctx?.contextTokens ?? 0
        let maxTok = max(ctx?.maxContextTokens ?? 1, 1)
        let pct = min(Double(used) / Double(maxTok), 1.0)

        let turn0 = ctx?.turn0Tokens ?? 0
        let cached = ctx?.cachedIn ?? 0
        let uncached = ctx?.uncachedIn ?? 0
        let totalIn = cached + uncached
        let think = ctx?.totalThinkingTokens ?? 0
        let out = ctx?.totalOutputTokens ?? 0
        let readOnly = max(0, totalIn - turn0)

        let cacheHitPct = totalIn > 0 ? Int((Double(cached) / Double(totalIn) * 100.0).rounded()) : 0

        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(String(format: "%.1f%%", pct * 100))
                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                    .foregroundColor(contextColor)
                Text("上下文")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.55))
                Spacer()
                Text("\(IslandFormatters.formatTokens(used)) / \(IslandFormatters.formatTokens(maxTok))")
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundColor(.white.opacity(0.8))
            }

            // Segmented bar
            GeometryReader { geo in
                let w = geo.size.width
                let t0W = w * CGFloat(min(Double(turn0) / Double(maxTok), 1.0))
                let readW = w * CGFloat(min(Double(readOnly) / Double(maxTok), 1.0))
                let thinkW = w * CGFloat(min(Double(think) / Double(maxTok), 1.0))
                let outW = w * CGFloat(min(Double(out) / Double(maxTok), 1.0))

                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.white.opacity(0.10))
                    HStack(spacing: 1) {
                        if t0W > 0 { Rectangle().fill(Color(hex: 0xd4940a)).frame(width: t0W) }
                        if readW > 0 { Rectangle().fill(Color(hex: 0x388bfd)).frame(width: readW) }
                        if thinkW > 0 { Rectangle().fill(Color(hex: 0x00b386)).frame(width: thinkW) }
                        if outW > 0 { Rectangle().fill(Color(hex: 0xe86a24)).frame(width: outW) }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                }
            }
            .frame(height: 6)

            // Cache & Speed row
            HStack(spacing: 10) {
                HStack(spacing: 4) {
                    Circle()
                        .fill(cacheStatusColor)
                        .frame(width: 6, height: 6)
                    Text("缓存 \(cacheHitPct)%")
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundColor(.white.opacity(0.75))
                    if let idle = IslandFormatters.cacheIdleSeconds(lastStepEpochMs: ctx?.lastStepEpochMs) {
                        Text("(\(Int(idle / 60))分)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(cacheStatusColor.opacity(0.9))
                    }
                }

                Spacer()

                if let gen = ctx?.turnSpeed?.generation ?? ctx?.generation {
                    HStack(spacing: 6) {
                        if let tps = gen.tps, tps > 0 {
                            Text(String(format: "%.1f tok/s", tps))
                                .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                                .foregroundColor(speedColor)
                        }
                        if let ttft = gen.ttft {
                            Text("首字 \(IslandFormatters.formatDuration(ttft))")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.white.opacity(0.55))
                        } else if let dur = gen.duration {
                            Text("耗时 \(IslandFormatters.formatDuration(dur))")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.white.opacity(0.55))
                        }
                    }
                }
            }
        }
        .padding(10)
        .background(Color.white.opacity(0.06))
        .cornerRadius(10)
    }

    private func errorBanner(_ err: RequestErrorInfo) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11))
                .foregroundColor(.red)
            Text(err.kind ?? "请求失败")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.red.opacity(0.95))
            if let retry = err.retryAfterSec, retry > 0 {
                Text("\(retry)秒后重试")
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundColor(.white.opacity(0.7))
            }
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.red.opacity(0.16))
        .cornerRadius(8)
    }

    private var quotaSection: some View {
        let groups = service.context?.quotaGroups ?? []
        return VStack(spacing: 6) {
            if groups.isEmpty {
                Text(service.context?.cloudPaygo == true ? "按量计费模式" : "暂无配额数据")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.5))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(Color.white.opacity(0.05))
                    .cornerRadius(8)
            } else {
                ForEach(groups.prefix(2)) { group in
                    quotaGroupRow(group)
                }
            }
        }
    }

    private func quotaGroupRow(_ group: QuotaGroup) -> some View {
        let buckets = group.buckets ?? []
        let b5h = buckets.first(where: { $0.window == "5h" })
        let b7d = buckets.first(where: { $0.window == "weekly" })

        return Group {
            if state.isBarMode {
                HStack(alignment: .center, spacing: 10) {
                    Text(group.shortName)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundColor(.white.opacity(0.9))
                        .frame(width: 50, alignment: .leading)

                    VStack(spacing: 5) {
                        if let b5h {
                            quotaBarRow(label: "5小时", bucket: b5h)
                        }
                        if let b7d {
                            quotaBarRow(label: "7天", bucket: b7d)
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color.white.opacity(0.06))
                .cornerRadius(9)
            } else {
                HStack(spacing: 8) {
                    Text(group.shortName)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundColor(.white.opacity(0.9))
                        .frame(width: 50, alignment: .leading)

                    if let b5h {
                        quotaPill(label: "5小时", bucket: b5h)
                    }
                    if let b7d {
                        quotaPill(label: "7天", bucket: b7d)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color.white.opacity(0.06))
                .cornerRadius(9)
            }
        }
    }

    private func quotaBarRow(label: String, bucket: QuotaBucket) -> some View {
        let frac = max(0, min(bucket.remainingFraction ?? 0, 1))
        let pct = Int((frac * 100).rounded())
        let color: Color = frac > 0.35 ? Color(hex: 0x3fb950) : (frac > 0.15 ? Color(hex: 0xd29922) : Color(hex: 0xf85149))
        let reset = IslandFormatters.formatCountdown(isoString: bucket.resetTime)

        return HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundColor(.white.opacity(0.55))
                .frame(width: 30, alignment: .leading)

            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2.5)
                        .fill(Color.white.opacity(0.10))
                    RoundedRectangle(cornerRadius: 2.5)
                        .fill(color)
                        .frame(width: max(2, w * CGFloat(frac)))
                }
            }
            .frame(height: 5)

            HStack(spacing: 3) {
                Text("\(pct)%")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(color)
                if frac < 0.999 && reset != "--" {
                    Text(reset)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.white.opacity(0.45))
                }
            }
            .frame(minWidth: 74, alignment: .trailing)
        }
    }

    private func quotaPill(label: String, bucket: QuotaBucket) -> some View {
        let frac = max(0, min(bucket.remainingFraction ?? 0, 1))
        let pct = Int((frac * 100).rounded())
        let color: Color = frac > 0.35 ? Color(hex: 0x3fb950) : (frac > 0.15 ? Color(hex: 0xd29922) : Color(hex: 0xf85149))
        let reset = IslandFormatters.formatCountdown(isoString: bucket.resetTime)

        return HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.white.opacity(0.5))
            Text("\(pct)%")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundColor(color)
            if frac < 0.999 && reset != "--" {
                Text("(\(reset))")
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundColor(.white.opacity(0.45))
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Color.white.opacity(0.06))
        .cornerRadius(6)
    }

    private var footerModeToggleRow: some View {
        HStack {
            Text("每 1.5 秒同步")
                .font(.system(size: 9.5))
                .foregroundColor(.white.opacity(0.35))
            Spacer()
            Button {
                state.isBarMode.toggle()
                UserDefaults.standard.set(state.isBarMode, forKey: "quotaBarMode")
                onToggleQuotaMode?()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: state.isBarMode ? "textformat.123" : "chart.bar.fill")
                        .font(.system(size: 9.5))
                    Text(state.isBarMode ? "数字视图" : "长条视图")
                        .font(.system(size: 9.5, weight: .medium))
                }
                .foregroundColor(.white.opacity(0.75))
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Color.white.opacity(0.08))
                .cornerRadius(6)
            }
            .buttonStyle(.plain)
            .help("切换配额展示样式（长条 / 数字）")
        }
        .padding(.top, -2)
    }

    // MARK: - Computed Helpers

    private var statusDot: some View {
        let isGenerating = service.context?.turnSpeed?.hasActiveStep ?? false
        let color: Color = !service.isConnected ? .gray : (isGenerating ? Color.green : Color(hex: 0x388bfd))
        return Circle()
            .fill(color)
            .frame(width: 7, height: 7)
    }

    private var contextPercentText: String {
        guard service.isConnected || service.context != nil else { return "离线" }
        let used = service.context?.contextTokens ?? 0
        let maxTok = max(service.context?.maxContextTokens ?? 1, 1)
        let pct = Double(used) / Double(maxTok) * 100.0
        return String(format: "%.0f%%", pct)
    }

    private var contextColor: Color {
        guard service.isConnected || service.context != nil else { return .white.opacity(0.5) }
        let used = service.context?.contextTokens ?? 0
        let maxTok = max(service.context?.maxContextTokens ?? 1, 1)
        let pct = Double(used) / Double(maxTok)
        if pct >= 0.90 { return Color(hex: 0xf85149) }
        if pct >= 0.75 { return Color(hex: 0xd29922) }
        return .white.opacity(0.92)
    }

    private var speedOrQuotaCompactText: String {
        guard let tps = (service.context?.turnSpeed?.generation ?? service.context?.generation)?.tps, tps > 0 else {
            return "--t/s"
        }
        return String(format: "%.0ft/s", tps)
    }

    private var speedColor: Color {
        guard let tps = (service.context?.turnSpeed?.generation ?? service.context?.generation)?.tps, tps > 0 else {
            return .white.opacity(0.6)
        }
        if tps < 10 { return Color(hex: 0xf85149) }
        if tps < 25 { return Color(hex: 0xd29922) }
        return Color(hex: 0x3fb950)
    }

    private var primary5hPercent: String? {
        guard let gemini = service.context?.quotaGroups?.first(where: { $0.displayName.lowercased().contains("gemini") }),
              let b5h = gemini.buckets?.first(where: { $0.window == "5h" }),
              let frac = b5h.remainingFraction else { return nil }
        return "\(Int((frac * 100).rounded()))%"
    }

    private var cacheStatusColor: Color {
        guard let idle = IslandFormatters.cacheIdleSeconds(lastStepEpochMs: service.context?.lastStepEpochMs) else {
            return .gray
        }
        if idle >= 240 { return Color(hex: 0xf85149) }
        if idle >= 180 { return Color(hex: 0xd29922) }
        return Color(hex: 0x3fb950)
    }
}

struct IslandBackgroundShape: InsettableShape {
    var topCornerRadius: CGFloat
    var bottomCornerRadius: CGFloat
    var topFlareRadius: CGFloat = 0
    var insetAmount: CGFloat = 0

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topCornerRadius, bottomCornerRadius) }
        set {
            topCornerRadius = newValue.first
            bottomCornerRadius = newValue.second
        }
    }

    func inset(by amount: CGFloat) -> some InsettableShape {
        var copy = self
        copy.insetAmount += amount
        return copy
    }

    func path(in rect: CGRect) -> Path {
        let flare = max(0, topFlareRadius)
        if flare > 0 {
            // Notch-style shape with small outward-flared concave top corners
            let r = CGRect(
                x: rect.minX + insetAmount,
                y: rect.minY,
                width: max(0, rect.width - insetAmount * 2),
                height: max(0, rect.height - insetAmount)
            )
            let fr = min(flare, r.width * 0.15, r.height * 0.45)
            let br = max(0, min(bottomCornerRadius - insetAmount, (r.width - fr * 2) * 0.45, (r.height - fr) * 0.8))

            var p = Path()
            p.move(to: CGPoint(x: r.minX, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
            // Top-right concave flare
            p.addArc(
                center: CGPoint(x: r.maxX, y: r.minY + fr),
                radius: fr,
                startAngle: .degrees(-90),
                endAngle: .degrees(180),
                clockwise: true
            )
            p.addLine(to: CGPoint(x: r.maxX - fr, y: r.maxY - br))
            if br > 0 {
                p.addArc(
                    center: CGPoint(x: r.maxX - fr - br, y: r.maxY - br),
                    radius: br,
                    startAngle: .degrees(0),
                    endAngle: .degrees(90),
                    clockwise: false
                )
            }
            p.addLine(to: CGPoint(x: r.minX + fr + br, y: r.maxY))
            if br > 0 {
                p.addArc(
                    center: CGPoint(x: r.minX + fr + br, y: r.maxY - br),
                    radius: br,
                    startAngle: .degrees(90),
                    endAngle: .degrees(180),
                    clockwise: false
                )
            }
            p.addLine(to: CGPoint(x: r.minX + fr, y: r.minY + fr))
            // Top-left concave flare
            p.addArc(
                center: CGPoint(x: r.minX, y: r.minY + fr),
                radius: fr,
                startAngle: .degrees(0),
                endAngle: .degrees(-90),
                clockwise: true
            )
            p.closeSubpath()
            return p
        }

        let r = rect.insetBy(dx: insetAmount, dy: insetAmount)
        let tl = max(0, topCornerRadius - insetAmount)
        let tr = max(0, topCornerRadius - insetAmount)
        let bl = max(0, bottomCornerRadius - insetAmount)
        let br = max(0, bottomCornerRadius - insetAmount)

        var p = Path()
        p.move(to: CGPoint(x: r.minX + tl, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - tr, y: r.minY))
        if tr > 0 {
            p.addArc(center: CGPoint(x: r.maxX - tr, y: r.minY + tr), radius: tr, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
        }
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - br))
        if br > 0 {
            p.addArc(center: CGPoint(x: r.maxX - br, y: r.maxY - br), radius: br, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        }
        p.addLine(to: CGPoint(x: r.minX + bl, y: r.maxY))
        if bl > 0 {
            p.addArc(center: CGPoint(x: r.minX + bl, y: r.maxY - bl), radius: bl, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        }
        p.addLine(to: CGPoint(x: r.minX, y: r.minY + tl))
        if tl > 0 {
            p.addArc(center: CGPoint(x: r.minX + tl, y: r.minY + tl), radius: tl, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        }
        p.closeSubpath()
        return p
    }
}

extension Color {
    init(hex: UInt32) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b)
    }
}
