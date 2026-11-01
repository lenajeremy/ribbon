import Foundation
import FamilyControls

enum RuleMode: String, Codable, CaseIterable, Identifiable {
    case off, allowOnly, block
    var id: String { rawValue }
}

/// A kind of focus session: how long it runs and what you can use meanwhile. Apps come from Apple's picker, which
/// hands Ribbon sealed tokens rather than names; websites are typed, like on the desktop.
struct SessionProfile: Codable, Identifiable, Equatable {
    var id = UUID().uuidString
    var name: String
    var emoji: String
    var focusMinutes: Int
    var breakMinutes: Int
    var appMode: RuleMode
    var apps = FamilyActivitySelection(includeEntireCategory: true)
    var siteMode: RuleMode
    var sites: [String]

    var appCount: Int { apps.applicationTokens.count + apps.categoryTokens.count }

    /// "Blocks 4 apps; only github.com, localhost and 2 more."
    var rulesSummary: String {
        var parts: [String] = []
        switch appMode {
        case .allowOnly: parts.append(appCount == 0 ? "Blocks every app" : "Only \(Self.count(apps))")
        case .block: if appCount > 0 { parts.append("Blocks \(Self.count(apps))") }
        case .off: break
        }
        switch siteMode {
        case .allowOnly: parts.append("only " + Self.list(sites))
        case .block: if !sites.isEmpty { parts.append("blocks " + Self.list(sites)) }
        case .off: break
        }
        let text = parts.joined(separator: "; ")
        return text.isEmpty ? "No limits." : text.prefix(1).uppercased() + text.dropFirst() + "."
    }

    static func count(_ selection: FamilyActivitySelection) -> String {
        var parts: [String] = []
        let apps = selection.applicationTokens.count, categories = selection.categoryTokens.count
        if apps > 0 { parts.append("\(apps) app\(apps == 1 ? "" : "s")") }
        if categories > 0 { parts.append("\(categories) categor\(categories == 1 ? "y" : "ies")") }
        return parts.joined(separator: " and ")
    }

    static func list(_ sites: [String]) -> String {
        if sites.isEmpty { return "no websites" }
        if sites.count <= 3 { return ListFormatter.localizedString(byJoining: sites) }
        return sites.prefix(2).joined(separator: ", ") + " and \(sites.count - 2) more"
    }

    static let distractingSites = ["youtube.com", "x.com", "instagram.com", "tiktok.com", "reddit.com", "facebook.com"]

    static func defaults() -> [SessionProfile] {
        [
            SessionProfile(name: "Deep Work", emoji: "🎯", focusMinutes: 50, breakMinutes: 10,
                           appMode: .block, siteMode: .block, sites: distractingSites),
            SessionProfile(name: "Pomodoro", emoji: "🍅", focusMinutes: 25, breakMinutes: 5,
                           appMode: .block, siteMode: .block, sites: distractingSites),
            SessionProfile(name: "Reading", emoji: "📖", focusMinutes: 30, breakMinutes: 5,
                           appMode: .block, siteMode: .block, sites: distractingSites),
        ]
    }
}

enum SiteMatch {
    /// Accepts pasted URLs: "https://www.youtube.com/watch?v=1" → "youtube.com". "*.google.com" keeps its star.
    static func normalize(_ input: String) -> String {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let wildcard = text.hasPrefix("*.")
        if wildcard { text.removeFirst(2) }
        if text.contains("://"), let host = URL(string: text)?.host { text = host }
        text = String(text.split(separator: "/").first ?? "")
        text = String(text.split(separator: ":").first ?? "")
        if text.hasPrefix("www.") { text.removeFirst(4) }
        if text == "localhost" { return text }
        guard text.contains("."), !text.hasPrefix("."), !text.hasSuffix("."), !text.contains(" ") else { return "" }
        return wildcard ? "*." + text : text
    }

    /// The domain as iOS's web filter wants it: no star, which already covers subdomains.
    static func domain(_ site: String) -> String {
        site.hasPrefix("*.") ? String(site.dropFirst(2)) : site
    }
}

/// A focus session that starts by itself: a session type and a task, on some days, between two times.
/// Its rules stay on from the start time to the end time, through its breaks.
struct FocusSchedule: Codable, Identifiable, Hashable {
    var id = UUID().uuidString
    var profileID: String
    var task: String
    /// Calendar weekdays: 1 is Sunday, 2 is Monday, … 7 is Saturday.
    var days: Set<Int>
    /// Minutes after midnight.
    var start: Int
    var end: Int
    var enabled = true

    static let weekdays: Set<Int> = [2, 3, 4, 5, 6]
    /// iOS can't watch a span shorter than this.
    static let shortest = 15

    /// This schedule's window on the day of `date`, if one is open then with at least a minute left.
    func window(at date: Date, calendar: Calendar = .current) -> ScheduledWindow? {
        guard enabled, end > start, days.contains(calendar.component(.weekday, from: date)) else { return nil }
        let midnight = calendar.startOfDay(for: date)
        let from = midnight.addingTimeInterval(TimeInterval(start * 60)), to = midnight.addingTimeInterval(TimeInterval(end * 60))
        guard date >= from, to.timeIntervalSince(date) >= 60 else { return nil }
        return ScheduledWindow(scheduleID: id, key: "\(id)|\(Format.dayKey(date))", start: from, end: to)
    }

    /// "Weekdays", "Every day", "Weekends" or "Mon, Wed, Fri".
    var daysText: String {
        if days.count == 7 { return "Every day" }
        if days == Self.weekdays { return "Weekdays" }
        if days == [1, 7] { return "Weekends" }
        if days.isEmpty { return "No days" }
        let names = Calendar.current.shortWeekdaySymbols
        return [2, 3, 4, 5, 6, 7, 1].filter(days.contains).map { names[$0 - 1] }.joined(separator: ", ")
    }

    var timesText: String { "\(Format.clockTime(start))–\(Format.clockTime(end))" }
}

/// One day's run of a schedule.
struct ScheduledWindow: Codable, Equatable {
    let scheduleID: String
    /// The schedule and the day, so an emergency pass can end this window and not the next.
    let key: String
    let start: Date
    let end: Date
}

enum Phase: String, Codable {
    case focus, rest
}

/// The session running now, saved where Ribbon's extensions can read it. It carries a copy of its session type,
/// so editing that type mid-session doesn't loosen the rules.
struct ActiveSession: Codable, Equatable {
    var recordID: String
    var profile: SessionProfile
    var task: String
    var started: Date
    var phase: Phase
    var phaseStart: Date
    var phaseEnd: Date
    /// Set while a manual session is paused; the clock stands still.
    var pausedAt: Date?
    /// Pause time left in this session, not counting the pause in progress.
    var pauseBudget: TimeInterval
    var window: ScheduledWindow?

    var paused: Bool { pausedAt != nil }
    var isScheduled: Bool { window != nil }

    /// Rules apply while focusing, and through a scheduled window's breaks.
    var enforcing: Bool { isScheduled || (phase == .focus && !paused) }

    func timeLeft(at date: Date) -> TimeInterval { max(0, phaseEnd.timeIntervalSince(pausedAt ?? date)) }

    func pauseLeft(at date: Date) -> TimeInterval {
        max(0, pauseBudget - (pausedAt.map { date.timeIntervalSince($0) } ?? 0))
    }

    var canPause: Bool { !isScheduled && phase == .focus && !paused && pauseBudget >= 1 }

    /// "Focusing", "Paused", "On a break · rules stay on".
    var status: String {
        if paused { return "Paused" }
        if phase == .rest { return isScheduled ? "On a break · rules stay on" : "On a break" }
        return "Focusing"
    }

    static let pauseAllowance: TimeInterval = 5 * 60
}

/// How a focus session went: what you said you'd work on, against what Ribbon could see.
struct SessionReview: Codable, Hashable {
    struct Deduction: Codable, Hashable {
        let reason: String
        let points: Int
    }

    /// Out of 100.
    let score: Int
    let verdict: String
    let summary: String
    let tip: String
    let deductions: [Deduction]
    /// Written by the AI, rather than Ribbon's plain sentences.
    var byAI = false

    static func verdict(_ score: Int) -> String {
        switch score {
        case 90...: "Right on task"
        case 75..<90: "Mostly on task"
        case 50..<75: "Half on task"
        default: "Mostly off task"
        }
    }
}

/// A focus session, running or over.
struct SessionRecord: Codable, Identifiable, Equatable {
    var id = UUID().uuidString
    var task: String
    var profile: String
    var emoji: String
    var start: Date
    var end: Date?
    /// "running", "completed" or "stopped".
    var outcome = "running"
    /// Why it was stopped, in your words.
    var note = ""
    var plannedMinutes: Int
    var pauses: [DateInterval] = []
    /// Times the blocked screen was closed during the session.
    var blocks = 0
    /// Rough minutes in your distracting apps during the session, from iOS's time marks.
    var distractingMinutes = 0
    var windowKey: String?
    var review: SessionReview?
    var reviewed = false
    var hidden = false

    var isScheduled: Bool { windowKey != nil }

    /// The session's length, less pauses and breaks.
    var counted: TimeInterval {
        let finish = end ?? Date()
        let paused = pauses.reduce(0) { $0 + max(0, min($1.end, finish).timeIntervalSince($1.start)) }
        return max(0, finish.timeIntervalSince(start) - paused)
    }
}

/// The one way out of a scheduled session, once a week.
struct EmergencyPass: Codable {
    let date: Date
    let windowKey: String
    let reason: String
}

/// How the AI talks to you, like the orb's tone on the desktop.
enum Tone: String, Codable, CaseIterable, Identifiable {
    case friendly, ruthless
    var id: String { rawValue }
    var label: String { self == .friendly ? "Friendly" : "Ruthless" }
}
