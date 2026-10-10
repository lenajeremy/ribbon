import SwiftUI

/// Session types as plain rows you can start or edit, then a table of recent sessions.
struct SessionsView: View {
    let model: DashboardModel
    @State private var showRemoved = false

    var body: some View {
        Page {
            VStack(alignment: .leading, spacing: 10) {
                Text("Focus sessions").font(Typeface.greeting)
                Text("Each type sets how long you focus and which apps and websites you can open meanwhile.")
                    .font(Typeface.body).foregroundStyle(Theme.muted)
            }
            HStack {
                SectionLabel("Session types")
                Spacer()
                Button { model.editing = SessionProfile(name: "", emoji: "🎯", focusMinutes: 50, breakMinutes: 10, appMode: .off,
                                                        apps: [], siteMode: .off, sites: [], blockDistracting: true, watchScreen: true)
                } label: { Label("New session type", systemImage: "plus") }
                .buttonStyle(PillButtonStyle(primary: true))
            }
            ForEach(model.profiles) { profile in
                ProfileRow(profile: profile, start: { model.start(profile) }, edit: { model.editing = profile })
            }
            SectionLabel("Recent sessions")
            let removed = model.sessions.filter(\.hidden).count
            if model.sessions.isEmpty {
                Text("Sessions you run show up here, with how they went.").font(Typeface.body).foregroundStyle(Theme.muted)
            } else {
                ForEach(model.sessions.filter { !$0.hidden || showRemoved }.prefix(25)) { session in
                    SessionRow(session: session, emoji: model.profiles.first { $0.name == session.profile }?.emoji ?? "🎯",
                               setHidden: { model.setHidden($0, session: session) })
                }
                if removed > 0 {
                    Button(showRemoved ? "Hide removed sessions" : "Show \(removed) removed session\(removed == 1 ? "" : "s")") {
                        showRemoved.toggle()
                    }
                    .buttonStyle(.plain).font(Typeface.caption).foregroundStyle(Theme.muted)
                    .padding(.top, 12)
                }
            }
        }
    }
}

private struct ProfileRow: View {
    let profile: SessionProfile
    let start: () -> Void
    let edit: () -> Void

    var body: some View {
        TableRow(verticalPadding: 12) {
            Text(profile.emoji).font(.system(size: 20))
                .frame(width: 40, height: 40)
                .background(Theme.bubble, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(profile.name).font(.system(size: 14, weight: .semibold))
                Text("\(profile.focusMinutes) min focus, \(profile.breakMinutes) min break. \(rules)")
                    .font(Typeface.caption).foregroundStyle(Theme.muted).lineLimit(1)
            }
            Spacer()
            if profile.siteMode != .off && !profile.sites.isEmpty {
                HStack(spacing: 6) {
                    ForEach(profile.sites.prefix(3), id: \.self) { site in
                        ItemIcon(bundle: "", domain: site.hasPrefix("*.") ? String(site.dropFirst(2)) : site, size: 18).help(site)
                    }
                    if profile.sites.count > 3 {
                        Text("+\(profile.sites.count - 3)").font(Typeface.caption).foregroundStyle(Theme.muted).monospacedDigit()
                    }
                }
                .padding(.trailing, 6)
            }
            if profile.appMode == .allowOnly && !profile.apps.isEmpty {
                HStack(spacing: 6) {
                    ForEach(profile.apps.prefix(3)) { app in
                        Image(nsImage: InstalledApps.icon(for: app.bundleID)).resizable().interpolation(.high)
                            .frame(width: 18, height: 18)
                            .help(app.name)
                    }
                    if profile.apps.count > 3 {
                        Text("+\(profile.apps.count - 3)").font(Typeface.caption).foregroundStyle(Theme.muted).monospacedDigit()
                    }
                }
                .help(profile.apps.map(\.name).joined(separator: ", "))
                .padding(.trailing, 6)
            }
            Button("Edit", action: edit).buttonStyle(PillButtonStyle())
            Button("Start", action: start).buttonStyle(PillButtonStyle(primary: true))
        }
    }

    private var rules: String {
        var parts: [String] = []
        switch profile.siteMode {
        case .allowOnly: parts.append("Only " + list(profile.sites))
        case .block: parts.append("Blocks " + list(profile.sites))
        case .off: break
        }
        if profile.appMode == .allowOnly { parts.append("\(profile.apps.count) apps allowed") }
        if profile.appMode == .block { parts.append("\(profile.apps.count) apps blocked") }
        if profile.blockDistracting && (profile.appMode != .allowOnly || profile.siteMode != .allowOnly) { parts.append("no distractions") }
        return parts.isEmpty ? "No limits." : parts.joined(separator: "; ") + "."
    }

    private func list(_ sites: [String]) -> String {
        sites.count <= 3 ? sites.joined(separator: ", ") : sites.prefix(3).joined(separator: ", ") + " and \(sites.count - 3) more"
    }
}

/// A past session: what it was for, when, how long, how it ended, and its score. Click for the review.
private struct SessionRow: View {
    let session: SessionRecord
    let emoji: String
    let setHidden: (Bool) -> Void
    @State private var showReview = false

    var body: some View {
        Button { if session.review != nil { showReview.toggle() } } label: {
            TableRow(verticalPadding: 10) {
                Text(emoji).frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.task).font(Typeface.row).lineLimit(1)
                    Text("\(session.profile), \(session.start.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute()))")
                        .font(Typeface.caption).foregroundStyle(Theme.muted)
                }
                Spacer()
                if session.nudges > 0 {
                    Label("\(session.nudges)", systemImage: "speaker.wave.2").font(Typeface.caption).foregroundStyle(Theme.muted).help("Nudges")
                }
                if session.blocks > 0 {
                    Label("\(session.blocks)", systemImage: "hand.raised").font(Typeface.caption).foregroundStyle(Theme.muted).help("Blocked attempts")
                }
                Text(Format.duration((session.end ?? Date()).timeIntervalSince(session.start)))
                    .font(Typeface.row).monospacedDigit().frame(width: 60, alignment: .trailing)
                Text(outcome).font(Typeface.caption).foregroundStyle(session.outcome == "completed" ? Theme.ink : Theme.muted)
                    .frame(width: 80, alignment: .trailing)
                    .help(session.note)
                if let review = session.review {
                    HStack(spacing: 6) {
                        Circle().fill(SessionReviewView.color(review.score)).frame(width: 7, height: 7)
                        Text("\(review.score)").font(.system(size: 13, weight: .semibold)).monospacedDigit()
                    }
                    .frame(width: 48, alignment: .trailing)
                    .help("Session score. Click for the review.")
                } else {
                    Color.clear.frame(width: 48, height: 1)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(session.hidden ? 0.45 : 1)
        .contextMenu {
            if session.hidden {
                Button("Put Back in List") { setHidden(false) }
            } else {
                Button("Remove from List") { setHidden(true) }
            }
        }
        .popover(isPresented: $showReview, arrowEdge: .trailing) {
            if let review = session.review { SessionReviewView(task: session.task, review: review) }
        }
    }

    private var outcome: String {
        switch session.outcome {
        case "completed": "Completed"
        case "running": "Running"
        default: "Stopped"
        }
    }
}

/// A session's review: the verdict and score, what happened, the points taken off, what counted, and a tip.
struct SessionReviewView: View {
    let task: String
    let review: SessionReview

    /// Blue from 80, amber from 50, red below: the same scale as productive to distracting.
    static func color(_ score: Int) -> Color {
        score >= 80 ? Theme.productive : score >= 50 ? Theme.series(4) : Theme.distracting
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(review.verdict).font(.system(size: 15, weight: .semibold))
                    Text(task).font(Typeface.caption).foregroundStyle(Theme.muted).lineLimit(1)
                }
                Spacer(minLength: 12)
                Text("\(review.score)").font(.system(size: 30, weight: .semibold)).monospacedDigit()
                    .foregroundStyle(Self.color(review.score))
                    + Text(" / 100").font(.system(size: 12)).foregroundStyle(Theme.muted)
            }
            Text(review.summary).font(.system(size: 13)).lineSpacing(2).fixedSize(horizontal: false, vertical: true)
            if !review.deductions.isEmpty {
                section("Points off") {
                    ForEach(review.deductions, id: \.self) { deduction in
                        HStack(alignment: .firstTextBaseline) {
                            Text(deduction.reason).font(.system(size: 12.5))
                            Spacer(minLength: 16)
                            Text("−\(deduction.points)").font(.system(size: 12.5, weight: .medium)).monospacedDigit()
                        }
                    }
                }
            }
            section("What you used") {
                ForEach(review.items.filter { $0.minutes >= 1 }.prefix(8), id: \.self) { item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: item.onTask ? "checkmark" : "xmark")
                            .font(.system(size: 9.5, weight: .bold))
                            .foregroundStyle(item.onTask ? Theme.productive : Theme.distracting)
                            .frame(width: 12)
                        Text(item.name).font(.system(size: 12.5)).lineLimit(1)
                        if !item.why.isEmpty {
                            Text(item.why).font(.system(size: 11.5)).foregroundStyle(Theme.muted).lineLimit(1)
                        }
                        Spacer(minLength: 12)
                        Text(Format.duration(TimeInterval(item.minutes * 60))).font(.system(size: 12.5)).monospacedDigit()
                            .foregroundStyle(Theme.muted)
                    }
                }
            }
            (Text("Next time: ").fontWeight(.semibold) + Text(review.tip))
                .font(.system(size: 12.5)).fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(width: 400)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.system(size: 11.5, weight: .semibold)).foregroundStyle(Theme.muted)
            content()
        }
    }
}

/// Create or edit a session type, by describing it to the AI or row by row, in the style of ChatGPT's settings.
struct SessionEditor: View {
    let model: DashboardModel
    @State var profile: SessionProfile
    @State private var description = ""
    @State private var generating = false
    @State private var error: String?
    @State private var newSite = ""
    @State private var pickingApps = false
    @Environment(\.dismiss) private var dismiss

    private var isNew: Bool { !model.profiles.contains { $0.id == profile.id } }
    private let modes: [(RuleMode, String)] = [(.off, "No limits"), (.allowOnly, "Only these"), (.block, "Block these")]
    private let focusOptions: [(Int, String)] = [15, 20, 25, 30, 45, 50, 60, 75, 90, 120].map { ($0, "\($0) min") }
    private let breakOptions: [(Int, String)] = [0, 5, 10, 15, 20, 30].map { ($0, $0 == 0 ? "No break" : "\($0) min") }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(isNew ? "New session type" : "Edit \(profile.name)").font(Typeface.heading)
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark").font(.system(size: 12, weight: .semibold)) }
                    .buttonStyle(.plain).foregroundStyle(Theme.muted).keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 24).padding(.top, 20).padding(.bottom, 14)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if model.assistant.enabled {
                        VStack(alignment: .leading, spacing: 8) {
                            Composer(placeholder: "Describe it: coding, browser only for localhost and GitHub, no YouTube",
                                     text: $description, busy: generating) { Task { await generate() } }
                            Text(error ?? "The AI fills in everything below; you can still change any of it.")
                                .font(Typeface.caption).foregroundStyle(error == nil ? Theme.muted : Theme.distracting)
                                .padding(.leading, 6)
                        }
                        .padding(.bottom, 12)
                    }
                    Rectangle().fill(Theme.hairline).frame(height: 1)
                    FormRow(label: "Name") {
                        HStack(spacing: 8) {
                            TextField("🎯", text: $profile.emoji)
                                .textFieldStyle(.plain).multilineTextAlignment(.center).font(.system(size: 16))
                                .frame(width: 36, height: 30)
                                .background(Theme.bubble, in: RoundedRectangle(cornerRadius: 8))
                            TextField("Coding", text: $profile.name)
                                .textFieldStyle(.plain).font(.system(size: 14))
                                .padding(.horizontal, 10).frame(height: 30)
                                .background(Theme.bubble, in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                    FormRow(label: "Length") {
                        HStack(spacing: 10) {
                            Dropdown(selection: profile.focusMinutes, options: focusOptions) { profile.focusMinutes = $0 }
                            Text("of focus, then").font(.system(size: 13)).foregroundStyle(Theme.muted)
                            Dropdown(selection: profile.breakMinutes, options: breakOptions) { profile.breakMinutes = $0 }
                        }
                    }
                    FormRow(label: "Apps", detail: profile.appMode == .allowOnly ? "Any other app is hidden when you switch to it. Finder and Settings always work."
                                                   : profile.appMode == .block ? "These are hidden when you switch to them." : nil) {
                        PillChoice(selection: $profile.appMode, options: modes)
                        if profile.appMode != .off {
                            FlowLayout(spacing: 6) {
                                ForEach(profile.apps) { app in
                                    Token(text: app.name) {
                                        Image(nsImage: InstalledApps.icon(for: app.bundleID)).resizable().frame(width: 15, height: 15)
                                    } remove: { profile.apps.removeAll { $0 == app } }
                                }
                                Button { pickingApps = true } label: {
                                    Label("Add app", systemImage: "plus").font(.system(size: 12.5))
                                        .padding(.horizontal, 10).frame(height: 26)
                                        .overlay(Capsule().strokeBorder(Theme.hairline))
                                        .contentShape(Capsule())
                                }
                                .buttonStyle(.plain)
                                .popover(isPresented: $pickingApps) { AppPicker(selected: $profile.apps) }
                            }
                        }
                    }
                    FormRow(label: "Websites", detail: profile.siteMode == .off ? nil
                            : "*.google.com covers every subdomain. Blocked tabs turn into a \u{201C}blocked\u{201D} page.") {
                        PillChoice(selection: $profile.siteMode, options: modes)
                        if profile.siteMode != .off {
                            FlowLayout(spacing: 6) {
                                ForEach(profile.sites, id: \.self) { site in
                                    Token(text: site) {
                                        ItemIcon(bundle: "", domain: site.hasPrefix("*.") ? String(site.dropFirst(2)) : site, size: 15)
                                    } remove: { profile.sites.removeAll { $0 == site } }
                                }
                                HStack(spacing: 4) {
                                    Image(systemName: "plus").font(.system(size: 11)).foregroundStyle(Theme.muted)
                                    TextField("Add website", text: $newSite)
                                        .textFieldStyle(.plain).font(.system(size: 12.5)).frame(width: 110)
                                        .onSubmit(addSite)
                                }
                                .padding(.horizontal, 10).frame(height: 26)
                                .overlay(Capsule().strokeBorder(Theme.hairline))
                            }
                        }
                    }
                    FormRow(label: "Block distractions", detail: "Also block anything the AI marks as social, news or entertainment.") {
                        Toggle("", isOn: $profile.blockDistracting).toggleStyle(.switch).labelsHidden()
                            .disabled(profile.appMode == .allowOnly && profile.siteMode == .allowOnly)
                    }
                    FormRow(label: "Watch my screen", detail: "The orb checks your screens and nudges you out loud when you drift.") {
                        Toggle("", isOn: $profile.watchScreen).toggleStyle(.switch).labelsHidden()
                    }
                }
                .padding(.horizontal, 24)
            }

            HStack(spacing: 8) {
                if !isNew {
                    Button("Delete") { model.delete(profile); dismiss() }.buttonStyle(PillButtonStyle(destructive: true))
                }
                Spacer()
                Button("Cancel") { dismiss() }.buttonStyle(PillButtonStyle())
                Button(isNew ? "Add session type" : "Save") { model.save(profile); dismiss() }
                    .buttonStyle(PillButtonStyle(primary: true))
                    .keyboardShortcut(.defaultAction)
                    .disabled(profile.name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 24).padding(.vertical, 16)
        }
        .frame(width: 640, height: 680)
        .background(Theme.page)
    }

    private func addSite() {
        let site = SiteMatch.normalize(newSite)
        if !site.isEmpty && !profile.sites.contains(site) { profile.sites.append(site) }
        newSite = ""
    }

    private func generate() async {
        generating = true
        defer { generating = false }
        do {
            var made = try await model.assistant.makeProfile(from: description)
            made.id = profile.id
            profile = made
            description = ""
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}

private struct AppPicker: View {
    @Binding var selected: [AppRef]
    @State private var search = ""

    var body: some View {
        VStack(spacing: 0) {
            TextField("Search apps", text: $search)
                .textFieldStyle(.plain).font(.system(size: 13))
                .padding(.horizontal, 10).frame(height: 30)
                .background(Theme.bubble, in: RoundedRectangle(cornerRadius: 8))
                .padding(10)
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(InstalledApps.all.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }) { app in
                        Button {
                            if selected.contains(app) { selected.removeAll { $0 == app } } else { selected.append(app) }
                        } label: {
                            HStack(spacing: 8) {
                                Image(nsImage: InstalledApps.icon(for: app.bundleID)).resizable().frame(width: 18, height: 18)
                                Text(app.name).font(.system(size: 13))
                                Spacer()
                                if selected.contains(app) { Image(systemName: "checkmark").font(.system(size: 11, weight: .semibold)) }
                            }
                            .padding(.horizontal, 12).frame(height: 30)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .frame(width: 280, height: 360)
    }
}
