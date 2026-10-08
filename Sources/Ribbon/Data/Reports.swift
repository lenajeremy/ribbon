import Foundation

/// Builds day and week reports from the database with the current category rules and goals.
@MainActor final class Reports {
    let store: Store
    let settings: Settings
    var rules: CategoryRules

    init(store: Store, settings: Settings) {
        self.store = store
        self.settings = settings
        rules = store.categoryPrefs()
    }

    func day(_ date: Date) -> DayReport {
        let start = Calendar.current.startOfDay(for: date)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start)!
        return Analytics.day(start, segments: store.segments(from: start, to: min(end, Date())), rules: rules, focusGoal: settings.focusGoal)
    }

    func week(_ start: Date) -> WeekReport {
        let days = (0..<7).map { Calendar.current.date(byAdding: .day, value: $0, to: start)! }
            .filter { $0 <= Date() }
            .map(day)
        return Analytics.week(start: start, days: days)
    }

    /// Monday of the week containing `date`.
    static func weekStart(for date: Date) -> Date {
        var calendar = Calendar.current
        calendar.firstWeekday = 2
        return calendar.dateInterval(of: .weekOfYear, for: date)!.start
    }

    // MARK: Summaries the AI reads

    func summary(_ report: DayReport) -> [String: Any] {
        let sessions = store.sessions(from: report.day, to: report.day.addingTimeInterval(86400))
        return [
            "date": Format.dayKey(report.day),
            "weekday": report.day.formatted(.dateTime.weekday(.wide)),
            "tracked_minutes": minutes(report.total),
            "productive_minutes": minutes(report.byKind[.productive] ?? 0),
            "neutral_minutes": minutes(report.byKind[.neutral] ?? 0),
            "distracting_minutes": minutes(report.byKind[.distracting] ?? 0),
            "productivity_score": report.productivity.value as Any,
            "focus_score": report.focus.value as Any,
            "break_score": report.breakScore.value as Any,
            "focus_minutes": minutes(report.focusTime),
            "focus_blocks": report.focusBlocks.map { "\(Format.time($0.start))–\(Format.time($0.end))" },
            "breaks": report.breaks.map { "\(Format.time($0.start)) for \(Format.duration($0.duration))" },
            "context_switches_per_hour": Int(report.switchesPerHour.rounded()),
            "meeting_minutes": minutes(report.meetingTime),
            "first_activity": report.span.map { Format.time($0.start) } as Any,
            "last_activity": report.span.map { Format.time($0.end) } as Any,
            "categories": report.byCategory.map { ["category": Categories.by($0.id).name, "minutes": minutes($0.seconds)] },
            "top_apps_and_sites": report.items.prefix(12).map {
                ["name": $0.label, "category": Categories.by($0.category).name, "minutes": minutes($0.seconds)]
            },
            "focus_sessions": sessions.map { ["task": $0.task, "type": $0.profile, "outcome": $0.outcome,
                                              "start": Format.time($0.start), "nudges": $0.nudges, "blocked": $0.blocks] },
        ]
    }

    func compactSummary(_ report: DayReport) -> [String: Any] {
        ["date": Format.dayKey(report.day), "tracked_minutes": minutes(report.total),
         "productive_minutes": minutes(report.byKind[.productive] ?? 0),
         "distracting_minutes": minutes(report.byKind[.distracting] ?? 0),
         "focus_minutes": minutes(report.focusTime),
         "productivity_score": report.productivity.value as Any, "focus_score": report.focus.value as Any]
    }

    private func minutes(_ seconds: TimeInterval) -> Int { Int((seconds / 60).rounded()) }
}
