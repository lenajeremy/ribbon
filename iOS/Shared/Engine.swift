import Foundation
import os
import DeviceActivity
import FamilyControls
import ManagedSettings
import UserNotifications

let log = Logger(subsystem: "com.jeremiahlena.ribbon", category: "engine")

/// Runs focus sessions, in the app and in the monitor extension alike. What's running is worked out from what's
/// saved and the clock, so whichever wakes first (the app, or the extension iOS starts at a schedule's times) does the
/// same thing: ends what's over, starts a scheduled window that's open, and sets the blocking to match.
///
/// The rules mirror the desktop: starting is easy; pausing (5 minutes per session) and ending take effort; a scheduled
/// session's rules stay on from its start to its end, breaks included, and only the weekly emergency pass ends it early.
enum Engine {
    static let shields = ManagedSettingsStore(named: ManagedSettingsStore.Name("ribbon.session"))
    private static var applied: String?

    // MARK: Working out what's running

    /// Brings the saved session up to date with the clock and the schedules, saves it, and sets the shields to match.
    @discardableResult
    static func reconcile(now: Date = Date()) -> ActiveSession? {
        let before = SharedStore.active
        var active = before

        if var session = active {
            // A pause runs out by itself.
            if let pausedAt = session.pausedAt, now.timeIntervalSince(pausedAt) >= session.pauseBudget {
                session = resumed(session, at: pausedAt.addingTimeInterval(session.pauseBudget))
            }
            if let window = session.window {
                if SharedStore.windowWasEnded(window.key) {
                    active = nil
                } else if window.end.timeIntervalSince(now) < 30 {
                    finish(session, outcome: "completed", at: window.end)
                    notify("Scheduled focus session finished", "That's \(session.task) done for today.")
                    active = nil
                } else {
                    active = phased(session, at: now)
                }
            } else if session.phase == .focus, !session.paused, session.phaseEnd.timeIntervalSince(now) < 5 {
                finish(session, outcome: "completed", at: session.phaseEnd)
                let breakEnd = session.phaseEnd.addingTimeInterval(TimeInterval(session.profile.breakMinutes * 60))
                if now < breakEnd {
                    session.phase = .rest
                    session.phaseStart = session.phaseEnd
                    session.phaseEnd = breakEnd
                    active = session
                } else {
                    active = nil
                }
            } else if session.phase == .rest, now >= session.phaseEnd {
                active = nil
            } else {
                active = session
            }
        }

        // A scheduled window that's open now takes over from anything else.
        if active?.window == nil, let open = openWindow(at: now) {
            if let manual = active, manual.phase == .focus {
                finish(manual, outcome: "stopped", note: "A scheduled session started", at: now)
            }
            active = startWindow(open.0, schedule: open.1, profile: open.2, now: now)
        }

        if active != before { SharedStore.active = active }
        applyShields(active)
        return active
    }

    /// The earliest schedule window open now that the emergency pass hasn't ended, with its session type.
    static func openWindow(at now: Date) -> (ScheduledWindow, FocusSchedule, SessionProfile)? {
        let profiles = SharedStore.profiles
        return SharedStore.schedules
            .compactMap { schedule -> (ScheduledWindow, FocusSchedule, SessionProfile)? in
                guard let window = schedule.window(at: now), !SharedStore.windowWasEnded(window.key),
                      let profile = profiles.first(where: { $0.id == schedule.profileID }) else { return nil }
                return (window, schedule, profile)
            }
            .min { $0.0.start < $1.0.start }
    }

    private static func startWindow(_ window: ScheduledWindow, schedule: FocusSchedule, profile: SessionProfile,
                                     now: Date) -> ActiveSession {
        // After a restart of the phone, or an update, carry on the session this window already had.
        let earlier = SharedStore.sessions.last { $0.windowKey == window.key }
        let recordID: String
        if let earlier {
            recordID = earlier.id
            SharedStore.update(earlier.id) { $0.outcome = "running"; $0.end = nil }
        } else {
            let record = SessionRecord(task: schedule.task, profile: profile.name, emoji: profile.emoji, start: now,
                                       plannedMinutes: Int(window.end.timeIntervalSince(now) / 60), windowKey: window.key)
            SharedStore.add(record)
            recordID = record.id
            notify("Scheduled focus session started",
                   "\(profile.emoji) \(profile.name): \(schedule.task), until \(Format.time(window.end)).")
        }
        let session = ActiveSession(recordID: recordID, profile: profile, task: schedule.task, started: earlier?.start ?? now,
                                    phase: .focus, phaseStart: now, phaseEnd: window.end, pausedAt: nil, pauseBudget: 0,
                                    window: window)
        log.info("Scheduled session started until \(window.end)")
        return phased(session, at: now)
    }

    /// Where a scheduled window is in its cycle of focus parts and breaks.
    static func phased(_ session: ActiveSession, at now: Date) -> ActiveSession {
        guard let window = session.window else { return session }
        var session = session
        let focus = TimeInterval(max(1, session.profile.focusMinutes) * 60)
        let rest = TimeInterval(session.profile.breakMinutes * 60)
        let cycle = focus + rest
        let elapsed = max(0, now.timeIntervalSince(window.start))
        let cycleStart = window.start.addingTimeInterval((elapsed / cycle).rounded(.down) * cycle)
        if rest == 0 || now < cycleStart.addingTimeInterval(focus) {
            session.phase = .focus
            session.phaseStart = cycleStart
            session.phaseEnd = min(cycleStart.addingTimeInterval(focus), window.end)
        } else {
            session.phase = .rest
            session.phaseStart = cycleStart.addingTimeInterval(focus)
            session.phaseEnd = min(cycleStart.addingTimeInterval(cycle), window.end)
        }
        return session
    }

    /// A scheduled window's breaks between two times, which its review leaves out.
    static func breaks(in session: ActiveSession, from start: Date, to end: Date) -> [DateInterval] {
        guard let window = session.window, session.profile.breakMinutes > 0 else { return [] }
        let focus = TimeInterval(max(1, session.profile.focusMinutes) * 60)
        let cycle = focus + TimeInterval(session.profile.breakMinutes * 60)
        var result: [DateInterval] = []
        var cycleStart = window.start
        while cycleStart < end {
            let breakStart = max(cycleStart.addingTimeInterval(focus), start)
            let breakEnd = min(cycleStart.addingTimeInterval(cycle), end)
            if breakEnd > breakStart { result.append(DateInterval(start: breakStart, end: breakEnd)) }
            cycleStart = cycleStart.addingTimeInterval(cycle)
        }
        return result
    }

    private static func finish(_ session: ActiveSession, outcome: String, note: String = "", at end: Date) {
        SharedStore.update(session.recordID) { record in
            guard record.outcome == "running" else { return }
            record.outcome = outcome
            record.note = note
            record.end = max(record.start, end)
            if let pausedAt = session.pausedAt { record.pauses.append(DateInterval(start: pausedAt, end: max(pausedAt, end))) }
            record.pauses += breaks(in: session, from: record.start, to: max(record.start, end))
        }
        log.info("Session \(outcome): \(session.task)")
    }

    private static func resumed(_ session: ActiveSession, at date: Date) -> ActiveSession {
        guard let pausedAt = session.pausedAt else { return session }
        var session = session
        let paused = max(0, date.timeIntervalSince(pausedAt))
        SharedStore.update(session.recordID) { $0.pauses.append(DateInterval(start: pausedAt, end: pausedAt.addingTimeInterval(paused))) }
        session.pauseBudget = max(0, session.pauseBudget - paused)
        session.phaseStart = session.phaseStart.addingTimeInterval(paused)
        session.phaseEnd = session.phaseEnd.addingTimeInterval(paused)
        session.pausedAt = nil
        return session
    }

    // MARK: Controls

    /// Starts a session now. A scheduled session can't be replaced.
    @discardableResult
    static func start(_ profile: SessionProfile, task: String, now: Date = Date()) -> ActiveSession? {
        let current = reconcile(now: now)
        guard current?.window == nil else { return current }
        if let current, current.phase == .focus { finish(current, outcome: "stopped", note: "Started another session", at: now) }
        let record = SessionRecord(task: task, profile: profile.name, emoji: profile.emoji, start: now,
                                   plannedMinutes: profile.focusMinutes)
        SharedStore.add(record)
        let session = ActiveSession(recordID: record.id, profile: profile, task: task, started: now, phase: .focus,
                                    phaseStart: now, phaseEnd: now.addingTimeInterval(TimeInterval(profile.focusMinutes * 60)),
                                    pausedAt: nil, pauseBudget: ActiveSession.pauseAllowance, window: nil)
        save(session)
        log.info("\(profile.name) session started: \(task)")
        return session
    }

    static func pause(now: Date = Date()) {
        guard var session = reconcile(now: now), session.canPause else { return }
        session.pausedAt = now
        save(session)
    }

    static func resume(now: Date = Date()) {
        guard let session = reconcile(now: now), session.paused else { return }
        save(resumed(session, at: now))
    }

    /// Ends a manual session early. Only the emergency pass ends a scheduled one.
    static func stop(reason: String, now: Date = Date()) {
        guard let session = reconcile(now: now), !session.isScheduled else { return }
        if session.phase == .focus { finish(session, outcome: "stopped", note: reason, at: now) }
        save(nil)
    }

    /// Ends a manual session's break now; scheduled breaks run their course.
    static func endBreak(now: Date = Date()) {
        guard let session = reconcile(now: now), !session.isScheduled, session.phase == .rest else { return }
        save(nil)
    }

    /// Ends today's scheduled session with this week's emergency pass.
    @discardableResult
    static func useEmergencyPass(reason: String, now: Date = Date()) -> Bool {
        guard let session = reconcile(now: now), let window = session.window, SharedStore.passUsedThisWeek(now: now) == nil else {
            return false
        }
        SharedStore.passes = SharedStore.passes + [EmergencyPass(date: now, windowKey: window.key, reason: reason)]
        finish(session, outcome: "stopped", note: "Emergency pass: \(reason)", at: now)
        save(nil)
        log.info("Emergency pass used")
        return true
    }

    private static func save(_ session: ActiveSession?) {
        SharedStore.active = session
        applyShields(session)
        registerMonitors()
        scheduleReminders(session)
    }

    // MARK: Blocking

    /// Sets iOS's shields to the running session's rules, or lifts them.
    static func applyShields(_ session: ActiveSession?) {
        let key = session.map { "\($0.recordID)|\($0.enforcing)" } ?? "none"
        guard key != applied else { return }
        applied = key
        guard let session, session.enforcing else {
            shields.clearAllSettings()
            return
        }
        let profile = session.profile, apps = profile.apps
        switch profile.appMode {
        case .off:
            shields.shield.applications = nil
            shields.shield.applicationCategories = nil
            shields.shield.webDomains = nil
            shields.shield.webDomainCategories = nil
        case .allowOnly:
            shields.shield.applications = nil
            shields.shield.applicationCategories = .all(except: apps.applicationTokens)
            shields.shield.webDomains = nil
            shields.shield.webDomainCategories = nil
        case .block:
            shields.shield.applications = apps.applicationTokens.isEmpty ? nil : apps.applicationTokens
            shields.shield.applicationCategories = apps.categoryTokens.isEmpty ? nil : .specific(apps.categoryTokens, except: [])
            shields.shield.webDomains = apps.webDomainTokens.isEmpty ? nil : apps.webDomainTokens
            shields.shield.webDomainCategories = apps.categoryTokens.isEmpty ? nil : .specific(apps.categoryTokens, except: [])
        }
        let domains = Set(profile.sites.map { WebDomain(domain: SiteMatch.domain($0)) })
        switch profile.siteMode {
        case .off: shields.webContent.blockedByFilter = nil
        case .allowOnly: shields.webContent.blockedByFilter = .all(except: domains)
        case .block: shields.webContent.blockedByFilter = domains.isEmpty ? nil : .specific(domains)
        }
        log.info("Shields on for \(profile.name)")
    }

    // MARK: Waking up while Ribbon is closed

    enum Names {
        static let session = DeviceActivityName("session")
        static let resume = DeviceActivityName("resume")
        static let day = DeviceActivityName("day")
        static let windowEnd = DeviceActivityName("window-end")
        static func schedule(_ id: String) -> DeviceActivityName { DeviceActivityName("schedule." + id) }
    }

    /// Marks for distracting time: through the day for check-ins, and during sessions for their reviews.
    static let daySteps = [15, 30, 45, 60, 90, 120, 180, 240]
    static func sessionSteps(upTo minutes: Int) -> [Int] {
        [5, 10, 15, 20, 30, 45, 60, 90, 120, 180, 240, 300, 360, 480].filter { $0 <= minutes }
    }

    /// Asks iOS to wake the monitor extension at each schedule's start and end, when a manual session's focus part
    /// or pause runs out, and when distracting apps pass a time mark. iOS won't watch a span shorter than 15
    /// minutes, so short ones are watched from 15 minutes before they end.
    static func registerMonitors(now: Date = Date()) {
        let center = DeviceActivityCenter()
        let distracting = SharedStore.hasDistracting ? SharedStore.distracting : nil
        let selectionKey = distracting.flatMap { try? JSONEncoder().encode($0) }.map(fnv) ?? "none"
        var wanted: [(name: DeviceActivityName, schedule: DeviceActivitySchedule, events: [DeviceActivityEvent.Name: DeviceActivityEvent], key: String)] = []

        for schedule in SharedStore.schedules where schedule.enabled && schedule.end - schedule.start >= FocusSchedule.shortest {
            let span = DeviceActivitySchedule(intervalStart: DateComponents(hour: schedule.start / 60, minute: schedule.start % 60),
                                              intervalEnd: DateComponents(hour: schedule.end / 60, minute: schedule.end % 60),
                                              repeats: true)
            let steps = sessionSteps(upTo: schedule.end - schedule.start)
            wanted.append((Names.schedule(schedule.id), span, distracting.map { events($0, steps) } ?? [:],
                           "\(schedule.start)-\(schedule.end)|\(steps)|\(selectionKey)"))
        }
        // The running window ends on time even if its schedule was turned off or deleted meanwhile.
        if let window = SharedStore.active?.window {
            wanted.append((Names.windowEnd, oneOff(from: window.start, to: window.end), [:], window.key))
        }
        if let session = SharedStore.active, !session.isScheduled, session.phase == .focus {
            if let pausedAt = session.pausedAt {
                let resumeAt = pausedAt.addingTimeInterval(session.pauseBudget)
                wanted.append((Names.resume, oneOff(from: resumeAt, to: resumeAt), [:], "\(resumeAt.timeIntervalSince1970)"))
            } else {
                let steps = sessionSteps(upTo: session.profile.focusMinutes)
                wanted.append((Names.session, oneOff(from: session.phaseStart, to: session.phaseEnd),
                               distracting.map { events($0, steps) } ?? [:],
                               "\(session.recordID)|\(session.phaseEnd.timeIntervalSince1970)|\(selectionKey)"))
            }
        }
        if SharedStore.checkIns, let distracting {
            let wholeDay = DeviceActivitySchedule(intervalStart: DateComponents(hour: 0, minute: 0),
                                                  intervalEnd: DateComponents(hour: 23, minute: 59), repeats: true)
            wanted.append((Names.day, wholeDay, events(distracting, daySteps), "day|\(selectionKey)"))
        }

        let saved = SharedStore.defaults.dictionary(forKey: "monitors") as? [String: String] ?? [:]
        let running = Set(center.activities)
        var next: [String: String] = [:]
        for item in wanted {
            next[item.name.rawValue] = item.key
            if saved[item.name.rawValue] == item.key && running.contains(item.name) { continue }
            center.stopMonitoring([item.name])
            do {
                try center.startMonitoring(item.name, during: item.schedule, events: item.events)
            } catch {
                log.error("Couldn't watch \(item.name.rawValue): \(error.localizedDescription)")
                next[item.name.rawValue] = nil
            }
        }
        let stale = running.filter { next[$0.rawValue] == nil }
        if !stale.isEmpty { center.stopMonitoring(Array(stale)) }
        SharedStore.defaults.set(next, forKey: "monitors")
    }

    private static func events(_ selection: FamilyActivitySelection, _ steps: [Int]) -> [DeviceActivityEvent.Name: DeviceActivityEvent] {
        Dictionary(uniqueKeysWithValues: steps.map { minutes in
            (DeviceActivityEvent.Name("distracting.\(minutes)"),
             DeviceActivityEvent(applications: selection.applicationTokens, categories: selection.categoryTokens,
                                 webDomains: selection.webDomainTokens, threshold: DateComponents(minute: minutes)))
        })
    }

    /// A span that ends at `end`, at least 15 minutes long.
    private static func oneOff(from start: Date, to end: Date) -> DeviceActivitySchedule {
        let calendar = Calendar.current
        let begin = min(start, end.addingTimeInterval(-TimeInterval(FocusSchedule.shortest * 60)))
        let parts: Set<Calendar.Component> = [.year, .month, .day, .hour, .minute, .second]
        return DeviceActivitySchedule(intervalStart: calendar.dateComponents(parts, from: begin),
                                      intervalEnd: calendar.dateComponents(parts, from: end), repeats: false)
    }

    private static func fnv(_ data: Data) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in data { hash = (hash ^ UInt64(byte)) &* 0x100000001b3 }
        return String(hash, radix: 16)
    }

    /// A span iOS was watching started or ended.
    static func intervalChanged(_ activity: DeviceActivityName) {
        reconcile()
        registerMonitors()
    }

    /// Distracting apps passed a time mark: for the day, or during the running session.
    /// Returns the day's minutes when that's a new mark for today, for a check-in.
    static func reached(_ event: DeviceActivityEvent.Name, in activity: DeviceActivityName, now: Date = Date()) -> Int? {
        guard let minutes = Int(event.rawValue.split(separator: ".").last ?? "") else { return nil }
        if activity == Names.day {
            let key = Format.dayKey(now)
            var marks = SharedStore.dayMarks
            guard minutes > (marks[key] ?? 0) else { return nil }
            marks[key] = minutes
            let oldest = Format.dayKey(now.addingTimeInterval(-60 * 86400))
            SharedStore.dayMarks = marks.filter { $0.key >= oldest }
            return minutes
        }
        if let session = SharedStore.active,
           activity == Names.session || activity == Names.schedule(session.window?.scheduleID ?? "") {
            SharedStore.update(session.recordID) { $0.distractingMinutes = max($0.distractingMinutes, minutes) }
        }
        return nil
    }

    // MARK: Notifications

    static func notify(_ title: String, _ body: String, id: String = UUID().uuidString, at date: Date? = nil) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let trigger = date.map { UNTimeIntervalNotificationTrigger(timeInterval: max(1, $0.timeIntervalSinceNow), repeats: false) }
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }

    /// "Session done" when the focus part ends, and "Pause's over" when a pause runs out, scheduled ahead so they
    /// arrive with Ribbon closed.
    static func scheduleReminders(_ session: ActiveSession?) {
        let ids = ["session.done", "session.breakOver", "session.pauseOver"]
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
        guard let session, !session.isScheduled else { return }
        if let pausedAt = session.pausedAt {
            notify("Pause's over", "Your \(session.profile.name) session carries on: \(session.task).", id: ids[2],
                   at: pausedAt.addingTimeInterval(session.pauseBudget))
            return
        }
        let breakLength = TimeInterval(session.profile.breakMinutes * 60)
        if session.phase == .focus {
            notify("Session done", "Nice work on \(session.task)." + (breakLength > 0 ? " Take \(Format.duration(breakLength))." : ""),
                   id: ids[0], at: session.phaseEnd)
            if breakLength > 0 {
                notify("Break's over", "Ready for the next one?", id: ids[1], at: session.phaseEnd.addingTimeInterval(breakLength))
            }
        } else if session.phase == .rest {
            notify("Break's over", "Ready for the next one?", id: ids[1], at: session.phaseEnd)
        }
    }
}
