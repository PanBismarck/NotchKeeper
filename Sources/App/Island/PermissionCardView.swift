import SwiftUI

/// Shown instead of the session list while Claude Code waits for a permission decision.
struct PermissionCardView: View {
    let request: PermissionRequest
    /// Requests still waiting behind this one.
    let queued: Int
    /// `nil` = "answer in the terminal" (the hook returns nothing and Claude asks as usual).
    let onDecide: (PermissionDecision?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: ToolSummary.symbol(for: request.tool))
                    .foregroundStyle(.orange)
                Text(request.title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(queued > 0 ? "\(request.project) · +\(queued)" : request.project)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.45))
                    .lineLimit(1)
            }
            if let detail = request.detail {
                DetailBox(text: detail, truncated: request.detailTruncated)
            }
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                if request.detailTruncated {
                    // Too long to show whole → no one-click approval of something the card can't show.
                    Spacer(minLength: 0)
                    Button("Odrzuć") { onDecide(.deny) }
                        .buttonStyle(CardButtonStyle(fill: .white.opacity(0.12), text: .white))
                    Button("W terminalu") { onDecide(nil) }
                        .buttonStyle(CardButtonStyle(fill: .orange, text: .black))
                } else {
                    Button("W terminalu") { onDecide(nil) }
                        .buttonStyle(CardButtonStyle(fill: .clear, text: .white.opacity(0.5)))
                    Spacer(minLength: 0)
                    Button("Odrzuć") { onDecide(.deny) }
                        .buttonStyle(CardButtonStyle(fill: .white.opacity(0.12), text: .white))
                    if request.canAlwaysAllow {
                        Button("Zawsze") { onDecide(.always) }
                            .buttonStyle(CardButtonStyle(fill: .white.opacity(0.12), text: .white))
                    }
                    Button("Pozwól") { onDecide(.allow) }
                        .buttonStyle(CardButtonStyle(fill: .orange, text: .black))
                }
            }
        }
        .foregroundStyle(.white)
    }
}

/// Everything "Pozwól" approves, scrollable instead of cut off. A marker stays until the end has been seen.
private struct DetailBox: View {
    let text: String
    let truncated: Bool
    @State private var scroll = ScrollState()
    /// About three lines of 11 pt monospaced.
    private static let maxHeight: CGFloat = 40

    private struct ScrollState: Equatable {
        var contentHeight: CGFloat = 0
        var moreBelow = false
    }

    var body: some View {
        ScrollView(.vertical) {
            Text(text)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.white.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: min(max(scroll.contentHeight, 13), Self.maxHeight))
        .onScrollGeometryChange(for: ScrollState.self) { geo in
            ScrollState(contentHeight: geo.contentSize.height,
                        moreBelow: geo.visibleRect.maxY < geo.contentSize.height - 2)
        } action: { _, new in scroll = new }
        .overlay(alignment: .bottomTrailing) {
            if scroll.moreBelow || truncated {
                Text(truncated ? "za długie — odpowiedz w terminalu" : "przewiń ↓")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(.orange, in: Capsule())
                    .allowsHitTesting(false)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
    }
}

private struct CardButtonStyle: ButtonStyle {
    let fill: Color
    let text: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(text)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(fill, in: Capsule())
            .opacity(configuration.isPressed ? 0.6 : 1)
            .contentShape(Capsule())
    }
}
