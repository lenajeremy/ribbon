import Carbon
import AppKit

@main
enum RibbonApp {
    @MainActor static func main() {
        setvbuf(stdout, nil, _IOLBF, 0)
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var store: Store!
    private var tracker: ActivityTracker!
    private var focus: FocusController!
    private var scheduler: FocusScheduler!
    /// When macOS last announced a log out, restart or shut down.
    private var poweringOffAt: Date?
    private var blocker: Blocker!
    private var dashboard: DashboardWindow!
    private var dashboardModel: DashboardModel!
    private var statusBar: StatusBar!
    private var breakCoach: BreakCoach!
    private var assistant: Assistant!
    private var updater: Updater!
    private var checkIns: CheckInCoach!
    private var sessionReviewer: SessionReviewer!

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let id = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: id).count > 1 {
            logLine("Ribbon is already running")
            NSApp.terminate(nil)
            return
        }
        let config = Config.load()
        // A key from .env (builds from source) is kept in the keychain too, so it survives updating to a downloaded build.
        if !config.apiKey.isEmpty && APIKeyStore.read() == nil { APIKeyStore.save(config.apiKey) }
        let settings = Settings()
        updater = Updater(settings: settings)
        let chatgpt = ChatGPTAuth()
        let openai = OpenAI(key: config.apiKey, chatgpt: chatgpt)
        store = Store()
        Categories.custom = store.customCategories()
        let classifier = Classifier(store: store, openai: openai)
        tracker = ActivityTracker(store: store, classifier: classifier)
        tracker.idleThreshold = TimeInterval(settings.idleMinutes * 60)
        let reports = Reports(store: store, settings: settings)
        assistant = Assistant(openai: openai, reports: reports)
        dashboardModel = DashboardModel(store: store, reports: reports, assistant: assistant, classifier: classifier,
                                        tracker: tracker, settings: settings)
        dashboard = DashboardWindow(model: dashboardModel)
        let model = dashboardModel!
        let gemini = GeminiVoice()
        dashboardModel.gemini = gemini
        Task { await gemini.prepare() }
        focus = FocusController(config: config, openai: openai, gemini: gemini, store: store, assistant: assistant, settings: settings,
                                profiles: { model.profiles })
        dashboardModel.focus = focus
        scheduler = FocusScheduler(store: store, focus: focus)
        dashboardModel.scheduler = scheduler
        focus.onWindowEnded = { [weak self] in self?.scheduler.refreshKeepOpen() }
        sessionReviewer = SessionReviewer(store: store, assistant: assistant, rules: { reports.rules })
        focus.onSessionEnd = { [weak self] ended in
            Task { [weak self] in
                guard let review = await self?.sessionReviewer.finish(ended) else { return }
                self?.focus.showReview(review)
                self?.dashboardModel.refresh()
            }
        }
        dashboardModel.updater = updater
        blocker = Blocker(browsers: tracker.browsers, rules: { reports.rules })
        statusBar = StatusBar(reports: reports, tracker: tracker, focus: focus) { [weak self] section in
            self?.dashboard.show(section)
        }
        statusBar.updater = updater
        updater.isBusy = { [weak self] in self?.focus.model.phase == .focus || self?.focus.window != nil }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willPowerOffNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.poweringOffAt = Date() }
        }
        breakCoach = BreakCoach(tracker: tracker, settings: settings, isFocusing: { [weak self] in
            self?.focus.model.phase != .idle
        })
        checkIns = CheckInCoach(store: store, reports: reports, assistant: assistant, tracker: tracker, settings: settings,
                                isFocusing: { [weak self] in self?.focus.model.phase != .idle })

        tracker.onActivity = { [weak self] observation, category, app in
            self?.blocker.check(observation, category: category, app: app)
        }
        blocker.onBlock = { [weak self] message in self?.focus.blocked(message) }
        blocker.onBrowserProblem = { [weak self] problem in self?.focus.browserProblem(problem) }
        focus.onStateChange = { [weak self] in
            guard let self else { return }
            blocker.profile = focus.enforcedProfile
            blocker.task = focus.model.task
            if let profile = focus.enforcedProfile, profile.appMode != .off || profile.blockDistracting {
                Blocker.requestAccessibility()
            }
            statusBar.update()
            updater.focusEnded()
        }
        focus.openDashboard = { [weak self] in self?.dashboard.show(.today) }
        Notifier.onOpen = { [weak self] in self?.dashboard.show(.today) }

        NSApp.mainMenu = Self.mainMenu()
        Notifier.requestPermission()
        let args = CommandLine.arguments
        // ⌃⌥⌘O hides or shows the orb from any app.
        HotKey.register(id: 1, keyCode: kVK_ANSI_O, modifiers: cmdKey | optionKey | controlKey) { [weak self] in
            guard let focus = self?.focus else { return }
            focus.setOrbHidden(!focus.orbHidden)
        }
        focus.start(task: args.firstIndex(of: "--start").flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil })
        scheduler.start()
        tracker.start()
        breakCoach.start()
        checkIns.start()
        scheduleReviews()
        updater.start()
        Task { await classifier.repairCustomLabels() }
        if args.contains("--dashboard") { dashboard.show(.today) }
        logLine("Ribbon ready. Tracking \(tracker.isPaused ? "paused" : "on"); AI "
                + (openai.usesPlan ? "on (ChatGPT plan)" : openai.isAvailable ? "on (API key)" : "off"))
    }

    /// Opening the app again (from Finder or Spotlight) opens the dashboard.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        dashboard.show(nil)
        return true
    }

    /// A session holds off quitting (a scheduled one entirely), but never logging out, restarting or shutting down;
    /// a scheduled session picks up again after you log back in.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if let poweringOffAt, Date().timeIntervalSince(poweringOffAt) < 60 { return .terminateNow }
        // focus is nil when a second copy quits right after launch.
        return (focus?.allowQuit() ?? true) ? .terminateNow : .terminateCancel
    }

    func applicationWillTerminate(_ notification: Notification) {
        updater?.applicationWillQuit()
    }

    @objc func checkForUpdates(_ sender: Any?) {
        Task { await updater.check(userInitiated: true) }
    }

    /// Yesterday's review and last week's review get written in the background, so they're waiting for you.
    private func scheduleReviews() {
        let check = { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                guard self.assistant.enabled else { return }
                let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
                if self.assistant.cachedBrief(for: yesterday) == nil,
                   self.dashboardModel.reports.day(yesterday).total >= 30 * 60 {
                    _ = try? await self.assistant.dailyBrief(for: yesterday)
                }
                let lastWeek = Calendar.current.date(byAdding: .day, value: -7, to: Reports.weekStart(for: Date()))!
                if self.assistant.cachedWeekly(for: lastWeek) == nil,
                   self.dashboardModel.reports.week(lastWeek).total >= 2 * 3600,
                   (try? await self.assistant.weeklyReview(for: lastWeek)) != nil {
                    Notifier.post(title: "Your weekly review is ready", body: "See how last week went, and one thing to try this week.")
                }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 20, execute: check)
        Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { _ in check() }
    }

    private static func mainMenu() -> NSMenu {
        let main = NSMenu()
        func submenu(_ title: String, _ items: [NSMenuItem]) {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            let menu = NSMenu(title: title)
            items.forEach(menu.addItem)
            item.submenu = menu
            main.addItem(item)
        }
        submenu("Ribbon", [
            NSMenuItem(title: "About Ribbon", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: ""),
            NSMenuItem(title: "Check for Updates…", action: #selector(AppDelegate.checkForUpdates(_:)), keyEquivalent: ""),
            .separator(),
            NSMenuItem(title: "Hide Ribbon", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h"),
            NSMenuItem(title: "Quit Ribbon", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"),
        ])
        submenu("Edit", [
            NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z"),
            NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "Z"),
            .separator(),
            NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"),
            NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"),
            NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"),
            NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"),
        ])
        submenu("Window", [
            NSMenuItem(title: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"),
            NSMenuItem(title: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m"),
        ])
        return main
    }
}

private let logFile: FileHandle? = {
    let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Ribbon.log")
    if !FileManager.default.fileExists(atPath: url.path) { FileManager.default.createFile(atPath: url.path, contents: nil) }
    let handle = try? FileHandle(forWritingTo: url)
    _ = try? handle?.seekToEnd()
    return handle
}()

/// Prints to the terminal and appends to ~/Library/Logs/Ribbon.log.
func logLine(_ message: String) {
    let line = "[\(Date().formatted(date: .abbreviated, time: .standard))] \(message)"
    print(line)
    logFile?.write(Data((line + "\n").utf8))
}
