import SwiftUI

/// The week, read like the day: the AI's headline, seven days on one hour axis, a summary, then tables.
struct WeekView: View {
    let model: DashboardModel
    @State private var question = ""

    var body: some View {
        ZStack(alignment: .bottom) {
            Page {
                header
                if let week = model.week, week.total > 0 {
                    WeekRibbons(week: week, start: model.weekStart).padding(.top, 30)
                    summary
                    SectionLabel("Days")
                    DaysTable(week: week, start: model.weekStart, open: { model.show(day: $0) })
                    SectionLabel("Where your time went")
                    CategoryTable(totals: week.byCategory, total: week.total)
                    SectionLabel("Most used")
                    MostUsedTable(items: Array(week.items.prefix(10)), model: model)
                } else {
                    Text("Nothing tracked this week yet.").font(Typeface.body).foregroundStyle(Theme.muted).padding(.top, 24)
                }
            }
            Composer(placeholder: "Ask about this week", text: $question, busy: model.asking) {
                let text = model.isThisWeek ? "This week: \(question)"
                    : "The week of \(model.weekStart.formatted(.dateTime.month(.wide).day())): \(question)"
                question = ""
                Task { await model.ask(text) }
            }
            .modifier(ComposerDock())
        }
        .background(Theme.page)
    }

    private var header: some View {
        let end = Calendar.current.date(byAdding: .day, value: 6, to: model.weekStart)!
        return VStack(alignment: .leading, spacing: 10) {
            DayStepper(title: model.isThisWeek ? "This week"
                            : "\(model.weekStart.formatted(.dateTime.month(.abbreviated).day())) to \(end.formatted(.dateTime.month(.abbreviated).day()))",
                       isCurrent: model.isThisWeek,
                       back: { model.moveWeek(by: -1) }, forward: { model.moveWeek(by: 1) },
                       reset: { model.weekStart = Reports.weekStart(for: Date()); model.refresh() })
            Text(headline).font(Typeface.greeting).fixedSize(horizontal: false, vertical: true)
            if let week = model.week, week.total > 0 {
                Text("\(Format.duration(week.total)) tracked, \(Format.duration(week.focusTime)) in focus. Average productivity \(week.averageProductivity.map(String.init) ?? "–"), focus \(week.averageFocus.map(String.init) ?? "–").")
                    .font(Typeface.body).foregroundStyle(Theme.muted)
            }
        }
    }

    private var headline: String {
        if let weekly = model.weekly, let first = weekly.text.split(separator: "\n").first,
           !first.hasPrefix("•"), !first.hasPrefix("→") {
            return first.replacingOccurrences(of: "**", with: "")
        }
        guard let week = model.week, week.total > 0 else { return "A fresh week" }
        return "\(Format.duration(week.total)) tracked\(model.isThisWeek ? " so far" : "")"
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                SectionLabel("Summary", detail: model.weekly.map { "Written by AI \($0.created.formatted(.dateTime.weekday(.wide).hour().minute()))" })
                Spacer()
                if model.weeklyLoading {
                    ProgressView().controlSize(.small)
                } else if model.assistant.enabled {
                    Button { Task { await model.writeWeekly() } } label: {
                        Label(model.weekly == nil ? "Write summary" : "Rewrite", systemImage: model.weekly == nil ? "sparkles" : "arrow.clockwise")
                    }
                    .buttonStyle(PillButtonStyle(primary: model.weekly == nil))
                }
            }
            if let weekly = model.weekly {
                MarkdownBlocks(text: weekly.text.split(separator: "\n").dropFirst().joined(separator: "\n"))
            } else {
                Text("The AI compares this week with last: trends, your best and worst days, and one thing to try.")
                    .font(Typeface.body).foregroundStyle(Theme.muted)
            }
        }
    }
}

/// One row per day: totals, a productive / neutral / distracting bar, and the score.
private struct DaysTable: View {
    let week: WeekReport
    let start: Date
    let open: (Date) -> Void

    var body: some View {
        let days = (0..<7).map { Calendar.current.date(byAdding: .day, value: $0, to: start)! }
        let longest = max(1, week.days.map(\.total).max() ?? 1)
        VStack(spacing: 0) {
            TableHeader(columns: [("Day", 110), ("", nil), ("Tracked", 70), ("Focus", 64), ("Score", 50)])
            ForEach(days, id: \.self) { day in
                let report = week.days.first { Calendar.current.isDate($0.day, inSameDayAs: day) }
                Button { if report?.total ?? 0 > 0 { open(day) } } label: {
                    TableRow {
                        Text(day.formatted(.dateTime.weekday(.wide))).font(Typeface.row).frame(width: 110, alignment: .leading)
                            .foregroundStyle(report == nil ? Theme.muted : Theme.ink)
                        GeometryReader { geo in
                            HStack(spacing: 2) {
                                ForEach(Productivity.allCases, id: \.self) { kind in
                                    let seconds = report?.byKind[kind] ?? 0
                                    if seconds > 0 {
                                        RoundedRectangle(cornerRadius: 2).fill(kind.color)
                                            .frame(width: max(2, (geo.size.width - 4) * seconds / longest), height: 8)
                                    }
                                }
                            }
                            .frame(maxHeight: .infinity)
                        }
                        .frame(height: 16)
                        .help(report.map { r in Productivity.allCases.map { "\($0.label) \(Format.duration(r.byKind[$0] ?? 0))" }.joined(separator: ", ") } ?? "")
                        Text(report.map { Format.duration($0.total) } ?? "").font(Typeface.row).monospacedDigit().frame(width: 70, alignment: .trailing)
                        Text(report.map { Format.duration($0.focusTime) } ?? "").font(Typeface.row).monospacedDigit()
                            .foregroundStyle(Theme.muted).frame(width: 64, alignment: .trailing)
                        Text(report?.productivity.value.map(String.init) ?? "").font(.system(size: 14, weight: .semibold)).monospacedDigit()
                            .frame(width: 50, alignment: .trailing)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            HStack(spacing: 14) {
                ForEach(Productivity.allCases, id: \.self) { kind in
                    HStack(spacing: 6) {
                        Swatch(color: kind.color, size: 8)
                        Text(kind.label)
                    }
                }
            }
            .font(Typeface.caption)
            .foregroundStyle(Theme.muted)
            .padding(.top, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
