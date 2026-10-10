import Foundation
import Testing

struct MascotTests {
    @Test func moodFollowsStatus() {
        #expect(MascotMood(nil) == .idle)
        #expect(MascotMood(.idle) == .idle)
        #expect(MascotMood(.working) == .working)
        #expect(MascotMood(.waiting) == .waiting)
        #expect(MascotMood(.done) == .happy)
        #expect(MascotMood(.error) == .error)
    }

    @Test func blinksOncePerPeriod() {
        for cycle in 0..<50 {
            let start = Mascot.blinkStart(cycle: Double(cycle))
            #expect(start >= Double(cycle) * Mascot.blinkPeriod)
            #expect(start + Mascot.blinkDuration <= Double(cycle + 1) * Mascot.blinkPeriod + 1e-9)
            #expect(Mascot.blink(at: start + Mascot.blinkDuration / 2) < 0.01)   // closed mid-blink
            #expect(Mascot.blink(at: start + Mascot.blinkDuration + 0.01) == 1)
        }
    }

    @Test func blinkMomentVaries() {
        let offsets = (0..<10).map { Mascot.blinkStart(cycle: Double($0)) - Double($0) * Mascot.blinkPeriod }
        #expect(Set(offsets.map { ($0 * 100).rounded() }).count > 5)
    }

    @Test func lookPointsAtCursorAndIgnoresFarAway() {
        let center = CGPoint(x: 100, y: 100)
        let right = Mascot.look(from: center, toward: CGPoint(x: 400, y: 100))!
        #expect(right.dx == 1 && right.dy == 0)
        let near = Mascot.look(from: center, toward: CGPoint(x: 100, y: 145))!
        #expect(near.dx == 0 && abs(near.dy - 0.5) < 1e-9)   // halfway to full strength
        #expect(Mascot.look(from: center, toward: CGPoint(x: 100, y: 100 + Mascot.lookReach + 1)) == nil)
    }

    @Test func cursorOverridesMoodGaze() {
        let look = CGVector(dx: -1, dy: 0)
        #expect(Mascot.pose(mood: .working, time: 3, elapsed: 3, cursor: look).look == look)
        #expect(Mascot.pose(mood: .waiting, time: 3, elapsed: 3, cursor: nil).look.dy < 0)
    }

    @Test func faces() {
        #expect(Mascot.pose(mood: .happy, time: 1, elapsed: 5, cursor: nil).eyes == .happy)
        #expect(Mascot.pose(mood: .error, time: 1, elapsed: 5, cursor: nil).eyes == .cross)
        #expect(Mascot.pose(mood: .working, time: 1, elapsed: 5, cursor: nil).eyes == .round)
    }

    @Test func happyJumpsOnceThenRests() {
        let mid = Mascot.pose(mood: .happy, time: 0, elapsed: Mascot.jumpDuration / 2, cursor: nil)
        #expect(mid.shift.dy < -0.1)
        let a = Mascot.pose(mood: .happy, time: 10, elapsed: 10, cursor: nil)
        let b = Mascot.pose(mood: .happy, time: 20, elapsed: 20, cursor: nil)
        #expect(a == b)
    }

    @Test func idleIsStaticBetweenBlinks() {
        let start = Mascot.blinkStart(cycle: 3)
        let a = Mascot.pose(mood: .idle, time: start - 1, elapsed: 100, cursor: nil)
        let b = Mascot.pose(mood: .idle, time: start - 0.2, elapsed: 100, cursor: nil)
        #expect(a == b)
    }

    // MARK: - Frame schedule (battery)

    let interval = 1.0 / 30

    @Test func activeMoodsOnlyBlink() {
        let start = Mascot.blinkStart(cycle: 4)
        #expect(Mascot.nextFrame(after: start - 0.5, mood: .working, since: 0, interval: interval) == start)
        #expect(Mascot.nextFrame(after: start - 0.5, mood: .waiting, since: 0, interval: interval) == start)
    }

    @Test func idleWakesOnlyForBlinks() {
        let start = Mascot.blinkStart(cycle: 4)
        #expect(Mascot.nextFrame(after: start - 0.5, mood: .idle, since: 0, interval: interval) == start)
        #expect(Mascot.nextFrame(after: start, mood: .idle, since: 0, interval: interval) == start + interval)
        let end = Mascot.nextFrame(after: start + Mascot.blinkDuration - 0.01, mood: .idle, since: 0, interval: interval)
        #expect(end == start + Mascot.blinkDuration)
        #expect(Mascot.nextFrame(after: start + Mascot.blinkDuration, mood: .idle, since: 0, interval: interval)
                == Mascot.blinkStart(cycle: 5))

        // Over a minute of idle: only a handful of frames per blink.
        var t = 0.0, frames = 0
        while let next = Mascot.nextFrame(after: t, mood: .idle, since: -100, interval: interval), next < 60 {
            t = next; frames += 1
        }
        #expect(Double(frames) < 60 / Mascot.blinkPeriod * 8)
    }

    @Test func reactionsEndInStillness() {
        #expect(Mascot.nextFrame(after: 10, mood: .happy, since: 10, interval: interval) == 10 + interval)
        #expect(Mascot.nextFrame(after: 10.59, mood: .happy, since: 10, interval: interval) == 10 + Mascot.jumpDuration)
        #expect(Mascot.nextFrame(after: 10 + Mascot.jumpDuration, mood: .happy, since: 10, interval: interval) == nil)
        #expect(Mascot.nextFrame(after: 20, mood: .error, since: 10, interval: interval) == nil)
    }
}
