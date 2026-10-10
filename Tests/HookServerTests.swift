import Darwin
import Foundation
import Synchronization
import Testing

@Suite struct WireFormatTests {
    @Test func roundTrip() throws {
        let payload = Data(#"{"a":1}"#.utf8)
        let decoded = try #require(NotchSocket.decode(NotchSocket.encode(event: "Stop", payload: payload)))
        #expect(decoded.event == "Stop")
        #expect(decoded.payload == payload)
    }

    @Test func emptyEventName() throws {
        let decoded = try #require(NotchSocket.decode(NotchSocket.encode(event: "", payload: Data("{}".utf8))))
        #expect(decoded.event == "")
    }

    @Test func rejectsForeignData() {
        #expect(NotchSocket.decode(Data(#"{"hook_event_name":"Stop"}"#.utf8)) == nil)
        #expect(NotchSocket.decode(Data("NOTCH1X\n{}".utf8)) == nil)
    }

    @Test func pathTooLong() {
        #expect(NotchSocket.address(for: String(repeating: "a", count: 200)) == nil)
        #expect(NotchSocket.address(for: "/tmp/x.sock") != nil)
    }
}

@Suite struct HookEventTests {
    @Test func payloadNameWins() throws {
        let json = Data(#"{"hook_event_name":"PreToolUse","session_id":"s1","cwd":"/p","tool_name":"Edit"}"#.utf8)
        let e = try #require(HookEvent(argvEvent: "Other", payload: json))
        #expect(e.name == "PreToolUse")
        #expect(e.sessionID == "s1")
        #expect(e.cwd == "/p")
        #expect(e.toolName == "Edit")
    }

    @Test func fallsBackToArgv() throws {
        let e = try #require(HookEvent(argvEvent: "Stop", payload: Data(#"{"session_id":"s1"}"#.utf8)))
        #expect(e.name == "Stop")
    }

    @Test func rejectsInvalid() {
        #expect(HookEvent(argvEvent: "Stop", payload: Data("not json".utf8)) == nil)
        #expect(HookEvent(argvEvent: "Stop", payload: Data("[1]".utf8)) == nil)
        #expect(HookEvent(argvEvent: "", payload: Data("{}".utf8)) == nil)
    }
}

@Suite(.serialized) struct HookServerTests {
    private static func tempPath() -> String { "/tmp/notch-test-\(UUID().uuidString.prefix(8)).sock" }

    /// Sends like notchkeeper-hook does; returns the reply (empty for plain events).
    private static func send(_ data: Data, to path: String) -> Data? {
        guard let fd = NotchSocket.connect(to: path, timeoutSeconds: 2) else { return nil }
        defer { close(fd) }
        _ = NotchSocket.writeAll(fd, data)
        shutdown(fd, SHUT_WR)
        return NotchSocket.readAll(fd)
    }

    @Test func deliversEventAndCleansUp() async throws {
        let path = Self.tempPath()
        let received = Mutex<[HookEvent]>([])
        let server = HookServer(path: path) { e, _ in received.withLock { $0.append(e) } }
        #expect(server.start())

        var st = stat()
        #expect(stat(path, &st) == 0)
        #expect(st.st_mode & 0o777 == 0o600)

        let msg = NotchSocket.encode(event: "PreToolUse", payload: Data(#"{"tool_name":"Bash"}"#.utf8))
        #expect(Self.send(msg, to: path) == Data())
        // Handler runs before the server closes the fd, so the event is already in.
        let events = received.withLock { $0 }
        #expect(events.map(\.name) == ["PreToolUse"])
        #expect(events.first?.toolName == "Bash")

        server.stop()
        #expect(access(path, F_OK) != 0)
        #expect(NotchSocket.connect(to: path, timeoutSeconds: 1) == nil)
    }

    @Test func secondInstanceDoesNotStealSocket() {
        let path = Self.tempPath()
        let a = HookServer(path: path) { _, _ in }
        let b = HookServer(path: path) { _, _ in }
        #expect(a.start())
        #expect(!b.start())
        a.stop()
    }

    @Test func dropsMalformedAndOversized() {
        let path = Self.tempPath()
        let count = Mutex(0)
        let server = HookServer(path: path) { _, _ in count.withLock { $0 += 1 } }
        #expect(server.start())
        _ = Self.send(Data("garbage".utf8), to: path)
        var big = NotchSocket.encode(event: "Stop", payload: Data(#"{"x":""#.utf8))
        big.append(Data(repeating: UInt8(ascii: "a"), count: NotchSocket.maxPayload + 10))
        big.append(Data(#""}"#.utf8))
        _ = Self.send(big, to: path)
        #expect(count.withLock { $0 } == 0)
        server.stop()
    }

    @Test func noAppMeansNoConnection() {
        #expect(NotchSocket.connect(to: Self.tempPath(), timeoutSeconds: 1) == nil)
    }
}
