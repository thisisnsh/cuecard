import SwiftUI
import FoundationModels

/// What the assistant answers from.
enum AssistantTopic {
    /// How to use CueCard, from the help topics.
    case help
    /// The user's own saved scripts.
    case scripts
}

/// Ask a question and get an answer from Apple's on-device model, drawn from
/// the help topics or from the user's scripts. Nothing asked leaves the iPhone.
struct HelpAssistantView: View {
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var assistant: HelpAssistant
    @State private var question = ""
    @FocusState private var isAsking: Bool

    let topic: AssistantTopic
    /// More to read under the examples, before anything is asked: the help
    /// to browse, where this is Help's front page.
    let browse: AnyView?
    /// Done, from the page this was opened from: closes the whole sheet.
    let close: () -> Void

    init(topic: AssistantTopic = .help, browse: AnyView? = nil, close: @escaping () -> Void) {
        self.topic = topic
        self.browse = browse
        self.close = close
        _assistant = StateObject(wrappedValue: HelpAssistant(topic: topic))
    }

    private var screen: String {
        topic == .help ? "help_assistant" : "scripts_assistant"
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
        .navigationTitle(browse == nil ? "Ask" : "Help")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done", action: close)
            }
        }
        .onAppear {
            AnalyticsEvents.logButtonClick("open", screen: screen)
            // As Help's front page, the help to browse stays in view.
            isAsking = assistant.availability == .available && browse == nil
        }
        .onDisappear { assistant.stop() }
    }

    // MARK: Parts

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .foregroundStyle(AppColors.purple(for: colorScheme))
                Text(topic == .help ? "Ask anything about using CueCard." : "Ask anything about your scripts.")
                    .font(.headline)
                    .foregroundStyle(AppColors.textPrimary(for: colorScheme))
                BetaBadge()
            }

            if case .unavailable(let reason) = assistant.availability {
                Text(reason)
                    .font(.subheadline)
                    .foregroundStyle(AppColors.textSecondary(for: colorScheme))
            } else {
                Text(topic == .help
                     ? "Answers come from Apple Intelligence on this iPhone, using CueCard's help. They can be wrong."
                     : "Answers come from Apple Intelligence on this iPhone, reading your saved scripts. Nothing leaves this iPhone. Answers can be wrong.")
                    .font(.subheadline)
                    .foregroundStyle(AppColors.textSecondary(for: colorScheme))

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(examples, id: \.self) { example in
                        Button {
                            AnalyticsEvents.logButtonClick("example", screen: screen)
                            ask(example)
                        } label: {
                            Text(example)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(AppColors.textPrimary(for: colorScheme))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .glassedEffect(in: Capsule(), interactive: true)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var examples: [String] {
        switch topic {
        case .help:
            return [
                String(localized: "How do I add a pause to my script?"),
                String(localized: "How does Follow My Voice work?"),
                String(localized: "How do I record a video while I read?")
            ]
        case .scripts:
            return [
                String(localized: "Which script talks about pricing?"),
                String(localized: "Summarize my latest script."),
                String(localized: "Which of my scripts is the longest?")
            ]
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

    private var askBar: some View {
        HStack(spacing: 10) {
            TextField("Ask a question", text: $question, axis: .vertical)
                .lineLimit(1...4)
                .focused($isAsking)
                .submitLabel(.send)
                .onSubmit { ask(trimmedQuestion) }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .glassedEffect(in: RoundedRectangle(cornerRadius: 22, style: .continuous))

            Button {
                ask(trimmedQuestion)
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
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .disabled(assistant.availability != .available)
    }

    private var canAsk: Bool {
        !trimmedQuestion.isEmpty && !assistant.isAnswering && assistant.availability == .available
    }

    private func ask(_ text: String) {
        guard !text.isEmpty, !assistant.isAnswering else { return }
        AnalyticsEvents.logButtonClick("ask", screen: screen, parameters: ["length": text.count])
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
    let availability = OnDeviceModelAvailability.current
    let topic: AssistantTopic
    private var task: Task<Void, Never>?

    init(topic: AssistantTopic = .help) {
        self.topic = topic
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

    func ask(_ question: String) {
        guard #available(iOS 26.0, *), availability == .available else { return }
        exchanges.append(Exchange(question: question))
        let index = exchanges.count - 1

        let answers = topic == .help
            ? HelpAnswerer.answer(question)
            : ScriptsAnswerer.answer(question, notes: SettingsService.shared.savedNotes)
        task = Task { [weak self] in
            do {
                for try await answer in answers {
                    self?.exchanges[index].answer = answer
                }
                self?.exchanges[index].isAnswering = false
            } catch {
                self?.exchanges[index].answer = HelpAnswerer.message(for: error)
                self?.exchanges[index].failed = true
                self?.exchanges[index].isAnswering = false
            }
        }
    }
}

@available(iOS 26.0, *)
private enum HelpAnswerer {
    private static let instructions = """
        You answer questions about CueCard, an iPhone app for reading a script from a teleprompter \
        or from cards while speaking or recording. Answer only from the help topics in the prompt. \
        Be brief: one to three sentences, naming the buttons and settings to use. \
        If the topics don't answer the question, say you aren't sure, and suggest Report a Bug or \
        Request a Feature in Help. Answer in the language of the question.
        """

    /// About how much help goes in with a question. The model's context holds
    /// a few thousand tokens, instructions and answer included.
    private static let helpLength = 2400

    /// The answer as it's written, each time a little more of it.
    static func answer(_ question: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let session = LanguageModelSession(model: SystemLanguageModel.default, instructions: instructions)
                    let prompt = "Help topics:\n\(relevantHelp(for: question))\n\nQuestion: \(question)"
                    for try await snapshot in session.streamResponse(to: prompt) {
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

    /// The help topics sharing the most words with the question, as many as
    /// fit, best first.
    private static func relevantHelp(for question: String) -> String {
        let asked = words(in: question)
        let ranked = HelpLibrary.topics
            .map { entry in (entry, asked.intersection(words(in: entry.topic.title + " " + entry.topic.detail)).count) }
            .sorted { $0.1 > $1.1 }
        var help = ""
        for (entry, _) in ranked {
            let line = "- \(entry.section) › \(entry.topic.title): \(entry.topic.detail)\n"
            guard help.count + line.count <= helpLength else { continue }
            help += line
        }
        return help
    }

    /// The words that tell one topic from another: longer ones, any form.
    private static func words(in text: String) -> Set<String> {
        var words = Set<String>()
        text.enumerateSubstrings(in: text.startIndex..., options: .byWords) { word, _, _, _ in
            guard let word, word.count >= 4 else { return }
            words.insert(word.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil))
        }
        return words
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

@available(iOS 26.0, *)
private enum ScriptsAnswerer {
    private static let instructions = """
        You answer questions about the user's own scripts, written in CueCard to read from a \
        teleprompter or from cards. Answer only from the scripts in the prompt, naming each script \
        you mean by its title in quotes. Be brief: one to four sentences. If the scripts don't answer \
        the question, say you couldn't find it in them. Answer in the language of the question.
        """

    /// About how much of the scripts goes in with a question: a list of them
    /// all, then the text of those that look most relevant. The model's
    /// context holds a few thousand tokens, instructions and answer included.
    private static let listLength = 800
    private static let textLength = 2000
    private static let textPerScript = 700

    static func answer(_ question: String, notes: [SavedNote]) -> AsyncThrowingStream<String, Error> {
        let prompt = prompt(for: question, notes: notes)
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let session = LanguageModelSession(model: SystemLanguageModel.default, instructions: instructions)
                    for try await snapshot in session.streamResponse(to: prompt) {
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

    private static func prompt(for question: String, notes: [SavedNote]) -> String {
        let newest = notes.sorted { $0.updatedAt > $1.updatedAt }
        guard !newest.isEmpty else {
            return "The user has no saved scripts.\n\nQuestion: \(question)"
        }

        var list = ""
        for note in newest {
            let kind = note.mode == .cards ? "cards" : "teleprompter"
            let words = LibraryText.plain(note.content).split(whereSeparator: \.isWhitespace).count
            let folder = note.folder.map { ", folder \"\($0)\"" } ?? ""
            let line = "- \"\(note.title)\" (\(kind), \(words) words\(folder), edited "
                + "\(note.updatedAt.formatted(date: .abbreviated, time: .omitted)))\n"
            guard list.count + line.count <= listLength else { break }
            list += line
        }

        // The newest first among those sharing as many words with the question.
        let asked = words(in: question)
        let overlap: [UUID: Int] = Dictionary(newest.map { note in
            (note.id, asked.intersection(words(in: note.title + " " + note.content)).count)
        }, uniquingKeysWith: { first, _ in first })
        // A stable sort, so ties keep newest first.
        let ranked: [SavedNote] = newest.enumerated()
            .sorted { lhs, rhs in
                let left = overlap[lhs.element.id] ?? 0
                let right = overlap[rhs.element.id] ?? 0
                return left != right ? left > right : lhs.offset < rhs.offset
            }
            .map(\.element)
        var texts = ""
        for note in ranked {
            let text = String(LibraryText.plain(note.content).prefix(textPerScript))
            let entry = "## \"\(note.title)\"\n\(text)\n\n"
            guard texts.count + entry.count <= textLength else { continue }
            texts += entry
        }

        return "Scripts, newest first:\n\(list)\nTheir text:\n\(texts)Question: \(question)"
    }

    private static func words(in text: String) -> Set<String> {
        var words = Set<String>()
        text.enumerateSubstrings(in: text.startIndex..., options: .byWords) { word, _, _, _ in
            guard let word, word.count >= 4 else { return }
            words.insert(word.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil))
        }
        return words
    }
}
