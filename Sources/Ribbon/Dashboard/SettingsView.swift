import AppKit
import ApplicationServices
import SwiftUI

/// Settings as a modal with a list of sections on the left, like ChatGPT's: each row is a name,
/// a gray line saying what it does, and the control on the right.
struct SettingsView: View {
    let model: DashboardModel
    @State private var pane: Pane = .general
    @State private var confirmDelete = false
    @State private var refresh = 0
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
                            .overlay(Capsule().strokeBorder(Theme.hairline))
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
            ForEach(browsers, id: \.id) { browser in
                let access = model.tracker.browsers.access[browser.id] ?? .unknown
                PermissionRow(title: browser.name, detail: "Reads the address of the tab you're on, and blocks sites in sessions.",
                              granted: access == .granted, denied: access == .denied, pane: "Privacy_Automation")
            }
        case .ai:
            SettingRow("OpenAI", model.assistant.enabled
                       ? "Sorting apps and sites and picking session types use the Decisions API; summaries and answers use the Responses API (gpt-6-luna)."
                       : "Add OPENAI_API_KEY to the .env file in the project folder, then relaunch.") {
                Text(model.assistant.enabled ? "Connected" : "Not set up").font(Typeface.caption)
                    .foregroundStyle(model.assistant.enabled ? Theme.ink : Theme.distracting)
            }
            SettingRow("What the AI sees", "App names, website names, page titles and totals. Screenshots only during focus sessions that watch your screen, and they're never saved.") {
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
