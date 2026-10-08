import SwiftUI

/// One day, read like a ChatGPT answer: the AI's headline, the day as a ribbon, a short summary,
/// then plain tables. The composer at the bottom asks about this day.
struct TodayView: View {
    let model: DashboardModel
    @State private var question = ""

    var body: some View {
        ZStack(alignment: .bottom) {
            Page {
                header
                if let report = model.report, report.total > 0 {
                    VStack(alignment: .leading, spacing: 12) {
                        DayRibbon(report: report, showNow: model.isToday)
                        CategoryLegend(totals: report.byCategory)
                    }
                    .padding(.top, 30)
                    summary
                    scores(report)
                    SectionLabel("Where your time went")
                    CategoryTable(totals: report.byCategory, total: report.total)
                    SectionLabel("Most used")
                    MostUsedTable(items: Array(report.items.prefix(10)), model: model)
                    ActivityList(blocks: report.blocks)
                } else {
                    EmptyDay(isToday: model.isToday, paused: model.tracker.isPaused)
                }
            }
            Composer(placeholder: model.isToday ? "Ask about today" : "Ask about this day", text: $question, busy: model.asking) {
                let text = model.isToday ? question : "About \(model.day.formatted(.dateTime.weekday(.wide).month(.wide).day())): \(question)"
                question = ""
                Task { await model.ask(text) }
            }
            .modifier(ComposerDock())
        }
        .background(Theme.page)
        .task(id: model.day) { await model.briefIfStale() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            DayStepper(title: model.isToday ? "Today" : model.day.formatted(.dateTime.weekday(.wide).month(.wide).day()),
                       isCurrent: model.isToday,
                       back: { model.moveDay(by: -1) }, forward: { model.moveDay(by: 1) },
                       reset: { model.show(day: Date()) })
            Text(headline).font(Typeface.greeting).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
            if let report = model.report, report.total > 0 {
                Text("\(Format.duration(report.total)) tracked, \(Format.duration(report.byKind[.productive] ?? 0)) productive, \(Format.duration(report.focusTime)) in focus.")
                    .font(Typeface.body).foregroundStyle(Theme.muted)
            }
        }
    }

    /// The AI's first line when there is one; otherwise the plain facts.
    private var headline: String {
        if let brief = model.brief, let first = brief.text.split(separator: "\n").first,
           !first.hasPrefix("•"), !first.hasPrefix("→") {
            return first.replacingOccurrences(of: "**", with: "")
        }
        guard let report = model.report, report.total > 0 else { return model.isToday ? "Nothing tracked yet today" : "Nothing tracked this day" }
        return "\(Format.duration(report.total)) tracked\(model.isToday ? " so far" : "")"
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                SectionLabel("Summary", detail: model.brief.map { "Written by AI at \(Format.time($0.created))" })
                Spacer()
                if model.briefLoading {
                    ProgressView().controlSize(.small)
                } else if model.assistant.enabled {
                    Button { Task { await model.writeBrief() } } label: { Label("Rewrite", systemImage: "arrow.clockwise") }
                        .buttonStyle(PillButtonStyle())
                }
            }
            if let brief = model.brief {
                MarkdownBlocks(text: brief.text.split(separator: "\n").dropFirst().joined(separator: "\n"))
            } else {
                Text(model.assistant.enabled ? "A summary appears once there's half an hour of your day to talk about."
                                             : "Add OPENAI_API_KEY to the .env file for AI summaries.")
                    .font(Typeface.body).foregroundStyle(Theme.muted)
            }
        }
    }

    private func scores(_ report: DayReport) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel("Scores")
            ScoreRow(title: "Productivity", score: report.productivity)
            ScoreRow(title: "Focus", score: report.focus)
            ScoreRow(title: "Breaks", score: report.breakScore)
        }
    }
}

/// "‹ Today ›", and a way back to today from other days.
struct DayStepper: View {
    let title: String
    let isCurrent: Bool
    let back: () -> Void
    let forward: () -> Void
    let reset: () -> Void

    var body: some View {
        HStack(spacing: 2) {
            Button(action: back) { Image(systemName: "chevron.left").frame(width: 24, height: 24).contentShape(Rectangle()) }
            Text(title).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.muted)
            Button(action: forward) { Image(systemName: "chevron.right").frame(width: 24, height: 24).contentShape(Rectangle()) }
                .disabled(isCurrent).opacity(isCurrent ? 0.3 : 1)
            if !isCurrent {
                Button("Back to today", action: reset).buttonStyle(PillButtonStyle()).padding(.leading, 8)
            }
        }
        .buttonStyle(.plain)
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(Theme.muted)
        .padding(.leading, -6)
    }
}

/// A score as a table row; click for the numbers behind it.
struct ScoreRow: View {
    let title: String
    let score: Score
    @State private var showDetails = false

    var body: some View {
        Button { showDetails.toggle() } label: {
            TableRow {
                Text(title).font(Typeface.row).frame(width: 130, alignment: .leading)
                Text(score.value.map(String.init) ?? "–").font(.system(size: 14, weight: .semibold)).monospacedDigit()
                    .frame(width: 40, alignment: .leading)
                Text(score.caption).font(Typeface.row).foregroundStyle(Theme.muted)
                Spacer()
                Image(systemName: "info.circle").font(.system(size: 12)).foregroundStyle(Theme.muted)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showDetails, arrowEdge: .trailing) {
            VStack(alignment: .leading, spacing: 10) {
                Text("\(title) score").font(.system(size: 13, weight: .semibold))
                ForEach(score.details) { detail in
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(detail.label).font(.system(size: 12.5))
                            if !detail.note.isEmpty { Text(detail.note).font(.system(size: 11)).foregroundStyle(Theme.muted) }
                        }
                        Spacer(minLength: 24)
                        Text(detail.value).font(.system(size: 12.5, weight: .medium)).monospacedDigit()
                    }
                }
            }
            .padding(16)
            .frame(width: 300)
        }
    }
}

/// The legend under the ribbon: each category with its total.
struct CategoryLegend: View {
    let totals: [(id: String, seconds: TimeInterval)]

    var body: some View {
        FlowLayout(spacing: 14) {
            ForEach(totals, id: \.id) { entry in
                let category = Categories.by(entry.id)
                HStack(spacing: 6) {
                    Swatch(color: category.color, size: 8)
                    Text(category.name).foregroundStyle(Theme.ink)
                    Text(Format.duration(entry.seconds)).foregroundStyle(Theme.muted).monospacedDigit()
                }
                .font(.system(size: 12.5))
            }
        }
    }
}

/// Category, a bar for its share, time and percent.
struct CategoryTable: View {
    let totals: [(id: String, seconds: TimeInterval)]
    let total: TimeInterval

    var body: some View {
        VStack(spacing: 0) {
            TableHeader(columns: [("Category", 190), ("", nil), ("Time", 70), ("Share", 50)])
            ForEach(totals, id: \.id) { entry in
                let category = Categories.by(entry.id)
                TableRow {
                    HStack(spacing: 8) {
                        Swatch(color: category.color)
                        Text(category.name).font(Typeface.row).lineLimit(1)
                    }
                    .frame(width: 190, alignment: .leading)
                    GeometryReader { geo in
                        Capsule().fill(category.color)
                            .frame(width: max(3, geo.size.width * entry.seconds / max(total, 1)), height: 6)
                            .frame(maxHeight: .infinity)
                    }
                    .frame(height: 16)
                    Text(Format.duration(entry.seconds)).font(Typeface.row).monospacedDigit().frame(width: 70, alignment: .trailing)
                    Text("\(Int((100 * entry.seconds / max(total, 1)).rounded()))%").font(Typeface.row).monospacedDigit()
                        .foregroundStyle(Theme.muted).frame(width: 50, alignment: .trailing)
                }
            }
        }
    }
}

/// Apps and sites by time, with their icons and categories. Right-click one to move it to another category.
struct MostUsedTable: View {
    let items: [ItemTotal]
    let model: DashboardModel

    var body: some View {
        VStack(spacing: 0) {
            ForEach(items) { item in
                let category = Categories.by(item.category)
                TableRow(verticalPadding: 8) {
                    ItemIcon(bundle: item.bundle, domain: item.domain, size: 22)
                    Text(item.label).font(Typeface.row).lineLimit(1)
                    Spacer()
                    HStack(spacing: 6) {
                        Swatch(color: category.color, size: 7)
                        Text(category.name).font(Typeface.caption).foregroundStyle(Theme.muted)
                    }
                    Text(Format.duration(item.seconds)).font(Typeface.row).monospacedDigit().frame(width: 70, alignment: .trailing)
                }
                .contentShape(Rectangle())
                .contextMenu {
                    Menu("Move to category") {
                        ForEach(Categories.all) { option in
                            Button(option.name) {
                                let key = item.domain.isEmpty ? "app:" + item.bundle : "site:" + item.domain
                                model.classifier.setUserLabel(key: key, category: option.id)
                                model.refresh()
                            }
                        }
                    }
                }
            }
        }
    }
}

/// Every stretch of the day, newest first.
struct ActivityList: View {
    let blocks: [TimelineBlock]
    @State private var showAll = false
    @State private var opened: Int?

    var body: some View {
        // Quick hops (under two minutes) stay on the ribbon but would bury the list.
        let ordered = Array(blocks.reversed().filter { $0.end.timeIntervalSince($0.start) >= 120 })
        let hops = blocks.count - ordered.count
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel("Activity", detail: hops > 0 ? "\(ordered.count) stretches, \(hops) quick hops not listed" : nil)
            ForEach(showAll ? ordered : Array(ordered.prefix(12))) { block in
                let category = Categories.by(block.category)
                TableRow(verticalPadding: 9) {
                    Text("\(Format.time(block.start))–\(Format.time(block.end))")
                        .font(Typeface.row).monospacedDigit().foregroundStyle(Theme.muted)
                        .frame(width: 112, alignment: .leading)
                    Swatch(color: category.color)
                    Text(category.name).font(.system(size: 14, weight: .medium))
                    Text(block.items.prefix(3).map(\.label).joined(separator: ", "))
                        .font(Typeface.row).foregroundStyle(Theme.muted).lineLimit(1)
                    Spacer()
                    Text(Format.duration(block.end.timeIntervalSince(block.start))).font(Typeface.row).monospacedDigit()
                }
                .contentShape(Rectangle())
                .onTapGesture { opened = block.id }
                .popover(isPresented: Binding(get: { opened == block.id }, set: { if !$0 { opened = nil } }), arrowEdge: .leading) {
                    BlockDetails(block: block)
                }
            }
            if ordered.count > 12 {
                Button(showAll ? "Show fewer" : "Show all \(ordered.count)") { withAnimation { showAll.toggle() } }
                    .buttonStyle(PillButtonStyle()).padding(.top, 12)
            }
        }
    }
}

/// An app's icon, or a website's own logo (a globe until it loads).
struct ItemIcon: View {
    let bundle: String
    let domain: String
    var size: CGFloat = 24

    var body: some View {
        if domain.isEmpty {
            Image(nsImage: InstalledApps.icon(for: bundle)).resizable().frame(width: size, height: size)
        } else if let logo = Favicons.shared.image(for: domain) {
            Image(nsImage: logo).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                .frame(width: size * 0.72, height: size * 0.72)
                .frame(width: size, height: size)
                .background(Color.white, in: RoundedRectangle(cornerRadius: size / 4))
                .overlay(RoundedRectangle(cornerRadius: size / 4).strokeBorder(Theme.hairline))
        } else {
            Image(systemName: domain == "localhost" || domain == "127.0.0.1" ? "laptopcomputer" : "globe")
                .font(.system(size: size * 0.52)).foregroundStyle(Theme.muted)
                .frame(width: size, height: size)
                .background(Theme.bubble, in: RoundedRectangle(cornerRadius: size / 4))
        }
    }
}

private struct EmptyDay: View {
    let isToday: Bool
    let paused: Bool

    var body: some View {
        Text(paused ? "Tracking is paused. Resume it from the menu bar when you're ready."
                    : isToday ? "Your day fills in here as you work: every app and site you use, sorted into categories as you go."
                              : "Ribbon wasn't running this day, or you were away.")
            .font(Typeface.body).foregroundStyle(Theme.muted)
            .padding(.top, 24)
    }
}
