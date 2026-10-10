import SwiftUI

extension Session.Status {
    var color: Color {
        switch self {
        case .working: Color(red: 0.85, green: 0.47, blue: 0.34)
        case .waiting: .yellow
        case .idle: .gray
        case .done: .green
        case .error: .red
        }
    }

    var label: String {
        switch self {
        case .working: "pracuje"
        case .waiting: "czeka na Ciebie"
        case .idle: "bezczynna"
        case .done: "gotowe"
        case .error: "błąd"
        }
    }
}

struct StatusDot: View {
    let status: Session.Status
    var size: CGFloat = 8

    var body: some View {
        Circle().fill(status.color).frame(width: size, height: size)
    }
}

/// Content of the two ears beside the notch: mascot or status dot (+ session count) left, current tool right.
struct EarsView: View {
    let store: SessionStore
    let notchWidth: CGFloat
    /// False shows a plain status dot instead of the mascot (the big one is on screen).
    var showsMascot = true

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 3) {
                if let primary = store.primary {
                    if showsMascot {
                        MascotView(status: primary.status)
                            .frame(width: 20, height: 20)
                    } else {
                        StatusDot(status: primary.status)
                    }
                    if store.sessions.count > 1 {
                        Text("\(store.sessions.count)").font(.system(size: 10, weight: .semibold).monospacedDigit())
                    }
                }
            }
            .frame(maxWidth: .infinity)
            Color.clear.frame(width: notchWidth)
            Group {
                if let primary = store.primary {
                    if primary.status == .working {
                        // Claude-style spinning sparkles while it works.
                        SpinningSymbol(name: "sparkles", color: NSColor(primary.status.color))
                            .frame(width: 20, height: 20)
                    } else {
                        Image(systemName: primary.status == .done ? "checkmark" : ToolSummary.symbol(for: primary.tool))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(primary.status.color)
                            .contentTransition(.symbolEffect(.replace))
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
        .foregroundStyle(.white.opacity(0.85))
    }
}

/// Body of the expanded island, below the notch.
struct SessionListView: View {
    let store: SessionStore
    static let maxRows = 3

    var body: some View {
        if store.sessions.isEmpty {
            Text("Brak aktywnych sesji Claude Code")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.5))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if store.sessions.count == 1, let only = store.sessions.first {
            VStack(alignment: .leading, spacing: 6) {
                SessionRow(session: only)
                ForEach(Array(only.steps.dropLast().suffix(3).reversed().enumerated()), id: \.offset) { _, step in
                    Text(step.text)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.4))
                        .lineLimit(1)
                        .padding(.leading, 16)
                }
                Spacer(minLength: 0)
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(store.sessions.prefix(Self.maxRows)) { SessionRow(session: $0) }
                if store.sessions.count > Self.maxRows {
                    Text("+\(store.sessions.count - Self.maxRows) więcej")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.4))
                }
                Spacer(minLength: 0)
            }
        }
    }
}

struct SessionRow: View {
    let session: Session

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                StatusDot(status: session.status)
                Text(session.project)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                Text(session.status.label)
                    .font(.system(size: 11))
                    .foregroundStyle(session.status.color)
                Spacer(minLength: 4)
                // Ticks only while this row is on screen (expanded) — no app-level timer.
                Text(session.startedAt, style: .timer)
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.4))
            }
            if let detail = session.detail ?? session.steps.last?.text {
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
                    .padding(.leading, 16)
            }
        }
        .foregroundStyle(.white)
    }
}
