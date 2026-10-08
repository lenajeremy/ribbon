import AppKit
import ApplicationServices

/// Enforces the running session's rules: hides apps it doesn't allow and turns blocked tabs into a "blocked" page.
@MainActor final class Blocker {
    private let browsers: BrowserBridge
    private let rules: () -> CategoryRules
    /// The session whose rules apply right now (nil outside an active, unpaused focus session).
    var profile: SessionProfile?
    var task = ""
    /// Something was blocked; the message is shown by the orb.
    var onBlock: ((String) -> Void)?
    private var lastAction: (key: String, at: Date)?
    /// Apps already hidden once in a row; a second try within a few seconds quits them.
    private var hiddenAt: [String: Date] = [:]

    /// Never blocked, or you couldn't get back out: the system, and Ribbon itself.
    static let alwaysAllowed: Set<String> = [
        "com.jeremiahlena.focusorb", "com.apple.finder", "com.apple.systempreferences", "com.apple.loginwindow",
        "com.apple.dock", "com.apple.Spotlight", "com.apple.controlcenter", "com.apple.notificationcenterui",
        "com.apple.SecurityAgent", "com.apple.ScreenContinuity", "com.apple.ActivityMonitor",
    ]

    init(browsers: BrowserBridge, rules: @escaping () -> CategoryRules) {
        self.browsers = browsers
        self.rules = rules
        writeBlockedPage()
    }

    func check(_ o: FrontActivity, category: String, app: NSRunningApplication) {
        guard let profile, !Self.alwaysAllowed.contains(o.bundleID) else { return }
        let distracting = rules().kind(category) == .distracting
        let isBrowser = BrowserBridge.isBrowser(o.bundleID)
        let listed = profile.apps.contains { $0.bundleID == o.bundleID }

        let blockApp: Bool
        switch profile.appMode {
        case .allowOnly: blockApp = !listed
        case .block: blockApp = listed || (!isBrowser && profile.blockDistracting && distracting)
        case .off: blockApp = !isBrowser && profile.blockDistracting && distracting
        }
        if blockApp {
            act(on: "app:" + o.bundleID) { block(app, name: o.app, session: profile.name) }
            return
        }

        guard isBrowser, o.url.hasPrefix("http"), !o.domain.isEmpty else { return }
        let siteListed = profile.sites.contains { SiteMatch.matches(o.domain, $0) }
        let blockSite: Bool
        switch profile.siteMode {
        case .allowOnly: blockSite = !siteListed
        case .block: blockSite = siteListed || (profile.blockDistracting && distracting)
        case .off: blockSite = profile.blockDistracting && distracting
        }
        guard blockSite else { return }
        act(on: "site:" + o.domain) {
            browsers.open(blockedPageURL(site: o.domain, session: profile.name), in: o.bundleID)
            return "\(o.domain) is blocked during \(profile.name)"
        }
    }

    /// Hide the app (through Accessibility, which macOS always honors). If you bring it back within a few seconds,
    /// or hiding isn't possible, quit it; apps with unsaved work ask to save first.
    private func block(_ app: NSRunningApplication, name: String, session: String) -> String? {
        let key = app.bundleIdentifier ?? name
        let sinceHidden = hiddenAt[key].map { Date().timeIntervalSince($0) }
        if let sinceHidden, sinceHidden < 1.5 { return nil }  // still disappearing
        if sinceHidden.map({ $0 >= 8 }) ?? true, Self.hideWithAccessibility(app) {
            hiddenAt[key] = Date()
            return "\(name) isn't part of your \(session) session"
        }
        hiddenAt[key] = nil
        app.terminate()
        return "Quit \(name): it isn't part of your \(session) session"
    }

    static var canHide: Bool { AXIsProcessTrusted() }

    /// Shows the system prompt that sends you to Privacy & Security › Accessibility (once per launch).
    static func requestAccessibility() {
        guard !AXIsProcessTrusted(), !askedForAccessibility else { return }
        askedForAccessibility = true
        AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary)
    }
    private static var askedForAccessibility = false

    private static func hideWithAccessibility(_ app: NSRunningApplication) -> Bool {
        guard canHide else { return false }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        return AXUIElementSetAttributeValue(element, kAXHiddenAttribute as CFString, kCFBooleanTrue) == .success
    }

    /// At most once a second per app or site, so a stubborn tab doesn't loop.
    private func act(on key: String, _ action: () -> String?) {
        if let last = lastAction, last.key == key, Date().timeIntervalSince(last.at) < 1 { return }
        lastAction = (key, Date())
        guard let message = action() else { return }
        logLine("Blocked: \(message)")
        onBlock?(message)
    }

    private var pageURL: URL { Store.folder.appendingPathComponent("blocked.html") }

    private func blockedPageURL(site: String, session: String) -> String {
        var components = URLComponents(url: pageURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "site", value: site), URLQueryItem(name: "session", value: session),
                                 URLQueryItem(name: "task", value: task)]
        return components.url!.absoluteString
    }

    private func writeBlockedPage() {
        let html = """
        <!doctype html><html><head><meta charset="utf-8"><title>Blocked by Ribbon</title>
        <style>
        :root { color-scheme: light dark; --bg: #f2f2ef; --ink: #0b0b0b; --ink2: #52514e; }
        @media (prefers-color-scheme: dark) { :root { --bg: #0d0d0d; --ink: #fff; --ink2: #c3c2b7; } }
        body { margin: 0; height: 100vh; display: grid; place-items: center; background: var(--bg); color: var(--ink);
               font: 16px/1.5 -apple-system, system-ui, sans-serif; }
        main { text-align: center; max-width: 440px; padding: 24px; }
        .orb { width: 88px; height: 88px; border-radius: 50%; margin: 0 auto 28px;
               background: radial-gradient(circle at 38% 32%, #ffc46b, #ff5a36 45%, #e8235f 85%);
               box-shadow: 0 0 60px #ff5a3699; animation: breathe 4s ease-in-out infinite; }
        @keyframes breathe { 50% { transform: scale(1.05); } }
        h1 { font-size: 26px; margin: 0 0 8px; letter-spacing: -0.01em; }
        p { color: var(--ink2); margin: 0 0 6px; }
        </style></head><body><main>
        <div class="orb"></div>
        <h1 id="title">Not right now</h1>
        <p id="why"></p><p id="task"></p>
        </main><script>
        const q = new URLSearchParams(location.search);
        const site = q.get('site') || 'This site', session = q.get('session') || 'focus', task = q.get('task');
        document.getElementById('title').textContent = site + ' is blocked';
        document.getElementById('why').textContent = "It isn't part of your " + session + " session.";
        if (task) document.getElementById('task').textContent = 'Back to: ' + task;
        </script></body></html>
        """
        try? html.write(to: pageURL, atomically: true, encoding: .utf8)
    }
}
