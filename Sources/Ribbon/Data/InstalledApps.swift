import AppKit

/// The apps on this Mac, for choosing which ones a session allows or blocks.
@MainActor enum InstalledApps {
    private(set) static var all: [AppRef] = scan()
    private static var icons: [String: NSImage] = [:]

    static func refresh() { all = scan() }

    static func named(_ name: String) -> AppRef? {
        let wanted = name.lowercased()
        return all.first { $0.name.lowercased() == wanted } ?? all.first { $0.name.lowercased().contains(wanted) }
    }

    static func icon(for bundleID: String) -> NSImage {
        if let icon = icons[bundleID] { return icon }
        let icon = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID).map {
            NSWorkspace.shared.icon(forFile: $0.path)
        } ?? NSImage(systemSymbolName: "app.dashed", accessibilityDescription: nil)!
        icons[bundleID] = icon
        return icon
    }

    private static func scan() -> [AppRef] {
        let fm = FileManager.default
        let roots = ["/Applications", "/Applications/Utilities", "/System/Applications", "/System/Applications/Utilities",
                     fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications").path]
        var seen = Set<String>()
        var apps: [AppRef] = []
        for root in roots {
            for name in (try? fm.contentsOfDirectory(atPath: root)) ?? [] where name.hasSuffix(".app") {
                guard let bundle = Bundle(path: "\(root)/\(name)"), let id = bundle.bundleIdentifier, seen.insert(id).inserted else { continue }
                let display = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                    ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
                    ?? String(name.dropLast(4))
                apps.append(AppRef(bundleID: id, name: display))
            }
        }
        return apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
