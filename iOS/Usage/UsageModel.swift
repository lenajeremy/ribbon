import SwiftUI
import FamilyControls
import ManagedSettings
import DeviceActivity

extension DeviceActivityReport.Context {
    static let today = Self("Today")
    static let week = Self("Week")
}

/// Productive and distracting are the two ends of one scale, as on the desktop.
enum UsageKind: String {
    case productive, neutral, distracting

    var weight: Double {
        switch self {
        case .productive: 1
        case .neutral: 0.5
        case .distracting: 0
        }
    }
}

/// One of Apple's app categories, given a color from the desktop's palette and a place on the productive scale.
struct UsageCategory: Hashable {
    let name: String
    let slot: Int?
    let kind: UsageKind

    var color: Color { Theme.series(slot) }

    /// Apple's categories, matched on their names: Social, Games, Entertainment, Creativity, Productivity & Finance,
    /// Education, Information & Reading, Health & Fitness, and the rest.
    static func of(_ name: String) -> UsageCategory {
        if let yours = YourCategories.shared.byName[name] {
            return UsageCategory(name: name, slot: yours.slot, kind: UsageKind(rawValue: yours.kind) ?? .neutral)
        }
        let lower = name.lowercased()
        let rules: [(String, Int, UsageKind)] = [
            ("productiv", 1, .productive), ("creativ", 2, .productive), ("educat", 3, .productive),
            ("information", 4, .neutral), ("reading", 4, .neutral), ("social", 5, .distracting),
            ("health", 6, .neutral), ("fitness", 6, .neutral), ("game", 7, .distracting), ("entertain", 8, .distracting),
        ]
        if let rule = rules.first(where: { lower.contains($0.0) }) { return UsageCategory(name: name, slot: rule.1, kind: rule.2) }
        return UsageCategory(name: name.isEmpty ? "Other" : name, slot: nil, kind: .neutral)
    }
}

struct CategoryTotal: Identifiable, Hashable {
    let category: UsageCategory
    var seconds: TimeInterval
    var id: String { category.name }
}

struct AppUsage: Identifiable {
    let name: String
    let category: UsageCategory
    var seconds: TimeInterval
    var pickups: Int
    var token: ApplicationToken?
    var id: String { name }
}

/// Your own categories, read from the app group: the apps you put in each move there from Apple's category.
final class YourCategories {
    static let shared = YourCategories()
    let all: [AppCategory]
    let byName: [String: AppCategory]

    private init() {
        all = AppCategory.saved() ?? []
        byName = Dictionary(all.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// The category of yours an app is in, by the app itself or by its Apple category.
    func category(app: ApplicationToken?, appleCategory: ActivityCategoryToken?) -> AppCategory? {
        if let app, let found = all.first(where: { $0.apps.applicationTokens.contains(app) }) { return found }
        if let appleCategory, let found = all.first(where: { $0.apps.categoryTokens.contains(appleCategory) }) { return found }
        return nil
    }
}

/// One hour of the day: how long each category was on screen.
struct HourUsage: Identifiable {
    let start: Date
    var byCategory: [String: TimeInterval]
    var id: Date { start }
    var total: TimeInterval { byCategory.values.reduce(0, +) }
}

/// A day of Screen Time, as the report draws it.
struct DayUsage {
    var day: Date
    var hours: [HourUsage] = []
    var apps: [AppUsage] = []
    var pickups = 0
    var firstPickup: Date?
    /// The present moment, where the orb sits on today's ribbon.
    var now = Date()

    var total: TimeInterval { hours.reduce(0) { $0 + $1.total } }
    var isToday: Bool { Calendar.current.isDateInToday(day) }

    var categories: [CategoryTotal] { Self.totals(hours) }

    static func totals(_ hours: [HourUsage]) -> [CategoryTotal] {
        var sums: [String: TimeInterval] = [:]
        for hour in hours { for (name, seconds) in hour.byCategory { sums[name, default: 0] += seconds } }
        return sums.filter { $0.value >= 30 }
            .map { CategoryTotal(category: .of($0.key), seconds: $0.value) }
            .sorted { $0.seconds > $1.seconds }
    }

    func seconds(_ kind: UsageKind) -> TimeInterval {
        categories.filter { $0.category.kind == kind }.reduce(0) { $0 + $1.seconds }
    }

    /// Out of 100, like the desktop's: productive time counts fully, neutral time half.
    var productivity: Int? {
        guard total >= 60 else { return nil }
        let weighted = categories.reduce(0) { $0 + $1.seconds * $1.category.kind.weight }
        return Int((100 * weighted / total).rounded())
    }

    /// The share of the time that was productive, 0 to 100.
    var productiveShare: Int { Int((100 * seconds(.productive) / max(total, 1)).rounded()) }
}

/// Seven days of Screen Time, Monday first.
struct WeekUsage {
    var start: Date
    var days: [DayUsage]

    var total: TimeInterval { days.reduce(0) { $0 + $1.total } }
    var categories: [CategoryTotal] { DayUsage.totals(days.flatMap(\.hours)) }
    var apps: [AppUsage] { Self.merge(days.flatMap(\.apps)) }
    var activeDays: Int { days.filter { $0.total >= 60 }.count }

    func seconds(_ kind: UsageKind) -> TimeInterval {
        days.reduce(0) { $0 + $1.seconds(kind) }
    }

    static func merge(_ apps: [AppUsage]) -> [AppUsage] {
        var merged: [String: AppUsage] = [:]
        for app in apps {
            if var existing = merged[app.name] {
                existing.seconds += app.seconds
                existing.pickups += app.pickups
                merged[app.name] = existing
            } else {
                merged[app.name] = app
            }
        }
        return merged.values.sorted { $0.seconds > $1.seconds }
    }
}

extension DayUsage {
    /// Reads iOS's hourly Screen Time into days. Only the report extension can do this, and what it reads stays there.
    static func read(_ results: DeviceActivityResults<DeviceActivityData>) async -> [DayUsage] {
        let calendar = Calendar.current
        var days: [Date: DayUsage] = [:]
        var apps: [Date: [String: AppUsage]] = [:]
        for await data in results {
            for await segment in data.activitySegments {
                let start = segment.dateInterval.start
                let day = calendar.startOfDay(for: start)
                var usage = days[day] ?? DayUsage(day: day)
                var hour = HourUsage(start: start, byCategory: [:])
                usage.pickups += segment.totalPickupsWithoutApplicationActivity
                if let first = segment.firstPickup, first < (usage.firstPickup ?? .distantFuture) { usage.firstPickup = first }
                for await category in segment.categories {
                    let appleName = category.category.localizedDisplayName ?? "Other"
                    var inApps: TimeInterval = 0
                    for await app in category.applications {
                        let label = app.application.localizedDisplayName ?? app.application.bundleIdentifier ?? "An app"
                        let name = YourCategories.shared.category(app: app.application.token,
                                                                  appleCategory: category.category.token)?.name ?? appleName
                        hour.byCategory[name, default: 0] += app.totalActivityDuration
                        inApps += app.totalActivityDuration
                        var entry = apps[day]?[label] ?? AppUsage(name: label, category: .of(name), seconds: 0, pickups: 0,
                                                                  token: app.application.token)
                        entry.seconds += app.totalActivityDuration
                        entry.pickups += app.numberOfPickups
                        apps[day, default: [:]][label] = entry
                        usage.pickups += app.numberOfPickups
                    }
                    // Time not in any app, like websites, stays in Apple's category.
                    let rest = category.totalActivityDuration - inApps
                    if rest > 1 { hour.byCategory[appleName, default: 0] += rest }
                }
                // iOS counts overlapping use (a video in picture-in-picture over another app) twice; an hour holds 60 minutes.
                let counted = hour.total
                if counted > 3600 { hour.byCategory = hour.byCategory.mapValues { $0 * 3600 / counted } }
                if hour.total > 0 { usage.hours.append(hour) }
                days[day] = usage
            }
        }
        return days.keys.sorted().map { day in
            var usage = days[day]!
            usage.hours.sort { $0.start < $1.start }
            usage.apps = (apps[day] ?? [:]).values.filter { $0.seconds >= 30 }.sorted { $0.seconds > $1.seconds }
            return usage
        }
    }
}
