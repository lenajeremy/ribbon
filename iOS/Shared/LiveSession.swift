import ActivityKit
import Foundation

/// The running session on the Lock Screen and in the Dynamic Island.
struct SessionActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// "focus" or "rest".
        var phase: String
        var phaseStart: Date
        var phaseEnd: Date
        /// The time left on the clock while paused, when it stands still.
        var pausedLeft: TimeInterval?
        var pauseEnds: Date?
        var scheduledUntil: Date?
        var task: String

        var status: String {
            if pausedLeft != nil { return "Paused" }
            if scheduledUntil != nil { return "Scheduled" }
            if phase == "rest" { return scheduledUntil == nil ? "On a break" : "On a break · rules stay on" }
            return "Focusing"
        }
    }

    var recordID: String
    var profileName: String
    var emoji: String
}
