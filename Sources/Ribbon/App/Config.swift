import Foundation

/// Settings, read from the process environment, then a `.env` file (when building from source), then Settings › AI.
struct Config {
    let apiKey: String
    /// Set FOCUS_MINUTES / BREAK_MINUTES to override every session type (handy for testing).
    let focusOverride: TimeInterval?
    let breakOverride: TimeInterval?
    let checkSeconds: TimeInterval
    let driftSeconds: TimeInterval
    let pauseSeconds: TimeInterval
    let voice: String

    static func load() -> Config {
        var env = ProcessInfo.processInfo.environment
        if let url = findDotEnv() {
            for (key, value) in parseDotEnv(url) where env[key] == nil { env[key] = value }
        }
        func optional(_ key: String) -> Double? { env[key].flatMap { Double($0.trimmingCharacters(in: .whitespaces)) } }
        func number(_ key: String, _ fallback: Double) -> Double { optional(key) ?? fallback }
        return Config(
            // Accept OPEN_API_KEY too; the key you enter in Settings › AI is the fallback.
            apiKey: env["OPENAI_API_KEY"] ?? env["OPEN_API_KEY"] ?? APIKeyStore.read() ?? "",
            focusOverride: optional("FOCUS_MINUTES").map { $0 * 60 },
            breakOverride: optional("BREAK_MINUTES").map { $0 * 60 },
            checkSeconds: max(2, number("CHECK_SECONDS", 5)),
            driftSeconds: number("DRIFT_SECONDS", 60),
            pauseSeconds: number("PAUSE_MINUTES", 5) * 60,
            voice: env["VOICE"] ?? "coral"
        )
    }

    /// The project's .env (its path is baked into Info.plist by build.sh), then next to the app, then the working directory.
    private static func findDotEnv() -> URL? {
        var candidates: [URL] = []
        if let path = Bundle.main.object(forInfoDictionaryKey: "RibbonEnvFile") as? String {
            candidates.append(URL(fileURLWithPath: path))
        }
        var dir = Bundle.main.bundleURL.deletingLastPathComponent()
        for _ in 0..<4 {
            candidates.append(dir.appendingPathComponent(".env"))
            dir = dir.deletingLastPathComponent()
        }
        candidates.append(URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".env"))
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    private static func parseDotEnv(_ url: URL) -> [String: String] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [:] }
        var values: [String: String] = [:]
        for rawLine in text.components(separatedBy: .newlines) {
            var line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            if line.hasPrefix("export ") { line.removeFirst("export ".count) }
            guard let eq = line.firstIndex(of: "=") else { continue }
            let key = line[..<eq].trimmingCharacters(in: .whitespaces)
            var value = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            if value.count >= 2, let first = value.first, first == value.last, first == "\"" || first == "'" {
                value = String(value.dropFirst().dropLast())
            }
            values[key] = value
        }
        return values
    }
}
