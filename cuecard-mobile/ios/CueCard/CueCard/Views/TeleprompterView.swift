import SwiftUI
import UIKit
import FirebaseAnalytics
import FirebaseCrashlytics

struct TeleprompterView: View {
    let content: TeleprompterContent
    let settings: TeleprompterSettings

    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    @StateObject private var pipManager = TeleprompterPiPManager.shared

    @State private var isPlaying = false
    @State private var scrollOffset: CGFloat = 0
    @State private var elapsedTime: Double = 0
    @State private var timer: Timer?
    @State private var timerStartDate: Date?
    @State private var elapsedTimeAtTimerStart: Double = 0
    @State private var contentHeight: CGFloat = 0
    @State private var viewHeight: CGFloat = 0
    @State private var showControls = true
    @State private var controlsTimer: Timer?
    @State private var currentWordIndex: Int = 0
    @State private var dragOffset: CGFloat = 0
    @State private var countdownValue: Int = 0
    @State private var isCountingDown = false
    @State private var countdownTimer: Timer?
    @Environment(\.scenePhase) private var scenePhase

    // Timer properties
    private var timerDuration: Int { settings.timerDurationSeconds }
    private var remainingTime: Int {
        max(timerDuration - Int(elapsedTime), timerDuration > 0 ? Int(elapsedTime) - timerDuration : 0)
    }
    private var isOvertime: Bool {
        timerDuration > 0 && Int(elapsedTime) > timerDuration
    }

    private var timerColor: Color {
        // Show pink color during countdown
        if isCountingDown {
            return AppColors.pink(for: colorScheme)
        }
        guard timerDuration > 0 else {
            return AppColors.textPrimary(for: colorScheme)
        }
        return AppColors.timerColor(
            remainingSeconds: timerDuration - Int(elapsedTime),
            totalSeconds: timerDuration,
            colorScheme: colorScheme
        )
    }

    private var timeDisplay: String {
        // Show countdown if counting down (in mm:ss format)
        if isCountingDown {
            return " \(TeleprompterParser.formatTime(countdownValue)) "
        }
        if timerDuration > 0 {
            let remaining = timerDuration - Int(elapsedTime)
            return " \(TeleprompterParser.formatTime(remaining)) "
        }
        return " \(TeleprompterParser.formatTime(Int(elapsedTime))) "
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ZStack {
                    // Background - matches device theme
                    AppColors.background(for: colorScheme)
                        .ignoresSafeArea()

                    // Teleprompter content with attributed text
                    let wordsPerSecond = Double(settings.wordsPerMinute) / 60.0
                    let highlightProgress = (elapsedTime == 0 && !isPlaying)
                        ? -Double.greatestFiniteMagnitude
                        : (elapsedTime * wordsPerSecond)

                    AttributedTextView(
                        content: content,
                        fontSize: CGFloat(settings.fontSize),
                        currentWordIndex: currentWordIndex,
                        highlightProgress: highlightProgress,
                        colorScheme: colorScheme,
                        topPadding: geometry.size.height * 0.4,
                        bottomPadding: geometry.size.height * 0.6,
                        onTap: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showControls.toggle()
                            }
                            resetControlsTimer()
                        }
                    )

                    // Controls overlay
                    if showControls {
                        VStack {
                            Spacer()

                            HStack(spacing: 24) {
                                // Backward 10 seconds
                                Button(action: {
                                    AnalyticsEvents.logButtonClick("seek_backward", screen: "teleprompter")
                                    seekBackward()
                                }) {
                                    Image(systemName: "gobackward.10")
                                        .font(.system(size: 24))
                                        .foregroundStyle(AppColors.textPrimary(for: colorScheme))
                                        .frame(width: 48, height: 48)
                                        .glassedEffect(in: Circle())
                                }

                                // PiP toggle button
                                if pipManager.isPiPPossible {
                                    Button(action: {
                                        AnalyticsEvents.logButtonClick(pipManager.isPiPActive ? "pip_exit" : "pip_enter", screen: "teleprompter")
                                        togglePiP()
                                    }) {
                                        Image(systemName: pipManager.isPiPActive ? "pip.exit" : "pip.enter")
                                            .font(.system(size: 20, weight: .semibold))
                                            .foregroundStyle(AppColors.textPrimary(for: colorScheme))
                                            .frame(width: 52, height: 52)
                                            .glassedEffect(in: Circle())
                                    }
                                    .accessibilityLabel(pipManager.isPiPActive ? "Close Overlay" : "Start Overlay")
                                }

                                // Play/Pause button
                                Button(action: {
                                    AnalyticsEvents.logButtonClick((isPlaying || isCountingDown) ? "pause" : "play", screen: "teleprompter")
                                    togglePlayPause()
                                }) {
                                    Image(systemName: (isPlaying || isCountingDown) ? "pause.fill" : "play.fill")
                                        .font(.system(size: 28, weight: .semibold))
                                        .foregroundStyle(colorScheme == .dark ? .black : .white)
                                        .frame(width: 72, height: 72)
                                        .background(
                                            Circle()
                                                .fill(AppColors.green(for: colorScheme))
                                        )
                                        .glassedEffect(in: Circle())
                                }

                                // Restart button
                                Button(action: {
                                    AnalyticsEvents.logButtonClick("restart", screen: "teleprompter")
                                    restart()
                                }) {
                                    Image(systemName: "arrow.counterclockwise")
                                        .font(.system(size: 20, weight: .semibold))
                                        .foregroundStyle(AppColors.textPrimary(for: colorScheme))
                                        .frame(width: 52, height: 52)
                                        .glassedEffect(in: Circle())
                                }

                                // Forward 10 seconds
                                Button(action: {
                                    AnalyticsEvents.logButtonClick("seek_forward", screen: "teleprompter")
                                    seekForward()
                                }) {
                                    Image(systemName: "goforward.10")
                                        .font(.system(size: 24))
                                        .foregroundStyle(AppColors.textPrimary(for: colorScheme))
                                        .frame(width: 48, height: 48)
                                        .glassedEffect(in: Circle())
                                }
                            }
                            .padding(.bottom, 48)
                        }
                        .transition(.opacity)
                    }

                }
                .onAppear {
                    viewHeight = geometry.size.height
                    setupPiP()
                    Analytics.logEvent("teleprompter_started", parameters: [
                        "word_count": content.words.count,
                        "timer_duration": timerDuration
                    ])
                }
            }
            .navigationTitle("Teleprompter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(AppColors.background(for: colorScheme), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: {
                        AnalyticsEvents.logButtonClick("close", screen: "teleprompter")
                        stopAndDismiss()
                    }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(AppColors.textPrimary(for: colorScheme))
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Text(timeDisplay)
                        .font(.system(size: 16, weight: .bold, design: .monospaced))
                        .foregroundStyle(timerColor)
                }
            }
        }
        .persistentSystemOverlays(.hidden)
        .offset(x: dragOffset)
        .gesture(
            DragGesture()
                .onChanged { value in
                    // Only respond to swipes starting from left edge (first 40 points)
                    if value.startLocation.x < 40 && value.translation.width > 0 {
                        dragOffset = value.translation.width
                    }
                }
                .onEnded { value in
                    if value.startLocation.x < 40 && value.translation.width > 100 {
                        // Swipe was far enough, dismiss
                        stopAndDismiss()
                    } else {
                        // Reset position
                        withAnimation(.spring(response: 0.3)) {
                            dragOffset = 0
                        }
                    }
                }
        )
        .onDisappear {
            stopTimer()
            stopControlsTimer()
            stopCountdownTimer()
        }
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .background && !pipManager.isPiPActive && pipManager.isPiPPossible {
                // Auto-start PiP when app goes to background (like YouTube)
                startPiP(minimizeApp: false)
            } else if newPhase == .active && pipManager.isPiPActive {
                // Sync state when coming back to foreground
                elapsedTime = pipManager.elapsedTime
                isPlaying = pipManager.isPlaying
                updateCurrentWord()
            }
        }
    }

    // MARK: - PiP Setup

    private func setupPiP() {
        pipManager.configure(
            text: content.fullText,
            settings: settings,
            timerDuration: timerDuration,
            colorScheme: colorScheme
        )

        pipManager.onPiPClosed = {
            elapsedTime = pipManager.elapsedTime
            isPlaying = pipManager.isPlaying
            updateCurrentWord()
            if isPlaying {
                startTimer()
            }
        }

        pipManager.onPiPRestoreUI = {
            elapsedTime = pipManager.elapsedTime
            isPlaying = pipManager.isPlaying
            updateCurrentWord()
            if isPlaying {
                startTimer()
            }
        }

        // Handle play/pause from PiP controls
        pipManager.onPlayPauseFromPiP = { playing in
            if playing {
                isPlaying = true
                if !pipManager.isPiPActive {
                    startTimer()
                }
            } else {
                isPlaying = false
                stopTimer()
            }
        }

        // Handle restart from PiP controls
        pipManager.onRestartFromPiP = {
            stopTimer()
            stopCountdownTimer()
            isCountingDown = false
            elapsedTime = 0
            currentWordIndex = 0
            scrollOffset = 0
            isPlaying = false
        }

        // Handle expand from PiP - app will come to foreground automatically
        pipManager.onExpandFromPiP = {
            elapsedTime = pipManager.elapsedTime
            isPlaying = pipManager.isPlaying
            updateCurrentWord()
            if isPlaying {
                startTimer()
            }
        }
    }

    private func startPiP(minimizeApp: Bool = false) {
        pipManager.updateState(
            elapsedTime: elapsedTime,
            isPlaying: isPlaying,
            currentWordIndex: currentWordIndex,
            countdownValue: countdownValue,
            isCountingDown: isCountingDown
        )
        // Stop the view's timer — PiP manager has its own playback timer.
        // Running both causes dual writes to pipManager state and doubles CPU work.
        guard pipManager.startPiP(minimizeApp: minimizeApp) else { return }
        stopTimer()
        Analytics.logEvent("teleprompter_pip_started", parameters: nil)
    }

    private func togglePiP() {
        if pipManager.isPiPActive {
            pipManager.stopPiP()
            Analytics.logEvent("teleprompter_pip_stopped", parameters: nil)
        } else {
            // Start PiP and minimize the app
            startPiP(minimizeApp: true)
        }
    }

    // MARK: - Controls

    private func togglePlayPause() {
        if isPlaying || isCountingDown {
            pause()
        } else {
            startCountdownThenPlay()
        }
        resetControlsTimer()
    }

    private func startCountdownThenPlay() {
        // If countdown is 0, play immediately
        guard settings.countdownSeconds > 0 else {
            play()
            return
        }

        // Start countdown
        countdownValue = settings.countdownSeconds
        isCountingDown = true
        pipManager.updateState(elapsedTime: elapsedTime, isPlaying: isPlaying, currentWordIndex: currentWordIndex, countdownValue: countdownValue, isCountingDown: true)

        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            Task { @MainActor in
                withAnimation(.snappy) {
                    countdownValue -= 1
                }
                pipManager.updateState(elapsedTime: elapsedTime, isPlaying: isPlaying, currentWordIndex: currentWordIndex, countdownValue: countdownValue, isCountingDown: countdownValue > 0)

                if countdownValue <= 0 {
                    stopCountdownTimer()
                    isCountingDown = false
                    play()
                }
            }
        }
    }

    private func stopCountdownTimer() {
        countdownTimer?.invalidate()
        countdownTimer = nil
    }

    private func play() {
        isPlaying = true
        startTimer()
        pipManager.updateState(elapsedTime: elapsedTime, isPlaying: true, currentWordIndex: currentWordIndex)
        Analytics.logEvent("teleprompter_play", parameters: nil)
        resetControlsTimer()
    }

    private func pause() {
        // Cancel countdown if running
        if isCountingDown {
            stopCountdownTimer()
            isCountingDown = false
            pipManager.updateState(elapsedTime: elapsedTime, isPlaying: false, currentWordIndex: currentWordIndex, countdownValue: 0, isCountingDown: false)
            return
        }
        isPlaying = false
        stopTimer()
        pipManager.updateState(elapsedTime: elapsedTime, isPlaying: false, currentWordIndex: currentWordIndex)
        Analytics.logEvent("teleprompter_pause", parameters: nil)
    }

    private func restart() {
        stopTimer()
        stopCountdownTimer()
        isCountingDown = false
        elapsedTime = 0
        currentWordIndex = 0
        scrollOffset = 0
        isPlaying = false
        pipManager.updateState(elapsedTime: 0, isPlaying: false, currentWordIndex: 0)
        Analytics.logEvent("teleprompter_restart", parameters: nil)
    }

    private func seekForward() {
        // Seek forward 10 seconds worth of words
        guard !content.words.isEmpty else { return }
        let wordsPerSecond = Double(settings.wordsPerMinute) / 60.0
        let wordsToSkip = Int(10 * wordsPerSecond)
        currentWordIndex = min(currentWordIndex + wordsToSkip, content.words.count - 1)
        elapsedTime = Double(currentWordIndex) / wordsPerSecond
        // Reset wall-clock anchor so the timer continues from the new position
        if timerStartDate != nil {
            timerStartDate = Date()
            elapsedTimeAtTimerStart = elapsedTime
        }
        pipManager.updateState(elapsedTime: elapsedTime, isPlaying: isPlaying, currentWordIndex: currentWordIndex)
    }

    private func seekBackward() {
        // Seek backward 10 seconds worth of words
        guard !content.words.isEmpty else { return }
        let wordsPerSecond = Double(settings.wordsPerMinute) / 60.0
        let wordsToSkip = Int(10 * wordsPerSecond)
        currentWordIndex = max(currentWordIndex - wordsToSkip, 0)
        elapsedTime = Double(currentWordIndex) / wordsPerSecond
        // Reset wall-clock anchor so the timer continues from the new position
        if timerStartDate != nil {
            timerStartDate = Date()
            elapsedTimeAtTimerStart = elapsedTime
        }
        pipManager.updateState(elapsedTime: elapsedTime, isPlaying: isPlaying, currentWordIndex: currentWordIndex)
    }

    private func stopAndDismiss() {
        stopTimer()
        stopCountdownTimer()
        pipManager.cleanup()
        Analytics.logEvent("teleprompter_closed", parameters: [
            "elapsed_time": Int(elapsedTime)
        ])
        dismiss()
    }

    // MARK: - Timer

    private func startTimer() {
        // Prevent multiple timers from running simultaneously
        stopTimer()

        // Track wall-clock start time to avoid drift from accumulated intervals
        timerStartDate = Date()
        elapsedTimeAtTimerStart = elapsedTime

        let interval = 1.0 / 30.0

        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            Task { @MainActor in
                guard let startDate = timerStartDate else { return }
                elapsedTime = elapsedTimeAtTimerStart + Date().timeIntervalSince(startDate)
                updateCurrentWord()
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
        timerStartDate = nil  // Prevents stale Task blocks from writing elapsedTime
    }

    private func updateCurrentWord() {
        if !content.words.isEmpty {
            let wordsPerSecond = Double(settings.wordsPerMinute) / 60.0
            let newWordIndex = min(Int(elapsedTime * wordsPerSecond), content.words.count - 1)
            if newWordIndex != currentWordIndex && newWordIndex >= 0 {
                currentWordIndex = newWordIndex
            }
        }

        pipManager.updateState(elapsedTime: elapsedTime, isPlaying: isPlaying, currentWordIndex: currentWordIndex)
    }

    // MARK: - Controls Timer

    private func resetControlsTimer() {
        stopControlsTimer()
        if isPlaying {
            controlsTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { _ in
                Task { @MainActor in
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showControls = false
                    }
                }
            }
        }
    }

    private func stopControlsTimer() {
        controlsTimer?.invalidate()
        controlsTimer = nil
    }
}

/// UITextView wrapper for attributed text with word highlighting
struct AttributedTextView: UIViewRepresentable {
    let content: TeleprompterContent
    let fontSize: CGFloat
    let currentWordIndex: Int
    let highlightProgress: Double
    let colorScheme: ColorScheme
    let topPadding: CGFloat
    let bottomPadding: CGFloat
    let onTap: (() -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(onTap: onTap)
    }

    class Coordinator: NSObject {
        var lastContentId: String?
        var lastFontSize: CGFloat = 0
        var lastColorScheme: ColorScheme = .dark
        var lastProgressBucket: Double = -1
        var appliedProgress: Double = 0
        var wordRanges: [NSRange] = []
        var wordIsNote: [Bool] = []
        var lastScrolledWordIndex: Int = -1
        var lastScrollTarget: CGFloat = -1
        var lastBoundsHeight: CGFloat = 0
        var onTap: (() -> Void)?

        init(onTap: (() -> Void)?) {
            self.onTap = onTap
        }

        @objc func handleTap() {
            onTap?()
        }
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.isEditable = false
        textView.isSelectable = false
        textView.backgroundColor = .clear
        textView.showsVerticalScrollIndicator = false
        textView.alwaysBounceVertical = true
        textView.textContainerInset = UIEdgeInsets(top: topPadding, left: 24, bottom: bottomPadding, right: 24)
        textView.textContainer.lineFragmentPadding = 0

        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap))
        tapGesture.cancelsTouchesInView = false
        textView.addGestureRecognizer(tapGesture)
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        let coordinator = context.coordinator
        coordinator.onTap = onTap
        textView.textContainerInset = UIEdgeInsets(top: topPadding, left: 24, bottom: bottomPadding, right: 24)

        let contentId = content.fullText
        let needsFullRebuild = coordinator.lastContentId != contentId
            || coordinator.lastFontSize != fontSize
            || coordinator.lastColorScheme != colorScheme

        if needsFullRebuild {
            let built = buildAttributedString()
            textView.attributedText = built.text
            textView.layoutIfNeeded()
            textView.contentOffset = .zero

            coordinator.lastContentId = contentId
            coordinator.lastFontSize = fontSize
            coordinator.lastColorScheme = colorScheme
            coordinator.wordRanges = built.wordRanges
            coordinator.wordIsNote = built.wordIsNote
            coordinator.appliedProgress = highlightProgress
            coordinator.lastProgressBucket = (highlightProgress * 10).rounded(.down) / 10
            coordinator.lastScrolledWordIndex = -1
            coordinator.lastScrollTarget = -1
            coordinator.lastBoundsHeight = 0
        } else {
            // Only the few words inside the fade window change color, so recolor
            // those in place instead of rebuilding and re-laying out the document.
            let progressBucket = (highlightProgress * 10).rounded(.down) / 10
            if coordinator.lastProgressBucket != progressBucket {
                coordinator.lastProgressBucket = progressBucket
                applyHighlight(to: textView, coordinator: coordinator)
            }
        }

        // Auto-scroll to current word
        guard currentWordIndex < coordinator.wordRanges.count else { return }

        let boundsHeight = textView.bounds.height
        guard currentWordIndex != coordinator.lastScrolledWordIndex
            || boundsHeight != coordinator.lastBoundsHeight else { return }

        coordinator.lastScrolledWordIndex = currentWordIndex
        coordinator.lastBoundsHeight = boundsHeight

        var scrollY: CGFloat = 0
        if currentWordIndex > 0 {
            let range = coordinator.wordRanges[currentWordIndex]
            let glyphRange = textView.layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            let rect = textView.layoutManager.boundingRect(forGlyphRange: glyphRange, in: textView.textContainer)

            let targetY = rect.origin.y + topPadding - (boundsHeight / 3)
            let maxY = textView.contentSize.height - boundsHeight
            scrollY = max(0, min(targetY, maxY))
        }

        // Re-target only on a real move, so the eased scroll can finish instead of
        // being restarted and snapped on every frame.
        guard abs(scrollY - coordinator.lastScrollTarget) > 0.5 else { return }
        coordinator.lastScrollTarget = scrollY

        UIView.animate(withDuration: 0.3, delay: 0, options: [.curveEaseInOut, .allowUserInteraction, .beginFromCurrentState]) {
            textView.contentOffset = CGPoint(x: 0, y: scrollY)
        }
    }

    private func applyHighlight(to textView: UITextView, coordinator: Coordinator) {
        let wordCount = coordinator.wordRanges.count
        guard wordCount > 0 else { return }

        let previous = coordinator.appliedProgress
        let current = highlightProgress
        coordinator.appliedProgress = current

        // Words below the window are fully faded and words above it are fully lit,
        // so only the span the window swept over since the last pass can have changed.
        let limit = Double(wordCount)
        let lower = min(max(min(previous, current) - 1, -1), limit)
        let upper = min(max(max(previous, current) + Self.fadeRange + 1, -1), limit)
        let first = max(0, Int(lower.rounded(.down)))
        let last = min(wordCount - 1, Int(upper.rounded(.up)))
        guard first <= last else { return }

        let textColor = colorScheme == .dark ? AppColors.UIColors.Dark.textPrimary : AppColors.UIColors.Light.textPrimary
        let storage = textView.textStorage

        storage.beginEditing()
        for index in first...last where !coordinator.wordIsNote[index] {
            storage.addAttribute(
                .foregroundColor,
                value: textColor.withAlphaComponent(highlightAlpha(for: index)),
                range: coordinator.wordRanges[index]
            )
        }
        storage.endEditing()
    }

    private static let fadeRange = 2.0

    private func highlightAlpha(for index: Int) -> CGFloat {
        let distance = highlightProgress - Double(index)
        let t = min(max((distance + Self.fadeRange) / Self.fadeRange, 0.0), 1.0)
        let blend = t * t * (3.0 - 2.0 * t)
        return 0.3 + CGFloat(blend) * 0.7
    }

    private func buildAttributedString() -> (text: NSAttributedString, wordRanges: [NSRange], wordIsNote: [Bool]) {
        let result = NSMutableAttributedString()
        var wordRanges: [NSRange] = []
        var wordIsNote: [Bool] = []
        let paragraphs = content.fullText.components(separatedBy: "\n\n")

        let textColor = colorScheme == .dark ? AppColors.UIColors.Dark.textPrimary : AppColors.UIColors.Light.textPrimary
        let pinkColor = colorScheme == .dark ? AppColors.UIColors.Dark.pink : AppColors.UIColors.Light.pink
        let noteKern = fontSize * 0.05

        var globalWordIndex = 0

        for (paragraphIndex, paragraph) in paragraphs.enumerated() {
            if paragraphIndex > 0 {
                result.append(NSAttributedString(string: "\n"))
            }

            let lines = paragraph.components(separatedBy: "\n")

            for (lineIndex, line) in lines.enumerated() {
                if lineIndex > 0 {
                    result.append(NSAttributedString(string: "\n"))
                }

                if line.isEmpty { continue }

                let segments = splitLineIntoSegments(line)
                var lineWordIndex = 0

                for segment in segments {
                    switch segment {
                    case .note(let noteContent):
                        let noteAttrs: [NSAttributedString.Key: Any] = [
                            .font: UIFont.systemFont(ofSize: fontSize * 0.72, weight: .semibold),
                            .foregroundColor: pinkColor,
                            .kern: noteKern
                        ]
                        let noteWords = noteContent.split(separator: " ", omittingEmptySubsequences: true)
                        for word in noteWords {
                            if lineWordIndex > 0 {
                                result.append(NSAttributedString(string: " ", attributes: noteAttrs))
                            }
                            let location = result.length
                            result.append(NSAttributedString(string: String(word), attributes: noteAttrs))
                            wordRanges.append(NSRange(location: location, length: result.length - location))
                            wordIsNote.append(true)
                            globalWordIndex += 1
                            lineWordIndex += 1
                        }
                    case .text(let textContent):
                        let words = textContent.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
                        for word in words {
                            if lineWordIndex > 0 {
                                result.append(NSAttributedString(string: " ", attributes: [
                                    .font: UIFont.systemFont(ofSize: fontSize, weight: .medium),
                                    .foregroundColor: textColor
                                ]))
                            }

                            let alpha = highlightAlpha(for: globalWordIndex)
                            let color = textColor.withAlphaComponent(alpha)

                            let attrs: [NSAttributedString.Key: Any] = [
                                .font: UIFont.systemFont(ofSize: fontSize, weight: .medium),
                                .foregroundColor: color
                            ]
                            let location = result.length
                            result.append(NSAttributedString(string: word, attributes: attrs))
                            wordRanges.append(NSRange(location: location, length: result.length - location))
                            wordIsNote.append(false)

                            globalWordIndex += 1
                            lineWordIndex += 1
                        }
                    }
                }
            }
        }

        // Add paragraph style for line spacing
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = fontSize * 0.18
        paragraphStyle.paragraphSpacing = fontSize * 0.45
        result.addAttribute(.paragraphStyle, value: paragraphStyle, range: NSRange(location: 0, length: result.length))

        return (result, wordRanges, wordIsNote)
    }

    private enum LineSegment {
        case text(String)
        case note(String)
    }

    private func splitLineIntoSegments(_ line: String) -> [LineSegment] {
        let pattern = #"\[note\s+([^\]]+)\]"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return [.text(line)]
        }

        let nsLine = line as NSString
        let matches = regex.matches(in: line, range: NSRange(location: 0, length: nsLine.length))

        if matches.isEmpty {
            return [.text(line)]
        }

        var segments: [LineSegment] = []
        var lastEnd = line.startIndex

        for match in matches {
            guard let fullRange = Range(match.range, in: line),
                  let contentRange = Range(match.range(at: 1), in: line) else { continue }

            // Text before the note
            if lastEnd < fullRange.lowerBound {
                let before = String(line[lastEnd..<fullRange.lowerBound]).trimmingCharacters(in: .whitespaces)
                if !before.isEmpty {
                    segments.append(.text(before))
                }
            }

            segments.append(.note(String(line[contentRange])))
            lastEnd = fullRange.upperBound
        }

        // Text after the last note
        if lastEnd < line.endIndex {
            let after = String(line[lastEnd...]).trimmingCharacters(in: .whitespaces)
            if !after.isEmpty {
                segments.append(.text(after))
            }
        }

        return segments
    }
}

#Preview {
    TeleprompterView(
        content: TeleprompterParser.parseNotes(""),
        settings: .default
    )
}
