import FamilyControls
import SwiftUI

/// "‹ Today ›", and a way back to today from other days.
struct DayStepper: View {
    let title: String
    let isCurrent: Bool
    let back: () -> Void
    let forward: () -> Void
    let reset: () -> Void

    var body: some View {
        HStack(spacing: 2) {
            Button(action: back) { Image(systemName: "chevron.left").frame(width: 32, height: 32).contentShape(Rectangle()) }
                .accessibilityLabel("Earlier")
            Text(title).font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.muted)
            Button(action: forward) { Image(systemName: "chevron.right").frame(width: 32, height: 32).contentShape(Rectangle()) }
                .disabled(isCurrent).opacity(isCurrent ? 0.3 : 1)
                .accessibilityLabel("Later")
            if !isCurrent {
                Button("Back to today", action: reset).buttonStyle(PillButtonStyle()).padding(.leading, 6)
            }
        }
        .buttonStyle(.plain)
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(Theme.muted)
        .padding(.leading, -9)
    }
}

/// A round floating button, like the ones at the top of ChatGPT's pages.
struct RoundButton: View {
    let symbol: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 16, weight: .regular))
                .foregroundStyle(Theme.ink)
                .frame(width: 42, height: 42)
                .background(Theme.composer, in: Circle())
                .overlay(Circle().strokeBorder(Theme.composerBorder))
                .shadow(color: Theme.composerShadow, radius: 10, y: 3)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

struct SettingsButton: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        RoundButton(symbol: "gearshape", label: "Settings") { model.showSettings = true }
    }
}

/// The session running now, small, at the top of a page: what it is, the time left and how much is done.
/// Tap it for the session screen.
struct SessionStrip: View {
    let session: ActiveSession
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let now = context.date
                let total = max(1, session.phaseEnd.timeIntervalSince(session.phaseStart))
                let left = session.timeLeft(at: now)
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        OrbSphere(palette: palette, size: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(session.profile.emoji) \(session.profile.name) · \(session.status)")
                                .font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.muted).lineLimit(1)
                            Text(session.task).font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.ink).lineLimit(1)
                        }
                        Spacer(minLength: 8)
                        Text(clock(left)).font(.system(size: 22, weight: .semibold)).monospacedDigit().foregroundStyle(Theme.ink)
                    }
                    ProgressBar(value: 1 - left / total, tint: session.phase == .rest ? Theme.series(3) : Theme.productive)
                }
                .padding(16)
                .background(Theme.subtle, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.hairline))
                .contentShape(RoundedRectangle(cornerRadius: 16))
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens the session")
    }

    private var palette: OrbPalette {
        session.paused ? .paused : session.phase == .rest ? .rest : .focus
    }
}

struct ProgressBar: View {
    let value: Double
    var tint: Color = Theme.productive
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.track)
                Capsule().fill(tint).frame(width: max(height, geo.size.width * min(1, max(0, value))))
            }
        }
        .frame(height: height)
    }
}

/// Ribbon can't show your day or block anything until iOS allows it.
struct PermissionCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "hourglass").font(.system(size: 15)).padding(.top, 2)
                Text("Allow Screen Time access to see your day here and to block apps and websites during focus sessions.")
                    .font(Typeface.row).fixedSize(horizontal: false, vertical: true)
            }
            Button("Allow") { Task { await model.requestScreenTime() } }.buttonStyle(PillButtonStyle(primary: true))
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.bubble, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// The emoji in its gray tile, as in the desktop's session lists.
struct EmojiTile: View {
    let emoji: String
    var size: CGFloat = 44

    var body: some View {
        Text(emoji).font(.system(size: size * 0.48))
            .frame(width: size, height: size)
            .background(Theme.bubble, in: RoundedRectangle(cornerRadius: size * 0.25, style: .continuous))
    }
}

extension SessionReview {
    /// Blue from 80, amber from 50, red below: the same scale as productive to distracting.
    static func color(_ score: Int) -> Color {
        score >= 80 ? Theme.productive : score >= 50 ? Theme.series(4) : Theme.distracting
    }
}

/// What was picked in Apple's app picker: whole categories as rows with their names, apps as a grid of their icons,
/// each with a ✕ to take it out, then a button to change the choice and how many there are.
/// (Apple's labels only show names reliably at full width, so apps go by their icons.)
struct PickedApps: View {
    @Binding var selection: FamilyActivitySelection
    let change: () -> Void

    private var count: Int { selection.applicationTokens.count + selection.categoryTokens.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(selection.categoryTokens), id: \.self) { token in
                HStack(spacing: 10) {
                    Label(token).font(.system(size: 15)).frame(maxWidth: .infinity, alignment: .leading)
                    RemoveButton { selection.categoryTokens.remove(token) }
                }
                .padding(.leading, 12).padding(.trailing, 6)
                .frame(height: 46)
                .background(Theme.bubble, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            if !selection.applicationTokens.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 46, maximum: 56), spacing: 10)], alignment: .leading, spacing: 12) {
                    ForEach(Array(selection.applicationTokens), id: \.self) { token in
                        Label(token).labelStyle(.iconOnly)
                            .scaleEffect(42 / 28)
                            .frame(width: 42, height: 42)
                            .overlay(alignment: .topTrailing) {
                                RemoveButton(small: true) { selection.applicationTokens.remove(token) }
                                    .offset(x: 8, y: -8)
                            }
                            .padding(.top, 6)
                    }
                }
            }
            HStack(spacing: 12) {
                Button(action: change) { Label(count == 0 ? "Choose apps" : "Change", systemImage: count == 0 ? "plus" : "square.grid.2x2") }
                    .buttonStyle(PillButtonStyle())
                if count > 0 {
                    Text("\(count) chosen").font(Typeface.caption).foregroundStyle(Theme.muted)
                }
            }
        }
    }
}

/// A small round ✕ for taking something out of a list.
struct RemoveButton: View {
    var small = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark").font(.system(size: small ? 8 : 10, weight: .bold))
                .foregroundStyle(small ? Theme.page : Theme.muted)
                .frame(width: small ? 20 : 30, height: small ? 20 : 30)
                .background(small ? Theme.ink : Color.clear, in: Circle())
                .overlay(Circle().strokeBorder(small ? Theme.page : .clear, lineWidth: 2))
                .contentShape(Circle().inset(by: small ? -6 : 0))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Remove")
    }
}
