import Foundation

/// Everything the AI writes or answers: daily and weekly reviews, questions about your time,
/// session types from a description, and which session type fits a task.
@MainActor final class Assistant {
    private let openai: OpenAI
    private let reports: Reports
    let enabled: Bool

    init(openai: OpenAI, reports: Reports, enabled: Bool) {
        self.openai = openai
        self.reports = reports
        self.enabled = enabled
    }

    private var store: Store { reports.store }
    private var model: String { "gpt-6-luna" }

    // MARK: Reviews

    func cachedBrief(for day: Date) -> (text: String, created: Date)? {
        store.report(Format.dayKey(day), kind: "daily")
    }

    func dailyBrief(for day: Date) async throws -> String {
        let report = reports.day(day)
        let isToday = Calendar.current.isDateInToday(day)
        var input = reports.summary(report)
        input["day_in_progress"] = isToday
        input["time_now"] = Format.time(Date())
        let text = try await write(instructions: """
            You are the coach inside Ribbon, a private time tracker on the user's Mac. Write their daily review \
            from the stats. Format exactly:
            A headline under 12 words on its own line.
            Two or three lines starting with "• " on what went well and where time leaked, citing real numbers, apps and sites.
            A last line starting with "→ " with one concrete suggestion for \(isToday ? "the rest of the day" : "tomorrow").
            Second person, warm and direct, no filler, under 90 words. If the day is still in progress, say "so far".
            Write durations like "2h 15m" or "40m", never as large minute counts.
            """, input: input)
        store.saveReport(Format.dayKey(day), kind: "daily", text: text)
        return text
    }

    func cachedWeekly(for weekStart: Date) -> (text: String, created: Date)? {
        store.report(Format.dayKey(weekStart), kind: "weekly")
    }

    func weeklyReview(for weekStart: Date) async throws -> String {
        let week = reports.week(weekStart)
        let previous = reports.week(Calendar.current.date(byAdding: .day, value: -7, to: weekStart)!)
        func pack(_ w: WeekReport) -> [String: Any] {
            ["days": w.days.map(reports.compactSummary),
             "tracked_minutes": Int(w.total / 60), "focus_minutes": Int(w.focusTime / 60),
             "average_productivity_score": w.averageProductivity as Any, "average_focus_score": w.averageFocus as Any,
             "categories": w.byCategory.map { ["category": Categories.by($0.id).name, "minutes": Int($0.seconds / 60)] },
             "top_apps_and_sites": w.items.prefix(12).map { ["name": $0.label, "minutes": Int($0.seconds / 60)] }]
        }
        let text = try await write(instructions: """
            You are the coach inside Ribbon, a private time tracker. Write the user's weekly review, comparing this week \
            with last week. Format exactly:
            A headline under 12 words on its own line.
            Three or four lines starting with "• ": trends, best and worst day, biggest time sinks, focus patterns, with real numbers.
            A last line starting with "→ " with one experiment to try next week.
            Second person, warm and direct, under 120 words. If the week is still in progress, say "so far".
            Write durations like "27h 20m" or "40m", never as large minute counts.
            """, input: ["this_week": pack(week), "last_week": pack(previous), "today": Format.dayKey(Date())])
        store.saveReport(Format.dayKey(weekStart), kind: "weekly", text: text)
        return text
    }

    private func write(instructions: String, input: [String: Any]) async throws -> String {
        let data = try JSONSerialization.data(withJSONObject: input, options: [.sortedKeys])
        let json = try await openai.respond([
            "model": model, "reasoning": ["effort": "low"], "instructions": instructions,
            "input": String(decoding: data, as: UTF8.self),
        ])
        return OpenAI.outputText(json)
    }

    // MARK: Ask

    /// Answers a question about your time, looking things up in the local log with tools.
    /// Pass the previous response's id to keep the conversation going.
    func ask(_ question: String, previousID: String?) async throws -> (answer: String, responseID: String) {
        let now = Date()
        let instructions = """
            You are the AI inside Ribbon, a private time tracker on the user's Mac. Answer questions about how they spend \
            their time, using the tools to look things up; never guess numbers. Today is \(now.formatted(.dateTime.weekday(.wide).month(.wide).day().year())) \
            (\(Format.dayKey(now))), and it's \(Format.time(now)). Weeks start on Monday. Lead with a one-sentence answer, then the details. \
            Be specific: durations like "2h 15m", named apps and sites, times of day. Format in Markdown like a good chat answer: \
            "### " headings only for longer answers, "- " bullets for lists, a Markdown table when comparing several numbers, \
            **bold** for the key figures. Keep it short. If there's no data for a period, say so plainly.
            """
        var body: [String: Any] = [
            "model": model, "reasoning": ["effort": "low"], "instructions": instructions, "tools": Self.tools,
            "input": [["role": "user", "content": question]],
        ]
        if let previousID { body["previous_response_id"] = previousID }
        for _ in 0..<6 {
            let json = try await openai.respond(body)
            let id = json["id"] as? String ?? ""
            let calls = OpenAI.functionCalls(json)
            if calls.isEmpty { return (OpenAI.outputText(json), id) }
            body["previous_response_id"] = id
            body["input"] = calls.map { call in
                ["type": "function_call_output", "call_id": call.callID, "output": runTool(call.name, call.arguments)]
            }
        }
        throw OpenAIError(message: "The assistant kept looking things up without answering.")
    }

    private static let dateParam: [String: Any] = ["type": "string", "description": "A date as YYYY-MM-DD"]
    private static let tools: [[String: Any]] = [
        tool("get_day_summary", "Scores, time per category, top apps and sites, focus blocks, breaks and focus sessions for one day.",
             ["date": dateParam]),
        tool("get_range_summary", "Totals per day plus category and app/site totals for a date range (inclusive, at most 92 days).",
             ["start": dateParam, "end": dateParam]),
        tool("search_activity", "Time spent on apps, websites or page titles matching a word (like 'youtube', 'figma' or 'pull request') in a date range.",
             ["query": ["type": "string"], "start": dateParam, "end": dateParam]),
        tool("get_focus_sessions", "Focus sessions (Pomodoros) in a date range: task, session type, outcome, nudges and blocked attempts.",
             ["start": dateParam, "end": dateParam]),
    ]

    private static func tool(_ name: String, _ description: String, _ properties: [String: Any]) -> [String: Any] {
        ["type": "function", "name": name, "description": description, "strict": true,
         "parameters": ["type": "object", "properties": properties, "required": Array(properties.keys), "additionalProperties": false]]
    }

    private func runTool(_ name: String, _ arguments: String) -> String {
        let args = (try? JSONSerialization.jsonObject(with: Data(arguments.utf8))) as? [String: Any] ?? [:]
        func date(_ key: String) -> Date? { (args[key] as? String).flatMap(Format.day(fromKey:)) }
        let result: Any
        switch name {
        case "get_day_summary":
            result = date("date").map { reports.summary(reports.day($0)) } ?? ["error": "bad date"]
        case "get_range_summary":
            guard let range = range(date("start"), date("end")) else { result = ["error": "bad range"]; break }
            let days = range.map(reports.day)
            let week = Analytics.week(start: range[0], days: days)
            result = ["days": days.map(reports.compactSummary),
                      "categories": week.byCategory.map { ["category": Categories.by($0.id).name, "minutes": Int($0.seconds / 60)] },
                      "top_apps_and_sites": week.items.prefix(15).map { ["name": $0.label, "category": Categories.by($0.category).name,
                                                                          "minutes": Int($0.seconds / 60)] }]
        case "search_activity":
            guard let range = range(date("start"), date("end")) else { result = ["error": "bad range"]; break }
            let query = (args["query"] as? String ?? "").lowercased()
            let end = Calendar.current.date(byAdding: .day, value: 1, to: range.last!)!
            let matches = store.segments(from: range[0], to: end).filter {
                $0.label.lowercased().contains(query) || $0.app.lowercased().contains(query) || $0.title.lowercased().contains(query)
            }
            var byDay: [String: Double] = [:], byTitle: [String: (label: String, seconds: Double)] = [:]
            for m in matches {
                byDay[Format.dayKey(m.start), default: 0] += m.duration
                let title = m.title.isEmpty ? m.label : m.title
                byTitle[title, default: (m.label, 0)].seconds += m.duration
            }
            result = ["total_minutes": Int(matches.reduce(0) { $0 + $1.duration } / 60),
                      "by_day": byDay.sorted { $0.key < $1.key }.map { ["date": $0.key, "minutes": Int($0.value / 60)] },
                      "top_titles": byTitle.sorted { $0.value.seconds > $1.value.seconds }.prefix(12).map {
                          ["title": $0.key, "app_or_site": $0.value.label, "minutes": Int($0.value.seconds / 60)] }]
        case "get_focus_sessions":
            guard let range = range(date("start"), date("end")) else { result = ["error": "bad range"]; break }
            result = store.sessions(from: range[0], to: Calendar.current.date(byAdding: .day, value: 1, to: range.last!)!).map {
                ["date": Format.dayKey($0.start), "start": Format.time($0.start), "task": $0.task, "type": $0.profile,
                 "outcome": $0.outcome, "note": $0.note, "minutes": Int((($0.end ?? Date()).timeIntervalSince($0.start)) / 60),
                 "nudges": $0.nudges, "blocked_attempts": $0.blocks]
            }
        default:
            result = ["error": "unknown tool"]
        }
        let data = (try? JSONSerialization.data(withJSONObject: result)) ?? Data("{}".utf8)
        return String(decoding: data, as: UTF8.self)
    }

    private func range(_ start: Date?, _ end: Date?) -> [Date]? {
        guard let start, let end, start <= end else { return nil }
        let count = min(92, (Calendar.current.dateComponents([.day], from: start, to: end).day ?? 0) + 1)
        return (0..<count).map { Calendar.current.date(byAdding: .day, value: $0, to: start)! }
    }

    // MARK: Sessions

    /// "coding, browser only for localhost and google, no YouTube" → a session type.
    func makeProfile(from description: String) async throws -> SessionProfile {
        let installed = InstalledApps.all.map(\.name).joined(separator: ", ")
        let modeSchema: [String: Any] = ["type": "string", "enum": ["off", "allow_only", "block"]]
        let schema: [String: Any] = [
            "type": "object", "additionalProperties": false,
            "required": ["name", "emoji", "focus_minutes", "break_minutes", "app_mode", "apps", "site_mode", "sites",
                         "block_distracting", "watch_screen"],
            "properties": [
                "name": ["type": "string"], "emoji": ["type": "string"],
                "focus_minutes": ["type": "integer"], "break_minutes": ["type": "integer"],
                "app_mode": modeSchema, "apps": ["type": "array", "items": ["type": "string"]],
                "site_mode": modeSchema, "sites": ["type": "array", "items": ["type": "string"]],
                "block_distracting": ["type": "boolean"], "watch_screen": ["type": "boolean"],
            ],
        ]
        let json = try await openai.respond([
            "model": model, "reasoning": ["effort": "low"],
            "instructions": """
                Turn the user's description into a focus session type for Ribbon on macOS.
                - name: 1–3 words. emoji: one emoji. Default 50 minutes focus and 10 break unless they say otherwise.
                - app_mode "allow_only" means only the listed apps may be used; "block" means the listed apps are blocked; "off" means no app rules.
                - apps: exact names picked from the installed apps below. With allow_only, include everything the work needs \
                  (editor, terminal, browser if they mention websites). Only use apps from the list.
                - site_mode works the same way for websites. sites: bare domains like "github.com"; include "localhost" and "127.0.0.1" \
                  for local web development. "*.example.com" includes subdomains.
                - block_distracting: also block anything categorized as social media, news, entertainment or shopping.
                - watch_screen: true unless they ask not to be watched.
                Installed apps: \(installed)
                """,
            "input": description,
            "text": ["format": ["type": "json_schema", "name": "session", "strict": true, "schema": schema]],
        ])
        guard let fields = try JSONSerialization.jsonObject(with: Data(OpenAI.outputText(json).utf8)) as? [String: Any] else {
            throw OpenAIError(message: "Couldn't read the session the AI wrote.")
        }
        func mode(_ key: String) -> RuleMode {
            switch fields[key] as? String { case "allow_only": .allowOnly; case "block": .block; default: .off }
        }
        var apps: [AppRef] = []
        for name in fields["apps"] as? [String] ?? [] {
            if let app = InstalledApps.named(name), !apps.contains(app) { apps.append(app) }
        }
        return SessionProfile(
            name: fields["name"] as? String ?? "Focus", emoji: fields["emoji"] as? String ?? "🎯",
            focusMinutes: max(5, fields["focus_minutes"] as? Int ?? 50), breakMinutes: max(0, fields["break_minutes"] as? Int ?? 10),
            appMode: mode("app_mode"), apps: apps, siteMode: mode("site_mode"),
            sites: (fields["sites"] as? [String] ?? []).map(SiteMatch.normalize).filter { !$0.isEmpty },
            blockDistracting: fields["block_distracting"] as? Bool ?? true, watchScreen: fields["watch_screen"] as? Bool ?? true)
    }

    /// The session type that best fits what you're about to work on (Decisions API), if the AI is reasonably sure.
    func suggestProfile(for task: String, from profiles: [SessionProfile]) async -> String? {
        guard enabled, profiles.count > 1 else { return nil }
        let pick = try? await openai.choose(
            input: "The user is about to start a focus session to work on: \(task)",
            instructions: "Which session type fits this work best?",
            choices: profiles.map { ($0.id, "\($0.name): \($0.focusMinutes) minutes. \($0.rulesSummary).") })
        guard let pick, pick.confidence >= 0.4 else { return nil }
        return pick.value
    }
}
