import SwiftUI

/// The day as one band of color: each stretch of time in its category's color, focus blocks bracketed above,
/// gaps where you were away, and the orb riding at "now". Hover a stretch for what was in it; click for the list.
struct DayRibbon: View {
    let report: DayReport
    var showNow = false
    var compact = false
    /// Shared range for the week's rows; by default the ribbon fits the day.
    var hours: ClosedRange<Int>?

    @State private var hovered: Int?
    @State private var opened: Int?

    private var ribbonHeight: CGFloat { compact ? 16 : 36 }

    var body: some View {
        let range = hours ?? Self.hourRange(for: [report], showNow: showNow)
        VStack(alignment: .leading, spacing: compact ? 0 : 8) {
            GeometryReader { geo in
                let scale = Scale(day: report.day, hours: range, width: geo.size.width)
                ZStack(alignment: .topLeading) {
                    if !compact { focusBrackets(scale) }
                    ribbon(scale).offset(y: compact ? 0 : 22)
                    if let hovered, let block = report.blocks.first(where: { $0.id == hovered }), !compact {
                        tooltip(block).position(x: min(max(scale.x(block.start.midpoint(block.end)), 130), geo.size.width - 130), y: -30)
                    }
                }
            }
            .frame(height: compact ? ribbonHeight : ribbonHeight + 22)
            if !compact { HourAxis(day: report.day, hours: range) }
        }
    }

    private func ribbon(_ scale: Scale) -> some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: compact ? 4 : 7, style: .continuous).fill(Theme.track)
            ForEach(report.blocks) { block in
                let x = scale.x(block.start), width = max(2, scale.x(block.end) - x - 1)
                let category = Categories.by(block.category)
                RoundedRectangle(cornerRadius: compact ? 2 : 4, style: .continuous)
                    .fill(category.color)
                    .opacity(hovered == nil || hovered == block.id ? 1 : 0.4)
                    .frame(width: width, height: ribbonHeight)
                    .offset(x: x)
                    .onHover { inside in withAnimation(.easeOut(duration: 0.12)) { hovered = inside ? block.id : (hovered == block.id ? nil : hovered) } }
                    .onTapGesture { opened = block.id }
                    .popover(isPresented: Binding(get: { opened == block.id }, set: { if !$0 { opened = nil } }), arrowEdge: .bottom) {
                        BlockDetails(block: block)
                    }
                    .help(compact ? "\(category.name), \(Format.time(block.start))–\(Format.time(block.end))" : "")
            }
            if showNow {
                NowOrb(size: compact ? 9 : 13).offset(x: scale.x(Date()) - (compact ? 4.5 : 6.5))
            }
        }
        .frame(height: ribbonHeight)
    }

    private func focusBrackets(_ scale: Scale) -> some View {
        ForEach(Array(report.focusBlocks.enumerated()), id: \.offset) { _, block in
            let x = scale.x(block.start), width = max(8, scale.x(block.end) - x)
            VStack(alignment: .leading, spacing: 3) {
                if width > 86 {
                    Text("Focus \(Format.duration(block.duration))")
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary).lineLimit(1)
                }
                Bracket().stroke(Color.secondary.opacity(0.7), lineWidth: 1.2).frame(width: width, height: 5)
            }
            .frame(width: width, alignment: .leading)
            .offset(x: x, y: width > 86 ? 0 : 14)
            .help("Focus block, \(Format.time(block.start))–\(Format.time(block.end))")
        }
    }

    private func tooltip(_ block: TimelineBlock) -> some View {
        let category = Categories.by(block.category)
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Swatch(color: category.color)
                Text(category.name).font(.system(size: 12, weight: .semibold))
                Text("\(Format.time(block.start))–\(Format.time(block.end))").font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Text(block.items.prefix(3).map(\.label).joined(separator: ", "))
                .font(.system(size: 11.5)).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.grid))
        .fixedSize()
        .allowsHitTesting(false)
    }

    /// Whole hours from the first activity to the last (or now), at least four.
    /// From the hour the first activity started to the hour the last one ended, counted from the start of the day,
    /// so a night that runs to midnight ends the ribbon at 24 rather than 0. Slivers under a minute (the seconds of
    /// last night that spill past midnight) don't decide where the ribbon starts.
    static func hourRange(for days: [DayReport], showNow: Bool) -> ClosedRange<Int> {
        let calendar = Calendar.current
        func hours(_ date: Date, into day: Date) -> Double { date.timeIntervalSince(calendar.startOfDay(for: day)) / 3600 }
        var starts: [Int] = [], ends: [Int] = []
        for report in days {
            guard let first = report.segments.first(where: { $0.duration >= 60 }) ?? report.segments.first,
                  let last = report.segments.map(\.end).max() else { continue }
            starts.append(Int(hours(first.start, into: report.day).rounded(.down)))
            ends.append(Int(hours(last, into: report.day).rounded(.up)))
        }
        if showNow { ends.append(calendar.component(.hour, from: Date()) + 1) }
        let first = starts.min() ?? 9
        let last = min(24, max(ends.max() ?? 17, first + 4))
        return first...last
    }
}

/// Maps a time of day to an x position.
struct Scale {
    let start: Date
    let seconds: TimeInterval
    let width: CGFloat

    init(day: Date, hours: ClosedRange<Int>, width: CGFloat) {
        start = Calendar.current.date(bySettingHour: hours.lowerBound, minute: 0, second: 0, of: day)!
        seconds = TimeInterval(hours.upperBound - hours.lowerBound) * 3600
        self.width = width
    }

    func x(_ date: Date) -> CGFloat {
        CGFloat(min(max(date.timeIntervalSince(start) / seconds, 0), 1)) * width
    }
}

struct HourAxis: View {
    let day: Date
    let hours: ClosedRange<Int>

    var body: some View {
        GeometryReader { geo in
            let perHour = geo.size.width / CGFloat(max(1, hours.count - 1))
            let step = perHour < 46 ? 2 : 1
            ForEach(Array(hours).filter { ($0 - hours.lowerBound) % step == 0 }, id: \.self) { hour in
                let date = Calendar.current.date(bySettingHour: hour % 24, minute: 0, second: 0, of: day)!
                Text(date.formatted(.dateTime.hour()))
                    .font(.system(size: 11)).monospacedDigit().foregroundStyle(.tertiary)
                    .fixedSize()
                    .position(x: CGFloat(hour - hours.lowerBound) * perHour, y: 6)
            }
        }
        .frame(height: 14)
    }
}

/// The orb, small: a glowing ember sphere marking the present moment.
struct NowOrb: View {
    var size: CGFloat = 16

    var body: some View {
        Circle()
            .fill(RadialGradient(colors: [Color(hex: 0xFFE2B8), Color(hex: 0xFF5A36), Color(hex: 0xE8235F)],
                                 center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: size * 0.7))
            .frame(width: size, height: size)
            .overlay(Circle().strokeBorder(.white.opacity(0.85), lineWidth: 1.5))
            .shadow(color: Color(hex: 0xFF5A36).opacity(0.7), radius: size * 0.5)
            .help("Now")
    }
}

/// A focus block's span: a line with small end ticks.
private struct Bracket: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + 0.5, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + 0.5, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - 0.5, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - 0.5, y: rect.maxY))
        return path
    }
}

struct BlockDetails: View {
    let block: TimelineBlock

    var body: some View {
        let category = Categories.by(block.category)
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Swatch(color: category.color)
                Text(category.name).font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("\(Format.time(block.start))–\(Format.time(block.end))").font(.system(size: 12)).foregroundStyle(.secondary)
            }
            ForEach(block.items) { item in
                HStack(spacing: 8) {
                    ItemIcon(bundle: item.bundle, domain: item.domain)
                    Text(item.label).font(.system(size: 12.5)).lineLimit(1)
                    Spacer(minLength: 20)
                    Text(Format.duration(item.seconds)).font(.system(size: 12.5)).monospacedDigit().foregroundStyle(.secondary)
                }
            }
        }
        .padding(14)
        .frame(width: 300)
    }
}

/// Seven days on one shared hour axis: when you work, at a glance.
struct WeekRibbons: View {
    let week: WeekReport
    let start: Date

    var body: some View {
        let days = (0..<7).map { Calendar.current.date(byAdding: .day, value: $0, to: start)! }
        let range = DayRibbon.hourRange(for: week.days.filter { $0.total > 0 }, showNow: false)
        VStack(alignment: .leading, spacing: 10) {
            ForEach(days, id: \.self) { day in
                let report = week.days.first { Calendar.current.isDate($0.day, inSameDayAs: day) }
                HStack(spacing: 14) {
                    Text(day.formatted(.dateTime.weekday(.abbreviated)))
                        .font(.system(size: 12.5, weight: Calendar.current.isDateInToday(day) ? .semibold : .regular))
                        .foregroundStyle(report == nil ? .tertiary : .primary)
                        .frame(width: 34, alignment: .leading)
                    if let report, report.total > 0 {
                        DayRibbon(report: report, showNow: Calendar.current.isDateInToday(day), compact: true, hours: range)
                            .frame(height: 16)
                    } else {
                        RoundedRectangle(cornerRadius: 4).fill(Theme.track).frame(height: 16)
                    }
                    Text(report.map { $0.total > 0 ? Format.duration($0.total) : "" } ?? "")
                        .font(Typeface.figure(13, .medium)).monospacedDigit()
                        .frame(width: 64, alignment: .trailing)
                }
            }
            HStack(spacing: 14) {
                Color.clear.frame(width: 34, height: 1)
                HourAxis(day: start, hours: range)
                Color.clear.frame(width: 64, height: 1)
            }
        }
    }
}

private extension Date {
    func midpoint(_ other: Date) -> Date { Date(timeIntervalSince1970: (timeIntervalSince1970 + other.timeIntervalSince1970) / 2) }
}
