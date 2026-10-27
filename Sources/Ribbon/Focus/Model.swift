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
    var toastSymbol = "hand.raised.fill"
    var phaseStart = Date()
    var phaseEnd = Date()
    /// Set while a focus session is paused; the clock stands still.
    var pausedAt: Date?
    /// Pause time left in this Pomodoro, not counting the pause in progress.
    var pauseBudget: TimeInterval = 0
    /// The end of the scheduled window this session belongs to.
    var scheduledUntil: Date?
    var nudging = false
    var nudgeText: String?
    var hovering = false
    /// The orb is being held down to wave off a nudge.
    var holding = false
    var panelOpen = false
    /// Where you dragged the small orb, as fractions of the screen from its top-left; nil keeps it in the corner.
    var anchor: CGPoint?
    /// The orb is being dragged; its label stays out of the way meanwhile.
    var dragging = false
    /// The orb's window is on screen. While it isn't, the orb doesn't animate.
    var visible = false
    var muted = false
    /// A problem worth showing on hover, like a missing permission or a failing API.
    var status: String?
    /// Shown on hover while the browser in front can't be read, so its sites can't be blocked.
    var browserProblem: String?

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

    /// How close a dragged orb's ring may come to the screen's edge.
    static let edge: CGFloat = 6

    /// In the overlay's coordinates (origin top-left). The small orb sits where you left it (`anchor`, as fractions
    /// of the screen), or in the bottom-right corner; a nudge always brings it to the middle.
    static func center(in size: CGSize, nudging: Bool, anchor: CGPoint? = nil) -> CGPoint {
        if nudging { return CGPoint(x: size.width / 2, y: size.height * 0.4) }
        let radius = ringDiameter(smallCore) / 2
        guard let anchor else { return CGPoint(x: size.width - margin - radius, y: size.height - margin - radius) }
        return clamp(CGPoint(x: anchor.x * size.width, y: anchor.y * size.height), in: size)
    }

    /// Keeps the small orb's whole ring on screen.
    static func clamp(_ point: CGPoint, in size: CGSize) -> CGPoint {
        let inset = edge + ringDiameter(smallCore) / 2
        return CGPoint(x: min(max(point.x, inset), max(inset, size.width - inset)),
                       y: min(max(point.y, inset), max(inset, size.height - inset)))
    }

    /// The anchor for a small orb centered at `point`, both in the overlay's coordinates.
    static func anchor(for point: CGPoint, in size: CGSize) -> CGPoint {
        let clamped = clamp(point, in: size)
        return CGPoint(x: clamped.x / max(size.width, 1), y: clamped.y / max(size.height, 1))
    }

    /// Labels and toasts sit to the orb's left unless there isn't room, then to its right.
    static func labelOnLeft(center: CGPoint, width: CGFloat = 340) -> Bool {
        center.x - ringDiameter(smallCore) / 2 - 12 - width >= 0
    }

    /// The orb's controls grow up and to the left from beside it, or the other way where the screen runs out.
    /// `orb` and `screen` are in screen coordinates (origin bottom-left).
    static func panelFrame(orb: CGPoint, size: CGSize, screen: CGRect) -> (frame: CGRect, alignment: Alignment) {
        let radius = ringDiameter(smallCore) / 2
        var x = orb.x - radius - 4 - size.width, y = orb.y - 41
        let right = x < screen.minX, down = y + size.height > screen.maxY
        if right { x = orb.x + radius + 4 }
        if down { y = orb.y + 41 - size.height }
        x = min(max(x, screen.minX), screen.maxX - size.width)
        y = min(max(y, screen.minY), screen.maxY - size.height)
        let alignment: Alignment = down ? (right ? .topLeading : .topTrailing) : (right ? .bottomLeading : .bottomTrailing)
        return (CGRect(x: x, y: y, width: size.width, height: size.height), alignment)
    }
}
