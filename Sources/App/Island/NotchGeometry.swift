import AppKit

/// Resting size of the island on a given screen: the real notch, or a small pill on screens without one.
struct NotchGeometry: Equatable {
    static let fallbackNotchWidth: CGFloat = 185
    static let pillSize = CGSize(width: 90, height: 22)
    /// Width of NotchShape's outward top flare on each side; the panel is widened by it so the body covers the notch.
    static let flare: CGFloat = 6

    let hasNotch: Bool
    let size: CGSize

    init(screenWidth: CGFloat, safeAreaTop: CGFloat,
         auxLeftWidth: CGFloat?, auxRightWidth: CGFloat?, menuBarHeight: CGFloat) {
        hasNotch = safeAreaTop > 0
        guard hasNotch else {
            size = CGSize(width: Self.pillSize.width, height: min(Self.pillSize.height, menuBarHeight))
            return
        }
        var width = Self.fallbackNotchWidth
        if let left = auxLeftWidth, let right = auxRightWidth {
            let measured = screenWidth - left - right
            if measured > 0, measured < screenWidth { width = measured }
        }
        size = CGSize(width: width, height: safeAreaTop)
    }

    init(screen: NSScreen) {
        let visibleMenuBar = screen.frame.maxY - screen.visibleFrame.maxY
        self.init(screenWidth: screen.frame.width,
                  safeAreaTop: screen.safeAreaInsets.top,
                  auxLeftWidth: screen.auxiliaryTopLeftArea?.width,
                  auxRightWidth: screen.auxiliaryTopRightArea?.width,
                  menuBarHeight: visibleMenuBar > 0 ? visibleMenuBar : NSStatusBar.system.thickness)
    }

    /// Extra width on each side of the notch in `.compact`.
    static let earWidth: CGFloat = 48
    /// The physical notch reaches a few points below `safeAreaInsets.top`; the ears go that far too.
    static let compactExtraHeight: CGFloat = 4
    /// Minimum size of `.expanded`: width, and height of the body below the notch.
    static let expandedWidth: CGFloat = 380
    static let expandedBodyHeight: CGFloat = 150

    /// The panel pokes this far above the screen: the pointer pinned to the top edge sits exactly
    /// on the frame's max-Y edge, which AppKit hit-testing excludes, so clicks there were lost.
    static let topOverhang: CGFloat = 1

    /// Size of the visible island in `state`, including the flares and the top overhang.
    func panelSize(for state: IslandStateMachine.State) -> CGSize {
        let s = bodySize(for: state)
        return CGSize(width: s.width, height: s.height + Self.topOverhang)
    }

    private func bodySize(for state: IslandStateMachine.State) -> CGSize {
        let flares = 2 * Self.flare
        switch state {
        case .hidden:
            return CGSize(width: size.width + flares, height: size.height)
        case .compact:
            let extra = hasNotch ? Self.compactExtraHeight : 0
            return CGSize(width: size.width + 2 * Self.earWidth + flares, height: size.height + extra)
        case .expanded:
            let width = max(size.width + 2 * Self.earWidth, Self.expandedWidth)
            return CGSize(width: width + flares, height: size.height + Self.expandedBodyHeight)
        }
    }

    /// Largest panel over all states: the fixed size of the SwiftUI canvas.
    var maxPanelSize: CGSize { panelSize(for: .expanded) }

    /// Panel frame in screen coordinates: top-centre of `screen`, growing downwards.
    func frame(for state: IslandStateMachine.State, on screen: NSScreen) -> NSRect {
        let sf = screen.frame
        let s = panelSize(for: state)
        return NSRect(x: sf.midX - s.width / 2, y: sf.maxY + Self.topOverhang - s.height, width: s.width, height: s.height)
    }

    /// The display named `preferred` if connected, else the one with a built-in notch, else the main one.
    @MainActor static func targetScreen(preferred: String = "") -> NSScreen? {
        NSScreen.screens.first { !preferred.isEmpty && $0.localizedName == preferred }
            ?? NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main ?? NSScreen.screens.first
    }
}
