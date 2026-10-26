import SwiftUI

/// The session running now, at the top of Today: what it is, a live countdown with how much is done, and the
/// controls the session allows. Pausing and ending take the same effort as at the orb. A scheduled session gets no
/// controls here: the emergency pass is kept in Settings, out of sight while you work.
struct SessionCard: View {
    let focus: FocusController
    @State private var asking: Ask?

    enum Ask: String, Identifiable {
        case pause, end
        var id: String { rawValue }
    }

    var body: some View {
        let orb = focus.model
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let now = context.date
            let total = max(1, orb.phaseEnd.timeIntervalSince(orb.phaseStart))
            let left = orb.timeLeft(at: now)
            let done = max(0, total - left)
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(orb.profileName) · \(status)").font(.system(size: 12.5, weight: .medium)).foregroundStyle(Theme.muted)
                        Text(orb.task).font(.system(size: 17, weight: .semibold)).lineLimit(1)
                    }
                    Spacer(minLength: 12)
                    buttons
                }
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(clock(left)).font(.system(size: 30, weight: .semibold)).monospacedDigit()
                        Text(leftLabel(now)).font(.system(size: 13)).foregroundStyle(Theme.muted)
                        Spacer()
                        Text("\(Int(done / 60)) of \(Int((total / 60).rounded())) min done")
                            .font(Typeface.caption).foregroundStyle(Theme.muted).monospacedDigit()
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Theme.track)
                            Capsule().fill(orb.phase == .rest ? Theme.series(3) : Theme.productive)
                                .frame(width: geo.size.width * min(1, done / total))
                        }
                    }
                    .frame(height: 6)
                }
                if let window = focus.window {
                    Text("Scheduled \(window.schedule.timesText) · \(Format.duration(now.timeIntervalSince(window.start))) done, "
                         + "\(Format.duration(window.end.timeIntervalSince(now))) left")
                        .font(Typeface.caption).foregroundStyle(Theme.muted).monospacedDigit()
                }
            }
            .padding(18)
            .background(Theme.subtle, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.hairline))
        }
        .sheet(item: $asking) { ask in
            ConfirmSessionAction(ask: ask, focus: focus) { asking = nil }
        }
    }

    private var status: String {
        let orb = focus.model
        if orb.paused { return "Paused" }
        if orb.phase == .rest { return focus.window != nil ? "On a break · rules stay on" : "On a break" }
        return "Focusing"
    }

    private func leftLabel(_ now: Date) -> String {
        let orb = focus.model
        if orb.paused { return "left · paused, \(clock(orb.pauseLeft(at: now))) of pause left" }
        if orb.phase == .rest { return "left in this break" }
        return focus.window != nil ? "left in this focus part" : "left"
    }

    @ViewBuilder private var buttons: some View {
        let orb = focus.model
        HStack(spacing: 8) {
            if focus.window != nil {
                EmptyView()
            } else if orb.phase == .rest {
                Button("End break") { focus.endBreak() }.buttonStyle(PillButtonStyle())
            } else if orb.paused {
                Button("Resume") { focus.resume() }.buttonStyle(PillButtonStyle(primary: true))
                Button("End") { asking = .end }.buttonStyle(PillButtonStyle(destructive: true))
            } else {
                if focus.canPause {
                    Button("Pause") { asking = .pause }.buttonStyle(PillButtonStyle())
                }
                Button("End") { asking = .end }.buttonStyle(PillButtonStyle(destructive: true))
            }
        }
    }
}

/// Pausing or ending from the dashboard: the same reason and hold as at the orb.
struct ConfirmSessionAction: View {
    let ask: SessionCard.Ask
    let focus: FocusController
    let close: () -> Void
    @State private var reason = ""

    private var words: Int { reason.split(whereSeparator: \.isWhitespace).count }

    var body: some View {
        let orb = focus.model
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(Typeface.heading)
            Text(detail).font(.system(size: 13)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
            if ask != .pause {
                TextField("A real reason, a few words at least", text: $reason)
                    .textFieldStyle(.plain).font(.system(size: 14))
                    .padding(.horizontal, 12).frame(height: 34)
                    .background(Theme.bubble, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            switch ask {
            case .pause:
                HoldButton(title: "Hold to pause", seconds: 3, tint: Color(hex: 0xFFB35C), track: Theme.bubble) {
                    focus.pause(); close()
                }
            case .end:
                HoldButton(title: words >= 3 ? "Hold 5 seconds to end" : "Give a reason first", seconds: 5,
                           tint: Theme.distracting, enabled: words >= 3, track: Theme.bubble) {
                    focus.stop(reason: reason.trimmingCharacters(in: .whitespacesAndNewlines)); close()
                }
            }
            HStack {
                Spacer()
                Button("Cancel", action: close).buttonStyle(PillButtonStyle()).keyboardShortcut(.cancelAction)
            }
            .padding(.top, 2)
        }
        .padding(22)
        .frame(width: 420)
        .background(Theme.page)
        .foregroundStyle(Theme.ink)
        .onChange(of: orb.phase) { close() }
    }

    private var title: String {
        switch ask {
        case .pause: "Pause this session?"
        case .end: "End this session?"
        }
    }

    private var detail: String {
        let orb = focus.model
        switch ask {
        case .pause:
            return "The clock stops and the orb stops watching. You have \(clock(orb.pauseLeft(at: Date()))) of pause left; "
                + "when it runs out, the session carries on by itself."
        case .end:
            return "\(clock(orb.timeLeft(at: Date()))) left on the clock. What's making you stop?"
        }
    }
}
