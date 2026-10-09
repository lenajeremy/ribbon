import Foundation

/// Every so often (30 minutes by default), looks at today so far and the last stretch, and sends a notification.
/// A nudge when most of the stretch went to distractions, or the day's productivity score is under 80 and you're
/// not working right now. Encouragement otherwise, at most once an hour, including when a slow day is turning
/// around. It stays quiet during focus sessions (the orb watches those), while tracking is paused or you're away,
/// and until there's enough of the day to judge.
@MainActor final class CheckInCoach {
    enum Kind: String { case nudge, encourage }

    enum Decision: Equatable {
        /// More than half the stretch went to distracting apps and sites.
        case distracted(percent: Int)
        /// The day's score is low and the stretch wasn't mostly productive either.
        case lowScore(Int)
        /// The day's score is low, but the stretch was mostly productive.
        case turningAround(score: Int)
        case onTrack

        var kind: Kind {
            switch self {
            case .distracted, .lowScore: .nudge
            case .turningAround, .onTrack: .encourage
            }
        }

        func reason(minutes: Int) -> String {
            switch self {
            case .distracted(let percent): "\(percent)% of the last \(minutes) minutes went to distracting apps and sites"
            case .lowScore(let score): "today's productivity score is \(score), and the last \(minutes) minutes weren't mostly productive"
            case .turningAround(let score): "today's productivity score is only \(score), but the last \(minutes) minutes were mostly productive: they're turning the day around"
            case .onTrack: "the day is going well"
            }
        }
    }

    static let scoreToBeat = 80
    static let minimumDay: TimeInterval = 15 * 60
    static let encourageEvery: TimeInterval = 3600

    private let store: Store
    private let reports: Reports
    private let assistant: Assistant
    private let tracker: ActivityTracker
    private let settings: Settings
    private let isFocusing: () -> Bool
    private var lastCheck = Date()
    private var lastEncouragement = Date.distantPast

    init(store: Store, reports: Reports, assistant: Assistant, tracker: ActivityTracker, settings: Settings,
         isFocusing: @escaping () -> Bool) {
        self.store = store
        self.reports = reports
        self.assistant = assistant
        self.tracker = tracker
        self.settings = settings
        self.isFocusing = isFocusing
    }

    func start() {
        let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.tick() } }
        RunLoop.main.add(timer, forMode: .common)
    }

    private func tick() {
        let now = Date()
        let window = TimeInterval(settings.checkInMinutes * 60)
        guard settings.checkIns, now.timeIntervalSince(lastCheck) >= window else { return }
        // A full stretch after a focus session ends, not straight away.
        if isFocusing() { lastCheck = now; return }
        guard !tracker.isPaused, !tracker.isAway else { return }
        let today = reports.day(now)
        let recent = Self.recent(store, now: now, window: window)
        guard let decision = Self.decide(today: today, recent: recent, window: window, rules: reports.rules) else { return }
        lastCheck = now
        if decision.kind == .encourage {
            guard now.timeIntervalSince(lastEncouragement) >= Self.encourageEvery else { return }
            lastEncouragement = now
        }
        let facts = facts(decision, today: today, recent: recent, window: window, now: now)
        Task {
            var message = Self.fallback(decision, today: today, recent: recent, window: window, rules: reports.rules)
            if assistant.enabled {
                do { message = try await assistant.checkIn(facts) } catch { logLine("Check-in AI failed: \(error.localizedDescription)") }
            }
            Notifier.post(title: message.title, body: message.body)
            logLine("Check-in (\(decision.kind.rawValue), \(decision.reason(minutes: Int(window / 60)))): \(message.body)")
        }
    }

    /// The last stretch of activity, leaving out time in Ribbon itself.
    static func recent(_ store: Store, now: Date, window: TimeInterval) -> [Segment] {
        store.segments(from: now.addingTimeInterval(-window), to: now).filter { $0.bundle != Analytics.ownBundle }
    }

    /// Nudge or encourage, or nil to stay quiet: too little of the day tracked, or away for most of the stretch.
    static func decide(today: DayReport, recent: [Segment], window: TimeInterval, rules: CategoryRules) -> Decision? {
        let tracked = recent.reduce(0) { $0 + $1.duration }
        guard today.total >= minimumDay, tracked >= window / 2 else { return nil }
        func share(_ kind: Productivity) -> Double {
            recent.filter { rules.kind($0.category) == kind }.reduce(0) { $0 + $1.duration } / tracked
        }
        let distracting = share(.distracting)
        if distracting > 0.5 { return .distracted(percent: Int((distracting * 100).rounded())) }
        if let score = today.productivity.value, score < scoreToBeat {
            return share(.productive) >= 0.5 ? .turningAround(score: score) : .lowScore(score)
        }
        return .onTrack
    }

    /// The message when the AI is off or doesn't answer.
    static func fallback(_ decision: Decision, today: DayReport, recent: [Segment], window: TimeInterval,
                         rules: CategoryRules) -> (title: String, body: String) {
        let items = Analytics.itemTotals(recent)
        let minutes = Int(window / 60)
        let productive = recent.filter { rules.kind($0.category) == .productive }.reduce(0) { $0 + $1.duration }
        let topProductive = items.first { rules.kind($0.category) == .productive }
        let worked = "\(Format.duration(productive)) of productive time in the last \(minutes) minutes"
            + (topProductive.map { ", mostly \($0.label)" } ?? "")
        switch decision {
        case .distracted:
            let top = items.first { rules.kind($0.category) == .distracting }
            return ("Time to refocus", "\(Format.duration(top?.seconds ?? 0)) on \(top?.label ?? "distractions") in the last \(minutes) minutes. "
                    + "Close it and give your next task 25 focused minutes.")
        case .lowScore(let score):
            return ("Time to refocus", "Today's productivity score is \(score). Pick one task and give it 25 focused minutes.")
        case .turningAround:
            return ("You're turning it around", "\(worked). Keep going.")
        case .onTrack:
            return ("Keep it going", "\(worked). Nice work.")
        }
    }

    func facts(_ decision: Decision, today: DayReport, recent: [Segment], window: TimeInterval, now: Date) -> [String: Any] {
        func minutes(_ seconds: TimeInterval) -> Int { Int((seconds / 60).rounded()) }
        func top(_ items: [ItemTotal]) -> [[String: Any]] {
            items.prefix(5).map { ["name": $0.label, "minutes": minutes($0.seconds), "kind": reports.rules.kind($0.category).rawValue] }
        }
        let week = store.sessions(from: Reports.weekStart(for: now), to: now)
        var goals: [String] = []
        for session in week.reversed() where !session.task.isEmpty && !goals.contains(session.task) && goals.count < 5 {
            goals.append(session.task)
        }
        let recentDistracting = recent.filter { reports.rules.kind($0.category) == .distracting }.reduce(0) { $0 + $1.duration }
        let recentTracked = recent.reduce(0) { $0 + $1.duration }
        return [
            "kind": decision.kind.rawValue,
            "why": decision.reason(minutes: Int(window / 60)),
            "time_now": Format.time(now),
            "today": [
                "tracked_minutes": minutes(today.total),
                "productivity_score": today.productivity.value ?? 0,
                "productive_minutes": minutes(today.byKind[.productive] ?? 0),
                "distracting_minutes": minutes(today.byKind[.distracting] ?? 0),
                "focus_minutes": minutes(today.focusTime),
                "focus_goal_minutes": minutes(settings.focusGoal),
                "top": top(today.items.filter { $0.bundle != Analytics.ownBundle }),
            ],
            "last_stretch": [
                "minutes": Int(window / 60),
                "tracked_minutes": minutes(recentTracked),
                "distracting_percent": recentTracked > 0 ? Int((recentDistracting / recentTracked * 100).rounded()) : 0,
                "top": top(Analytics.itemTotals(recent)),
                "right_now": recent.last?.label ?? "",
            ],
            "working_toward": goals,
        ]
    }
}
