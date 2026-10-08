import SwiftUI

enum Productivity: String, CaseIterable, Codable {
    case productive, neutral, distracting

    var label: String {
        switch self {
        case .productive: "Productive"
        case .neutral: "Neutral"
        case .distracting: "Distracting"
        }
    }

    /// How much an hour of this counts toward the Productivity score.
    var weight: Double {
        switch self {
        case .productive: 1
        case .neutral: 0.5
        case .distracting: 0
        }
    }

    var color: Color {
        switch self {
        case .productive: Theme.productive
        case .neutral: Theme.neutral
        case .distracting: Theme.distracting
        }
    }
}

/// A category. The eight built-ins each own one color of the validated palette (plus gray for Other);
/// ones you add reuse a palette color rather than inventing a new one nobody could tell apart.
struct Category: Identifiable, Hashable, Codable {
    var id: String
    var name: String
    var symbol: String
    var slot: Int?
    var kind: Productivity
    var focus: Bool
    /// What belongs here, for the AI that sorts new apps and sites.
    var hint: String
    var isCustom = false

    var color: Color { Theme.series(slot) }
}

enum Categories {
    /// Categories you added, loaded from the database at launch.
    nonisolated(unsafe) static var custom: [Category] = []

    /// Built-ins, then yours, with Other last.
    static var all: [Category] { Array(builtIn.dropLast()) + custom + [builtIn.last!] }

    static let builtIn: [Category] = [
        Category(id: "code", name: "Code", symbol: "chevron.left.forwardslash.chevron.right", slot: 1, kind: .productive, focus: true,
                 hint: "programming: code editors, IDEs, terminals, GitHub, developer docs, Stack Overflow, localhost, cloud consoles"),
        Category(id: "design", name: "Design", symbol: "paintpalette", slot: 2, kind: .productive, focus: true,
                 hint: "design tools and design inspiration: Figma, Sketch, Photoshop, Canva, Dribbble, Mobbin"),
        Category(id: "writing", name: "Writing & Planning", symbol: "doc.text", slot: 3, kind: .productive, focus: true,
                 hint: "writing, documents, spreadsheets, slides, notes, task and project planning: Google Docs, Notion, Linear, Jira"),
        Category(id: "learning", name: "Research & AI", symbol: "sparkle.magnifyingglass", slot: 4, kind: .productive, focus: true,
                 hint: "research and learning: search engines, articles, tutorials, courses, papers, Wikipedia, AI assistants like ChatGPT and Claude"),
        Category(id: "social", name: "Social & News", symbol: "person.2", slot: 5, kind: .distracting, focus: false,
                 hint: "social media feeds and news: X, Instagram, Facebook, Reddit, LinkedIn feed, TikTok, Hacker News, news sites"),
        Category(id: "communication", name: "Communication", symbol: "bubble.left.and.bubble.right", slot: 6, kind: .neutral, focus: false,
                 hint: "messages and email: Slack, Mail, Gmail, Messages, WhatsApp, Discord, Telegram"),
        Category(id: "meetings", name: "Meetings", symbol: "video", slot: 7, kind: .neutral, focus: false,
                 hint: "video calls and meetings: Zoom, Google Meet, Teams, FaceTime"),
        Category(id: "entertainment", name: "Entertainment", symbol: "play.rectangle", slot: 8, kind: .distracting, focus: false,
                 hint: "entertainment and shopping: YouTube videos for fun, Netflix, Twitch, games, music browsing, online shopping"),
        Category(id: "other", name: "Other", symbol: "square.grid.2x2", slot: nil, kind: .neutral, focus: false,
                 hint: "anything else: system utilities, Finder, settings, banking, travel, personal admin"),
    ]

    static func by(_ id: String) -> Category { all.first { $0.id == id } ?? builtIn.last! }

    static func isCustom(_ id: String) -> Bool { custom.contains { $0.id == id } }

    /// Symbols to pick from when you make a category.
    static let symbols = [
        "graduationcap", "book", "briefcase", "brain.head.profile", "chart.bar", "dollarsign.circle", "hammer",
        "wrench.and.screwdriver", "terminal", "function", "paintbrush", "camera", "music.note", "gamecontroller",
        "cart", "heart", "dumbbell", "leaf", "house", "airplane", "person.2", "newspaper", "globe", "star",
    ]
}

/// The user's adjustments to which categories count as productive and as focus time.
struct CategoryRules: Equatable {
    var kinds: [String: Productivity] = [:]
    var focus: [String: Bool] = [:]

    func kind(_ id: String) -> Productivity { kinds[id] ?? Categories.by(id).kind }
    func isFocus(_ id: String) -> Bool { focus[id] ?? Categories.by(id).focus }
}
