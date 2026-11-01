import Foundation
import FamilyControls

/// Everything Ribbon keeps, as small JSON files in the app group's folder, so the app and its extensions (the
/// schedule monitor, the blocked screen) read and write the same session types, schedules and sessions.
/// It all stays on the phone.
enum SharedStore {
    static let group = "group.com.jeremiahlena.ribbon"

    static var folder: URL {
        if let shared = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) { return shared }
        // Without the app group (a build signed without it), keep to the app's own folder.
        let own = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: own, withIntermediateDirectories: true)
        return own
    }

    static var defaults: UserDefaults { UserDefaults(suiteName: group) ?? .standard }

    private static func url(_ name: String) -> URL { folder.appendingPathComponent(name + ".json") }

    private static func load<T: Decodable>(_ name: String, as type: T.Type) -> T? {
        guard let data = try? Data(contentsOf: url(name)) else { return nil }
        return try? decoder.decode(T.self, from: data)
    }

    private static func save<T: Encodable>(_ value: T?, _ name: String) {
        guard let value else { try? FileManager.default.removeItem(at: url(name)); return }
        guard let data = try? encoder.encode(value) else { return }
        try? data.write(to: url(name), options: .atomic)
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }()

    // MARK: Session types and schedules

    static var profiles: [SessionProfile] {
        get {
            if let saved = load("profiles", as: [SessionProfile].self) { return saved }
            let made = SessionProfile.defaults()
            save(made, "profiles")
            return made
        }
        set { save(newValue, "profiles") }
    }

    static var schedules: [FocusSchedule] {
        get { load("schedules", as: [FocusSchedule].self) ?? [] }
        set { save(newValue, "schedules") }
    }

    // MARK: Sessions

    static var active: ActiveSession? {
        get { load("active", as: ActiveSession.self) }
        set { save(newValue, "active") }
    }

    static var sessions: [SessionRecord] {
        get { load("sessions", as: [SessionRecord].self) ?? [] }
        set { save(Array(newValue.suffix(300)), "sessions") }
    }

    static func record(_ id: String) -> SessionRecord? { sessions.first { $0.id == id } }

    static func update(_ id: String, _ change: (inout SessionRecord) -> Void) {
        var all = sessions
        guard let index = all.firstIndex(where: { $0.id == id }) else { return }
        change(&all[index])
        sessions = all
    }

    static func add(_ record: SessionRecord) {
        sessions = sessions + [record]
    }

    /// The blocked screen was closed during the running session.
    static func countBlocked() {
        guard let active else { return }
        update(active.recordID) { $0.blocks += 1 }
    }

    // MARK: Emergency pass

    static var passes: [EmergencyPass] {
        get { load("passes", as: [EmergencyPass].self) ?? [] }
        set { save(newValue, "passes") }
    }

    /// This week's pass, if it's been used: a new one every Monday.
    static func passUsedThisWeek(now: Date = Date()) -> EmergencyPass? {
        let monday = Calendar.current.weekStart(for: now)
        return passes.last { $0.date >= monday }
    }

    static func windowWasEnded(_ key: String) -> Bool {
        passes.contains { $0.windowKey == key }
    }

    // MARK: Distracting apps and time marks

    /// The apps and categories that count as distracting, for check-ins and session reviews.
    static var distracting: FamilyActivitySelection {
        get { load("distracting", as: FamilyActivitySelection.self) ?? FamilyActivitySelection(includeEntireCategory: true) }
        set { save(newValue, "distracting") }
    }

    /// Your categories. Saved without dates, so the Screen Time report can read them with a plain decoder.
    static var categories: [AppCategory] {
        get {
            if let saved = AppCategory.saved() { return saved }
            let made = AppCategory.defaults()
            categories = made
            return made
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            try? data.write(to: folder.appendingPathComponent("categories.json"), options: .atomic)
        }
    }

    static var hasDistracting: Bool {
        let selection = distracting
        return !selection.applicationTokens.isEmpty || !selection.categoryTokens.isEmpty || !selection.webDomainTokens.isEmpty
    }

    /// Minutes in distracting apps reached each day, as far as iOS has said: "2026-11-01" → 45.
    static var dayMarks: [String: Int] {
        get { load("marks", as: [String: Int].self) ?? [:] }
        set { save(newValue, "marks") }
    }

    static func distractingToday(_ now: Date = Date()) -> Int { dayMarks[Format.dayKey(now)] ?? 0 }

    // MARK: Settings

    static var tone: Tone {
        get { Tone(rawValue: defaults.string(forKey: "tone") ?? "") ?? .friendly }
        set { defaults.set(newValue.rawValue, forKey: "tone") }
    }

    static var checkIns: Bool {
        get { defaults.object(forKey: "checkIns") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "checkIns") }
    }
}
