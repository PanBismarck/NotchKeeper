import Foundation

/// One Claude Code hook event as received by the app. Only the fields every event shares are decoded here;
/// `payload` keeps the raw JSON for later phases (sessions, permissions).
struct HookEvent: Sendable, Equatable {
    let name: String
    let sessionID: String?
    let cwd: String?
    let toolName: String?
    let payload: Data

    private struct Common: Decodable {
        let hook_event_name: String?
        let session_id: String?
        let cwd: String?
        let tool_name: String?
    }

    /// `argvEvent` is the name passed to `notchkeeper-hook`; the payload's `hook_event_name` wins when present.
    init?(argvEvent: String, payload: Data) {
        guard let common = try? JSONDecoder().decode(Common.self, from: payload) else { return nil }
        let name = common.hook_event_name ?? argvEvent
        guard !name.isEmpty else { return nil }
        self.name = name
        self.sessionID = common.session_id
        self.cwd = common.cwd
        self.toolName = common.tool_name
        self.payload = payload
    }

    /// The hook waits for the app's answer instead of returning immediately.
    var awaitsReply: Bool { name == "PermissionRequest" }

    init?(message: Data) {
        guard let (event, payload) = NotchSocket.decode(message) else { return nil }
        self.init(argvEvent: event, payload: payload)
    }
}
