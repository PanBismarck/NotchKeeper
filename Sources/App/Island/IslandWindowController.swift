import AppKit
import SwiftUI

/// Owns the notch panel, drives it from `IslandStateMachine` and keeps it glued to the right screen.
@MainActor
final class IslandWindowController {
    private let panel: NotchPanel
    private let host: IslandHostView
    private let model: IslandModel
    private let fsm = IslandStateMachine()
    private var screen: NSScreen?
    private var screenObserver: NSObjectProtocol?
    /// Global mouse-down monitor, installed only while expanded (click outside → dismiss).
    private var outsideClickMonitor: Any?
    /// Bumped on every transition so a stale animation completion doesn't shrink the panel.
    private var generation = 0
    /// One-shot timer for the next linger end or stale session — armed only while sessions exist (no polling).
    private var pruneTimer: Timer?
    /// Open hook connections, one per queued permission request.
    private var replies: [UUID: HookReply] = [:]
    /// Gives up on the oldest request before notchkeeper-hook does (110 s) — armed only while requests wait.
    private var permissionTimer: Timer?
    private var fadingOut = false
    static let permissionTimeout: TimeInterval = 100

    private let settings: AppSettings
    private let fullScreen = FullScreenWatcher()
    private let systemGlass = SystemGlass()
    /// Right-click menu on the notch (replaces the old menu bar icon).
    var contextMenu: (() -> NSMenu)?
    func openWindow(id: String) {
        NSApplication.shared.activate()
        model.openWindow?(id: id)
    }

    init(settings: AppSettings) {
        self.settings = settings
        screen = NotchGeometry.targetScreen(preferred: settings.screenName)
        model = IslandModel(geometry: screen.map(NotchGeometry.init(screen:))
                            ?? NotchGeometry(screenWidth: 0, safeAreaTop: 0, auxLeftWidth: nil,
                                             auxRightWidth: nil, menuBarHeight: 24))
        panel = NotchPanel(frame: .zero)
        host = IslandHostView(model: model)
        // The SwiftUI canvas keeps one fixed size and the panel just clips it: resizing the panel then
        // needs no SwiftUI relayout, so both ears move in the same frame (no one-frame lag/shift).
        let container = NSView()
        container.addSubview(host)
        panel.contentView = container

        host.onMouseEntered = { [weak self] in self?.fsm.mouseEntered() }
        host.onMouseExited = { [weak self] in self?.fsm.mouseExited() }
        host.onClick = { [weak self] in self?.handleClick() }
        host.contextMenu = { [weak self] in self?.contextMenu?() ?? NSMenu() }
        panel.onEscape = { [weak self] in self?.fsm.dismiss() }
        fsm.onTransition = { [weak self] old, new in self?.apply(from: old, to: new) }
        model.onDecide = { [weak self] id, decision in self?.decide(id, decision) }

        fullScreen.onChange = { [weak self] _ in self?.updateVisibility() }
        systemGlass.onChange = { [weak self] in self?.applySettings() }
        applySettings()

        // Monitor plugged/unplugged, lid closed, resolution or arrangement changed.
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.relocate() }
        }
    }

    // MARK: - Sessions

    func handle(_ event: HookEvent, reply: HookReply? = nil) {
        let now = Date()
        let before = model.sessions.sessions
        model.sessions.apply(event, at: now)
        if let alert = SessionAlert.between(before, model.sessions.sessions) { settings.play(alert) }
        sessionsChanged()

        if let reply {
            guard let request = PermissionRequest(event: event, at: now) else { reply.send(nil); return }
            model.permissions.enqueue(request)
            replies[request.id] = reply
            fsm.setHeldOpen(true)
        } else {
            let answered = model.permissions.resolved(by: event)
            guard !answered.isEmpty else { return }
            for r in answered { replies.removeValue(forKey: r.id)?.send(nil) }
        }
        permissionsChanged()
    }

    // MARK: - Permissions

    /// A click on the card. `nil` = answer in the terminal (hook returns nothing).
    private func decide(_ id: UUID, _ decision: PermissionDecision?) {
        guard let request = model.permissions.remove(id: id) else { return }
        replies.removeValue(forKey: id)?.send(decision.map(request.response))
        permissionsChanged()
    }

    private func permissionsChanged() {
        if model.permissions.isEmpty { fsm.setHeldOpen(false) }
        updateVisibility()
        permissionTimer?.invalidate()
        permissionTimer = nil
        guard let oldest = model.permissions.items.map(\.createdAt).min() else { return }
        let timer = Timer(fire: oldest.addingTimeInterval(Self.permissionTimeout), interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.expirePermissions() }
        }
        timer.tolerance = 2
        RunLoop.main.add(timer, forMode: .common)
        permissionTimer = timer
    }

    private func expirePermissions() {
        let cutoff = Date().addingTimeInterval(-Self.permissionTimeout + 1)
        for r in model.permissions.items where r.createdAt <= cutoff {
            model.permissions.remove(id: r.id)
            replies.removeValue(forKey: r.id)?.send(nil)
        }
        permissionsChanged()
    }

    private func sessionsChanged() {
        let now = Date()
        fsm.setActive(model.sessions.hasActivity(at: now))
        pruneTimer?.invalidate()
        pruneTimer = nil
        guard let due = model.sessions.nextDeadline(after: now) else { return }
        let timer = Timer(fire: due, interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.model.sessions.prune(now: Date())
                self.sessionsChanged()
            }
        }
        timer.tolerance = 5
        RunLoop.main.add(timer, forMode: .common)
        pruneTimer = timer
    }

    // MARK: - Inputs

    private func handleClick() {
        fsm.click()
        guard fsm.state == .expanded, !panel.isKeyWindow else { return }
        // Clicked open: take key so Escape reaches us (non-activating — the app stays inactive).
        panel.allowsKey = true
        panel.makeKey()
    }

    // MARK: - Transitions

    private func apply(from old: IslandStateMachine.State, to new: IslandStateMachine.State) {
        generation += 1
        let gen = generation
        let growing = rank(new) > rank(old)

        // Grow the panel first so the shape has room; shrink only once the animation is done.
        if growing { setPanelFrame(for: new) }
        if new == .expanded { installOutsideClickMonitor() } else { leaveExpanded() }
        // A light tap on the trackpad when hovering opens the big view (felt only with a finger on it).
        if new == .expanded, fsm.openedByHover {
            NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
        }

        withAnimation(.spring(duration: 0.38, bounce: 0.22)) {
            model.state = new
        } completion: { [weak self] in
            guard let self, self.generation == gen else { return }
            if !growing { self.setPanelFrame(for: new) }
            self.syncPointer()
        }
    }

    private func rank(_ s: IslandStateMachine.State) -> Int {
        switch s {
        case .hidden: 0
        case .compact: 1
        case .expanded: 2
        }
    }

    private func leaveExpanded() {
        removeOutsideClickMonitor()
        guard panel.allowsKey else { return }
        panel.allowsKey = false
        if panel.isKeyWindow {
            // Hand key focus back to the app that had it before the click.
            panel.orderOut(nil)
            panel.orderFrontRegardless()
        }
    }

    private func installOutsideClickMonitor() {
        guard outsideClickMonitor == nil else { return }
        // Global monitors only see events aimed at other apps, i.e. clicks outside the island.
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.fsm.dismiss() }
        }
    }

    private func removeOutsideClickMonitor() {
        if let m = outsideClickMonitor { NSEvent.removeMonitor(m) }
        outsideClickMonitor = nil
    }

    /// After a resize the tracking area may not report enter/exit; check the pointer once.
    private func syncPointer() {
        let inside = panel.frame.insetBy(dx: 0, dy: -1).contains(NSEvent.mouseLocation)
        guard inside != fsm.pointerInside else { return }
        if inside { fsm.mouseEntered() } else { fsm.mouseExited() }
    }

    // MARK: - Layout

    private func setPanelFrame(for state: IslandStateMachine.State) {
        guard let screen else { return }
        let frame = model.geometry.frame(for: state, on: screen)
        if panel.frame != frame { panel.setFrame(frame, display: false) }
        let canvas = model.geometry.maxPanelSize
        // Pinned to the top centre of the panel; set in the same pass as the panel frame.
        host.frame = NSRect(x: (frame.width - canvas.width) / 2, y: frame.height - canvas.height,
                            width: canvas.width, height: canvas.height)
        panel.displayIfNeeded()
    }

    // MARK: - Settings & shortcut

    func applySettings() {
        fsm.hoverExpandDelay = settings.hoverToExpand ? 0.3 : nil
        fsm.expandedCollapseDelay = settings.collapseDelay
        model.glass = settings.glassIsland
        model.glassTransparency = settings.glassFollowsSystem ? SystemGlass.transparency
            : SystemGlass.reduceTransparency ? 0 : settings.glassIntensity
        if settings.hideInFullScreen { fullScreen.start() } else { fullScreen.stop() }
        if model.sessions.finishedLinger != settings.finishedLinger {
            model.sessions.finishedLinger = settings.finishedLinger
            sessionsChanged()
        }
        relocate()
    }

    /// Global shortcut: open the island (taking key so Escape works), or close it.
    func toggle() {
        if fsm.state == .expanded { fsm.dismiss() } else { handleClick() }
    }

    private func relocate() {
        guard let target = NotchGeometry.targetScreen(preferred: settings.screenName) else { panel.orderOut(nil); return }
        screen = target
        let geometry = NotchGeometry(screen: target)
        if model.geometry != geometry { model.geometry = geometry }
        fullScreen.screen = target
        setPanelFrame(for: fsm.state)
        updateVisibility()
    }

    /// Out of the way over a full-screen app, unless an approval is waiting.
    private func updateVisibility() {
        guard screen != nil else { return }
        let quiet = fullScreen.isFullScreen && model.permissions.isEmpty
        // Tucked into the notch (still hoverable), or gone entirely.
        let tucked = quiet && settings.peekInFullScreen
        if tucked != fsm.isTucked {
            fsm.isTucked = tucked
            if tucked { fsm.dismiss() }
        }
        let suppressed = quiet && !settings.peekInFullScreen
        // Fade rather than cut: macOS draws the panel on the new full-screen Space before telling us,
        // so a short flash on entering is unavoidable — a fade makes it look intended.
        if suppressed, panel.isVisible, !fadingOut {
            fsm.dismiss()
            fadingOut = true
            NSAnimationContext.runAnimationGroup({ $0.duration = 0.2; panel.animator().alphaValue = 0 }) { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, self.fadingOut else { return }
                    self.fadingOut = false
                    self.panel.orderOut(nil)
                }
            }
        } else if !suppressed, !panel.isVisible || fadingOut {
            fadingOut = false
            if !panel.isVisible { panel.alphaValue = 0 }
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { $0.duration = 0.2; panel.animator().alphaValue = 1 }
        }
    }
}
