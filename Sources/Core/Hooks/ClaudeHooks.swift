import Foundation

/// Pure merge logic for the `hooks` section of `~/.claude/settings.json`.
/// Our entries are recognised by `marker` (or a legacy one) in the command; everything else is left exactly as found.
enum ClaudeHooks {
    /// Event → hook timeout (s). notchkeeper-hook itself gives up after ~2 s; PermissionRequest will wait for a click (phase 6).
    static let events: [(name: String, timeout: Int)] = [
        ("SessionStart", 5), ("UserPromptSubmit", 5), ("PreToolUse", 5), ("PostToolUse", 5),
        ("Notification", 5), ("Stop", 5), ("SessionEnd", 5), ("PermissionRequest", 120),
    ]
    static let marker = "notchkeeper-hook"
    /// Helper names of earlier builds (app was called Notch): still ours, so install/uninstall replaces them.
    static let legacyMarkers = ["notch-hook"]

    enum Status: Equatable { case notInstalled, installed, outdated }

    enum MergeError: Error, Equatable {
        case notAnObject(String)   // a key we must edit has a shape we don't understand → refuse, never replace
    }

    /// Double-quoted for `sh -c`: survives the space in "Application Support".
    static func command(helperPath: String, event: String) -> String {
        var escaped = ""
        for c in helperPath {
            if "\"\\$`".contains(c) { escaped.append("\\") }
            escaped.append(c)
        }
        return "\"\(escaped)\" \(event)"
    }

    static func status(of settings: JSONValue, helperPath: String) -> Status {
        guard let installedVersion = try? installing(into: settings, helperPath: helperPath) else { return .outdated }
        if installedVersion == settings { return .installed }
        let withoutOurs = (try? uninstalling(from: settings)) ?? settings
        return withoutOurs == settings ? .notInstalled : .outdated
    }

    /// Idempotent: drops any previous entries of ours (any path, any event), then adds one group per event.
    /// Keys keep their positions, so re-installing over an installed file is a no-op.
    static func installing(into settings: JSONValue, helperPath: String) throws(MergeError) -> JSONValue {
        guard case .object(var root) = settings else { throw .notAnObject("settings") }
        var (hooks, emptied) = try strip(root)
        for (event, timeout) in events {
            var groups: [JSONValue]
            switch hooks[event] {
            case nil: groups = []
            case .array(let g)?: groups = g
            default: throw .notAnObject("hooks.\(event)")
            }
            let entry = JSONObject([
                ("type", .string("command")),
                ("command", .string(command(helperPath: helperPath, event: event))),
                ("timeout", .number(String(timeout))),
            ])
            groups.append(.object(JSONObject([("hooks", .array([.object(entry)]))])))
            hooks[event] = .array(groups)
            emptied.remove(event)
        }
        for key in emptied { hooks[key] = nil } // events we no longer use
        root["hooks"] = .object(hooks)
        return .object(root)
    }

    /// Removes only our hook entries. Containers are dropped only when we were the ones who emptied them.
    static func uninstalling(from settings: JSONValue) throws(MergeError) -> JSONValue {
        guard case .object(var root) = settings else { throw .notAnObject("settings") }
        guard case .object? = root["hooks"] else { return settings }
        var (hooks, emptied) = try strip(root)
        for key in emptied { hooks[key] = nil }
        root["hooks"] = hooks.isEmpty && !emptied.isEmpty ? nil : .object(hooks)
        return .object(root)
    }

    /// Our entries removed from `root.hooks`; arrays we emptied stay in place as `[]` and are reported.
    private static func strip(_ root: JSONObject) throws(MergeError) -> (hooks: JSONObject, emptied: Set<String>) {
        var hooks: JSONObject
        switch root["hooks"] {
        case nil: return (JSONObject(), [])
        case .object(let h)?: hooks = h
        default: throw .notAnObject("hooks")
        }
        var emptied = Set<String>()
        for key in hooks.keys {
            guard case .array(let groups)? = hooks[key] else { continue }
            var kept: [JSONValue] = []
            for group in groups {
                guard case .object(var g) = group, case .array(let entries)? = g["hooks"] else { kept.append(group); continue }
                let others = entries.filter { !isOurs($0) }
                if others.count == entries.count { kept.append(group); continue }
                if others.isEmpty { continue }
                g["hooks"] = .array(others)
                kept.append(.object(g))
            }
            guard kept != groups else { continue }
            hooks[key] = .array(kept)
            if kept.isEmpty { emptied.insert(key) }
        }
        return (hooks, emptied)
    }

    private static func isOurs(_ entry: JSONValue) -> Bool {
        guard case .object(let e) = entry, case .string(let cmd)? = e["command"] else { return false }
        return ([marker] + legacyMarkers).contains { cmd.contains($0) }
    }
}

/// Line-level diff for the confirmation window.
enum LineDiff {
    enum Line: Equatable {
        case same(String), added(String), removed(String)
    }

    static func diff(old: String, new: String) -> [Line] {
        let a = old.isEmpty ? [] : old.components(separatedBy: "\n")
        let b = new.isEmpty ? [] : new.components(separatedBy: "\n")
        var removed = Set<Int>(), inserted = Set<Int>()
        for change in b.difference(from: a) {
            switch change {
            case .remove(let offset, _, _): removed.insert(offset)
            case .insert(let offset, _, _): inserted.insert(offset)
            }
        }
        var out: [Line] = []
        var i = 0, j = 0
        while i < a.count || j < b.count {
            if i < a.count, removed.contains(i) { out.append(.removed(a[i])); i += 1 }
            else if j < b.count, inserted.contains(j) { out.append(.added(b[j])); j += 1 }
            else { out.append(.same(a[i])); i += 1; j += 1 }
        }
        return out
    }
}
