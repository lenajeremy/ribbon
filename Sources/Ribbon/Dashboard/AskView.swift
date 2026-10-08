import SwiftUI

/// Ask anything about your time, laid out like ChatGPT: a question and a composer when it's empty,
/// a conversation with the composer at the bottom once it starts. Answers come from the local log.
struct AskView: View {
    @Bindable var model: DashboardModel

    private let suggestions: [(String, String)] = [
        ("clock", "Where did my time go today?"), ("play.rectangle", "How much YouTube did I watch this week?"),
        ("scope", "When am I most focused?"), ("chart.bar", "Compare this week with last week"),
        ("exclamationmark.bubble", "What distracted me most yesterday?"),
    ]

    var body: some View {
        if model.messages.isEmpty {
            VStack(spacing: 26) {
                Spacer()
                Text("What do you want to know about your time?")
                    .font(Typeface.greeting).foregroundStyle(Theme.ink).multilineTextAlignment(.center)
                Composer(placeholder: "Ask anything", text: $model.draft, busy: model.asking) { send() }
                FlowLayout(spacing: 8) {
                    ForEach(suggestions, id: \.1) { symbol, text in
                        Chip(text: text, symbol: symbol) { Task { await model.ask(text) } }
                    }
                }
                Spacer()
                Spacer()
            }
            .frame(maxWidth: 720)
            .padding(.horizontal, 32)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.page)
        } else {
            ZStack(alignment: .bottom) {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 28) {
                            ForEach(model.messages) { message in
                                MessageView(message: message).id(message.id)
                            }
                            if model.asking {
                                HStack(spacing: 8) {
                                    ProgressView().controlSize(.small)
                                    Text("Looking through your log").font(Typeface.body).foregroundStyle(Theme.muted)
                                }
                                .id("thinking")
                            }
                        }
                        .frame(maxWidth: 720, alignment: .leading)
                        .padding(.horizontal, 32)
                        .padding(.top, 32)
                        .padding(.bottom, 130)
                        .frame(maxWidth: .infinity)
                    }
                    .onChange(of: model.messages.count) {
                        withAnimation {
                            if model.asking { proxy.scrollTo("thinking", anchor: .bottom) }
                            else if let last = model.messages.last { proxy.scrollTo(last.id, anchor: .bottom) }
                        }
                    }
                }
                Composer(placeholder: "Ask a follow-up", text: $model.draft, busy: model.asking) { send() }
                    .modifier(ComposerDock())
            }
            .background(Theme.page)
        }
    }

    private func send() {
        Task { await model.ask(model.draft) }
    }
}

private struct MessageView: View {
    let message: ChatMessage

    var body: some View {
        switch message.role {
        case .user:
            HStack {
                Spacer(minLength: 140)
                Text(message.text)
                    .font(Typeface.body)
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(Theme.bubble, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .textSelection(.enabled)
            }
        case .assistant:
            VStack(alignment: .leading, spacing: 10) {
                MarkdownBlocks(text: message.text)
                HStack(spacing: 14) {
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(message.text, forType: .string)
                    } label: { Image(systemName: "doc.on.doc") }
                    .help("Copy")
                }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(Theme.muted)
            }
        case .error:
            Label(message.text, systemImage: "exclamationmark.triangle")
                .font(Typeface.body).foregroundStyle(Theme.muted)
        }
    }
}
