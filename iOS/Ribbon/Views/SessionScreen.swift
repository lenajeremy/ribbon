import SwiftUI

/// Starting a session: what you're working on, and which session type. Starting is easy; stopping isn't.
struct StartSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var task = ""
    @State private var profileID: String?
    @FocusState private var typing: Bool

    private var selected: SessionProfile? {
        model.profiles.first { $0.id == (profileID ?? model.startProfileID) } ?? model.profiles.first
    }

    private var entered: String { task.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetHeader(title: "Start a focus session") { dismiss() }
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("What are you working on?").font(.system(size: 15, weight: .medium))
                    TextField("Ship the iOS release", text: $task)
                        .fieldStyle()
                        .focused($typing)
                        .submitLabel(.go)
                        .onSubmit(start)
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text("Session type").font(.system(size: 15, weight: .medium))
                    FlowLayout(spacing: 8) {
                        ForEach(model.profiles) { profile in
                            Chip(text: "\(profile.emoji) \(profile.name)", selected: profile.id == selected?.id) {
                                profileID = profile.id
                            }
                        }
                    }
                    if let selected {
                        Text("\(selected.focusMinutes) min of focus, then \(selected.breakMinutes == 0 ? "no break" : "a \(selected.breakMinutes) min break"). \(selected.rulesSummary)")
                            .font(Typeface.caption).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
                Button("Start", action: start)
                    .buttonStyle(PillButtonStyle(primary: true, large: true))
                    .disabled(entered.isEmpty || selected == nil)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 16)
        }
        .background(Theme.page)
        .presentationDetents([.medium, .large])
        .presentationCornerRadius(28)
        .onAppear { typing = true }
    }

    private func start() {
        guard let selected, !entered.isEmpty else { return }
        dismiss()
        model.start(selected, task: entered)
    }
}

/// The running session, full screen: the orb with its countdown ring, the task, the clock, and the controls the
/// session allows. A scheduled session has none: only the emergency pass in Settings ends it early.
struct SessionScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var asking: SessionAsk?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                RoundButton(symbol: "chevron.down", label: "Close") { dismiss() }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)

            if let session = model.active {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    content(session, now: context.date)
                }
            } else {
                Spacer()
                Text("No session running.").font(Typeface.body).foregroundStyle(Theme.muted)
                Spacer()
            }
        }
        .background(Theme.page)
        .sheet(item: $asking) { ConfirmSessionAction(ask: $0) }
    }

    @ViewBuilder private func content(_ session: ActiveSession, now: Date) -> some View {
        let total = max(1, session.phaseEnd.timeIntervalSince(session.phaseStart))
        let left = session.timeLeft(at: now)
        let palette: OrbPalette = session.paused ? .paused : session.phase == .rest ? .rest : .focus
        VStack(spacing: 0) {
            Spacer(minLength: 12)
            SessionOrb(palette: palette, remaining: left / total, size: 220, breathing: !session.paused)
            VStack(spacing: 8) {
                Text("\(session.profile.emoji) \(session.profile.name) · \(session.status)")
                    .font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.muted)
                Text(session.task).font(.system(size: 24, weight: .semibold)).multilineTextAlignment(.center)
                    .lineLimit(3).foregroundStyle(Theme.ink)
            }
            .padding(.top, 34)
            .padding(.horizontal, 28)
            VStack(spacing: 6) {
                Text(clock(left)).font(.system(size: 56, weight: .semibold)).monospacedDigit().foregroundStyle(Theme.ink)
                    .contentTransition(.numericText(countsDown: true))
                Text(leftLabel(session, now: now, done: total - left, total: total))
                    .font(.system(size: 14)).foregroundStyle(Theme.muted).monospacedDigit()
                    .multilineTextAlignment(.center)
                if let window = session.window {
                    Text("Scheduled \(Format.time(window.start))–\(Format.time(window.end)) · \(Format.duration(now.timeIntervalSince(window.start))) done, \(Format.duration(window.end.timeIntervalSince(now))) left")
                        .font(Typeface.caption).foregroundStyle(Theme.muted).monospacedDigit().padding(.top, 4)
                }
            }
            .padding(.top, 22)
            Spacer(minLength: 12)
            controls(session)
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
        }
    }

    private func leftLabel(_ session: ActiveSession, now: Date, done: TimeInterval, total: TimeInterval) -> String {
        if session.paused { return "left · paused, \(clock(session.pauseLeft(at: now))) of pause left" }
        if session.phase == .rest { return "left in this break" }
        return "left · \(Int(done / 60)) of \(Int((total / 60).rounded())) min done"
    }

    @ViewBuilder private func controls(_ session: ActiveSession) -> some View {
        if let window = session.window {
            Text("The rules stay on until \(Format.time(window.end)), breaks included.")
                .font(Typeface.row).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
                .frame(maxWidth: .infinity).frame(height: 50)
        } else if session.phase == .rest {
            Button("End break") { model.endBreak() }.buttonStyle(PillButtonStyle(large: true))
        } else if session.paused {
            HStack(spacing: 10) {
                Button("Resume") { model.resume() }.buttonStyle(PillButtonStyle(primary: true, large: true))
                Button("End") { asking = .end }.buttonStyle(PillButtonStyle(destructive: true, large: true))
            }
        } else {
            HStack(spacing: 10) {
                Button("Pause") { asking = .pause }.buttonStyle(PillButtonStyle(large: true)).disabled(!session.canPause)
                Button("End") { asking = .end }.buttonStyle(PillButtonStyle(destructive: true, large: true))
            }
        }
    }
}

enum SessionAsk: String, Identifiable {
    case pause, end, pass
    var id: String { rawValue }
}

/// Pausing or ending, the same effort as at the desktop's orb: pausing is a 3-second hold; ending takes a reason and
/// a 5-second hold. The emergency pass takes the same, for a scheduled session.
struct ConfirmSessionAction: View {
    let ask: SessionAsk
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var reason = ""

    private var words: Int { reason.split(whereSeparator: \.isWhitespace).count }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SheetHeader(title: title) { dismiss() }.padding(.horizontal, -20)
            Text(detail).font(Typeface.row).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
            if ask != .pause {
                TextField("A real reason, a few words at least", text: $reason).fieldStyle()
            }
            switch ask {
            case .pause:
                HoldButton(title: "Hold to pause", seconds: 3, tint: Theme.pause) { model.pause(); dismiss() }
            case .end:
                HoldButton(title: words >= 3 ? "Hold 5 seconds to end" : "Give a reason first", seconds: 5,
                           tint: Theme.distracting, enabled: words >= 3) {
                    model.stop(reason: reason.trimmingCharacters(in: .whitespacesAndNewlines)); dismiss()
                }
            case .pass:
                HoldButton(title: words >= 3 ? "Hold 5 seconds to end" : "Give a reason first", seconds: 5,
                           tint: Theme.distracting, enabled: words >= 3 && model.passNote.available) {
                    model.useEmergencyPass(reason: reason.trimmingCharacters(in: .whitespacesAndNewlines)); dismiss()
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .background(Theme.page)
        .presentationDetents([.height(ask == .pause ? 260 : 340)])
        .presentationCornerRadius(28)
        .onChange(of: model.active?.recordID) { dismiss() }
    }

    private var title: String {
        switch ask {
        case .pause: "Pause this session?"
        case .end: "End this session?"
        case .pass: "End today's scheduled session?"
        }
    }

    private var detail: String {
        let now = Date()
        switch ask {
        case .pause:
            let left = model.active?.pauseLeft(at: now) ?? 0
            return "The clock stops and blocking lifts. You have \(clock(left)) of pause left; when it runs out, the session carries on by itself."
        case .end:
            return "\(clock(model.active?.timeLeft(at: now) ?? 0)) left on the clock. What's making you stop?"
        case .pass:
            return "This uses this week's emergency pass, and you get a new one next Monday. What's making you stop?"
        }
    }
}
