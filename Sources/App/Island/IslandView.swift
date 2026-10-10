import SwiftUI

@MainActor @Observable
final class IslandModel {
    var state: IslandStateMachine.State = .hidden
    var geometry: NotchGeometry
    var sessions = SessionStore()
    var permissions = PermissionQueue()
    /// Glass behind the expanded island (setting); otherwise solid black.
    var glass = true
    /// How see-through the glass is, 0...1 (setting).
    var glassTransparency = 0.6
    var onDecide: (UUID, PermissionDecision?) -> Void = { _, _ in }
    /// SwiftUI's window opener, captured from the island view so AppKit (the right-click menu) can open scenes.
    @ObservationIgnored var openWindow: OpenWindowAction?

    init(geometry: NotchGeometry) { self.geometry = geometry }
}

struct IslandView: View {
    let model: IslandModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let size = model.geometry.panelSize(for: model.state)
        let notch = model.geometry.size
        let showsList = model.state == .expanded && model.permissions.current == nil
        let glassy = model.glass && model.state == .expanded
        let shape = NotchShape(bottomRadius: model.state == .expanded ? 22 : 10)
        // Glass is only built while expanded, so a resting island never keeps a live blur (battery).
        // The notch band stays black to blend into the hardware notch and fades into the glass below.
        ZStack(alignment: .top) {
            if glassy {
                IslandGlass(shape: shape, transparency: model.glassTransparency)
                    .transition(.opacity)
            }
            shape.fill(.black.opacity(glassy ? 0 : 1))
            if glassy {
                let band = (NotchGeometry.topOverhang + notch.height) / max(size.height, 1)
                shape.fill(LinearGradient(stops: [.init(color: .black, location: 0),
                                                  .init(color: .black, location: band),
                                                  .init(color: .clear, location: min(band + 0.15, 1))],
                                          startPoint: .top, endPoint: .bottom))
                    .transition(.opacity)
            }
        }
            .environment(\.colorScheme, .dark)
            .overlay(alignment: .top) {
                if model.state != .hidden {
                    VStack(spacing: 0) {
                        // The big mascot sits by the session list; elsewhere the small one lives in the left ear.
                        EarsView(store: model.sessions, notchWidth: notch.width,
                                 showsMascot: !showsList)
                            .frame(height: notch.height + (model.state == .compact && model.geometry.hasNotch
                                                           ? NotchGeometry.compactExtraHeight : 0))
                        if model.state == .expanded, let request = model.permissions.current {
                            PermissionCardView(request: request, queued: model.permissions.items.count - 1) {
                                model.onDecide(request.id, $0)
                            }
                            .id(request.id)
                            .padding(.horizontal, 18)
                            .padding(.top, 18)
                            .padding(.bottom, 12)
                            .frame(maxHeight: .infinity, alignment: .top)
                        } else if showsList {
                            HStack(alignment: .top, spacing: 14) {
                                MascotView(status: model.sessions.primary?.status)
                                    .frame(width: 44, height: 44)
                                SessionListView(store: model.sessions)
                            }
                                .padding(.horizontal, 18)
                                .padding(.top, 18)
                                .padding(.bottom, 12)
                                .frame(maxHeight: .infinity, alignment: .top)
                        }
                    }
                    .padding(.top, NotchGeometry.topOverhang)
                    .padding(.horizontal, NotchGeometry.flare)
                    .transition(.opacity)
                }
            }
            .frame(width: size.width, height: size.height)
            .clipped()
            // Panel may be larger than the shape mid-animation; stay pinned to the top centre.
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .onAppear { model.openWindow = openWindow }
    }
}

/// Glass whose see-through amount follows the slider: frosted `.regular` fades into the clearer
/// `.clear` variant. A light black layer keeps the island's white text readable on any wallpaper.
private struct IslandGlass: View {
    let shape: NotchShape
    /// 0 = frosted, 1 = as clear as it gets.
    let transparency: Double

    var body: some View {
        let frost = 1 - transparency
        let shade = shape.fill(.black.opacity(0.15 + 0.3 * frost))
        if #available(macOS 26, *) {
            ZStack {
                Color.clear.glassEffect(.clear, in: shape)
                Color.clear.glassEffect(.regular, in: shape).opacity(frost)
            }
            .overlay(shade)
        } else {
            shape.fill(.ultraThinMaterial).opacity(0.25 + 0.75 * frost).overlay(shade)
        }
    }
}
