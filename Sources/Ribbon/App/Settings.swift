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
    var automaticUpdates: Bool { didSet { defaults.set(automaticUpdates, forKey: "automaticUpdates") } }
    var checkIns: Bool { didSet { defaults.set(checkIns, forKey: "checkIns") } }
    var checkInMinutes: Int { didSet { defaults.set(checkInMinutes, forKey: "checkInMinutes") } }

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
                                     "breakIntervalMinutes": 50, "showOrbWhenIdle": true, "automaticUpdates": true,
                                     "checkIns": true, "checkInMinutes": 30])
        idleMinutes = defaults.integer(forKey: "idleMinutes")
        focusGoalHours = defaults.double(forKey: "focusGoalHours")
        breakReminders = defaults.bool(forKey: "breakReminders")
        breakIntervalMinutes = defaults.integer(forKey: "breakIntervalMinutes")
        showOrbWhenIdle = defaults.bool(forKey: "showOrbWhenIdle")
        automaticUpdates = defaults.bool(forKey: "automaticUpdates")
        checkIns = defaults.bool(forKey: "checkIns")
        checkInMinutes = defaults.integer(forKey: "checkInMinutes")
    }
}
