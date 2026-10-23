import AppKit

/// Reads (and, to block a site, changes) the current tab's URL in browsers that support AppleScript.
/// Each browser asks once for permission ("Ribbon wants to control Google Chrome").
/// Ribbon asks the copy of the browser that's in front, by its process. Asked by name, macOS picks one copy when
/// several are running (tools that test or record web pages start their own), and that may be a page you can't see.
@MainActor final class BrowserBridge {
    enum Access: Equatable { case unknown, asking, granted, denied }

    /// The browser in front hasn't told Ribbon its address twice in a row, so a session can't block sites there.
    struct Problem: Equatable {
        let browser: String
        /// You turned off Ribbon's permission to control it.
        let notAllowed: Bool
    }

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
    /// Reads in a row that got no answer, per browser.
    private var failures: [String: Int] = [:]

    func url(of app: NSRunningApplication) -> String? {
        guard let bundle = app.bundleIdentifier else { return nil }
        guard ensureAccess(bundle) else {
            if access[bundle] == .denied { failed(bundle, app: app, why: "not allowed") }
            return nil
        }
        do {
            let url = try send(AEEventID(kAEGetData), to: app, about: Self.urlProperty(bundle))
            succeeded(bundle, app: app)
            return url
        } catch let error as NSError where [Int(errAENoSuchObject), Int(errAEIllegalIndex)].contains(error.code) {
            succeeded(bundle, app: app)  // No window open: nothing to read, and nothing wrong.
            return nil
        } catch let error as NSError {
            if error.code == Int(errAEEventNotPermitted) { denied(bundle) }
            failed(bundle, app: app, why: "error \(error.code)")
            return nil
        }
    }

    @discardableResult
    func open(_ url: String, in app: NSRunningApplication) -> Bool {
        guard let bundle = app.bundleIdentifier, ensureAccess(bundle) else { return false }
        do {
            _ = try send(AEEventID(kAESetData), to: app, about: Self.urlProperty(bundle), data: NSAppleEventDescriptor(string: url))
            return true
        } catch let error as NSError {
            if error.code == Int(errAEEventNotPermitted) { denied(bundle) }
            logLine("Couldn't show the blocked page in \(app.localizedName ?? bundle): error \(error.code)")
            return false
        }
    }

    func problem(_ app: NSRunningApplication) -> Problem? {
        guard let bundle = app.bundleIdentifier, failures[bundle, default: 0] >= 2 else { return nil }
        return Problem(browser: app.localizedName ?? bundle, notAllowed: access[bundle] == .denied)
    }

    private func succeeded(_ bundle: String, app: NSRunningApplication) {
        if failures.removeValue(forKey: bundle).map({ $0 >= 2 }) == true {
            logLine("Reading the address in \(app.localizedName ?? bundle) again")
        }
    }

    private func failed(_ bundle: String, app: NSRunningApplication, why: String) {
        failures[bundle, default: 0] += 1
        if failures[bundle] == 2 {
            logLine("Can't read the address in \(app.localizedName ?? bundle) (\(why)), so sessions can't block sites there")
        }
    }

    private func denied(_ bundle: String) {
        if access[bundle] != .denied { logLine("Browser access for \(bundle): denied") }
        access[bundle] = .denied
        retryAfter[bundle] = Date().addingTimeInterval(60)
    }

    private func ensureAccess(_ bundle: String) -> Bool {
        guard Self.chromium.contains(bundle) || Self.webkit.contains(bundle) else { return false }
        let state = access[bundle] ?? .unknown
        if state == .granted { return true }
        if state == .asking || retryAfter[bundle].map({ $0 > Date() }) == true { return false }
        // Never asked: ask. Turned off: check again now and then, without asking, in case you turned it back on.
        requestAccess(bundle, ask: state == .unknown)
        return false
    }

    /// Asking can block until the person answers the system prompt, so it happens off the main thread.
    private func requestAccess(_ bundle: String, ask: Bool) {
        let was = access[bundle] ?? .unknown
        access[bundle] = .asking
        Task.detached {
            let target = NSAppleEventDescriptor(bundleIdentifier: bundle)
            let status = AEDeterminePermissionToAutomateTarget(target.aeDesc, typeWildCard, typeWildCard, ask)
            await MainActor.run {
                let now: Access
                switch status {
                case noErr: now = .granted
                case OSStatus(errAEEventNotPermitted): now = .denied
                default: now = ask ? .unknown : was
                }
                self.access[bundle] = now
                if now != .granted { self.retryAfter[bundle] = Date().addingTimeInterval(60) }
                if now != was { logLine("Browser access for \(bundle): \(now)") }
            }
        }
    }

    /// Sends a get or set event to this copy of the browser and waits up to 3 seconds for its answer.
    private func send(_ eventID: AEEventID, to app: NSRunningApplication, about object: NSAppleEventDescriptor,
                      data: NSAppleEventDescriptor? = nil) throws -> String? {
        let event = NSAppleEventDescriptor.appleEvent(
            withEventClass: AEEventClass(kAECoreSuite), eventID: eventID,
            targetDescriptor: NSAppleEventDescriptor(processIdentifier: app.processIdentifier),
            returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
        event.setParam(object, forKeyword: AEKeyword(keyDirectObject))
        if let data { event.setParam(data, forKeyword: AEKeyword(keyAEData)) }
        let reply = try event.sendEvent(options: [.waitForReply], timeout: 3)
        if let code = reply.paramDescriptor(forKeyword: AEKeyword(keyErrorNumber))?.int32Value, code != 0 {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(code))
        }
        return reply.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue
    }

    // MARK: What to ask for

    /// "URL of active tab of window 1" in Chromium browsers; "URL of document 1" (the front tab) in Safari.
    private static func urlProperty(_ bundle: String) -> NSAppleEventDescriptor {
        webkit.contains(bundle)
            ? property("pURL", of: element("docu", at: 1))
            : property("URL ", of: property("acTa", of: element("cwin", at: 1)))
    }

    private static func element(_ kind: String, at index: Int32) -> NSAppleEventDescriptor {
        specifier(want: code(kind), form: DescType(formAbsolutePosition), data: NSAppleEventDescriptor(int32: index), in: .null())
    }

    private static func property(_ name: String, of container: NSAppleEventDescriptor) -> NSAppleEventDescriptor {
        specifier(want: DescType(cProperty), form: DescType(formPropertyID), data: NSAppleEventDescriptor(typeCode: code(name)), in: container)
    }

    private static func specifier(want: DescType, form: DescType, data: NSAppleEventDescriptor,
                                  in container: NSAppleEventDescriptor) -> NSAppleEventDescriptor {
        let spec = NSAppleEventDescriptor.record().coerce(toDescriptorType: DescType(typeObjectSpecifier))!
        spec.setDescriptor(NSAppleEventDescriptor(typeCode: want), forKeyword: AEKeyword(keyAEDesiredClass))
        spec.setDescriptor(NSAppleEventDescriptor(enumCode: form), forKeyword: AEKeyword(keyAEKeyForm))
        spec.setDescriptor(data, forKeyword: AEKeyword(keyAEKeyData))
        spec.setDescriptor(container, forKeyword: AEKeyword(keyAEContainer))
        return spec
    }

    private static func code(_ text: String) -> FourCharCode { text.utf8.reduce(0) { $0 << 8 | FourCharCode($1) } }
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
