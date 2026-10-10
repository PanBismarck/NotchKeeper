import Foundation

/// A `PermissionRequest` hook waiting for the user's click in the island.
struct PermissionRequest: Identifiable, Sendable {
    let id: UUID
    let sessionID: String
    let project: String
    let tool: String
    /// "Bash: run tests", "Edit main.swift"
    let title: String
    /// The thing being approved, whole (invisible characters made visible): full command, file path, URL…
    let detail: String?
    /// The detail was too long to keep — the card then offers no one-click approval.
    let detailTruncated: Bool
    /// Sorted-keys `tool_input`, to match the PostToolUse that follows an answer given in the terminal.
    let inputKey: String
    /// Claude Code's `permission_suggestions` ("always allow" rules), passed back on **Always**.
    let suggestions: JSONValue?
    let createdAt: Date

    static let maxDetailLength = 5_000

    init?(event: HookEvent, at now: Date, id: UUID = UUID()) {
        guard event.name == "PermissionRequest", let session = event.sessionID, !session.isEmpty else { return nil }
        let payload = (try? JSONSerialization.jsonObject(with: event.payload)) as? [String: Any] ?? [:]
        let input = payload["tool_input"] as? [String: Any] ?? [:]
        let tool = event.toolName ?? "Tool"

        self.id = id
        self.sessionID = session
        self.project = Session.projectName(cwd: event.cwd)
        self.tool = tool
        self.title = ToolSummary.describe(tool: tool, input: input)
        let detail = Self.detail(tool: tool, input: input).map(Self.visible)
        let truncated = (detail?.count ?? 0) > Self.maxDetailLength
        self.detailTruncated = truncated
        self.detail = truncated ? detail.map { String($0.prefix(Self.maxDetailLength)) + "…" } : detail
        self.inputKey = Self.inputKey(input)
        self.createdAt = now

        if case .object(let root)? = try? JSONValue.parse(event.payload),
           case .array(let rules)? = root["permission_suggestions"], !rules.isEmpty {
            self.suggestions = .array(rules)
        } else {
            self.suggestions = nil
        }
    }

    var canAlwaysAllow: Bool { suggestions != nil }

    static func inputKey(_ input: [String: Any]) -> String {
        guard !input.isEmpty,
              let data = try? JSONSerialization.data(withJSONObject: input, options: .sortedKeys) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    private static func detail(tool: String, input: [String: Any]) -> String? {
        func str(_ key: String) -> String? {
            guard let s = input[key] as? String, !s.isEmpty else { return nil }
            return s
        }
        let text: String?
        switch tool {
        case "Bash": text = str("command")
        case "Read", "Edit", "MultiEdit", "Write": text = str("file_path")
        case "NotebookEdit": text = str("notebook_path")
        case "WebFetch": text = str("url")
        case "WebSearch": text = str("query")
        case "Grep", "Glob": text = [str("pattern"), str("path")].compactMap { $0 }.joined(separator: "  in  ")
        default: // MCP and the rest: every parameter, so nothing approved stays off-card (e.g. an e-mail's "to")
            text = input.keys.sorted().compactMap { key in input[key].map { "\(key): \(render($0))" } }.joined(separator: "\n")
        }
        guard let text, !text.isEmpty else { return nil }
        return text
    }

    private static func render(_ value: Any) -> String {
        if let s = value as? String { return s }
        guard let data = try? JSONSerialization.data(withJSONObject: value,
                                                     options: [.sortedKeys, .fragmentsAllowed, .withoutEscapingSlashes])
        else { return String(describing: value) }
        return String(decoding: data, as: UTF8.self)
    }

    /// Characters that draw nothing or reorder text (bidi overrides, zero-width, tags, control codes) shown as
    /// `⟨U+XXXX⟩`, so the card can't read differently from what gets approved. Newlines and tabs stay.
    static func visible(_ text: String) -> String {
        var out = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            switch scalar.properties.generalCategory {
            case .control where scalar != "\n" && scalar != "\t", .format, .lineSeparator, .paragraphSeparator:
                out.append(contentsOf: String(format: "⟨U+%04X⟩", scalar.value).unicodeScalars)
            default:
                out.append(scalar)
            }
        }
        return String(out)
    }
}

enum PermissionDecision: Sendable {
    case allow, always, deny
}

extension PermissionRequest {
    /// Hook stdout for Claude Code. No output at all (timeout, "answer in terminal") means Claude asks as usual.
    func response(_ decision: PermissionDecision) -> Data {
        var verdict = JSONObject()
        switch decision {
        case .allow:
            verdict["behavior"] = .string("allow")
        case .always:
            verdict["behavior"] = .string("allow")
            verdict["updatedPermissions"] = suggestions
        case .deny:
            verdict["behavior"] = .string("deny")
            verdict["message"] = .string("Odrzucone w NotchKeeper")
        }
        var output = JSONObject()
        output["hookEventName"] = .string("PermissionRequest")
        output["decision"] = .object(verdict)
        var root = JSONObject()
        root["hookSpecificOutput"] = .object(output)
        return Data((JSONValue.object(root).serialized() + "\n").utf8)
    }
}

/// Pending requests, oldest first — the island shows one card at a time.
struct PermissionQueue: Sendable {
    private(set) var items: [PermissionRequest] = []

    var current: PermissionRequest? { items.first }
    var isEmpty: Bool { items.isEmpty }

    mutating func enqueue(_ request: PermissionRequest) { items.append(request) }

    @discardableResult
    mutating func remove(id: UUID) -> PermissionRequest? {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return nil }
        return items.remove(at: i)
    }

    /// Removes and returns requests that `event` shows were already answered (in the terminal) or abandoned.
    mutating func resolved(by event: HookEvent) -> [PermissionRequest] {
        guard let session = event.sessionID else { return [] }
        let matches: (PermissionRequest) -> Bool
        switch event.name {
        case "PostToolUse", "PostToolUseFailure":
            let payload = (try? JSONSerialization.jsonObject(with: event.payload)) as? [String: Any] ?? [:]
            let key = PermissionRequest.inputKey(payload["tool_input"] as? [String: Any] ?? [:])
            matches = { $0.sessionID == session && $0.tool == event.toolName && $0.inputKey == key }
        case "UserPromptSubmit", "Stop", "StopFailure", "SessionEnd":
            matches = { $0.sessionID == session }
        default:
            return []
        }
        let gone = items.filter(matches)
        items.removeAll(where: matches)
        return gone
    }
}
