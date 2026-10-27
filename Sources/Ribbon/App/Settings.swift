import Foundation
import ServiceManagement

/// Preferences, kept in UserDefaults.
@Observable @MainActor final class Settings {
    private let defaults = UserDefaults.standard

    var idleMinutes: Int { didSet { defaults.set(idleMinutes, forKey: "idleMinutes") } }
    var focusGoalHours: Double { didSet { defaults.set(focusGoalHours, forKey: "focusGoalHours") } }
    var breakReminders: Bool { didSet { defaults.set(breakReminders, forKey: "breakReminders") } }
    var breakIntervalMinutes: Int { didSet { defaults.set(breakIntervalMinutes, forKey: "breakIntervalMinutes") } }
    var showOrbWhenIdle: Bool { didSet { defaults.set(showOrbWhenIdle, forKey: "showOrbWhenIdle") } }
    /// You hid the orb. Sessions keep running; it comes back when you show it again.
    var orbHidden: Bool { didSet { defaults.set(orbHidden, forKey: "orbHidden") } }
    var automaticUpdates: Bool { didSet { defaults.set(automaticUpdates, forKey: "automaticUpdates") } }
    var checkIns: Bool { didSet { defaults.set(checkIns, forKey: "checkIns") } }
    var checkInMinutes: Int { didSet { defaults.set(checkInMinutes, forKey: "checkInMinutes") } }
    var orbTone: OrbTone { didSet { defaults.set(orbTone.rawValue, forKey: "orbTone") } }

    var focusGoal: TimeInterval { focusGoalHours * 3600 }
    var breakInterval: TimeInterval { TimeInterval(breakIntervalMinutes * 60) }

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                logLine("Launch at login: \(error.localizedDescription)")
            }
        }
    }

    init() {
        defaults.register(defaults: ["idleMinutes": 5, "focusGoalHours": 4.0, "breakReminders": true,
                                     "breakIntervalMinutes": 50, "showOrbWhenIdle": true, "orbHidden": false, "automaticUpdates": true,
                                     "checkIns": true, "checkInMinutes": 30, "orbTone": OrbTone.friendly.rawValue])
        idleMinutes = defaults.integer(forKey: "idleMinutes")
        focusGoalHours = defaults.double(forKey: "focusGoalHours")
        breakReminders = defaults.bool(forKey: "breakReminders")
        breakIntervalMinutes = defaults.integer(forKey: "breakIntervalMinutes")
        showOrbWhenIdle = defaults.bool(forKey: "showOrbWhenIdle")
        orbHidden = defaults.bool(forKey: "orbHidden")
        automaticUpdates = defaults.bool(forKey: "automaticUpdates")
        checkIns = defaults.bool(forKey: "checkIns")
        checkInMinutes = defaults.integer(forKey: "checkInMinutes")
        orbTone = OrbTone(rawValue: defaults.string(forKey: "orbTone") ?? "") ?? .friendly
    }
}

/// How the orb talks to you when you drift: out loud, and in check-ins.
enum OrbTone: String, CaseIterable, Sendable {
    case friendly, ruthless

    var label: String { self == .friendly ? "Friendly" : "Ruthless" }

    var detail: String {
        switch self {
        case .friendly: "Playful and a little funny, never mean."
        case .ruthless: "Brutal and unhinged. It roasts you with your whole day, swears, insults you, and screams by the fifth "
            + "time you ignore it or wave it off. It never touches self-harm, slurs or threats."
        }
    }

    /// The pace every line keeps, whatever its delivery.
    var pace: String { self == .friendly ? "Quick and light overall." : "Brisk overall, never drawn out." }

    /// How a line is read aloud when nothing more specific was chosen for it.
    var delivery: String {
        switch self {
        case .friendly: "A cheeky, warm little sidekick. Light, quick and playful, with a smile in the voice."
        case .ruthless: "Savage, contemptuous and sharp."
        }
    }
}
