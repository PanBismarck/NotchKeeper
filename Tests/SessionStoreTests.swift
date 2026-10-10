import Foundation
import Testing

struct SessionStoreTests {
    var store = SessionStore()
    let t0 = Date(timeIntervalSince1970: 1_000_000)

    func event(_ name: String, session: String = "s1", cwd: String = "/Users/me/Notch",
               _ extra: [String: Any] = [:]) -> HookEvent {
        var body: [String: Any] = ["hook_event_name": name, "session_id": session, "cwd": cwd]
        body.merge(extra) { _, new in new }
        let data = try! JSONSerialization.data(withJSONObject: body)
        return HookEvent(argvEvent: name, payload: data)!
    }

    @Test mutating func promptToolStopLifecycle() {
        store.apply(event("SessionStart"), at: t0)
        #expect(store.sessions.first?.status == .idle)
        #expect(store.sessions.first?.project == "Notch")
        #expect(!store.hasActivity(at: t0))

        store.apply(event("UserPromptSubmit", ["prompt": "napraw\nbuild"]), at: t0 + 1)
        #expect(store.sessions[0].status == .working)
        #expect(store.sessions[0].steps.last?.text == "› napraw")
        #expect(store.hasActivity(at: t0 + 1))

        store.apply(event("PreToolUse", ["tool_name": "Edit", "tool_input": ["file_path": "/a/b/main.swift"]]), at: t0 + 2)
        #expect(store.sessions[0].tool == "Edit")
        #expect(store.sessions[0].detail == "Edit main.swift")

        store.apply(event("PostToolUse", ["tool_name": "Edit"]), at: t0 + 3)
        #expect(store.sessions[0].tool == nil)
        #expect(store.sessions[0].status == .working)

        store.apply(event("Stop", ["last_assistant_message": "Zrobione.\nDetale"]), at: t0 + 4)
        #expect(store.sessions[0].status == .done)
        #expect(store.sessions[0].detail == "Zrobione.")
        #expect(store.hasActivity(at: t0 + 4 + store.finishedLinger - 1))   // ears linger on the result
        #expect(store.nextDeadline(after: t0 + 5) == t0 + 4 + store.finishedLinger)
        #expect(!store.hasActivity(at: t0 + 4 + store.finishedLinger))
        #expect(store.nextDeadline(after: t0 + 4 + store.finishedLinger) == t0 + 4 + SessionStore.staleAfter)
        #expect(store.sessions[0].startedAt == t0)
    }

    @Test mutating func permissionAndNotificationWait() {
        store.apply(event("PermissionRequest", ["tool_name": "Bash", "tool_input": ["command": "rm -rf build"]]), at: t0)
        #expect(store.sessions[0].status == .waiting)
        #expect(store.sessions[0].detail == "Pozwolić? Bash: rm -rf build")
        store.apply(event("PostToolUse", ["tool_name": "Bash"]), at: t0 + 1)
        #expect(store.sessions[0].status == .working)
        store.apply(event("Notification", ["message": "Claude needs your permission to use Bash"]), at: t0 + 2)
        #expect(store.sessions[0].status == .waiting)
    }

    @Test mutating func idlePromptDoesNotReopenFinishedTurn() {
        store.apply(event("Stop"), at: t0)
        store.apply(event("Notification", ["message": "Claude is waiting for your input",
                                           "notification_type": "idle_prompt"]), at: t0 + 60)
        #expect(store.sessions[0].status == .done)
    }

    @Test mutating func sessionsOrderPrimaryAndEnd() {
        store.apply(event("UserPromptSubmit", session: "a"), at: t0)
        store.apply(event("Stop", session: "b", cwd: "/x/Other"), at: t0 + 1)
        #expect(store.sessions.map(\.id) == ["b", "a"])
        #expect(store.primary?.id == "a")          // working beats done
        store.apply(event("PermissionRequest", session: "b", cwd: "/x/Other", ["tool_name": "Bash"]), at: t0 + 2)
        #expect(store.primary?.id == "b")          // waiting beats working
        store.apply(event("SessionEnd", session: "b"), at: t0 + 3)
        #expect(store.sessions.map(\.id) == ["a"])
    }

    @Test mutating func pruneStaleSessions() {
        store.apply(event("UserPromptSubmit", session: "a"), at: t0)
        store.apply(event("UserPromptSubmit", session: "b"), at: t0 + 600)
        #expect(store.nextExpiry == t0 + SessionStore.staleAfter)
        let early = store.prune(now: t0 + SessionStore.staleAfter - 1)
        #expect(!early)
        let removed = store.prune(now: t0 + SessionStore.staleAfter)
        #expect(removed)
        #expect(store.sessions.map(\.id) == ["b"])
    }

    @Test mutating func ignoresEventsWithoutSession() {
        let data = try! JSONSerialization.data(withJSONObject: ["hook_event_name": "Stop"])
        store.apply(HookEvent(argvEvent: "Stop", payload: data)!, at: t0)
        #expect(store.sessions.isEmpty)
    }

    @Test func toolSummaries() {
        #expect(ToolSummary.describe(tool: "Bash", input: ["command": "ls", "description": "List files"]) == "Bash: List files")
        #expect(ToolSummary.describe(tool: "WebFetch", input: ["url": "https://example.com/a"]) == "WebFetch example.com")
        #expect(ToolSummary.describe(tool: "mcp__notion__search", input: [:]) == "search")
        #expect(ToolSummary.oneLine("  \n  a   b  \nc") == "a b")
        #expect(ToolSummary.oneLine(String(repeating: "x", count: 100)).count == ToolSummary.maxLength)
    }

    @Test func stepsAreCapped() {
        var s = Session(id: "x", cwd: nil, at: t0)
        for i in 0..<10 { s.appendStep("step \(i)", at: t0) }
        #expect(s.steps.count == Session.maxSteps)
        #expect(s.steps.last?.text == "step 9")
        #expect(s.project == "Sesja")
    }
}
