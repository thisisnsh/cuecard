import AVFoundation
import NaturalLanguage
import Speech

/// Follow My Voice (beta): the teleprompter listens to the reader and keeps
/// the words being said on the reading line, instead of scrolling at a set
/// speed. Speech is recognized on the iPhone and never leaves it.
@MainActor
final class VoiceFollower: ObservableObject {
    enum Status: Equatable {
        case idle
        case listening
        /// Listening can't start, and why, for the reader.
        case unavailable(String)
    }

    @Published private(set) var status: Status = .idle

    var isListening: Bool { status == .listening }

    /// How the session went, to report alongside the reader's rating.
    private(set) var metrics = VoiceSessionMetrics()

    private let microphone = Microphone()
    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var tracker: VoiceTracker?
    private var contextualWords: [String] = []
    private var listeningSince: Date?
    private var configurationObserver: NSObjectProtocol?
    /// Bumped for every start, stop and recognition task, so a late result
    /// from a task that was replaced is ignored, and a start still waiting on
    /// the microphone gives up if it was stopped or started again.
    private var generation = 0

    /// Called with each character of the script the voice has reached.
    var onProgress: ((Double) -> Void)?
    /// Where the reading line is now, so a drag or a jump by hand is followed
    /// from where it left the script.
    var readingCharacter: (() -> Double)?

    /// Start listening for `text`, the script as the teleprompter sets it.
    func start(text: String) async {
        guard !isListening else { return }
        generation += 1
        let current = generation
        if tracker?.text != text {
            tracker = VoiceTracker(text: text)
            contextualWords = VoiceTracker.distinctiveWords(in: text)
        }

        guard await Self.requestPermissions() else {
            status = .unavailable(String(localized: "Allow CueCard to use the microphone and speech recognition in Settings to follow your voice."))
            log("denied")
            return
        }
        guard current == generation else { return }
        guard let recognizer = Self.recognizer(for: text) else {
            status = .unavailable(String(localized: "Your voice can't be followed in this script's language on this iPhone yet."))
            log("unsupported_language")
            return
        }
        self.recognizer = recognizer

        do {
            try await microphone.start(into: audioTarget)
            guard current == generation else { return }
        } catch {
            guard current == generation else { return }
            stop()
            status = .unavailable(String(localized: "The microphone couldn't be started. Close anything else using it and try again."))
            log("audio_failed")
            return
        }

        // Another recorder taking the microphone — the camera — restarts the engine.
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: microphone.engine, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.restartEngine() }
        }

        status = .listening
        listeningSince = Date()
        beginRecognition()
        // A change while the microphone was starting came before anyone was watching.
        await restartEngine()
    }

    /// Stop listening. What's been heard so far still counts toward the session.
    func stop() {
        if let listeningSince {
            metrics.listenedSeconds += Date().timeIntervalSince(listeningSince)
        }
        listeningSince = nil
        generation += 1
        task?.cancel()
        task = nil
        request?.endAudio()
        request = nil
        audioTarget.set(nil)
        microphone.stop()
        if let configurationObserver { NotificationCenter.default.removeObserver(configurationObserver) }
        configurationObserver = nil
        if isListening { status = .idle }
    }

    /// Back to the top of the script: the next words are looked for from there.
    func restart() {
        tracker?.reset()
    }

    // MARK: Recognition

    private let audioTarget = AudioTarget()

    /// A recognition task runs until the recognizer decides an utterance is
    /// over, then another takes its place, for as long as listening goes on.
    private func beginRecognition() {
        guard isListening, let recognizer else { return }
        generation += 1
        let current = generation

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        request.contextualStrings = contextualWords
        self.request = request
        audioTarget.set(request)

        task = recognizer.recognitionTask(with: request, resultHandler: Self.results { [weak self] words, isOver in
            Task { @MainActor in
                guard let self, current == self.generation else { return }
                if !words.isEmpty { self.heard(words) }
                if isOver {
                    self.task = nil
                    self.request?.endAudio()
                    self.beginRecognition()
                }
            }
        })
    }

    /// The words recognized so far, and whether this task is over, from
    /// whatever queue the recognizer calls back on.
    nonisolated private static func results(
        _ deliver: @escaping @Sendable ([String], Bool) -> Void
    ) -> (SFSpeechRecognitionResult?, Error?) -> Void {
        { result, error in
            deliver(result?.bestTranscription.segments.map(\.substring) ?? [],
                    (result?.isFinal ?? false) || error != nil)
        }
    }

    private func heard(_ words: [String]) {
        guard var tracker else { return }
        if let reading = readingCharacter?() { tracker.sync(toCharacter: reading) }
        metrics.wordsHeard = max(metrics.wordsHeard, words.count)
        if let character = tracker.advance(heard: words) {
            metrics.moves += 1
            onProgress?(character)
        }
        metrics.progress = tracker.progress
        self.tracker = tracker
    }

    private func restartEngine() async {
        guard isListening else { return }
        let session = listeningSince
        do {
            try await microphone.restart()
        } catch {
            // Listening has since been stopped, or started over.
            guard listeningSince == session else { return }
            stop()
            status = .unavailable(String(localized: "The microphone stopped. Tap Play to listen again."))
            log("audio_interrupted")
        }
    }

    private func log(_ problem: String) {
        AnalyticsEvents.logButtonClick("follow_voice_unavailable", screen: "teleprompter", parameters: ["reason": problem])
    }

    // MARK: Setup

    private static func requestPermissions() async -> Bool {
        let speech = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0 == .authorized) }
        }
        guard speech else { return false }
        return await AVAudioApplication.requestRecordPermission()
    }

    /// A recognizer for the script's language that works on the iPhone,
    /// preferring the reader's own region's way of speaking it.
    private static func recognizer(for text: String) -> SFSpeechRecognizer? {
        let language = NLLanguageRecognizer.dominantLanguage(for: text)?.rawValue
            ?? Locale.current.language.languageCode?.identifier ?? "en"
        let locales = SFSpeechRecognizer.supportedLocales().filter { $0.language.languageCode?.identifier == language }
        let region = Locale.current.region
        let ordered = locales.sorted { a, _ in a.region == region }
        for locale in ordered {
            if let recognizer = SFSpeechRecognizer(locale: locale), recognizer.supportsOnDeviceRecognition {
                return recognizer
            }
        }
        return nil
    }
}

/// What a Follow My Voice session amounted to, for the rating sent after it.
struct VoiceSessionMetrics {
    var listenedSeconds: Double = 0
    /// The most words heard in one stretch of recognition.
    var wordsHeard = 0
    /// Times the script was moved on to follow the voice.
    var moves = 0
    /// How far through the script the voice got, from 0 to 1.
    var progress: Double = 0
}

/// The audio session and engine, worked on one call at a time on their own
/// queue: these calls can hang the main thread. A stop always lands after any
/// start before it, so the microphone ends up off however the two overlap.
private final class Microphone: @unchecked Sendable {
    /// Only for watching its configuration changes from outside the queue.
    let engine = AVAudioEngine()
    private let queue = DispatchQueue(label: "com.thisisnsh.cuecard.microphone", qos: .userInitiated)

    func start(into target: AudioTarget) async throws {
        try await perform {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default,
                                    options: [.mixWithOthers, .defaultToSpeaker, .allowBluetoothHFP])
            try session.setActive(true)
            let input = self.engine.inputNode
            input.removeTap(onBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { buffer, _ in
                target.append(buffer)
            }
            self.engine.prepare()
            try self.engine.start()
        }
    }

    /// Start the engine again, if something has stopped it.
    func restart() async throws {
        try await perform {
            guard !self.engine.isRunning else { return }
            self.engine.prepare()
            try self.engine.start()
        }
    }

    func stop() {
        queue.async {
            self.engine.inputNode.removeTap(onBus: 0)
            self.engine.stop()
        }
    }

    private func perform(_ work: @escaping @Sendable () throws -> Void) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async { continuation.resume(with: Result(catching: work)) }
        }
    }
}

/// The request the microphone's audio goes to, set on the main thread and
/// read on the audio thread.
private final class AudioTarget: @unchecked Sendable {
    private let lock = NSLock()
    private var request: SFSpeechAudioBufferRecognitionRequest?

    func set(_ request: SFSpeechAudioBufferRecognitionRequest?) {
        lock.withLock { self.request = request }
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        lock.withLock { request }?.append(buffer)
    }
}

// MARK: - Finding the words in the script

/// Finds where in the script the words just heard were said, from the
/// latest few words of what's been recognized.
///
/// The words are matched in order against a stretch of the script around
/// where the reader was, allowing for words skipped, misheard or not read
/// (a cue is in the text, but not said). Moving back, or far ahead, takes
/// more words in agreement than moving on a little does, so a common word
/// heard again doesn't throw the script about.
struct VoiceTracker {
    let text: String
    private let words: [(word: String, range: NSRange)]
    /// The last word of the script matched; -1 before any.
    private var current = -1

    init(text: String) {
        self.text = text
        var words: [(String, NSRange)] = []
        let string = text as NSString
        string.enumerateSubstrings(in: NSRange(location: 0, length: string.length), options: .byWords) { word, range, _, _ in
            guard let word else { return }
            let normalized = Self.normalized(word)
            if !normalized.isEmpty { words.append((normalized, range)) }
        }
        self.words = words
    }

    var progress: Double {
        words.isEmpty ? 0 : Double(current + 1) / Double(words.count)
    }

    mutating func reset() { current = -1 }

    /// The reading line was moved by hand: carry on from the word it's at.
    mutating func sync(toCharacter character: Double) {
        let expected = characterAfterCurrent
        guard abs(expected - character) > 2 else { return }
        // Everything before the reading line counts as read.
        current = words.lastIndex { Double($0.range.location) < character } ?? -1
    }

    /// Where the reading line goes after the current word: the start of the next one.
    private var characterAfterCurrent: Double {
        if current + 1 < words.count { return Double(words[current + 1].range.location) }
        guard let last = words.last else { return 0 }
        return Double(NSMaxRange(last.range))
    }

    /// Match the latest heard words. Returns the character to bring to the
    /// reading line, if the voice has moved on.
    mutating func advance(heard: [String]) -> Double? {
        let tail = heard.suffix(8).map(Self.normalized).filter { !$0.isEmpty }
        guard !tail.isEmpty, !words.isEmpty else { return nil }

        let low = max(0, current - 12)
        let high = min(words.count - 1, current + 60)
        guard low <= high else { return nil }

        var best: (index: Int, score: Int)?
        for end in low...high where Self.matches(words[end].word, tail[tail.count - 1]) {
            let start = max(0, end - tail.count - 3)
            let score = Self.agreement(tail, Array(words[start...end].map(\.word)))
            let needed = end < current || end > current + 20
                ? min(4, tail.count)
                : min(3, tail.count)
            guard score >= needed else { continue }
            // Most in agreement; between equals, the nearest ahead of where the reader was.
            if let previous = best {
                let closer = abs(end - (current + 1)) < abs(previous.index - (current + 1))
                guard score > previous.score || (score == previous.score && closer) else { continue }
            }
            best = (end, score)
        }

        // A word or two on its own only counts right after where the reader is.
        guard let best, tail.count >= 3 || best.index <= current + 3 else { return nil }
        guard best.index != current else { return nil }
        current = best.index
        return characterAfterCurrent
    }

    /// The most heard words found in the script stretch in the same order.
    private static func agreement(_ heard: [String], _ script: [String]) -> Int {
        var previous = [Int](repeating: 0, count: script.count + 1)
        for word in heard {
            var row = [Int](repeating: 0, count: script.count + 1)
            for j in 1...script.count {
                row[j] = matches(script[j - 1], word) ? previous[j - 1] + 1 : max(previous[j], row[j - 1])
            }
            previous = row
        }
        return previous.last ?? 0
    }

    /// The same word, allowing for a letter misheard in a longer one, or a
    /// word still being recognized.
    private static func matches(_ a: String, _ b: String) -> Bool {
        if a == b { return true }
        guard a.count >= 4, b.count >= 4 else { return false }
        if a.hasPrefix(b) || b.hasPrefix(a) { return true }
        return a.count == b.count && zip(a, b).filter { $0 != $1 }.count <= 1
    }

    private static func normalized(_ word: String) -> String {
        word.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .filter { $0.isLetter || $0.isNumber }
    }

    /// Words worth telling the recognizer to expect: the script's longer and
    /// rarer ones, like names, which it would otherwise mishear.
    static func distinctiveWords(in text: String) -> [String] {
        var counts: [String: Int] = [:]
        (text as NSString).enumerateSubstrings(in: NSRange(location: 0, length: (text as NSString).length),
                                              options: .byWords) { word, _, _, _ in
            guard let word, word.count >= 5 else { return }
            counts[word, default: 0] += 1
        }
        return counts.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value < $1.value }
            .prefix(100).map(\.key)
    }
}
