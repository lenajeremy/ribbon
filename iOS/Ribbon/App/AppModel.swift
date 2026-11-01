import FamilyControls
import SwiftUI
import UserNotifications

/// What the app's screens draw from, and the actions they take. Sessions themselves run in Engine, which the
/// monitor extension shares, so they carry on with the app closed.
@Observable @MainActor final class AppModel {
    enum TabID: Hashable { case today, focus, week }

    var profiles: [SessionProfile] = []
    var schedules: [FocusSchedule] = []
    var sessions: [SessionRecord] = []
    var active: ActiveSession?
    var authorized = false
    var aiOn = false
    var tone: Tone = .friendly
    var checkIns = true
    var distracting = FamilyActivitySelection(includeEntireCategory: true)
    var categories: [AppCategory] = []
    var reviewing = false

    var tab: TabID = .today
    var showSettings = false
    var showSession = false
    var showStart = false
    var startProfileID: String?
    var editing: SessionProfile?
    var editingSchedule: FocusSchedule?
    var openRecord: SessionRecord?
    /// A category for Settings to open its editor on, for screenshots.
    var openCategory: AppCategory?

    /// Sample data for screenshots in the Simulator, which has no Screen Time: launch with -RibbonDemo.
    let demo = ProcessInfo.processInfo.arguments.contains("-RibbonDemo")

    init() {
        if demo { Demo.seed() }
        refresh()
        #if DEBUG
        // Debug builds open the page named by -RibbonTab / -RibbonOpen / -RibbonScroll, for screenshots of real data.
        // The scroll is shared through the app group so the Screen Time report, a separate process, can follow it.
        let arguments = ProcessInfo.processInfo.arguments
        for key in ["RibbonScroll", "RibbonAppearance"] {
            SharedStore.defaults.set(UserDefaults.standard.string(forKey: key), forKey: key)
        }
        SharedStore.defaults.set(arguments.contains { $0.hasPrefix("-Ribbon") }, forKey: "RibbonShot")
        Demo.open(self)
        #else
        if demo { Demo.open(self) }
        #endif
    }

    // MARK: Loading

    func refresh() {
        active = Engine.reconcile()
        load()
        authorized = demo || AuthorizationCenter.shared.authorizationStatus == .approved
        aiOn = AI.isOn
        LiveActivities.sync(active)
        guard !demo else { return }
        Engine.registerMonitors()
        Engine.scheduleReminders(active)
        Task { await reviewPending() }
    }

    private func load() {
        profiles = SharedStore.profiles
        schedules = SharedStore.schedules
        sessions = SharedStore.sessions
        tone = SharedStore.tone
        checkIns = SharedStore.checkIns
        distracting = SharedStore.distracting
        categories = SharedStore.categories
    }

    /// Every few seconds while Ribbon is open: a focus part, pause or schedule may have just ended or begun.
    func tick() {
        let now = Engine.reconcile()
        guard now != active else { return }
        let ended = active != nil && now?.recordID != active?.recordID
        active = now
        sessions = SharedStore.sessions
        LiveActivities.sync(now)
        if now == nil { showSession = false }
        if ended || now?.phase == .rest { Task { await reviewPending() } }
    }

    // MARK: Permissions

    func requestScreenTime() async {
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
        } catch {
            log.error("Screen Time access: \(error.localizedDescription)")
        }
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        refresh()
    }

    // MARK: Sessions

    func openStart(_ profile: SessionProfile? = nil) {
        startProfileID = profile?.id ?? profiles.first?.id
        showStart = true
    }

    func start(_ profile: SessionProfile, task: String) {
        Engine.start(profile, task: task)
        Task { _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) }
        refresh()
        showSession = active != nil
    }

    func pause() { Engine.pause(); refresh() }
    func resume() { Engine.resume(); refresh() }
    func stop(reason: String) { Engine.stop(reason: reason); refresh() }
    func endBreak() { Engine.endBreak(); refresh() }

    func useEmergencyPass(reason: String) {
        Engine.useEmergencyPass(reason: reason)
        refresh()
    }

    var passNote: (available: Bool, text: String) {
        guard let used = SharedStore.passUsedThisWeek() else {
            return (true, "You have this week's emergency pass. It's the only way to end a scheduled session early.")
        }
        return (false, "You used this week's emergency pass on \(used.date.formatted(.dateTime.weekday(.wide))) at "
                + "\(Format.time(used.date)). You get a new one next Monday.")
    }

    /// Ended sessions not yet reviewed, reviewed now: by the AI when it's on, otherwise in Ribbon's own words.
    func reviewPending() async {
        guard !reviewing else { return }
        reviewing = true
        defer { reviewing = false }
        for record in SharedStore.sessions where record.outcome != "running" && !record.reviewed {
            SharedStore.update(record.id) { $0.reviewed = true }
            guard record.counted >= Reviewer.minimumLength else { continue }
            let review = await Reviewer.review(record)
            SharedStore.update(record.id) { $0.review = review }
            Engine.notify("Session score: \(review.score)", "\(review.verdict). \(review.summary)", id: "review.\(record.id)")
        }
        sessions = SharedStore.sessions
    }

    /// Deletes a past session and its review for good. The running session can't be deleted.
    func delete(_ session: SessionRecord) {
        guard session.outcome != "running" else { return }
        SharedStore.sessions = SharedStore.sessions.filter { $0.id != session.id }
        sessions = SharedStore.sessions
    }

    func setHidden(_ hidden: Bool, session: SessionRecord) {
        SharedStore.update(session.id) { $0.hidden = hidden }
        sessions = SharedStore.sessions
    }

    // MARK: Session types and schedules

    func newProfile() -> SessionProfile {
        SessionProfile(name: "", emoji: "🎯", focusMinutes: 50, breakMinutes: 10, appMode: .block, siteMode: .block,
                       sites: SessionProfile.distractingSites)
    }

    func save(_ profile: SessionProfile) {
        var all = SharedStore.profiles
        if let index = all.firstIndex(where: { $0.id == profile.id }) { all[index] = profile } else { all.append(profile) }
        SharedStore.profiles = all
        profiles = all
    }

    func delete(_ profile: SessionProfile) {
        SharedStore.profiles = SharedStore.profiles.filter { $0.id != profile.id }
        profiles = SharedStore.profiles
    }

    func newSchedule() -> FocusSchedule {
        FocusSchedule(profileID: profiles.first?.id ?? "", task: "", days: FocusSchedule.weekdays, start: 9 * 60, end: 12 * 60)
    }

    func save(_ schedule: FocusSchedule) {
        var all = SharedStore.schedules
        if let index = all.firstIndex(where: { $0.id == schedule.id }) { all[index] = schedule } else { all.append(schedule) }
        SharedStore.schedules = all
        refresh()
    }

    func delete(_ schedule: FocusSchedule) {
        SharedStore.schedules = SharedStore.schedules.filter { $0.id != schedule.id }
        refresh()
    }

    // MARK: Settings

    func setTone(_ tone: Tone) {
        SharedStore.tone = tone
        self.tone = tone
    }

    func setCheckIns(_ on: Bool) {
        SharedStore.checkIns = on
        checkIns = on
        Engine.registerMonitors()
    }

    func setDistracting(_ selection: FamilyActivitySelection) {
        SharedStore.distracting = selection
        distracting = selection
        Engine.registerMonitors()
    }

    // MARK: Your categories

    func newCategory() -> AppCategory {
        let used = Set(categories.map(\.slot))
        return AppCategory(name: "", slot: (1...8).first { !used.contains($0) } ?? 1, kind: "productive")
    }

    /// Saves a category. An app lives in one category of yours, so apps picked here leave the others.
    func save(_ category: AppCategory) {
        var all = SharedStore.categories.map { other -> AppCategory in
            guard other.id != category.id else { return other }
            var other = other
            other.apps.applicationTokens.subtract(category.apps.applicationTokens)
            other.apps.categoryTokens.subtract(category.apps.categoryTokens)
            other.apps.webDomainTokens.subtract(category.apps.webDomainTokens)
            return other
        }
        if let index = all.firstIndex(where: { $0.id == category.id }) { all[index] = category } else { all.append(category) }
        SharedStore.categories = all
        categories = all
    }

    func delete(_ category: AppCategory) {
        SharedStore.categories = SharedStore.categories.filter { $0.id != category.id }
        categories = SharedStore.categories
    }

    func saveKey(_ key: String?) {
        Keychain.save(key?.trimmingCharacters(in: .whitespacesAndNewlines))
        aiOn = AI.isOn
    }
}
