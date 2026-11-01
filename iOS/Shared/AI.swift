import Foundation
import Security

/// The OpenAI API key, in the keychain, shared with the monitor extension through the app group.
enum Keychain {
    private static let service = "com.jeremiahlena.ribbon"
    private static let account = "openai-api-key"

    static func load() -> String? {
        for group in [SharedStore.group, nil] {
            var query = base(group)
            query[kSecReturnData as String] = true
            query[kSecMatchLimit as String] = kSecMatchLimitOne
            var item: CFTypeRef?
            if SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data,
               let text = String(data: data, encoding: .utf8), !text.isEmpty {
                return text
            }
        }
        return nil
    }

    static func save(_ key: String?) {
        for group in [SharedStore.group, nil] { SecItemDelete(base(group) as CFDictionary) }
        guard let key, !key.isEmpty else { return }
        for group in [SharedStore.group, nil] {
            var query = base(group)
            query[kSecValueData as String] = Data(key.utf8)
            query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            if SecItemAdd(query as CFDictionary, nil) == errSecSuccess { return }
        }
    }

    private static func base(_ group: String?) -> [String: Any] {
        var query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service, kSecAttrAccount as String: account]
        if let group { query[kSecAttrAccessGroup as String] = group }
        return query
    }
}

struct AIError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// Ribbon's calls to OpenAI, paid for by your API key. They carry only what Ribbon itself records about a session (its
/// type, task, times, how it ended, the reason you gave). Nothing from Screen Time is sent: not minutes in apps, not the
/// blocked screen. Apple's Family Controls terms keep that data on the phone.
enum AI {
    static let model = "gpt-6-luna"

    static var isOn: Bool { Keychain.load() != nil }

    /// A structured answer, checked against `schema`.
    static func json(instructions: String, input: String, name: String, schema: [String: Any],
                     timeout: TimeInterval = 40) async throws -> [String: Any] {
        let text = try await respond([
            "model": model,
            "instructions": instructions,
            "input": input,
            "text": ["format": ["type": "json_schema", "name": name, "schema": schema, "strict": true]],
        ], timeout: timeout)
        guard let data = text.data(using: .utf8), let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AIError(message: "The AI's answer couldn't be read.")
        }
        return json
    }

    static func text(instructions: String, input: String, timeout: TimeInterval = 40) async throws -> String {
        try await respond(["model": model, "instructions": instructions, "input": input], timeout: timeout)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func respond(_ body: [String: Any], timeout: TimeInterval) async throws -> String {
        guard let key = Keychain.load() else { throw AIError(message: "Add an OpenAI API key in Settings › AI.") }
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/responses")!, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            let message = (json["error"] as? [String: Any])?["message"] as? String
            throw AIError(message: message ?? "OpenAI didn't answer (\((response as? HTTPURLResponse)?.statusCode ?? 0)).")
        }
        let text = (json["output"] as? [[String: Any]] ?? [])
            .filter { $0["type"] as? String == "message" }
            .flatMap { $0["content"] as? [[String: Any]] ?? [] }
            .compactMap { $0["type"] as? String == "output_text" ? $0["text"] as? String : nil }
            .joined()
        guard !text.isEmpty else { throw AIError(message: "The AI's answer was empty.") }
        return text
    }

    /// How the AI should talk: the desktop's two tones.
    static func voice(_ tone: Tone) -> String {
        switch tone {
        case .friendly:
            return "Be warm, playful and a little funny, never mean."
        case .ruthless:
            return """
            They chose the ruthless tone and asked for it: be a posh English butler who has run out of patience. Mock what \
            they're doing, throw their own numbers and goal back at them, swear if you like, never soften it or say please. \
            Hard limits: nothing about self-harm, suicide or mental illness, or that their life is worthless; no slurs or \
            attacks on race, religion, gender, sexuality or nationality; no threats of violence.
            """
        }
    }

    /// A check-in for when distracting apps pass a time mark today, in Ribbon's own words.
    static func plainCheckIn(minutes: Int, task: String?, tone: Tone) -> String {
        let spent = "\(Format.duration(TimeInterval(minutes * 60))) in distracting apps today."
        switch tone {
        case .friendly: return spent + (task.map { " Back to \($0)?" } ?? " Time to put the phone down?")
        case .ruthless: return spent + (task.map { " \($0) isn't going to finish itself." } ?? " Put the phone down.")
        }
    }
}
