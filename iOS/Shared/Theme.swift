import SwiftUI
import UIKit

/// The desktop's look, carried over: white pages, gray fields, hairlines and black primary buttons, in the manner of
/// ChatGPT and Apple's own apps. Color belongs to the data: the eight category colors are the desktop's validated,
/// colorblind-checked palette, with separate light and dark steps.
enum Theme {
    static let page = Color(light: 0xFFFFFF, dark: 0x212121)
    static let bubble = Color(light: 0xF4F4F4, dark: 0x303030)
    static let subtle = Color(light: 0xF7F7F8, dark: 0x2A2A2A)
    static let hairline = Color(light: 0xECECEC, dark: 0x3A3A3A)
    static let track = Color(light: 0xF0F0F0, dark: 0x2E2E2E)
    static let ink = Color(light: 0x0D0D0D, dark: 0xECECEC)
    static let muted = Color(light: 0x8F8F8F, dark: 0x9B9B9B)
    /// The message box: white with a hairline and soft shadow in light mode; a filled gray pill in dark mode.
    static let composer = Color(light: 0xFFFFFF, dark: 0x303030)
    static let composerBorder = Color(light: 0xE3E3E3, dark: 0x303030)
    static let composerShadow = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? .clear : UIColor.black.withAlphaComponent(0.07) })
    static let sendDisabled = Color(light: 0xD7D7D7, dark: 0x4A4A4A)
    /// The chosen part of a segmented control: white on light gray, a lighter gray on dark.
    static let thumb = Color(light: 0xFFFFFF, dark: 0x4A4A4A)
    /// The orb's own color, used only for the orb itself.
    static let ember = Color(light: 0xF0502B, dark: 0xFF6A45)

    /// Productive and distracting are the two ends of one scale: blue and red around a gray middle.
    static let productive = series(1)
    static let neutral = Color(light: 0xBDBCB4, dark: 0x5A5955)
    static let distracting = series(8)
    static let pause = Color(hex: 0xFFB35C)
    /// Switches use iOS's green: on has to look on in light and dark alike.
    static let switchOn = Color(uiColor: .systemGreen)

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

    /// For UIKit surfaces, like the blocked screen.
    static func ui(light: UInt32, dark: UInt32) -> UIColor {
        UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) }
    }
}

extension Color {
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: Theme.ui(light: light, dark: dark))
    }

    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

/// One family, SF Pro, at a small set of sizes: the desktop's, a step larger for a phone held in the hand.
enum Typeface {
    static let greeting = Font.system(size: 28, weight: .regular)
    static let heading = Font.system(size: 17, weight: .semibold)
    static let body = Font.system(size: 16)
    static let row = Font.system(size: 15)
    static let caption = Font.system(size: 13)
    static func figure(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font { .system(size: size, weight: weight) }
}

/// Debug-only helpers for screenshots: `-RibbonScroll 0.5` opens pages scrolled halfway, and `-RibbonAppearance light`
/// forces light or dark. The app copies them into the app group so the Screen Time report, a separate process, follows.
enum ScreenshotOptions {
    private static let group = UserDefaults(suiteName: "group.com.jeremiahlena.ribbon")

    static func value(_ key: String) -> String? {
        #if DEBUG
        return UserDefaults.standard.string(forKey: key) ?? group?.string(forKey: key)
        #else
        return nil
        #endif
    }

    static var scroll: Double { value("RibbonScroll").flatMap(Double.init) ?? 0 }

    static var appearance: ColorScheme? {
        switch value("RibbonAppearance") {
        case "light": .light
        case "dark": .dark
        default: nil
        }
    }
}

extension View {
    func screenshotScroll() -> some View {
        defaultScrollAnchor(UnitPoint(x: 0.5, y: ScreenshotOptions.scroll))
    }

    func screenshotAppearance() -> some View {
        let scheme = ScreenshotOptions.appearance
        return preferredColorScheme(scheme).transformEnvironment(\.colorScheme) { if let scheme { $0 = scheme } }
    }
}

/// The reading column every page uses.
struct Page<Content: View>: View {
    var bottom: CGFloat = 40
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) { content }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, bottom)
        }
        .scrollIndicators(.hidden)
        .screenshotScroll()
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
            if let detail { Text(detail).font(Typeface.caption).foregroundStyle(Theme.muted).lineLimit(1) }
        }
        .padding(.top, 32)
        .padding(.bottom, 8)
    }
}

/// A heading with an action at its right, like "Session types  + New".
struct SectionHeader<Trailing: View>: View {
    let text: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .lastTextBaseline) {
            SectionLabel(text)
            Spacer()
            trailing.padding(.bottom, 6)
        }
    }
}

/// A table row with a hairline under it.
struct TableRow<Content: View>: View {
    var verticalPadding: CGFloat = 12
    var showsLine = true
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) { content }
                .padding(.vertical, verticalPadding)
            if showsLine { Rectangle().fill(Theme.hairline).frame(height: 1) }
        }
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

/// A choice pill, like ChatGPT's suggestions: filled black when chosen.
struct Chip: View {
    let text: String
    var symbol: String?
    var selected = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let symbol { Image(systemName: symbol).font(.system(size: 13)) }
                Text(text).lineLimit(1)
            }
            .font(.system(size: 14))
            .foregroundStyle(selected ? Theme.page : Theme.ink)
            .padding(.horizontal, 14)
            .frame(height: 36)
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
    var large = false

    func makeBody(configuration: Configuration) -> some View {
        PillButton(configuration: configuration, primary: primary, destructive: destructive, large: large)
    }
}

/// A pill that fades when it's disabled, so a button you can't use doesn't look like one you can.
private struct PillButton: View {
    let configuration: ButtonStyleConfiguration
    let primary: Bool
    let destructive: Bool
    let large: Bool
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        configuration.label
            .font(.system(size: large ? 16 : 14, weight: large ? .semibold : .medium))
            .foregroundStyle(primary ? Theme.page : destructive ? Theme.distracting : Theme.ink)
            .padding(.horizontal, large ? 20 : 15)
            .frame(maxWidth: large ? .infinity : nil)
            .frame(height: large ? 50 : 34)
            .background(primary ? Theme.ink : Theme.page, in: Capsule())
            .overlay(Capsule().strokeBorder(primary ? Color.clear : destructive ? Theme.distracting.opacity(0.6) : Theme.hairline))
            .opacity(!isEnabled ? 0.38 : configuration.isPressed ? 0.7 : 1)
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
                .font(.system(size: 16))
                .lineLimit(1...5)
                .padding(.vertical, 8)
                .submitLabel(.send)
                .onSubmit { if !busy { send() } }
            let empty = text.trimmingCharacters(in: .whitespaces).isEmpty
            Button(action: send) {
                Group {
                    if busy { ProgressView().controlSize(.small).tint(Theme.page) } else {
                        Image(systemName: "arrow.up").font(.system(size: 15, weight: .semibold))
                    }
                }
                .foregroundStyle(Theme.page)
                .frame(width: 34, height: 34)
                .background(empty && !busy ? Theme.sendDisabled : Theme.ink, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(empty || busy)
        }
        .padding(.leading, 18)
        .padding(.trailing, 7)
        .padding(.vertical, 6)
        .background(Theme.composer, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(Theme.composerBorder))
        .shadow(color: Theme.composerShadow, radius: 14, y: 4)
    }
}

/// A gray rounded field for typing, like the desktop's form fields.
struct FieldStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.system(size: 16))
            .padding(.horizontal, 14)
            .frame(height: 46)
            .background(Theme.bubble, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.hairline.opacity(0.7)))
    }
}

extension View {
    func fieldStyle() -> some View { modifier(FieldStyle()) }
}

/// A select field, "50 min ⌃⌄": the value in a gray field with the up-and-down chevrons iOS uses for menus.
struct Dropdown<Value: Hashable>: View {
    let selection: Value
    let options: [(Value, String)]
    let onChange: (Value) -> Void

    var body: some View {
        Menu {
            Picker("", selection: Binding(get: { selection }, set: onChange)) {
                ForEach(options, id: \.0) { value, label in Text(label).tag(value) }
            }
        } label: {
            HStack(spacing: 8) {
                Text(options.first { $0.0 == selection }?.1 ?? "").font(.system(size: 15, weight: .medium)).lineLimit(1)
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.muted)
            }
            .foregroundStyle(Theme.ink)
            .padding(.leading, 14).padding(.trailing, 12)
            .frame(height: 42)
            .background(Theme.bubble, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.hairline.opacity(0.7)))
            .contentShape(Rectangle())
        }
        .fixedSize()
    }
}

/// Mutually exclusive choices as a segmented control: a gray track with the chosen one raised in white.
struct PillChoice<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(Value, String)]
    @Namespace private var thumb

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.0) { value, label in
                let chosen = selection == value
                Button {
                    withAnimation(.snappy(duration: 0.25)) { selection = value }
                } label: {
                    Text(label)
                        .font(.system(size: 14, weight: chosen ? .semibold : .regular))
                        .foregroundStyle(chosen ? Theme.ink : Theme.muted)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .background {
                            if chosen {
                                Capsule().fill(Theme.thumb)
                                    .shadow(color: .black.opacity(0.08), radius: 3, y: 1)
                                    .matchedGeometryEffect(id: "thumb", in: thumb)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(chosen ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Theme.bubble, in: Capsule())
    }
}

/// A removable pill, like an app or a website in a session's list.
struct Token<Leading: View>: View {
    let text: String?
    @ViewBuilder var leading: Leading
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 7) {
            leading
            if let text { Text(text).font(.system(size: 14)).lineLimit(1) }
            Button(action: remove) {
                Image(systemName: "xmark").font(.system(size: 9.5, weight: .bold))
                    .frame(width: 20, height: 20).contentShape(Rectangle())
            }
            .buttonStyle(.plain).foregroundStyle(Theme.muted)
        }
        .padding(.leading, 10).padding(.trailing, 5)
        .frame(height: 32)
        .background(Theme.bubble, in: Capsule())
    }
}

/// A labeled row in a form: the label and its note on top, the content below, a hairline under it.
/// On the desktop the label sits to the left; a phone is too narrow for that.
struct FormRow<Content: View>: View {
    let label: String
    var detail: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(label).font(.system(size: 15, weight: .medium))
                    if let detail {
                        Text(detail).font(Typeface.caption).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
                    }
                }
                content
            }
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            Rectangle().fill(Theme.hairline).frame(height: 1)
        }
    }
}

/// A sheet's top bar: the title on the left, a close button on the right.
struct SheetHeader: View {
    let title: String
    let close: () -> Void

    var body: some View {
        HStack {
            Text(title).font(.system(size: 20, weight: .semibold))
            Spacer()
            Button(action: close) {
                Image(systemName: "xmark").font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 34, height: 34)
                    .background(Theme.bubble, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 8)
    }
}

/// A button you have to hold down, filling as you hold: pausing and ending take deliberate effort.
struct HoldButton: View {
    let title: String
    let seconds: Double
    let tint: Color
    var enabled = true
    var track: Color = Theme.bubble
    let action: () -> Void
    @State private var progress: CGFloat = 0
    @State private var holding = false
    @State private var holdTask: Task<Void, Never>?

    var body: some View {
        Text(holding ? "Keep holding…" : title)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(Theme.ink)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(track)
                        Capsule().fill(tint.opacity(0.85)).frame(width: geo.size.width * progress)
                    }
                }
            }
            .clipShape(Capsule())
            .contentShape(Capsule())
            .opacity(enabled ? 1 : 0.4)
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard enabled, !holding else { return }
                    holding = true
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.linear(duration: seconds)) { progress = 1 }
                    holdTask = Task { @MainActor in
                        try? await Task.sleep(for: .seconds(seconds))
                        if !Task.isCancelled {
                            UINotificationFeedbackGenerator().notificationOccurred(.success)
                            action()
                        }
                    }
                }
                .onEnded { _ in
                    holdTask?.cancel()
                    holdTask = nil
                    holding = false
                    withAnimation(.easeOut(duration: 0.25)) { progress = 0 }
                })
            .accessibilityLabel(title)
            .accessibilityAddTraits(.isButton)
    }
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
