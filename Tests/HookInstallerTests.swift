import Foundation
import Testing

/// File side of hook installation, run against a throwaway directory — never the real `~/.claude`.
@Suite struct HookInstallerTests {
    let dir: URL
    let settings: URL
    let helper = "/Users/me/Library/Application Support/NotchKeeper/bin/notchkeeper-hook"

    init() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("HookInstallerTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        settings = dir.appendingPathComponent(".claude/settings.json")
    }

    private func write(_ text: String, permissions: Int = 0o644) throws {
        try FileManager.default.createDirectory(at: settings.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: settings)
        try FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: settings.path)
    }

    private func permissions(_ url: URL) throws -> Int {
        try (FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber)?.intValue ?? -1
    }

    private func backups() throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: settings.deletingLastPathComponent(), includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("settings.json.notchkeeper-backup-") }
    }

    private func plan(install: Bool) throws -> HookInstaller.Plan {
        try HookInstaller.plan(install: install, settingsURL: settings, helperPath: helper)
    }

    @Test func installBacksUpAndKeepsPermissions() throws {
        let original = "{\n  \"model\": \"opus\"\n}\n"
        try write(original, permissions: 0o640)
        var helperCopied = false
        let backup = try HookInstaller.apply(try plan(install: true)) { helperCopied = true }

        #expect(helperCopied)
        #expect(try String(contentsOf: #require(backup), encoding: .utf8) == original)
        let written = try Data(contentsOf: settings)
        #expect(written.last == UInt8(ascii: "\n"))
        #expect(String(decoding: written, as: UTF8.self).contains("\"model\""))
        #expect(ClaudeHooks.status(of: try JSONValue.parse(written), helperPath: helper) == .installed)
        #expect(try permissions(settings) == 0o640)
    }

    @Test func refusesWhenFileChangedSincePreview() throws {
        try write(#"{"model":"opus"}"#)
        let plan = try plan(install: true)
        try write(#"{"model":"sonnet"}"#) // edited by the user (or Claude Code) while the diff was open

        #expect(throws: HookInstaller.InstallError.self) { try HookInstaller.apply(plan) {} }
        #expect(try String(contentsOf: settings, encoding: .utf8) == #"{"model":"sonnet"}"#)
        #expect(try backups().isEmpty)
    }

    @Test func createsMissingFileWithoutBackup() throws {
        let backup = try HookInstaller.apply(try plan(install: true)) {}
        #expect(backup == nil)
        #expect(try permissions(settings) == 0o600)
        #expect(ClaudeHooks.status(of: try JSONValue.parse(Data(contentsOf: settings)), helperPath: helper) == .installed)
    }

    @Test func unchangedPlanWritesNothing() throws {
        try write(#"{"model":"opus"}"#)
        let plan = try plan(install: false) // nothing of ours to remove
        #expect(!plan.changes)
        #expect(try HookInstaller.apply(plan) { Issue.record("helper copied on uninstall") } == nil)
        #expect(try backups().isEmpty)
    }

    @Test func uninstallRestoresOriginalContent() throws {
        try write(#"{"model":"opus"}"#)
        try HookInstaller.apply(try plan(install: true)) {}
        try HookInstaller.apply(try plan(install: false)) { Issue.record("helper copied on uninstall") }
        #expect(try JSONValue.parse(Data(contentsOf: settings)) == JSONValue.parse(Data(#"{"model":"opus"}"#.utf8)))
        #expect(try backups().count == 2) // both within the same second → distinct names
    }

    @Test func refusesInvalidJSON() throws {
        try write(#"{"model": "#)
        #expect(throws: HookInstaller.InstallError.self) { try plan(install: true) }
    }

    @Test func legacyCleanupRemovesOnlyOurFiles() throws {
        let fm = FileManager.default
        let legacy = dir.appendingPathComponent("Notch")
        try fm.createDirectory(at: legacy.appendingPathComponent("bin"), withIntermediateDirectories: true)
        for f in ["bin/notch-hook", "notch.sock"] { try Data().write(to: legacy.appendingPathComponent(f)) }
        HookInstaller.removeLegacyFiles(in: legacy)
        #expect(!fm.fileExists(atPath: legacy.path))

        try fm.createDirectory(at: legacy.appendingPathComponent("bin"), withIntermediateDirectories: true)
        for f in ["bin/notch-hook", "notes.txt"] { try Data().write(to: legacy.appendingPathComponent(f)) }
        HookInstaller.removeLegacyFiles(in: legacy)
        #expect(try fm.contentsOfDirectory(atPath: legacy.path) == ["notes.txt"])
        HookInstaller.removeLegacyFiles(in: dir.appendingPathComponent("missing")) // no folder → no-op
    }
}
