import AppKit
import Security

/// The API keys you enter in Settings, kept in your login keychain.
enum APIKeyStore {
    static let openAI = "OpenAI API key"
    static let gemini = "Gemini API key"
    private static let service = "Ribbon"

    static func read(_ account: String = openAI) -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecAttrAccount as String: account, kSecReturnData as String: true]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func save(_ key: String, as account: String = openAI) -> Bool {
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                   kSecAttrAccount as String: account]
        SecItemDelete(base as CFDictionary)
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        var item = base
        item[kSecValueData as String] = Data(trimmed.utf8)
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }
}

/// Quits and reopens Ribbon with its dashboard showing (it otherwise opens to the menu bar only, which looks like
/// it never came back), so an update or settings read at launch take effect. The reopen waits for this copy to
/// exit and retries while macOS still counts it as running.
@MainActor func relaunch() {
    let path = Bundle.main.bundlePath.replacingOccurrences(of: "'", with: "'\\''")
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/bin/sh")
    task.arguments = ["-c", """
        while kill -0 \(getpid()) 2>/dev/null; do sleep 0.2; done
        for attempt in 1 2 3 4 5 6; do
            open '\(path)' --args --dashboard && sleep 1 && pgrep -x Ribbon >/dev/null && exit 0
            sleep 1
        done
        """]
    try? task.run()
    NSApp.terminate(nil)
}
