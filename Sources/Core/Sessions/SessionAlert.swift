import Foundation

/// What deserves a sound after a batch of session changes: a session newly needing the user, or a turn ending.
enum SessionAlert: Equatable, Sendable {
    case waiting
    case done
    case error

    /// The most urgent alert among sessions whose status changed between `old` and `new` (nil = stay quiet).
    static func between(_ old: [Session], _ new: [Session]) -> SessionAlert? {
        let before = Dictionary(old.map { ($0.id, $0.status) }, uniquingKeysWith: { a, _ in a })
        let changed = new.filter { before[$0.id] != $0.status }.map(\.status)
        if changed.contains(.waiting) { return .waiting }
        if changed.contains(.error) { return .error }
        if changed.contains(.done) { return .done }
        return nil
    }
}
