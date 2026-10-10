import AppKit

/// Borderless, non-activating panel that sits above the menu bar, on every Space and over full-screen apps.
final class NotchPanel: NSPanel {
    init(frame: NSRect) {
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 3)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isMovable = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
    }

    /// Key only while expanded by a click, so Escape reaches us; never steals focus on hover.
    var allowsKey = false
    var onEscape: (() -> Void)?

    override var canBecomeKey: Bool { allowsKey }
    override var canBecomeMain: Bool { false }

    // The panel is key only after a click, so a hover-opened island would draw its glass in the
    // inactive (flat) look. These private AppKit hooks make it always render as active — appearance only,
    // focus and key handling are untouched.
    @objc var _hasActiveAppearance: Bool { true }
    @objc var _hasActiveAppearanceIgnoringKeyFocus: Bool { true }
    @objc var _hasKeyAppearance: Bool { true }
    @objc var _hasMainAppearance: Bool { true }

    override func cancelOperation(_ sender: Any?) { onEscape?() }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onEscape?() } else { super.keyDown(with: event) }
    }

    /// Keep the panel in the menu bar / notch area instead of letting AppKit push it below.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}
