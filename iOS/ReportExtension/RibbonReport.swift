import DeviceActivity
import ExtensionKit
import SwiftUI

/// Draws Today and This week from your Screen Time. iOS runs this sealed off: it can show what it reads, but it
/// can't send it anywhere or save it where the rest of Ribbon could read it.
@main
struct RibbonReport: DeviceActivityReportExtension {
    var body: some DeviceActivityReportScene {
        TodayScene { TodayUsageView(usage: $0) }
        WeekScene { WeekUsageView(week: $0) }
    }
}

struct TodayScene: DeviceActivityReportScene {
    let context: DeviceActivityReport.Context = .today
    let content: (DayUsage) -> TodayUsageView

    func makeConfiguration(representing data: DeviceActivityResults<DeviceActivityData>) async -> DayUsage {
        await DayUsage.read(data).last ?? DayUsage(day: Calendar.current.startOfDay(for: Date()))
    }
}

struct WeekScene: DeviceActivityReportScene {
    let context: DeviceActivityReport.Context = .week
    let content: (WeekUsage) -> WeekUsageView

    func makeConfiguration(representing data: DeviceActivityResults<DeviceActivityData>) async -> WeekUsage {
        let calendar = Calendar.current
        let days = await DayUsage.read(data)
        let start = days.first.map { calendar.weekStart(for: $0.day) } ?? calendar.weekStart(for: Date())
        let week = (0..<7).map { offset -> DayUsage in
            let day = calendar.date(byAdding: .day, value: offset, to: start)!
            return days.first { calendar.isDate($0.day, inSameDayAs: day) } ?? DayUsage(day: day)
        }
        return WeekUsage(start: start, days: week)
    }
}
