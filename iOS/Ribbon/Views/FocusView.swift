import SwiftUI

/// Session types you can start or edit, your schedules, then recent sessions, as on the desktop's Focus sessions page.
struct FocusView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center) {
                Text("Focus sessions").font(Typeface.greeting)
                Spacer()
                SettingsButton()
            }
            .padding(.horizontal, 20)
            .padding(.top, 6)
            .padding(.bottom, 4)
            page
        }
        .background(Theme.page)
    }

    /// A list rather than a plain scroll view, so recent sessions can be swiped away; drawn to look like the other pages.
    private var page: some View {
        List {
            Group {
                Text("Each type sets how long you focus and which apps and websites you can open meanwhile.")
                    .font(Typeface.body).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)

                if let session = model.active {
                    SessionStrip(session: session) { model.showSession = true }.padding(.top, 20)
                }

                SectionHeader(text: "Session types") {
                    Button { model.editing = model.newProfile() } label: { Label("New", systemImage: "plus") }
                        .buttonStyle(PillButtonStyle())
                }
                ForEach(model.profiles) { profile in
                    ProfileRow(profile: profile, canStart: model.active?.isScheduled != true,
                               start: { model.openStart(profile) }, edit: { model.editing = profile })
                }

                SectionHeader(text: "Schedule") {
                    Button { model.editingSchedule = model.newSchedule() } label: { Label("Add", systemImage: "plus") }
                        .buttonStyle(PillButtonStyle())
                        .disabled(model.profiles.isEmpty)
                }
                if model.schedules.isEmpty {
                    Text("Schedule a focus session to start by itself, like 9:00–17:00 on weekdays. Its rules stay on until it ends.")
                        .font(Typeface.row).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(model.schedules) { schedule in
                        ScheduleRow(schedule: schedule, profile: model.profiles.first { $0.id == schedule.profileID },
                                    toggle: { var changed = schedule; changed.enabled.toggle(); model.save(changed) },
                                    edit: { model.editingSchedule = schedule })
                    }
                }

                SectionLabel("Recent sessions")
                if model.sessions.filter({ !$0.hidden }).isEmpty {
                    Text("Sessions you run show up here, with how they went.").font(Typeface.row).foregroundStyle(Theme.muted)
                } else {
                    ForEach(Array(model.sessions.reversed().filter { !$0.hidden }.prefix(50))) { session in
                        SessionRow(session: session, delete: { delete(session) }) { model.openRecord = session }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                if session.outcome != "running" {
                                    Button(role: .destructive) { delete(session) } label: { Label("Delete", systemImage: "trash") }
                                        .tint(Color(uiColor: .systemRed))
                                }
                            }
                    }
                }
                Color.clear.frame(height: 30)
            }
            .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
            .listRowSeparator(.hidden)
            .listRowBackground(Theme.page)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollIndicators(.hidden)
        .environment(\.defaultMinListRowHeight, 0)
        .screenshotScroll()
        .background(Theme.page)
    }

    private func delete(_ session: SessionRecord) {
        withAnimation { model.delete(session) }
    }
}

private struct ProfileRow: View {
    let profile: SessionProfile
    let canStart: Bool
    let start: () -> Void
    let edit: () -> Void

    var body: some View {
        TableRow {
            Button(action: edit) {
                HStack(spacing: 12) {
                    EmojiTile(emoji: profile.emoji)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(profile.name).font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.ink)
                        Text("\(profile.focusMinutes) min focus, \(profile.breakMinutes == 0 ? "no break" : "\(profile.breakMinutes) min break"). \(profile.rulesSummary)")
                            .font(Typeface.caption).foregroundStyle(Theme.muted).lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 8)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Edits this session type")
            Button("Start", action: start).buttonStyle(PillButtonStyle(primary: true)).disabled(!canStart)
        }
    }
}

/// A schedule: when it runs, which session type and task, and a switch to turn it off.
private struct ScheduleRow: View {
    let schedule: FocusSchedule
    let profile: SessionProfile?
    let toggle: () -> Void
    let edit: () -> Void

    var body: some View {
        TableRow {
            Button(action: edit) {
                HStack(spacing: 12) {
                    EmojiTile(emoji: profile?.emoji ?? "🗓")
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(schedule.daysText), \(schedule.timesText)").font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Theme.ink)
                        Text("\(profile?.name ?? "Deleted session type"): \(schedule.task)")
                            .font(Typeface.caption).foregroundStyle(Theme.muted).lineLimit(1)
                    }
                    Spacer(minLength: 8)
                }
                .opacity(schedule.enabled ? 1 : 0.5)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Toggle("", isOn: Binding(get: { schedule.enabled }, set: { _ in toggle() }))
                .labelsHidden().tint(Theme.switchOn)
                .accessibilityLabel(schedule.enabled ? "On: starts by itself" : "Off")
        }
    }
}

/// A past session: what it was for, when, how long, how it ended, and its score. Tap for the review.
private struct SessionRow: View {
    let session: SessionRecord
    let delete: () -> Void
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            TableRow {
                Text(session.emoji).font(.system(size: 18)).frame(width: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.task).font(Typeface.row).foregroundStyle(Theme.ink).lineLimit(1)
                    Text([session.profile, when, outcome].compactMap { $0 }.joined(separator: " · "))
                        .font(.system(size: 12)).foregroundStyle(Theme.muted).lineLimit(1)
                }
                Spacer(minLength: 8)
                Text(Format.duration(session.counted)).font(Typeface.row).monospacedDigit().foregroundStyle(Theme.ink)
                if let review = session.review {
                    HStack(spacing: 6) {
                        Circle().fill(SessionReview.color(review.score)).frame(width: 7, height: 7)
                        Text("\(review.score)").font(.system(size: 14, weight: .semibold)).monospacedDigit().foregroundStyle(Theme.ink)
                    }
                    .frame(width: 44, alignment: .trailing)
                } else {
                    Color.clear.frame(width: 44, height: 1)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            if session.outcome != "running" {
                Button("Delete", systemImage: "trash", role: .destructive, action: delete)
            }
        }
    }

    /// Only when it didn't run its full length.
    private var outcome: String? {
        switch session.outcome {
        case "completed": nil
        case "running": "Running"
        default: "Stopped"
        }
    }

    /// "Today 08:05", "Yesterday 21:30", "Fri 16:10", or "Oct 20" for older ones.
    private var when: String {
        let calendar = Calendar.current, time = Format.time(session.start)
        if calendar.isDateInToday(session.start) { return "Today \(time)" }
        if calendar.isDateInYesterday(session.start) { return "Yesterday \(time)" }
        if Date().timeIntervalSince(session.start) < 6 * 86400 {
            return "\(session.start.formatted(.dateTime.weekday(.abbreviated))) \(time)"
        }
        return session.start.formatted(.dateTime.month(.abbreviated).day())
    }
}
