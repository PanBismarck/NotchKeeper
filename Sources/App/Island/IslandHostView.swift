import AppKit
import SwiftUI

/// Hosts the SwiftUI island and reports hover/click via NSTrackingArea and mouseDown (event-driven, no polling).
final class IslandHostView: NSHostingView<IslandView> {
    var onMouseEntered: (() -> Void)?
    var onMouseExited: (() -> Void)?
    var onClick: (() -> Void)?
    /// Built fresh on every right-click so titles (e.g. demo on/off) are current.
    var contextMenu: (() -> NSMenu)?

    init(model: IslandModel) {
        super.init(rootView: IslandView(model: model))
        sizingOptions = []   // the controller owns the panel size, not SwiftUI
    }

    required init(rootView: IslandView) { fatalError("use init(model:)") }
    @MainActor required dynamic init?(coder: NSCoder) { fatalError("not supported") }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.filter { $0.owner === self }.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds,
                                       options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self))
    }

    override func mouseEntered(with event: NSEvent) { onMouseEntered?() }
    override func mouseExited(with event: NSEvent) { onMouseExited?() }

    override func mouseDown(with event: NSEvent) {
        onClick?()
        super.mouseDown(with: event)
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let menu = contextMenu?() else { return super.rightMouseDown(with: event) }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
