import AppKit
import SwiftUI

/// Runs focus sessions: the timer, the session's rules, the screen checks while focusing, and the nudges when you drift.
@MainActor final class FocusController {
    let model = OrbModel()
    private let config: Config
    private let openai: OpenAI
    private let store: Store
    private let assistant: Assistant
    private let settings: Settings
    private let profiles: () -> [SessionProfile]
    private(set) var activeProfile: SessionProfile?
    private var sessionID: Int64?
    /// The scheduled window running now. Its session stays open from start to end, through its breaks.
    private(set) var window: ScheduledWindow?
    /// When the current scheduled break began; breaks are left out of the session's review.
    private var restStart: Date?
    /// The emergency pass ended a scheduled window.
    var onWindowEnded: (() -> Void)?
    private var sessionStart: Date?
    /// The running session's pauses, which its review leaves out.
    private var pauses: [DateInterval] = []
    private var toastWork: Task<Void, Never>?
    /// Focus started, paused, resumed or ended.
    var onStateChange: (() -> Void)?
    var openDashboard: (() -> Void)?
    /// A session ended; it's handed over for its review.
    var onSessionEnd: ((SessionReviewer.Ended) -> Void)?

    var isFocusing: Bool { model.phase == .focus && !model.paused }
    /// The session whose rules apply right now: while focusing, and through a scheduled window's breaks.
    var enforcedProfile: SessionProfile? {
        if window != nil && model.phase != .idle { return activeProfile }
        return isFocusing ? activeProfile : nil
    }
    private let speaker = Speaker()
    private var overlay: OverlayPanel!
    private var panel: InputPanel?
    private var panelObserver: NSObjectProtocol?
    private var previousApp: NSRunningApplication?
    private var timers: [Timer] = []
    private var watcher: Task<Void, Never>?
    private var pressing = false
    private var pressBeganNudging = false
    private var holdWork: Task<Void, Never>?
    private var screenLocked = false
    private var screensAsleep = false

    // Drift tracking for the current Pomodoro.
    private struct Line { let text: String; let audio: Data? }
    private var driftSince: Date?
    private var lastNudgeAt: Date?
    private var nudgeCount = 0
    private var pendingLine: Task<Line, Never>?
    private var firing = false
    /// Bumped whenever a drift ends, so a line prepared for an old drift is never spoken.
    private var episode = 0
    private var spokenLines: [String] = []

    init(config: Config, openai: OpenAI, store: Store, assistant: Assistant, settings: Settings,
         profiles: @escaping () -> [SessionProfile]) {
        self.config = config
        self.openai = openai
        self.store = store
        self.assistant = assistant
        self.settings = settings
        self.profiles = profiles
    }

    func start(task: String?) {
        let screen = NSScreen.screens.first!
        overlay = OverlayPanel(frame: screen.visibleFrame)
        let host = FirstClickHostingView(rootView: OverlayView(model: model))
        host.sizingOptions = []
        overlay.contentView = host
        overlay.ignoresMouseEvents = true
        overlay.orderFrontRegardless()

        every(1) { [weak self] in self?.tick() }
        every(1.0 / 30) { [weak self] in self?.pollMouse() }
        // The overlay only takes the mouse while it's over the orb, so any press it gets is a press on the orb.
        NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp, .rightMouseDown]) { [weak self] event in
            guard let self, event.window === overlay else { return event }
            MainActor.assumeIsolated {
                switch event.type {
                case .leftMouseDown: self.orbPressed()
                case .leftMouseUp: self.orbReleased()
                default: self.tapped()
                }
            }
            return nil
        }
        observeSystem()

        if !ScreenCapture.hasPermission {
            ScreenCapture.requestPermission()
            model.status = "Allow Ribbon under Privacy & Security › Screen Recording, then relaunch it"
        }
        updateOverlayVisibility()
        if let task { startFocus(task, profileID: nil) }
    }

    // MARK: Phases

    private func startFocus(_ task: String, profileID: String?) {
        let all = profiles()
        guard let profile = all.first(where: { $0.id == profileID }) ?? all.first else { return }
        speaker.stop()
        endSession(outcome: "stopped", note: "Started another session")
        activeProfile = profile
        model.task = task
        model.profileName = "\(profile.emoji) \(profile.name)"
        model.pauseBudget = config.pauseSeconds
        spokenLines = []
        resetDrift()
        let duration = focusLength(profile)
        setPhase(.focus, duration: duration)
        sessionStart = Date()
        pauses = []
        sessionID = store.beginSession(task: task, profile: profile.name, at: sessionStart!)
        if profile.watchScreen { startWatching() }
        onStateChange?()
        logLine("\(profile.name) session started (\(minutes(duration))): \(task)")
    }

    /// A focus part's length: the session type's, cut short by a scheduled window's end.
    private func focusLength(_ profile: SessionProfile) -> TimeInterval {
        let length = config.focusOverride ?? TimeInterval(profile.focusMinutes * 60)
        guard let window else { return length }
        return min(length, window.end.timeIntervalSinceNow)
    }

    // MARK: Scheduled windows

    /// Starts a scheduled window's session, or carries on if it's already running. Replaces a session in progress.
    func startScheduled(_ window: ScheduledWindow) {
        guard self.window?.key != window.key else { return }
        guard profiles().contains(where: { $0.id == window.schedule.profileID }) else {
            return logLine("Scheduled session skipped: its session type was deleted")
        }
        closeBreak()  // A break in another window ends with that window's session.
        self.window = window
        model.scheduledUntil = window.end
        startFocus(window.schedule.task, profileID: window.schedule.profileID)
        Notifier.post(title: "Scheduled focus session started",
                      body: "\(model.profileName): \(window.schedule.task), until \(Format.time(window.end)).")
        logLine("Scheduled session started until \(Format.time(window.end))")
    }

    /// The next focus part of a scheduled window, after its break.
    private func nextFocusPart() {
        guard let profile = activeProfile, window != nil else { return goIdle(chime: true) }
        closeBreak()
        spokenLines = []
        resetDrift()
        setPhase(.focus, duration: focusLength(profile))
        if profile.watchScreen { startWatching() }
        onStateChange?()
        NSSound(named: "Glass")?.play()
        logLine("Scheduled focus part started")
    }

    /// The window's end time: its session ends as completed.
    private func finishWindow() {
        guard let window else { return }
        closeBreak()
        stopWatching()
        endSession(outcome: "completed")
        leaveWindow()
        activeProfile = nil
        setPhase(.idle, duration: 0)
        onStateChange?()
        NSSound(named: "Hero")?.play()
        Notifier.post(title: "Scheduled focus session finished", body: "That's \(window.schedule.task) done for today.")
        logLine("Scheduled session finished")
    }

    /// Ends the scheduled window for the rest of today, with this week's emergency pass.
    private func useEmergencyPass(reason: String) {
        guard let window, store.emergencyPassUsedThisWeek() == nil else { return }
        store.useEmergencyPass(window: window.key, reason: reason)
        logLine("Emergency pass used: \(reason)")
        closeBreak()
        endSession(outcome: "stopped", note: "Emergency pass: \(reason)")
        leaveWindow()
        goIdle(chime: false)
        onWindowEnded?()
    }

    /// The emergency pass: whether it's left this week, and what to say about it.
    var emergencyPass: (available: Bool, note: String) {
        guard let used = store.emergencyPassUsedThisWeek() else {
            return (true, "You have this week's emergency pass. It's the only way to end a scheduled session early.")
        }
        return (false, "You used this week's emergency pass on \(used.formatted(.dateTime.weekday(.wide))) at \(Format.time(used)). "
                + "You get a new one on Monday.")
    }

    private func closeBreak() {
        if let restStart { pauses.append(DateInterval(start: restStart, end: max(restStart, Date()))) }
        restStart = nil
    }

    private func leaveWindow() {
        window = nil
        model.scheduledUntil = nil
    }

    private func startBreak() {
        stopWatching()
        if let window, let profile = activeProfile {
            // A scheduled window keeps its session and rules through the break.
            let left = window.end.timeIntervalSinceNow
            guard left >= 60 else { return finishWindow() }
            let duration = min(config.breakOverride ?? TimeInterval(profile.breakMinutes * 60), left)
            guard duration > 0 else { return nextFocusPart() }
            restStart = Date()
            setPhase(.rest, duration: duration)
            onStateChange?()
            NSSound(named: "Glass")?.play()
            logLine("Scheduled break for \(minutes(duration)); the rules stay on")
            return
        }
        endSession(outcome: "completed")
        let duration = config.breakOverride ?? TimeInterval((activeProfile?.breakMinutes ?? 5) * 60)
        guard duration > 0 else { return goIdle(chime: true) }
        setPhase(.rest, duration: duration)
        onStateChange?()
        NSSound(named: "Glass")?.play()
        Notifier.post(title: "Session done", body: "Nice work on \(model.task). Take \(Format.duration(duration)).")
        logLine("Session done. Break for \(minutes(duration)); not watching")
    }

    private func goIdle(chime: Bool) {
        stopWatching()
        closeBreak()
        endSession(outcome: "stopped")
        leaveWindow()
        activeProfile = nil
        setPhase(.idle, duration: 0)
        onStateChange?()
        if chime { NSSound(named: "Hero")?.play() }
        logLine("Idle until the next session")
    }

    private func endSession(outcome: String, note: String = "") {
        guard let id = sessionID else { return }
        let end = Date()
        store.endSession(id, outcome: outcome, note: note, at: end)
        sessionID = nil
        if let pausedAt = model.pausedAt { pauses.append(DateInterval(start: pausedAt, end: max(pausedAt, end))) }
        if let profile = activeProfile, let start = sessionStart {
            onSessionEnd?(.init(id: id, task: model.task, profile: profile, outcome: outcome, start: start, end: end, pauses: pauses))
        }
        sessionStart = nil
        pauses = []
    }

    /// Something the session's rules blocked: show it by the orb and count it.
    func blocked(_ message: String) {
        if let sessionID { store.countSession(sessionID, nudge: false) }
        showToast(message, symbol: "hand.raised.fill", seconds: 4)
    }

    /// A session's score, by the orb, once its review is ready.
    func showReview(_ review: SessionReview) {
        showToast("Session score \(review.score): \(review.verdict)", symbol: "checkmark.seal.fill", seconds: 12)
    }

    private func showToast(_ message: String, symbol: String, seconds: Double) {
        toastWork?.cancel()
        withAnimation(.spring(duration: 0.35)) {
            model.toastSymbol = symbol
            model.toast = message
        }
        toastWork = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.3)) { self?.model.toast = nil }
        }
    }

    /// Opens the orb's control panel, optionally with a session type picked.
    func openPanel(profileID: String? = nil) {
        closePanel()
        showPanel(profileID: profileID)
    }

    /// Quitting mid-session is the same as stopping, so it goes through the same deliberate steps.
    /// During a scheduled window that means the emergency pass, even on a break.
    func allowQuit() -> Bool {
        guard model.phase == .focus || window != nil else { return true }
        openPanel()
        return false
    }

    func updateOverlayVisibility() {
        let show = settings.showOrbWhenIdle || model.phase != .idle || panel != nil
        if model.visible != show { model.visible = show }
        if show && !overlay.isVisible { overlay.orderFrontRegardless() }
        if !show && overlay.isVisible { overlay.orderOut(nil) }
    }

    private func setPhase(_ phase: Phase, duration: TimeInterval) {
        closePanel()
        defer { updateOverlayVisibility() }
        withAnimation(.easeInOut(duration: 0.8)) {
            model.phase = phase
            model.pausedAt = nil
            model.phaseStart = Date()
            model.phaseEnd = Date().addingTimeInterval(duration)
        }
    }

    private func tick() {
        if let pausedAt = model.pausedAt {
            if Date().timeIntervalSince(pausedAt) >= model.pauseBudget { resume(automatically: true) }
            return
        }
        if let window, Date() >= window.end { return finishWindow() }
        guard Date() >= model.phaseEnd else { return }
        switch model.phase {
        case .focus: startBreak()
        case .rest: window != nil ? nextFocusPart() : goIdle(chime: true)
        case .idle: break
        }
    }

    // MARK: Controls (deliberately effortful; see ControlPanel)

    private func pause() {
        // Scheduled sessions can't be paused; the emergency pass is the way out.
        guard window == nil, model.phase == .focus, !model.paused, model.pauseBudget >= 1 else { return }
        watcher?.cancel()
        watcher = nil
        resetDrift()
        endNudge()
        speaker.stop()
        closePanel()
        withAnimation(.easeInOut(duration: 0.6)) { model.pausedAt = Date() }
        onStateChange?()
        logLine("Paused (up to \(clock(model.pauseBudget)))")
    }

    private func resume(automatically: Bool = false) {
        guard let pausedAt = model.pausedAt else { return }
        let paused = Date().timeIntervalSince(pausedAt)
        pauses.append(DateInterval(start: pausedAt, end: max(pausedAt, Date())))
        closePanel()
        withAnimation(.easeInOut(duration: 0.6)) {
            model.pauseBudget = max(0, model.pauseBudget - paused)
            model.phaseStart = model.phaseStart.addingTimeInterval(paused)
            model.phaseEnd = model.phaseEnd.addingTimeInterval(paused)
            model.pausedAt = nil
        }
        if activeProfile?.watchScreen ?? true { startWatching() }
        onStateChange?()
        if automatically { NSSound(named: "Glass")?.play() }
        logLine(automatically ? "Pause time's up; watching again" : "Resumed")
    }

    private func changeFocus(to task: String) {
        guard model.phase == .focus else { return }
        logLine("Changed focus: \(model.task) → \(task)")
        model.task = task
        if let sessionID { store.updateSessionTask(sessionID, task: task) }
        spokenLines = []
        resetDrift()
        endNudge()
        closePanel()
    }

    private func stop(reason: String) {
        guard window == nil else { return }  // Only the emergency pass ends a scheduled window.
        logLine("Stopped early with \(clock(model.timeLeft(at: Date()))) left. Reason: \(reason)")
        endSession(outcome: "stopped", note: reason)
        goIdle(chime: false)
    }

    // MARK: Watching

    private func startWatching() {
        watcher?.cancel()
        watcher = Task { [weak self] in
            while !Task.isCancelled {
                let started = Date()
                await self?.check()
                guard let interval = self?.checkInterval else { return }
                try? await Task.sleep(for: .seconds(max(0.5, interval - Date().timeIntervalSince(started))))
            }
        }
    }

    /// How often the orb looks at your screen. On the ChatGPT plan, every 30 seconds at most, to spare its allowance.
    private var checkInterval: TimeInterval {
        openai.usesPlan ? max(30, config.checkSeconds) : config.checkSeconds
    }

    private func stopWatching() {
        watcher?.cancel()
        watcher = nil
        resetDrift()
        endNudge()
        speaker.stop()
    }

    private func check() async {
        guard model.phase == .focus, !screenLocked, !screensAsleep else { return }
        guard openai.isAvailable else {
            model.status = "Turn on AI in Settings › AI to have the orb watch: continue with ChatGPT or add an OpenAI API key"
            return
        }
        guard ScreenCapture.hasPermission else {
            model.status = "Allow Ribbon under Privacy & Security › Screen Recording, then relaunch it"
            return
        }
        let front = ScreenCapture.frontmost()
        let activeDisplay = ScreenCapture.cursorDisplayID()
        do {
            let shots = try await Task.detached { try await ScreenCapture.captureAll(activeDisplay: activeDisplay) }.value
            guard !shots.isEmpty else { return }
            let context = describe(front)
            let started = Date()
            let probability = try await openai.onTaskProbability(task: model.task, context: context, shots: shots)
            guard model.phase == .focus, !Task.isCancelled else { return }
            guard let probability else { return logLine("Check: the model declined to answer") }
            model.status = nil
            let where_ = [front.app, front.window].compactMap { $0 }.joined(separator: " — ")
            let ms = Int(Date().timeIntervalSince(started) * 1000)
            logLine(String(format: "%@ %.2f  %@  (%d displays, %d ms)",
                           probability >= 0.5 ? "on task " : "OFF TASK", probability, where_, shots.count, ms))
            handleVerdict(onTask: probability >= 0.5, shots: shots, context: context)
        } catch {
            guard !Task.isCancelled else { return }
            logLine("Check failed: \(error.localizedDescription)")
            model.status = "Can't check your screens: \(error.localizedDescription)"
        }
    }

    private func describe(_ front: (app: String?, window: String?)) -> String {
        var text = "The user is in a Pomodoro focus session. They said they'd work on: \"\(model.task)\"."
        if let app = front.app {
            text += " The frontmost app is \(app)"
            if let window = front.window { text += ", and its front window is titled \"\(window)\"" }
            text += "."
        }
        return text + " Below are screenshots of each of their displays, taken just now."
    }

    // MARK: Drifting and nudging

    private func handleVerdict(onTask: Bool, shots: [Screenshot], context: String) {
        let now = Date()
        if onTask {
            if driftSince != nil { logLine("Back on task") }
            resetDrift()
            endNudge()
            return
        }
        if driftSince == nil {
            driftSince = now
            logLine("Drifting…")
        }
        // First nudge after a full minute adrift, then another every minute you stay adrift.
        let due = (lastNudgeAt ?? driftSince!).addingTimeInterval(config.driftSeconds)
        // Write and voice the line a little early so it plays right on time.
        let lead = min(15, config.driftSeconds * 0.4)
        if pendingLine == nil, now >= due.addingTimeInterval(-lead) {
            pendingLine = prepareLine(shot: shots.first, context: context)
        }
        if now >= due, !firing {
            Task { await fireNudge() }
        }
    }

    private func prepareLine(shot: Screenshot?, context: String) -> Task<Line, Never> {
        let openai = openai, task = model.task, previous = spokenLines, reminder = nudgeCount + 1
        let voice = config.voice, muted = model.muted
        return Task.detached {
            let text: String
            do {
                text = try await openai.quip(task: task, context: context, shot: shot, previous: previous, reminder: reminder)
            } catch {
                if Task.isCancelled { return Line(text: "", audio: nil) }
                logLine("Couldn't write a line: \(error.localizedDescription)")
                text = "Hey, that doesn't look like \(task). Back to it?"
            }
            // Without an OpenAI voice (on the ChatGPT plan), the macOS voice reads it.
            if muted || Task.isCancelled || !openai.canSpeak { return Line(text: text, audio: nil) }
            do {
                return Line(text: text, audio: try await openai.speech(text, voice: voice))
            } catch {
                if !Task.isCancelled { logLine("OpenAI voice failed, using the macOS voice: \(error.localizedDescription)") }
                return Line(text: text, audio: nil)
            }
        }
    }

    private func fireNudge() async {
        guard let pending = pendingLine else { return }
        firing = true
        defer { firing = false }
        let currentEpisode = episode
        let line = await pending.value
        guard episode == currentEpisode, model.phase == .focus, driftSince != nil else { return }
        pendingLine = nil
        nudgeCount += 1
        lastNudgeAt = Date()
        if let sessionID { store.countSession(sessionID, nudge: true) }
        spokenLines.append(line.text)
        logLine("Nudge #\(nudgeCount): \(line.text)")

        if model.nudging {
            withAnimation(.easeInOut(duration: 0.4)) { model.nudgeText = line.text }
        } else {
            closePanel()
            moveOverlayToCursorScreen()
            try? await Task.sleep(for: .milliseconds(60))
            guard episode == currentEpisode else { return }
            withAnimation(.spring(duration: 1.1, bounce: 0.25)) {
                model.nudging = true
                model.nudgeText = line.text
            }
        }
        if !model.muted {
            if let audio = line.audio { speaker.play(audio) } else { speaker.say(line.text) }
        }
    }

    private func endNudge() {
        guard model.nudging else { return }
        withAnimation(.spring(duration: 1.0, bounce: 0.15)) {
            model.nudging = false
            model.nudgeText = nil
        }
    }

    /// Clicking the big orb: "I'm on it" or "you got it wrong". Either way, back to the corner for another full minute.
    private func dismissNudge() {
        speaker.stop()
        endNudge()
        resetDrift()
        driftSince = Date()
        logLine("Nudge dismissed")
    }

    private func resetDrift() {
        pendingLine?.cancel()
        pendingLine = nil
        episode += 1
        driftSince = nil
        lastNudgeAt = nil
        nudgeCount = 0
    }

    // MARK: Input

    /// A click opens the controls; waving off a nudge takes a 2-second hold instead.
    private func orbPressed() {
        guard !pressing else { return }
        pressing = true
        pressBeganNudging = model.nudging
        guard model.nudging else { return }
        withAnimation(.linear(duration: 2)) { model.holding = true }
        holdWork = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, let self else { return }
            dismissNudge()
            withAnimation(.spring(duration: 0.3)) { model.holding = false }
        }
    }

    private func orbReleased(click: Bool = true) {
        guard pressing else { return }
        pressing = false
        holdWork?.cancel()
        holdWork = nil
        withAnimation(.spring(duration: 0.3)) { model.holding = false }
        if click && !pressBeganNudging { tapped() }
    }

    private var panelActions: PanelActions {
        PanelActions(
            start: { [weak self] in self?.startFocus($0, profileID: $1) },
            pause: { [weak self] in self?.pause() },
            resume: { [weak self] in self?.resume() },
            changeFocus: { [weak self] in self?.changeFocus(to: $0) },
            stop: { [weak self] in self?.stop(reason: $0) },
            useEmergencyPass: { [weak self] in self?.useEmergencyPass(reason: $0) },
            toggleMute: { [weak self] in
                guard let self else { return }
                model.muted.toggle()
                if model.muted { speaker.stop() }
            },
            quit: { NSApp.terminate(nil) },
            close: { [weak self] in self?.closePanel() },
            openDashboard: { [weak self] in self?.closePanel(); self?.openDashboard?() }
        )
    }

    private func tapped() {
        if model.nudging { return }  // a nudge is waved off by holding, not clicking
        if panel != nil { closePanel() } else { showPanel(profileID: nil) }
    }

    private func showPanel(profileID: String?) {
        guard panel == nil, !model.nudging else { return }
        if !overlay.isVisible { overlay.orderFrontRegardless() }
        previousApp = NSWorkspace.shared.frontmostApplication
        let orb = orbScreenCenter(nudging: false)
        let ringRadius = OrbLayout.ringDiameter(OrbLayout.smallCore) / 2
        // Grows up and to the left from beside the orb; the content sits in the bottom-right corner.
        let size = NSSize(width: 420, height: 340)
        let window = InputPanel(frame: NSRect(
            x: orb.x - ringRadius - 4 - size.width, y: orb.y - 41,
            width: size.width, height: size.height))
        let all = profiles()
        let host = NSHostingView(rootView: ControlPanel(
            model: model,
            profiles: all,
            profileID: profileID ?? activeProfile?.id ?? all.first?.id,
            actions: panelActions,
            emergencyPass: emergencyPass,
            suggest: { [assistant] task in await assistant.suggestProfile(for: task, from: all) }))
        host.sizingOptions = []
        window.contentView = host
        panel = window
        model.panelOpen = true
        window.makeKeyAndOrderFront(nil)
        if !window.isKeyWindow {
            NSApp.activate()
            window.makeKeyAndOrderFront(nil)
        }
        if !window.isKeyWindow { logLine("The control panel couldn't take keyboard focus") }
        panelObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: window, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.closePanel() }
        }
    }

    private func closePanel() {
        guard let window = panel else { return }
        panel = nil
        if let panelObserver { NotificationCenter.default.removeObserver(panelObserver) }
        panelObserver = nil
        window.orderOut(nil)
        model.panelOpen = false
        updateOverlayVisibility()
        if NSApp.isActive { previousApp?.activate(options: []) }
        previousApp = nil
    }

    /// The overlay ignores the mouse except right over the orb, so it never gets in the way of your clicks.
    private func pollMouse() {
        let mouse = NSEvent.mouseLocation
        let center = orbScreenCenter(nudging: model.nudging)
        let radius = OrbLayout.ringDiameter(OrbLayout.core(nudging: model.nudging)) / 2
        let over = pressing || hypot(mouse.x - center.x, mouse.y - center.y) <= radius
        // A release that landed somewhere else still ends the press.
        if pressing && NSEvent.pressedMouseButtons & 1 == 0 { orbReleased(click: false) }
        if overlay.ignoresMouseEvents == over { overlay.ignoresMouseEvents = !over }
        if model.hovering != over {
            withAnimation(.easeOut(duration: 0.18)) { model.hovering = over }
        }
    }

    // MARK: Screens and system

    private func orbScreenCenter(nudging: Bool) -> CGPoint {
        let frame = overlay.frame
        let center = OrbLayout.center(in: frame.size, nudging: nudging)
        return CGPoint(x: frame.minX + center.x, y: frame.maxY - center.y)
    }

    /// The orb floats to the front of whichever display you're using.
    private func moveOverlayToCursorScreen() {
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }),
              screen.visibleFrame != overlay.frame else { return }
        overlay.setFrame(screen.visibleFrame, display: true)
    }

    private func screensChanged() {
        let screen = NSScreen.screens.first { $0.frame.intersects(overlay.frame) } ?? NSScreen.screens.first
        if let screen, screen.visibleFrame != overlay.frame {
            overlay.setFrame(screen.visibleFrame, display: true)
        }
    }

    private func observeSystem() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.screensChanged() }
        }
        let distributed = DistributedNotificationCenter.default()
        for (name, locked) in [("com.apple.screenIsLocked", true), ("com.apple.screenIsUnlocked", false)] {
            distributed.addObserver(forName: .init(name), object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.pause(locked: locked) }
            }
        }
        let workspace = NSWorkspace.shared.notificationCenter
        for (name, asleep) in [(NSWorkspace.screensDidSleepNotification, true), (NSWorkspace.screensDidWakeNotification, false)] {
            workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.pause(asleep: asleep) }
            }
        }
    }

    /// No judging the lock screen.
    private func pause(locked: Bool? = nil, asleep: Bool? = nil) {
        if let locked { screenLocked = locked }
        if let asleep { screensAsleep = asleep }
        if screenLocked || screensAsleep {
            resetDrift()
            endNudge()
            speaker.stop()
        }
    }

    private func every(_ interval: TimeInterval, _ body: @escaping @MainActor () -> Void) {
        let timer = Timer(timeInterval: interval, repeats: true) { _ in MainActor.assumeIsolated { body() } }
        RunLoop.main.add(timer, forMode: .common)
        timers.append(timer)
    }

    private func minutes(_ seconds: TimeInterval) -> String {
        seconds >= 60 && seconds.truncatingRemainder(dividingBy: 60) == 0 ? "\(Int(seconds / 60)) min" : "\(Int(seconds)) s"
    }
}
