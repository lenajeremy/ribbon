import Foundation

/// Sample data for looking at the screens in the Simulator, which has no Screen Time. Only used when Ribbon is
/// launched with -RibbonDemo; -RibbonOpen picks a screen to open (session, start, editor, schedule, review, settings),
/// and -RibbonTab a tab (focus, week).
enum Demo {
    static func seed() {
        let now = Date()
        let calendar = Calendar.current
        func at(_ hour: Int, _ minute: Int, daysAgo: Int = 0) -> Date {
            let day = calendar.date(byAdding: .day, value: -daysAgo, to: calendar.startOfDay(for: now))!
            return day.addingTimeInterval(TimeInterval(hour * 3600 + minute * 60))
        }
        var profiles = SessionProfile.defaults()
        profiles.insert(SessionProfile(name: "Coding", emoji: "💻", focusMinutes: 50, breakMinutes: 10, appMode: .allowOnly,
                                       siteMode: .allowOnly,
                                       sites: ["localhost", "github.com", "developer.apple.com", "stackoverflow.com", "chatgpt.com"]),
                        at: 0)
        SharedStore.profiles = profiles
        SharedStore.schedules = [
            FocusSchedule(profileID: profiles[0].id, task: "Ship the iOS release", days: FocusSchedule.weekdays,
                          start: 9 * 60, end: 12 * 60),
            FocusSchedule(profileID: profiles[3].id, task: "Read before bed", days: [1, 2, 3, 4, 5, 6, 7],
                          start: 22 * 60, end: 23 * 60, enabled: false),
        ]
        func record(_ task: String, _ profile: SessionProfile, start: Date, minutes: Int, planned: Int, outcome: String = "completed",
                    note: String = "", blocks: Int = 0, distracting: Int = 0, review: SessionReview?) -> SessionRecord {
            var record = SessionRecord(task: task, profile: profile.name, emoji: profile.emoji, start: start,
                                       plannedMinutes: planned)
            record.end = start.addingTimeInterval(TimeInterval(minutes * 60))
            record.outcome = outcome
            record.note = note
            record.blocks = blocks
            record.distractingMinutes = distracting
            record.review = review
            record.reviewed = true
            return record
        }
        SharedStore.sessions = [
            record("Write the launch post", profiles[1], start: at(16, 10, daysAgo: 2), minutes: 50, planned: 50, blocks: 1,
                   review: SessionReview(score: 96, verdict: "Right on task", summary: "You wrote for the full 50 minutes and only hit the blocked screen once.", tip: "Start the next one the same way.", deductions: [], byAI: true)),
            record("Fix the sync bug", profiles[0], start: at(14, 0, daysAgo: 1), minutes: 31, planned: 50, outcome: "stopped",
                   note: "Team call moved earlier", blocks: 3, distracting: 5,
                   review: SessionReview(score: 52, verdict: "Cut short", summary: "You fixed the bug for 31 of 50 minutes, then stopped for the team call. At least 5 minutes went to distracting apps before that.", tip: "Book the next one after the call, not before it.", deductions: [.init(reason: "Ended early, 19m left", points: 38), .init(reason: "At least 5m in distracting apps", points: 10)], byAI: true)),
            record("Chapter 4 of Deep Work", profiles[4 - 1], start: at(21, 30, daysAgo: 1), minutes: 30, planned: 30,
                   review: SessionReview(score: 100, verdict: "Right on task", summary: "Thirty quiet minutes of reading, nothing blocked, nothing distracting.", tip: "Keep the phone across the room again.", deductions: [], byAI: true)),
            record("Plan the week", profiles[2], start: at(8, 5), minutes: 25, planned: 25, blocks: 2,
                   review: SessionReview(score: 92, verdict: "Right on task", summary: "You planned for the full 25 minutes. You reached for YouTube twice and closed it both times.", tip: "Leave the phone face down for the next one.", deductions: [.init(reason: "At least 2m in distracting apps", points: 8)], byAI: true)),
        ]
        let start = now.addingTimeInterval(-18 * 60 - 24)
        var running = SessionRecord(task: "Ship the iOS release", profile: profiles[0].name, emoji: profiles[0].emoji,
                                    start: start, plannedMinutes: 50)
        running.blocks = 1
        SharedStore.add(running)
        SharedStore.active = ActiveSession(recordID: running.id, profile: profiles[0], task: running.task, started: start,
                                           phase: .focus, phaseStart: start, phaseEnd: start.addingTimeInterval(50 * 60),
                                           pausedAt: nil, pauseBudget: ActiveSession.pauseAllowance, window: nil)
        SharedStore.passes = []
    }

    @MainActor static func open(_ model: AppModel) {
        let arguments = ProcessInfo.processInfo.arguments
        func value(_ flag: String) -> String? {
            arguments.firstIndex(of: flag).flatMap { arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil }
        }
        switch value("-RibbonTab") {
        case "focus": model.tab = .focus
        case "week": model.tab = .week
        default: break
        }
        switch value("-RibbonOpen") {
        case "session": model.showSession = true
        case "start": model.openStart()
        case "editor": model.editing = model.profiles.first
        case "schedule": model.editingSchedule = model.schedules.first
        case "review": model.openRecord = model.sessions.first { $0.distractingMinutes > 0 }
            ?? model.sessions.last { $0.review != nil } ?? model.sessions.last
        case "settings": model.showSettings = true
        case "category": model.openCategory = model.categories.first; model.showSettings = true
        default: break
        }
    }

    // MARK: Sample Screen Time

    /// A made-up day: [hour: [category: minutes]].
    private static let pattern: [Int: [String: Double]] = [
        7: ["Social": 9, "Information & Reading": 6, "Health & Fitness": 4],
        8: ["Productivity & Finance": 12, "Social": 6],
        9: ["Productivity & Finance": 14, "Social": 3],
        10: ["Productivity & Finance": 6, "Creativity": 9],
        11: ["Entertainment": 14, "Social": 6],
        12: ["Social": 18, "Information & Reading": 10, "Entertainment": 8],
        13: ["Productivity & Finance": 10, "Education": 12],
        14: ["Productivity & Finance": 8, "Social": 5],
        15: ["Creativity": 12, "Productivity & Finance": 7],
        16: ["Social": 7, "Productivity & Finance": 9],
        17: ["Entertainment": 11, "Social": 9],
        18: ["Social": 14, "Games": 10],
        19: ["Entertainment": 22, "Social": 8],
        20: ["Entertainment": 18, "Information & Reading": 9],
        21: ["Information & Reading": 20, "Social": 6],
        22: ["Information & Reading": 12],
    ]

    private static let apps: [(String, String, Double, Int)] = [
        ("Instagram", "Social", 0.42, 11), ("YouTube", "Entertainment", 0.7, 6), ("Slack", "Productivity & Finance", 0.45, 9),
        ("Messages", "Social", 0.35, 14), ("Notion", "Productivity & Finance", 0.35, 3), ("Kindle", "Information & Reading", 0.6, 1),
        ("Figma", "Creativity", 1, 2), ("Duolingo", "Education", 1, 1), ("Safari", "Information & Reading", 0.4, 4),
        ("WhatsApp", "Social", 0.23, 7), ("Netflix", "Entertainment", 0.3, 1), ("Gmail", "Productivity & Finance", 0.2, 5),
        ("Clash Royale", "Games", 1, 2), ("Strava", "Health & Fitness", 1, 1),
    ]

    static func usage(for day: Date, scale: Double = 1, lastHour: Int? = nil) -> DayUsage {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: day)
        let isToday = calendar.isDateInToday(day)
        // Screenshots look like mid-afternoon whatever the time.
        let now = isToday ? start.addingTimeInterval(15 * 3600 + 12 * 60) : Date()
        let until = lastHour ?? (isToday ? 15 : 23)
        var usage = DayUsage(day: start, now: now)
        for (hour, categories) in pattern.sorted(by: { $0.key < $1.key }) where hour <= until {
            var minutes = categories.mapValues { $0 * scale }
            if isToday && hour == until {
                let fraction = 12.0 / 60
                minutes = minutes.mapValues { $0 * fraction }
            }
            usage.hours.append(HourUsage(start: start.addingTimeInterval(TimeInterval(hour * 3600)),
                                         byCategory: minutes.mapValues { $0 * 60 }))
        }
        let totals = Dictionary(uniqueKeysWithValues: usage.categories.map { ($0.category.name, $0.seconds) })
        usage.apps = apps.compactMap { name, category, share, pickups in
            guard let seconds = totals[category], seconds * share >= 60 else { return nil }
            return AppUsage(name: name, category: .of(category), seconds: seconds * share, pickups: pickups)
        }
        .sorted { $0.seconds > $1.seconds }
        usage.pickups = usage.apps.reduce(0) { $0 + $1.pickups } + 6
        usage.firstPickup = usage.hours.first.map { $0.start.addingTimeInterval(7 * 60) }
        return usage
    }

    static func week() -> WeekUsage {
        let calendar = Calendar.current
        let start = calendar.weekStart(for: Date())
        let scales = [0.9, 1.15, 0.7, 1.0, 1.3, 0.8, 0.6]
        let days = (0..<7).map { offset -> DayUsage in
            let day = calendar.date(byAdding: .day, value: offset, to: start)!
            if day > Date() { return DayUsage(day: day) }
            return usage(for: day, scale: scales[offset], lastHour: calendar.isDateInToday(day) ? nil : 21 + offset % 2)
        }
        return WeekUsage(start: start, days: days)
    }
}
