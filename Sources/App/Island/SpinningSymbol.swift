import AppKit
import SwiftUI

/// An SF Symbol spun by Core Animation: the render server rotates it, the app does no per-frame work
/// (SwiftUI's `.symbolEffect(.rotate)` costs ~8% CPU here).
struct SpinningSymbol: NSViewRepresentable {
    let name: String
    let color: NSColor
    var pointSize: CGFloat = 11

    func makeNSView(context: Context) -> SpinningSymbolView { SpinningSymbolView() }

    func updateNSView(_ view: SpinningSymbolView, context: Context) {
        let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)
            .applying(.init(paletteColors: [color]))
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(config)
        view.symbol.contents = image
        view.needsLayout = true
    }
}

final class SpinningSymbolView: NSView {
    let symbol = CALayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        symbol.contentsGravity = .center
        layer?.addSublayer(symbol)
    }

    required init?(coder: NSCoder) { fatalError("not supported") }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        symbol.frame = bounds
        symbol.contentsScale = window?.backingScaleFactor ?? 2
        CATransaction.commit()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil, symbol.animation(forKey: "spin") == nil else { return }
        let spin = CABasicAnimation(keyPath: "transform.rotation.z")
        spin.fromValue = 0
        spin.toValue = 2 * Double.pi   // counter-clockwise on screen
        spin.duration = 2
        spin.repeatCount = .infinity
        spin.isRemovedOnCompletion = false
        symbol.add(spin, forKey: "spin")
    }
}
