import Foundation
import Testing

struct SessionAlertTests {
    private func store(_ events: [(String, String)]) -> SessionStore {
        var store = SessionStore()
        for (session, name) in events {
            let body = #"{"hook_event_name":"\#(name)","session_id":"\#(session)","message":"Claude needs your permission"}"#
            store.apply(HookEvent(argvEvent: name, payload: Data(body.utf8))!, at: Date())
        }
        return store
    }

    @Test func alertsOnlyOnStatusChange() {
        let working = store([("a", "UserPromptSubmit")])
        #expect(SessionAlert.between([], working.sessions) == nil)

        let waiting = store([("a", "UserPromptSubmit"), ("a", "Notification")])
        #expect(SessionAlert.between(working.sessions, waiting.sessions) == .waiting)
        #expect(SessionAlert.between(waiting.sessions, waiting.sessions) == nil)

        let done = store([("a", "UserPromptSubmit"), ("a", "Stop")])
        #expect(SessionAlert.between(working.sessions, done.sessions) == .done)

        let failed = store([("a", "UserPromptSubmit"), ("a", "StopFailure")])
        #expect(SessionAlert.between(working.sessions, failed.sessions) == .error)
    }

    @Test func waitingWinsOverDone() {
        let old = store([("a", "UserPromptSubmit"), ("b", "UserPromptSubmit")])
        let new = store([("a", "UserPromptSubmit"), ("b", "UserPromptSubmit"), ("a", "Stop"), ("b", "Notification")])
        #expect(SessionAlert.between(old.sessions, new.sessions) == .waiting)
    }
}
