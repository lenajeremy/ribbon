import Foundation
import UserNotifications

/// Reminds you to step away after a long stretch of work (outside focus sessions, which have their own breaks).
@MainActor final class BreakCoach {
    private let tracker: ActivityTracker
    private let settings: Settings
    private let isFocusing: () -> Bool
    private var lastReminder = Date.distantPast

    init(tracker: ActivityTracker, settings: Settings, isFocusing: @escaping () -> Bool) {
        self.tracker = tracker
        self.settings = settings
        self.isFocusing = isFocusing
    }

    func start() {
        let timer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.check() } }
        RunLoop.main.add(timer, forMode: .common)
    }

    private func check() {
        guard settings.breakReminders, !isFocusing(), !tracker.isAway, let streak = tracker.streakStart else { return }
        let worked = Date().timeIntervalSince(streak)
        guard worked >= settings.breakInterval, Date().timeIntervalSince(lastReminder) >= 20 * 60 else { return }
        lastReminder = Date()
        Notifier.post(title: "Time for a break",
                      body: "You've been at it for \(Format.duration(worked)) straight. Step away for five minutes.")
        logLine("Break reminder after \(Format.duration(worked))")
    }
}

enum Notifier {
    static func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            if !granted { logLine("Notifications not allowed") }
        }
    }

    static func post(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }
}
