import AppKit
import SwiftUI

struct ChatMessage: Identifiable, Hashable, Codable {
    enum Role: String, Codable { case user, assistant, error }
    var id = UUID()
    let role: Role
    let text: String
}

/// A saved conversation with the AI, listed in the sidebar like ChatGPT's history.
struct Chat: Identifiable, Hashable, Codable {
    var id = UUID().uuidString
    var title: String
    var messages: [ChatMessage]
    var responseID: String?
    var updated = Date()
}

/// State behind the dashboard window.
@Observable @MainActor final class DashboardModel {
    enum Section: String, CaseIterable, Identifiable {
        case today, week, sessions, ask, categories, settings
        var id: String { rawValue }

        var title: String {
            switch self {
            case .today: "Today"
            case .week: "Week"
            case .sessions: "Focus Sessions"
            case .ask: "Ask AI"
            case .categories: "Categories"
            case .settings: "Settings"
            }
        }

        var symbol: String {
            switch self {
            case .today: "sun.max"
            case .week: "chart.bar.xaxis"
            case .sessions: "target"
            case .ask: "sparkles"
            case .categories: "square.grid.2x2"
            case .settings: "gearshape"
            }
        }
    }

    var section: Section = .today
    var day = Calendar.current.startOfDay(for: Date())
    var report: DayReport?
    var weekStart = Reports.weekStart(for: Date())
    var week: WeekReport?
    var brief: (text: String, created: Date)?
    var briefLoading = false
    var weekly: (text: String, created: Date)?
    var weeklyLoading = false
    var aiError: String?
    var messages: [ChatMessage] = []
    var asking = false
    var draft = ""
    var chats: [Chat] = []
    var chatID: String?
    var recentDays: [(day: Date, seconds: Double)] = []
    var showSettings = false
    /// Which part of Settings to open on.
    var settingsPane = "General"
    var profiles: [SessionProfile]
    var sessions: [SessionRecord] = []
    var items: [KnownItem] = []
    var rules: CategoryRules
    var editing: SessionProfile?
    var editingCategory: Category?
    /// Bumped when categories change, so views redraw.
    var categoryVersion = 0
    var categoryNotice: String?
    var todayTotal: TimeInterval = 0

    @ObservationIgnored let store: Store
    @ObservationIgnored let reports: Reports
    @ObservationIgnored let assistant: Assistant
    @ObservationIgnored let classifier: Classifier
    @ObservationIgnored let tracker: ActivityTracker
    @ObservationIgnored let settings: Settings
    @ObservationIgnored var focus: FocusController?
    @ObservationIgnored var updater: Updater?
    @ObservationIgnored private var conversationID: String?
    @ObservationIgnored private var timer: Timer?

    init(store: Store, reports: Reports, assistant: Assistant, classifier: Classifier, tracker: ActivityTracker, settings: Settings) {
        self.store = store
        self.reports = reports
        self.assistant = assistant
        self.classifier = classifier
        self.tracker = tracker
        self.settings = settings
        rules = reports.rules
        var saved = store.profiles()
        if saved.isEmpty {
            saved = SessionProfile.defaults()
            store.saveProfiles(saved)
        }
        profiles = saved
        chats = store.chats()
    }

    var isToday: Bool { Calendar.current.isDateInToday(day) }
    var isThisWeek: Bool { weekStart == Reports.weekStart(for: Date()) }

    // MARK: Loading

    /// Takes a session off the Recent sessions list, or puts it back. Its time and review stay.
    func setHidden(_ hidden: Bool, session: SessionRecord) {
        store.setHidden(hidden, session: session.id)
        refresh()
    }

    func refresh() {
        recentDays = store.dailyTotals(days: 14)
        todayTotal = Calendar.current.isDateInToday(day) ? (report?.total ?? 0) : reports.day(Date()).total
        switch section {
        case .today:
            report = reports.day(day)
            if isToday { todayTotal = report!.total }
            brief = assistant.cachedBrief(for: day)
        case .week:
            week = reports.week(weekStart)
            weekly = assistant.cachedWeekly(for: weekStart)
        case .sessions:
            sessions = store.sessions(from: Date().addingTimeInterval(-30 * 86400), to: Date().addingTimeInterval(60))
        case .categories:
            items = store.knownItems(from: Date().addingTimeInterval(-7 * 86400), to: Date())
        case .ask, .settings:
            break
        }
    }

    func startAutoRefresh() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    func stopAutoRefresh() {
        timer?.invalidate()
        timer = nil
    }

    func show(_ section: Section) {
        self.section = section
        logLine("Dashboard: \(section.title)")
        refresh()
    }

    func moveDay(by days: Int) {
        let next = Calendar.current.date(byAdding: .day, value: days, to: day)!
        guard next <= Date() else { return }
        day = Calendar.current.startOfDay(for: next)
        refresh()
    }

    func moveWeek(by weeks: Int) {
        let next = Calendar.current.date(byAdding: .day, value: 7 * weeks, to: weekStart)!
        guard next <= Date() else { return }
        weekStart = next
        refresh()
    }

    // MARK: AI

    func writeBrief() async {
        guard assistant.enabled, !briefLoading else { return }
        briefLoading = true
        defer { briefLoading = false }
        do {
            let text = try await assistant.dailyBrief(for: day)
            brief = (text, Date())
            aiError = nil
        } catch {
            aiError = error.localizedDescription
        }
    }

    /// Writes today's brief when there's enough to say and the last one is stale.
    func briefIfStale() async {
        guard let report, report.total >= 30 * 60 else { return }
        let stale = brief.map { isToday && Date().timeIntervalSince($0.created) > 2 * 3600 } ?? true
        if stale { await writeBrief() }
    }

    func writeWeekly() async {
        guard assistant.enabled, !weeklyLoading else { return }
        weeklyLoading = true
        defer { weeklyLoading = false }
        do {
            let text = try await assistant.weeklyReview(for: weekStart)
            weekly = (text, Date())
            aiError = nil
        } catch {
            aiError = error.localizedDescription
        }
    }

    func ask(_ question: String) async {
        let question = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !asking else { return }
        section = .ask
        draft = ""
        var chat = chats.first { $0.id == chatID } ?? Chat(title: String(question.prefix(60)), messages: [])
        chatID = chat.id
        chat.messages.append(ChatMessage(role: .user, text: question))
        messages = chat.messages
        persist(chat)
        guard assistant.enabled else {
            chat.messages.append(ChatMessage(role: .error, text: "Add OPENAI_API_KEY to the .env file to ask questions."))
            messages = chat.messages
            return persist(chat)
        }
        asking = true
        defer { asking = false }
        do {
            let reply = try await assistant.ask(question, previousID: chat.responseID)
            chat.responseID = reply.responseID
            chat.messages.append(ChatMessage(role: .assistant, text: reply.answer))
        } catch {
            chat.messages.append(ChatMessage(role: .error, text: error.localizedDescription))
        }
        chat.updated = Date()
        if chatID == chat.id { messages = chat.messages }
        persist(chat)
    }

    private func persist(_ chat: Chat) {
        store.saveChat(chat)
        chats.removeAll { $0.id == chat.id }
        chats.insert(chat, at: 0)
    }

    func open(chat id: String) {
        guard let chat = chats.first(where: { $0.id == id }) else { return }
        chatID = id
        messages = chat.messages
        section = .ask
    }

    func newChat() {
        messages = []
        chatID = nil
        section = .ask
        logLine("Dashboard: new chat")
    }

    func rename(chat id: String, to title: String) {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, var chat = chats.first(where: { $0.id == id }) else { return }
        chat.title = title
        store.saveChat(chat)
        if let index = chats.firstIndex(where: { $0.id == id }) { chats[index] = chat }
    }

    func delete(chat id: String) {
        store.deleteChat(id)
        chats.removeAll { $0.id == id }
        if chatID == id { newChat() }
    }

    func show(day: Date) {
        self.day = Calendar.current.startOfDay(for: day)
        show(.today)
    }

    // MARK: Sessions

    func save(_ profile: SessionProfile) {
        if let index = profiles.firstIndex(where: { $0.id == profile.id }) { profiles[index] = profile } else { profiles.append(profile) }
        store.saveProfiles(profiles)
    }

    func delete(_ profile: SessionProfile) {
        profiles.removeAll { $0.id == profile.id }
        store.saveProfiles(profiles)
    }

    func start(_ profile: SessionProfile) {
        focus?.openPanel(profileID: profile.id)
    }

    // MARK: Categories

    func setCategory(_ item: KnownItem, to category: String) {
        classifier.setUserLabel(key: item.key, category: category)
        refresh()
    }

    func setKind(_ kind: Productivity, for category: Category) {
        rules.kinds[category.id] = kind
        persistRules(category)
    }

    func setFocus(_ focus: Bool, for category: Category) {
        rules.focus[category.id] = focus
        persistRules(category)
    }

    func save(_ category: Category, sortRecent: Bool) {
        var custom = Categories.custom
        if let index = custom.firstIndex(where: { $0.id == category.id }) { custom[index] = category } else { custom.append(category) }
        Categories.custom = custom
        store.saveCustomCategories(custom)
        categoryVersion += 1
        refresh()
        guard sortRecent, assistant.enabled else { return }
        categoryNotice = "Sorting your last week into \(category.name)…"
        let recent = store.knownItems(from: Date().addingTimeInterval(-7 * 86400), to: Date())
        Task {
            let moved = await classifier.resort(recent, into: category)
            categoryNotice = moved == 0 ? "Nothing from your last week fit \(category.name) yet. New apps and sites will be sorted into it as they show up."
                                        : "Moved \(moved) app\(moved == 1 ? "" : "s") and site\(moved == 1 ? "" : "s") into \(category.name)."
            categoryVersion += 1
            refresh()
        }
    }

    func delete(_ category: Category) {
        Categories.custom.removeAll { $0.id == category.id }
        store.saveCustomCategories(Categories.custom)
        store.forgetCategory(category.id)
        classifier.forget(category.id)
        categoryVersion += 1
        refresh()
    }

    private func persistRules(_ category: Category) {
        store.saveCategoryPref(id: category.id, kind: rules.kind(category.id), focus: rules.isFocus(category.id))
        reports.rules = rules
    }
}
