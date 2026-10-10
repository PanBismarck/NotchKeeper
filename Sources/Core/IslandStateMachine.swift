import Foundation

/// Handle for a scheduled one-shot callback.
@MainActor protocol IslandTimer: AnyObject {
    func cancel()
}

/// Pure 3-state FSM for the island: no AppKit, time is injected so tests can drive it.
/// At most one timer is pending at any moment: a hover dwell while the pointer is inside, otherwise a leave timer.
@MainActor
final class IslandStateMachine {
    enum State: Equatable, Sendable {
        case hidden    // notch-sized, blends into the hardware notch
        case compact   // notch + ears
        case expanded  // full panel below the notch
    }

    typealias Schedule = @MainActor (TimeInterval, @escaping @MainActor @Sendable () -> Void) -> any IslandTimer

    private(set) var state: State = .hidden
    private(set) var pointerInside = false
    /// True while expanded because of a hover, until the user clicks inside.
    private(set) var openedByHover = false
    /// Keeps the island expanded: no timer or mouse-leave collapses it (pending approval).
    /// Explicit `dismiss()` still works.
    private(set) var isHeldOpen = false
    /// A session is working or waiting: the island rests in `.compact` (ears out) instead of `.hidden`.
    private(set) var isActive = false
    /// Tucked into the notch (full-screen app): session activity doesn't show the ears and hover
    /// doesn't open the island — hover shows the ears, a click opens it.
    var isTucked = false {
        didSet {
            guard isTucked != oldValue else { return }
            if isTucked {
                if state == .compact, !pointerInside { cancelTimer(); transition(to: .hidden) }
            } else if isActive, state == .hidden {
                transition(to: .compact)
            }
        }
    }
    /// Activity that keeps the ears out.
    private var showsActivity: Bool { isActive && !isTucked }

    /// Fired on every transition: (from, to).
    var onTransition: ((State, State) -> Void)?

    /// Hover expands straight away instead of only peeking (compact).
    var openOnHover = false
    var compactHideDelay: TimeInterval = 1.0
    var expandedCollapseDelay: TimeInterval = 0.3
    /// Resting the pointer on the compact island this long opens it like a click (nil = never).
    var hoverExpandDelay: TimeInterval? = 0.3
    /// Grace period after the pointer leaves a hover-opened island.
    var hoverCloseDelay: TimeInterval = 0.6

    private let schedule: Schedule
    private var timer: (any IslandTimer)?

    init(schedule: @escaping Schedule = IslandStateMachine.liveSchedule) {
        self.schedule = schedule
    }

    // MARK: - Inputs

    func mouseEntered() {
        pointerInside = true
        cancelTimer()
        switch state {
        case .hidden, .compact:
            if openOnHover, !isTucked {
                openedByHover = true
                transition(to: .expanded)
            } else {
                transition(to: .compact)
                scheduleHoverExpand()
            }
        case .expanded:
            break
        }
    }

    func mouseExited() {
        pointerInside = false
        scheduleLeaveTimer()
    }

    /// Click inside the island: opens it, or pins a hover-opened one.
    func click() {
        openedByHover = false
        guard state != .expanded else { return }
        cancelTimer()
        transition(to: .expanded)
    }

    /// Escape or click outside.
    func dismiss() {
        openedByHover = false
        guard state == .expanded else { return }
        cancelTimer()
        transition(to: pointerInside || showsActivity ? .compact : .hidden)
    }

    /// Session activity changed: show the ears while something is going on, tuck them away after.
    func setActive(_ active: Bool) {
        guard active != isActive else { return }
        isActive = active
        if active {
            if state == .hidden, !isTucked { transition(to: .compact) }
        } else if state == .compact {
            scheduleLeaveTimer()
        }
    }

    /// Hold the island open (e.g. waiting for a permission decision), or release it.
    /// Holding again re-opens an island the user dismissed (a new request arrived).
    func setHeldOpen(_ held: Bool) {
        guard held != isHeldOpen || (held && state != .expanded) else { return }
        isHeldOpen = held
        if held {
            cancelTimer()
            openedByHover = false
            transition(to: .expanded)
        } else {
            scheduleLeaveTimer()
        }
    }

    // MARK: - Timers

    private func scheduleHoverExpand() {
        guard let delay = hoverExpandDelay, !isTucked else { return }
        timer = schedule(delay) { [weak self] in
            guard let self else { return }
            self.timer = nil
            guard self.pointerInside, self.state == .compact else { return }
            self.openedByHover = true
            self.transition(to: .expanded)
        }
    }

    private func scheduleLeaveTimer() {
        cancelTimer()
        guard !pointerInside, !isHeldOpen else { return }
        switch state {
        case .hidden:
            return
        case .compact:
            guard !showsActivity else { return }
            timer = schedule(compactHideDelay) { [weak self] in
                self?.fire(from: .compact, to: .hidden)
            }
        case .expanded:
            let delay = openedByHover ? hoverCloseDelay : expandedCollapseDelay
            timer = schedule(delay) { [weak self] in
                self?.fire(from: .expanded, to: .compact)
            }
        }
    }

    private func fire(from: State, to: State) {
        timer = nil
        guard state == from, !pointerInside, !isHeldOpen, !(to == .hidden && showsActivity) else { return }
        openedByHover = false
        transition(to: to)
        scheduleLeaveTimer()   // expanded → compact → hidden
    }

    private func cancelTimer() {
        timer?.cancel()
        timer = nil
    }

    private func transition(to new: State) {
        guard new != state else { return }
        let old = state
        state = new
        onTransition?(old, new)
    }
}

// MARK: - Live scheduling

extension IslandStateMachine {
    /// One-shot `Timer` with ≥10% tolerance so the system can coalesce wakeups.
    static let liveSchedule: Schedule = { delay, work in
        let timer = Timer(timeInterval: delay, repeats: false) { _ in
            MainActor.assumeIsolated { work() }
        }
        timer.tolerance = max(0.05, delay * 0.1)
        RunLoop.main.add(timer, forMode: .common)
        return LiveTimer(timer)
    }

    private final class LiveTimer: IslandTimer {
        private let timer: Timer
        init(_ timer: Timer) { self.timer = timer }
        func cancel() { timer.invalidate() }
    }
}
