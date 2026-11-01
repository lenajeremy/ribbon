import SwiftUI

/// The orb's colors, from the desktop: ember while focusing, sea green on a break, lavender while paused,
/// a calm blue when nothing's running.
struct OrbPalette: Equatable {
    let a: Color, b: Color, c: Color

    static let focus = OrbPalette(a: Color(hex: 0xFF5A36), b: Color(hex: 0xE8235F), c: Color(hex: 0xFFC46B))
    static let rest = OrbPalette(a: Color(hex: 0x2BD9A4), b: Color(hex: 0x2E8BFF), c: Color(hex: 0xC8FFE9))
    static let paused = OrbPalette(a: Color(hex: 0x9A93B0), b: Color(hex: 0x5D5873), c: Color(hex: 0xE2DCF0))
    static let idle = OrbPalette(a: Color(hex: 0x8C8CFF), b: Color(hex: 0x4E5BFF), c: Color(hex: 0xE4E6FF))

    static func of(phase: String, paused: Bool) -> OrbPalette {
        if paused { return .paused }
        switch phase {
        case "focus": return .focus
        case "rest": return .rest
        default: return .idle
        }
    }
}

/// The orb itself: a glowing sphere, lit from the top left.
struct OrbSphere: View {
    var palette: OrbPalette = .focus
    var size: CGFloat
    var glow = true

    var body: some View {
        Circle()
            .fill(RadialGradient(colors: [palette.c, palette.a, palette.b],
                                 center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: size * 0.7))
            .overlay(Circle().fill(RadialGradient(colors: [.white.opacity(0.55), .clear],
                                                  center: UnitPoint(x: 0.32, y: 0.26), startRadius: 0, endRadius: size * 0.28)))
            .frame(width: size, height: size)
            .shadow(color: glow ? palette.a.opacity(0.55) : .clear, radius: size * 0.35)
    }
}

/// The orb, small, marking the present moment on a ribbon, as on the desktop.
struct NowOrb: View {
    var size: CGFloat = 13

    var body: some View {
        OrbSphere(palette: .focus, size: size, glow: true)
            .overlay(Circle().strokeBorder(.white.opacity(0.85), lineWidth: 1.5))
            .accessibilityLabel("Now")
    }
}

/// The big orb on the session screen: the sphere breathing slowly inside a ring that empties as the time runs down.
struct SessionOrb: View {
    let palette: OrbPalette
    /// How much of the part is left, 0 to 1.
    let remaining: Double
    var size: CGFloat = 210
    var breathing = true
    @State private var inhale = false

    var body: some View {
        let line = max(3, size * 0.022)
        ZStack {
            Circle().fill(palette.a.opacity(0.18)).frame(width: size * 0.9, height: size * 0.9).blur(radius: size * 0.16)
            Circle().stroke(Theme.track, lineWidth: line)
            Circle()
                .trim(from: 0, to: remaining)
                .stroke(palette.a, style: StrokeStyle(lineWidth: line, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 1), value: remaining)
            OrbSphere(palette: palette, size: size * 0.62)
                .scaleEffect(inhale ? 1.035 : 1)
        }
        .frame(width: size, height: size)
        .onAppear {
            guard breathing else { return }
            withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) { inhale = true }
        }
        .accessibilityHidden(true)
    }
}
