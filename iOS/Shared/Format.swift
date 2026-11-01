import Foundation

enum Format {
    /// "3h 20m", "14m", "<1m".
    static func duration(_ seconds: TimeInterval) -> String {
        let minutes = Int((seconds / 60).rounded())
        if minutes < 1 { return seconds > 0 ? "<1m" : "0m" }
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60, rest = minutes % 60
        return rest == 0 ? "\(hours)h" : "\(hours)h \(rest)m"
    }

    /// The time of day in the phone's own style, like "15:04" or "3:04 PM".
    static func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    /// "2026-11-01": one key per calendar day.
    static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// Minutes after midnight as a time of day.
    static func clockTime(_ minutes: Int) -> String {
        time(Calendar.current.startOfDay(for: Date()).addingTimeInterval(TimeInterval(minutes * 60)))
    }
}

/// A countdown: "4:05", or "1:04:05" past an hour.
func clock(_ seconds: TimeInterval) -> String {
    let whole = max(0, Int(seconds.rounded()))
    if whole >= 3600 { return String(format: "%d:%02d:%02d", whole / 3600, whole / 60 % 60, whole % 60) }
    return String(format: "%d:%02d", whole / 60, whole % 60)
}

extension Calendar {
    /// Monday at midnight of the week holding `date`.
    func weekStart(for date: Date) -> Date {
        var monday = Calendar(identifier: .iso8601)
        monday.timeZone = timeZone
        return monday.dateInterval(of: .weekOfYear, for: date)?.start ?? startOfDay(for: date)
    }
}
