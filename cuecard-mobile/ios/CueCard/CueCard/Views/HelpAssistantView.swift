import SwiftUI
import FoundationModels
import FirebaseAnalytics

/// Ask a question and get an answer from Apple's on-device model, drawn from
/// the help topics. Nothing asked leaves the iPhone.
struct HelpAssistantView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openURL) private var openURL
    @StateObject private var assistant = HelpAssistant()
    @State private var question = ""
    @State private var isRating = false
    @FocusState private var isAsking: Bool

    private let screen = "help_assistant"

    /// More to read under the introduction, before anything is asked: the help
    /// to browse, where this is Help's front page.
    let browse: AnyView?
    /// Done, from the page this was opened from: closes the whole sheet.
    let close: () -> Void

    init(browse: AnyView? = nil, close: @escaping () -> Void) {
        self.browse = browse
        self.close = close
    }

    private var trimmedQuestion: String {
        question.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if assistant.exchanges.isEmpty {
                        introduction
                        if let browse { browse }
                    }
                    ForEach(assistant.exchanges) { exchange in
                        exchangeView(exchange)
                            .id(exchange.id)
                    }
                    if !assistant.exchanges.isEmpty && !assistant.isAnswering {
                        feedbackRow
                    }
                }
                .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: assistant.exchanges.last?.answer) {
                guard let last = assistant.exchanges.last else { return }
                withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
            }
        }
        .safeAreaInset(edge: .bottom) { askBar }
        .navigationTitle(browse == nil ? "Help AI" : "Help")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // As Help's front page, back from the chat to the front page.
            // Pushed from the help list, the system's back button does it.
            if browse != nil && !assistant.exchanges.isEmpty {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        AnalyticsEvents.logButtonClick("help_ask_back", screen: screen)
                        isAsking = false
                        withAnimation(.snappy(duration: 0.25)) { assistant.reset() }
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .accessibilityLabel("Back")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") {
                    AnalyticsEvents.logButtonClick("help_ask_done", screen: screen)
                    close()
                }
            }
        }
        .onAppear {
            AnalyticsEvents.logButtonClick("open", screen: screen)
            // As Help's front page, the help to browse stays in view.
            isAsking = assistant.availability == .available && browse == nil
        }
        .onDisappear { assistant.stop() }
        .sheet(isPresented: $isRating) {
            AIFeedbackSheet(experience: .help(HelpFeedback.shared.metrics))
        }
    }

    // MARK: Parts

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .foregroundStyle(AppColors.purple(for: colorScheme))
                Text("Help AI")
                    .font(.headline)
                    .foregroundStyle(AppColors.textPrimary(for: colorScheme))
                BetaBadge()
            }
            .accessibilityElement(children: .combine)

            if case .unavailable(let reason) = assistant.availability {
                Text(reason)
                    .font(.subheadline)
                    .foregroundStyle(AppColors.textSecondary(for: colorScheme))
            } else {
                Text("Answers come from Apple Intelligence on this iPhone, using CueCard's help. They can be wrong.")
                    .font(.subheadline)
                    .foregroundStyle(AppColors.textSecondary(for: colorScheme))
            }
        }
    }

    private func exchangeView(_ exchange: HelpAssistant.Exchange) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(exchange.question)
                .font(.body)
                .foregroundStyle(colorScheme == .dark ? .black : .white)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(AppColors.textPrimary(for: colorScheme)))
                .frame(maxWidth: .infinity, alignment: .trailing)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(AppColors.purple(for: colorScheme))
                if exchange.answer.isEmpty && exchange.isAnswering {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text(exchange.answer)
                        .font(.body)
                        .foregroundStyle(exchange.failed
                                         ? AppColors.textSecondary(for: colorScheme)
                                         : AppColors.textPrimary(for: colorScheme))
                        .textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Under the last answer: rate the answers, or report what went wrong.
    /// Either one stands for the rating asked for when Help closes.
    private var feedbackRow: some View {
        HStack(spacing: 20) {
            Button {
                AnalyticsEvents.logButtonClick("help_ai_rate", screen: screen)
                HelpFeedback.shared.didAsk()
                isRating = true
            } label: {
                Label("Rate Answers", systemImage: "star")
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }

            Button {
                AnalyticsEvents.logButtonClick("help_ai_report", screen: screen)
                let experience = AIExperience.help(HelpFeedback.shared.metrics)
                Analytics.logEvent("\(experience.metric)_report", parameters: experience.parameters)
                HelpFeedback.shared.didAsk()
                openURL(experience.reportURL(stars: 0))
            } label: {
                Label("Report an Issue", systemImage: "exclamationmark.bubble")
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
        }
        .font(.footnote.weight(.semibold))
        .foregroundStyle(AppColors.textSecondary(for: colorScheme))
        .buttonStyle(.plain)
    }

    private var askBar: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Ask a question", text: $question, axis: .vertical)
                .lineLimit(1...4)
                .focused($isAsking)
                .submitLabel(.send)
                .onSubmit { ask(trimmedQuestion, from: "ask_keyboard") }
                .padding(.leading, 16)
                .padding(.vertical, 12)

            Button {
                ask(trimmedQuestion, from: "ask")
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(colorScheme == .dark ? .black : .white)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(AppColors.purple(for: colorScheme)))
            }
            .buttonStyle(.plain)
            .disabled(!canAsk)
            .opacity(canAsk ? 1 : 0.4)
            .accessibilityLabel("Ask")
        }
        .padding(6)
        .glassedEffect(in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .disabled(assistant.availability != .available)
    }

    private var canAsk: Bool {
        !trimmedQuestion.isEmpty && !assistant.isAnswering && assistant.availability == .available
    }

    private func ask(_ text: String, from button: String) {
        guard !text.isEmpty, !assistant.isAnswering else { return }
        AnalyticsEvents.logButtonClick(button, screen: screen, parameters: ["length": text.count])
        question = ""
        assistant.ask(text)
    }
}

// MARK: - Answering

/// The questions asked and their answers, as the model writes them.
@MainActor
final class HelpAssistant: ObservableObject {
    struct Exchange: Identifiable {
        let id = UUID()
        let question: String
        var answer = ""
        var isAnswering = true
        /// No answer could be given; `answer` says why.
        var failed = false
    }

    @Published private(set) var exchanges: [Exchange] = []
    let availability = OnDeviceModelAvailability.forAskAI
    private var task: Task<Void, Never>?
    /// A session for the next question, with the help already read in, so
    /// the answer starts sooner.
    private var nextSession: AnyObject?

    init() {
        prepare()
    }

    var isAnswering: Bool { exchanges.last?.isAnswering ?? false }

    /// Leaving the page stops an answer still being written.
    func stop() {
        task?.cancel()
        task = nil
        if let last = exchanges.indices.last, exchanges[last].isAnswering {
            exchanges[last].isAnswering = false
        }
    }

    /// Back to nothing asked: stops any answer, and clears the chat.
    func reset() {
        stop()
        exchanges.removeAll()
        prepare()
    }

    func ask(_ question: String) {
        guard #available(iOS 26.0, *), availability == .available else { return }
        AIUsage.recordQuestion()
        HelpFeedback.shared.recordQuestion()
        let exchange = Exchange(question: question)
        exchanges.append(exchange)
        let id = exchange.id

        let session = nextSession as? LanguageModelSession ?? HelpAnswerer.session()
        nextSession = nil
        let answers = HelpAnswerer.answer(question, in: session)
        task = Task { [weak self] in
            do {
                for try await answer in answers {
                    self?.update(id) { $0.answer = answer }
                }
                self?.update(id) { $0.isAnswering = false }
                if !Task.isCancelled { HelpFeedback.shared.recordAnswer(failed: false) }
            } catch {
                // Stopped, or the chat cleared: nothing to say about it.
                guard !Task.isCancelled else { return }
                self?.update(id) {
                    $0.answer = HelpAnswerer.message(for: error)
                    $0.failed = true
                    $0.isAnswering = false
                }
                HelpFeedback.shared.recordAnswer(failed: true)
            }
            if !Task.isCancelled { self?.prepare() }
        }
    }

    /// Changes the exchange with `id`, if it's still in the chat.
    private func update(_ id: Exchange.ID, _ change: (inout Exchange) -> Void) {
        guard let index = exchanges.firstIndex(where: { $0.id == id }) else { return }
        change(&exchanges[index])
    }

    /// Each question gets a session of its own, so one answer never leans on
    /// the last. The next one is readied while the user is reading or typing.
    private func prepare() {
        guard #available(iOS 26.0, *), availability == .available, nextSession == nil else { return }
        let session = HelpAnswerer.session()
        session.prewarm()
        nextSession = session
    }
}

@available(iOS 26.0, *)
private enum HelpAnswerer {
    /// All of CueCard's help goes in with every question. It's about 2,000
    /// tokens in English and 2,600 in Russian, which leaves room for the
    /// question and the answer even in the model's smallest context of 4,096.
    static func session() -> LanguageModelSession {
        let help = HelpLibrary.topics
            .map { "- \($0.section) › \($0.topic.title): \($0.topic.detail)" }
            .joined(separator: "\n")
        let instructions = """
            You answer questions about CueCard, an iPhone app for reading a script from a teleprompter \
            or from cards while speaking or recording. Answer only from CueCard's help, below. \
            Be brief: one to three sentences, naming the buttons and settings to use. \
            If the help doesn't answer the question, say that you don't know, and suggest Report a Bug or \
            Request a Feature in Help. Answer in the language of the question.

            CueCard's help:
            \(help)
            """
        return LanguageModelSession(model: SystemLanguageModel.default, instructions: instructions)
    }

    /// The answer as it's written, each time a little more of it.
    static func answer(_ question: String, in session: LanguageModelSession) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await snapshot in session.streamResponse(to: question) {
                        continuation.yield(snapshot.content)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    static func message(for error: Error) -> String {
        if let error = error as? LanguageModelSession.GenerationError {
            switch error {
            case .unsupportedLanguageOrLocale:
                return String(localized: "Questions in this language can't be answered yet.")
            case .guardrailViolation, .refusal:
                return String(localized: "That question couldn't be answered. Try asking it another way.")
            default:
                break
            }
        }
        return String(localized: "No answer could be found right now. Try again in a little while.")
    }
}
