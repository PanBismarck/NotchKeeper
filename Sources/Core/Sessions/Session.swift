import Foundation

/// One Claude Code session as shown in the island.
struct Session: Identifiable, Equatable, Sendable {
    enum Status: Equatable, Sendable {
        case working   // prompt submitted / tool running
        case waiting   // needs the user (permission, question)
        case idle      // started, nothing happening
        case done      // turn finished
        case error

        /// Higher wins when picking the one status the compact island shows.
        var priority: Int {
            switch self {
            case .waiting: 4
            case .error: 3
            case .working: 2
            case .done: 1
            case .idle: 0
            }
        }

        /// Something the user should see without hovering: keeps the ears out.
        var isActive: Bool { self == .working || self == .waiting }
    }

    struct Step: Equatable, Sendable {
        let text: String
        let at: Date
    }

    static let maxSteps = 5

    let id: String
    var project: String
    var cwd: String?
    var status: Status = .idle
    /// Tool currently running (PreToolUse … PostToolUse), e.g. "Edit".
    var tool: String?
    /// Short human line for it, e.g. "Edit main.swift".
    var detail: String?
    let startedAt: Date
    var lastEventAt: Date
    /// Newest last, at most `maxSteps`.
    var steps: [Step] = []

    init(id: String, cwd: String?, at date: Date) {
        self.id = id
        self.cwd = cwd
        self.project = Session.projectName(cwd: cwd)
        self.startedAt = date
        self.lastEventAt = date
    }

    static func projectName(cwd: String?) -> String {
        guard let cwd, !cwd.isEmpty else { return "Sesja" }
        let name = URL(fileURLWithPath: cwd).lastPathComponent
        return name.isEmpty || name == "/" ? "Sesja" : name
    }

    mutating func appendStep(_ text: String, at date: Date) {
        let line = ToolSummary.oneLine(text)
        guard !line.isEmpty, steps.last?.text != line else { return }
        steps.append(Step(text: line, at: date))
        if steps.count > Self.maxSteps { steps.removeFirst(steps.count - Self.maxSteps) }
    }
}
