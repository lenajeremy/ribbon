import AppKit

/// What's in front of you right now.
struct FrontActivity: Equatable {
    var bundleID: String
    var app: String
    var title: String
    var url: String
    var domain: String
}

/// Records every app and website you use, with exact times, into the local database.
/// Checks once a second and writes only when something changes.
@MainActor final class ActivityTracker {
    struct Current {
        var observation: FrontActivity
        var rowID: Int64
        var start: Date
        var lastWrite: Date
        var key: String
        var category: String
    }

    private let store: Store
    private let classifier: Classifier
    let browsers = BrowserBridge()
    var idleThreshold: TimeInterval = 5 * 60
    /// Called every tick with what's in front, so session rules can be enforced.
    var onActivity: ((FrontActivity, String, NSRunningApplication) -> Void)?

    private(set) var current: Current?
    /// When the current stretch of uninterrupted work began (reset by 5 minutes away).
    private(set) var streakStart: Date?
    private var lastActive: Date?
    private var lastURL: (bundle: String, title: String, at: Date, url: String)?
    /// The last address a browser did give, for the moments when asking it fails.
    private var lastGoodURL: (bundle: String, at: Date, url: String)?
    private var screenLocked = false
    private var screensAsleep = false

    var pausedUntil: Date? {
        didSet { UserDefaults.standard.set(pausedUntil, forKey: "trackingPausedUntil"); tick() }
    }
    var isPaused: Bool { pausedUntil.map { $0 > Date() } ?? false }
    var isAway: Bool { current == nil }

    init(store: Store, classifier: Classifier) {
        self.store = store
        self.classifier = classifier
        pausedUntil = UserDefaults.standard.object(forKey: "trackingPausedUntil") as? Date
        classifier.onLabel = { [weak self] key, category in
            guard let self, current?.key == key else { return }
            current?.category = category
        }
    }

    func start() {
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.tick() } }
        RunLoop.main.add(timer, forMode: .common)
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        for (name, asleep) in [(NSWorkspace.screensDidSleepNotification, true), (NSWorkspace.screensDidWakeNotification, false),
                               (NSWorkspace.willSleepNotification, true), (NSWorkspace.didWakeNotification, false)] {
            workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.screensAsleep = asleep; self?.tick() }
            }
        }
        for (name, locked) in [("com.apple.screenIsLocked", true), ("com.apple.screenIsUnlocked", false)] {
            DistributedNotificationCenter.default().addObserver(forName: .init(name), object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.screenLocked = locked; self?.tick() }
            }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.close(at: Date()) }
        }
        tick()
    }

    func tick() {
        let now = Date()
        if let until = pausedUntil, until <= now { pausedUntil = nil; logLine("Tracking resumed") }
        guard !isPaused, !screenLocked, !screensAsleep else { return close(at: now) }
        guard let app = NSWorkspace.shared.frontmostApplication else { return }

        let bundle = app.bundleIdentifier ?? app.localizedName ?? "unknown"
        var observation = FrontActivity(bundleID: bundle, app: app.localizedName ?? bundle,
                                      title: WindowInfo.frontTitle(pid: app.processIdentifier) ?? "", url: "", domain: "")
        if BrowserBridge.isBrowser(bundle) {
            observation.url = browserURL(bundle, title: observation.title, now: now)
            observation.domain = Domains.host(of: observation.url)
        }
        let same = current?.observation == observation
        let category = same ? current!.category : classifier.category(for: observation).category

        // Away from the keyboard, unless it's something you'd watch or listen to without touching anything.
        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
        if idle >= idleThreshold && !Self.isPassive(observation, category: category) {
            return close(at: now.addingTimeInterval(-idle))
        }

        onActivity?(observation, category, app)

        if same, let current {
            if now.timeIntervalSince(current.lastWrite) >= 15 {
                store.extendActivity(current.rowID, to: now)
                self.current?.lastWrite = now
            }
            return
        }
        close(at: now)
        let resolved = classifier.category(for: observation)
        let id = store.beginActivity(observation, key: resolved.key, category: resolved.category, at: now)
        current = Current(observation: observation, rowID: id, start: now, lastWrite: now, key: resolved.key, category: resolved.category)
        if streakStart == nil || now.timeIntervalSince(lastActive ?? .distantPast) >= Analytics.minimumBreak { streakStart = now }
    }

    private func close(at end: Date) {
        guard let current else { return }
        let end = max(current.start, end)
        store.extendActivity(current.rowID, to: end)
        lastActive = end
        self.current = nil
    }

    private func browserURL(_ bundle: String, title: String, now: Date) -> String {
        if let last = lastURL, last.bundle == bundle, last.title == title, now.timeIntervalSince(last.at) < 5 { return last.url }
        var url = browsers.url(of: bundle) ?? ""
        if !url.isEmpty {
            lastGoodURL = (bundle, now, url)
        } else if let good = lastGoodURL, good.bundle == bundle, now.timeIntervalSince(good.at) < 30 {
            // The browser sometimes doesn't answer for a moment. That isn't leaving the page.
            url = good.url
        }
        lastURL = (bundle, title, now, url)
        return url
    }

    private static let videoApps: Set<String> = ["com.apple.TV", "com.apple.QuickTimePlayerX", "com.colliderli.iina", "org.videolan.vlc"]
    private static let videoSites: Set<String> = ["youtube.com", "netflix.com", "twitch.tv", "hulu.com", "disneyplus.com",
                                                  "primevideo.com", "max.com", "vimeo.com"]

    static func isPassive(_ o: FrontActivity, category: String) -> Bool {
        category == "meetings" || videoApps.contains(o.bundleID) || Domains.suffixes(o.domain).contains { videoSites.contains($0) }
    }
}
