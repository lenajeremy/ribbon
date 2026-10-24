import AppKit
import ApplicationServices
import AVFoundation
import SwiftUI

/// Settings as a modal with a list of sections on the left, like ChatGPT's: each row is a name,
/// a gray line saying what it does, and the control on the right.
struct SettingsView: View {
    let model: DashboardModel
    @State private var pane: Pane = .general
    @State private var newKey = ""
    @State private var keySaved = false
    @State private var confirmDelete = false
    @State private var refresh = 0
    /// Bumped when the ChatGPT sign-in changes, so the rows that depend on it update (without resetting the sign-in row).
    @State private var planChanges = 0
    @Environment(\.dismiss) private var dismiss

    enum Pane: String, CaseIterable, Identifiable {
        case general = "General", tracking = "Tracking", breaks = "Breaks", permissions = "Permissions", ai = "AI", data = "Data"
        var id: String { rawValue }
        var symbol: String {
            switch self {
            case .general: "gearshape"
            case .tracking: "waveform.path.ecg"
            case .breaks: "cup.and.saucer"
            case .permissions: "lock"
            case .ai: "sparkles"
            case .data: "externaldrive"
            }
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Button { dismiss() } label: { Image(systemName: "xmark").font(.system(size: 12, weight: .semibold)) }
                    .buttonStyle(.plain).foregroundStyle(Theme.muted).padding(.bottom, 14).padding(.leading, 8)
                    .keyboardShortcut(.cancelAction)
                ForEach(Pane.allCases) { item in
                    Button { pane = item } label: {
                        Label(item.rawValue, systemImage: item.symbol)
                            .font(.system(size: 13))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 10).frame(height: 30)
                            .background(pane == item ? Theme.bubble : .clear, in: RoundedRectangle(cornerRadius: 8))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .padding(14)
            .frame(width: 190)
            .background(Theme.subtle)

            VStack(alignment: .leading, spacing: 0) {
                Text(pane.rawValue).font(Typeface.heading).padding(.bottom, 10)
                Rectangle().fill(Theme.hairline).frame(height: 1)
                ScrollView { VStack(spacing: 0) { rows } }
            }
            .padding(.horizontal, 24)
            .padding(.top, 22)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 720, height: 500)
        .onAppear { pane = Pane(rawValue: model.settingsPane) ?? .general; model.settingsPane = Pane.general.rawValue }
        .background(Theme.page)
        .id(refresh)
        .alert("Delete all tracked data?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) { model.store.deleteAllData(); model.refresh() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your timeline, sessions, chats about your time, reviews and category choices are removed from this Mac. Session types stay.")
        }
    }

    @ViewBuilder private var rows: some View {
        @Bindable var settings = model.settings
        switch pane {
        case .general:
            SettingRow("Open at login", "Start Ribbon when you log in, so tracking never misses a day.") {
                Toggle("", isOn: Binding(get: { settings.launchAtLogin }, set: { settings.launchAtLogin = $0; refresh += 1 }))
                    .toggleStyle(.switch).labelsHidden()
            }
            SettingRow("Show the orb when idle", "Keep the orb in the corner when no focus session is running.") {
                Toggle("", isOn: $settings.showOrbWhenIdle).toggleStyle(.switch).labelsHidden()
                    .onChange(of: settings.showOrbWhenIdle) { model.focus?.updateOverlayVisibility() }
            }
            SettingRow("Check in with me", "Ribbon looks at your day and sends a nudge when you drift, or encouragement when it's going well.") {
                Toggle("", isOn: $settings.checkIns).toggleStyle(.switch).labelsHidden()
            }
            SettingRow("Check in every", "Nudges come this often. Encouragement comes at most once an hour.") {
                Dropdown(selection: settings.checkInMinutes, options: [15, 30, 60].map { ($0, "\($0) minutes") }) {
                    settings.checkInMinutes = $0
                }
                .disabled(!settings.checkIns).opacity(settings.checkIns ? 1 : 0.5)
            }
            SettingRow("Install updates automatically", "Ribbon downloads new versions and shows you what's new. They're installed when Ribbon restarts.") {
                Toggle("", isOn: $settings.automaticUpdates).toggleStyle(.switch).labelsHidden()
            }
            if let updater = model.updater {
                SettingRow("Ribbon \(Updater.current)", updateStatus(updater)) {
                    if updater.latest != nil {
                        Button("See Update") { updater.showWindow() }.buttonStyle(PillButtonStyle(primary: true))
                    } else {
                        Button("Check Now") { Task { await updater.check(userInitiated: true) } }
                            .buttonStyle(PillButtonStyle()).disabled(updater.phase == .checking)
                    }
                }
            }
        case .tracking:
            SettingRow("Tracking", model.tracker.isPaused
                       ? "Paused until \(model.tracker.pausedUntil?.formatted(date: .omitted, time: .shortened) ?? "later")."
                       : "Recording the apps and websites you use.") {
                if model.tracker.isPaused {
                    Button("Resume") { model.tracker.pausedUntil = nil; refresh += 1 }.buttonStyle(PillButtonStyle())
                } else {
                    Menu {
                        Button("For 15 minutes") { pause(15 * 60) }
                        Button("For an hour") { pause(3600) }
                        Button("Until tomorrow") { pause(until: Calendar.current.startOfDay(for: Date()).addingTimeInterval(30 * 3600)) }
                    } label: {
                        Text("Pause").font(.system(size: 13, weight: .medium)).padding(.horizontal, 14).frame(height: 30)
                            .overlay(Capsule(style: .circular).strokeBorder(Theme.hairline))
                    }
                    .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
                }
            }
            SettingRow("Count me as away after", "Videos and meetings keep counting while you sit still.") {
                Dropdown(selection: settings.idleMinutes, options: [2, 5, 10, 15].map { ($0, "\($0) minutes") }) {
                    settings.idleMinutes = $0
                    model.tracker.idleThreshold = TimeInterval($0 * 60)
                }
            }
            SettingRow("Daily focus goal", "Focus scores full marks for focus time at this many hours.") {
                Dropdown(selection: settings.focusGoalHours, options: stride(from: 1.0, through: 8.0, by: 0.5).map { ($0, "\($0.formatted()) hours") }) {
                    settings.focusGoalHours = $0
                    model.refresh()
                }
            }
        case .breaks:
            SettingRow("Remind me to take breaks", "A notification after a long stretch of work outside focus sessions.") {
                Toggle("", isOn: $settings.breakReminders).toggleStyle(.switch).labelsHidden()
            }
            SettingRow("After working for", "How long a stretch counts as long.") {
                Dropdown(selection: settings.breakIntervalMinutes, options: [30, 45, 50, 60, 90].map { ($0, "\($0) minutes") }) {
                    settings.breakIntervalMinutes = $0
                }
                .disabled(!settings.breakReminders).opacity(settings.breakReminders ? 1 : 0.5)
            }
        case .permissions:
            PermissionRow(title: "Screen Recording", detail: "Window titles, and the orb's screen checks during sessions.",
                          granted: CGPreflightScreenCaptureAccess(), pane: "Privacy_ScreenCapture")
            PermissionRow(title: "Accessibility", detail: "Hides apps a focus session doesn't allow. Without it, they're quit.",
                          granted: AXIsProcessTrusted(), pane: "Privacy_Accessibility")
            NotificationsRow()
            ForEach(browsers, id: \.id) { browser in
                let access = model.tracker.browsers.access[browser.id] ?? .unknown
                PermissionRow(title: browser.name, detail: "Reads the address of the tab you're on, and blocks sites in sessions.",
                              granted: access == .granted, denied: access == .denied, pane: "Privacy_Automation")
            }
        case .ai:
            let openai = model.assistant.openai
            let _ = planChanges
            ChatGPTPlanRow(openai: openai) { planChanges += 1 }
            if openai.usesPlan { PlanModelRow(openai: openai) }
            SettingRow("OpenAI API key", keySaved ? "Saved to your keychain. Relaunch Ribbon to start using it."
                       : openai.usesPlan ? (openai.hasAPIKey ? "Not used while Ribbon uses your ChatGPT plan. It's used again if you sign out."
                                                             : "Not needed while Ribbon uses your ChatGPT plan.")
                       : openai.hasAPIKey ? "Connected. Paste a different key to replace it."
                       : "Or use a key from platform.openai.com. It turns on sorting, summaries, answers and the orb.") {
                if keySaved {
                    Button("Relaunch") { relaunch() }.buttonStyle(PillButtonStyle(primary: true))
                } else {
                    HStack(spacing: 8) {
                        SecureField("sk-…", text: $newKey)
                            .textFieldStyle(.plain).font(.system(size: 13))
                            .padding(.horizontal, 10).frame(width: 190, height: 30)
                            .background(Theme.bubble, in: RoundedRectangle(cornerRadius: 8))
                        Button("Save") { keySaved = APIKeyStore.save(newKey); newKey = "" }
                            .buttonStyle(PillButtonStyle(primary: true))
                            .fixedSize()
                            .disabled(newKey.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            SettingRow("Models", openai.usesPlan
                       ? "Your plan's model does everything, including the yes-or-no questions an API key sends to the Decisions API. The orb checks your screen every 30 seconds."
                       : "Sorting apps and sites and picking session types use the Decisions API; summaries and answers use the Responses API (gpt-6-luna).") {
                EmptyView()
            }
            if let gemini = model.gemini { OrbVoiceRows(gemini: gemini, settings: model.settings, focus: model.focus) }
            SettingRow("What the AI sees", "App names, website names, page titles and totals. Screenshots only during focus sessions that watch your screen, and they're never saved. With a Gemini key, what the orb says aloud also goes to Google to be turned into speech.") {
                EmptyView()
            }
        case .data:
            SettingRow("Your data", "Everything is stored on this Mac, in Application Support.") {
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([Store.folder]) }.buttonStyle(PillButtonStyle())
            }
            SettingRow("Delete all tracked data", "Removes your timeline, sessions, chats, reviews and category choices.") {
                Button("Delete all") { confirmDelete = true }.buttonStyle(PillButtonStyle(destructive: true))
            }
        }
    }

    private var browsers: [(id: String, name: String)] {
        BrowserBridge.chromium.union(BrowserBridge.webkit).compactMap { id in
            InstalledApps.all.first { $0.bundleID == id }.map { (id, $0.name) }
        }
        .sorted { $0.name < $1.name }
    }

    private func updateStatus(_ updater: Updater) -> String {
        if let latest = updater.latest {
            return updater.phase == .ready ? "Ribbon \(latest.version) is ready. Restart Ribbon to install it." : "Ribbon \(latest.version) is available."
        }
        switch updater.phase {
        case .checking: return "Checking for updates…"
        case .failed: return "Couldn't check for updates."
        default:
            guard let checked = updater.lastChecked else { return "You're on the newest version." }
            return "You're on the newest version. Checked \(checked.formatted(.relative(presentation: .named)))."
        }
    }

    private func pause(_ seconds: TimeInterval) { pause(until: Date().addingTimeInterval(seconds)) }

    private func pause(until date: Date) {
        model.tracker.pausedUntil = date
        refresh += 1
    }
}

private struct SettingRow<Control: View>: View {
    let title: String
    let detail: String
    @ViewBuilder let control: Control

    init(_ title: String, _ detail: String, @ViewBuilder control: () -> Control) {
        self.title = title
        self.detail = detail
        self.control = control()
    }

    var body: some View {
        TableRow(verticalPadding: 13) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 13.5))
                Text(detail).font(.system(size: 12)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 20)
            control
        }
    }
}

/// Whether macOS lets Ribbon show notifications, which check-ins and break reminders need.
private struct NotificationsRow: View {
    @State private var allowed: Bool?

    var body: some View {
        SettingRow("Notifications", "Check-ins, break reminders and your weekly review.") {
            if allowed == true {
                Label("Allowed", systemImage: "checkmark").font(Typeface.caption).foregroundStyle(Theme.ink)
            } else if allowed == false {
                Button("Open Settings") {
                    let id = Bundle.main.bundleIdentifier ?? ""
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(id)")!)
                }
                .buttonStyle(PillButtonStyle())
            }
        }
        .task { allowed = await Notifier.isAllowed() }
    }
}

/// Use your ChatGPT plan: sign in with ChatGPT so Ribbon's AI is paid by the plan instead of an API key.
private struct ChatGPTPlanRow: View {
    let openai: OpenAI
    let changed: () -> Void
    @State private var signingIn = false
    @State private var error: String?
    @State private var note: String?
    @State private var showWelcome = false

    var body: some View {
        let account = openai.chatgpt?.account
        SettingRow("Use your ChatGPT plan", detail(account)) {
            HStack(spacing: 8) {
                if signingIn {
                    ProgressView().controlSize(.small)
                    Button("Cancel") { openai.chatgpt?.cancelSignIn() }.buttonStyle(PillButtonStyle())
                } else if let account, account.canUsePlan {
                    Button("Manage usage") { NSWorkspace.shared.open(ChatGPTAuth.usageSettings) }.buttonStyle(PillButtonStyle())
                    Button("Sign Out") { Task { await signOut() } }.buttonStyle(PillButtonStyle())
                } else {
                    if account != nil {
                        Button("Sign Out") { Task { await signOut() } }.buttonStyle(PillButtonStyle())
                    }
                    Button("Continue with ChatGPT") { Task { await signIn() } }.buttonStyle(PillButtonStyle(primary: true))
                }
            }
        }
        .alert("You're using your ChatGPT plan", isPresented: $showWelcome) {
            Button("Got it") {}
            Button("Manage usage") { NSWorkspace.shared.open(ChatGPTAuth.usageSettings) }
        } message: {
            Text("Ribbon's AI now uses your ChatGPT plan, the same allowance as ChatGPT and Codex. You can see your usage and set a limit for Ribbon in ChatGPT settings.")
        }
    }

    private func detail(_ account: ChatGPTAccount?) -> String {
        if signingIn { return "Finish signing in in your browser." }
        if let error { return error }
        guard let account else {
            return note ?? "Ribbon's AI can use your ChatGPT Plus or Pro plan instead of an API key. You can set a weekly limit for Ribbon in ChatGPT."
        }
        if !account.canUsePlan {
            return "Signed in as \(account.email), but Ribbon isn't allowed to use your plan. Continue with ChatGPT again and allow it, or use an API key."
        }
        if openai.limitReached {
            return "Signed in as \(account.email). Usage limit reached: Ribbon's AI is paused until your plan has room again."
        }
        return "Signed in as \(account.email). Using ChatGPT plan: your plan pays for Ribbon's AI."
    }

    @MainActor private func signIn() async {
        guard let auth = openai.chatgpt else { return }
        error = nil
        note = nil
        signingIn = true
        defer {
            signingIn = false
            changed()
        }
        do {
            let account = try await auth.signIn()
            NSApp.activate()
            if account.canUsePlan && !UserDefaults.standard.bool(forKey: "chatgptWelcomeShown") {
                UserDefaults.standard.set(true, forKey: "chatgptWelcomeShown")
                showWelcome = true
            }
        } catch ChatGPTAuthError.cancelled {
        } catch {
            self.error = error.localizedDescription
        }
    }

    @MainActor private func signOut() async {
        guard let auth = openai.chatgpt else { return }
        let revoked = await auth.signOut()
        note = revoked ? nil : "Signed out on this Mac. Ribbon couldn't reach OpenAI to disconnect, so remove Ribbon in ChatGPT settings to finish."
        changed()
    }
}

/// The orb's voice and manner: a Gemini key, which voice, and how it talks to you when you drift.
private struct OrbVoiceRows: View {
    let gemini: GeminiVoice
    let settings: Settings
    let focus: FocusController?
    @State private var newKey = ""
    @State private var connected: Bool
    @State private var voice: String
    @State private var player: AVAudioPlayer?
    @State private var sampling = false
    @State private var sampleError: String?
    /// The last ruthless sample: which level, and what it said.
    @State private var sampleNote: String?
    @State private var sampleLevel = 0

    init(gemini: GeminiVoice, settings: Settings, focus: FocusController?) {
        self.gemini = gemini
        self.settings = settings
        self.focus = focus
        _connected = State(initialValue: gemini.isAvailable)
        _voice = State(initialValue: gemini.voice)
    }

    var body: some View {
        SettingRow("Gemini API key", connected
                   ? "Connected. The orb speaks with Gemini 3.8 Flash TTS. Paste a different key to replace it."
                   : "Optional, from aistudio.google.com. The orb then speaks with Gemini 3.8 Flash TTS instead of a macOS voice. What it says aloud is sent to Google to be turned into speech.") {
            HStack(spacing: 8) {
                SecureField("AIza…", text: $newKey)
                    .textFieldStyle(.plain).font(.system(size: 13))
                    .padding(.horizontal, 10).frame(width: 190, height: 30)
                    .background(Theme.bubble, in: RoundedRectangle(cornerRadius: 8))
                Button("Save") {
                    if gemini.setKey(newKey) {
                        connected = gemini.isAvailable
                        Task { await gemini.prepare() }
                    }
                    newKey = ""
                }
                .buttonStyle(PillButtonStyle(primary: true))
                .fixedSize()
                .disabled(newKey.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        if connected {
            SettingRow("Orb's voice", sampleError ?? sampleNote ?? (voice == GeminiVoice.ribbonVoice
                       ? "Ribbon's own voice, a bone-dry English butler. It's made in your Google project when you first choose it."
                       : "One of Gemini's built-in voices.")) {
                HStack(spacing: 8) {
                    Dropdown(selection: voice, options: [(GeminiVoice.ribbonVoice, "Ribbon's butler")] + GeminiVoice.builtIn.map { ($0, $0) }) {
                        voice = $0
                        gemini.voice = $0
                        Task { await gemini.prepare() }
                    }
                    Button(sampling ? "Playing…" : settings.orbTone == .ruthless ? "Roast me" : "Play sample") { Task { await playSample() } }
                        .buttonStyle(PillButtonStyle())
                        .fixedSize()
                        .disabled(sampling)
                }
            }
        }
        SettingRow("How the orb talks to you", settings.orbTone.detail + " Its check-ins too.") {
            Dropdown(selection: settings.orbTone, options: OrbTone.allCases.map { ($0, $0.label) }) { settings.orbTone = $0 }
        }
    }

    private func playSample() async {
        sampling = true
        sampleError = nil
        defer { sampling = false }
        var sample = OpenAI.Quip(spoken: "That video looks fun, but your task misses you. Back to it?", delivery: "bright and quick, amused")
        sampleNote = nil
        if settings.orbTone == .ruthless {
            // A real roast from today's activity, one level harsher each time you ask.
            sampleLevel = sampleLevel % 4 + 1
            if let roast = await focus?.sampleRoast(level: sampleLevel) {
                sample = roast
                sampleNote = "Level \(sampleLevel) of 4: \(roast.text)"
            } else {
                sample = OpenAI.Quip(spoken: "Eleven minutes of cat videos. <sigh> Pathetic, even by your standards.",
                                     delivery: "cold contempt, a sneer on the last word")
            }
        }
        do {
            player = try AVAudioPlayer(data: try await gemini.speech(sample.spoken, style: sample.style(settings.orbTone), voice: voice))
            player?.play()
        } catch {
            sampleError = "Couldn't play a sample: \(error.localizedDescription)"
        }
    }
}

/// Which of the plan's models Ribbon uses.
private struct PlanModelRow: View {
    let openai: OpenAI
    @State private var models: [String]?
    @State private var selected = ""

    var body: some View {
        SettingRow("Model", "The model from your ChatGPT plan that Ribbon uses.") {
            if let models, !models.isEmpty {
                Dropdown(selection: selected, options: models.map { ($0, $0) }) {
                    selected = $0
                    UserDefaults.standard.set($0, forKey: "chatgptModel")
                }
            } else if models != nil {
                Text("Couldn't load your plan's models").font(Typeface.caption).foregroundStyle(Theme.muted)
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .task {
            let list = await openai.planModels()
            selected = await openai.planModel()
            models = list
        }
    }
}

private struct PermissionRow: View {
    let title: String
    let detail: String
    let granted: Bool
    var denied = false
    let pane: String

    var body: some View {
        SettingRow(title, detail) {
            if granted {
                Label("Allowed", systemImage: "checkmark").font(Typeface.caption).foregroundStyle(Theme.ink)
            } else {
                Button(denied ? "Allow in Settings" : "Open Settings") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")!)
                }
                .buttonStyle(PillButtonStyle())
            }
        }
    }
}
