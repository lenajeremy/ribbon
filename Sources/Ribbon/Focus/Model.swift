import SwiftUI

enum Phase: Equatable {
    case idle, focus, rest
}

/// Everything the orb's views draw from.
@Observable @MainActor final class OrbModel {
    var phase: Phase = .idle
    var task = ""
    /// The running session type, like "💻 Coding".
    var profileName = ""
    /// A short message by the orb, like what was just blocked.
    var toast: String?
    var phaseStart = Date()
    var phaseEnd = Date()
    /// Set while a focus session is paused; the clock stands still.
    var pausedAt: Date?
    /// Pause time left in this Pomodoro, not counting the pause in progress.
    var pauseBudget: TimeInterval = 0
    var nudging = false
    var nudgeText: String?
    var hovering = false
    /// The orb is being held down to wave off a nudge.
    var holding = false
    var panelOpen = false
    /// The orb's window is on screen. While it isn't, the orb doesn't animate.
    var visible = false
    var muted = false
    /// A problem worth showing on hover, like a missing permission or a failing API.
    var status: String?

    var paused: Bool { pausedAt != nil }

    func timeLeft(at date: Date) -> TimeInterval {
        max(0, phaseEnd.timeIntervalSince(pausedAt ?? date))
    }

    func pauseLeft(at date: Date) -> TimeInterval {
        max(0, pauseBudget - (pausedAt.map { date.timeIntervalSince($0) } ?? 0))
    }
}

func clock(_ seconds: TimeInterval) -> String {
    let whole = Int(seconds.rounded())
    return String(format: "%d:%02d", whole / 60, whole % 60)
}

/// Where the orb sits and how big it is, shared by the view and the hit-testing in the controller.
enum OrbLayout {
    static let smallCore: CGFloat = 44
    static let bigCore: CGFloat = 220
    static let margin: CGFloat = 22

    static func core(nudging: Bool) -> CGFloat { nudging ? bigCore : smallCore }

    static func ringDiameter(_ core: CGFloat) -> CGFloat { core * 1.42 }

    /// In the overlay's coordinates (origin top-left).
    static func center(in size: CGSize, nudging: Bool) -> CGPoint {
        if nudging { return CGPoint(x: size.width / 2, y: size.height * 0.4) }
        let radius = ringDiameter(smallCore) / 2
        return CGPoint(x: size.width - margin - radius, y: size.height - margin - radius)
    }
}
