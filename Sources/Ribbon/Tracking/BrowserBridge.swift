import AppKit

/// Reads (and, to block a site, changes) the current tab's URL in browsers that support AppleScript.
/// Each browser asks once for permission ("Ribbon wants to control Google Chrome").
@MainActor final class BrowserBridge {
    enum Access: Equatable { case unknown, asking, granted, denied }

    static let chromium: Set<String> = [
        "com.google.Chrome", "com.google.Chrome.beta", "com.google.Chrome.canary", "com.brave.Browser",
        "com.microsoft.edgemac", "company.thebrowser.Browser", "com.vivaldi.Vivaldi", "org.chromium.Chromium",
        "com.operasoftware.Opera",
    ]
    static let webkit: Set<String> = ["com.apple.Safari", "com.apple.SafariTechnologyPreview"]
    /// Browsers without AppleScript tab access; their page titles still get tracked.
    static let titleOnly: Set<String> = ["org.mozilla.firefox", "app.zen-browser.zen", "org.mozilla.firefoxdeveloperedition"]

    static func isBrowser(_ bundle: String) -> Bool {
        chromium.contains(bundle) || webkit.contains(bundle) || titleOnly.contains(bundle)
    }

    private(set) var access: [String: Access] = [:]
    private var retryAfter: [String: Date] = [:]
    private var scripts: [String: NSAppleScript] = [:]

    func url(of bundle: String) -> String? {
        guard ensureAccess(bundle) else { return nil }
        return run(bundle, Self.webkit.contains(bundle) ? "return URL of front document" : "return URL of active tab of front window")
    }

    @discardableResult
    func open(_ url: String, in bundle: String) -> Bool {
        guard ensureAccess(bundle) else { return false }
        let quoted = url.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let body = Self.webkit.contains(bundle) ? "set URL of front document to \"\(quoted)\""
                                                : "set URL of active tab of front window to \"\(quoted)\""
        return run(bundle, body) != nil || access[bundle] == .granted
    }

    private func ensureAccess(_ bundle: String) -> Bool {
        guard Self.chromium.contains(bundle) || Self.webkit.contains(bundle) else { return false }
        switch access[bundle] ?? .unknown {
        case .granted: return true
        case .asking, .denied: return false
        case .unknown:
            if let retry = retryAfter[bundle], retry > Date() { return false }
            requestAccess(bundle)
            return false
        }
    }

    /// Asking can block until the person answers the system prompt, so it happens off the main thread.
    private func requestAccess(_ bundle: String) {
        access[bundle] = .asking
        Task.detached {
            let target = NSAppleEventDescriptor(bundleIdentifier: bundle)
            let status = AEDeterminePermissionToAutomateTarget(target.aeDesc, typeWildCard, typeWildCard, true)
            await MainActor.run {
                switch status {
                case noErr: self.access[bundle] = .granted
                case OSStatus(errAEEventNotPermitted): self.access[bundle] = .denied
                default:
                    self.access[bundle] = .unknown
                    self.retryAfter[bundle] = Date().addingTimeInterval(60)
                }
                logLine("Browser access for \(bundle): \(self.access[bundle]!)")
            }
        }
    }

    private func run(_ bundle: String, _ body: String) -> String? {
        let source = "tell application id \"\(bundle)\" to \(body)"
        let script = scripts[source] ?? {
            let script = NSAppleScript(source: source)
            scripts[source] = script
            return script
        }()
        var error: NSDictionary?
        let result = script?.executeAndReturnError(&error)
        if let error {
            if (error[NSAppleScript.errorNumber] as? Int) == Int(errAEEventNotPermitted) { access[bundle] = .denied }
            return nil
        }
        return result?.stringValue
    }
}

enum WindowInfo {
    /// The title of an app's front window (needs Screen Recording permission).
    /// Skips the untitled helper windows some apps (Chrome) keep in front.
    static func frontTitle(pid: pid_t) -> String? {
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        return windows.lazy
            .filter { ($0[kCGWindowOwnerPID as String] as? pid_t) == pid && ($0[kCGWindowLayer as String] as? Int) == 0 }
            .compactMap { $0[kCGWindowName as String] as? String }
            .first { !$0.isEmpty }
    }
}
