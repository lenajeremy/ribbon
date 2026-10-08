import Foundation

/// Categories for apps and sites everyone has, so the AI only has to look at the long tail.
enum BuiltinRules {
    static func app(_ bundle: String) -> String? {
        if let category = apps[bundle] { return category }
        if bundle.hasPrefix("com.jetbrains.") { return "code" }
        if bundle.hasPrefix("com.adobe.") { return "design" }
        return nil
    }

    /// Looks up the host and then each parent domain ("mail.google.com", then "google.com").
    static func site(_ host: String) -> String? {
        for domain in Domains.suffixes(host) { if let category = sites[domain] { return category } }
        return nil
    }

    /// Sites where the page decides the category: a SwiftUI tutorial on YouTube isn't a cat video.
    static func judgedPerPage(_ host: String) -> Bool {
        Domains.suffixes(host).contains { perPage.contains($0) }
    }

    static let perPage: Set<String> = ["youtube.com", "youtu.be", "medium.com", "substack.com"]

    private static let apps: [String: String] = [
        // Code
        "com.apple.dt.Xcode": "code", "com.microsoft.VSCode": "code", "com.microsoft.VSCodeInsiders": "code",
        "com.todesktop.230313mzl4w4u92": "code", "dev.zed.Zed": "code", "com.sublimetext.4": "code",
        "com.apple.Terminal": "code", "com.googlecode.iterm2": "code", "com.mitchellh.ghostty": "code",
        "dev.warp.Warp-Stable": "code", "net.kovidgoyal.kitty": "code", "io.alacritty": "code",
        "com.github.GitHubClient": "code", "com.postmanlabs.mac": "code", "com.docker.docker": "code",
        "com.apple.dt.Instruments": "code", "com.openai.codex": "code", "com.tinyapp.TablePlus": "code",
        // Design
        "com.figma.Desktop": "design", "com.bohemiancoding.sketch3": "design", "com.pixelmatorteam.pixelmator.x": "design",
        "com.seriflabs.affinitydesigner2": "design", "com.framer.electron": "design",
        // Writing & planning
        "com.apple.iWork.Pages": "writing", "com.apple.iWork.Numbers": "writing", "com.apple.iWork.Keynote": "writing",
        "com.microsoft.Word": "writing", "com.microsoft.Excel": "writing", "com.microsoft.Powerpoint": "writing",
        "notion.id": "writing", "md.obsidian": "writing", "com.apple.Notes": "writing", "com.linear": "writing",
        "com.culturedcode.ThingsMac": "writing", "com.apple.reminders": "writing", "com.apple.iCal": "writing",
        "com.lukilabs.lukiapp": "writing", "net.shinyfrog.bear": "writing", "com.ulyssesapp.mac": "writing",
        "com.jeremiahlena.focusorb": "writing",
        // Research & AI
        "com.openai.chat": "learning", "com.anthropic.claudefordesktop": "learning", "ai.perplexity.mac": "learning",
        "com.apple.iBooksX": "learning", "com.apple.Dictionary": "learning", "net.readdle.PDFExpert-Mac": "learning",
        // Communication
        "com.tinyspeck.slackmacgap": "communication", "com.apple.mail": "communication", "com.microsoft.Outlook": "communication",
        "com.apple.MobileSMS": "communication", "net.whatsapp.WhatsApp": "communication", "ru.keepcoder.Telegram": "communication",
        "com.hnc.Discord": "communication", "com.readdle.SparkDesktop": "communication", "com.superhuman.electron": "communication",
        "com.facebook.archon": "communication",
        // Meetings
        "us.zoom.xos": "meetings", "com.microsoft.teams2": "meetings", "com.microsoft.teams": "meetings",
        "com.apple.FaceTime": "meetings", "com.cisco.webexmeetingsapp": "meetings",
        // Entertainment
        "com.spotify.client": "entertainment", "com.apple.Music": "entertainment", "com.apple.TV": "entertainment",
        "com.apple.podcasts": "entertainment", "com.valvesoftware.steam": "entertainment", "tv.twitch.studio": "entertainment",
        "com.colliderli.iina": "entertainment", "org.videolan.vlc": "entertainment", "com.apple.QuickTimePlayerX": "entertainment",
        // Other
        "com.apple.finder": "other", "com.apple.systempreferences": "other", "com.apple.ActivityMonitor": "other",
        "com.1password.1password": "other", "com.apple.AppStore": "other", "com.apple.calculator": "other",
        "com.apple.Preview": "other", "com.apple.Photos": "other",
    ]

    private static let sites: [String: String] = [
        // Code
        "github.com": "code", "gitlab.com": "code", "bitbucket.org": "code", "stackoverflow.com": "code",
        "localhost": "code", "127.0.0.1": "code", "developer.apple.com": "code", "developer.mozilla.org": "code",
        "vercel.com": "code", "netlify.com": "code", "npmjs.com": "code", "railway.com": "code", "railway.app": "code",
        "supabase.com": "code", "console.aws.amazon.com": "code", "cloud.google.com": "code", "platform.openai.com": "code",
        "console.anthropic.com": "code", "codesandbox.io": "code", "replit.com": "code", "leetcode.com": "code",
        "swift.org": "code", "pypi.org": "code", "docs.python.org": "code", "huggingface.co": "code",
        // Design
        "figma.com": "design", "dribbble.com": "design", "behance.net": "design", "mobbin.com": "design",
        "canva.com": "design", "framer.com": "design", "coolors.co": "design",
        // Writing & planning
        "docs.google.com": "writing", "sheets.google.com": "writing", "slides.google.com": "writing",
        "drive.google.com": "writing", "calendar.google.com": "writing", "notion.so": "writing", "notion.site": "writing",
        "linear.app": "writing", "atlassian.net": "writing", "trello.com": "writing", "asana.com": "writing",
        "coda.io": "writing", "overleaf.com": "writing", "airtable.com": "writing", "office.com": "writing",
        // Research & AI
        "google.com": "learning", "bing.com": "learning", "duckduckgo.com": "learning", "chatgpt.com": "learning",
        "chat.openai.com": "learning", "claude.ai": "learning", "gemini.google.com": "learning", "perplexity.ai": "learning",
        "wikipedia.org": "learning", "arxiv.org": "learning", "scholar.google.com": "learning", "coursera.org": "learning",
        "udemy.com": "learning", "khanacademy.org": "learning", "developers.google.com": "code",
        // Communication
        "mail.google.com": "communication", "outlook.live.com": "communication", "outlook.office.com": "communication",
        "slack.com": "communication", "web.whatsapp.com": "communication", "discord.com": "communication",
        "messenger.com": "communication", "web.telegram.org": "communication",
        // Meetings
        "meet.google.com": "meetings", "zoom.us": "meetings", "teams.microsoft.com": "meetings", "teams.live.com": "meetings",
        "whereby.com": "meetings",
        // Social & news
        "x.com": "social", "twitter.com": "social", "facebook.com": "social", "instagram.com": "social",
        "linkedin.com": "social", "reddit.com": "social", "tiktok.com": "social", "threads.net": "social",
        "bsky.app": "social", "news.ycombinator.com": "social", "producthunt.com": "social", "cnn.com": "social",
        "nytimes.com": "social", "bbc.com": "social", "bbc.co.uk": "social", "theverge.com": "social",
        "techcrunch.com": "social", "foxnews.com": "social", "washingtonpost.com": "social", "pinterest.com": "social",
        // Entertainment & shopping (YouTube starts here; each video gets judged on its own)
        "youtube.com": "entertainment", "youtu.be": "entertainment", "netflix.com": "entertainment",
        "twitch.tv": "entertainment", "hulu.com": "entertainment", "disneyplus.com": "entertainment",
        "primevideo.com": "entertainment", "max.com": "entertainment", "open.spotify.com": "entertainment",
        "music.apple.com": "entertainment", "amazon.com": "entertainment", "ebay.com": "entertainment",
        "etsy.com": "entertainment", "store.steampowered.com": "entertainment", "9gag.com": "entertainment",
    ]
}

enum Domains {
    /// "https://www.youtube.com/watch?v=1" → "youtube.com"
    static func host(of url: String) -> String {
        guard let host = URL(string: url)?.host?.lowercased() else { return "" }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    /// "a.b.example.com" → ["a.b.example.com", "b.example.com", "example.com"]
    static func suffixes(_ host: String) -> [String] {
        let parts = host.split(separator: ".")
        guard parts.count > 2 else { return [host] }
        return (0...(parts.count - 2)).map { parts[$0...].joined(separator: ".") }
    }
}
