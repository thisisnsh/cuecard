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
    @State private var elapsedTime: Double = 0
    @State private var timer: Timer?
    @State private var timerStartDate: Date?
    @State private var elapsedTimeAtTimerStart: Double = 0
    /// How many lines the script wrapped into on this screen. Zero until it lays out.
    @State private var lineCount: Int = 0
    @State private var showControls = true
    @State private var controlsTimer: Timer?
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

    /// How far the script fades into the background at each end. The reading line
    /// sits clear of both.
    private static let topFade: CGFloat = 96
    private static let bottomFade: CGFloat = 140

    /// How long the whole script takes at the current speed: the time for the
    /// last line to reach the reading line. Zero until the script has laid out.
    private var scriptDuration: Double {
        duration(forLines: lineCount)
    }

    private func duration(forLines lines: Int) -> Double {
        guard lines > 1, settings.linesPerMinute > 0 else { return 0 }
        return Double(lines - 1) * 60.0 / Double(settings.linesPerMinute)
    }

    /// Where on screen the line being read sits, as a fraction of the view height.
    /// Just above centre: high enough to leave the next few lines in view, low
    /// enough to read as the middle of the screen rather than the top of it.
    ///
    /// It doubles as the script's top inset, so the first line starts on the
    /// reading line and a line's scroll target is its own position in the text.
    private static let readingLineFraction: CGFloat = 0.45

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ZStack {
                    // Background - matches device theme
                    AppColors.background(for: colorScheme)
                        .ignoresSafeArea()

                    // The script scrolls at the reader's own pace: so many rendered
                    // lines a minute, counted from the time on the clock.
                    AttributedTextView(
                        content: content,
                        cueColor: settings.cueColor,
                        fontSize: CGFloat(settings.fontSize),
                        linePosition: elapsedTime * Double(settings.linesPerMinute) / 60.0,
                        colorScheme: colorScheme,
                        topPadding: geometry.size.height * Self.readingLineFraction,
                        bottomPadding: geometry.size.height * (1 - Self.readingLineFraction),
                        onLineCountChange: { lines in
                            lineCount = lines
                            pipManager.scriptDuration = duration(forLines: lines)
                        },
                        onTap: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showControls.toggle()
                            }
                            resetControlsTimer()
                        }
                    )
                    // Lines arrive and leave through a fade rather than being cut
                    // off flat against the toolbar and the controls.
                    .scriptEdgeFade(for: colorScheme, top: Self.topFade, bottom: Self.bottomFade)

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
            }
        }
    }

    // MARK: - PiP Setup

    private func setupPiP() {
        // Remote kill switch. If the overlay starts misbehaving on some iOS build
        // this turns it off for everyone without waiting on a release — nothing
        // offers PiP, and the background auto-start stays quiet too.
        guard RemoteConfigService.shared.isPiPEnabled else {
            pipManager.disable()
            return
        }

        pipManager.configure(
            text: content.fullText,
            settings: settings,
            timerDuration: timerDuration,
            colorScheme: colorScheme
        )
        pipManager.scriptDuration = scriptDuration

        pipManager.onPiPClosed = {
            elapsedTime = pipManager.elapsedTime
            isPlaying = pipManager.isPlaying
            if isPlaying {
                startTimer()
            }
        }

        pipManager.onPiPRestoreUI = {
            elapsedTime = pipManager.elapsedTime
            isPlaying = pipManager.isPlaying
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
            isPlaying = false
        }

        // Handle expand from PiP - app will come to foreground automatically
        pipManager.onExpandFromPiP = {
            elapsedTime = pipManager.elapsedTime
            isPlaying = pipManager.isPlaying
            if isPlaying {
                startTimer()
            }
        }
    }

    private func startPiP(minimizeApp: Bool = false) {
        pipManager.scriptDuration = scriptDuration
        pipManager.updateState(
            elapsedTime: elapsedTime,
            isPlaying: isPlaying,
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
        pipManager.updateState(elapsedTime: elapsedTime, isPlaying: isPlaying, countdownValue: countdownValue, isCountingDown: true)

        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            Task { @MainActor in
                withAnimation(.snappy) {
                    countdownValue -= 1
                }
                pipManager.updateState(elapsedTime: elapsedTime, isPlaying: isPlaying, countdownValue: countdownValue, isCountingDown: countdownValue > 0)

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
        pipManager.updateState(elapsedTime: elapsedTime, isPlaying: true)
        Analytics.logEvent("teleprompter_play", parameters: nil)
        resetControlsTimer()
    }

    private func pause() {
        // Cancel countdown if running
        if isCountingDown {
            stopCountdownTimer()
            isCountingDown = false
            pipManager.updateState(elapsedTime: elapsedTime, isPlaying: false, countdownValue: 0, isCountingDown: false)
            return
        }
        isPlaying = false
        stopTimer()
        pipManager.updateState(elapsedTime: elapsedTime, isPlaying: false)
        Analytics.logEvent("teleprompter_pause", parameters: nil)
    }

    /// Back to the first line, which the script scrolls up to rather than snapping.
    private func restart() {
        stopTimer()
        stopCountdownTimer()
        isCountingDown = false
        elapsedTime = 0
        isPlaying = false
        pipManager.updateState(elapsedTime: 0, isPlaying: false)
        Analytics.logEvent("teleprompter_restart", parameters: nil)
    }

    private func seekForward() {
        seek(by: 10)
    }

    private func seekBackward() {
        seek(by: -10)
    }

    /// Move the script by a slice of time, which at the current speed is
    /// `linesPerMinute × seconds / 60` lines. The scroll animates across them.
    private func seek(by seconds: Double) {
        let end = scriptDuration > 0 ? scriptDuration : .greatestFiniteMagnitude
        let target = min(max(elapsedTime + seconds, 0), end)
        guard target != elapsedTime else { return }

        elapsedTime = target
        // Reset wall-clock anchor so the timer continues from the new position
        if timerStartDate != nil {
            timerStartDate = Date()
            elapsedTimeAtTimerStart = elapsedTime
        }
        pipManager.updateState(elapsedTime: elapsedTime, isPlaying: isPlaying)
    }

    private func stopAndDismiss() {
        stopTimer()
        stopCountdownTimer()
        pipManager.cleanup()
        Analytics.logEvent("teleprompter_closed", parameters: [
            "elapsed_time": Int(elapsedTime)
        ])
        ReviewPromptService.shared.recordCompletedSession()
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
                pipManager.updateState(elapsedTime: elapsedTime, isPlaying: isPlaying)
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
        timerStartDate = nil  // Prevents stale Task blocks from writing elapsedTime
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

/// UITextView wrapper that scrolls the script by rendered line
///
/// The script is one continuous block at one brightness — the position on the
/// screen is what says where the reader is, so nothing is highlighted.
struct AttributedTextView: UIViewRepresentable {
    let content: TeleprompterContent
    let cueColor: CueColor
    let fontSize: CGFloat
    /// How far into the script the reader is, in rendered lines. Fractional: the
    /// scroll interpolates between lines rather than stepping between them.
    let linePosition: Double
    let colorScheme: ColorScheme
    let topPadding: CGFloat
    let bottomPadding: CGFloat
    /// Reports how many lines the script laid out into, which is what turns the
    /// lines-per-minute setting into a duration.
    let onLineCountChange: (Int) -> Void
    let onTap: (() -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(onTap: onTap)
    }

    class Coordinator: NSObject {
        var lastContentId: String?
        var lastFontSize: CGFloat = 0
        var lastCueColor: CueColor?
        var lastColorScheme: ColorScheme = .dark
        /// The scroll offset that puts each rendered line on the reading line.
        var lineOffsets: [CGFloat] = []
        var lastLayoutSize: CGSize = .zero
        var lastReportedLineCount = -1
        var lastTarget: CGFloat = -1
        var onTap: (() -> Void)?

        /// The scroll eases toward the target on its own display link rather than
        /// being written straight to the text view. Playback moves the target in
        /// small steps and the easing is invisible; a seek or a restart moves it a
        /// long way and the same easing carries the script there smoothly.
        private static let timeConstant: Double = 0.12
        private weak var textView: UITextView?
        private var displayLink: CADisplayLink?
        private var lastTimestamp: CFTimeInterval = 0

        init(onTap: (() -> Void)?) {
            self.onTap = onTap
        }

        @objc func handleTap() {
            onTap?()
        }

        /// Place the script without easing, for the first layout and after a rebuild.
        func settle(at offset: CGFloat, in textView: UITextView) {
            stopEasing()
            lastTarget = offset
            self.textView = textView
            textView.contentOffset = CGPoint(x: 0, y: offset)
        }

        func ease(to offset: CGFloat, in textView: UITextView) {
            lastTarget = offset
            self.textView = textView

            guard displayLink == nil else { return }
            lastTimestamp = 0
            let link = CADisplayLink(target: self, selector: #selector(step))
            link.add(to: .main, forMode: .common)
            displayLink = link
        }

        func stopEasing() {
            displayLink?.invalidate()
            displayLink = nil
        }

        @objc private func step(_ link: CADisplayLink) {
            guard let textView else {
                stopEasing()
                return
            }

            let elapsed = lastTimestamp == 0 ? link.duration : link.timestamp - lastTimestamp
            lastTimestamp = link.timestamp

            let distance = lastTarget - textView.contentOffset.y
            guard abs(distance) > 0.05 else {
                textView.contentOffset = CGPoint(x: 0, y: lastTarget)
                stopEasing()
                return
            }

            let advance = distance * (1 - exp(-elapsed / Self.timeConstant))
            textView.contentOffset = CGPoint(x: 0, y: textView.contentOffset.y + advance)
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

    static func dismantleUIView(_ uiView: UITextView, coordinator: Coordinator) {
        coordinator.stopEasing()
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        let coordinator = context.coordinator
        coordinator.onTap = onTap
        textView.textContainerInset = UIEdgeInsets(top: topPadding, left: 24, bottom: bottomPadding, right: 24)

        let contentId = content.fullText
        let needsFullRebuild = coordinator.lastContentId != contentId
            || coordinator.lastFontSize != fontSize
            || coordinator.lastCueColor != cueColor
            || coordinator.lastColorScheme != colorScheme

        if needsFullRebuild {
            textView.attributedText = buildAttributedString()
            textView.layoutIfNeeded()

            coordinator.lastContentId = contentId
            coordinator.lastFontSize = fontSize
            coordinator.lastCueColor = cueColor
            coordinator.lastColorScheme = colorScheme
            coordinator.lineOffsets = []
            coordinator.lastLayoutSize = .zero
        }

        // The line the reader is on sits on the reading line, and the text is inset
        // from the top by exactly that distance — so a line's target offset is just
        // its own position within the laid-out text.
        let layoutSize = textView.bounds.size
        let isFirstLayout = coordinator.lineOffsets.isEmpty
        if isFirstLayout || coordinator.lastLayoutSize != layoutSize {
            coordinator.lastLayoutSize = layoutSize
            coordinator.lineOffsets = lineOffsets(for: textView)

            let lineCount = coordinator.lineOffsets.count
            if lineCount != coordinator.lastReportedLineCount {
                coordinator.lastReportedLineCount = lineCount
                // Out of the layout pass this call is inside.
                DispatchQueue.main.async {
                    onLineCountChange(lineCount)
                }
            }
        }

        let offsets = coordinator.lineOffsets
        guard offsets.count > 1 else { return }

        let position = min(max(linePosition, 0), Double(offsets.count - 1))
        let line = min(Int(position), offsets.count - 2)
        let fraction = CGFloat(position - Double(line))
        let target = offsets[line] + (offsets[line + 1] - offsets[line]) * fraction

        let maxY = max(0, textView.contentSize.height - textView.bounds.height)
        let scrollY = min(max(target, 0), maxY)

        if isFirstLayout || needsFullRebuild {
            coordinator.settle(at: scrollY, in: textView)
            return
        }

        // Only move when the target itself moved, so a script the reader has
        // dragged by hand while paused stays where they put it.
        guard abs(scrollY - coordinator.lastTarget) > 0.05 else { return }
        coordinator.ease(to: scrollY, in: textView)
    }

    /// The scroll offset that puts each rendered line on the reading line, one
    /// entry per line the script actually wraps into on this screen.
    private func lineOffsets(for textView: UITextView) -> [CGFloat] {
        let layoutManager = textView.layoutManager
        let container = textView.textContainer
        layoutManager.ensureLayout(for: container)

        // Line fragments are measured inside the text container, which is already
        // the offset that line should be scrolled to.
        var offsets: [CGFloat] = []
        let glyphRange = layoutManager.glyphRange(for: container)
        var glyphIndex = glyphRange.location

        while glyphIndex < NSMaxRange(glyphRange) {
            var lineRange = NSRange(location: 0, length: 0)
            let fragment = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: &lineRange)
            offsets.append(fragment.origin.y)

            guard lineRange.length > 0 else { break }
            glyphIndex = NSMaxRange(lineRange)
        }

        return offsets
    }

    private func buildAttributedString() -> NSAttributedString {
        let result = NSMutableAttributedString()
        let paragraphs = content.fullText.components(separatedBy: "\n\n")

        let textColor = colorScheme == .dark ? AppColors.UIColors.Dark.textPrimary : AppColors.UIColors.Light.textPrimary
        let textAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: fontSize, weight: .medium),
            .foregroundColor: textColor
        ]
        let cueAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: fontSize * 0.72, weight: .semibold),
            .foregroundColor: cueColor.uiColor(isDarkMode: colorScheme == .dark),
            .kern: fontSize * 0.05
        ]

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

                for (segmentIndex, segment) in TeleprompterParser.segments(in: line).enumerated() {
                    if segmentIndex > 0 {
                        result.append(NSAttributedString(string: " ", attributes: textAttrs))
                    }

                    switch segment {
                    case .cue(let cueText):
                        result.append(NSAttributedString(string: cueText, attributes: cueAttrs))
                    case .text(let text):
                        result.append(NSAttributedString(string: text, attributes: textAttrs))
                    }
                }
            }
        }

        // Add paragraph style for line spacing
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = fontSize * 0.18
        paragraphStyle.paragraphSpacing = fontSize * 0.45
        result.addAttribute(.paragraphStyle, value: paragraphStyle, range: NSRange(location: 0, length: result.length))

        return result
    }
}

#Preview {
    TeleprompterView(
        content: TeleprompterParser.parseNotes(""),
        settings: .default
    )
}
