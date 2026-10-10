import Foundation
import Testing

struct DemoScriptTests {
    private var events: [HookEvent] {
        DemoScript.steps.compactMap { if case .event(let e) = $0 { e } else { nil } }
    }

    @Test func everyStepParses() {
        // A malformed event turns into `.pause(0)`.
        let broken = DemoScript.steps.filter { if case .pause(let s) = $0 { s == 0 } else { false } }
        #expect(broken.isEmpty)
    }

    @Test func coversEveryIslandState() {
        var store = SessionStore()
        var seen = Set<Session.Status>()
        var permissions = 0
        let now = Date()
        for event in events {
            store.apply(event, at: now)
            if PermissionRequest(event: event, at: now) != nil { permissions += 1 }
            seen.formUnion(store.sessions.map(\.status))
        }
        #expect(seen.isSuperset(of: [.working, .waiting, .done, .error]))
        #expect(permissions == 1)
        #expect(Set(store.sessions.map(\.id)) == Set(DemoScript.sessionIDs))
    }
}
