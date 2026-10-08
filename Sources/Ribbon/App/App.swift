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
    private var blocker: Blocker!
    private var dashboard: DashboardWindow!
    private var dashboardModel: DashboardModel!
    private var statusBar: StatusBar!
    private var breakCoach: BreakCoach!
    private var assistant: Assistant!
    private var updater: Updater!

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let id = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: id).count > 1 {
            logLine("Ribbon is already running")
            NSApp.terminate(nil)
            return
        }
        let config = Config.load()
        let aiEnabled = !config.apiKey.isEmpty
        // A key from .env (builds from source) is kept in the keychain too, so it survives updating to a downloaded build.
        if aiEnabled && APIKeyStore.read() == nil { APIKeyStore.save(config.apiKey) }
        let settings = Settings()
        updater = Updater(settings: settings)
        let openai = OpenAI(key: config.apiKey)
        store = Store()
        Categories.custom = store.customCategories()
        let classifier = Classifier(store: store, openai: openai, aiEnabled: aiEnabled)
        tracker = ActivityTracker(store: store, classifier: classifier)
        tracker.idleThreshold = TimeInterval(settings.idleMinutes * 60)
        let reports = Reports(store: store, settings: settings)
        assistant = Assistant(openai: openai, reports: reports, enabled: aiEnabled)
        dashboardModel = DashboardModel(store: store, reports: reports, assistant: assistant, classifier: classifier,
                                        tracker: tracker, settings: settings)
        dashboard = DashboardWindow(model: dashboardModel)
        let model = dashboardModel!
        focus = FocusController(config: config, openai: openai, store: store, assistant: assistant, settings: settings,
                                profiles: { model.profiles })
        dashboardModel.focus = focus
        dashboardModel.updater = updater
        blocker = Blocker(browsers: tracker.browsers, rules: { reports.rules })
        statusBar = StatusBar(reports: reports, tracker: tracker, focus: focus) { [weak self] section in
            self?.dashboard.show(section)
        }
        statusBar.updater = updater
        updater.isBusy = { [weak self] in self?.focus.model.phase == .focus }
        breakCoach = BreakCoach(tracker: tracker, settings: settings, isFocusing: { [weak self] in
            self?.focus.model.phase != .idle
        })

        tracker.onActivity = { [weak self] observation, category, app in
            self?.blocker.check(observation, category: category, app: app)
        }
        blocker.onBlock = { [weak self] message in self?.focus.blocked(message) }
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

        NSApp.mainMenu = Self.mainMenu()
        Notifier.requestPermission()
        let args = CommandLine.arguments
        focus.start(task: args.firstIndex(of: "--start").flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil })
        tracker.start()
        breakCoach.start()
        scheduleReviews()
        updater.start()
        Task { await classifier.repairCustomLabels() }
        if args.contains("--dashboard") { dashboard.show(.today) }
        logLine("Ribbon ready. Tracking \(tracker.isPaused ? "paused" : "on"); AI \(aiEnabled ? "on" : "off")")
    }

    /// Opening the app again (from Finder or Spotlight) opens the dashboard.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        dashboard.show(nil)
        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // focus is nil when a second copy quits right after launch.
        (focus?.allowQuit() ?? true) ? .terminateNow : .terminateCancel
    }

    func applicationWillTerminate(_ notification: Notification) {
        updater?.applicationWillQuit()
    }

    @objc func checkForUpdates(_ sender: Any?) {
        Task { await updater.check(userInitiated: true) }
    }

    /// Yesterday's review and last week's review get written in the background, so they're waiting for you.
    private func scheduleReviews() {
        guard assistant.enabled else { return }
        let check = { [weak self] in
            guard let self else { return }
            Task { @MainActor in
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
