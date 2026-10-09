import Foundation

/// How a focus session went: what you said you'd work on, compared with what Ribbon recorded while it ran.
struct SessionReview: Codable, Hashable {
    struct Deduction: Codable, Hashable {
        let reason: String
        let points: Int
    }

    struct Item: Codable, Hashable {
        let name: String
        let minutes: Int
        let onTask: Bool
        let why: String
    }

    /// Out of 100: the share of the session spent on the task.
    let score: Int
    let verdict: String
    let summary: String
    let tip: String
    /// The session's length, less pauses.
    let minutes: Int
    let onTaskMinutes: Int
    let deductions: [Deduction]
    let items: [Item]
}

/// Reviews a focus session when it ends. Every app and website used during the session is judged against what
/// you said you'd work on: by the AI when it's on (the session type's rules are context, not the verdict: a prep site
/// the session forgot to allow still counts), otherwise by the categories and the session's rules. The score
/// is the share of the session spent on the task: time on other things and time away from your Mac (lid closed,
/// screen locked, no activity) come off it. Time you paused the session doesn't count either way. Blocked attempts
/// aren't scored (Ribbon counts them but not what they were, so a session type blocking the task itself would cost
/// points); the AI can mention them.
@MainActor final class SessionReviewer {
    /// A session that just ended, as FocusController hands it over.
    struct Ended {
        let id: Int64
        let task: String
        let profile: SessionProfile
        let outcome: String
        let start: Date
        let end: Date
        let pauses: [DateInterval]
    }

    /// The session's time, with pauses and time in Ribbon itself taken out.
    struct Time {
        let counted: TimeInterval
        let away: TimeInterval
        let segments: [Segment]
    }

    /// Shorter sessions aren't reviewed.
    static let minimumLength: TimeInterval = 5 * 60

    private let store: Store
    private let assistant: Assistant
    private let rules: () -> CategoryRules

    init(store: Store, assistant: Assistant, rules: @escaping () -> CategoryRules) {
        self.store = store
        self.assistant = assistant
        self.rules = rules
    }

    /// Reviews the session, saves the review with it and sends it as a notification.
    @discardableResult func finish(_ session: Ended) async -> SessionReview? {
        guard let review = await review(session) else { return nil }
        store.saveReview(review, for: session.id)
        Notifier.post(title: "Session score: \(review.score)", body: "\(review.verdict). \(review.summary)")
        logLine("Session reviewed: \(review.score)/100, \(review.verdict). " + review.deductions.map { "-\($0.points) \($0.reason)" }.joined(separator: ", "))
        return review
    }

    func review(_ session: Ended) async -> SessionReview? {
        let time = Self.measure(session, segments: store.segments(from: session.start, to: session.end))
        guard time.counted >= Self.minimumLength else { return nil }
        let rules = rules()
        let items = Analytics.itemTotals(time.segments)
        let sessionRules = items.map { Self.rule(for: $0, in: session.profile, rules: rules) }
        let blocked = store.session(session.id)?.blocks ?? 0

        var judged = zip(items, sessionRules).map { item, rule in
            (item: item, onTask: Self.fallbackOnTask(kind: rules.kind(item.category), rule: rule), why: "")
        }
        var words: (summary: String, tip: String)?
        if assistant.enabled {
            do {
                let answer = try await assistant.judgeSession(Self.facts(session, time: time, items: items, rules: sessionRules,
                                                                         categories: rules, blocked: blocked))
                judged = judged.map { entry in
                    guard let verdict = answer.items[entry.item.label] else { return entry }
                    return (entry.item, verdict.onTask, verdict.why)
                }
                words = (answer.summary, answer.tip)
            } catch {
                logLine("Session review AI failed: \(error.localizedDescription)")
            }
        }

        let deductions = Self.deductions(judged.map { ($0.item, $0.onTask) }, away: time.away, counted: time.counted)
        let score = max(0, 100 - deductions.reduce(0) { $0 + $1.points })
        let onTask = judged.filter(\.onTask).reduce(0) { $0 + $1.item.seconds }
        let fallback = Self.fallbackWords(task: session.task, score: score, onTask: onTask, time: time,
                                          offTask: judged.filter { !$0.onTask }.map(\.item))
        return SessionReview(
            score: score, verdict: Self.verdict(score), summary: words?.summary ?? fallback.summary,
            tip: words?.tip ?? fallback.tip, minutes: Self.minutes(time.counted), onTaskMinutes: Self.minutes(onTask),
            deductions: deductions,
            items: judged.map { SessionReview.Item(name: $0.item.label, minutes: Self.minutes($0.item.seconds), onTask: $0.onTask, why: $0.why) })
    }

    // MARK: Measuring

    static func measure(_ session: Ended, segments: [Segment]) -> Time {
        let window = DateInterval(start: session.start, end: max(session.start, session.end))
        let pauses = session.pauses.compactMap { $0.intersection(with: window) }
        var kept: [Segment] = []
        var inRibbon: TimeInterval = 0
        for segment in segments {
            for part in subtract(DateInterval(start: segment.start, end: max(segment.start, segment.end)), pauses) where part.duration > 0 {
                if segment.bundle == Analytics.ownBundle { inRibbon += part.duration; continue }
                kept.append(Segment(id: segment.id, start: part.start, end: part.end, app: segment.app, bundle: segment.bundle,
                                    title: segment.title, domain: segment.domain, category: segment.category))
            }
        }
        let counted = max(0, window.duration - pauses.reduce(0) { $0 + $1.duration } - inRibbon)
        let tracked = kept.reduce(0) { $0 + $1.duration }
        return Time(counted: counted, away: max(0, counted - tracked), segments: kept)
    }

    /// The parts of `interval` outside every one of `holes`.
    static func subtract(_ interval: DateInterval, _ holes: [DateInterval]) -> [DateInterval] {
        var parts = [interval]
        for hole in holes {
            parts = parts.flatMap { part -> [DateInterval] in
                guard let overlap = part.intersection(with: hole), overlap.duration > 0 else { return [part] }
                var pieces: [DateInterval] = []
                if overlap.start > part.start { pieces.append(DateInterval(start: part.start, end: overlap.start)) }
                if overlap.end < part.end { pieces.append(DateInterval(start: overlap.end, end: part.end)) }
                return pieces
            }
        }
        return parts
    }

    /// What the session's own rules say about an app or website: allowed (true), blocked (false) or nothing (nil).
    /// The same rules the blocker enforces.
    static func rule(for item: ItemTotal, in profile: SessionProfile, rules: CategoryRules) -> Bool? {
        let distracting = rules.kind(item.category) == .distracting
        if !item.domain.isEmpty {
            let listed = profile.sites.contains { SiteMatch.matches(item.domain, $0) }
            switch profile.siteMode {
            case .allowOnly: return listed
            case .block: return listed || (profile.blockDistracting && distracting) ? false : nil
            case .off: return profile.blockDistracting && distracting ? false : nil
            }
        }
        guard !Blocker.alwaysAllowed.contains(item.bundle) else { return nil }
        let listed = profile.apps.contains { $0.bundleID == item.bundle }
        let browser = BrowserBridge.isBrowser(item.bundle)
        switch profile.appMode {
        case .allowOnly: return listed
        case .block: return listed || (!browser && profile.blockDistracting && distracting) ? false : nil
        case .off: return !browser && profile.blockDistracting && distracting ? false : nil
        }
    }

    /// Without the AI: productive work counts, distractions don't, and anything else goes by the session's rules.
    static func fallbackOnTask(kind: Productivity, rule: Bool?) -> Bool {
        if rule == true || kind == .productive { return true }
        if kind == .distracting { return false }
        return rule ?? true
    }

    // MARK: Scoring

    static func verdict(_ score: Int) -> String {
        score >= 85 ? "Right on task" : score >= 60 ? "Mostly on task" : score >= 30 ? "Often off task" : "Off task"
    }

    /// Under a minute in seconds, so a small time doesn't read as nothing next to its points.
    static func duration(_ seconds: TimeInterval) -> String {
        seconds < 60 ? "\(max(1, Int(seconds.rounded())))s" : Format.duration(seconds)
    }

    /// Points off: each thing off task for a minute or more, the rest together, and time away.
    static func deductions(_ items: [(item: ItemTotal, onTask: Bool)], away: TimeInterval,
                           counted: TimeInterval) -> [SessionReview.Deduction] {
        func points(_ seconds: TimeInterval) -> Int { counted > 0 ? Int((seconds / counted * 100).rounded()) : 0 }
        var deductions: [SessionReview.Deduction] = []
        var small: [ItemTotal] = []
        for (item, onTask) in items where !onTask {
            if item.seconds >= 60 && points(item.seconds) >= 1 {
                deductions.append(.init(reason: "\(duration(item.seconds)) on \(item.label)", points: points(item.seconds)))
            } else {
                small.append(item)
            }
        }
        let smallTime = small.reduce(0) { $0 + $1.seconds }
        if points(smallTime) >= 1 {
            let what = small.count == 1 ? small[0].label : "other things"
            deductions.append(.init(reason: "\(duration(smallTime)) on \(what)", points: points(smallTime)))
        }
        if points(away) >= 1 { deductions.append(.init(reason: "\(duration(away)) away from your Mac", points: points(away))) }
        return deductions.sorted { $0.points > $1.points }
    }

    /// The summary and tip when the AI is off or doesn't answer.
    static func fallbackWords(task: String, score: Int, onTask: TimeInterval, time: Time,
                              offTask: [ItemTotal]) -> (summary: String, tip: String) {
        var summary = "You spent \(Format.duration(onTask)) of \(Format.duration(time.counted)) on \(task)."
        let top = offTask.max { $0.seconds < $1.seconds }
        if let top, top.seconds >= 60 { summary += " \(Format.duration(top.seconds)) went to \(top.label)." }
        if time.away >= 60 { summary += " You were away from your Mac for \(Format.duration(time.away))." }
        let tip: String
        if time.away >= max(60, top?.seconds ?? 0) {
            tip = "Keep your Mac open and in front of you until the session ends."
        } else if let top, top.seconds >= 60 {
            tip = "Close \(top.label) before your next session starts."
        } else {
            tip = "Start the next session the same way."
        }
        return (summary, tip)
    }

    private static func facts(_ session: Ended, time: Time, items: [ItemTotal], rules: [Bool?], categories: CategoryRules,
                              blocked: Int) -> [String: Any] {
        var titles: [String: [String]] = [:]
        for segment in time.segments where !segment.title.isEmpty {
            var list = titles[segment.label, default: []]
            if !list.contains(segment.title) && list.count < 4 { list.append(segment.title) }
            titles[segment.label] = list
        }
        return [
            "task": session.task,
            "session_type": session.profile.name,
            "session_rules": session.profile.rulesSummary,
            "planned_minutes": session.profile.focusMinutes,
            "minutes": minutes(time.counted),
            "away_minutes": minutes(time.away),
            "blocked_attempts": blocked,
            "ended": session.outcome == "completed" ? "completed" : "stopped early",
            "items": zip(items, rules).map { item, rule in
                [
                    "name": item.label, "app": item.app, "minutes": max(1, minutes(item.seconds)),
                    "category": Categories.by(item.category).name, "kind": categories.kind(item.category).rawValue,
                    "session_rule": rule.map { $0 ? "allowed" : "blocked" } ?? "none",
                    "titles": titles[item.label] ?? [],
                ] as [String: Any]
            },
        ]
    }

    private static func minutes(_ seconds: TimeInterval) -> Int { Int((seconds / 60).rounded()) }
}
