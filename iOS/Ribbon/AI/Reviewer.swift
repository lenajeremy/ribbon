import Foundation

/// Reviews a focus session when it ends. The score comes from how long you focused against the plan and iOS's rough
/// minutes in your distracting apps, worked out on the phone. The AI, when it's on, writes the summary and tip from
/// Ribbon's own record of the session only; the Screen Time facts (distracting minutes, the blocked screen) are added
/// to its words on the phone and never sent, as Apple's Family Controls terms require.
enum Reviewer {
    /// Shorter sessions aren't reviewed.
    static let minimumLength: TimeInterval = 5 * 60

    static func review(_ record: SessionRecord) async -> SessionReview {
        let counted = record.counted
        let planned = TimeInterval(max(1, record.plannedMinutes) * 60)
        var deductions: [SessionReview.Deduction] = []
        if record.outcome == "stopped" {
            let left = max(0, planned - counted)
            let points = Int((100 * left / planned).rounded())
            if points > 0 {
                let how = record.note.hasPrefix("Emergency pass") ? "Ended with the emergency pass" : "Ended early"
                deductions.append(.init(reason: "\(how), \(Format.duration(left)) left", points: points))
            }
        }
        if record.distractingMinutes > 0 {
            let points = min(100, Int((100 * TimeInterval(record.distractingMinutes * 60) / max(counted, 60)).rounded()))
            deductions.append(.init(reason: "At least \(record.distractingMinutes)m in distracting apps", points: points))
        }
        let score = max(0, 100 - deductions.reduce(0) { $0 + $1.points })
        let plain = words(record, score: score, counted: counted)
        var review = SessionReview(score: score, verdict: SessionReview.verdict(score), summary: plain.summary,
                                   tip: plain.tip, deductions: deductions)
        guard AI.isOn else { return review }
        do {
            let answer = try await AI.json(instructions: instructions, input: facts(record, counted: counted),
                                           name: "session_review", schema: schema)
            if let summary = answer["summary"] as? String, let tip = answer["tip"] as? String, !summary.isEmpty {
                review = SessionReview(score: score, verdict: review.verdict, summary: summary + screenTimeNote(record),
                                       tip: record.distractingMinutes > 0 && record.outcome == "completed" ? plain.tip : tip,
                                       deductions: deductions, byAI: true)
            }
        } catch {
            log.error("Session review AI: \(error.localizedDescription)")
        }
        return review
    }

    private static var instructions: String {
        """
        You review a focus session the user just finished on their iPhone with Ribbon, a focus app that blocks apps and \
        websites during a session. You get only Ribbon's own record of the session below; you don't know which apps they \
        used, so never guess or mention any. Write:
        - summary: one or two plain sentences that use the real numbers: how long they focused out of the plan, and how \
        it ended, with the reason they gave if they stopped early.
        - tip: one sentence, something concrete to do differently next time.
        Don't invent anything that isn't in the facts. \(AI.voice(SharedStore.tone))
        """
    }

    private static let schema: [String: Any] = [
        "type": "object",
        "properties": ["summary": ["type": "string"], "tip": ["type": "string"]],
        "required": ["summary", "tip"],
        "additionalProperties": false,
    ]

    /// Ribbon's own record of the session: nothing here comes from Screen Time.
    private static func facts(_ record: SessionRecord, counted: TimeInterval) -> String {
        let paused = record.pauses.reduce(0) { $0 + $1.duration }
        let today = SharedStore.sessions.filter {
            $0.id != record.id && Calendar.current.isDate($0.start, inSameDayAs: record.start) && $0.start < record.start
        }
        var lines = [
            "working_on: \(record.task)",
            "session_type: \(record.profile)",
            "scheduled: \(record.isScheduled ? "yes, its rules can't be paused or stopped" : "no")",
            "started: \(Format.time(record.start))",
            "planned: \(record.plannedMinutes) minutes",
            "focused: \(Int(counted / 60)) minutes",
            "ended: \(record.outcome == "completed" ? "ran its full length" : "stopped early")",
        ]
        if !record.note.isEmpty { lines.append("reason_for_stopping: \(record.note)") }
        if record.isScheduled, paused > 0 { lines.append("breaks: \(Int(paused / 60)) minutes, not counted") }
        if !record.isScheduled, !record.pauses.isEmpty {
            lines.append("paused: \(record.pauses.count) time(s), \(Int(paused / 60)) minutes in all")
        }
        for earlier in today.suffix(4) {
            lines.append("earlier_today: \(earlier.task), \(earlier.outcome == "completed" ? "ran its full length" : "stopped early")")
        }
        return lines.joined(separator: "\n")
    }

    /// The Screen Time side of the session, added to the AI's words on the phone.
    private static func screenTimeNote(_ record: SessionRecord) -> String {
        var note = ""
        if record.distractingMinutes > 0 { note += " At least \(record.distractingMinutes)m went to distracting apps." }
        if record.blocks > 0 { note += " You hit the blocked screen \(record.blocks) time\(record.blocks == 1 ? "" : "s")." }
        return note
    }

    /// Ribbon's own words, when the AI is off or doesn't answer.
    private static func words(_ record: SessionRecord, score: Int, counted: TimeInterval) -> (summary: String, tip: String) {
        var summary = "You focused \(Format.duration(counted)) of \(Format.duration(TimeInterval(record.plannedMinutes * 60))) on \(record.task)."
        if record.outcome == "stopped", !record.note.isEmpty { summary += " You stopped early: \(record.note)." }
        if record.distractingMinutes > 0 { summary += " At least \(record.distractingMinutes)m went to distracting apps." }
        if record.blocks > 0 { summary += " You hit the blocked screen \(record.blocks) time\(record.blocks == 1 ? "" : "s")." }
        let tip: String
        if record.outcome == "stopped" {
            tip = "Pick a shorter session type when you can't give it the full time."
        } else if record.distractingMinutes > 0 {
            tip = "Add the apps that pulled you away to this session type's blocked apps."
        } else if record.blocks > 2 {
            tip = "Leave the phone face down and out of reach for the next one."
        } else {
            tip = "Start the next session the same way."
        }
        return (summary, tip)
    }
}
