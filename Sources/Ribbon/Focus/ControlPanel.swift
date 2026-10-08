import SwiftUI

struct PanelActions {
    var start: @MainActor (String, String) -> Void
    var pause: @MainActor () -> Void
    var resume: @MainActor () -> Void
    var changeFocus: @MainActor (String) -> Void
    var stop: @MainActor (String) -> Void
    var toggleMute: @MainActor () -> Void
    var quit: @MainActor () -> Void
    var close: @MainActor () -> Void
    var openDashboard: @MainActor () -> Void
}

/// What you get when you click the orb. Starting a Pomodoro is easy;
/// pausing, switching focus and stopping take deliberate effort.
struct ControlPanel: View {
    enum Step { case start, menu, pause, change, stop }

    let model: OrbModel
    let profiles: [SessionProfile]
    let actions: PanelActions
    let suggest: (String) async -> String?
    @State private var step: Step
    @State private var text: String
    @State private var profileID: String?
    /// The AI's pick for what you typed; it stops guessing once you pick one yourself.
    @State private var aiPick: String?
    @State private var pickedByHand = false
    @State private var suggestion: Task<Void, Never>?
    @FocusState private var fieldFocused: Bool

    init(model: OrbModel, profiles: [SessionProfile], profileID: String?, actions: PanelActions,
         suggest: @escaping (String) async -> String?) {
        self.model = model
        self.profiles = profiles
        self.actions = actions
        self.suggest = suggest
        let starting = model.phase != .focus
        _step = State(initialValue: starting ? .start : .menu)
        _text = State(initialValue: starting ? model.task : "")
        _profileID = State(initialValue: profileID)
        _pickedByHand = State(initialValue: profileID != nil && profileID != profiles.first?.id)
    }

    private var selected: SessionProfile? { profiles.first { $0.id == profileID } ?? profiles.first }

    private var entered: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            content(now: context.date)
                .frame(width: 368, alignment: .leading)
                .padding(16)
                .background(Bubble(cornerRadius: 22))
        }
        .foregroundStyle(.white)
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        .environment(\.colorScheme, .dark)
        .onExitCommand {
            if step == .start || step == .menu { actions.close() } else { go(.menu) }
        }
    }

    @ViewBuilder private func content(now: Date) -> some View {
        switch step {
        case .start: startStep
        case .menu: if model.paused { pausedMenu(now) } else { focusMenu(now) }
        case .pause: pauseStep(now)
        case .change: changeStep
        case .stop: stopStep(now)
        }
    }

    // MARK: Steps

    private var startStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                TextField("What are you working on?", text: $text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .focused($fieldFocused)
                    .onSubmit { if !entered.isEmpty, let selected { actions.start(entered, selected.id) } }
                    .onChange(of: text) { askForSuggestion() }
                Text("↩︎ \(selected?.focusMinutes ?? 25) min")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.45))
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(profiles) { profile in
                        Button {
                            profileID = profile.id
                            pickedByHand = true
                        } label: {
                            HStack(spacing: 5) {
                                Text(profile.emoji)
                                Text(profile.name)
                                if aiPick == profile.id && !pickedByHand {
                                    Image(systemName: "sparkles").font(.system(size: 9, weight: .bold))
                                }
                            }
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .padding(.horizontal, 10)
                            .frame(height: 26)
                            .background(Capsule().fill(.white.opacity(profile.id == selected?.id ? 0.22 : 0.07)))
                            .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            if let selected {
                note(selected.rulesSummary + (aiPick == selected.id && !pickedByHand ? " · picked by AI for this task" : ""))
            }
            Rectangle().fill(.white.opacity(0.08)).frame(height: 1)
            HStack(spacing: 14) {
                Toggle("Mute voice", isOn: Binding(get: { model.muted }, set: { _ in actions.toggleMute() }))
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                Spacer()
                Button("Dashboard", action: actions.openDashboard)
                    .buttonStyle(.plain)
                Button("Quit", action: actions.quit)
                    .buttonStyle(.plain)
            }
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .foregroundStyle(.white.opacity(0.55))
        }
        .onAppear(perform: focusField)
    }

    private func focusMenu(_ now: Date) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            header(model.profileName.isEmpty ? "FOCUSING ON" : model.profileName.uppercased(),
                   trailing: "\(clock(model.timeLeft(at: now))) left")
            Text(model.task)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .lineLimit(2)
            HStack(spacing: 8) {
                PanelButton("Pause", systemImage: "pause.fill", enabled: model.pauseLeft(at: now) >= 1) { go(.pause) }
                PanelButton("Change focus", systemImage: "arrow.triangle.swap") { go(.change) }
                PanelButton("Stop", systemImage: "stop.fill") { go(.stop) }
            }
            note(model.pauseLeft(at: now) >= 1
                 ? "Each of these takes a long press. On purpose."
                 : "You've used up this Pomodoro's pause time.")
        }
    }

    private func pausedMenu(_ now: Date) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            header("PAUSED", trailing: "\(clock(model.pauseLeft(at: now))) of pause left")
            Text(model.task)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .lineLimit(2)
            HStack(spacing: 8) {
                PanelButton("Resume", systemImage: "play.fill", prominent: true, action: actions.resume)
                PanelButton("Stop", systemImage: "stop.fill") { go(.stop) }
            }
            note("\(clock(model.timeLeft(at: now))) to go. When the pause runs out I start watching again by myself.")
        }
    }

    private func pauseStep(_ now: Date) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            title("Pause this Pomodoro?")
            note("The clock stops and I stop watching. You have \(clock(model.pauseLeft(at: now))) of pause left in this Pomodoro; when it runs out, I start again by myself.")
            HoldButton(title: "Hold to pause", seconds: 3, tint: Color(hex: 0xFFB35C), action: actions.pause)
            backButton
        }
    }

    private var changeStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            title("Switch your focus")
            field("What are you working on now?")
            note("The clock keeps running. From now on I'll judge you against the new task.")
            HoldButton(title: "Hold to switch", seconds: 3, tint: Color(hex: 0x5AA9FF),
                       enabled: !entered.isEmpty && entered != model.task) { actions.changeFocus(entered) }
            backButton
        }
    }

    private func stopStep(_ now: Date) -> some View {
        let words = entered.split(whereSeparator: \.isWhitespace).count
        return VStack(alignment: .leading, spacing: 12) {
            title("Stop this Pomodoro?")
            note("\(clock(model.timeLeft(at: now))) left on the clock. What's making you stop?")
            field("A real reason, a few words at least")
            HoldButton(title: words >= 3 ? "Hold 5 seconds to stop" : "Give a reason first", seconds: 5,
                       tint: Color(hex: 0xFF4D5E), enabled: words >= 3) { actions.stop(entered) }
            backButton
        }
    }

    // MARK: Pieces

    private func askForSuggestion() {
        suggestion?.cancel()
        guard !pickedByHand, entered.count >= 4 else { return }
        let task = entered
        suggestion = Task {
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled, let id = await suggest(task), !Task.isCancelled, !pickedByHand else { return }
            withAnimation(.easeOut(duration: 0.2)) {
                aiPick = id
                profileID = id
            }
        }
    }

    private func go(_ next: Step) {
        text = ""
        withAnimation(.easeOut(duration: 0.18)) { step = next }
        if next == .change || next == .stop { focusField() }
    }

    private func focusField() {
        Task { @MainActor in fieldFocused = true }
    }

    private func header(_ label: String, trailing: String) -> some View {
        HStack {
            Text(label).tracking(0.8)
            Spacer()
            Text(trailing).monospacedDigit()
        }
        .font(.system(size: 11, weight: .semibold, design: .rounded))
        .foregroundStyle(.white.opacity(0.5))
    }

    private func title(_ text: String) -> some View {
        Text(text).font(.system(size: 16, weight: .semibold, design: .rounded))
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .foregroundStyle(.white.opacity(0.55))
            .fixedSize(horizontal: false, vertical: true)
    }

    private func field(_ placeholder: String) -> some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .font(.system(size: 14, weight: .medium, design: .rounded))
            .focused($fieldFocused)
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white.opacity(0.08)))
    }

    private var backButton: some View {
        Button { go(.menu) } label: {
            Label("Back", systemImage: "chevron.left")
        }
        .buttonStyle(.plain)
        .font(.system(size: 12, weight: .medium, design: .rounded))
        .foregroundStyle(.white.opacity(0.5))
    }
}

struct PanelButton: View {
    let title: String
    let systemImage: String
    var prominent = false
    var enabled = true
    let action: () -> Void

    init(_ title: String, systemImage: String, prominent: Bool = false, enabled: Bool = true, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.prominent = prominent
        self.enabled = enabled
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .frame(height: 32)
                .background(Capsule().fill(.white.opacity(prominent ? 0.22 : 0.09)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
    }
}

/// A button that only fires after being held down for `seconds`, filling up as you hold.
struct HoldButton: View {
    let title: String
    let seconds: Double
    let tint: Color
    var enabled = true
    let action: () -> Void
    @State private var progress: CGFloat = 0
    @State private var holding = false
    @State private var holdTask: Task<Void, Never>?

    var body: some View {
        Text(holding ? "Keep holding…" : title)
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .frame(maxWidth: .infinity)
            .frame(height: 38)
            .background {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.09))
                        Capsule().fill(tint.opacity(0.85)).frame(width: geo.size.width * progress)
                    }
                }
            }
            .clipShape(Capsule())
            .contentShape(Capsule())
            .opacity(enabled ? 1 : 0.4)
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard enabled, !holding else { return }
                    holding = true
                    withAnimation(.linear(duration: seconds)) { progress = 1 }
                    holdTask = Task { @MainActor in
                        try? await Task.sleep(for: .seconds(seconds))
                        if !Task.isCancelled { action() }
                    }
                }
                .onEnded { _ in
                    holdTask?.cancel()
                    holdTask = nil
                    holding = false
                    withAnimation(.easeOut(duration: 0.25)) { progress = 0 }
                })
    }
}
