import AppKit
import SwiftUI

final class IslandPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class TrackingHostingView<Content: View>: NSHostingView<Content> {
    var onMouseEntered: (() -> Void)?
    var onMouseExited: (() -> Void)?
    private var trackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        onMouseEntered?()
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        onMouseExited?()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let service = CapsuleService()
    private let state = IslandState()

    private var panel: IslandPanel!
    private var hostingView: TrackingHostingView<IslandView>!
    private var statusItem: NSStatusItem?

    private var collapseWorkItem: DispatchWorkItem?
    private var shrinkFrameWorkItem: DispatchWorkItem?
    private var isIslandVisible = true

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        setupPanel()
        setupStatusItem()
        updateScreenMetrics()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        service.start()
        applyPanelFrame(expanded: false)
        panel.orderFrontRegardless()
    }

    func applicationWillTerminate(_ notification: Notification) {
        service.stop()
    }

    @objc private func screenChanged() {
        updateScreenMetrics()
        applyPanelFrame(expanded: state.isExpanded)
    }

    private func targetScreen() -> NSScreen? {
        NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main ?? NSScreen.screens.first
    }

    private func updateScreenMetrics() {
        guard let screen = targetScreen() else { return }
        if screen.safeAreaInsets.top > 0,
           let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea {
            state.hasNotch = true
            state.notchWidth = max(120, screen.frame.width - left.width - right.width)
            state.notchHeight = screen.safeAreaInsets.top
        } else {
            state.hasNotch = false
            state.notchWidth = 0
            state.notchHeight = 0
        }
    }

    private func setupPanel() {
        let rootView = IslandView(
            service: service,
            state: state,
            onTogglePin: { [weak self] in self?.togglePin() },
            onRefresh: { [weak self] in self?.service.refreshNow() },
            onQuit: { NSApp.terminate(nil) },
            onToggleQuotaMode: { [weak self] in
                guard let self else { return }
                self.applyPanelFrame(expanded: self.state.isExpanded)
            }
        )

        hostingView = TrackingHostingView(rootView: rootView)
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        hostingView.onMouseEntered = { [weak self] in self?.handleMouseEntered() }
        hostingView.onMouseExited = { [weak self] in self?.handleMouseExited() }

        panel = IslandPanel(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 32),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 3)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = false
        panel.contentView = hostingView
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "capsule.portrait.fill", accessibilityDescription: "AgyIsland")
            button.image?.isTemplate = true
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "显示 / 隐藏灵动岛", action: #selector(toggleVisibility), keyEquivalent: "h"))
        menu.addItem(NSMenuItem(title: "固定展开 / 取消固定", action: #selector(togglePinFromMenu), keyEquivalent: "p"))
        menu.addItem(NSMenuItem(title: "立即刷新数据", action: #selector(refreshFromMenu), keyEquivalent: "r"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "退出 AgyIsland", action: #selector(quitApp), keyEquivalent: "q"))

        for menuItem in menu.items {
            menuItem.target = self
        }
        item.menu = menu
        statusItem = item
    }

    @objc private func toggleVisibility() {
        isIslandVisible.toggle()
        if isIslandVisible {
            panel.orderFrontRegardless()
        } else {
            panel.orderOut(nil)
        }
    }

    @objc private func togglePinFromMenu() {
        togglePin()
    }

    @objc private func refreshFromMenu() {
        service.refreshNow()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    private func togglePin() {
        state.isPinned.toggle()
        if state.isPinned {
            handleMouseEntered()
        } else {
            handleMouseExited()
        }
    }

    private func handleMouseEntered() {
        collapseWorkItem?.cancel()
        shrinkFrameWorkItem?.cancel()

        if !state.isExpanded {
            applyPanelFrame(expanded: true)
            state.isExpanded = true
        }
    }

    private func handleMouseExited() {
        guard !state.isPinned else { return }

        collapseWorkItem?.cancel()
        shrinkFrameWorkItem?.cancel()

        let collapse = DispatchWorkItem { [weak self] in
            guard let self, !self.state.isPinned else { return }
            self.state.isExpanded = false

            let shrink = DispatchWorkItem { [weak self] in
                guard let self, !self.state.isExpanded else { return }
                self.applyPanelFrame(expanded: false)
            }
            self.shrinkFrameWorkItem = shrink
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.36, execute: shrink)
        }
        collapseWorkItem = collapse
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: collapse)
    }

    private func applyPanelFrame(expanded: Bool) {
        guard let screen = targetScreen() else { return }

        let unifiedNotchW = max(400, state.notchWidth + 212)
        let compactW: CGFloat = state.hasNotch ? unifiedNotchW : 228
        let compactH: CGFloat = state.hasNotch ? state.notchHeight : 28

        let hasError: Bool = {
            guard let kind = service.context?.requestError?.kind else { return false }
            return !kind.isEmpty && kind != "none"
        }()
        let expandedW: CGFloat = state.hasNotch ? unifiedNotchW : 388
        let contentDelta: CGFloat = state.isBarMode ? 244 : 214
        let expandedH: CGFloat = (state.hasNotch ? (state.notchHeight + contentDelta) : (contentDelta + 12)) + (hasError ? 28 : 0)

        let width = expanded ? expandedW : compactW
        let height = expanded ? expandedH : compactH

        let centerX: CGFloat
        if state.hasNotch, let left = screen.auxiliaryTopLeftArea {
            centerX = left.maxX + state.notchWidth / 2.0
        } else {
            centerX = screen.frame.midX
        }

        let topMargin: CGFloat = state.hasNotch ? 0 : 4
        let originX = round(centerX - width / 2.0)
        let originY = round(screen.frame.maxY - topMargin - height)

        panel.setFrame(NSRect(x: originX, y: originY, width: width, height: height), display: true)
        panel.invalidateShadow()
    }
}

@main
struct AgyIslandMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
