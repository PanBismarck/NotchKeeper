import AppKit
import Observation

/// User preferences, persisted in UserDefaults. `onChange` lets the island re-apply them (no polling).
@MainActor @Observable
final class AppSettings {
    static let shared: AppSettings = {
        migrateLegacyDefaults()
        return AppSettings()
    }()

    /// One-time copy of the preferences saved while the app was called Notch (bundle id pl.bismarck.Notch).
    private static func migrateLegacyDefaults(into defaults: UserDefaults = .standard) {
        let flag = "migratedFromNotch"
        guard !defaults.bool(forKey: flag) else { return }
        defaults.set(true, forKey: flag)
        guard let old = defaults.persistentDomain(forName: "pl.bismarck.Notch") else { return }
        for (key, value) in old where defaults.object(forKey: key) == nil { defaults.set(value, forKey: key) }
    }

    enum Shortcut: String, CaseIterable, Identifiable {
        case off, optionCommandN, controlOptionN, controlOptionSpace
        var id: String { rawValue }
        var label: String {
            switch self {
            case .off: "Brak"
            case .optionCommandN: "⌥⌘N"
            case .controlOptionN: "⌃⌥N"
            case .controlOptionSpace: "⌃⌥Spacja"
            }
        }
    }

    /// Built-in sounds from /System/Library/Sounds.
    static let systemSounds = ["Basso", "Blow", "Bottle", "Frog", "Funk", "Glass", "Hero", "Morse",
                               "Ping", "Pop", "Purr", "Sosumi", "Submarine", "Tink"]

    /// Resting the pointer on the notch opens the island.
    var hoverToExpand: Bool { didSet { save(hoverToExpand, "hoverToExpand") } }
    /// Seconds before a click-opened island folds back after the pointer leaves.
    var collapseDelay: Double { didSet { save(collapseDelay, "collapseDelay") } }
    /// Seconds the ears stay out after a turn ends.
    var finishedLinger: Double { didSet { save(finishedLinger, "finishedLinger") } }
    /// `localizedName` of the chosen display; empty = the notched one.
    var screenName: String { didSet { save(screenName, "screenName") } }
    var soundsEnabled: Bool { didSet { save(soundsEnabled, "soundsEnabled") } }
    var waitingSound: String { didSet { save(waitingSound, "waitingSound") } }
    var doneSound: String { didSet { save(doneSound, "doneSound") } }
    var shortcut: Shortcut { didSet { save(shortcut.rawValue, "shortcut") } }
    /// Hide the island while the frontmost app is in full screen (a pending approval still shows it).
    var hideInFullScreen: Bool { didSet { save(hideInFullScreen, "hideInFullScreen") } }
    /// …but stay tucked into the notch: hover shows the ears, a click opens the island.
    var peekInFullScreen: Bool { didSet { save(peekInFullScreen, "peekInFullScreen") } }
    /// Liquid Glass (macOS 26+, material on 15) behind the expanded island; the notch and ears stay black.
    var glassIsland: Bool { didSet { save(glassIsland, "glassIsland") } }
    /// Glass see-through amount: 0 = frosted, 1 = clear.
    var glassIntensity: Double { didSet { save(glassIntensity, "glassIntensity") } }
    /// Take transparency from macOS (Appearance → Liquid Glass) instead of the slider.
    var glassFollowsSystem: Bool { didSet { save(glassFollowsSystem, "glassFollowsSystem") } }

    @ObservationIgnored var onChange: () -> Void = {}
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        hoverToExpand = defaults.object(forKey: "hoverToExpand") as? Bool ?? true
        collapseDelay = defaults.object(forKey: "collapseDelay") as? Double ?? 0.3
        finishedLinger = defaults.object(forKey: "finishedLinger") as? Double ?? SessionStore.defaultFinishedLinger
        screenName = defaults.string(forKey: "screenName") ?? ""
        soundsEnabled = defaults.object(forKey: "soundsEnabled") as? Bool ?? false
        waitingSound = defaults.string(forKey: "waitingSound") ?? "Ping"
        doneSound = defaults.string(forKey: "doneSound") ?? "Glass"
        shortcut = defaults.string(forKey: "shortcut").flatMap(Shortcut.init) ?? .optionCommandN
        hideInFullScreen = defaults.object(forKey: "hideInFullScreen") as? Bool ?? true
        peekInFullScreen = defaults.object(forKey: "peekInFullScreen") as? Bool ?? true
        glassIsland = defaults.object(forKey: "glassIsland") as? Bool ?? true
        glassIntensity = defaults.object(forKey: "glassIntensity") as? Double ?? 0.6
        glassFollowsSystem = defaults.object(forKey: "glassFollowsSystem") as? Bool ?? true
    }

    private func save(_ value: Any, _ key: String) {
        defaults.set(value, forKey: key)
        onChange()
    }

    /// Plays the sound for `alert` if sounds are on.
    func play(_ alert: SessionAlert) {
        guard soundsEnabled else { return }
        let name = switch alert {
        case .waiting: waitingSound
        case .done: doneSound
        case .error: "Basso"
        }
        NSSound(named: name)?.play()
    }
}
