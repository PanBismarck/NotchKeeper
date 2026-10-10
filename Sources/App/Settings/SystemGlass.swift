import AppKit

/// The macOS Liquid Glass look (Appearance → clear / tinted) and Accessibility → Reduce transparency.
/// Change notifications only — KVO on the global default plus the accessibility notification, no polling.
@MainActor
final class SystemGlass: NSObject {
    private static let tintKey = "NSGlassTintAmount"
    var onChange: () -> Void = {}
    private var accessibilityObserver: NSObjectProtocol?

    /// Reduce transparency always wins: frosted glass.
    static var reduceTransparency: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency }

    /// Transparency the system asks for: 0 = tinted/frosted, 1 = clear.
    static var transparency: Double {
        if reduceTransparency { return 0 }
        let tint = UserDefaults.standard.object(forKey: tintKey) as? Double ?? 0
        return 1 - min(max(tint, 0), 1)
    }

    override init() {
        super.init()
        UserDefaults.standard.addObserver(self, forKeyPath: Self.tintKey, options: [], context: nil)
        accessibilityObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.onChange() }
        }
    }

    nonisolated override func observeValue(forKeyPath keyPath: String?, of object: Any?,
                                           change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
        nonisolated(unsafe) let me = self
        DispatchQueue.main.async { MainActor.assumeIsolated { me.onChange() } }
    }
}
