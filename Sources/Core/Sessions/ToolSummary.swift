import Foundation

/// Turns a tool call into a short line ("Edit main.swift", "Bash: swift test") and an SF Symbol.
enum ToolSummary {
    static let maxLength = 60

    static func describe(tool: String, input: [String: Any]) -> String {
        func str(_ key: String) -> String? {
            guard let s = input[key] as? String, !s.isEmpty else { return nil }
            return s
        }
        let arg: String?
        switch tool {
        case "Read", "Edit", "MultiEdit", "Write", "NotebookEdit":
            arg = (str("file_path") ?? str("notebook_path")).map { URL(fileURLWithPath: $0).lastPathComponent }
        case "Bash":
            arg = str("description") ?? str("command")
        case "Grep", "Glob":
            arg = str("pattern")
        case "WebFetch":
            arg = str("url").flatMap { URL(string: $0)?.host } ?? str("url")
        case "WebSearch":
            arg = str("query")
        case "Task", "Agent":
            arg = str("description")
        default:
            arg = nil
        }
        let name = displayName(tool)
        guard let arg else { return name }
        return oneLine(tool == "Bash" || tool == "Grep" || tool == "Glob" || tool == "WebSearch"
                       ? "\(name): \(arg)" : "\(name) \(arg)")
    }

    /// MCP tools are `mcp__server__tool` — show just the tool part.
    static func displayName(_ tool: String) -> String {
        guard tool.hasPrefix("mcp__") else { return tool }
        return tool.components(separatedBy: "__").last.flatMap { $0.isEmpty ? nil : $0 } ?? tool
    }

    static func symbol(for tool: String?) -> String {
        switch tool {
        case nil: "sparkles"
        case "Bash": "terminal"
        case "Read": "doc.text"
        case "Edit", "MultiEdit", "Write", "NotebookEdit": "pencil"
        case "Grep", "Glob": "magnifyingglass"
        case "WebFetch", "WebSearch": "globe"
        case "Task", "Agent": "person.2"
        case "TodoWrite": "checklist"
        default: "wrench.and.screwdriver"
        }
    }

    /// First non-empty line, whitespace collapsed, capped at `maxLength`.
    static func oneLine(_ text: String) -> String {
        let line = text.split(whereSeparator: \.isNewline)
            .lazy.map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty } ?? ""
        let collapsed = line.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard collapsed.count > maxLength else { return collapsed }
        return String(collapsed.prefix(maxLength - 1)) + "…"
    }
}
