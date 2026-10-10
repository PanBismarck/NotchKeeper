import SwiftUI

@main
struct NotchKeeperApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Window("Ustawienia NotchKeeper", id: SettingsView.windowID) {
            SettingsView(settings: AppSettings.shared)
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(.suppressed)
        Window("Hooki Claude Code", id: HookSetupView.windowID) {
            HookSetupView()
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(.suppressed)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var island: IslandWindowController?
    private lazy var hookServer = HookServer { [weak self] event, reply in
        HookServer.log.debug("event \(event.name, privacy: .public) tool=\(event.toolName ?? "-", privacy: .public)")
        Task { @MainActor in
            guard let island = self?.island else { reply?.send(nil); return }
            island.handle(event, reply: reply)
        }
    }

    private(set) lazy var demo = DemoRunner { [weak self] event, reply in
        guard let island = self?.island else { reply?.send(nil); return }
        island.handle(event, reply: reply)
    }

    private var hotKey: GlobalHotKey?
    private var sigterm: DispatchSourceSignal?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let settings = AppSettings.shared
        let island = IslandWindowController(settings: settings)
        self.island = island
        island.contextMenu = { [weak self, weak island] in
            guard let self, let island else { return NSMenu() }
            return NotchMenu.make(demo: self.demo, open: island.openWindow(id:))
        }
        hotKey = GlobalHotKey { [weak island] in island?.toggle() }
        hotKey?.set(settings.shortcut)
        var shortcut = settings.shortcut
        settings.onChange = { [weak self, weak island] in
            island?.applySettings()
            if settings.shortcut != shortcut { shortcut = settings.shortcut; self?.hotKey?.set(shortcut) }
        }
        hookServer.start()
        HookInstaller.refreshHelperIfInstalled()

        // `pkill`/logout send SIGTERM, which skips applicationWillTerminate — route it through a normal quit.
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler { NSApplication.shared.terminate(nil) }
        source.resume()
        sigterm = source
    }

    func applicationWillTerminate(_ notification: Notification) {
        demo.stop()
        hookServer.stop()
    }
}

/// Right-click menu on the notch. Built on demand — nothing lives in the menu bar.
@MainActor
enum NotchMenu {
    static func make(demo: DemoRunner, open: @escaping (String) -> Void) -> NSMenu {
        let menu = NSMenu()
        menu.addItem(ActionItem("Ustawienia…") { open(SettingsView.windowID) })
        menu.addItem(ActionItem("Hooki Claude Code…") { open(HookSetupView.windowID) })
        menu.addItem(ActionItem(demo.isRunning ? "Zatrzymaj demo" : "Tryb demo") {
            demo.isRunning ? demo.stop() : demo.start()
        })
        menu.addItem(.separator())
        menu.addItem(ActionItem("Zakończ NotchKeeper") { NSApplication.shared.terminate(nil) })
        return menu
    }
}

@MainActor
private final class ActionItem: NSMenuItem {
    private let handler: @MainActor () -> Void

    init(_ title: String, handler: @escaping @MainActor () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) { fatalError("not supported") }

    @objc private func run() { handler() }
}
