import Foundation

struct OpenAIError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// The three OpenAI calls the orb makes: a Decisions check every few seconds,
/// and, only when you drift, a one-line quip plus its speech audio.
final class OpenAI: @unchecked Sendable {
    private let key: String
    private let session: URLSession

    init(key: String) {
        self.key = key
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 20
        session = URLSession(configuration: config)
    }

    /// Probability (0–1) that the user is working on `task`, or nil if the model refused to answer.
    func onTaskProbability(task: String, context: String, shots: [Screenshot]) async throws -> Double? {
        var content: [[String: Any]] = [["type": "input_text", "text": context]]
        for shot in shots {
            content.append(["type": "input_text", "text": shot.label])
            content.append(["type": "input_image", "image_url": shot.dataURL])
        }
        let body: [String: Any] = [
            "model": "gpt-6-luna",
            "input": [["role": "user", "content": content]],
            "questions": [[
                "type": "predicate",
                "name": "on_task",
                "instructions": """
                Is the user, right now, actively working on what they said they'd work on ("\(task)")? \
                Judge by what they're actively using: the frontmost window and the display with the mouse cursor. \
                Count it as yes when that plausibly serves the task: the work itself, related docs, research or searches, \
                AI assistants or terminals used for it, or messages about it. \
                Count it as no when it's unrelated: entertainment, videos, social feeds, news, shopping, games, \
                or chats and work about other things. Unrelated things merely left open on other displays don't count against them. \
                Ignore the small glowing orb timer overlay; that's this focus timer.
                """,
            ]],
        ]
        let json = try await postJSON("decisions", body)
        let answer = (json["answers"] as? [[String: Any]])?.first
        return answer?["probability"] as? Double
    }

    /// A short, spoken, slightly funny line naming what the user is doing instead of their task.
    func quip(task: String, context: String, shot: Screenshot?, previous: [String], reminder: Int) async throws -> String {
        var instructions = """
        You are the focus orb in Ribbon, a tiny glowing orb that lives in the corner of the user's screen during a Pomodoro. \
        They said they'd work on: "\(task)". For over a minute they've been doing something else instead. \
        Say exactly one sentence to them out loud: under 20 words, playful and a little funny, never mean. \
        Name specifically what they're doing instead (the site, video, app or topic you can see), then nudge them back to their task. \
        Plain spoken English: no emojis, hashtags, quotation marks or stage directions.
        """
        if reminder > 1 {
            instructions += " This is reminder number \(reminder); they ignored the last one, so be a bit more insistent (still fun)."
        }
        if !previous.isEmpty {
            instructions += " Earlier lines, which you must not repeat or open the same way: " + previous.joined(separator: " | ")
        }
        var content: [[String: Any]] = [["type": "input_text", "text": context]]
        if let shot { content.append(["type": "input_image", "image_url": shot.dataURL]) }
        let body: [String: Any] = [
            "model": "gpt-6-luna",
            "reasoning": ["effort": "low"],
            "max_output_tokens": 800,
            "instructions": instructions,
            "input": [["role": "user", "content": content]],
        ]
        let json = try await postJSON("responses", body)
        let text = (json["output"] as? [[String: Any]] ?? [])
            .filter { $0["type"] as? String == "message" }
            .flatMap { $0["content"] as? [[String: Any]] ?? [] }
            .first { $0["type"] as? String == "output_text" }?["text"] as? String ?? ""
        let line = text
            .components(separatedBy: .newlines).first { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? ""
        let trimmed = line.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"“”")))
        guard !trimmed.isEmpty else { throw OpenAIError(message: "responses: empty output") }
        return trimmed
    }

    /// MP3 audio of `text` read by an OpenAI voice.
    func speech(_ text: String, voice: String) async throws -> Data {
        try await post("audio/speech", [
            "model": "gpt-4o-mini-tts",
            "voice": voice,
            "input": text,
            "instructions": "A cheeky, warm little sidekick. Light, quick and playful, with a smile in the voice.",
            "response_format": "mp3",
        ])
    }

    /// How likely (0–1) a yes/no statement about `input` is to hold, with the Decisions API.
    func probability(input: String, instructions: String) async throws -> Double? {
        let json = try await postJSON("decisions", [
            "model": "gpt-6-luna",
            "input": input,
            "questions": [["type": "predicate", "name": "fits", "instructions": instructions]],
        ])
        return (json["answers"] as? [[String: Any]])?.first?["probability"] as? Double
    }

    /// Picks one of `choices` with the Decisions API. Returns the chosen value and the model's confidence.
    func choose(input: String, instructions: String, choices: [(value: String, description: String)]) async throws -> (value: String, confidence: Double) {
        let json = try await postJSON("decisions", [
            "model": "gpt-6-luna",
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
    func respond(_ body: [String: Any]) async throws -> [String: Any] {
        try await postJSON("responses", body)
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
        guard !key.isEmpty else { throw OpenAIError(message: "No OPENAI_API_KEY in .env") }
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
