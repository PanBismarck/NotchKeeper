import Foundation

/// Minimal JSON model that keeps object key order and number literals, so rewriting `settings.json`
/// changes only what we touch. Printing matches `JSON.stringify(value, null, 2)` (Claude Code's own format).
indirect enum JSONValue: Sendable, Equatable {
    case null
    case bool(Bool)
    case number(String)   // raw literal, printed back verbatim
    case string(String)
    case array([JSONValue])
    case object(JSONObject)
}

struct JSONObject: Sendable, Equatable {
    var entries: [(key: String, value: JSONValue)] = []

    init(_ entries: [(key: String, value: JSONValue)] = []) { self.entries = entries }

    var isEmpty: Bool { entries.isEmpty }
    var keys: [String] { entries.map(\.key) }

    /// Setting an existing key keeps its position; a new key goes last; nil removes.
    subscript(key: String) -> JSONValue? {
        get { entries.first { $0.key == key }?.value }
        set {
            let i = entries.firstIndex { $0.key == key }
            switch (i, newValue) {
            case let (i?, v?): entries[i].value = v
            case let (i?, nil): entries.remove(at: i)
            case let (nil, v?): entries.append((key, v))
            case (nil, nil): break
            }
        }
    }

    static func == (a: JSONObject, b: JSONObject) -> Bool {
        a.entries.count == b.entries.count && zip(a.entries, b.entries).allSatisfy { $0.key == $1.key && $0.value == $1.value }
    }
}

struct JSONParseError: Error, Equatable {
    let offset: Int
}

// MARK: - Parsing

extension JSONValue {
    static func parse(_ data: Data) throws(JSONParseError) -> JSONValue {
        var p = Parser(bytes: Array(data))
        if p.bytes.starts(with: [0xEF, 0xBB, 0xBF]) { p.i = 3 } // UTF-8 BOM
        p.skipWhitespace()
        let value = try p.value(depth: 0)
        p.skipWhitespace()
        guard p.i == p.bytes.count else { throw p.fail() }
        return value
    }

    private struct Parser {
        let bytes: [UInt8]
        var i = 0

        func fail() -> JSONParseError { JSONParseError(offset: i) }
        var peek: UInt8? { i < bytes.count ? bytes[i] : nil }

        mutating func skipWhitespace() {
            while let c = peek, c == 0x20 || c == 0x0A || c == 0x0D || c == 0x09 { i += 1 }
        }

        mutating func expect(_ literal: String) throws(JSONParseError) {
            for b in literal.utf8 {
                guard peek == b else { throw fail() }
                i += 1
            }
        }

        mutating func value(depth: Int) throws(JSONParseError) -> JSONValue {
            guard depth < 512, let c = peek else { throw fail() }
            switch c {
            case UInt8(ascii: "{"): return .object(try object(depth: depth))
            case UInt8(ascii: "["): return .array(try array(depth: depth))
            case UInt8(ascii: "\""): return .string(try string())
            case UInt8(ascii: "t"): try expect("true"); return .bool(true)
            case UInt8(ascii: "f"): try expect("false"); return .bool(false)
            case UInt8(ascii: "n"): try expect("null"); return .null
            default: return .number(try number())
            }
        }

        mutating func object(depth: Int) throws(JSONParseError) -> JSONObject {
            i += 1
            var obj = JSONObject()
            skipWhitespace()
            if peek == UInt8(ascii: "}") { i += 1; return obj }
            while true {
                skipWhitespace()
                guard peek == UInt8(ascii: "\"") else { throw fail() }
                let key = try string()
                skipWhitespace()
                try expect(":")
                skipWhitespace()
                obj[key] = try value(depth: depth + 1) // duplicate key: last wins, like JSON.parse
                skipWhitespace()
                if peek == UInt8(ascii: ",") { i += 1; continue }
                try expect("}")
                return obj
            }
        }

        mutating func array(depth: Int) throws(JSONParseError) -> [JSONValue] {
            i += 1
            var items: [JSONValue] = []
            skipWhitespace()
            if peek == UInt8(ascii: "]") { i += 1; return items }
            while true {
                skipWhitespace()
                items.append(try value(depth: depth + 1))
                skipWhitespace()
                if peek == UInt8(ascii: ",") { i += 1; continue }
                try expect("]")
                return items
            }
        }

        mutating func hex4() throws(JSONParseError) -> UInt32 {
            guard i + 4 <= bytes.count, let v = UInt32(String(decoding: bytes[i..<i + 4], as: UTF8.self), radix: 16)
            else { throw fail() }
            i += 4
            return v
        }

        mutating func string() throws(JSONParseError) -> String {
            i += 1
            var out: [UInt8] = []
            while true {
                guard let c = peek else { throw fail() }
                i += 1
                switch c {
                case UInt8(ascii: "\""):
                    guard let s = String(bytes: out, encoding: .utf8) else { throw fail() }
                    return s
                case UInt8(ascii: "\\"):
                    guard let e = peek else { throw fail() }
                    i += 1
                    var scalar: UInt32
                    switch e {
                    case UInt8(ascii: "\""), UInt8(ascii: "\\"), UInt8(ascii: "/"): out.append(e); continue
                    case UInt8(ascii: "b"): scalar = 0x08
                    case UInt8(ascii: "f"): scalar = 0x0C
                    case UInt8(ascii: "n"): scalar = 0x0A
                    case UInt8(ascii: "r"): scalar = 0x0D
                    case UInt8(ascii: "t"): scalar = 0x09
                    case UInt8(ascii: "u"):
                        scalar = try hex4()
                        if (0xD800..<0xDC00).contains(scalar), bytes[i...].starts(with: Array("\\u".utf8)) {
                            i += 2
                            let low = try hex4()
                            guard (0xDC00..<0xE000).contains(low) else { throw fail() }
                            scalar = 0x10000 + ((scalar - 0xD800) << 10) + (low - 0xDC00)
                        }
                    default: throw fail()
                    }
                    let u = Unicode.Scalar(scalar) ?? "\u{FFFD}" // lone surrogate, as JS would keep it
                    out.append(contentsOf: Array(String(Character(u)).utf8))
                default:
                    guard c >= 0x20 else { throw fail() }
                    out.append(c)
                }
            }
        }

        mutating func number() throws(JSONParseError) -> String {
            let start = i
            func digits(_ p: inout Parser) -> Int {
                let s = p.i
                while let c = p.peek, (0x30...0x39).contains(c) { p.i += 1 }
                return p.i - s
            }
            if peek == UInt8(ascii: "-") { i += 1 }
            guard digits(&self) > 0 else { throw fail() }
            if peek == UInt8(ascii: ".") { i += 1; guard digits(&self) > 0 else { throw fail() } }
            if peek == UInt8(ascii: "e") || peek == UInt8(ascii: "E") {
                i += 1
                if peek == UInt8(ascii: "+") || peek == UInt8(ascii: "-") { i += 1 }
                guard digits(&self) > 0 else { throw fail() }
            }
            return String(decoding: bytes[start..<i], as: UTF8.self)
        }
    }
}

// MARK: - Printing

extension JSONValue {
    func serialized() -> String {
        var out = ""
        write(to: &out, indent: "")
        return out
    }

    private func write(to out: inout String, indent: String) {
        let inner = indent + "  "
        switch self {
        case .null: out += "null"
        case .bool(let b): out += b ? "true" : "false"
        case .number(let n): out += n
        case .string(let s): Self.writeString(s, to: &out)
        case .array(let items):
            guard !items.isEmpty else { out += "[]"; return }
            out += "[\n"
            for (n, item) in items.enumerated() {
                out += inner
                item.write(to: &out, indent: inner)
                out += n == items.count - 1 ? "\n" : ",\n"
            }
            out += indent + "]"
        case .object(let obj):
            guard !obj.isEmpty else { out += "{}"; return }
            out += "{\n"
            for (n, entry) in obj.entries.enumerated() {
                out += inner
                Self.writeString(entry.key, to: &out)
                out += ": "
                entry.value.write(to: &out, indent: inner)
                out += n == obj.entries.count - 1 ? "\n" : ",\n"
            }
            out += indent + "}"
        }
    }

    private static func writeString(_ s: String, to out: inout String) {
        out += "\""
        for u in s.unicodeScalars {
            switch u {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            case "\u{08}": out += "\\b"
            case "\u{0C}": out += "\\f"
            case _ where u.value < 0x20: out += String(format: "\\u%04x", u.value)
            default: out.unicodeScalars.append(u)
            }
        }
        out += "\""
    }
}
