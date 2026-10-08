import Foundation

enum RuleMode: String, Codable, CaseIterable, Identifiable {
    case off, allowOnly, block
    var id: String { rawValue }

    var label: String {
        switch self {
        case .off: "No limits"
        case .allowOnly: "Only allow"
        case .block: "Block"
        }
    }
}

struct AppRef: Codable, Hashable, Identifiable {
    var bundleID: String
    var name: String
    var id: String { bundleID }
}

/// A kind of focus session: how long it runs and what you're allowed to use during it.
struct SessionProfile: Codable, Hashable, Identifiable {
    var id = UUID().uuidString
    var name: String
    var emoji: String
    var focusMinutes: Int
    var breakMinutes: Int
    var appMode: RuleMode
    var apps: [AppRef]
    var siteMode: RuleMode
    var sites: [String]
    /// Also block whatever is categorized as distracting (Social & News, Entertainment).
    var blockDistracting: Bool
    /// The orb watches your screens and nudges you when you drift.
    var watchScreen: Bool

    var rulesSummary: String {
        var parts: [String] = []
        switch appMode {
        case .allowOnly: parts.append("Only \(apps.count) app\(apps.count == 1 ? "" : "s")")
        case .block: parts.append("Blocks \(apps.count) app\(apps.count == 1 ? "" : "s")")
        case .off: break
        }
        switch siteMode {
        case .allowOnly: parts.append("only \(sites.count) site\(sites.count == 1 ? "" : "s")")
        case .block: parts.append("blocks \(sites.count) site\(sites.count == 1 ? "" : "s")")
        case .off: break
        }
        if blockDistracting && (appMode != .allowOnly || siteMode != .allowOnly) { parts.append("no distractions") }
        let text = parts.joined(separator: " · ")
        return text.isEmpty ? "No limits" : text.prefix(1).uppercased() + text.dropFirst()
    }

    @MainActor static func defaults() -> [SessionProfile] {
        func apps(_ ids: [String]) -> [AppRef] {
            ids.compactMap { id in InstalledApps.all.first { $0.bundleID == id } }
        }
        let editors = ["com.apple.dt.Xcode", "com.microsoft.VSCode", "com.todesktop.230313mzl4w4u92", "dev.zed.Zed",
                       "com.apple.Terminal", "com.googlecode.iterm2", "com.mitchellh.ghostty", "dev.warp.Warp-Stable",
                       "com.openai.codex", "com.anthropic.claudefordesktop", "com.figma.Desktop", "com.postmanlabs.mac"]
        let browsers = ["com.google.Chrome", "com.apple.Safari", "company.thebrowser.Browser", "com.brave.Browser", "com.microsoft.edgemac"]
        let writing = ["notion.id", "md.obsidian", "com.apple.iWork.Pages", "com.microsoft.Word", "com.apple.Notes"]
        return [
            SessionProfile(name: "Coding", emoji: "💻", focusMinutes: 50, breakMinutes: 10,
                           appMode: .allowOnly, apps: apps(editors + browsers),
                           siteMode: .allowOnly,
                           sites: ["localhost", "127.0.0.1", "google.com", "github.com", "stackoverflow.com",
                                   "developer.apple.com", "chatgpt.com", "claude.ai"],
                           blockDistracting: true, watchScreen: true),
            SessionProfile(name: "Deep Work", emoji: "🎯", focusMinutes: 50, breakMinutes: 10,
                           appMode: .off, apps: [], siteMode: .off, sites: [],
                           blockDistracting: true, watchScreen: true),
            SessionProfile(name: "Pomodoro", emoji: "🍅", focusMinutes: 25, breakMinutes: 5,
                           appMode: .off, apps: [], siteMode: .block, sites: ["youtube.com", "x.com", "reddit.com", "instagram.com"],
                           blockDistracting: false, watchScreen: true),
            SessionProfile(name: "Writing", emoji: "✍️", focusMinutes: 45, breakMinutes: 10,
                           appMode: .allowOnly, apps: apps(writing + browsers),
                           siteMode: .allowOnly, sites: ["docs.google.com", "notion.so", "google.com", "wikipedia.org", "claude.ai"],
                           blockDistracting: true, watchScreen: true),
        ]
    }
}

enum SiteMatch {
    /// "google.com" matches google.com and www.google.com; "*.google.com" also matches every subdomain.
    static func matches(_ host: String, _ pattern: String) -> Bool {
        let pattern = normalize(pattern)
        if pattern.hasPrefix("*.") {
            let base = String(pattern.dropFirst(2))
            return host == base || host.hasSuffix("." + base)
        }
        return host == pattern || host == "www." + pattern
    }

    /// Accepts pasted URLs: "https://www.youtube.com/watch?v=1" → "youtube.com".
    static func normalize(_ input: String) -> String {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let wildcard = text.hasPrefix("*.")
        if wildcard { text.removeFirst(2) }
        if text.contains("://"), let host = URL(string: text)?.host { text = host }
        text = String(text.split(separator: "/").first ?? "")
        text = String(text.split(separator: ":").first ?? "")
        if text.hasPrefix("www.") { text.removeFirst(4) }
        return wildcard ? "*." + text : text
    }
}
