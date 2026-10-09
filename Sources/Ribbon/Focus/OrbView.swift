import SwiftUI

/// Fills the whole overlay window; only the orb, its hover label and the nudge caption draw anything.
/// Clicks on the orb are handled in FocusController (the panel never becomes key, so SwiftUI never sees them).
struct OverlayView: View {
    let model: OrbModel
    var body: some View {
        GeometryReader { geo in
            let center = OrbLayout.center(in: geo.size, nudging: model.nudging)
            let core = OrbLayout.core(nudging: model.nudging)
            let ringRadius = OrbLayout.ringDiameter(core) / 2

            ZStack {
                if let toast = model.toast, !model.nudging, !model.panelOpen {
                    Toast(text: toast, symbol: model.toastSymbol)
                        .frame(width: 340, alignment: .trailing)
                        .position(x: center.x - ringRadius - 12 - 170, y: center.y)
                        .transition(.opacity.combined(with: .offset(x: 10)))
                } else if model.hovering && !model.nudging && !model.panelOpen {
                    HoverLabel(model: model)
                        .frame(width: 340, alignment: .trailing)
                        .position(x: center.x - ringRadius - 12 - 170, y: center.y)
                        .transition(.opacity.combined(with: .offset(x: 6)))
                }

                OrbView(
                    core: core,
                    phase: model.phase,
                    drifting: model.nudging,
                    paused: model.paused,
                    phaseStart: model.phaseStart,
                    phaseEnd: model.phaseEnd,
                    pausedAt: model.pausedAt,
                    visible: model.visible
                )
                .scaleEffect(model.holding ? 0.9 : 1)
                .position(center)

                if model.nudging, let text = model.nudgeText {
                    Caption(text: text, holding: model.holding)
                        .frame(width: 600)
                        .position(x: center.x, y: center.y + ringRadius + 90)
                        .transition(.opacity.combined(with: .offset(y: 12)).animation(.easeOut(duration: 0.45).delay(0.55)))
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .environment(\.colorScheme, .dark)
    }
}

/// The glowing orb and its timer ring. Animatable so the size grows smoothly when it floats to the front.
/// The orb is drawn once as an image. During a focus session or a nudge it breathes (a slow scale run by
/// Core Animation, outside Ribbon), and the ring moves once a second. While the orb is hidden, nothing updates.
struct OrbView: View, Animatable {
    var core: CGFloat
    let phase: Phase
    let drifting: Bool
    let paused: Bool
    let phaseStart: Date
    let phaseEnd: Date
    let pausedAt: Date?
    let visible: Bool

    var animatableData: CGFloat {
        get { core }
        set { core = newValue }
    }

    var body: some View {
        let palette = Palette.of(phase, drifting: drifting, paused: paused)
        let ringDiameter = OrbLayout.ringDiameter(core)
        let lineWidth = max(2.5, core * 0.035)
        // Only a running focus session, or a nudge, makes the orb move.
        let breathing = visible && (drifting || (phase == .focus && !paused))

        ZStack {
            Circle()
                .fill(palette.a.opacity(phase == .idle ? 0.3 : 0.5))
                .frame(width: core * 1.35, height: core * 1.35)
                .blur(radius: core * 0.35)

            TimelineView(.animation(minimumInterval: 1, paused: !visible || phase == .idle)) { context in
                ZStack {
                    Circle().stroke(palette.ring.opacity(0.16), lineWidth: lineWidth)
                    Circle()
                        .trim(from: 0, to: remaining(at: context.date))
                        .stroke(palette.ring, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .shadow(color: palette.a, radius: lineWidth * 1.5)
                }
            }
            .frame(width: ringDiameter - lineWidth, height: ringDiameter - lineWidth)

            OrbBreathing(core: core, palette: palette, idle: phase == .idle,
                         breath: breathing ? (drifting ? .nudge : .focus) : nil)
                .frame(width: core, height: core)
        }
        .frame(width: ringDiameter, height: ringDiameter)
    }

    private func remaining(at date: Date) -> Double {
        guard phase != .idle else { return 0 }
        let total = phaseEnd.timeIntervalSince(phaseStart)
        guard total > 0 else { return 0 }
        return min(1, max(0, phaseEnd.timeIntervalSince(pausedAt ?? date) / total))
    }
}

/// How the orb breathes: how far it swells, and how long one breath takes.
struct Breath: Equatable {
    let depth: CGFloat
    let period: TimeInterval
    static let focus = Breath(depth: 0.03, period: 4.8)
    static let nudge = Breath(depth: 0.05, period: 2.4)
}

/// Shows the orb as one still image and lets Core Animation scale it. The breathing runs in the system's
/// renderer, so it costs Ribbon nothing per frame. The image is redrawn only when the size or colors change.
private struct OrbBreathing: NSViewRepresentable {
    let core: CGFloat
    let palette: Palette
    let idle: Bool
    let breath: Breath?

    final class Coordinator {
        var drawn: OrbBody?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> OrbLayerView { OrbLayerView() }

    func updateNSView(_ view: OrbLayerView, context: Context) {
        let body = OrbBody(core: core, palette: palette, idle: idle)
        if context.coordinator.drawn != body {
            context.coordinator.drawn = body
            let renderer = ImageRenderer(content: body)
            renderer.scale = view.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
            view.orb.contents = renderer.cgImage
            view.orb.contentsScale = renderer.scale
        }
        view.breathe(breath)
    }
}

/// A view holding one Core Animation layer: the orb image, scaled around its center.
final class OrbLayerView: NSView {
    let orb = CALayer()
    private var breath: Breath?

    init() {
        super.init(frame: .zero)
        layer = CALayer()
        wantsLayer = true
        orb.contentsGravity = .resizeAspect
        layer?.addSublayer(orb)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        orb.bounds = CGRect(origin: .zero, size: bounds.size)
        orb.position = CGPoint(x: bounds.midX, y: bounds.midY)
        CATransaction.commit()
    }

    func breathe(_ breath: Breath?) {
        guard breath != self.breath else { return }
        self.breath = breath
        orb.removeAnimation(forKey: "breathe")
        guard let breath else { return }
        let animation = CABasicAnimation(keyPath: "transform.scale")
        animation.fromValue = 1 - breath.depth
        animation.toValue = 1 + breath.depth
        animation.duration = breath.period / 2
        animation.autoreverses = true
        animation.repeatCount = .infinity
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        orb.add(animation, forKey: "breathe")
    }
}

/// The orb itself, still. It's only redrawn when its size or colors change.
private struct OrbBody: View, Equatable {
    let core: CGFloat
    let palette: Palette
    let idle: Bool

    var body: some View {
        ZStack {
            Circle().fill(RadialGradient(
                colors: [palette.c, palette.a, palette.b],
                center: UnitPoint(x: 0.38, y: 0.32), startRadius: 0, endRadius: core * 0.75))
            Circle()
                .fill(AngularGradient(colors: [palette.a, palette.b, palette.c, palette.a], center: .center))
                .rotationEffect(.degrees(40))
                .blur(radius: core * 0.16)
                .opacity(0.75)
            Circle()
                .fill(palette.c)
                .frame(width: core * 0.5, height: core * 0.5)
                .offset(x: -core * 0.12, y: -core * 0.1)
                .blur(radius: core * 0.14)
                .blendMode(.screen)
            Circle()
                .fill(palette.b)
                .frame(width: core * 0.45, height: core * 0.45)
                .offset(x: core * 0.16, y: core * 0.14)
                .blur(radius: core * 0.14)
                .opacity(0.7)
            Circle().fill(RadialGradient(
                colors: [.clear, .clear, .black.opacity(0.3)],
                center: .center, startRadius: 0, endRadius: core * 0.5))
            Ellipse()
                .fill(LinearGradient(colors: [.white.opacity(0.6), .white.opacity(0)], startPoint: .top, endPoint: .bottom))
                .frame(width: core * 0.55, height: core * 0.3)
                .offset(y: -core * 0.25)
        }
        .frame(width: core, height: core)
        .clipShape(Circle())
        .drawingGroup()
        .opacity(idle ? 0.8 : 1)
    }
}

struct Palette: Equatable {
    let a: Color, b: Color, c: Color, ring: Color

    static func of(_ phase: Phase, drifting: Bool, paused: Bool) -> Palette {
        if paused {
            return Palette(a: Color(hex: 0x9A93B0), b: Color(hex: 0x5D5873), c: Color(hex: 0xE2DCF0), ring: Color(hex: 0xE2DCF0))
        }
        if drifting {
            return Palette(a: Color(hex: 0xFF2D55), b: Color(hex: 0x8E2DE2), c: Color(hex: 0xFFA21F), ring: .white)
        }
        switch phase {
        case .idle: return Palette(a: Color(hex: 0x8C8CFF), b: Color(hex: 0x4E5BFF), c: Color(hex: 0xE4E6FF), ring: .white)
        case .focus: return Palette(a: Color(hex: 0xFF5A36), b: Color(hex: 0xE8235F), c: Color(hex: 0xFFC46B), ring: Color(hex: 0xFFE3C7))
        case .rest: return Palette(a: Color(hex: 0x2BD9A4), b: Color(hex: 0x2E8BFF), c: Color(hex: 0xC8FFE9), ring: Color(hex: 0xDFFFF3))
        }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

struct HoverLabel: View {
    let model: OrbModel

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(alignment: .trailing, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                Text(subtitle(at: context.date))
                    .font(.system(size: 12, weight: .medium, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.6))
                if let status = model.status {
                    Text(status)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(Color(hex: 0xFFB35C))
                        .multilineTextAlignment(.trailing)
                        .lineLimit(3)
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(Bubble(cornerRadius: 14))
        }
    }

    private var title: String {
        switch model.phase {
        case .idle: "Start a Pomodoro"
        case .focus: model.task
        case .rest: "Break time"
        }
    }

    private func subtitle(at date: Date) -> String {
        switch model.phase {
        case .idle: return "Click and tell me what you're working on"
        case .focus where model.paused: return "Paused · \(clock(model.pauseLeft(at: date))) of pause left"
        case .focus: return "\(clock(model.timeLeft(at: date))) left · \(model.profileName.isEmpty ? "click for controls" : model.profileName)"
        case .rest: return "\(clock(model.timeLeft(at: date))) · click to start the next one"
        }
    }
}

struct Toast: View {
    let text: String
    var symbol = "hand.raised.fill"

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).foregroundStyle(Color(hex: 0xFFB35C))
            Text(text).lineLimit(2)
        }
        .font(.system(size: 12.5, weight: .semibold, design: .rounded))
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Bubble(cornerRadius: 14))
    }
}

struct Caption: View {
    let text: String
    let holding: Bool

    var body: some View {
        VStack(spacing: 8) {
            Text(text)
                .font(.system(size: 24, weight: .semibold, design: .rounded))
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)
            Text(holding ? "Keep holding…" : "Get back to it and I'll shrink. Wrong call? Hold me for 2 seconds.")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.55))
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 26)
        .padding(.vertical, 18)
        .background(Bubble(cornerRadius: 22))
    }
}

struct Bubble: View {
    let cornerRadius: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color(white: 0.07).opacity(0.92))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).strokeBorder(.white.opacity(0.1)))
            .shadow(color: .black.opacity(0.35), radius: 20, y: 8)
    }
}
