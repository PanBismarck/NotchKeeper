import Foundation

/// Pure reducer: hook events in, live sessions out. Time is passed in so tests control it.
struct SessionStore: Equatable, Sendable {
    /// A session with no events for this long is considered dead (crashed, closed without SessionEnd).
    static let staleAfter: TimeInterval = 30 * 60
    /// A finished turn (done/error) keeps the ears out this long so the result can be seen.
    static let defaultFinishedLinger: TimeInterval = 2 * 60
    var finishedLinger = SessionStore.defaultFinishedLinger

    /// Most recently active first.
    private(set) var sessions: [Session] = []

    // MARK: - Derived

    /// The session the compact island speaks for: highest-priority status, then most recent.
    var primary: Session? {
        sessions.max { a, b in
            a.status.priority != b.status.priority
                ? a.status.priority < b.status.priority
                : a.lastEventAt < b.lastEventAt
        }
    }

    /// Something worth showing in the ears: a turn in progress, or one that finished moments ago.
    func hasActivity(at now: Date) -> Bool {
        sessions.contains { $0.status.isActive || (lingerEnd(of: $0).map { now < $0 } ?? false) }
    }

    /// When the next session goes stale, so the app can arm one timer instead of polling.
    var nextExpiry: Date? {
        sessions.map(\.lastEventAt).min()?.addingTimeInterval(Self.staleAfter)
    }

    /// The next moment `hasActivity` or staleness can change — one timer covers both.
    func nextDeadline(after now: Date) -> Date? {
        let lingers = sessions.compactMap(lingerEnd).filter { $0 > now }
        return (lingers + [nextExpiry].compactMap { $0 }).min()
    }

    private func lingerEnd(of s: Session) -> Date? {
        s.status == .done || s.status == .error ? s.lastEventAt.addingTimeInterval(finishedLinger) : nil
    }

    // MARK: - Reducer

    mutating func apply(_ event: HookEvent, at now: Date) {
        guard let id = event.sessionID, !id.isEmpty else { return }
        let payload = (try? JSONSerialization.jsonObject(with: event.payload)) as? [String: Any] ?? [:]

        if event.name == "SessionEnd" {
            sessions.removeAll { $0.id == id }
            return
        }

        var s = sessions.first { $0.id == id } ?? Session(id: id, cwd: event.cwd, at: now)
        s.lastEventAt = now
        if let cwd = event.cwd, !cwd.isEmpty, cwd != s.cwd {
            s.cwd = cwd
            s.project = Session.projectName(cwd: cwd)
        }

        switch event.name {
        case "SessionStart":
            s.status = .idle
            s.tool = nil
            s.detail = nil

        case "UserPromptSubmit":
            s.status = .working
            s.tool = nil
            s.detail = "Myśli…"
            if let prompt = payload["prompt"] as? String { s.appendStep("› " + prompt, at: now) }

        case "PreToolUse":
            let tool = event.toolName ?? "Tool"
            let line = ToolSummary.describe(tool: tool, input: payload["tool_input"] as? [String: Any] ?? [:])
            s.status = .working
            s.tool = tool
            s.detail = line
            s.appendStep(line, at: now)

        case "PostToolUse":
            // A permission answered in the terminal resolves here, too.
            s.status = .working
            s.tool = nil

        case "PostToolUseFailure":
            s.status = .working
            s.tool = nil
            s.appendStep("⚠ \(ToolSummary.displayName(event.toolName ?? "Tool")) nie powiódł się", at: now)

        case "PermissionRequest":
            let tool = event.toolName ?? "Tool"
            let line = ToolSummary.describe(tool: tool, input: payload["tool_input"] as? [String: Any] ?? [:])
            s.status = .waiting
            s.tool = tool
            s.detail = "Pozwolić? \(line)"

        case "Notification":
            let message = payload["message"] as? String ?? ""
            let type = payload["notification_type"] as? String
            if type == "idle_prompt" || message.lowercased().contains("waiting for your input") {
                // Fires ~1 min after a finished turn — nothing new to show.
                if s.status == .working { s.status = .waiting; s.detail = ToolSummary.oneLine(message) }
            } else if type == "auth_success" {
                break
            } else if !message.isEmpty {
                s.status = .waiting
                s.detail = ToolSummary.oneLine(message)
            }

        case "Stop":
            s.status = .done
            s.tool = nil
            let final = (payload["last_assistant_message"] as? String).map(ToolSummary.oneLine) ?? ""
            s.detail = final.isEmpty ? "Gotowe" : final
            if !final.isEmpty { s.appendStep(final, at: now) }

        case "StopFailure":
            s.status = .error
            s.tool = nil
            s.detail = "Błąd"

        default:
            break
        }

        sessions.removeAll { $0.id == id }
        sessions.insert(s, at: 0)
    }

    /// Drops sessions with no events for `staleAfter`. Returns true when anything was removed.
    @discardableResult
    mutating func prune(now: Date) -> Bool {
        let before = sessions.count
        sessions.removeAll { now.timeIntervalSince($0.lastEventAt) >= Self.staleAfter }
        return sessions.count != before
    }
}
