import CryptoKit
import Foundation

/// The orb's voice from Gemini 3.8 Flash TTS, used once you've saved a Gemini API key. Ribbon's own voice, a dry
/// English butler, is designed in your Google project the first time it speaks and reused after that; any of
/// Gemini's built-in voices can be picked instead. What the orb says is sent to Google to be turned into speech.
final class GeminiVoice: @unchecked Sendable {
    static let model = "gemini-3.8-flash-tts"
    /// Ribbon's own voice, as opposed to one of Gemini's built-in ones.
    static let ribbonVoice = "ribbon"
    static let builtIn = [
        "Achernar", "Achird", "Algenib", "Algieba", "Alnilam", "Aoede", "Autonoe", "Callirrhoe", "Charon", "Despina",
        "Enceladus", "Erinome", "Fenrir", "Gacrux", "Iapetus", "Kore", "Laomedeia", "Leda", "Orus", "Pulcherrima",
        "Puck", "Rasalgethi", "Sadachbia", "Sadaltager", "Schedar", "Sulafat", "Umbriel", "Vindemiatrix", "Zephyr",
        "Zubenelgenubi",
    ]
    private static let designName = "Ribbon's Butler"
    private static let design = "A posh, bone-dry English butler in his fifties with a crisp, plummy accent and a withering, "
        + "unimpressed wit; he speaks briskly, in clipped, precise sentences, faintly disappointed."
    private static let base = URL(string: "https://generativelanguage.googleapis.com/v1beta/")!

    private let lock = NSLock()
    private var key: String

    init(key: String = APIKeyStore.read(APIKeyStore.gemini) ?? "") {
        self.key = key
    }

    var isAvailable: Bool { lock.withLock { !key.isEmpty } }

    /// Saves the key to your keychain and starts using it right away.
    @discardableResult func setKey(_ newKey: String) -> Bool {
        let trimmed = newKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard APIKeyStore.save(trimmed, as: APIKeyStore.gemini) else { return false }
        lock.withLock { key = trimmed }
        return true
    }

    /// The voice you picked: Ribbon's own, or the name of a built-in one.
    var voice: String {
        get { UserDefaults.standard.string(forKey: "orbVoice") ?? Self.ribbonVoice }
        set { UserDefaults.standard.set(newValue, forKey: "orbVoice") }
    }

    /// WAV audio of `text` in `voice` (the one you picked, when nil), delivered the way `style` describes.
    func speech(_ text: String, style: String, voice: String? = nil) async throws -> Data {
        guard isAvailable else { throw GeminiError(status: 0, message: "No Gemini API key") }
        let chosen = voice ?? self.voice
        guard chosen == Self.ribbonVoice else { return try await synthesize(text, style: style, voice: chosen) }
        do {
            return try await synthesize(text, style: style, voice: try await designedVoice())
        } catch let error as GeminiError where error.status == 404 || (error.status == 400 && error.message.localizedCaseInsensitiveContains("voice")) {
            // Deleted, or unused for a year: design it again.
            UserDefaults.standard.removeObject(forKey: "geminiVoiceID")
            return try await synthesize(text, style: style, voice: try await designedVoice(lookUp: false))
        }
    }

    /// Finds or designs Ribbon's voice ahead of time (designing takes about half a minute), so the first nudge isn't late.
    func prepare() async {
        guard isAvailable, voice == Self.ribbonVoice else { return }
        do { _ = try await designedVoice() } catch { logLine("Gemini: couldn't get Ribbon's voice ready: \(error.localizedDescription)") }
    }

    private func synthesize(_ text: String, style: String, voice: String) async throws -> Data {
        let json = try await request("interactions", body: [
            "model": Self.model,
            "input": [["type": "user_input", "content": [[
                "type": "text", "text": text,
                "annotations": [["type": "speech_metadata", "style": style]],
            ]]]],
            "response_format": ["type": "audio"],
            "generation_config": ["speech_config": [["voice": voice]]],
        ])
        guard let encoded = Self.audio(in: json), let audio = Data(base64Encoded: encoded) else {
            throw GeminiError(status: 0, message: "Gemini sent no audio")
        }
        return Self.wav(audio)
    }

    // MARK: Ribbon's own voice

    /// Ribbon's voice in this key's Google project: remembered for the key, found again by name, or designed now.
    private func designedVoice(lookUp: Bool = true) async throws -> String {
        let defaults = UserDefaults.standard, owner = fingerprint
        if defaults.string(forKey: "geminiVoiceKey") == owner, let id = defaults.string(forKey: "geminiVoiceID") { return id }
        var id: String?
        if lookUp { id = try? await findDesignedVoice() }
        if id == nil { id = try await createDesignedVoice() }
        defaults.set(id, forKey: "geminiVoiceID")
        defaults.set(owner, forKey: "geminiVoiceKey")
        return id!
    }

    /// Made earlier with this project's key: on another Mac, or before Ribbon's settings were reset.
    private func findDesignedVoice() async throws -> String? {
        let json = try await request("voices", method: "GET")
        return (json["voices"] as? [[String: Any]] ?? [])
            .first { ($0["display_name"] ?? $0["displayName"]) as? String == Self.designName }
            .flatMap(Self.voiceID)
    }

    private func createDesignedVoice() async throws -> String {
        let json = try await request("voices", body: [
            "store": true,
            "voice": [
                "model": Self.model, "type": "prompted", "display_name": Self.designName,
                "gender": "male", "language_code": "en-GB", "prompted": ["input": Self.design],
            ],
        ])
        guard let id = Self.voiceID(json) ?? (json["voice"] as? [String: Any]).flatMap(Self.voiceID) else {
            throw GeminiError(status: 0, message: "Gemini didn't say which voice it made")
        }
        logLine("Gemini: designed Ribbon's voice (\(id))")
        return id
    }

    private static func voiceID(_ object: [String: Any]) -> String? {
        if let id = object["id"] as? String { return id }
        return (object["name"] as? String).map { $0.replacingOccurrences(of: "voices/", with: "") }
    }

    /// Tells keys apart without keeping them anywhere but the keychain.
    private var fingerprint: String {
        let digest = SHA256.hash(data: Data(lock.withLock { key }.utf8))
        return digest.prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: Requests

    private func request(_ path: String, method: String = "POST", body: [String: Any]? = nil) async throws -> [String: Any] {
        var request = URLRequest(url: Self.base.appendingPathComponent(path), timeoutInterval: 30)
        request.httpMethod = method
        request.setValue(lock.withLock { key }, forHTTPHeaderField: "x-goog-api-key")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard (200..<300).contains(status) else {
            let message = (json["error"] as? [String: Any])?["message"] as? String ?? String(decoding: data.prefix(300), as: UTF8.self)
            throw GeminiError(status: status, message: message)
        }
        return json
    }

    /// The answer's base64 audio, wherever it sits (over REST, in the model's output step).
    static func audio(in value: Any) -> String? {
        if let object = value as? [String: Any] {
            let mime = (object["mime_type"] ?? object["mimeType"]) as? String ?? ""
            if let data = object["data"] as? String, object["type"] as? String == "audio" || mime.hasPrefix("audio") { return data }
            return object.values.lazy.compactMap { audio(in: $0) }.first
        }
        return (value as? [Any])?.lazy.compactMap { audio(in: $0) }.first
    }

    /// Whole answers come as WAV; raw 16-bit, 24 kHz mono PCM gets a WAV header so it plays.
    static func wav(_ audio: Data) -> Data {
        if audio.starts(with: Data("RIFF".utf8)) { return audio }
        var header = Data()
        func append<T: FixedWidthInteger>(_ value: T) { withUnsafeBytes(of: value.littleEndian) { header.append(contentsOf: $0) } }
        header.append(Data("RIFF".utf8)); append(UInt32(36 + audio.count)); header.append(Data("WAVEfmt ".utf8))
        append(UInt32(16)); append(UInt16(1)); append(UInt16(1)); append(UInt32(24_000)); append(UInt32(48_000))
        append(UInt16(2)); append(UInt16(16)); header.append(Data("data".utf8)); append(UInt32(audio.count))
        return header + audio
    }
}

struct GeminiError: LocalizedError {
    let status: Int
    let message: String
    var errorDescription: String? { status > 0 ? "Gemini (\(status)): \(message)" : message }
}
