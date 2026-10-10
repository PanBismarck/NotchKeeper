import Foundation

/// File side of hook installation: stable helper copy, settings snapshot, backup, guarded write.
/// Nothing here writes `settings.json` except `apply(_:)`, which the user triggers from the diff window.
enum HookInstaller {
    struct Plan {
        let install: Bool
        let settingsURL: URL          // symlinks resolved (dotfile repos)
        let original: Data?           // nil = file did not exist
        let new: Data
        var changes: Bool { new != original }
        var diff: [LineDiff.Line] {
            LineDiff.diff(old: original.map { String(decoding: $0, as: UTF8.self) } ?? "",
                          new: String(decoding: new, as: UTF8.self))
        }
    }

    enum InstallError: LocalizedError {
        case unreadable(String)
        case invalidJSON(Int)
        case unexpectedShape(String)
        case changedSincePreview
        case helperMissing

        var errorDescription: String? {
            switch self {
            case .unreadable(let why): "Nie mogę odczytać settings.json: \(why)"
            case .invalidJSON(let at): "settings.json nie jest poprawnym JSON-em (bajt \(at)) — popraw go ręcznie."
            case .unexpectedShape(let key): "Nieznany format „\(key)” w settings.json — nic nie zmieniam."
            case .changedSincePreview: "settings.json zmienił się w międzyczasie — odśwież podgląd."
            case .helperMissing: "Brak notchkeeper-hook w paczce apki."
            }
        }
    }

    static var helperURL: URL {
        URL(fileURLWithPath: (NotchSocket.defaultPath as NSString).deletingLastPathComponent)
            .appendingPathComponent("bin/notchkeeper-hook")
    }

    static var settingsURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/settings.json").resolvingSymlinksInPath()
    }

    // MARK: Status & plan

    static func status() -> ClaudeHooks.Status {
        guard let data = try? Data(contentsOf: settingsURL), let json = try? JSONValue.parse(data) else { return .notInstalled }
        return ClaudeHooks.status(of: json, helperPath: helperURL.path)
    }

    /// `url` and `helperPath` are injectable for tests; the app uses the real locations.
    static func plan(install: Bool, settingsURL url: URL = settingsURL, helperPath: String = helperURL.path) throws -> Plan {
        let original: Data?
        do { original = try Data(contentsOf: url) } catch CocoaError.fileReadNoSuchFile { original = nil }
        catch { throw InstallError.unreadable(error.localizedDescription) }

        var settings = JSONValue.object(JSONObject())
        if let original {
            do throws(JSONParseError) { settings = try JSONValue.parse(original) }
            catch { throw InstallError.invalidJSON(error.offset) }
        }

        let updated: JSONValue
        do throws(ClaudeHooks.MergeError) {
            updated = install ? try ClaudeHooks.installing(into: settings, helperPath: helperPath)
                              : try ClaudeHooks.uninstalling(from: settings)
        } catch .notAnObject(let key) { throw InstallError.unexpectedShape(key) }

        // Unchanged content → keep the user's exact bytes (formatting, trailing newline).
        if updated == settings, let original { return Plan(install: install, settingsURL: url, original: original, new: original) }
        var text = updated.serialized()
        if original?.last == UInt8(ascii: "\n") { text += "\n" }
        return Plan(install: install, settingsURL: url, original: original, new: Data(text.utf8))
    }

    // MARK: Apply

    /// Backs up, then writes atomically. Returns the backup URL (nil when there was no file).
    /// `helper` copies notchkeeper-hook on install (stubbed in tests, where there is no app bundle).
    @discardableResult
    static func apply(_ plan: Plan, helper: () throws -> Void = installHelper) throws -> URL? {
        if plan.install { try helper() }
        let fm = FileManager.default
        let current = try? Data(contentsOf: plan.settingsURL)
        guard current == plan.original else { throw InstallError.changedSincePreview }
        guard plan.changes else { return nil }

        var backup: URL?
        var permissions: NSNumber = 0o600
        if plan.original != nil {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "yyyyMMdd-HHmmss"
            let stamp = f.string(from: .now)
            let base = plan.settingsURL.deletingLastPathComponent().appendingPathComponent("settings.json.notchkeeper-backup-\(stamp)")
            var url = base, n = 1
            while fm.fileExists(atPath: url.path) { n += 1; url = URL(fileURLWithPath: "\(base.path)-\(n)") } // same second
            try fm.copyItem(at: plan.settingsURL, to: url)
            backup = url
            if let p = try? fm.attributesOfItem(atPath: plan.settingsURL.path)[.posixPermissions] as? NSNumber { permissions = p }
        } else {
            try fm.createDirectory(at: plan.settingsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        }
        try plan.new.write(to: plan.settingsURL, options: .atomic)
        try fm.setAttributes([.posixPermissions: permissions], ofItemAtPath: plan.settingsURL.path)
        return backup
    }

    // MARK: Helper copy

    /// Hooks point at a stable copy, not into the .app (which moves between builds/installs).
    static func installHelper() throws {
        guard let bundled = Bundle.main.url(forAuxiliaryExecutable: "notchkeeper-hook") else { throw InstallError.helperMissing }
        let fm = FileManager.default
        let target = helperURL
        if fm.contentsEqual(atPath: bundled.path, andPath: target.path) { return }
        try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        let temp = target.deletingLastPathComponent().appendingPathComponent(".notchkeeper-hook.\(UUID().uuidString)")
        try fm.copyItem(at: bundled, to: temp)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: temp.path)
        if rename(temp.path, target.path) != 0 { // atomic swap: a running hook keeps its old inode
            try? fm.removeItem(at: temp)
            throw CocoaError(.fileWriteUnknown)
        }
    }

    /// At launch: keep an already-installed helper in sync with this build. Never installs it on its own.
    static func refreshHelperIfInstalled() {
        guard FileManager.default.fileExists(atPath: helperURL.path) else { return }
        try? installHelper()
    }

    // MARK: Legacy (app called Notch)

    static var legacyDirectory: URL {
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support/Notch")
    }

    /// Call after a successful `apply`: no entry points at the old helper any more.
    /// Removes only what earlier builds put there, then the folders if they ended up empty.
    static func removeLegacyFiles(in dir: URL = legacyDirectory) {
        let fm = FileManager.default
        try? fm.removeItem(at: dir.appendingPathComponent("bin/notch-hook"))
        try? fm.removeItem(at: dir.appendingPathComponent("notch.sock"))
        for d in [dir.appendingPathComponent("bin"), dir] where (try? fm.contentsOfDirectory(atPath: d.path))?.isEmpty == true {
            try? fm.removeItem(at: d)
        }
    }
}
