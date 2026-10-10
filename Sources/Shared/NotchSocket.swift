import Darwin
import Foundation

/// Shared by the app (server) and `notchkeeper-hook` (client). Keep it light — the hook runs on every Claude Code event.
///
/// Wire format (client → app): `NOTCH1 <event-from-argv>\n<raw hook JSON>`, then the client half-closes.
/// The app answers with an optional body (empty for plain events) and closes.
enum NotchSocket {
    static let maxPayload = 1_048_576
    static let magic = "NOTCH1"

    /// `NOTCHKEEPER_SOCKET` overrides the path (tests, manual runs).
    static var defaultPath: String {
        if let override = ProcessInfo.processInfo.environment["NOTCHKEEPER_SOCKET"], !override.isEmpty { return override }
        return NSHomeDirectory() + "/Library/Application Support/NotchKeeper/notch.sock"
    }

    // MARK: Wire format

    static func encode(event: String, payload: Data) -> Data {
        var out = Data("\(magic) \(event)\n".utf8)
        out.append(payload)
        return out
    }

    static func decode(_ message: Data) -> (event: String, payload: Data)? {
        guard let nl = message.firstIndex(of: UInt8(ascii: "\n")),
              let header = String(data: message[..<nl], encoding: .utf8),
              header == magic || header.hasPrefix(magic + " ") else { return nil }
        let event = header.dropFirst(magic.count).trimmingCharacters(in: .whitespaces)
        return (event, Data(message[message.index(after: nl)...]))
    }

    // MARK: Socket helpers

    static func address(for path: String) -> sockaddr_un? {
        var addr = sockaddr_un()
        let bytes = Array(path.utf8)
        guard !bytes.isEmpty, bytes.count < MemoryLayout.size(ofValue: addr.sun_path) else { return nil }
        addr.sun_family = sa_family_t(AF_UNIX)
        addr.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        withUnsafeMutableBytes(of: &addr.sun_path) { $0.copyBytes(from: bytes) } // rest stays zero → NUL-terminated
        return addr
    }

    static func withSockaddr<R>(_ addr: inout sockaddr_un, _ body: (UnsafePointer<sockaddr>, socklen_t) -> R) -> R {
        withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { body($0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
    }

    static func configure(_ fd: Int32, timeoutSeconds: Int) {
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        var tv = timeval(tv_sec: timeoutSeconds, tv_usec: 0)
        let len = socklen_t(MemoryLayout<timeval>.size)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, len)
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, len)
    }

    /// Returns a connected fd, or nil when nobody listens (app not running) — never blocks.
    static func connect(to path: String, timeoutSeconds: Int) -> Int32? {
        guard var addr = address(for: path) else { return nil }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        configure(fd, timeoutSeconds: timeoutSeconds)
        guard withSockaddr(&addr, { Darwin.connect(fd, $0, $1) }) == 0 else { close(fd); return nil }
        return fd
    }

    static func writeAll(_ fd: Int32, _ data: Data) -> Bool {
        data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return true }
            var off = 0
            while off < raw.count {
                let n = send(fd, base + off, raw.count - off, 0)
                if n < 0 { if errno == EINTR { continue }; return false }
                off += n
            }
            return true
        }
    }

    /// Reads until EOF or timeout. nil when the data exceeds `limit` or the read failed outright.
    static func readAll(_ fd: Int32, limit: Int = maxPayload) -> Data? {
        var out = Data()
        var buf = [UInt8](repeating: 0, count: 16_384)
        while true {
            let n = read(fd, &buf, buf.count)
            if n < 0 {
                if errno == EINTR { continue }
                return out.isEmpty ? nil : out   // timeout with partial data → caller's JSON parse decides
            }
            if n == 0 { return out }
            out.append(contentsOf: buf[..<n])
            if out.count > limit { return nil }
        }
    }
}
