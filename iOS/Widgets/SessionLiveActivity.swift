import ActivityKit
import SwiftUI
import WidgetKit

@main
struct RibbonWidgets: WidgetBundle {
    var body: some Widget {
        SessionLiveActivity()
    }
}

/// The running session where you'll see it without opening Ribbon: the orb, the session type, the task and a
/// countdown on the Lock Screen; the orb and the time in the Dynamic Island.
struct SessionLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SessionActivityAttributes.self) { context in
            LockScreenView(attributes: context.attributes, state: context.state)
                .widgetURL(URL(string: "ribbon://session"))
                .activityBackgroundTint(Theme.page)
                .activitySystemActionForegroundColor(Theme.ink)
        } dynamicIsland: { context in
            let state = context.state
            let palette = OrbPalette.of(phase: state.phase, paused: state.pausedLeft != nil)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 8) {
                        OrbSphere(palette: palette, size: 22)
                        Text("\(context.attributes.emoji) \(context.attributes.profileName)")
                            .font(.system(size: 14, weight: .semibold)).lineLimit(1)
                    }
                    .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Countdown(state: state).font(.system(size: 22, weight: .semibold)).padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(state.status) · \(state.task)").font(.system(size: 13)).foregroundStyle(.secondary).lineLimit(1)
                        Progress(state: state, palette: palette, track: .white.opacity(0.18))
                    }
                    .padding(.horizontal, 4)
                }
            } compactLeading: {
                OrbSphere(palette: palette, size: 18)
            } compactTrailing: {
                Countdown(state: state).font(.system(size: 14, weight: .semibold)).frame(maxWidth: 56)
            } minimal: {
                OrbSphere(palette: palette, size: 18)
            }
        }
    }
}

private struct LockScreenView: View {
    let attributes: SessionActivityAttributes
    let state: SessionActivityAttributes.ContentState

    var body: some View {
        let palette = OrbPalette.of(phase: state.phase, paused: state.pausedLeft != nil)
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                OrbSphere(palette: palette, size: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(attributes.emoji) \(attributes.profileName) · \(state.status)")
                        .font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.muted).lineLimit(1)
                    Text(state.task).font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.ink).lineLimit(1)
                }
                Spacer(minLength: 8)
                Countdown(state: state).font(.system(size: 28, weight: .semibold)).foregroundStyle(Theme.ink)
            }
            Progress(state: state, palette: palette, track: Theme.track)
            if let until = state.scheduledUntil {
                Text("The rules stay on until \(Format.time(until)).")
                    .font(.system(size: 12)).foregroundStyle(Theme.muted)
            }
        }
        .padding(16)
    }
}

/// The time left in this part, counting down by itself; standing still while paused.
private struct Countdown: View {
    let state: SessionActivityAttributes.ContentState

    var body: some View {
        Group {
            if let left = state.pausedLeft {
                Text(clock(left))
            } else {
                Text(timerInterval: state.phaseStart...max(state.phaseStart, state.phaseEnd), countsDown: true)
            }
        }
        .monospacedDigit()
        .multilineTextAlignment(.trailing)
    }
}

private struct Progress: View {
    let state: SessionActivityAttributes.ContentState
    let palette: OrbPalette
    let track: Color

    var body: some View {
        let tint = state.phase == "rest" ? Theme.series(3) : Theme.productive
        Group {
            if let left = state.pausedLeft {
                let total = max(1, state.phaseEnd.timeIntervalSince(state.phaseStart))
                ProgressView(value: min(1, max(0, 1 - left / total)))
            } else {
                ProgressView(timerInterval: state.phaseStart...max(state.phaseStart, state.phaseEnd), countsDown: false) {
                    EmptyView()
                } currentValueLabel: {
                    EmptyView()
                }
            }
        }
        .progressViewStyle(.linear)
        .tint(tint)
        .background(Capsule().fill(track).frame(height: 4))
    }
}
