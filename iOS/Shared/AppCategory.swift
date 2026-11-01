import Foundation
import FamilyControls

/// A category of your own, like the desktop's: a name, a color from the palette, how its time counts, and the apps
/// you put in it. An app you put here shows under this category on Today and This week instead of Apple's.
struct AppCategory: Codable, Identifiable, Equatable {
    var id = UUID().uuidString
    var name: String
    /// 1 to 8: one of the palette's colors.
    var slot: Int
    /// "productive", "neutral" or "distracting".
    var kind: String
    var apps = FamilyActivitySelection(includeEntireCategory: true)

    var appCount: Int { apps.applicationTokens.count + apps.categoryTokens.count + apps.webDomainTokens.count }

    static let kinds: [(String, String)] = [("productive", "Productive"), ("neutral", "Neutral"), ("distracting", "Distracting")]

    var kindLabel: String { Self.kinds.first { $0.0 == kind }?.1 ?? "Neutral" }

    /// The desktop's categories, empty, ready for apps.
    static func defaults() -> [AppCategory] {
        [
            AppCategory(name: "Code", slot: 1, kind: "productive"),
            AppCategory(name: "Design", slot: 2, kind: "productive"),
            AppCategory(name: "Writing & Planning", slot: 3, kind: "productive"),
            AppCategory(name: "Research & AI", slot: 4, kind: "productive"),
            AppCategory(name: "Social & News", slot: 5, kind: "distracting"),
            AppCategory(name: "Communication", slot: 6, kind: "neutral"),
            AppCategory(name: "Meetings", slot: 7, kind: "neutral"),
            AppCategory(name: "Entertainment", slot: 8, kind: "distracting"),
        ]
    }

    /// Your categories, read straight from the app group's folder, so the Screen Time report can read them too.
    static func saved() -> [AppCategory]? {
        guard let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.jeremiahlena.ribbon")?
                .appendingPathComponent("categories.json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode([AppCategory].self, from: data)
    }
}
