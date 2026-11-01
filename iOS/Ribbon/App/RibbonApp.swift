import SwiftUI

@main
struct RibbonApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
        }
    }
}

/// Like the desktop's sidebar, three places: Today, Focus and This week. Settings sits behind the gear on each.
struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var model = model
        TabView(selection: $model.tab) {
            Tab("Today", systemImage: "clock", value: AppModel.TabID.today) { TodayView() }
            Tab("Focus", systemImage: "timer", value: AppModel.TabID.focus) { FocusView() }
            Tab("Week", systemImage: "calendar", value: AppModel.TabID.week) { WeekView() }
        }
        .tint(Theme.ink)
        .screenshotAppearance()
        .sheet(isPresented: $model.showSettings) { SettingsView() }
        .sheet(isPresented: $model.showStart) { StartSheet() }
        .sheet(item: $model.editing) { SessionEditor(profile: $0) }
        .sheet(item: $model.editingSchedule) { ScheduleEditor(schedule: $0) }
        .sheet(item: $model.openRecord) { ReviewSheet(record: $0) }
        .fullScreenCover(isPresented: $model.showSession) { SessionScreen() }
        .onChange(of: scenePhase) { if scenePhase == .active { model.refresh() } }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                model.tick()
            }
        }
        .onOpenURL { url in
            if url.host == "session", model.active != nil { model.showSession = true }
        }
    }
}
