import Darwin
import Foundation

// notchkeeper-hook — forwards a Claude Code hook event (stdin JSON) to the NotchKeeper app.
// Fail-open: app missing, slow or anything odd → exit 0 with no output, so Claude Code is never blocked.
// Usage: notchkeeper-hook <EventName> < payload.json

signal(SIGPIPE, SIG_IGN)

let event = CommandLine.arguments.dropFirst().first ?? ""
let payload: Data = isatty(STDIN_FILENO) == 1 ? Data() : (NotchSocket.readAll(STDIN_FILENO) ?? Data())
guard !payload.isEmpty else { exit(0) }

// A permission request waits for a click in the island; stay under the hook's 120 s timeout so we exit
// cleanly (no output → Claude Code asks in the terminal). Everything else must not hold Claude up.
let timeout = event == "PermissionRequest" ? 110 : 2
guard let fd = NotchSocket.connect(to: NotchSocket.defaultPath, timeoutSeconds: timeout) else { exit(0) }
guard NotchSocket.writeAll(fd, NotchSocket.encode(event: event, payload: payload)) else { exit(0) }
shutdown(fd, SHUT_WR)

if let reply = NotchSocket.readAll(fd), !reply.isEmpty {
    FileHandle.standardOutput.write(reply)
}
exit(0)
