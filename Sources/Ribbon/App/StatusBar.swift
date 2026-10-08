import AppKit

/// The menu bar item: today's tracked time at a glance, and quick actions.
@MainActor final class StatusBar: NSObject, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let reports: Reports
    private let tracker: ActivityTracker
    private let focus: FocusController
    private let openDashboard: (DashboardModel.Section?) -> Void

    init(reports: Reports, tracker: ActivityTracker, focus: FocusController, openDashboard: @escaping (DashboardModel.Section?) -> Void) {
        self.reports = reports
        self.tracker = tracker
        self.focus = focus
        self.openDashboard = openDashboard
        super.init()
        item.button?.image = Self.icon
        item.button?.imagePosition = .imageLeading
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        update()
        let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.update() } }
        RunLoop.main.add(timer, forMode: .common)
    }

    func update() {
        let model = focus.model
        if model.phase == .focus {
            item.button?.title = " " + (model.paused ? "Paused" : clock(model.timeLeft(at: Date())))
        } else if tracker.isPaused {
            item.button?.title = " Paused"
        } else {
            item.button?.title = " " + Format.duration(reports.day(Date()).total)
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let today = reports.day(Date())
        var summary = "Today: \(Format.duration(today.total)) tracked"
        if let score = today.productivity.value { summary += " · productivity \(score)" }
        if let score = today.focus.value { summary += " · focus \(score)" }
        menu.addItem(withTitle: summary, action: nil, keyEquivalent: "").isEnabled = false
        if focus.model.phase == .focus {
            menu.addItem(withTitle: "\(focus.model.profileName): \(focus.model.task)", action: nil, keyEquivalent: "").isEnabled = false
        }
        menu.addItem(.separator())
        add(menu, "Open Dashboard", #selector(openToday), "d")
        add(menu, focus.model.phase == .focus ? "Session Controls…" : "Start a Focus Session…", #selector(startSession), "f")
        add(menu, "Ask AI…", #selector(openAsk), "")
        menu.addItem(.separator())
        if tracker.isPaused {
            add(menu, "Resume Tracking", #selector(resumeTracking), "")
        } else {
            let pause = NSMenuItem(title: "Pause Tracking", action: nil, keyEquivalent: "")
            let submenu = NSMenu()
            add(submenu, "For 15 Minutes", #selector(pause15), "")
            add(submenu, "For an Hour", #selector(pauseHour), "")
            add(submenu, "Until Tomorrow", #selector(pauseTomorrow), "")
            pause.submenu = submenu
            menu.addItem(pause)
        }
        menu.addItem(.separator())
        add(menu, "Quit Ribbon", #selector(quit), "q")
    }

    private func add(_ menu: NSMenu, _ title: String, _ action: Selector, _ key: String) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        menu.addItem(item)
    }

    @objc private func openToday() { openDashboard(.today) }
    @objc private func openAsk() { openDashboard(.ask) }
    @objc private func startSession() { focus.openPanel() }
    @objc private func resumeTracking() { tracker.pausedUntil = nil; update() }
    @objc private func pause15() { tracker.pausedUntil = Date().addingTimeInterval(15 * 60); update() }
    @objc private func pauseHour() { tracker.pausedUntil = Date().addingTimeInterval(3600); update() }
    @objc private func pauseTomorrow() {
        tracker.pausedUntil = Calendar.current.startOfDay(for: Date()).addingTimeInterval(86400 + 6 * 3600)
        update()
    }
    @objc private func quit() { NSApp.terminate(nil) }

    /// A small orb with a timer ring, drawn as a template so it follows the menu bar's color.
    private static let icon: NSImage = {
        let image = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { rect in
            let ring = NSBezierPath()
            ring.appendArc(withCenter: NSPoint(x: 8, y: 8), radius: 6.5, startAngle: 90, endAngle: 90 - 280, clockwise: true)
            ring.lineWidth = 1.6
            ring.lineCapStyle = .round
            NSColor.black.setStroke()
            ring.stroke()
            NSColor.black.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 4.5, dy: 4.5)).fill()
            return true
        }
        image.isTemplate = true
        return image
    }()
}
