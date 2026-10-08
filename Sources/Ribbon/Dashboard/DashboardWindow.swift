import AppKit
import SwiftUI

/// The main window. While it's open, Ribbon gets a Dock icon and a menu bar like a normal app.
@MainActor final class DashboardWindow: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let model: DashboardModel

    init(model: DashboardModel) {
        self.model = model
    }

    func show(_ section: DashboardModel.Section? = nil) {
        if let section { model.section = section }
        if window == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1240, height: 840),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                                  backing: .buffered, defer: false)
            window.title = "Ribbon"
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.toolbarStyle = .unified
            window.contentMinSize = NSSize(width: 1020, height: 680)
            let host = NSHostingController(rootView: DashboardRoot(model: model))
            host.sizingOptions = []
            window.contentViewController = host
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.setContentSize(NSSize(width: 1240, height: 840))
            window.center()
            window.setFrameAutosaveName("Dashboard")
            window.collectionBehavior.insert(.moveToActiveSpace)
            self.window = window
        }
        // The saved position may be on a display that's no longer connected.
        if let window, !NSScreen.screens.contains(where: { $0.visibleFrame.intersects(window.frame) }) {
            window.setFrame(NSRect(origin: .zero, size: NSSize(width: 1240, height: 840)), display: false)
            window.center()
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
        model.refresh()
        model.startAutoRefresh()
    }

    func windowWillClose(_ notification: Notification) {
        model.stopAutoRefresh()
        NSApp.setActivationPolicy(.accessory)
    }
}

struct DashboardRoot: View {
    @Bindable var model: DashboardModel

    var body: some View {
        NavigationSplitView {
            Sidebar(model: model)
                .navigationSplitViewColumnWidth(min: 230, ideal: 250, max: 320)
                .toolbar(removing: .sidebarToggle)
        } detail: {
            Group {
                switch model.section {
                case .today: TodayView(model: model)
                case .week: WeekView(model: model)
                case .sessions: SessionsView(model: model)
                case .ask: AskView(model: model)
                case .categories: CategoriesView(model: model)
                case .settings: TodayView(model: model)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.page)
        }
        .sheet(item: $model.editing) { profile in
            SessionEditor(model: model, profile: profile)
        }
        .sheet(item: $model.editingCategory) { category in
            CategoryEditor(model: model, category: category)
        }
        .sheet(isPresented: $model.showSettings) {
            SettingsView(model: model)
        }
        .onChange(of: model.section) {
            if model.section == .settings { model.showSettings = true; model.section = .today }
        }
    }
}

/// Like ChatGPT's sidebar: a few places with thin gray icons, then your days and your chats as plain lists.
/// Selection is a soft gray, not the system blue, so the sidebar stays as quiet as the pages.
struct Sidebar: View {
    let model: DashboardModel
    @State private var renaming: Chat?
    @State private var newTitle = ""

    var body: some View {
        // A native sidebar list (it places clicks correctly under the transparent title bar), drawn with our own
        // rows so the icons stay gray and the selection stays a soft gray instead of the system blue.
        List {
            Group {
                SidebarRow(title: "Today", symbol: "clock", selected: model.section == .today && model.isToday) {
                    model.show(day: Date())
                }
                SidebarRow(title: "This week", symbol: "calendar", selected: model.section == .week) { model.show(.week) }
                SidebarRow(title: "Focus sessions", symbol: "timer", selected: model.section == .sessions) { model.show(.sessions) }
                SidebarRow(title: "Categories", symbol: "tag", selected: model.section == .categories) { model.show(.categories) }
                SidebarRow(title: "Ask AI", symbol: "bubble.left", selected: model.section == .ask && model.chatID == nil) {
                    model.newChat()
                }
            }
            .sidebarRowInsets()

            let pastDays = model.recentDays.filter { !Calendar.current.isDateInToday($0.day) }.prefix(10)
            if !pastDays.isEmpty {
                Section {
                    ForEach(pastDays, id: \.day) { entry in
                        SidebarRow(title: Calendar.current.isDateInYesterday(entry.day) ? "Yesterday"
                                   : entry.day.formatted(.dateTime.weekday(.wide).day().month(.abbreviated)),
                                   detail: Format.duration(entry.seconds),
                                   selected: model.section == .today && Calendar.current.isDate(model.day, inSameDayAs: entry.day)) {
                            model.show(day: entry.day)
                        }
                        .sidebarRowInsets()
                    }
                } header: { SidebarHeading("Days") }
            }
            if !model.chats.isEmpty {
                Section {
                    ForEach(model.chats.prefix(20)) { chat in
                        SidebarRow(title: chat.title, selected: model.section == .ask && model.chatID == chat.id) {
                            model.open(chat: chat.id)
                        }
                        .contextMenu {
                            Button("Rename…") { newTitle = chat.title; renaming = chat }
                            Divider()
                            Button("Delete chat", role: .destructive) { model.delete(chat: chat.id) }
                        }
                        .sidebarRowInsets()
                    }
                } header: { SidebarHeading("Your chats") { model.newChat() } }
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 230)
        .safeAreaInset(edge: .bottom) { StatusCard(model: model).padding(.horizontal, 10).padding(.bottom, 10) }
        .alert("Rename chat", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $newTitle)
            Button("Rename") { if let renaming { model.rename(chat: renaming.id, to: newTitle) }; renaming = nil }
            Button("Cancel", role: .cancel) { renaming = nil }
        }
    }
}

private extension View {
    func sidebarRowInsets() -> some View {
        listRowInsets(EdgeInsets(top: 2, leading: 0, bottom: 2, trailing: 0))
            .listRowSeparator(.hidden)
    }
}

private struct SidebarHeading: View {
    let text: String
    /// An optional "new" action shown at the right of the heading.
    var add: (() -> Void)?
    init(_ text: String, add: (() -> Void)? = nil) { self.text = text; self.add = add }

    var body: some View {
        HStack {
            Text(text).font(.system(size: 12)).foregroundStyle(.secondary)
            Spacer()
            if let add {
                Button(action: add) { Image(systemName: "square.and.pencil").font(.system(size: 12)) }
                    .buttonStyle(.plain).foregroundStyle(.secondary).help("New chat")
            }
        }
        .padding(.horizontal, 4)
        .padding(.top, 14)
        .padding(.bottom, 6)
    }
}

private struct SidebarRow: View {
    let title: String
    var symbol: String?
    var detail: String?
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 13.5, weight: .regular))
                        .foregroundStyle(.secondary)
                        .frame(width: 18)
                }
                Text(title).font(.system(size: 13.5)).foregroundStyle(.primary).lineLimit(1)
                Spacer(minLength: 6)
                if let detail { Text(detail).font(.system(size: 12)).foregroundStyle(.secondary).monospacedDigit().fixedSize() }
            }
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.primary.opacity(selected ? 0.08 : hovering ? 0.04 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// Bottom of the sidebar: whether tracking is on, the running session, and Settings.
private struct StatusCard: View {
    let model: DashboardModel

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { _ in
            HStack(spacing: 10) {
                if model.tracker.isPaused {
                    Circle().fill(Theme.muted).frame(width: 8, height: 8)
                } else {
                    NowOrb(size: 9)
                }
                VStack(alignment: .leading, spacing: 1) {
                    if let focus = model.focus, focus.model.phase == .focus {
                        Text(focus.model.profileName).font(.system(size: 12.5, weight: .medium)).lineLimit(1)
                        Text(focus.model.task).font(.system(size: 11.5)).foregroundStyle(.secondary).lineLimit(1)
                    } else {
                        Text(model.tracker.isPaused ? "Tracking paused" : "Tracking").font(.system(size: 12.5, weight: .medium))
                        Text("\(Format.duration(model.todayTotal)) today").font(.system(size: 11.5)).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button { model.showSettings = true } label: { Image(systemName: "gearshape").font(.system(size: 14)) }
                    .buttonStyle(.plain).foregroundStyle(.secondary).help("Settings")
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
        }
    }
}
