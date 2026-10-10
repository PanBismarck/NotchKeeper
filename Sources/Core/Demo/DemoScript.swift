import Foundation

/// A scripted pretend run of two Claude Code sessions, fed through the same `HookEvent` path as real hooks.
/// Exercises every island state: working, permission card, waiting, done and error.
enum DemoScript {
    enum Step: Sendable {
        case event(HookEvent)
        /// Pause before the next step, in seconds.
        case pause(Double)
    }

    static let sessionIDs = ["notch-demo-app", "notch-demo-site"]

    static var steps: [Step] {
        let app = Actor(id: sessionIDs[0], cwd: "/Users/demo/Projects/notch-app")
        let site = Actor(id: sessionIDs[1], cwd: "/Users/demo/Projects/website")
        let edit: [String: Any] = ["file_path": "/Users/demo/Projects/notch-app/Sources/Settings.swift",
                                   "old_string": "let sounds = false", "new_string": "let sounds = true"]
        let tests: [String: Any] = ["command": "swift test --filter SettingsTests", "description": "Uruchom testy"]
        let grep: [String: Any] = ["pattern": "footer", "path": "src/"]

        return [
            app.on("SessionStart"),
            app.on("UserPromptSubmit", ["prompt": "Dodaj przełącznik dźwięków w ustawieniach"]),
            .pause(1.5),
            app.tool("PreToolUse", "Read", ["file_path": "/Users/demo/Projects/notch-app/Sources/Settings.swift"]),
            .pause(1.5),
            app.tool("PostToolUse", "Read", ["file_path": "/Users/demo/Projects/notch-app/Sources/Settings.swift"]),
            site.on("SessionStart"),
            site.on("UserPromptSubmit", ["prompt": "Popraw stopkę na telefonach"]),
            site.tool("PreToolUse", "Grep", grep),
            .pause(2),
            app.tool("PreToolUse", "Edit", edit),
            .pause(0.5),
            app.tool("PermissionRequest", "Edit", edit, extra: [
                "permission_suggestions": [["type": "setMode", "mode": "acceptEdits", "destination": "session"]],
            ]),
            app.tool("PostToolUse", "Edit", edit),
            .pause(1),
            site.tool("PostToolUse", "Grep", grep),
            site.on("Notification", ["message": "Claude needs your permission to use Bash"]),
            app.tool("PreToolUse", "Bash", tests),
            .pause(3),
            app.tool("PostToolUse", "Bash", tests),
            .pause(1),
            app.on("Stop", ["last_assistant_message": "Dodałem przełącznik dźwięków, testy przechodzą."]),
            .pause(4),
            site.on("StopFailure"),
        ]
    }

    private struct Actor {
        let id: String
        let cwd: String

        func on(_ name: String, _ fields: [String: Any] = [:]) -> Step {
            make(name, fields)
        }

        func tool(_ name: String, _ tool: String, _ input: [String: Any], extra: [String: Any] = [:]) -> Step {
            make(name, extra.merging(["tool_name": tool, "tool_input": input]) { a, _ in a })
        }

        private func make(_ name: String, _ fields: [String: Any]) -> Step {
            var body = fields
            body["hook_event_name"] = name
            body["session_id"] = id
            body["cwd"] = cwd
            let data = (try? JSONSerialization.data(withJSONObject: body)) ?? Data()
            // Only fails on a malformed script — caught by DemoScriptTests.
            return HookEvent(argvEvent: name, payload: data).map(Step.event) ?? .pause(0)
        }
    }
}
