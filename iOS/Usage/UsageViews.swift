import SwiftUI
import FamilyControls

/// One day of Screen Time, read like the desktop's Today: a plain headline, the day as a ribbon of color, then tables.
/// Drawn by the report extension from what iOS hands it.
struct TodayUsageView: View {
    let usage: DayUsage

    var body: some View {
        UsagePage {
            VStack(alignment: .leading, spacing: 8) {
                Text(headline).font(Typeface.greeting).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
                if usage.total > 0 {
                    Text(subline).font(Typeface.body).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
                }
            }
            if usage.total > 0 {
                VStack(alignment: .leading, spacing: 14) {
                    DayRibbon(hours: usage.hours, day: usage.day, range: DayRibbon.hourRange([usage]), now: usage.isToday ? usage.now : nil)
                    CategoryLegend(totals: usage.categories)
                }
                .padding(.top, 26)
                SectionLabel("At a glance")
                FactRow(title: "Productivity", value: usage.productivity.map(String.init) ?? "–",
                        caption: "\(usage.productiveShare)% of your time was productive")
                FactRow(title: "Distracting", value: Format.duration(usage.seconds(.distracting)),
                        caption: "Social, games, entertainment and your distracting categories")
                FactRow(title: "Pickups", value: "\(usage.pickups)",
                        caption: usage.firstPickup.map { "First at \(Format.time($0))" } ?? "")
                SectionLabel("Where your time went")
                CategoryTable(totals: usage.categories, total: usage.total)
                SectionLabel("Most used")
                AppTable(apps: Array(usage.apps.prefix(10)))
            } else {
                Text(usage.isToday ? "Your day fills in here as you use your phone: every app, sorted into Apple's categories."
                                   : "Nothing was recorded on this phone this day.")
                    .font(Typeface.body).foregroundStyle(Theme.muted).padding(.top, 20)
            }
        }
    }

    private var headline: String {
        guard usage.total > 0 else { return usage.isToday ? "Nothing on your phone yet today" : "Nothing recorded this day" }
        return "\(Format.duration(usage.total)) on your phone\(usage.isToday ? " so far" : "")"
    }

    private var subline: String {
        "\(Format.duration(usage.seconds(.productive))) productive, \(Format.duration(usage.seconds(.distracting))) distracting, "
            + "\(usage.pickups) pickup\(usage.pickups == 1 ? "" : "s")."
    }
}

/// A week of Screen Time: seven days on one hour axis, then the week's tables.
struct WeekUsageView: View {
    let week: WeekUsage

    var body: some View {
        UsagePage {
            VStack(alignment: .leading, spacing: 8) {
                Text(headline).font(Typeface.greeting).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
                if week.total > 0 {
                    Text("A day's average is \(Format.duration(week.total / Double(max(1, week.activeDays)))). "
                         + "\(Format.duration(week.seconds(.distracting))) of the week was distracting.")
                        .font(Typeface.body).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
                }
            }
            if week.total > 0 {
                WeekRibbons(week: week).padding(.top, 26)
                SectionLabel("Where your time went")
                CategoryTable(totals: week.categories, total: week.total)
                SectionLabel("Most used")
                AppTable(apps: Array(week.apps.prefix(10)))
            } else {
                Text("Nothing recorded on this phone this week yet.").font(Typeface.body).foregroundStyle(Theme.muted).padding(.top, 20)
            }
        }
    }

    private var headline: String {
        guard week.total > 0 else { return "A fresh week" }
        let thisWeek = Calendar.current.weekStart(for: Date()) == week.start
        return "\(Format.duration(week.total)) on your phone \(thisWeek ? "this week so far" : "that week")"
    }
}

/// The report's own scrolling page, matching the app's margins.
struct UsagePage<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                #if DEBUG
                if UserDefaults(suiteName: "group.com.jeremiahlena.ribbon")?.bool(forKey: "RibbonShot") == true {
                    Text("Debug: this view can read Ribbon's app group (\(YourCategories.shared.all.count) categories).")
                        .font(.system(size: 11)).foregroundStyle(Theme.muted).padding(.bottom, 8)
                }
                #endif
                content
            }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 6)
                .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .screenshotScroll()
        .background(Theme.page)
        .screenshotAppearance()
    }
}

/// The day as one band of color: each hour filled by how long each category was on screen, with the orb at "now".
struct DayRibbon: View {
    let hours: [HourUsage]
    let day: Date
    let range: ClosedRange<Int>
    /// Where to put the orb, on today's ribbon.
    var now: Date?
    var compact = false

    private var height: CGFloat { compact ? 14 : 36 }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { geo in
                let perHour = geo.size.width / CGFloat(max(1, range.upperBound - range.lowerBound))
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: compact ? 4 : 7, style: .continuous).fill(Theme.track)
                    ForEach(hours) { hour in
                        let x = x(hour.start, perHour: perHour)
                        HStack(spacing: 0) {
                            ForEach(Self.ordered(hour.byCategory), id: \.0) { name, seconds in
                                Rectangle().fill(UsageCategory.of(name).color)
                                    .frame(width: max(1, perHour * min(1, seconds / 3600)))
                            }
                        }
                        .frame(height: height)
                        .clipShape(RoundedRectangle(cornerRadius: compact ? 2 : 4, style: .continuous))
                        .frame(width: max(2, perHour - 1.5), alignment: .leading)
                        .offset(x: x)
                    }
                    if let now {
                        NowOrb(size: compact ? 9 : 13)
                            .offset(x: min(max(0, x(now, perHour: perHour) - (compact ? 4.5 : 6.5)), geo.size.width - 13))
                    }
                }
            }
            .frame(height: height)
            if !compact { HourAxis(range: range, day: day) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Your day by the hour")
    }

    private func x(_ date: Date, perHour: CGFloat) -> CGFloat {
        let start = Calendar.current.startOfDay(for: day).addingTimeInterval(TimeInterval(range.lowerBound * 3600))
        return CGFloat(date.timeIntervalSince(start) / 3600) * perHour
    }

    /// Categories in a fixed order, so the colors sit the same way in every hour.
    static func ordered(_ byCategory: [String: TimeInterval]) -> [(String, TimeInterval)] {
        byCategory.filter { $0.value >= 20 }
            .sorted { (UsageCategory.of($0.key).slot ?? 99, $0.key) < (UsageCategory.of($1.key).slot ?? 99, $1.key) }
    }

    /// From the hour the first use began to the hour the last one ended (or now), at least six hours.
    static func hourRange(_ days: [DayUsage]) -> ClosedRange<Int> {
        let calendar = Calendar.current
        var first = 24, last = 0
        for day in days {
            for hour in day.hours where hour.total >= 60 {
                let h = calendar.component(.hour, from: hour.start)
                first = min(first, h)
                last = max(last, h + 1)
            }
            if day.isToday { last = max(last, calendar.component(.hour, from: day.now) + 1) }
        }
        if first > last { return 8...20 }
        let end = min(24, max(last, first + 6))
        return min(first, end - 6)...end
    }
}

struct HourAxis: View {
    let range: ClosedRange<Int>
    let day: Date

    var body: some View {
        GeometryReader { geo in
            let span = max(1, range.upperBound - range.lowerBound)
            let perHour = geo.size.width / CGFloat(span)
            let step = perHour < 22 ? 4 : perHour < 44 ? 2 : 1
            ForEach(Array(range).filter { ($0 - range.lowerBound) % step == 0 }, id: \.self) { hour in
                Text(String(format: "%02d", hour % 24))
                    .font(.system(size: 11)).monospacedDigit().foregroundStyle(Theme.muted.opacity(0.8))
                    .fixedSize()
                    .position(x: min(max(CGFloat(hour - range.lowerBound) * perHour, 8), geo.size.width - 8), y: 6)
            }
        }
        .frame(height: 14)
    }
}

/// Seven days on one shared hour axis: when you're on your phone, at a glance.
struct WeekRibbons: View {
    let week: WeekUsage

    var body: some View {
        let range = DayRibbon.hourRange(week.days)
        VStack(alignment: .leading, spacing: 10) {
            ForEach(week.days, id: \.day) { day in
                HStack(spacing: 12) {
                    Text(day.day.formatted(.dateTime.weekday(.abbreviated)))
                        .font(.system(size: 13, weight: day.isToday ? .semibold : .regular))
                        .foregroundStyle(day.total > 0 ? Theme.ink : Theme.muted)
                        .frame(width: 34, alignment: .leading)
                    DayRibbon(hours: day.hours, day: day.day, range: range, now: day.isToday ? day.now : nil, compact: true)
                    Text(day.total > 0 ? Format.duration(day.total) : "")
                        .font(.system(size: 13, weight: .medium)).monospacedDigit()
                        .lineLimit(1).minimumScaleFactor(0.8)
                        .frame(width: 62, alignment: .trailing)
                }
            }
            HStack(spacing: 12) {
                Color.clear.frame(width: 34, height: 1)
                HourAxis(range: range, day: week.start)
                Color.clear.frame(width: 62, height: 1)
            }
        }
    }
}

/// The legend under the ribbon: each category with its total.
struct CategoryLegend: View {
    let totals: [CategoryTotal]

    var body: some View {
        FlowLayout(spacing: 14) {
            ForEach(totals) { entry in
                HStack(spacing: 6) {
                    Swatch(color: entry.category.color, size: 8)
                    Text(entry.category.name).foregroundStyle(Theme.ink)
                    Text(Format.duration(entry.seconds)).foregroundStyle(Theme.muted).monospacedDigit()
                }
                .font(.system(size: 13))
            }
        }
    }
}

/// A number with what it means: the title and its note on the left, the number on the right.
struct FactRow: View {
    let title: String
    let value: String
    let caption: String

    var body: some View {
        TableRow {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(Typeface.row)
                if !caption.isEmpty {
                    Text(caption).font(Typeface.caption).foregroundStyle(Theme.muted).lineLimit(2)
                }
            }
            Spacer(minLength: 12)
            Text(value).font(.system(size: 17, weight: .semibold)).monospacedDigit()
        }
    }
}

/// Category, time and share, with a bar for the share under each: the desktop's table, folded for a narrow screen.
struct CategoryTable: View {
    let totals: [CategoryTotal]
    let total: TimeInterval

    var body: some View {
        VStack(spacing: 0) {
            ForEach(totals) { entry in
                VStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Swatch(color: entry.category.color)
                            Text(entry.category.name).font(Typeface.row).lineLimit(1)
                            Spacer(minLength: 8)
                            Text(Format.duration(entry.seconds)).font(Typeface.row).monospacedDigit()
                            Text("\(Int((100 * entry.seconds / max(total, 1)).rounded()))%").font(Typeface.caption).monospacedDigit()
                                .foregroundStyle(Theme.muted).frame(width: 36, alignment: .trailing)
                        }
                        GeometryReader { geo in
                            Capsule().fill(entry.category.color)
                                .frame(width: max(4, geo.size.width * entry.seconds / max(totals.first?.seconds ?? total, 1)))
                        }
                        .frame(height: 5)
                        .padding(.leading, 17)
                        .padding(.trailing, 44)
                    }
                    .padding(.vertical, 12)
                    Rectangle().fill(Theme.hairline).frame(height: 1)
                }
            }
        }
    }
}

/// Apps by time, with their icons and categories.
struct AppTable: View {
    let apps: [AppUsage]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(apps) { app in
                TableRow(verticalPadding: 10) {
                    AppIcon(app: app, size: 30)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(app.name).font(Typeface.row).lineLimit(1)
                        HStack(spacing: 6) {
                            Swatch(color: app.category.color, size: 7)
                            Text(caption(app))
                                .font(.system(size: 12)).foregroundStyle(Theme.muted).lineLimit(1)
                        }
                    }
                    Spacer(minLength: 8)
                    Text(Format.duration(app.seconds)).font(Typeface.row).monospacedDigit()
                }
            }
        }
    }
}

private func caption(_ app: AppUsage) -> String {
    var parts = [app.category.name]
    if app.pickups > 0 { parts.append("\(app.pickups) pickup\(app.pickups == 1 ? "" : "s")") }
    return parts.joined(separator: " · ")
}

/// An app's own icon from iOS, or its first letter while there isn't one.
struct AppIcon: View {
    let app: AppUsage
    var size: CGFloat = 28

    var body: some View {
        if let token = app.token {
            Label(token).labelStyle(.iconOnly).scaleEffect(size / 28).frame(width: size, height: size)
        } else {
            Text(String(app.name.prefix(1)))
                .font(.system(size: size * 0.46, weight: .semibold)).foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(app.category.color.gradient, in: RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
        }
    }
}
