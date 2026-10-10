import CoreGraphics
import Foundation

/// The mascot's mood, derived from the status the island shows.
enum MascotMood: Equatable, Sendable {
    case idle, working, waiting, happy, error

    init(_ status: Session.Status?) {
        switch status {
        case .working: self = .working
        case .waiting: self = .waiting
        case .done: self = .happy
        case .error: self = .error
        case .idle, nil: self = .idle
        }
    }
}

/// Everything the renderer needs for one frame. Distances are fractions of the mascot's size, y grows downwards.
struct MascotPose: Equatable, Sendable {
    enum Eyes: Equatable, Sendable { case round, happy, cross }

    var eyes: Eyes = .round
    /// 0 closed … 1 open.
    var eyeOpen: Double = 1
    var eyeScale: Double = 1
    /// Where the eyes look, each axis -1…1.
    var look = CGVector.zero
    var shift = CGVector.zero
    /// 1 = neutral, >1 wider and flatter.
    var squash: Double = 1
    /// Radians, positive = clockwise.
    var tilt: Double = 0
}

/// Pure animation curves: the pose is a function of mood, time and cursor only — no per-frame state.
enum Mascot {
    static let blinkPeriod = 3.6
    static let blinkDuration = 0.16
    /// Cursor further than this (points) is ignored and the mood's own gaze takes over.
    static let lookReach: Double = 420
    /// Cursor closer than this gets the full eye offset.
    static let lookFull: Double = 90
    static let jumpDuration = 0.6
    static let shakeDuration = 0.5

    /// Eye openness from a deterministic blink schedule: once per period, at a pseudo-random moment.
    static func blink(at t: Double) -> Double {
        let cycle = (t / blinkPeriod).rounded(.down)
        let start = blinkStart(cycle: cycle)
        let p = (t - start) / blinkDuration
        guard p >= 0, p <= 1 else { return 1 }
        return 1 - sin(.pi * p)
    }

    /// Gaze toward `point` seen from `center` (same coordinate space), or nil when the cursor is far away.
    static func look(from center: CGPoint, toward point: CGPoint) -> CGVector? {
        let dx = point.x - center.x, dy = point.y - center.y
        let dist = (dx * dx + dy * dy).squareRoot()
        guard dist <= lookReach else { return nil }
        guard dist > 0.5 else { return .zero }
        let strength = min(1, dist / lookFull)
        return CGVector(dx: dx / dist * strength, dy: dy / dist * strength)
    }

    /// - Parameters:
    ///   - time: absolute seconds, drives loops and blinking.
    ///   - elapsed: seconds since the mood changed, drives one-shot reactions (jump, shake).
    ///   - cursor: gaze from `look(from:toward:)`; nil lets the mood choose.
    static func pose(mood: MascotMood, time t: Double, elapsed: Double, cursor: CGVector?) -> MascotPose {
        var pose = MascotPose()
        pose.eyeOpen = blink(at: t)
        switch mood {
        case .idle:
            // Static apart from blinking: idle must not keep redrawing (battery).
            pose.eyeOpen *= 0.75   // a bit sleepy
            pose.look = cursor ?? CGVector(dx: 0, dy: 0.3)
        // Calm poses (battery): only blinks animate; the spinning ear icon shows activity.
        case .working:
            // Reading: eyes down and to the side.
            pose.look = cursor ?? CGVector(dx: 0.5, dy: 0.25)
        case .waiting:
            pose.tilt = 0.1
            pose.eyeScale = 1.2
            pose.look = cursor ?? CGVector(dx: 0, dy: -0.4)   // looking up at you
        case .happy:
            pose.eyes = .happy
            pose.eyeOpen = 1
            if elapsed < jumpDuration {
                let p = max(0, elapsed) / jumpDuration
                pose.shift.dy = -0.22 * sin(.pi * p)
                pose.squash = 1 - 0.12 * sin(.pi * p)
            }
            pose.look = cursor ?? .zero
        case .error:
            pose.eyes = .cross
            pose.eyeOpen = 1
            if elapsed < shakeDuration {
                let fade = 1 - max(0, elapsed) / shakeDuration
                pose.shift.dx = 0.08 * fade * sin(elapsed * 2 * .pi * 9)
            }
            pose.shift.dy = 0.04
            pose.squash = 1.06   // slumped
        }
        return pose
    }

    static func reactionDuration(_ mood: MascotMood) -> Double {
        switch mood {
        case .happy: jumpDuration
        case .error: shakeDuration
        default: 0
        }
    }

    static func blinkStart(cycle: Double) -> Double {
        cycle * blinkPeriod + jitter(Int(cycle)) * (blinkPeriod - blinkDuration)
    }

    /// When the next frame is due after `t` (seconds), or nil when the pose never changes again.
    /// Only one-shot reactions and blinks redraw; the rest of the time the frame is static.
    static func nextFrame(after t: Double, mood: MascotMood, since: Double, interval: Double) -> Double? {
        let reactionEnd = since + reactionDuration(mood)
        if t < reactionEnd { return min(t + interval, reactionEnd) }
        // Happy and error eyes have no lids: nothing left to animate.
        guard mood != .happy, mood != .error else { return nil }
        let cycle = (t / blinkPeriod).rounded(.down)
        let start = blinkStart(cycle: cycle)
        if t < start { return start }
        if t < start + blinkDuration { return min(t + interval, start + blinkDuration) }
        return blinkStart(cycle: cycle + 1)
    }

    /// Stable 0…1 value per blink cycle (splitmix64 hash) — the same time always gives the same pose.
    private static func jitter(_ n: Int) -> Double {
        var z = UInt64(bitPattern: Int64(n)) &+ 0x9E37_79B9_7F4A_7C15
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= z >> 31
        return Double(z >> 11) / Double(1 << 53)
    }
}
