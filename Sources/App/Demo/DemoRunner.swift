import Foundation
import Observation

/// Plays `DemoScript` into the island. A permission step waits for the user's click like a real hook would;
/// the answer goes nowhere.
@MainActor @Observable
final class DemoRunner {
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private let sink: (HookEvent, HookReply?) -> Void

    init(sink: @escaping (HookEvent, HookReply?) -> Void) {
        self.sink = sink
    }

    private(set) var isRunning = false

    func start() {
        stop()
        isRunning = true
        task = Task { [weak self] in
            for step in DemoScript.steps {
                guard !Task.isCancelled, let self else { return }
                switch step {
                case .pause(let seconds):
                    try? await Task.sleep(for: .seconds(seconds))
                case .event(let event) where event.awaitsReply:
                    await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
                        self.sink(event, HookReply { _ in done.resume() })
                    }
                case .event(let event):
                    self.sink(event, nil)
                }
            }
            self?.task = nil
            self?.isRunning = false
        }
    }

    /// Ends the demo sessions right away (also answers a pending demo permission card).
    func stop() {
        guard let task else { return }
        task.cancel()
        self.task = nil
        isRunning = false
        for id in DemoScript.sessionIDs {
            let body = #"{"hook_event_name":"SessionEnd","session_id":"\#(id)"}"#
            if let event = HookEvent(argvEvent: "SessionEnd", payload: Data(body.utf8)) { sink(event, nil) }
        }
    }
}
