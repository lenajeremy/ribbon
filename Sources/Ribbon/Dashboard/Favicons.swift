import AppKit
import Observation

/// Website logos, fetched from each site itself (its <link rel="icon"> or /favicon.ico) and cached on disk.
@Observable @MainActor final class Favicons {
    static let shared = Favicons()

    private(set) var images: [String: NSImage] = [:]
    @ObservationIgnored private var requested: Set<String> = []
    @ObservationIgnored private let folder = Store.folder.appendingPathComponent("Favicons", isDirectory: true)

    func image(for domain: String) -> NSImage? {
        if let image = images[domain] { return image }
        load(domain)
        return nil
    }

    private func load(_ domain: String) {
        guard !requested.contains(domain), Self.fetchable(domain) else { return }
        requested.insert(domain)
        let file = folder.appendingPathComponent(domain + ".icon")
        if let attributes = try? FileManager.default.attributesOfItem(atPath: file.path) {
            if let data = try? Data(contentsOf: file), !data.isEmpty, let image = NSImage(data: data) {
                images[domain] = image
                return
            }
            // An empty file means the site had no icon; look again after a week.
            if let date = attributes[.modificationDate] as? Date, Date().timeIntervalSince(date) < 7 * 86400 { return }
        }
        Task {
            let data = await Self.fetch(domain)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try? (data ?? Data()).write(to: file)
            if let data, let image = NSImage(data: data) { images[domain] = image }
        }
    }

    nonisolated static func fetchable(_ domain: String) -> Bool {
        domain.contains(".") && !domain.allSatisfy { $0.isNumber || $0 == "." }
    }

    nonisolated private static func fetch(_ domain: String) async -> Data? {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 8
        config.httpAdditionalHeaders = ["User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"]
        let session = URLSession(configuration: config)
        let home = URL(string: "https://\(domain)/")!
        var candidates: [URL] = []
        if let (html, response) = try? await session.data(from: home) {
            let page = String(decoding: html.prefix(400_000), as: UTF8.self)
            candidates += iconLinks(in: page, base: response.url ?? home)
        }
        candidates += [URL(string: "https://\(domain)/apple-touch-icon.png")!, URL(string: "https://\(domain)/favicon.ico")!]
        for url in candidates {
            guard let (data, response) = try? await session.data(from: url),
                  (response as? HTTPURLResponse)?.statusCode == 200, data.count > 64, NSImage(data: data) != nil else { continue }
            return data
        }
        return nil
    }

    /// The page's icon links, biggest first (apple-touch-icons are usually 180 px).
    nonisolated static func iconLinks(in html: String, base: URL) -> [URL] {
        guard let tags = try? NSRegularExpression(pattern: "<link\\b[^>]*>", options: .caseInsensitive) else { return [] }
        var found: [(url: URL, size: Int)] = []
        for match in tags.matches(in: html, range: NSRange(html.startIndex..., in: html)) {
            guard let range = Range(match.range, in: html) else { continue }
            let tag = String(html[range])
            guard let rel = attribute("rel", in: tag)?.lowercased(), rel.contains("icon"), !rel.contains("mask"),
                  let href = attribute("href", in: tag), let url = URL(string: href, relativeTo: base)?.absoluteURL else { continue }
            var size = attribute("sizes", in: tag).flatMap { Int($0.lowercased().split(separator: "x").first ?? "") } ?? 32
            if rel.contains("apple-touch-icon") { size = max(size, 180) }
            if href.lowercased().contains(".svg") { size = 1 }  // last resort; not every SVG draws
            found.append((url, size))
        }
        return found.sorted { $0.size > $1.size }.map(\.url)
    }

    nonisolated private static func attribute(_ name: String, in tag: String) -> String? {
        let pattern = "\\b\(name)\\s*=\\s*(?:\"([^\"]*)\"|'([^']*)'|([^\\s>]+))"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: tag, range: NSRange(tag.startIndex..., in: tag)) else { return nil }
        for group in 1...3 {
            if let range = Range(match.range(at: group), in: tag) { return String(tag[range]) }
        }
        return nil
    }
}
