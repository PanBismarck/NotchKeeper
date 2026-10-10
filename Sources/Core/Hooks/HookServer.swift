import Darwin
import Foundation
import os
import Synchronization

/// Unix-socket server receiving events from `notchkeeper-hook`.
/// Idle cost: none — the listening fd is watched by a `DispatchSource`, no thread blocks or polls.
final class HookServer: Sendable {
    /// `reply` is non-nil for events that wait for an answer (`PermissionRequest`): the client stays
    /// connected until the app calls `reply.send(_:)` — or `replyDeadline` passes.
    typealias Handler = @Sendable (HookEvent, HookReply?) -> Void

    static let maxConnections = 32
    static let receiveTimeoutSeconds = 5
    /// Backstop only; the app answers or gives up well before notchkeeper-hook's own timeout.
    static let replyDeadline: TimeInterval = 120
    static let log = Logger(subsystem: "io.github.panbismarck.NotchKeeper", category: "hooks")

    let path: String
    private let handler: Handler
    private let queue = DispatchQueue(label: "io.github.panbismarck.NotchKeeper.hooks", qos: .utility, attributes: .concurrent)

    private struct State {
        var source: DispatchSourceRead?
        var connections = 0
    }
    private let state = Mutex(State())

    init(path: String = NotchSocket.defaultPath, handler: @escaping Handler) {
        self.path = path
        self.handler = handler
    }

    /// Returns false when the socket can't be set up (or another Notch already owns it).
    @discardableResult
    func start() -> Bool {
        guard var addr = NotchSocket.address(for: path) else {
            Self.log.error("socket path too long: \(self.path, privacy: .public)")
            return false
        }
        let dir = (path as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir)

        // A live listener means another instance is running — don't steal its socket.
        if let other = NotchSocket.connect(to: path, timeoutSeconds: 1) {
            close(other)
            Self.log.error("another instance is listening on the socket")
            return false
        }
        unlink(path) // stale socket from a crash

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        let oldMask = umask(0o177) // socket file created as 0600, no window where it's wider
        let bound = NotchSocket.withSockaddr(&addr) { bind(fd, $0, $1) } == 0
        umask(oldMask)
        guard bound, chmod(path, 0o600) == 0, listen(fd, Int32(Self.maxConnections)) == 0 else {
            Self.log.error("bind/listen failed: errno \(errno)")
            close(fd)
            return false
        }
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)

        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in self?.acceptPending(fd) }
        source.setCancelHandler { close(fd) }
        state.withLock { $0.source = source }
        source.resume()
        Self.log.notice("listening on \(self.path, privacy: .public)")
        return true
    }

    func stop() {
        let source = state.withLock { s in defer { s.source = nil }; return s.source }
        guard let source else { return }
        source.cancel()
        unlink(path)
    }

    // MARK: - Connections

    private func acceptPending(_ listenFD: Int32) {
        while true {
            let fd = accept(listenFD, nil, nil)
            guard fd >= 0 else { return } // EAGAIN: drained
            var euid: uid_t = 0, egid: gid_t = 0
            let sameUser = getpeereid(fd, &euid, &egid) == 0 && euid == getuid()
            let admitted = sameUser && state.withLock { s in
                guard s.connections < Self.maxConnections else { return false }
                s.connections += 1
                return true
            }
            guard admitted else { close(fd); continue }
            _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) & ~O_NONBLOCK) // accepted fds inherit O_NONBLOCK
            NotchSocket.configure(fd, timeoutSeconds: Self.receiveTimeoutSeconds)
            queue.async { [weak self] in self?.handleClient(fd) }
        }
    }

    private func handleClient(_ fd: Int32) {
        let release: @Sendable () -> Void = { [self] in
            close(fd)
            self.state.withLock { $0.connections -= 1 }
        }
        guard let message = NotchSocket.readAll(fd), let event = HookEvent(message: message) else {
            Self.log.debug("dropped malformed or oversized message")
            release()
            return
        }
        guard event.awaitsReply else {
            // Plain events need no reply: closing the fd lets notchkeeper-hook exit right away.
            handler(event, nil)
            release()
            return
        }
        // Held without blocking a thread: the fd just stays open until someone answers.
        let reply = HookReply(fd: fd, release: release)
        queue.asyncAfter(deadline: .now() + Self.replyDeadline) { reply.send(nil) }
        handler(event, reply)
    }
}

/// One-shot answer to a waiting `notchkeeper-hook`. Thread-safe; later calls are ignored.
final class HookReply: Sendable {
    private let sink: Mutex<(@Sendable (Data?) -> Void)?>

    /// `sink` runs at most once, with the answer body (demo mode uses this without a socket).
    init(_ sink: @escaping @Sendable (Data?) -> Void) {
        self.sink = Mutex(sink)
    }

    fileprivate convenience init(fd: Int32, release: @escaping @Sendable () -> Void) {
        self.init { body in
            if let body, !body.isEmpty { _ = NotchSocket.writeAll(fd, body) }
            release()
        }
    }

    /// `nil` sends nothing — notchkeeper-hook prints nothing and Claude Code asks in the terminal as usual.
    func send(_ body: Data?) {
        guard let sink = sink.withLock({ v in defer { v = nil }; return v }) else { return }
        sink(body)
    }

    var isAnswered: Bool { sink.withLock { $0 == nil } }
}
