import AppKit
import SwiftUI

/// A quiet, grayscale interface in the manner of ChatGPT and Apple's own apps: white pages, hairlines,
/// black primary buttons. Color belongs to the data: the eight category colors are a validated,
/// colorblind-checked palette with separate light and dark steps (checked against `page`).
enum Theme {
    static let page = Color(light: 0xFFFFFF, dark: 0x212121)
    static let bubble = Color(light: 0xF4F4F4, dark: 0x303030)
    static let subtle = Color(light: 0xF7F7F8, dark: 0x2A2A2A)
    static let hairline = Color(light: 0xECECEC, dark: 0x3A3A3A)
    static let track = Color(light: 0xF0F0F0, dark: 0x2E2E2E)
    static let ink = Color(light: 0x0D0D0D, dark: 0xECECEC)
    static let muted = Color(light: 0x8F8F8F, dark: 0x9B9B9B)
    /// The composer: white with a hairline and soft shadow in light mode; a filled gray pill in dark mode, like ChatGPT.
    static let composer = Color(light: 0xFFFFFF, dark: 0x303030)
    static let composerBorder = Color(light: 0xE3E3E3, dark: 0x303030)
    static let composerShadow = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .clear : NSColor.black.withAlphaComponent(0.07)
    })
    static let sendDisabled = Color(light: 0xD7D7D7, dark: 0x4A4A4A)
    /// The orb's own color, used only for the orb itself.
    static let ember = Color(light: 0xF0502B, dark: 0xFF6A45)

    // Older names some views still use.
    static var surface: Color { page }
    static var raised: Color { bubble }
    static var grid: Color { hairline }
    static var border: Color { hairline }
    static var ink2: Color { muted }
    static var baseline: Color { hairline }
    static var accent: Color { ink }
    static var coachTint: Color { subtle }

    /// Productive and distracting are the two ends of one scale: blue and red around a gray middle.
    static let productive = series(1)
    static let neutral = Color(light: 0xBDBCB4, dark: 0x5A5955)
    static let distracting = series(8)

    static func series(_ slot: Int?) -> Color {
        switch slot {
        case 1: Color(light: 0x2A78D6, dark: 0x3987E5)
        case 2: Color(light: 0xEB6834, dark: 0xD95926)
        case 3: Color(light: 0x1BAF7A, dark: 0x199E70)
        case 4: Color(light: 0xEDA100, dark: 0xC98500)
        case 5: Color(light: 0xE87BA4, dark: 0xD55181)
        case 6: Color(light: 0x008300, dark: 0x008300)
        case 7: Color(light: 0x4A3AA7, dark: 0x9085E9)
        case 8: Color(light: 0xE34948, dark: 0xE66767)
        default: Color(light: 0xA8A7A0, dark: 0x6B6A65)
        }
    }
}

extension Color {
    init(light: UInt32, dark: UInt32) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(hex: dark) : NSColor(hex: light)
        })
    }
}

extension NSColor {
    convenience init(hex: UInt32) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

/// One family, SF Pro, at a small set of sizes.
enum Typeface {
    static let greeting = Font.system(size: 28, weight: .regular)
    static let heading = Font.system(size: 17, weight: .semibold)
    static let body = Font.system(size: 15)
    static let row = Font.system(size: 14)
    static let caption = Font.system(size: 12.5)
    static func figure(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font { .system(size: size, weight: weight) }
    static func prose(_ size: CGFloat = 15, _ weight: Font.Weight = .regular) -> Font { .system(size: size, weight: weight) }
}

/// The centered reading column every page uses, like a ChatGPT conversation.
struct Page<Content: View>: View {
    var width: CGFloat = 760
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) { content }
                .frame(maxWidth: width, alignment: .leading)
                .padding(.horizontal, 32)
                .padding(.top, 36)
                .padding(.bottom, 120)
                .frame(maxWidth: .infinity)
        }
        .background(Theme.page)
    }
}

/// A section heading inside a page, like the headings in a ChatGPT answer.
struct SectionLabel: View {
    let text: String
    var detail: String?
    init(_ text: String, detail: String? = nil) { self.text = text; self.detail = detail }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(text).font(Typeface.heading).foregroundStyle(Theme.ink)
            if let detail { Text(detail).font(Typeface.caption).foregroundStyle(Theme.muted) }
        }
        .padding(.top, 36)
        .padding(.bottom, 10)
    }
}

/// A group with an optional heading; no box, just the content.
struct Card<Content: View>: View {
    var title: String?
    var trailing: AnyView?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if title != nil || trailing != nil {
                HStack(alignment: .firstTextBaseline) {
                    if let title { SectionLabel(title) }
                    Spacer()
                    trailing
                }
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A table row with a hairline under it.
struct TableRow<Content: View>: View {
    var verticalPadding: CGFloat = 10
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) { content }
                .padding(.vertical, verticalPadding)
            Rectangle().fill(Theme.hairline).frame(height: 1)
        }
    }
}

/// A table's column titles.
struct TableHeader: View {
    let columns: [(String, CGFloat?)]

    var body: some View {
        TableRow(verticalPadding: 8) {
            ForEach(Array(columns.enumerated()), id: \.offset) { index, column in
                Group {
                    if let width = column.1 {
                        Text(column.0).frame(width: width, alignment: index == 0 ? .leading : .trailing)
                    } else {
                        Text(column.0).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .font(.system(size: 12.5, weight: .medium))
        .foregroundStyle(Theme.muted)
    }
}

/// The small square that ties a category's color to its name.
struct Swatch: View {
    let color: Color
    var size: CGFloat = 9

    var body: some View {
        RoundedRectangle(cornerRadius: 2.5, style: .continuous).fill(color).frame(width: size, height: size)
    }
}

/// A suggestion pill, like ChatGPT's.
struct Chip: View {
    let text: String
    var symbol: String?
    var selected = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let symbol { Image(systemName: symbol).font(.system(size: 12)) }
                Text(text).lineLimit(1)
            }
            .font(.system(size: 13))
            .foregroundStyle(selected ? Theme.page : Theme.ink)
            .padding(.horizontal, 13)
            .padding(.vertical, 8)
            .background(selected ? Theme.ink : Theme.page, in: Capsule())
            .overlay(Capsule().strokeBorder(selected ? Color.clear : Theme.hairline))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// Black capsule for the main action on a page; outlined capsule for everything else.
struct PillButtonStyle: ButtonStyle {
    var primary = false
    var destructive = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(primary ? Theme.page : destructive ? Theme.distracting : Theme.ink)
            .padding(.horizontal, 14)
            .frame(height: 30)
            .background(primary ? Theme.ink : Theme.page, in: Capsule())
            .overlay(Capsule().strokeBorder(primary ? Color.clear : destructive ? Theme.distracting.opacity(0.6) : Theme.hairline))
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(Capsule())
    }
}

/// The message box: a rounded field with a black send button, like ChatGPT's composer.
struct Composer: View {
    let placeholder: String
    @Binding var text: String
    var busy = false
    let send: () -> Void

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField(placeholder, text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .lineLimit(1...6)
                .padding(.vertical, 7)
                .onSubmit { if !busy { send() } }
            let empty = text.trimmingCharacters(in: .whitespaces).isEmpty
            Button(action: send) {
                Group {
                    if busy { ProgressView().controlSize(.small) } else {
                        Image(systemName: "arrow.up").font(.system(size: 13, weight: .semibold))
                    }
                }
                .foregroundStyle(Theme.page)
                .frame(width: 30, height: 30)
                .background(empty && !busy ? Theme.sendDisabled : Theme.ink, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(empty || busy)
        }
        .padding(.leading, 18)
        .padding(.trailing, 8)
        .padding(.vertical, 7)
        .background(Theme.composer, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Theme.composerBorder))
        .shadow(color: Theme.composerShadow, radius: 14, y: 4)
    }
}

/// The white fade behind a composer pinned to the bottom of a page, so text scrolls away under it.
struct ComposerDock: ViewModifier {
    func body(content: Content) -> some View {
        content
            .frame(maxWidth: 760)
            .padding(.horizontal, 32)
            .padding(.top, 36)
            .padding(.bottom, 20)
            .frame(maxWidth: .infinity)
            .background(LinearGradient(stops: [.init(color: Theme.page.opacity(0), location: 0), .init(color: Theme.page, location: 0.4)],
                                       startPoint: .top, endPoint: .bottom))
    }
}

/// A plain dropdown, "50 min ⌄", like the ones in ChatGPT's settings (instead of a heavy pop-up button).
struct Dropdown<Value: Hashable>: View {
    let selection: Value
    let options: [(Value, String)]
    let onChange: (Value) -> Void

    var body: some View {
        Menu {
            ForEach(options, id: \.0) { value, label in
                Button { onChange(value) } label: {
                    if value == selection { Label(label, systemImage: "checkmark") } else { Text(label) }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Text(options.first { $0.0 == selection }?.1 ?? "")
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold))
            }
            .font(.system(size: 13))
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(Theme.bubble, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

/// Mutually exclusive choices as pills; the chosen one is filled.
struct PillChoice<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(Value, String)]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(options, id: \.0) { value, label in
                Chip(text: label, selected: selection == value) { selection = value }
            }
        }
    }
}

/// A removable token, like an app or a website in a session's list.
struct Token<Leading: View>: View {
    let text: String
    @ViewBuilder var leading: Leading
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            leading
            Text(text).font(.system(size: 12.5)).lineLimit(1)
            Button(action: remove) { Image(systemName: "xmark").font(.system(size: 8.5, weight: .bold)) }
                .buttonStyle(.plain).foregroundStyle(Theme.muted)
        }
        .padding(.leading, 9).padding(.trailing, 8)
        .frame(height: 26)
        .background(Theme.bubble, in: Capsule())
    }
}

/// A labeled row in a form: the label on the left, the content on the right, a hairline below.
struct FormRow<Content: View>: View {
    let label: String
    var detail: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(label).font(.system(size: 13.5)).padding(.top, 6)
                    if let detail { Text(detail).font(.system(size: 12)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true) }
                }
                .frame(width: 150, alignment: .leading)
                VStack(alignment: .leading, spacing: 10) { content }
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 13)
            Rectangle().fill(Theme.hairline).frame(height: 1)
        }
    }
}

/// Renders what the AI writes: headings, bullets, numbered lists, tables and inline bold, like a ChatGPT answer.
struct MarkdownBlocks: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .heading(let line):
                    Text(markdown(line)).font(Typeface.heading).padding(.top, 6)
                case .paragraph(let line):
                    Text(markdown(line)).font(Typeface.body).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
                case .bullet(let line, let marker):
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(marker).font(Typeface.body).foregroundStyle(Theme.muted).frame(minWidth: 12, alignment: .leading)
                        Text(markdown(line)).font(Typeface.body).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.leading, 4)
                case .table(let rows):
                    VStack(spacing: 0) {
                        ForEach(Array(rows.enumerated()), id: \.offset) { index, cells in
                            TableRow(verticalPadding: 8) {
                                ForEach(Array(cells.enumerated()), id: \.offset) { _, cell in
                                    Text(markdown(cell))
                                        .font(index == 0 ? .system(size: 13, weight: .semibold) : .system(size: 13.5))
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }
                    }
                }
            }
        }
        .foregroundStyle(Theme.ink)
        .textSelection(.enabled)
    }

    private enum Block { case heading(String), paragraph(String), bullet(String, String), table([[String]]) }

    private var blocks: [Block] {
        var blocks: [Block] = []
        var table: [[String]] = []
        func flushTable() { if !table.isEmpty { blocks.append(.table(table)); table = [] } }
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("|") {
                let cells = line.split(separator: "|", omittingEmptySubsequences: false).dropFirst().dropLast()
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                if !cells.allSatisfy({ $0.allSatisfy { "-: ".contains($0) } }) { table.append(Array(cells)) }
                continue
            }
            flushTable()
            if line.isEmpty { continue }
            if line.hasPrefix("#") { blocks.append(.heading(line.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces))) }
            else if line.hasPrefix("- ") || line.hasPrefix("• ") || line.hasPrefix("* ") { blocks.append(.bullet(String(line.dropFirst(2)), "•")) }
            else if let dot = line.firstIndex(of: "."), let number = Int(line[..<dot]), line[line.index(after: dot)...].hasPrefix(" ") {
                blocks.append(.bullet(String(line[line.index(dot, offsetBy: 2)...]), "\(number)."))
            }
            else if line.hasPrefix("→") { blocks.append(.paragraph("**Next:** " + line.dropFirst().trimmingCharacters(in: .whitespaces))) }
            else { blocks.append(.paragraph(line)) }
        }
        flushTable()
        return blocks
    }
}

func markdown(_ text: String) -> AttributedString {
    (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
        ?? AttributedString(text)
}

/// Lays children out left to right, wrapping onto new lines.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0, widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width { x = 0; y += lineHeight + spacing; lineHeight = 0 }
            x += size.width + spacing
            widest = max(widest, x - spacing)
            lineHeight = max(lineHeight, size.height)
        }
        return CGSize(width: min(widest, width), height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, lineHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX { x = bounds.minX; y += lineHeight + spacing; lineHeight = 0 }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}
