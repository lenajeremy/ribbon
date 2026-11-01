import DeviceActivity
import SwiftUI

/// One day, read like the desktop's Today: the running session, then the day from Screen Time, drawn by the report
/// extension (Ribbon itself never sees those numbers).
struct TodayView: View {
    @Environment(AppModel.self) private var model
    @State private var day = Calendar.current.startOfDay(for: Date())

    private var isToday: Bool { Calendar.current.isDateInToday(day) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    DayStepper(title: isToday ? "Today" : day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()),
                               isCurrent: isToday, back: { move(-1) }, forward: { move(1) },
                               reset: { day = Calendar.current.startOfDay(for: Date()) })
                    Spacer()
                    SettingsButton()
                }
                if isToday, let session = model.active {
                    SessionStrip(session: session) { model.showSession = true }
                }
                if !model.authorized { PermissionCard() }
            }
            .padding(.horizontal, 20)
            .padding(.top, 6)
            .padding(.bottom, 14)

            if model.demo {
                TodayUsageView(usage: Demo.usage(for: day))
            } else if model.authorized {
                DeviceActivityReport(.today, filter: filter)
            } else {
                Spacer()
            }
        }
        .background(Theme.page)
    }

    private var filter: DeviceActivityFilter {
        let end = Calendar.current.date(byAdding: .day, value: 1, to: day)!
        return DeviceActivityFilter(segment: .hourly(during: DateInterval(start: day, end: end)),
                                    users: .all, devices: .init([.iPhone]))
    }

    private func move(_ days: Int) {
        let next = Calendar.current.date(byAdding: .day, value: days, to: day)!
        if next <= Date() { day = next }
    }
}

/// The week, read like the day: seven days on one hour axis, then the week's tables.
struct WeekView: View {
    @Environment(AppModel.self) private var model
    @State private var start = Calendar.current.weekStart(for: Date())

    private var isThisWeek: Bool { start == Calendar.current.weekStart(for: Date()) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                DayStepper(title: title, isCurrent: isThisWeek, back: { move(-1) }, forward: { move(1) },
                           reset: { start = Calendar.current.weekStart(for: Date()) })
                Spacer()
                SettingsButton()
            }
            .padding(.horizontal, 20)
            .padding(.top, 6)
            .padding(.bottom, 14)

            if model.demo {
                WeekUsageView(week: Demo.week())
            } else if model.authorized {
                DeviceActivityReport(.week, filter: filter)
            } else {
                PermissionCard().padding(.horizontal, 20)
                Spacer()
            }
        }
        .background(Theme.page)
    }

    private var title: String {
        if isThisWeek { return "This week" }
        let end = Calendar.current.date(byAdding: .day, value: 6, to: start)!
        return "\(start.formatted(.dateTime.month(.abbreviated).day())) to \(end.formatted(.dateTime.month(.abbreviated).day()))"
    }

    private var filter: DeviceActivityFilter {
        let end = Calendar.current.date(byAdding: .day, value: 7, to: start)!
        return DeviceActivityFilter(segment: .hourly(during: DateInterval(start: start, end: end)),
                                    users: .all, devices: .init([.iPhone]))
    }

    private func move(_ weeks: Int) {
        let next = Calendar.current.date(byAdding: .day, value: 7 * weeks, to: start)!
        if next <= Date() { start = next }
    }
}
