import DeviceActivity
import Foundation

/// iOS wakes this at a schedule's start and end, when a session's focus part or pause runs out, and when distracting
/// apps pass a time mark, even with Ribbon closed. It does what the app would: Engine works out what should be running.
final class Monitor: DeviceActivityMonitor {
    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        Engine.intervalChanged(activity)
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        Engine.intervalChanged(activity)
    }

    override func eventDidReachThreshold(_ event: DeviceActivityEvent.Name, activity: DeviceActivityName) {
        super.eventDidReachThreshold(event, activity: activity)
        guard let minutes = Engine.reached(event, in: activity), SharedStore.checkIns else { return }
        checkIn(minutes: minutes)
    }

    /// A check-in notification, in Ribbon's own words. It's written on the phone: Apple's terms keep Screen Time
    /// numbers from going anywhere else, the AI included.
    private func checkIn(minutes: Int) {
        let line = AI.plainCheckIn(minutes: minutes, task: SharedStore.active?.task, tone: SharedStore.tone)
        Engine.notify("Check-in", line, id: "checkin.\(minutes)")
    }
}
