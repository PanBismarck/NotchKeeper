import SwiftUI

/// Redraws only when `Mascot.nextFrame` asks for it: continuous while working/waiting,
/// otherwise just for reactions and blinks. Gone entirely while the island is hidden.
struct MascotSchedule: TimelineSchedule {
    let mood: MascotMood
    let since: Date
    let interval: Double

    func entries(from startDate: Date, mode: Mode) -> AnySequence<Date> {
        let since = since.timeIntervalSinceReferenceDate
        let (mood, interval) = (mood, interval)
        return AnySequence(sequence(first: startDate.timeIntervalSinceReferenceDate) {
            Mascot.nextFrame(after: $0, mood: mood, since: since, interval: interval)
        }.lazy.map(Date.init(timeIntervalSinceReferenceDate:)))
    }
}

/// The notch mascot: a small squishy blob whose colour and face follow the session status.
struct MascotView: View {
    static let headroom: CGFloat = 6
    let status: Session.Status?
    @State private var moodSince = Date()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let mood = MascotMood(status)
        let color = status?.color ?? Session.Status.idle.color
        let interval = ProcessInfo.processInfo.isLowPowerModeEnabled ? 1.0 / 15 : 1.0 / 30
        Group {
            if reduceMotion {
                // A fixed, eyes-open pose with no reactions. (A one-entry TimelineView draws nothing.)
                canvas(Mascot.pose(mood: mood, time: 0, elapsed: .infinity, cursor: nil), color: color)
            } else {
                TimelineView(MascotSchedule(mood: mood, since: moodSince, interval: interval)) { timeline in
                    let pose = Mascot.pose(mood: mood, time: timeline.date.timeIntervalSinceReferenceDate,
                                           elapsed: timeline.date.timeIntervalSince(moodSince), cursor: nil)
                    canvas(pose, color: color)
                }
            }
        }
        .onChange(of: mood) { moodSince = .now }
        .accessibilityHidden(true)
    }

    private func canvas(_ pose: MascotPose, color: Color) -> some View {
        // The canvas reaches above the frame so the antenna and hops never get cut off.
        Canvas { context, size in
            context.translateBy(x: 0, y: Self.headroom)
            MascotRenderer.draw(pose, color: color, in: &context,
                                size: CGSize(width: size.width, height: size.height - Self.headroom))
        }
        .padding(.top, -Self.headroom)
    }
}

enum MascotRenderer {
    static func draw(_ pose: MascotPose, color: Color, in context: inout GraphicsContext, size: CGSize) {
        let s = min(size.width, size.height)
        let width = s * 0.82 * pose.squash
        let height = s * 0.72 / pose.squash
        // Feet stay on the floor: squash grows sideways, shift moves the whole body.
        let floor = size.height / 2 + s * 0.43
        let center = CGPoint(x: size.width / 2 + pose.shift.dx * s,
                             y: floor - height / 2 + pose.shift.dy * s)

        var ctx = context
        ctx.translateBy(x: center.x, y: floor)
        ctx.rotate(by: .radians(pose.tilt))
        ctx.translateBy(x: -center.x, y: -floor)

        // Antenna, lagging a little behind the head.
        let top = CGPoint(x: center.x, y: center.y - height / 2)
        let tip = CGPoint(x: top.x + pose.look.dx * s * 0.05 + s * 0.04, y: top.y - s * 0.14)
        var antenna = Path()
        antenna.move(to: top)
        antenna.addQuadCurve(to: tip, control: CGPoint(x: top.x, y: top.y - s * 0.1))
        ctx.stroke(antenna, with: .color(color.opacity(0.9)), style: StrokeStyle(lineWidth: max(1, s * 0.05), lineCap: .round))
        let r = s * 0.065
        ctx.fill(Path(ellipseIn: CGRect(x: tip.x - r, y: tip.y - r, width: 2 * r, height: 2 * r)), with: .color(color))

        // Body.
        let body = CGRect(x: center.x - width / 2, y: center.y - height / 2, width: width, height: height)
        let shape = Path(roundedRect: body, cornerRadius: min(width, height) * 0.42, style: .continuous)
        ctx.fill(shape, with: .linearGradient(Gradient(colors: [color.mix(with: .white, by: 0.25), color]),
                                              startPoint: CGPoint(x: body.midX, y: body.minY),
                                              endPoint: CGPoint(x: body.midX, y: body.maxY)))

        // Eyes.
        let eyeColor = Color.black.opacity(0.85)
        let spacing = width * 0.22
        let eyeW = s * 0.11 * pose.eyeScale
        let eyeH = s * 0.17 * pose.eyeScale
        let gaze = CGPoint(x: pose.look.dx * width * 0.12, y: pose.look.dy * height * 0.1)
        for side in [-1.0, 1.0] {
            let c = CGPoint(x: center.x + side * spacing + gaze.x, y: center.y - height * 0.04 + gaze.y)
            switch pose.eyes {
            case .round:
                let h = max(eyeH * pose.eyeOpen, s * 0.025)
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - eyeW / 2, y: c.y - h / 2, width: eyeW, height: h)), with: .color(eyeColor))
            case .happy:
                var arc = Path()
                arc.move(to: CGPoint(x: c.x - eyeW * 0.7, y: c.y + eyeH * 0.2))
                arc.addQuadCurve(to: CGPoint(x: c.x + eyeW * 0.7, y: c.y + eyeH * 0.2),
                                 control: CGPoint(x: c.x, y: c.y - eyeH * 0.6))
                ctx.stroke(arc, with: .color(eyeColor), style: StrokeStyle(lineWidth: max(1, s * 0.05), lineCap: .round))
            case .cross:
                let d = eyeW * 0.6
                var cross = Path()
                cross.move(to: CGPoint(x: c.x - d, y: c.y - d)); cross.addLine(to: CGPoint(x: c.x + d, y: c.y + d))
                cross.move(to: CGPoint(x: c.x + d, y: c.y - d)); cross.addLine(to: CGPoint(x: c.x - d, y: c.y + d))
                ctx.stroke(cross, with: .color(eyeColor), style: StrokeStyle(lineWidth: max(1, s * 0.045), lineCap: .round))
            }
        }
    }
}
