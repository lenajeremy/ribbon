import Foundation
import SQLite3

private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// Everything Ribbon records lives in one local SQLite file. Nothing here leaves the Mac.
@MainActor final class Store {
    static let folder: URL = {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = support.appendingPathComponent("Ribbon", isDirectory: true)
        // The app used to be called Focus Orb; bring its data along the first time.
        let old = support.appendingPathComponent("Focus Orb", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path), FileManager.default.fileExists(atPath: old.path) {
            try? FileManager.default.moveItem(at: old, to: dir)
        }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private var db: OpaquePointer?

    init(path: String = Store.folder.appendingPathComponent("activity.sqlite").path) {
        if sqlite3_open(path, &db) != SQLITE_OK { logLine("Couldn't open the database at \(path)") }
        run("PRAGMA journal_mode=WAL")
        for sql in [
            """
            CREATE TABLE IF NOT EXISTS activity (id INTEGER PRIMARY KEY, start REAL NOT NULL, end REAL NOT NULL,
              app TEXT NOT NULL, bundle TEXT NOT NULL, title TEXT NOT NULL, url TEXT NOT NULL, domain TEXT NOT NULL,
              key TEXT NOT NULL, category TEXT NOT NULL)
            """,
            "CREATE INDEX IF NOT EXISTS activity_start ON activity(start)",
            "CREATE INDEX IF NOT EXISTS activity_key ON activity(key)",
            "CREATE TABLE IF NOT EXISTS labels (key TEXT PRIMARY KEY, category TEXT NOT NULL, source TEXT NOT NULL, updated REAL NOT NULL)",
            "CREATE TABLE IF NOT EXISTS category_prefs (id TEXT PRIMARY KEY, kind TEXT NOT NULL, focus INTEGER NOT NULL)",
            "CREATE TABLE IF NOT EXISTS profiles (id TEXT PRIMARY KEY, json TEXT NOT NULL, sort INTEGER NOT NULL)",
            "CREATE TABLE IF NOT EXISTS custom_categories (id TEXT PRIMARY KEY, json TEXT NOT NULL, sort INTEGER NOT NULL)",
            "CREATE TABLE IF NOT EXISTS chats (id TEXT PRIMARY KEY, json TEXT NOT NULL, updated REAL NOT NULL)",
            """
            CREATE TABLE IF NOT EXISTS sessions (id INTEGER PRIMARY KEY, start REAL NOT NULL, end REAL, task TEXT NOT NULL,
              profile TEXT NOT NULL, outcome TEXT NOT NULL DEFAULT 'running', note TEXT NOT NULL DEFAULT '',
              nudges INTEGER NOT NULL DEFAULT 0, blocks INTEGER NOT NULL DEFAULT 0)
            """,
            "CREATE TABLE IF NOT EXISTS reports (period TEXT NOT NULL, kind TEXT NOT NULL, text TEXT NOT NULL, created REAL NOT NULL, PRIMARY KEY (period, kind))",
            "CREATE TABLE IF NOT EXISTS session_reviews (session_id INTEGER PRIMARY KEY, json TEXT NOT NULL, created REAL NOT NULL)",
            // Sessions taken off the Recent sessions list. Their records and activity stay.
            "CREATE TABLE IF NOT EXISTS hidden_sessions (session_id INTEGER PRIMARY KEY)",
        ] { run(sql) }
        // A session left "running" by a crash or quit ends where it was.
        run("UPDATE sessions SET outcome = 'interrupted', end = COALESCE(end, start) WHERE outcome = 'running'")
    }

    // MARK: Activity

    func beginActivity(_ o: FrontActivity, key: String, category: String, at date: Date) -> Int64 {
        run("INSERT INTO activity (start, end, app, bundle, title, url, domain, key, category) VALUES (?,?,?,?,?,?,?,?,?)",
            [date, date, o.app, o.bundleID, o.title, o.url, o.domain, key, category])
        return sqlite3_last_insert_rowid(db)
    }

    func extendActivity(_ id: Int64, to date: Date) {
        run("UPDATE activity SET end = MAX(start, ?) WHERE id = ?", [date, id])
    }

    func segments(from: Date, to: Date) -> [Segment] {
        rows("""
            SELECT id, start, end, app, bundle, title, domain, category FROM activity
            WHERE start < ? AND end > ? AND end > start ORDER BY start
            """, [to, from]).map {
            Segment(id: $0.int64(0),
                    start: max(from, Date(timeIntervalSince1970: $0.double(1))),
                    end: min(to, Date(timeIntervalSince1970: $0.double(2))),
                    app: $0.text(3), bundle: $0.text(4), title: $0.text(5), domain: $0.text(6), category: $0.text(7))
        }
    }

    func setCategory(_ category: String, forKey key: String) {
        run("UPDATE activity SET category = ? WHERE key = ?", [category, key])
    }

    func setCategory(_ category: String, forDomain domain: String) {
        run("UPDATE activity SET category = ? WHERE domain = ? OR domain LIKE ?", [category, domain, "%." + domain])
    }

    func setCategory(_ category: String, forBundle bundle: String) {
        run("UPDATE activity SET category = ? WHERE bundle = ? AND domain = ''", [category, bundle])
    }

    /// Apps and websites seen in a period, with time spent, for the Categories screen.
    func knownItems(from: Date, to: Date) -> [KnownItem] {
        rows("""
            SELECT CASE WHEN domain != '' THEN 'site:' || domain ELSE 'app:' || bundle END AS k,
                   MAX(app), MAX(domain), MAX(bundle), category, SUM(MIN(end, ?) - MAX(start, ?)) AS secs
            FROM activity WHERE start < ? AND end > ? GROUP BY k, category ORDER BY secs DESC
            """, [to, from, to, from]).reduce(into: [KnownItem]()) { items, row in
            let key = row.text(0)
            // Keep each app or site once, under the category it spent the most time in.
            if items.contains(where: { $0.key == key }) { return }
            items.append(KnownItem(key: key, app: row.text(1), domain: row.text(2), bundle: row.text(3),
                                   category: row.text(4), seconds: row.double(5)))
        }
    }

    // MARK: Labels and category preferences

    func labels() -> [String: (category: String, source: String)] {
        var result: [String: (String, String)] = [:]
        for row in rows("SELECT key, category, source FROM labels") { result[row.text(0)] = (row.text(1), row.text(2)) }
        return result
    }

    func deleteLabel(key: String) {
        run("DELETE FROM labels WHERE key = ?", [key])
    }

    /// Distinct apps and sites currently counted in a category.
    func keys(inCategory category: String) -> [(key: String, app: String, bundle: String, domain: String, title: String)] {
        rows("SELECT key, MAX(app), MAX(bundle), MAX(domain), MAX(title) FROM activity WHERE category = ? GROUP BY key", [category]).map {
            ($0.text(0), $0.text(1), $0.text(2), $0.text(3), $0.text(4))
        }
    }

    func setCategory(_ category: String, forKey key: String, from previous: String) {
        run("UPDATE activity SET category = ? WHERE key = ? AND category = ?", [category, key, previous])
    }

    func saveLabel(key: String, category: String, source: String) {
        run("INSERT OR REPLACE INTO labels (key, category, source, updated) VALUES (?,?,?,?)", [key, category, source, Date()])
    }

    func categoryPrefs() -> CategoryRules {
        var rules = CategoryRules()
        for row in rows("SELECT id, kind, focus FROM category_prefs") {
            if let kind = Productivity(rawValue: row.text(1)) { rules.kinds[row.text(0)] = kind }
            rules.focus[row.text(0)] = row.int(2) != 0
        }
        return rules
    }

    func saveCategoryPref(id: String, kind: Productivity, focus: Bool) {
        run("INSERT OR REPLACE INTO category_prefs (id, kind, focus) VALUES (?,?,?)", [id, kind.rawValue, focus])
    }

    // MARK: Chats with the AI

    func chats() -> [Chat] {
        rows("SELECT json FROM chats ORDER BY updated DESC LIMIT 50").compactMap {
            try? JSONDecoder().decode(Chat.self, from: Data($0.text(0).utf8))
        }
    }

    func saveChat(_ chat: Chat) {
        guard let data = try? JSONEncoder().encode(chat) else { return }
        run("INSERT OR REPLACE INTO chats (id, json, updated) VALUES (?,?,?)", [chat.id, String(decoding: data, as: UTF8.self), chat.updated])
    }

    func deleteChat(_ id: String) { run("DELETE FROM chats WHERE id = ?", [id]) }

    /// Tracked time per local day, newest first.
    func dailyTotals(days: Int) -> [(day: Date, seconds: Double)] {
        let from = Calendar.current.date(byAdding: .day, value: -days, to: Calendar.current.startOfDay(for: Date()))!
        return rows("""
            SELECT date(start, 'unixepoch', 'localtime') AS d, SUM(end - start) FROM activity
            WHERE start >= ? GROUP BY d ORDER BY d DESC
            """, [from]).compactMap { row in Format.day(fromKey: row.text(0)).map { ($0, row.double(1)) } }
    }

    // MARK: Your categories

    func customCategories() -> [Category] {
        rows("SELECT json FROM custom_categories ORDER BY sort").compactMap {
            try? JSONDecoder().decode(Category.self, from: Data($0.text(0).utf8))
        }
    }

    func saveCustomCategories(_ categories: [Category]) {
        run("DELETE FROM custom_categories")
        for (index, category) in categories.enumerated() {
            guard let data = try? JSONEncoder().encode(category) else { continue }
            run("INSERT INTO custom_categories (id, json, sort) VALUES (?,?,?)", [category.id, String(decoding: data, as: UTF8.self), index])
        }
    }

    /// A deleted category's time goes back to Other, and the AI may sort it again.
    func forgetCategory(_ id: String) {
        run("UPDATE activity SET category = 'other' WHERE category = ?", [id])
        run("DELETE FROM labels WHERE category = ?", [id])
        run("DELETE FROM category_prefs WHERE id = ?", [id])
    }

    // MARK: Session types

    func profiles() -> [SessionProfile] {
        rows("SELECT json FROM profiles ORDER BY sort").compactMap {
            try? JSONDecoder().decode(SessionProfile.self, from: Data($0.text(0).utf8))
        }
    }

    func saveProfiles(_ profiles: [SessionProfile]) {
        run("DELETE FROM profiles")
        for (index, profile) in profiles.enumerated() {
            guard let data = try? JSONEncoder().encode(profile) else { continue }
            run("INSERT INTO profiles (id, json, sort) VALUES (?,?,?)", [profile.id, String(decoding: data, as: UTF8.self), index])
        }
    }

    // MARK: Focus sessions

    func beginSession(task: String, profile: String, at date: Date) -> Int64 {
        run("INSERT INTO sessions (start, task, profile) VALUES (?,?,?)", [date, task, profile])
        return sqlite3_last_insert_rowid(db)
    }

    func endSession(_ id: Int64, outcome: String, note: String = "", at date: Date = Date()) {
        run("UPDATE sessions SET end = ?, outcome = ?, note = ? WHERE id = ?", [date, outcome, note, id])
    }

    func updateSessionTask(_ id: Int64, task: String) {
        run("UPDATE sessions SET task = ? WHERE id = ?", [task, id])
    }

    func countSession(_ id: Int64, nudge: Bool) {
        run(nudge ? "UPDATE sessions SET nudges = nudges + 1 WHERE id = ?" : "UPDATE sessions SET blocks = blocks + 1 WHERE id = ?", [id])
    }

    func sessions(from: Date, to: Date) -> [SessionRecord] {
        sessions(where: "s.start >= ? AND s.start < ?", [from, to])
    }

    func session(_ id: Int64) -> SessionRecord? {
        sessions(where: "s.id = ?", [id]).first
    }

    private func sessions(where condition: String, _ args: [Any?]) -> [SessionRecord] {
        rows("""
            SELECT s.id, s.start, s.end, s.task, s.profile, s.outcome, s.note, s.nudges, s.blocks, r.json, h.session_id
            FROM sessions s LEFT JOIN session_reviews r ON r.session_id = s.id LEFT JOIN hidden_sessions h ON h.session_id = s.id
            WHERE \(condition) ORDER BY s.start DESC
            """, args).map {
            SessionRecord(id: $0.int64(0), start: Date(timeIntervalSince1970: $0.double(1)),
                          end: $0.isNull(2) ? nil : Date(timeIntervalSince1970: $0.double(2)),
                          task: $0.text(3), profile: $0.text(4), outcome: $0.text(5), note: $0.text(6),
                          nudges: $0.int(7), blocks: $0.int(8),
                          review: $0.isNull(9) ? nil : try? JSONDecoder().decode(SessionReview.self, from: Data($0.text(9).utf8)),
                          hidden: !$0.isNull(10))
        }
    }

    /// Takes a session off the Recent sessions list, or puts it back.
    func setHidden(_ hidden: Bool, session id: Int64) {
        run(hidden ? "INSERT OR IGNORE INTO hidden_sessions (session_id) VALUES (?)" : "DELETE FROM hidden_sessions WHERE session_id = ?", [id])
    }

    func saveReview(_ review: SessionReview, for sessionID: Int64) {
        guard let data = try? JSONEncoder().encode(review) else { return }
        run("INSERT OR REPLACE INTO session_reviews (session_id, json, created) VALUES (?,?,?)",
            [sessionID, String(decoding: data, as: UTF8.self), Date()])
    }

    // MARK: AI reports

    func report(_ period: String, kind: String) -> (text: String, created: Date)? {
        rows("SELECT text, created FROM reports WHERE period = ? AND kind = ?", [period, kind]).first.map {
            ($0.text(0), Date(timeIntervalSince1970: $0.double(1)))
        }
    }

    func saveReport(_ period: String, kind: String, text: String) {
        run("INSERT OR REPLACE INTO reports (period, kind, text, created) VALUES (?,?,?,?)", [period, kind, text, Date()])
    }

    func deleteAllData() {
        for table in ["activity", "labels", "sessions", "session_reviews", "hidden_sessions", "reports"] { run("DELETE FROM \(table)") }
        run("VACUUM")
    }

    // MARK: SQLite plumbing

    struct Row {
        let values: [Any?]
        func double(_ i: Int) -> Double { values[i] as? Double ?? Double(values[i] as? Int64 ?? 0) }
        func int64(_ i: Int) -> Int64 { values[i] as? Int64 ?? Int64(values[i] as? Double ?? 0) }
        func int(_ i: Int) -> Int { Int(int64(i)) }
        func text(_ i: Int) -> String { values[i] as? String ?? "" }
        func isNull(_ i: Int) -> Bool { values[i] == nil }
    }

    func run(_ sql: String, _ args: [Any?] = []) {
        guard let statement = prepare(sql, args) else { return }
        defer { sqlite3_finalize(statement) }
        let result = sqlite3_step(statement)
        if result != SQLITE_DONE && result != SQLITE_ROW { logLine("SQL error: \(String(cString: sqlite3_errmsg(db)))") }
    }

    func rows(_ sql: String, _ args: [Any?] = []) -> [Row] {
        guard let statement = prepare(sql, args) else { return [] }
        defer { sqlite3_finalize(statement) }
        var rows: [Row] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            rows.append(Row(values: (0..<sqlite3_column_count(statement)).map { i -> Any? in
                switch sqlite3_column_type(statement, i) {
                case SQLITE_INTEGER: return sqlite3_column_int64(statement, i)
                case SQLITE_FLOAT: return sqlite3_column_double(statement, i)
                case SQLITE_TEXT: return String(cString: sqlite3_column_text(statement, i))
                default: return nil
                }
            }))
        }
        return rows
    }

    private func prepare(_ sql: String, _ args: [Any?]) -> OpaquePointer? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            logLine("SQL error: \(String(cString: sqlite3_errmsg(db))) in \(sql.prefix(80))")
            return nil
        }
        for (offset, arg) in args.enumerated() {
            let index = Int32(offset + 1)
            switch arg {
            case let value as Int: sqlite3_bind_int64(statement, index, Int64(value))
            case let value as Int64: sqlite3_bind_int64(statement, index, value)
            case let value as Double: sqlite3_bind_double(statement, index, value)
            case let value as Bool: sqlite3_bind_int64(statement, index, value ? 1 : 0)
            case let value as Date: sqlite3_bind_double(statement, index, value.timeIntervalSince1970)
            case let value as String: sqlite3_bind_text(statement, index, value, -1, transient)
            default: sqlite3_bind_null(statement, index)
            }
        }
        return statement
    }
}

struct KnownItem: Identifiable, Hashable {
    let key: String
    let app: String
    let domain: String
    let bundle: String
    let category: String
    let seconds: Double
    var id: String { key }
    var label: String { domain.isEmpty ? app : domain }
}

struct SessionRecord: Identifiable, Hashable {
    let id: Int64
    let start: Date
    let end: Date?
    let task: String
    let profile: String
    let outcome: String
    let note: String
    let nudges: Int
    let blocks: Int
    /// How the session went, once it has ended and been reviewed.
    var review: SessionReview?
    /// Taken off the Recent sessions list.
    var hidden = false
}
