import AppKit

/// Tells whether the frontmost app is in full screen on the island's display.
/// Event-driven: re-checks only on Space switches and app activation (no polling).
@MainActor
final class FullScreenWatcher {
    private(set) var isFullScreen = false
    var onChange: (Bool) -> Void = { _ in }
    var screen: NSScreen? { didSet { check() } }

    private var observers: [NSObjectProtocol] = []
    /// One-shot re-check after the Space slide animation has settled.
    private var settleCheck: DispatchWorkItem?

    func start() {
        guard observers.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didActivateApplicationNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.spaceOrAppChanged() }
            })
        }
        check()
    }

    func stop() {
        observers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
        observers = []
        settleCheck?.cancel()
        settleCheck = nil
        update(false)
    }

    /// The event can arrive before the switch has finished, so always re-check once it has settled.
    private func spaceOrAppChanged() {
        check()
        scheduleSettleCheck()
    }

    /// Hides at once, but reports "no longer full screen" only after a settle re-check: mid-transition
    /// (Space switch, screen-parameter change) the window server briefly reports the old Space,
    /// which made the island flash.
    private func check() {
        guard !observers.isEmpty, let screen else { return update(false) }
        if Self.frontAppIsFullScreen(on: screen) {
            settleCheck?.cancel()
            settleCheck = nil
            update(true)
        } else if isFullScreen, settleCheck == nil {
            scheduleSettleCheck()
        }
    }

    private func scheduleSettleCheck() {
        settleCheck?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, !self.observers.isEmpty else { return }
                self.settleCheck = nil
                self.update(self.screen.map(Self.frontAppIsFullScreen) ?? false)
            }
        }
        settleCheck = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    private func update(_ value: Bool) {
        guard value != isFullScreen else { return }
        isFullScreen = value
        onChange(value)
    }

    /// Full screen = the current Space on this display is a full-screen Space (type 4), read from the
    /// window server. Window heuristics don't work on notched displays: the menu bar stays as the
    /// black strip beside the notch. Private API, looked up at runtime — if it's gone, never hide.
    static func frontAppIsFullScreen(on screen: NSScreen) -> Bool {
        guard let api = SpacesAPI.shared,
              let spaces = api.copySpaces(api.connection())?.takeRetainedValue() as? [[String: Any]],
              let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
              let uuid = CGDisplayCreateUUIDFromDisplayID(number)?.takeRetainedValue(),
              let id = CFUUIDCreateString(nil, uuid) as String?
        else { return false }
        // With "Displays have separate Spaces" off there's one entry ("Main") for all displays.
        let display = spaces.count == 1 ? spaces.first
            : spaces.first { ($0["Display Identifier"] as? String)?.caseInsensitiveCompare(id) == .orderedSame }
        let current = display?["Current Space"] as? [String: Any]
        return current?["type"] as? Int == 4
    }
}

private struct SpacesAPI: @unchecked Sendable {
    typealias Connection = @convention(c) () -> Int32
    typealias CopySpaces = @convention(c) (Int32) -> Unmanaged<CFArray>?
    let connection: Connection
    let copySpaces: CopySpaces

    static let shared: SpacesAPI? = {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY),
              let conn = dlsym(handle, "CGSMainConnectionID"),
              let copy = dlsym(handle, "CGSCopyManagedDisplaySpaces")
        else { return nil }
        return SpacesAPI(connection: unsafeBitCast(conn, to: Connection.self),
                         copySpaces: unsafeBitCast(copy, to: CopySpaces.self))
    }()
}
