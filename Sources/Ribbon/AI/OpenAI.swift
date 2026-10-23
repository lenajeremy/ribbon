import Foundation

struct OpenAIError: LocalizedError {
    let message: String
    /// OpenAI's error code, when there is one.
    var code: String?
    var errorDescription: String? { message }
}

/// Ribbon's calls to OpenAI. They're paid by an API key, or, when you sign in with ChatGPT, by your ChatGPT plan.
/// The plan route takes only streamed Responses requests without some parameters, and has no Decisions API or voices,
/// so in plan mode requests are trimmed and streamed, and Decisions questions are asked as structured Responses
/// requests. With an API key, everything goes to OpenAI as before.
final class OpenAI: @unchecked Sendable {
    static let apiModel = "gpt-6-luna"

    private let key: String
    let chatgpt: ChatGPTAuth?
    private let session: URLSession
    private let streaming: URLSession
    private let lock = NSLock()
    private var planModelsCache: [String]?
    private var limitReachedAt: Date?

    init(key: String, chatgpt: ChatGPTAuth? = nil) {
        self.key = key
        self.chatgpt = chatgpt
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 20
        session = URLSession(configuration: config)
        // A streamed answer can go quiet while the model thinks.
        let stream = URLSessionConfiguration.ephemeral
        stream.timeoutIntervalForRequest = 120
        streaming = URLSession(configuration: stream)
    }

    /// Signed in with ChatGPT and allowed to use the plan: the plan pays, and the API key isn't used.
    var usesPlan: Bool { chatgpt?.canUsePlan == true }
    var isAvailable: Bool { usesPlan || !key.isEmpty }
    var hasAPIKey: Bool { !key.isEmpty }
    /// OpenAI's voices aren't part of the ChatGPT plan; the orb uses a macOS voice then.
    var canSpeak: Bool { !usesPlan && !key.isEmpty }
    /// The plan's usage limit (or Ribbon's weekly cap) was hit recently; requests wait a while before trying again.
    var limitReached: Bool {
        lock.withLock { limitReachedAt.map { Date().timeIntervalSince($0) < 15 * 60 } ?? false }
    }

    /// Probability (0–1) that the user is working on `task`, or nil if the model refused to answer.
    func onTaskProbability(task: String, context: String, shots: [Screenshot]) async throws -> Double? {
        var content: [[String: Any]] = [["type": "input_text", "text": context]]
        for shot in shots {
            content.append(["type": "input_text", "text": shot.label])
            content.append(["type": "input_image", "image_url": shot.dataURL])
        }
        let question = """
                Is the user, right now, actively working on what they said they'd work on ("\(task)")? \
                Judge by what they're actively using: the frontmost window and the display with the mouse cursor. \
                Count it as yes when that plausibly serves the task: the work itself, related docs, research or searches, \
                AI assistants or terminals used for it, or messages about it. \
                Count it as no when it's unrelated: entertainment, videos, social feeds, news, shopping, games, \
                or chats and work about other things. Unrelated things merely left open on other displays don't count against them. \
                Ignore the small glowing orb timer overlay; that's this focus timer.
                """
        if usesPlan { return try await planProbability(content: content, statement: question) }
        let body: [String: Any] = [
            "model": Self.apiModel,
            "input": [["role": "user", "content": content]],
            "questions": [["type": "predicate", "name": "on_task", "instructions": question]],
        ]
        let json = try await postJSON("decisions", body)
        let answer = (json["answers"] as? [[String: Any]])?.first
        return answer?["probability"] as? Double
    }

    /// A short, spoken, slightly funny line naming what the user is doing instead of their task.
    /// A line for the orb to say, with the sound cues only the Gemini voice performs (like "<sigh>") left in.
    struct Quip: Sendable {
        let spoken: String
        /// How to perform it, chosen with the line: emotion, pace and emphasis.
        let delivery: String

        /// What the orb shows, and what voices without cues read.
        var text: String { Self.withoutCues(spoken) }

        /// The delivery, held to the tone's overall pace.
        func style(_ tone: OrbTone) -> String {
            delivery.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters)) + ". " + tone.pace
        }

        static func withoutCues(_ line: String) -> String {
            line.replacingOccurrences(of: #"\s*<[^<>]{1,30}>\s*"#, with: " ", options: .regularExpression)
                .replacingOccurrences(of: #"\s+([.,!?;:])"#, with: "$1", options: .regularExpression)
                .replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
        }
    }

    func quip(task: String, context: String, shot: Screenshot?, previous: [String], reminder: Int,
              tone: OrbTone = .friendly) async throws -> Quip {
        var instructions = """
        You are the focus orb in Ribbon, a tiny glowing orb that lives in the corner of the user's screen during a Pomodoro. \
        They said they'd work on: "\(task)". For over a minute they've been doing something else instead. \

        """
        switch tone {
        case .friendly:
            instructions += """
            Say exactly one sentence to them out loud: under 20 words, playful and a little funny, never mean. \
            Name specifically what they're doing instead (the site, video, app or topic you can see), then nudge them back to their task.
            """
            if reminder > 1 {
                instructions += " This is reminder number \(reminder); they ignored the last one, so be a bit more insistent (still fun)."
            }
        case .ruthless:
            instructions += """
            They chose the ruthless orb: they've asked you to say whatever it takes to get them back to work, and they won't take \
            offense. You speak like a cold, deeply unimpressed English butler: clipped, precise and quietly contemptuous, never \
            shouting. One or two short sentences, under 25 words in all. Name exactly what they're doing instead (the site, video, \
            app or topic you can see). Then make it land: hold them to the goal they set, point out what this is costing them, call \
            out the excuse they're about to make, or let your disappointment do the work. Dry sarcasm is fine; jokes and wordplay \
            aren't. Go after what they're doing, never who they are: nothing about their looks, body, health, family or identity, \
            no slurs, no threats, and mild swearing at most.
            """
            if reminder > 1 {
                instructions += " This is reminder number \(reminder) and they ignored the last one. Colder each time: "
                    + "by the third, no sarcasm left, only flat, quiet disappointment."
            }
        }
        let examples = tone == .ruthless ? "\"a weary sigh, then clipped and icy\" or \"mock-delighted, then suddenly flat\""
                                         : "\"a sly stage whisper\" or \"bright and quick, barely holding back a laugh\""
        instructions += """
         Plain spoken English: no emojis, hashtags, quotation marks or stage directions in the line. \
        An expressive voice reads it aloud, and you direct the performance. You may put up to two of these sound cues in the \
        line, where they'd happen: <sigh>, <short pause>, <long pause>, <laugh>. In "delivery", say how to perform it in under \
        12 words (emotion, pace, emphasis), like \(examples). Make each delivery different from the last. Describe the \
        performance, never the voice itself (age, accent, gender).
        """
        if !previous.isEmpty {
            instructions += " Earlier lines, which you must not repeat or open the same way: " + previous.joined(separator: " | ")
        }
        var content: [[String: Any]] = [["type": "input_text", "text": context]]
        if let shot { content.append(["type": "input_image", "image_url": shot.dataURL]) }
        let schema: [String: Any] = [
            "type": "object", "additionalProperties": false, "required": ["line", "delivery"],
            "properties": ["line": ["type": "string"], "delivery": ["type": "string"]],
        ]
        let output = Self.outputText(try await respond([
            "model": Self.apiModel,
            "reasoning": ["effort": "low"],
            "max_output_tokens": 800,
            "instructions": instructions,
            "input": [["role": "user", "content": content]],
            "text": ["format": ["type": "json_schema", "name": "orb_line", "strict": true, "schema": schema]],
        ]))
        let fields = (try? JSONSerialization.jsonObject(with: Data(output.utf8))) as? [String: String]
        let raw = fields?["line"] ?? output.components(separatedBy: .newlines).first { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? ""
        let line = raw.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"“”")))
        guard !Quip.withoutCues(line).isEmpty else { throw OpenAIError(message: "responses: empty output") }
        let delivery = fields?["delivery"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return Quip(spoken: line, delivery: delivery.isEmpty ? tone.delivery : delivery)
    }

    /// MP3 audio of `text` read by an OpenAI voice.
    func speech(_ text: String, voice: String, style: String = OrbTone.friendly.delivery) async throws -> Data {
        guard canSpeak else { throw OpenAIError(message: "OpenAI voices aren't part of the ChatGPT plan") }
        return try await post("audio/speech", [
            "model": "gpt-4o-mini-tts",
            "voice": voice,
            "input": text,
            "instructions": style,
            "response_format": "mp3",
        ])
    }

    /// How likely (0–1) a yes/no statement about `input` is to hold, with the Decisions API.
    func probability(input: String, instructions: String) async throws -> Double? {
        if usesPlan { return try await planProbability(content: [["type": "input_text", "text": input]], statement: instructions) }
        let json = try await postJSON("decisions", [
            "model": Self.apiModel,
            "input": input,
            "questions": [["type": "predicate", "name": "fits", "instructions": instructions]],
        ])
        return (json["answers"] as? [[String: Any]])?.first?["probability"] as? Double
    }

    /// Picks one of `choices` with the Decisions API. Returns the chosen value and the model's confidence.
    func choose(input: String, instructions: String, choices: [(value: String, description: String)]) async throws -> (value: String, confidence: Double) {
        if usesPlan { return try await planChoice(input: input, instructions: instructions, choices: choices) }
        let json = try await postJSON("decisions", [
            "model": Self.apiModel,
            "input": input,
            "questions": [[
                "type": "choice",
                "name": "pick",
                "instructions": instructions,
                "choices": choices.map { ["value": $0.value, "description": $0.description] },
            ]],
        ])
        guard let answer = (json["answers"] as? [[String: Any]])?.first, let value = answer["choice"] as? String else {
            throw OpenAIError(message: "decisions: no choice returned")
        }
        return (value, answer["confidence"] as? Double ?? 0)
    }

    /// A Responses API call; the caller builds the body (tools, structured output, follow-ups).
    /// On the ChatGPT plan, follow-ups can't use previous_response_id: send the history in `input` instead.
    func respond(_ body: [String: Any]) async throws -> [String: Any] {
        usesPlan ? try await planResponse(body) : try await postJSON("responses", body)
    }

    // MARK: ChatGPT plan

    /// The models the signed-in plan offers.
    func planModels() async -> [String] {
        if let cached = lock.withLock({ planModelsCache }) { return cached }
        guard let token = try? await chatgpt?.accessToken() else { return [] }
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/models")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        guard let (data, response) = try? await session.data(for: request), (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        let entries = json["models"] as? [[String: Any]] ?? json["data"] as? [[String: Any]] ?? []
        let models = entries.filter { ($0["visibility"] as? String ?? "list") == "list" }.compactMap { ($0["slug"] ?? $0["id"]) as? String }
        lock.withLock { planModelsCache = models }
        return models
    }

    /// The model plan requests use: the one picked in Settings, else Ribbon's usual model if the plan offers it,
    /// else the plan's first model of the same family, else its first model.
    func planModel() async -> String {
        let models = await planModels()
        if let picked = UserDefaults.standard.string(forKey: "chatgptModel"), models.contains(picked) { return picked }
        return models.first { $0 == Self.apiModel } ?? models.first { $0.contains("luna") } ?? models.first ?? Self.apiModel
    }

    /// Parameters the plan route rejects. Ribbon only uses max_output_tokens and previous_response_id, but drops all of them.
    private static let unsupportedOnPlan = ["background", "conversation", "max_output_tokens", "max_tool_calls", "metadata", "moderation",
                                            "prompt", "prompt_cache_retention", "safety_identifier", "temperature", "top_logprobs",
                                            "top_p", "truncation", "user", "previous_response_id"]

    /// A Responses request paid by the ChatGPT plan: unstored and streamed, as the plan route requires.
    /// Returns the finished response, in the same shape as a non-streamed one.
    private func planResponse(_ original: [String: Any], attempt: Int = 0) async throws -> [String: Any] {
        guard let chatgpt else { throw ChatGPTAuthError.signInNeeded }
        if limitReached { throw Self.planError(code: "subscription_sharing_usage_limit_exceeded", param: nil, message: "", status: 429) }
        var body = original
        for key in Self.unsupportedOnPlan { body.removeValue(forKey: key) }
        // The plan route takes input only as a list of items, not as plain text.
        if let text = body["input"] as? String { body["input"] = [["role": "user", "content": text]] }
        body["store"] = false
        body["stream"] = true
        body["model"] = await planModel()

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/responses")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(try await chatgpt.accessToken())", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (bytes, response) = try await streaming.bytes(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0

        guard (200..<300).contains(status) else {
            var data = Data()
            for try await byte in bytes {
                data.append(byte)
                if data.count > 64_000 { break }
            }
            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let error = json?["error"] as? [String: Any]
            let code = error?["code"] as? String, param = error?["param"] as? String
            let message = error?["message"] as? String ?? json?["detail"] as? String ?? String(decoding: data.prefix(300), as: UTF8.self)
            // An expired token, or a model the plan no longer offers: renew and try once more.
            if attempt == 0 && status == 401 {
                _ = try await chatgpt.accessToken(forceRefresh: true)
                return try await planResponse(original, attempt: 1)
            }
            if attempt == 0 && code == "subscription_sharing_unsupported_capability" && param == "model" {
                lock.withLock { planModelsCache = nil }
                return try await planResponse(original, attempt: 1)
            }
            throw note(Self.planError(code: code, param: param, message: message, status: status))
        }

        // The plan route's final event can arrive without the output, which streams item by item before it.
        var items: [(index: Int, item: [String: Any])] = []
        for try await line in bytes.lines {
            guard line.hasPrefix("data:") else { continue }
            let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            guard let event = try? JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any] else { continue }
            switch event["type"] as? String {
            case "response.output_item.done":
                if let item = event["item"] as? [String: Any] { items.append(((event["output_index"] as? Int) ?? items.count, item)) }
            case "response.completed":
                var finished = event["response"] as? [String: Any] ?? [:]
                if (finished["output"] as? [Any])?.isEmpty ?? true {
                    finished["output"] = items.sorted { $0.index < $1.index }.map(\.item)
                }
                return finished
            case "response.failed":
                let error = (event["response"] as? [String: Any])?["error"] as? [String: Any]
                throw note(Self.planError(code: error?["code"] as? String, param: error?["param"] as? String,
                                          message: error?["message"] as? String ?? "The answer failed.", status: 200))
            case "response.incomplete":
                throw OpenAIError(message: "The answer was cut off before it finished.")
            case "error":
                // The details are under "error", or at the top level in older streams.
                let error = event["error"] as? [String: Any] ?? event
                throw note(Self.planError(code: error["code"] as? String, param: error["param"] as? String,
                                          message: error["message"] as? String ?? "The answer failed.", status: 200))
            default:
                continue
            }
        }
        throw OpenAIError(message: "The answer stopped before it finished.")
    }

    /// A Decisions-style yes/no question, asked on the plan as a structured request: the probability that
    /// `statement` holds for the content.
    private func planProbability(content: [[String: Any]], statement: String) async throws -> Double? {
        let schema: [String: Any] = [
            "type": "object", "additionalProperties": false, "required": ["probability"],
            "properties": ["probability": ["type": "number", "description": "From 0 (certainly not) to 1 (certainly)."]],
        ]
        let json = try await planResponse([
            "reasoning": ["effort": "low"],
            "instructions": "Judge the input, then give the probability, from 0 to 1, that this holds:\n\(statement)",
            "input": [["role": "user", "content": content]],
            "text": ["format": ["type": "json_schema", "name": "decision", "strict": true, "schema": schema]],
        ])
        let fields = (try? JSONSerialization.jsonObject(with: Data(Self.outputText(json).utf8))) as? [String: Any]
        return (fields?["probability"] as? NSNumber).map { min(1, max(0, $0.doubleValue)) }
    }

    /// A Decisions-style pick from `choices`, asked on the plan as a structured request, with how sure the model is.
    private func planChoice(input: String, instructions: String,
                            choices: [(value: String, description: String)]) async throws -> (value: String, confidence: Double) {
        let schema: [String: Any] = [
            "type": "object", "additionalProperties": false, "required": ["choice", "confidence"],
            "properties": [
                "choice": ["type": "string", "enum": choices.map(\.value)],
                "confidence": ["type": "number", "description": "How sure you are, from 0 to 1."],
            ],
        ]
        let list = choices.map { "- \($0.value): \($0.description)" }.joined(separator: "\n")
        let json = try await planResponse([
            "reasoning": ["effort": "low"],
            "instructions": "\(instructions)\nAnswer with one of these choices, by its value:\n\(list)",
            "input": input,
            "text": ["format": ["type": "json_schema", "name": "choice", "strict": true, "schema": schema]],
        ])
        guard let fields = try? JSONSerialization.jsonObject(with: Data(Self.outputText(json).utf8)) as? [String: Any],
              let value = fields["choice"] as? String else { throw OpenAIError(message: "No choice returned") }
        return (value, min(1, max(0, (fields["confidence"] as? NSNumber)?.doubleValue ?? 0)))
    }

    /// What a plan error means, in words for the person.
    static func planError(code: String?, param: String?, message: String, status: Int) -> OpenAIError {
        let text: String
        switch code {
        case "subscription_sharing_usage_limit_exceeded":
            text = "Usage limit reached. Ribbon's AI is paused until your ChatGPT plan has room again. You can manage usage in ChatGPT settings."
        case "subscription_sharing_user_not_eligible":
            text = "Your ChatGPT plan can't be used in Ribbon. Use an OpenAI API key instead."
        case "subscription_sharing_usage_unavailable", "subscription_sharing_user_unavailable":
            text = "Using your ChatGPT plan isn't available right now. Ribbon will try again later."
        case "subscription_sharing_unsupported_capability":
            text = "Your ChatGPT plan doesn't support part of this request (\(param ?? "unknown"))."
        case "subscription_sharing_invalid_user", "chatpass_v2_scope_not_authorized", "chatpass_v2_invalid_authorization_context":
            text = "Your ChatGPT sign-in wasn't accepted. Sign in again in Settings › AI."
        default:
            text = "Request with your ChatGPT plan failed\(status == 200 ? "" : " (HTTP \(status))"): \(message)"
        }
        return OpenAIError(message: text, code: code)
    }

    /// Remembers a usage-limit error, so requests pause for a while instead of hitting the limit again.
    private func note(_ error: OpenAIError) -> OpenAIError {
        if error.code == "subscription_sharing_usage_limit_exceeded" {
            let first = lock.withLock { () -> Bool in
                defer { limitReachedAt = Date() }
                return limitReachedAt.map { Date().timeIntervalSince($0) >= 15 * 60 } ?? true
            }
            if first { logLine("ChatGPT plan usage limit reached; pausing AI requests") }
        }
        return error
    }

    static func outputText(_ json: [String: Any]) -> String {
        (json["output"] as? [[String: Any]] ?? [])
            .filter { $0["type"] as? String == "message" }
            .flatMap { $0["content"] as? [[String: Any]] ?? [] }
            .compactMap { $0["text"] as? String }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func functionCalls(_ json: [String: Any]) -> [(callID: String, name: String, arguments: String)] {
        (json["output"] as? [[String: Any]] ?? []).compactMap {
            guard $0["type"] as? String == "function_call", let id = $0["call_id"] as? String, let name = $0["name"] as? String else { return nil }
            return (id, name, $0["arguments"] as? String ?? "{}")
        }
    }

    private func postJSON(_ path: String, _ body: [String: Any]) async throws -> [String: Any] {
        let data = try await post(path, body)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw OpenAIError(message: "\(path): unexpected response")
        }
        return json
    }

    private func post(_ path: String, _ body: [String: Any]) async throws -> Data {
        guard !key.isEmpty else { throw OpenAIError(message: "Turn on AI in Settings › AI: continue with ChatGPT or add an OpenAI API key.") }
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/\(path)")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            let message = (json?["error"] as? [String: Any])?["message"] as? String
                ?? String(decoding: data.prefix(300), as: UTF8.self)
            throw OpenAIError(message: "\(path) HTTP \(status): \(message)")
        }
        return data
    }
}
