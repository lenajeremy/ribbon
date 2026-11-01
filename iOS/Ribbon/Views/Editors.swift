import FamilyControls
import SwiftUI

/// Create or edit a session type, row by row, as on the desktop. Apps come from Apple's picker; websites are typed.
struct SessionEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State var profile: SessionProfile
    @State private var newSite = ""
    @State private var picking = false

    private var isNew: Bool { !model.profiles.contains { $0.id == profile.id } }
    private let modes: [(RuleMode, String)] = [(.off, "No limits"), (.allowOnly, "Only these"), (.block, "Block these")]
    private let focusOptions: [(Int, String)] = [15, 20, 25, 30, 45, 50, 60, 75, 90, 120].map { ($0, "\($0) min") }
    private let breakOptions: [(Int, String)] = [0, 5, 10, 15, 20, 30].map { ($0, $0 == 0 ? "No break" : "\($0) min") }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: isNew ? "New session type" : "Edit \(profile.name)") { dismiss() }
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    FormRow(label: "Name") {
                        HStack(spacing: 8) {
                            TextField("🎯", text: $profile.emoji)
                                .multilineTextAlignment(.center).font(.system(size: 20))
                                .frame(width: 52, height: 44)
                                .background(Theme.bubble, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .onChange(of: profile.emoji) { if profile.emoji.count > 1 { profile.emoji = String(profile.emoji.suffix(1)) } }
                            TextField("Deep Work", text: $profile.name).fieldStyle()
                        }
                    }
                    FormRow(label: "Length") {
                        HStack(spacing: 10) {
                            Dropdown(selection: profile.focusMinutes, options: focusOptions) { profile.focusMinutes = $0 }
                            Text("of focus, then").font(.system(size: 15)).foregroundStyle(Theme.muted)
                            Dropdown(selection: profile.breakMinutes, options: breakOptions) { profile.breakMinutes = $0 }
                        }
                    }
                    FormRow(label: "Apps", detail: appsDetail) {
                        PillChoice(selection: $profile.appMode, options: modes)
                        if profile.appMode != .off {
                            PickedApps(selection: $profile.apps) { picking = true }
                        }
                    }
                    FormRow(label: "Websites", detail: sitesDetail) {
                        PillChoice(selection: $profile.siteMode, options: modes)
                        if profile.siteMode != .off {
                            FlowLayout(spacing: 6) {
                                ForEach(profile.sites, id: \.self) { site in
                                    Token(text: site) {
                                        Image(systemName: site == "localhost" ? "laptopcomputer" : "globe")
                                            .font(.system(size: 12)).foregroundStyle(Theme.muted)
                                    } remove: { profile.sites.removeAll { $0 == site } }
                                }
                                HStack(spacing: 5) {
                                    Image(systemName: "plus").font(.system(size: 12)).foregroundStyle(Theme.muted)
                                    TextField("Add website", text: $newSite)
                                        .font(.system(size: 14)).frame(width: 120)
                                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                                        .keyboardType(.URL).submitLabel(.done)
                                        .onSubmit(addSite)
                                }
                                .padding(.horizontal, 12).frame(height: 32)
                                .overlay(Capsule().strokeBorder(Theme.hairline))
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
            }
            .scrollDismissesKeyboard(.interactively)

            HStack(spacing: 8) {
                if !isNew {
                    Button("Delete") { model.delete(profile); dismiss() }.buttonStyle(PillButtonStyle(destructive: true))
                }
                Spacer()
                Button("Cancel") { dismiss() }.buttonStyle(PillButtonStyle())
                Button(isNew ? "Add" : "Save") {
                    addSite()
                    profile.name = profile.name.trimmingCharacters(in: .whitespaces)
                    model.save(profile)
                    dismiss()
                }
                .buttonStyle(PillButtonStyle(primary: true))
                .disabled(profile.name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 20).padding(.vertical, 14)
        }
        .background(Theme.page)
        .presentationCornerRadius(28)
        .screenshotScroll()
        .familyActivityPicker(isPresented: $picking, selection: $profile.apps)
    }

    private var appsDetail: String? {
        switch profile.appMode {
        case .allowOnly: "Every other app is blocked while you focus. Pick apps here rather than whole categories."
        case .block: "These are blocked while you focus. Whole categories, like Social, work too."
        case .off: nil
        }
    }

    private var sitesDetail: String? {
        switch profile.siteMode {
        case .allowOnly: "Every other website is blocked in your browsers while you focus."
        case .block: "These are blocked in your browsers while you focus. A site covers its subdomains."
        case .off: nil
        }
    }

    private func addSite() {
        let site = SiteMatch.normalize(newSite)
        if !site.isEmpty && !profile.sites.contains(site) { profile.sites.append(site) }
        newSite = ""
    }
}

/// Create or edit a schedule: session type, task, days and times.
struct ScheduleEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State var schedule: FocusSchedule

    private var isNew: Bool { !model.schedules.contains { $0.id == schedule.id } }
    private var longEnough: Bool { schedule.end - schedule.start >= FocusSchedule.shortest }
    private var valid: Bool {
        !schedule.task.trimmingCharacters(in: .whitespaces).isEmpty && !schedule.days.isEmpty && longEnough
            && model.profiles.contains { $0.id == schedule.profileID }
    }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: isNew ? "New schedule" : "Edit schedule") { dismiss() }
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    FormRow(label: "Session type", detail: "Its apps and websites rules, and its focus and break lengths.") {
                        Dropdown(selection: schedule.profileID, options: model.profiles.map { ($0.id, "\($0.emoji) \($0.name)") }) {
                            schedule.profileID = $0
                        }
                    }
                    FormRow(label: "Working on", detail: "What the session review holds you to.") {
                        TextField("Google interview prep", text: $schedule.task).fieldStyle()
                    }
                    FormRow(label: "Days", detail: schedule.daysText) {
                        HStack(spacing: 6) {
                            ForEach([2, 3, 4, 5, 6, 7, 1], id: \.self) { day in
                                let on = schedule.days.contains(day)
                                Button {
                                    if on { schedule.days.remove(day) } else { schedule.days.insert(day) }
                                } label: {
                                    Text(Calendar.current.veryShortWeekdaySymbols[day - 1])
                                        .font(.system(size: 14, weight: .semibold))
                                        .frame(width: 40, height: 40)
                                        .foregroundStyle(on ? Theme.page : Theme.ink)
                                        .background(on ? Theme.ink : Theme.bubble, in: Circle())
                                        .contentShape(Circle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(Calendar.current.weekdaySymbols[day - 1])
                                .accessibilityAddTraits(on ? .isSelected : [])
                            }
                        }
                    }
                    FormRow(label: "Time", detail: longEnough ? nil : "The end has to be at least 15 minutes after the start, on the same day.") {
                        HStack(spacing: 10) {
                            DatePicker("Start", selection: time(\.start), displayedComponents: .hourAndMinute).labelsHidden()
                            Text("to").font(.system(size: 15)).foregroundStyle(Theme.muted)
                            DatePicker("End", selection: time(\.end), displayedComponents: .hourAndMinute).labelsHidden()
                        }
                    }
                    Text("From the start time to the end, the session's rules stay on, breaks included. The only way to end it early is the emergency pass in Settings, one a week. The rules turn on at the start time even if Ribbon is closed.")
                        .font(Typeface.caption).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 16)
                }
                .padding(.horizontal, 20)
            }

            HStack(spacing: 8) {
                if !isNew {
                    Button("Delete") { model.delete(schedule); dismiss() }.buttonStyle(PillButtonStyle(destructive: true))
                }
                Spacer()
                Button("Cancel") { dismiss() }.buttonStyle(PillButtonStyle())
                Button(isNew ? "Add schedule" : "Save") {
                    schedule.task = schedule.task.trimmingCharacters(in: .whitespaces)
                    model.save(schedule)
                    dismiss()
                }
                .buttonStyle(PillButtonStyle(primary: true))
                .disabled(!valid)
            }
            .padding(.horizontal, 20).padding(.vertical, 14)
        }
        .background(Theme.page)
        .presentationCornerRadius(28)
        .screenshotScroll()
    }

    /// A time of day as a date for the picker, stored as minutes after midnight.
    private func time(_ field: WritableKeyPath<FocusSchedule, Int>) -> Binding<Date> {
        Binding(
            get: { Calendar.current.startOfDay(for: Date()).addingTimeInterval(TimeInterval(schedule[keyPath: field] * 60)) },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                schedule[keyPath: field] = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
            })
    }
}

/// A session's review: the verdict and score, what happened, the points taken off, and a tip.
struct ReviewSheet: View {
    let record: SessionRecord
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: record.review == nil ? "Session" : "Session review") { dismiss() }
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(record.review?.verdict ?? record.task).font(.system(size: 18, weight: .semibold))
                            Text(record.review == nil ? "\(record.emoji) \(record.profile)" : record.task)
                                .font(Typeface.caption).foregroundStyle(Theme.muted).lineLimit(2)
                        }
                        Spacer(minLength: 12)
                        if let review = record.review {
                            (Text("\(review.score)").font(.system(size: 40, weight: .semibold)).foregroundStyle(SessionReview.color(review.score))
                             + Text(" / 100").font(.system(size: 13)).foregroundStyle(Theme.muted))
                                .monospacedDigit()
                        }
                    }
                    if let review = record.review {
                        Text(review.summary).font(Typeface.body).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
                        if !review.deductions.isEmpty {
                            group("Points off") {
                                ForEach(review.deductions, id: \.self) { deduction in
                                    HStack(alignment: .firstTextBaseline) {
                                        Text(deduction.reason).font(Typeface.row)
                                        Spacer(minLength: 16)
                                        Text("−\(deduction.points)").font(.system(size: 15, weight: .medium)).monospacedDigit()
                                    }
                                }
                            }
                        }
                    }
                    group("What happened") {
                        fact("Started", record.start.formatted(.dateTime.weekday(.wide).hour().minute()))
                        fact("Focused", "\(Format.duration(record.counted)) of \(Format.duration(TimeInterval(record.plannedMinutes * 60)))")
                        fact("Ended", record.outcome == "completed" ? "Ran its full length" : record.outcome == "running" ? "Still running" : "Stopped early")
                        if !record.note.isEmpty { fact("Reason", record.note) }
                        if !record.isScheduled && !record.pauses.isEmpty {
                            fact("Paused", "\(record.pauses.count) time\(record.pauses.count == 1 ? "" : "s"), \(Format.duration(record.pauses.reduce(0) { $0 + $1.duration }))")
                        }
                        fact("Blocked screen", "Closed \(record.blocks) time\(record.blocks == 1 ? "" : "s")")
                        if SharedStore.hasDistracting { fact("Distracting apps", "At least \(record.distractingMinutes)m") }
                    }
                    if let review = record.review {
                        (Text("Next time: ").fontWeight(.semibold) + Text(review.tip))
                            .font(Typeface.row).fixedSize(horizontal: false, vertical: true)
                    } else if record.outcome != "running" && record.counted < Reviewer.minimumLength {
                        Text("Sessions shorter than 5 minutes aren't reviewed.").font(Typeface.caption).foregroundStyle(Theme.muted)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 30)
            }
        }
        .background(Theme.page)
        .presentationDetents([.medium, .large])
        .presentationCornerRadius(28)
        .screenshotScroll()
    }

    private func group<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.muted)
            content()
        }
    }

    private func fact(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).font(Typeface.row).foregroundStyle(Theme.muted).frame(width: 130, alignment: .leading)
            Text(value).font(Typeface.row).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
