import Foundation

struct Segment: Hashable {
    let id: Int64
    let start: Date
    let end: Date
    let app: String
    let bundle: String
    let title: String
    let domain: String
    let category: String

    var duration: TimeInterval { end.timeIntervalSince(start) }
    /// Websites are named by domain, everything else by app.
    var label: String { domain.isEmpty ? app : domain }
}

struct ScoreDetail: Identifiable, Hashable {
    let label: String
    let value: String
    var note = ""
    var id: String { label }
}

struct Score {
    let value: Int?
    let caption: String
    let details: [ScoreDetail]
}

struct ItemTotal: Identifiable, Hashable {
    let label: String
    let app: String
    let bundle: String
    let domain: String
    let category: String
    let seconds: TimeInterval
    var id: String { label }
}

struct TimelineBlock: Identifiable, Hashable {
    let id: Int
    let start: Date
    let end: Date
    let category: String
    let items: [ItemTotal]
}

struct DayReport {
    let day: Date
    let segments: [Segment]
    let total: TimeInterval
    let byKind: [Productivity: TimeInterval]
    let byCategory: [(id: String, seconds: TimeInterval)]
    let items: [ItemTotal]
    let blocks: [TimelineBlock]
    let focusBlocks: [DateInterval]
    let breaks: [DateInterval]
    let switches: Int
    let focusTime: TimeInterval
    let breakTime: TimeInterval
    let meetingTime: TimeInterval
    let span: DateInterval?
    let productivity: Score
    let focus: Score
    let breakScore: Score

    var switchesPerHour: Double { total > 0 ? Double(switches) / (total / 3600) : 0 }
}

struct WeekReport {
    let start: Date
    let days: [DayReport]
    let total: TimeInterval
    let byKind: [Productivity: TimeInterval]
    let byCategory: [(id: String, seconds: TimeInterval)]
    let items: [ItemTotal]
    let focusTime: TimeInterval

    var averageProductivity: Int? { average(days.compactMap(\.productivity.value)) }
    var averageFocus: Int? { average(days.compactMap(\.focus.value)) }

    private func average(_ values: [Int]) -> Int? {
        values.isEmpty ? nil : Int((Double(values.reduce(0, +)) / Double(values.count)).rounded())
    }
}

enum Analytics {
    /// Shorter than this, a day has too little to score.
    static let minimumToScore: TimeInterval = 10 * 60
    /// A focus block survives interruptions up to this long.
    static let interruptionTolerance: TimeInterval = 3 * 60
    static let minimumFocusBlock: TimeInterval = 20 * 60
    /// Away for at least this long is a break; longer than the cap is the end of a work period.
    static let minimumBreak: TimeInterval = 5 * 60
    static let maximumBreak: TimeInterval = 3 * 3600

    static func day(_ day: Date, segments: [Segment], rules: CategoryRules, focusGoal: TimeInterval) -> DayReport {
        let segments = segments.filter { $0.duration > 0 }.sorted { $0.start < $1.start }
        let total = segments.reduce(0) { $0 + $1.duration }

        var byKind: [Productivity: TimeInterval] = [:]
        var categoryTotals: [String: TimeInterval] = [:]
        for segment in segments {
            byKind[rules.kind(segment.category), default: 0] += segment.duration
            categoryTotals[segment.category, default: 0] += segment.duration
        }
        let byCategory = categoryTotals.sorted { $0.value > $1.value }.map { (id: $0.key, seconds: $0.value) }

        let items = itemTotals(segments)
        let focusBlocks = findFocusBlocks(segments, rules: rules)
        let breaks = findBreaks(segments)
        let switches = countSwitches(segments)
        let focusTime = focusBlocks.reduce(0) { $0 + $1.duration }
        let breakTime = breaks.reduce(0) { $0 + $1.duration }
        let span = segments.first.map { DateInterval(start: $0.start, end: max($0.start, segments.map(\.end).max()!)) }

        let report = (total: total, byKind: byKind, focusBlocks: focusBlocks, breaks: breaks, switches: switches,
                      focusTime: focusTime, breakTime: breakTime, span: span)
        return DayReport(
            day: day, segments: segments, total: total, byKind: byKind, byCategory: byCategory, items: items,
            blocks: timelineBlocks(segments), focusBlocks: focusBlocks, breaks: breaks, switches: switches,
            focusTime: focusTime, breakTime: breakTime, meetingTime: categoryTotals["meetings"] ?? 0, span: span,
            productivity: productivityScore(total: total, byKind: byKind),
            focus: focusScore(report.total, focusBlocks: focusBlocks, focusTime: focusTime, switches: switches, goal: focusGoal),
            breakScore: breakScore(span: span, segments: segments, breaks: breaks, breakTime: breakTime))
    }

    static func week(start: Date, days: [DayReport]) -> WeekReport {
        var byKind: [Productivity: TimeInterval] = [:]
        var categories: [String: TimeInterval] = [:]
        for day in days {
            for (kind, seconds) in day.byKind { byKind[kind, default: 0] += seconds }
            for entry in day.byCategory { categories[entry.id, default: 0] += entry.seconds }
        }
        return WeekReport(start: start, days: days, total: days.reduce(0) { $0 + $1.total }, byKind: byKind,
                          byCategory: categories.sorted { $0.value > $1.value }.map { (id: $0.key, seconds: $0.value) },
                          items: itemTotals(days.flatMap(\.segments)), focusTime: days.reduce(0) { $0 + $1.focusTime })
    }

    // MARK: Pieces

    static func itemTotals(_ segments: [Segment]) -> [ItemTotal] {
        var groups: [String: [Segment]] = [:]
        for segment in segments { groups[segment.label, default: []].append(segment) }
        return groups.map { label, group in
            var byCategory: [String: TimeInterval] = [:]
            for segment in group { byCategory[segment.category, default: 0] += segment.duration }
            let first = group[0]
            return ItemTotal(label: label, app: first.app, bundle: first.bundle, domain: first.domain,
                             category: byCategory.max { $0.value < $1.value }!.key,
                             seconds: group.reduce(0) { $0 + $1.duration })
        }
        .sorted { $0.seconds > $1.seconds }
    }

    /// Runs of time in one category, ignoring blips, for drawing the day.
    static func timelineBlocks(_ segments: [Segment]) -> [TimelineBlock] {
        var runs: [(start: Date, end: Date, category: String, segments: [Segment])] = []
        func merge(_ segment: Segment) {
            if let last = runs.last, last.category == segment.category, segment.start.timeIntervalSince(last.end) < 120 {
                runs[runs.count - 1].end = max(last.end, segment.end)
                runs[runs.count - 1].segments.append(segment)
            } else {
                runs.append((segment.start, segment.end, segment.category, [segment]))
            }
        }
        segments.forEach(merge)
        // Drop blips under 30 seconds, then merge what touches again.
        let kept = runs.filter { $0.end.timeIntervalSince($0.start) >= 30 }
        runs = []
        for run in kept {
            if let last = runs.last, last.category == run.category, run.start.timeIntervalSince(last.end) < 300 {
                runs[runs.count - 1].end = run.end
                runs[runs.count - 1].segments += run.segments
            } else {
                runs.append(run)
            }
        }
        return runs.enumerated().map { index, run in
            TimelineBlock(id: index, start: run.start, end: run.end, category: run.category,
                          items: Array(itemTotals(run.segments).prefix(6)))
        }
    }

    static func findFocusBlocks(_ segments: [Segment], rules: CategoryRules) -> [DateInterval] {
        var blocks: [DateInterval] = []
        var blockStart: Date?
        var lastFocusEnd = Date.distantPast
        func close() {
            if let start = blockStart, lastFocusEnd.timeIntervalSince(start) >= minimumFocusBlock {
                blocks.append(DateInterval(start: start, end: lastFocusEnd))
            }
            blockStart = nil
        }
        for segment in segments {
            let isFocus = rules.isFocus(segment.category)
            if blockStart != nil {
                if isFocus {
                    if segment.start.timeIntervalSince(lastFocusEnd) <= interruptionTolerance {
                        lastFocusEnd = max(lastFocusEnd, segment.end)
                        continue
                    }
                    close()
                } else {
                    if segment.end.timeIntervalSince(lastFocusEnd) > interruptionTolerance { close() }
                    continue
                }
            }
            if isFocus {
                blockStart = segment.start
                lastFocusEnd = segment.end
            }
        }
        close()
        return blocks
    }

    static func findBreaks(_ segments: [Segment]) -> [DateInterval] {
        var breaks: [DateInterval] = []
        var lastEnd: Date?
        for segment in segments {
            if let lastEnd {
                let gap = segment.start.timeIntervalSince(lastEnd)
                if gap >= minimumBreak && gap <= maximumBreak { breaks.append(DateInterval(start: lastEnd, end: segment.start)) }
            }
            lastEnd = max(lastEnd ?? segment.end, segment.end)
        }
        return breaks
    }

    /// A move to another app or website only counts once you've stayed there this long.
    static let minimumStay: TimeInterval = 10
    static let ownBundle = Bundle.main.bundleIdentifier ?? "com.jeremiahlena.focusorb"

    /// Moves to a different app or website where you then stay at least `minimumStay`. Back-to-back rows in the
    /// same place are one stay (a new window title starts a new row). Ribbon's own windows aren't a place, and a
    /// browser row without an address (the browser didn't answer for a moment) is the site it showed just before.
    static func countSwitches(_ segments: [Segment]) -> Int {
        var stays: [(place: String, seconds: TimeInterval)] = []
        var lastSite: [String: (domain: String, end: Date)] = [:]
        for segment in segments where segment.bundle != ownBundle {
            var place = segment.label
            if !segment.domain.isEmpty {
                lastSite[segment.bundle] = (segment.domain, segment.end)
            } else if let site = lastSite[segment.bundle], segment.start.timeIntervalSince(site.end) < 60 {
                place = site.domain
                lastSite[segment.bundle] = (site.domain, segment.end)
            }
            if stays.last?.place == place {
                stays[stays.count - 1].seconds += segment.duration
            } else {
                stays.append((place, segment.duration))
            }
        }
        var switches = 0
        var previous: String?
        for stay in stays where stay.seconds >= minimumStay {
            if let previous, previous != stay.place { switches += 1 }
            previous = stay.place
        }
        return switches
    }

    // MARK: Scores

    static func productivityScore(total: TimeInterval, byKind: [Productivity: TimeInterval]) -> Score {
        let productive = byKind[.productive] ?? 0, neutral = byKind[.neutral] ?? 0, distracting = byKind[.distracting] ?? 0
        let details = [
            ScoreDetail(label: "Productive", value: Format.duration(productive), note: "counts in full"),
            ScoreDetail(label: "Neutral", value: Format.duration(neutral), note: "counts half"),
            ScoreDetail(label: "Distracting", value: Format.duration(distracting), note: "counts zero"),
        ]
        guard total >= minimumToScore else { return Score(value: nil, caption: "Not enough tracked yet", details: details) }
        let value = Int((100 * (productive + 0.5 * neutral) / total).rounded())
        return Score(value: value, caption: "\(Int((100 * productive / total).rounded()))% of your time was productive", details: details)
    }

    static func focusScore(_ total: TimeInterval, focusBlocks: [DateInterval], focusTime: TimeInterval,
                           switches: Int, goal: TimeInterval) -> Score {
        let perHour = total > 0 ? Double(switches) / (total / 3600) : 0
        let average = focusBlocks.isEmpty ? 0 : focusTime / Double(focusBlocks.count)
        let goalPart = min(1, focusTime / max(goal, 1))
        let lengthPart = min(1, average / (50 * 60))
        let switchPart = min(1, max(0, (60 - perHour) / 50))
        let details = [
            ScoreDetail(label: "Focus time", value: "\(Format.duration(focusTime)) of \(Format.duration(goal))", note: "45% of the score"),
            ScoreDetail(label: "Average focus block", value: focusBlocks.isEmpty ? "None yet" : Format.duration(average), note: "30%, full marks at 50 min"),
            ScoreDetail(label: "Context switches", value: "\(Int(perHour.rounded())) per hour", note: "25%, full marks at 10 or fewer"),
        ]
        guard total >= minimumToScore else { return Score(value: nil, caption: "Not enough tracked yet", details: details) }
        let value = Int((100 * (0.45 * goalPart + 0.3 * lengthPart + 0.25 * switchPart)).rounded())
        let caption = focusBlocks.isEmpty ? "No 20-minute focus block yet"
            : "\(focusBlocks.count) focus block\(focusBlocks.count == 1 ? "" : "s"), \(Format.duration(focusTime)) in all"
        return Score(value: value, caption: caption, details: details)
    }

    static func breakScore(span: DateInterval?, segments: [Segment], breaks: [DateInterval], breakTime: TimeInterval) -> Score {
        // The longest stretch of work with no break in it.
        var longest: TimeInterval = 0
        var stretchStart = segments.first?.start
        var lastEnd = segments.first?.start
        for segment in segments {
            if let last = lastEnd, segment.start.timeIntervalSince(last) >= minimumBreak { stretchStart = segment.start }
            if let start = stretchStart { longest = max(longest, segment.end.timeIntervalSince(start)) }
            lastEnd = max(lastEnd ?? segment.end, segment.end)
        }
        let ratio = (span?.duration ?? 0) > 0 ? breakTime / span!.duration : 0
        let details = [
            ScoreDetail(label: "Break time", value: "\(Format.duration(breakTime)) in \(breaks.count) break\(breaks.count == 1 ? "" : "s")"),
            ScoreDetail(label: "Share of your day", value: "\(Int((ratio * 100).rounded()))%", note: "10–25% is ideal"),
            ScoreDetail(label: "Longest stretch without one", value: Format.duration(longest)),
        ]
        guard let span, span.duration >= 2 * 3600 else {
            return Score(value: nil, caption: "Scored after two hours", details: details)
        }
        let value: Int
        switch ratio {
        case ..<0.10: value = Int((100 * ratio / 0.10).rounded())
        case ...0.25: value = 100
        default: value = max(0, Int((100 - (ratio - 0.25) * 250).rounded()))
        }
        let caption = ratio < 0.10 ? "Take more breaks" : ratio <= 0.25 ? "Well rested" : "Lots of time away"
        return Score(value: value, caption: caption, details: details)
    }
}

enum Format {
    static func duration(_ seconds: TimeInterval) -> String {
        if seconds > 0 && seconds < 60 { return "<1m" }
        let minutes = Int((seconds / 60).rounded())
        if minutes < 60 { return "\(minutes)m" }
        return minutes % 60 == 0 ? "\(minutes / 60)h" : "\(minutes / 60)h \(minutes % 60)m"
    }

    static func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    static func dayKey(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }

    static func day(fromKey key: String) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return Calendar.current.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }
}
