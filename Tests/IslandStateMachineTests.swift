import Foundation
import Testing

/// Manual clock: timers fire only when the test advances time.
@MainActor
final class FakeClock {
    final class Entry: IslandTimer {
        let due: TimeInterval
        let work: @MainActor @Sendable () -> Void
        var cancelled = false
        init(due: TimeInterval, work: @escaping @MainActor @Sendable () -> Void) { self.due = due; self.work = work }
        func cancel() { cancelled = true }
    }

    private(set) var now: TimeInterval = 0
    private var entries: [Entry] = []

    var pending: Int { entries.filter { !$0.cancelled }.count }

    func schedule(_ delay: TimeInterval, _ work: @escaping @MainActor @Sendable () -> Void) -> any IslandTimer {
        let e = Entry(due: now + delay, work: work)
        entries.append(e)
        return e
    }

    func advance(_ dt: TimeInterval) {
        let end = now + dt
        while let next = entries.filter({ !$0.cancelled && $0.due <= end }).min(by: { $0.due < $1.due }) {
            now = next.due
            next.cancelled = true
            next.work()
        }
        now = end
        entries.removeAll { $0.cancelled }
    }
}

@MainActor
struct IslandStateMachineTests {
    let clock = FakeClock()
    let fsm: IslandStateMachine

    init() {
        let clock = clock
        fsm = IslandStateMachine(schedule: { clock.schedule($0, $1) })
        fsm.compactHideDelay = 1
        fsm.expandedCollapseDelay = 4
        fsm.hoverCloseDelay = 0.5
        fsm.hoverExpandDelay = nil   // dwell has its own tests
    }

    @Test func dwellingOnCompactExpands() {
        fsm.hoverExpandDelay = 0.6
        fsm.mouseEntered()
        #expect(fsm.state == .compact)
        clock.advance(0.6)
        #expect(fsm.state == .expanded)
        #expect(fsm.openedByHover)
        fsm.mouseExited()
        clock.advance(0.5)
        #expect(fsm.state == .compact)
    }

    @Test func leavingBeforeDwellDoesNotExpand() {
        fsm.hoverExpandDelay = 0.6
        fsm.mouseEntered()
        clock.advance(0.3)
        fsm.mouseExited()
        clock.advance(0.5)
        #expect(fsm.state == .compact)
        clock.advance(1)
        #expect(fsm.state == .hidden)
    }

    @Test func startsHidden() {
        #expect(fsm.state == .hidden)
        #expect(clock.pending == 0)
    }

    @Test func hoverPeeksCompactAndHidesAfterLeave() {
        fsm.mouseEntered()
        #expect(fsm.state == .compact)
        #expect(clock.pending == 0)   // no timer while the pointer is inside
        fsm.mouseExited()
        clock.advance(0.9)
        #expect(fsm.state == .compact)
        clock.advance(0.2)
        #expect(fsm.state == .hidden)
        #expect(clock.pending == 0)
    }

    @Test func reenteringCancelsHideTimer() {
        fsm.mouseEntered(); fsm.mouseExited()
        clock.advance(0.5)
        fsm.mouseEntered()
        clock.advance(10)
        #expect(fsm.state == .compact)
    }

    @Test func clickExpands() {
        fsm.mouseEntered(); fsm.click()
        #expect(fsm.state == .expanded)
    }

    @Test func clickWorksFromHidden() {
        fsm.click()
        #expect(fsm.state == .expanded)
    }

    @Test func leavingExpandedCollapsesInSteps() {
        fsm.mouseEntered(); fsm.click(); fsm.mouseExited()
        clock.advance(3.9)
        #expect(fsm.state == .expanded)
        clock.advance(0.2)
        #expect(fsm.state == .compact)
        clock.advance(1)
        #expect(fsm.state == .hidden)
    }

    @Test func escapeWithPointerInsideGoesCompact() {
        fsm.mouseEntered(); fsm.click(); fsm.dismiss()
        #expect(fsm.state == .compact)
        #expect(clock.pending == 0)
    }

    @Test func clickOutsideHidesImmediately() {
        fsm.mouseEntered(); fsm.click(); fsm.mouseExited(); fsm.dismiss()
        #expect(fsm.state == .hidden)
        #expect(clock.pending == 0)
    }

    @Test func dismissIgnoredWhenNotExpanded() {
        fsm.mouseEntered(); fsm.dismiss()
        #expect(fsm.state == .compact)
    }

    @Test func openOnHoverExpandsAndClosesQuickly() {
        fsm.openOnHover = true
        fsm.mouseEntered()
        #expect(fsm.state == .expanded)
        #expect(fsm.openedByHover)
        fsm.mouseExited()
        clock.advance(0.6)
        #expect(fsm.state == .compact)
    }

    @Test func clickPinsHoverOpenedIsland() {
        fsm.openOnHover = true
        fsm.mouseEntered(); fsm.click(); fsm.mouseExited()
        #expect(!fsm.openedByHover)
        clock.advance(1)
        #expect(fsm.state == .expanded)   // normal 4 s delay now
    }

    @Test func heldOpenIgnoresLeaveAndTimers() {
        fsm.setHeldOpen(true)
        #expect(fsm.state == .expanded)
        fsm.mouseEntered(); fsm.mouseExited()
        clock.advance(100)
        #expect(fsm.state == .expanded)
        #expect(clock.pending == 0)
    }

    @Test func releasingHoldStartsCollapse() {
        fsm.setHeldOpen(true)
        fsm.setHeldOpen(false)
        clock.advance(4.1)
        #expect(fsm.state == .compact)
        clock.advance(1)
        #expect(fsm.state == .hidden)
    }

    @Test func releasingHoldWithPointerInsideStaysOpen() {
        fsm.setHeldOpen(true); fsm.mouseEntered(); fsm.setHeldOpen(false)
        clock.advance(100)
        #expect(fsm.state == .expanded)
    }

    @Test func dismissWorksWhileHeld() {
        fsm.setHeldOpen(true); fsm.dismiss()
        #expect(fsm.state == .hidden)
    }

    @Test func holdingAgainReopensDismissed() {
        fsm.setHeldOpen(true); fsm.dismiss()
        fsm.setHeldOpen(true)
        #expect(fsm.state == .expanded)
    }

    @Test func transitionsAreReported() {
        var log: [IslandStateMachine.State] = []
        fsm.onTransition = { _, new in log.append(new) }
        fsm.mouseEntered(); fsm.click(); fsm.mouseExited()
        clock.advance(10)
        #expect(log == [.compact, .expanded, .compact, .hidden])
    }

    @Test func atMostOneTimerPending() {
        fsm.mouseEntered(); fsm.mouseExited(); fsm.mouseEntered(); fsm.mouseExited()
        #expect(clock.pending == 1)
    }

    // MARK: - Session activity

    @Test func activityShowsEarsAndKeepsThem() {
        fsm.setActive(true)
        #expect(fsm.state == .compact)
        fsm.mouseEntered()
        fsm.mouseExited()
        clock.advance(10)
        #expect(fsm.state == .compact)
        #expect(clock.pending == 0)
    }

    @Test func expandedCollapsesToEarsWhileActive() {
        fsm.setActive(true)
        fsm.click()
        fsm.mouseExited()
        clock.advance(10)
        #expect(fsm.state == .compact)
        fsm.click()
        fsm.dismiss()
        #expect(fsm.state == .compact)
    }

    @Test func inactiveHidesEarsAfterDelay() {
        fsm.setActive(true)
        fsm.setActive(false)
        #expect(fsm.state == .compact)
        clock.advance(1)
        #expect(fsm.state == .hidden)
    }

    @Test func inactiveWhileHoveringWaitsForLeave() {
        fsm.setActive(true)
        fsm.mouseEntered()
        fsm.setActive(false)
        clock.advance(10)
        #expect(fsm.state == .compact)
        fsm.mouseExited()
        clock.advance(1)
        #expect(fsm.state == .hidden)
    }

    @Test func activityDuringPendingHideCancelsIt() {
        fsm.mouseEntered()
        fsm.mouseExited()          // hide timer armed
        fsm.setActive(true)
        clock.advance(10)
        #expect(fsm.state == .compact)
    }

    // MARK: - Tucked (full screen)

    @Test func tuckingHidesActiveEarsAndUntuckingBringsThemBack() {
        fsm.setActive(true)
        fsm.isTucked = true
        #expect(fsm.state == .hidden)
        clock.advance(10)
        #expect(fsm.state == .hidden)
        fsm.isTucked = false
        #expect(fsm.state == .compact)
    }

    @Test func tuckedHoverShowsEarsWithoutExpanding() {
        fsm.isTucked = true
        fsm.setActive(true)
        #expect(fsm.state == .hidden)
        fsm.mouseEntered()
        clock.advance(5)
        #expect(fsm.state == .compact)
        fsm.click()
        #expect(fsm.state == .expanded)
    }

    @Test func tuckedLeaveTucksEarsAwayDespiteActivity() {
        fsm.isTucked = true
        fsm.setActive(true)
        fsm.mouseEntered()
        fsm.mouseExited()
        clock.advance(5)
        #expect(fsm.state == .hidden)
    }
}
