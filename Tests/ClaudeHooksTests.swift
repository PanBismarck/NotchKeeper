import Foundation
import Testing

private func parse(_ s: String) throws -> JSONValue { try JSONValue.parse(Data(s.utf8)) }

@Suite struct JSONValueTests {
    @Test func roundTripMatchesJSONStringify() throws {
        let text = """
        {
          "enableWorkflows": true,
          "z": [],
          "a": {
            "n": 1.50,
            "e": -2E+3,
            "s": "ąę \\"q\\" \\\\ /\\n\\u0001",
            "list": [
              null,
              false,
              {}
            ]
          }
        }
        """
        #expect(try parse(text).serialized() == text)
    }

    @Test func keepsKeyOrder() throws {
        guard case .object(let o) = try parse(#"{"b":1,"a":2,"c":3}"#) else { Issue.record(); return }
        #expect(o.keys == ["b", "a", "c"])
    }

    @Test func unicodeEscapes() throws {
        #expect(try parse(#""é😀""#) == .string("é😀"))
    }

    @Test(arguments: ["", "{", "{\"a\":}", "[1,]", "01x", "\"\u{01}\"", "{} x", "tru"])
    func rejectsInvalid(_ text: String) {
        #expect(throws: JSONParseError.self) { try parse(text) }
    }
}

@Suite struct ClaudeHooksTests {
    let path = "/Users/me/Library/Application Support/NotchKeeper/bin/notchkeeper-hook"

    @Test func commandIsQuoted() {
        #expect(ClaudeHooks.command(helperPath: path, event: "Stop") == "\"\(path)\" Stop")
        #expect(ClaudeHooks.command(helperPath: "/a\"b$c", event: "Stop") == #""/a\"b\$c" Stop"#)
    }

    @Test func installIntoEmptyAndUninstallRestores() throws {
        let original = try parse(#"{"enableWorkflows":true}"#)
        #expect(ClaudeHooks.status(of: original, helperPath: path) == .notInstalled)
        let installed = try ClaudeHooks.installing(into: original, helperPath: path)
        #expect(ClaudeHooks.status(of: installed, helperPath: path) == .installed)
        guard case .object(let root) = installed, case .object(let hooks)? = root["hooks"] else { Issue.record(); return }
        #expect(hooks.keys == ClaudeHooks.events.map(\.name))
        #expect(root.keys == ["enableWorkflows", "hooks"])
        #expect(try ClaudeHooks.uninstalling(from: installed) == original)
    }

    @Test func reinstallIsNoOp() throws {
        let installed = try ClaudeHooks.installing(into: parse(#"{"hooks":{},"x":1}"#), helperPath: path)
        #expect(try ClaudeHooks.installing(into: installed, helperPath: path) == installed)
    }

    @Test func foreignHooksUntouched() throws {
        let text = """
        {"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"lint.sh"}]}],
                  "Custom":[{"hooks":[{"type":"command","command":"mine.sh"}]}]}}
        """
        let original = try parse(text)
        let installed = try ClaudeHooks.installing(into: original, helperPath: path)
        guard case .object(let root) = installed, case .object(let hooks)? = root["hooks"],
              case .array(let pre)? = hooks["PreToolUse"] else { Issue.record(); return }
        #expect(pre.count == 2)
        #expect(hooks["Custom"] != nil)
        #expect(try ClaudeHooks.uninstalling(from: installed) == original)
    }

    @Test func sharedGroupKeepsForeignEntry() throws {
        let text = #"{"hooks":{"Stop":[{"hooks":[{"command":"other.sh"},{"command":"\"/old/notch-hook\" Stop"}]}]}}"#
        let cleaned = try ClaudeHooks.uninstalling(from: parse(text))
        #expect(cleaned == (try parse(#"{"hooks":{"Stop":[{"hooks":[{"command":"other.sh"}]}]}}"#)))
    }

    @Test func oldPathIsOutdatedAndReplaced() throws {
        let old = try ClaudeHooks.installing(into: parse("{}"), helperPath: "/old/build/notchkeeper-hook")
        #expect(ClaudeHooks.status(of: old, helperPath: path) == .outdated)
        let updated = try ClaudeHooks.installing(into: old, helperPath: path)
        #expect(ClaudeHooks.status(of: updated, helperPath: path) == .installed)
        #expect(!updated.serialized().contains("/old/build"))
    }

    @Test func entriesFromBuildsCalledNotchAreOursToReplace() throws {
        let legacy = try ClaudeHooks.installing(into: parse(#"{"hooks":{"Stop":[{"hooks":[{"command":"other.sh"}]}]}}"#),
                                                helperPath: "/Users/me/Library/Application Support/Notch/bin/notch-hook")
        #expect(ClaudeHooks.status(of: legacy, helperPath: path) == .outdated)
        let updated = try ClaudeHooks.installing(into: legacy, helperPath: path)
        #expect(ClaudeHooks.status(of: updated, helperPath: path) == .installed)
        #expect(!updated.serialized().contains("Support/Notch/"))
        #expect(updated.serialized().contains("other.sh"))
        #expect(try ClaudeHooks.uninstalling(from: legacy) == (try parse(#"{"hooks":{"Stop":[{"hooks":[{"command":"other.sh"}]}]}}"#)))
    }

    @Test func refusesUnknownShapes() throws {
        #expect(throws: ClaudeHooks.MergeError.notAnObject("hooks")) {
            try ClaudeHooks.installing(into: parse(#"{"hooks":[]}"#), helperPath: path)
        }
        #expect(throws: ClaudeHooks.MergeError.notAnObject("hooks.Stop")) {
            try ClaudeHooks.installing(into: parse(#"{"hooks":{"Stop":"x"}}"#), helperPath: path)
        }
        #expect(throws: ClaudeHooks.MergeError.notAnObject("settings")) {
            try ClaudeHooks.installing(into: parse("[]"), helperPath: path)
        }
    }

    @Test func emptyHooksObjectKeptOnUninstall() throws {
        let s = try parse(#"{"hooks":{}}"#)
        #expect(try ClaudeHooks.uninstalling(from: s) == s)
    }
}

@Suite struct LineDiffTests {
    @Test func marksChanges() {
        let d = LineDiff.diff(old: "a\nb\nc", new: "a\nB\nc\nd")
        #expect(d == [.same("a"), .removed("b"), .added("B"), .same("c"), .added("d")])
    }

    @Test func fromNothing() {
        #expect(LineDiff.diff(old: "", new: "x") == [.added("x")])
    }
}
