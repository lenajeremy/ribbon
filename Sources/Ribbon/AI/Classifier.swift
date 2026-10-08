import Foundation

/// Decides which category an app or website belongs to.
/// Order: your own choices, then the built-in list, then the AI's earlier answers, then the AI (Decisions API).
@MainActor final class Classifier {
    struct Label {
        let category: String
        let source: String
    }

    private let store: Store
    private let openai: OpenAI
    private let aiEnabled: Bool
    private(set) var labels: [String: Label] = [:]
    private var pending: Set<String> = []
    private var queue: [(key: String, description: String)] = []
    private var inFlight = 0
    /// A key was categorized (by the AI or by you).
    var onLabel: ((String, String) -> Void)?

    init(store: Store, openai: OpenAI, aiEnabled: Bool) {
        self.store = store
        self.openai = openai
        self.aiEnabled = aiEnabled
        for (key, value) in store.labels() { labels[key] = Label(category: value.category, source: value.source) }
    }

    func category(for o: FrontActivity) -> (key: String, category: String) {
        let appKey = "app:" + o.bundleID
        if BrowserBridge.isBrowser(o.bundleID) {
            if !o.domain.isEmpty {
                let suffixes = Domains.suffixes(o.domain)
                if let mine = suffixes.lazy.compactMap({ self.labels["site:" + $0] }).first(where: { $0.source == "user" }) {
                    return ("site:" + o.domain, mine.category)
                }
                if BuiltinRules.judgedPerPage(o.domain) && !o.title.isEmpty {
                    let key = "page:\(o.domain)|\(Self.trim(o.title))"
                    if let label = labels[key] { return (key, label.category) }
                    request(key, o)
                    return (key, BuiltinRules.site(o.domain) ?? "other")
                }
                let key = "site:" + o.domain
                if let mine = suffixes.lazy.compactMap({ self.labels["site:" + $0] }).first(where: { Categories.isCustom($0.category) }) {
                    return (key, mine.category)
                }
                if let builtin = BuiltinRules.site(o.domain) { return (key, builtin) }
                if let label = suffixes.lazy.compactMap({ self.labels["site:" + $0] }).first { return (key, label.category) }
                request(key, o)
                return (key, "other")
            }
            // No URL (Firefox, or no permission yet): judge the page by its title.
            guard !o.title.isEmpty else { return (appKey, "other") }
            let key = "page:\(o.bundleID)|\(Self.trim(o.title))"
            if let label = labels[key] { return (key, label.category) }
            request(key, o)
            return (key, "other")
        }
        if let label = labels[appKey], label.source == "user" || Categories.isCustom(label.category) { return (appKey, label.category) }
        if let builtin = BuiltinRules.app(o.bundleID) { return (appKey, builtin) }
        if let label = labels[appKey] { return (appKey, label.category) }
        request(appKey, o)
        return (appKey, "other")
    }

    /// Where a key's category came from, for the Categories screen.
    func source(for item: KnownItem) -> String {
        if let label = labels[item.key] { return label.source == "user" ? "You" : "AI" }
        if item.domain.isEmpty ? BuiltinRules.app(item.bundle) != nil : BuiltinRules.site(item.domain) != nil { return "Built-in" }
        return "AI"
    }

    /// A category was deleted: drop the labels that pointed at it so those apps and sites get sorted again.
    func forget(_ categoryID: String) {
        for (key, label) in labels where label.category == categoryID {
            labels[key] = nil
            pending.remove(key)
        }
    }

    /// You recategorized something: remember it, and rewrite history to match.
    func setUserLabel(key: String, category: String) {
        labels[key] = Label(category: category, source: "user")
        store.saveLabel(key: key, category: category, source: "user")
        if key.hasPrefix("site:") { store.setCategory(category, forDomain: String(key.dropFirst(5))) }
        else if key.hasPrefix("app:") { store.setCategory(category, forBundle: String(key.dropFirst(4))) }
        else { store.setCategory(category, forKey: key) }
        onLabel?(key, category)
    }

    /// For each recent app and site you haven't sorted yourself, asks the AI which category fits best,
    /// out of all of them, and moves it only if the new category wins. Returns how many moved.
    func resort(_ items: [KnownItem], into category: Category) async -> Int {
        guard aiEnabled else { return 0 }
        let candidates = items.filter { labels[$0.key]?.source != "user" && $0.category != category.id }
        var moved = 0
        for start in stride(from: 0, to: candidates.count, by: 4) {
            let batch = candidates[start..<min(start + 4, candidates.count)]
            await withTaskGroup(of: (KnownItem, String?).self) { group in
                for item in batch {
                    group.addTask { (item, await self.bestCategory(app: item.app, domain: item.domain, title: "")) }
                }
                for await (item, pick) in group where pick == category.id {
                    labels[item.key] = Label(category: category.id, source: "ai")
                    store.saveLabel(key: item.key, category: category.id, source: "ai")
                    store.setCategory(category.id, forKey: item.key, from: item.category)
                    moved += 1
                    logLine("AI moved \(item.label) into \(category.name)")
                }
            }
        }
        return moved
    }

    /// One-time repair: an earlier version asked "does this belong?" app by app, which said yes to far too much.
    /// Every AI pick for one of your categories gets re-asked comparatively, and history is recomputed to match.
    func repairCustomLabels() async {
        let flag = "repairedCustomLabels1"
        guard aiEnabled, !UserDefaults.standard.bool(forKey: flag), !Categories.custom.isEmpty else { return }
        for (key, label) in labels where label.source == "ai" && Categories.isCustom(label.category) {
            let sample = store.keys(inCategory: label.category).first { $0.key == key }
            let isSite = key.hasPrefix("site:")
            let domain = isSite ? String(key.dropFirst(5)) : (sample?.domain ?? "")
            let bundle = isSite ? (sample?.bundle ?? "") : String(key.dropFirst(4))
            let app = sample?.app ?? InstalledApps.all.first { $0.bundleID == bundle }?.name ?? bundle
            let pick = await bestCategory(app: app, domain: domain, title: sample?.title ?? "")
            guard pick != label.category else { continue }
            labels[key] = nil
            store.deleteLabel(key: key)
            let builtin = isSite ? BuiltinRules.site(domain) : BuiltinRules.app(bundle)
            if builtin == nil, let pick {
                labels[key] = Label(category: pick, source: "ai")
                store.saveLabel(key: key, category: pick, source: "ai")
            }
            logLine("Repaired \(key): \(Categories.by(label.category).name) → \(Categories.by(builtin ?? pick ?? "other").name)")
        }
        // Recompute every row still counted in one of your categories from the corrected labels.
        for category in Categories.custom {
            for row in store.keys(inCategory: category.id) {
                let activity = FrontActivity(bundleID: row.bundle, app: row.app, title: row.title, url: "", domain: row.domain)
                let resolved = self.category(for: activity).category
                if resolved != category.id { store.setCategory(resolved, forKey: row.key, from: category.id) }
            }
        }
        UserDefaults.standard.set(true, forKey: flag)
        onLabel?("", "")
    }

    /// The single best category for an app or site, if the AI is reasonably sure.
    private func bestCategory(app: String, domain: String, title: String) async -> String? {
        var description = "App: \(app)"
        if !domain.isEmpty { description += "\nWebsite: \(domain)" }
        if !title.isEmpty { description += "\nPage or window title: \(Self.trim(title))" }
        let pick = try? await openai.choose(
            input: description,
            instructions: "Which category best describes what a person is doing here? Judge by the app, the website and the page or window title.",
            choices: Self.choices)
        guard let pick, pick.confidence >= 0.5 else { return nil }
        return pick.value
    }

    private static var choices: [(value: String, description: String)] {
        Categories.all.map { ($0.id, "\($0.name): \($0.hint.isEmpty ? $0.name : $0.hint)") }
    }

    private func request(_ key: String, _ o: FrontActivity) {
        guard aiEnabled, !pending.contains(key) else { return }
        pending.insert(key)
        var description = "App: \(o.app)"
        if !o.domain.isEmpty { description += "\nWebsite: \(o.domain)" }
        if !o.title.isEmpty { description += "\nPage or window title: \(Self.trim(o.title))" }
        queue.append((key, description))
        drain()
    }

    private func drain() {
        while inFlight < 3, !queue.isEmpty {
            let job = queue.removeFirst()
            inFlight += 1
            Task {
                defer { inFlight -= 1; drain() }
                do {
                    let pick = try await openai.choose(
                        input: job.description,
                        instructions: "Which category best describes what a person is doing here? Judge by the app, the website and the page or window title.",
                        choices: Self.choices)
                    guard labels[job.key]?.source != "user" else { return }
                    labels[job.key] = Label(category: pick.value, source: "ai")
                    store.saveLabel(key: job.key, category: pick.value, source: "ai")
                    store.setCategory(pick.value, forKey: job.key)
                    onLabel?(job.key, pick.value)
                    logLine("AI sorted \(job.key.prefix(70)) → \(Categories.by(pick.value).name)")
                } catch {
                    pending.remove(job.key)  // try again next time it shows up
                    logLine("Couldn't categorize \(job.key.prefix(60)): \(error.localizedDescription)")
                }
            }
        }
    }

    private static func trim(_ title: String) -> String {
        String(title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120))
    }
}
