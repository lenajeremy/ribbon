import AppKit
import ServiceManagement

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

    /// This schedule's window at `date`, if one is running then with at least a minute left.
    func window(at date: Date, calendar: Calendar = .current) -> ScheduledWindow? {
        guard enabled, end > start, days.contains(calendar.component(.weekday, from: date)) else { return nil }
        let midnight = calendar.startOfDay(for: date)
        let from = midnight.addingTimeInterval(TimeInterval(start * 60)), to = midnight.addingTimeInterval(TimeInterval(end * 60))
        guard date >= from, to.timeIntervalSince(date) >= 60 else { return nil }
        return ScheduledWindow(schedule: self, key: "\(id)|\(Format.dayKey(date))", start: from, end: to)
    }

    /// "Weekdays", "Every day", "Weekends" or "Mon, Wed, Fri".
    var daysText: String {
        if days.count == 7 { return "Every day" }
        if days == Self.weekdays { return "Weekdays" }
        if days == [1, 7] { return "Weekends" }
        let names = Calendar.current.shortWeekdaySymbols
        return [2, 3, 4, 5, 6, 7, 1].filter(days.contains).map { names[$0 - 1] }.joined(separator: ", ")
    }

    var timesText: String { "\(Self.clock(start))–\(Self.clock(end))" }

    static func clock(_ minutes: Int) -> String {
        let date = Calendar.current.startOfDay(for: Date()).addingTimeInterval(TimeInterval(minutes * 60))
        return date.formatted(date: .omitted, time: .shortened)
    }
}

/// One day's run of a schedule.
struct ScheduledWindow: Equatable {
    let schedule: FocusSchedule
    /// The schedule and the day, so an emergency pass can end this window and not the next.
    let key: String
    let start: Date
    let end: Date
}

/// Starts scheduled focus sessions when their windows open: checked every 20 seconds, at launch, and when the
/// Mac wakes. A window you ended with the emergency pass doesn't start again that day.
/// While a schedule is on, a launchd agent in the app bundle reopens Ribbon within a minute if it's quit during
/// a window; it reads the coming week's windows from "scheduled-windows", which this keeps up to date.
@MainActor final class FocusScheduler {
    private let store: Store
    private let focus: FocusController
    private(set) var schedules: [FocusSchedule]

    init(store: Store, focus: FocusController) {
        self.store = store
        self.focus = focus
        schedules = store.schedules()
    }

    func start() {
        let timer = Timer(timeInterval: 20, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.check() } }
        RunLoop.main.add(timer, forMode: .common)
        let hourly = Timer(timeInterval: 3600, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.refreshKeepOpen() } }
        RunLoop.main.add(hourly, forMode: .common)
        refreshKeepOpen()
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        }
        check()
    }

    func save(_ schedules: [FocusSchedule]) {
        self.schedules = schedules
        store.saveSchedules(schedules)
        refreshKeepOpen()
        check()
    }

    /// Updates the windows the keep-open agent reads, and registers the agent only while a schedule is on.
    func refreshKeepOpen() {
        writeWindows()
        let agent = SMAppService.agent(plistName: "com.jeremiahlena.focusorb.keepopen.plist")
        let wanted = schedules.contains(where: \.enabled)
        do {
            if wanted && agent.status != .enabled {
                try agent.register()
                logLine("Keep-open agent: \(agent.status == .enabled ? "on" : "waiting for approval in Login Items")")
            } else if !wanted && agent.status == .enabled {
                try agent.unregister()
                logLine("Keep-open agent: off")
            }
        } catch {
            logLine("Keep-open agent: \(error.localizedDescription)")
        }
    }

    /// The next week's windows as "start end" in Unix seconds, one per line, leaving out any the emergency pass ended.
    private func writeWindows() {
        let calendar = Calendar.current, now = Date()
        var lines: [String] = []
        for offset in 0...7 {
            let day = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now))!
            for schedule in schedules where schedule.enabled && schedule.end > schedule.start
                && schedule.days.contains(calendar.component(.weekday, from: day)) {
                let start = day.addingTimeInterval(TimeInterval(schedule.start * 60))
                let end = day.addingTimeInterval(TimeInterval(schedule.end * 60))
                guard end > now, !store.windowWasEnded("\(schedule.id)|\(Format.dayKey(day))") else { continue }
                lines.append("\(Int(start.timeIntervalSince1970)) \(Int(end.timeIntervalSince1970))")
            }
        }
        let text = lines.map { $0 + "\n" }.joined()
        try? text.write(to: Store.folder.appendingPathComponent("scheduled-windows"), atomically: true, encoding: .utf8)
    }

    func check() {
        let now = Date()
        let open = schedules.compactMap { $0.window(at: now) }.filter { !store.windowWasEnded($0.key) }
        guard let window = open.min(by: { $0.start < $1.start }) else { return }
        focus.startScheduled(window)
    }
}
