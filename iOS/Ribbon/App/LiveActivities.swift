import ActivityKit
import Foundation

/// Keeps the Lock Screen and Dynamic Island in step with the running session. A scheduled session shows its whole
/// window counting down, which stays right with Ribbon closed; a manual one shows its focus part or break.
enum LiveActivities {
    @MainActor static func sync(_ session: ActiveSession?) {
        let current = Activity<SessionActivityAttributes>.activities
        guard let session else {
            for activity in current { Task { await activity.end(nil, dismissalPolicy: .immediate) } }
            return
        }
        let now = Date()
        let state = SessionActivityAttributes.ContentState(
            phase: session.isScheduled ? "focus" : session.phase.rawValue,
            phaseStart: session.window?.start ?? session.phaseStart,
            phaseEnd: session.window?.end ?? session.phaseEnd,
            pausedLeft: session.paused ? session.timeLeft(at: now) : nil,
            pauseEnds: session.pausedAt.map { $0.addingTimeInterval(session.pauseBudget) },
            scheduledUntil: session.window?.end,
            task: session.task)
        let content = ActivityContent(state: state, staleDate: session.paused ? nil : state.phaseEnd)
        if let match = current.first(where: { $0.attributes.recordID == session.recordID }) {
            if match.content.state != state { Task { await match.update(content) } }
            for other in current where other.id != match.id { Task { await other.end(nil, dismissalPolicy: .immediate) } }
            return
        }
        for other in current { Task { await other.end(nil, dismissalPolicy: .immediate) } }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let attributes = SessionActivityAttributes(recordID: session.recordID, profileName: session.profile.name,
                                                   emoji: session.profile.emoji)
        do {
            _ = try Activity.request(attributes: attributes, content: content, pushType: nil)
        } catch {
            log.error("Live Activity: \(error.localizedDescription)")
        }
    }
}
