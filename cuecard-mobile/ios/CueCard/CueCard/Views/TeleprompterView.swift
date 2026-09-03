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
    /// The clock. It counts the time spent speaking and nothing else: it starts,
    /// it pauses, it goes back to zero on a restart. Moving through the script —
    /// by dragging it, or by a cue holding it — leaves it alone.
    @State private var elapsedTime: Double = 0
    @State private var timer: Timer?
    @State private var timerStartDate: Date?
    @State private var elapsedTimeAtTimerStart: Double = 0
    /// Where the script was last placed by hand, which is what the clock reading
    /// is measured out from to say which line the reader is on.
    @State private var playback = ScriptPlayback()
    /// How the script wrapped on this screen, and which of those lines the pauses
    /// landed on. Empty until it lays out.
    @State private var geometry = ScriptGeometry()
    @State private var showControls = true
    @State private var controlsTimer: Timer?
    @State private var countdownValue: Int = 0
    @State private var isCountingDown = false
    @State private var countdownTimer: Timer?
    /// Whether playback has begun since the last restart. The countdown only
    /// runs on the first play; resuming from a pause starts right away.
    @State private var hasStarted = false
    /// Bumped whenever the reader's position comes back from the overlay rather
    /// than from this view's own clock. The script jumps straight to it instead
    /// of easing, so the app is already where the overlay was when it expands.
    @State private var scriptSnapToken = 0
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

    /// The line the reader is on, and whether a pause is holding them there.
    private var position: ScriptPosition {
        playback.position(
            at: elapsedTime,
            linesPerMinute: Double(settings.linesPerMinute),
            pauses: geometry.pauses,
            lineCount: geometry.lineCount
        )
    }

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                ZStack {
                    // Background - matches device theme
                    AppColors.background(for: colorScheme)
                        .ignoresSafeArea()

                    // The script scrolls at the reader's own pace: so many rendered
                    // lines a minute, counted from the time on the clock — except
                    // where a cue holds it still.
                    AttributedTextView(
                        content: content,
                        cueColor: settings.cueColor,
                        fontSize: CGFloat(settings.fontSize),
                        linePosition: position.line,
                        pauseStates: geometry.pauseStates(at: position),
                        colorScheme: colorScheme,
                        topPadding: proxy.size.height * TeleprompterLayout.readingLineFraction,
                        bottomPadding: proxy.size.height * (1 - TeleprompterLayout.readingLineFraction),
                        snapToken: scriptSnapToken,
                        onGeometryChange: { measured in
                            geometry = measured
                            pipManager.geometry = measured
                        },
                        onScrub: { line in
                            scrub(toLine: line)
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
                syncFromPiP()
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
        pipManager.geometry = geometry

        pipManager.onPiPClosed = {
            syncFromPiP()
            if isPlaying {
                startTimer()
            }
        }

        pipManager.onPiPRestoreUI = {
            syncFromPiP()
            if isPlaying {
                startTimer()
            }
        }

        // Handle play/pause from PiP controls
        pipManager.onPlayPauseFromPiP = { playing in
            if playing {
                isPlaying = true
                hasStarted = true
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
            playback = ScriptPlayback()
            isPlaying = false
            hasStarted = false
        }

        // Handle expand from PiP - app will come to foreground automatically
        pipManager.onExpandFromPiP = {
            syncFromPiP()
            if isPlaying {
                startTimer()
            }
        }
    }

    /// Take the reader's position back from the overlay. The script snaps to it
    /// rather than scrolling there, so the two are already on the same line when
    /// the overlay expands back into the app.
    private func syncFromPiP() {
        elapsedTime = pipManager.elapsedTime
        playback = pipManager.playback
        isPlaying = pipManager.isPlaying
        scriptSnapToken += 1
    }

    private func startPiP(minimizeApp: Bool = false) {
        pipManager.geometry = geometry
        pipManager.updateState(
            elapsedTime: elapsedTime,
            isPlaying: isPlaying,
            playback: playback,
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
        // Only count down from the top of the script — a resume plays immediately
        guard settings.countdownSeconds > 0, !hasStarted else {
            play()
            return
        }

        // Start countdown
        countdownValue = settings.countdownSeconds
        isCountingDown = true
        pipManager.updateState(elapsedTime: elapsedTime, isPlaying: isPlaying, playback: playback, countdownValue: countdownValue, isCountingDown: true)

        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            Task { @MainActor in
                withAnimation(.snappy) {
                    countdownValue -= 1
                }
                pipManager.updateState(elapsedTime: elapsedTime, isPlaying: isPlaying, playback: playback, countdownValue: countdownValue, isCountingDown: countdownValue > 0)

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
        hasStarted = true
        startTimer()
        pipManager.updateState(elapsedTime: elapsedTime, isPlaying: true, playback: playback)
        Analytics.logEvent("teleprompter_play", parameters: nil)
        resetControlsTimer()
    }

    private func pause() {
        // Cancel countdown if running
        if isCountingDown {
            stopCountdownTimer()
            isCountingDown = false
            pipManager.updateState(elapsedTime: elapsedTime, isPlaying: false, playback: playback, countdownValue: 0, isCountingDown: false)
            return
        }
        isPlaying = false
        stopTimer()
        pipManager.updateState(elapsedTime: elapsedTime, isPlaying: false, playback: playback)
        Analytics.logEvent("teleprompter_pause", parameters: nil)
    }

    /// Back to the first line, which the script scrolls up to rather than snapping.
    /// The one thing that puts the clock back to zero.
    private func restart() {
        stopTimer()
        stopCountdownTimer()
        isCountingDown = false
        elapsedTime = 0
        playback = ScriptPlayback()
        isPlaying = false
        hasStarted = false
        pipManager.updateState(elapsedTime: 0, isPlaying: false, playback: playback)
        Analytics.logEvent("teleprompter_restart", parameters: nil)
    }

    /// Pick up from wherever the reader dragged the script to. The line they left
    /// on the reading line is where playback carries on from — and the clock,
    /// which counts how long they have been speaking rather than how far down the
    /// page they are, doesn't move for it.
    private func scrub(toLine line: Double) {
        playback.place(atLine: line, time: elapsedTime, lineCount: geometry.lineCount)
        pipManager.updateState(elapsedTime: elapsedTime, isPlaying: isPlaying, playback: playback)
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
                pipManager.updateState(elapsedTime: elapsedTime, isPlaying: isPlaying, playback: playback)
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
    /// What each pause in the script reads right now — counting down while it
    /// holds the reader, expired once they are past it.
    let pauseStates: [PauseState]
    let colorScheme: ColorScheme
    let topPadding: CGFloat
    let bottomPadding: CGFloat
    /// Changes when the position was set from outside this view's own clock —
    /// coming back from the overlay. The script settles at the new position
    /// instead of easing there.
    let snapToken: Int
    /// Reports how the script wrapped on this screen — which the overlay reads its
    /// own place from, and which is what puts every holding cue on a line.
    let onGeometryChange: (ScriptGeometry) -> Void
    /// Reports where the reader dragged the script to, in rendered lines, so
    /// playback can carry on from there.
    let onScrub: (Double) -> Void
    let onTap: (() -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(onTap: onTap, onScrub: onScrub)
    }

    class Coordinator: NSObject, UITextViewDelegate {
        var lastContentId: String?
        var lastFontSize: CGFloat = 0
        var lastCueColor: CueColor?
        var lastColorScheme: ColorScheme = .dark
        /// The script as it is laid out on this screen.
        var layout = ScriptLayout()
        /// Where each pause's label sits in the drawn script, from the last build.
        var pauses: [PauseMark] = []
        var lastLayoutSize: CGSize = .zero
        var lastReportedGeometry: ScriptGeometry?
        var lastTarget: CGFloat = -1
        var lastSnapToken = 0
        /// True from the moment a drag starts until the script comes to rest, so
        /// playback leaves the scroll alone while the reader has hold of it.
        var isUserScrolling = false
        var onTap: (() -> Void)?
        var onScrub: ((Double) -> Void)?

        /// The scroll eases toward the target on its own display link rather than
        /// being written straight to the text view. Playback moves the target in
        /// small steps and the easing is invisible; a seek or a restart moves it a
        /// long way and the same easing carries the script there smoothly.
        private static let timeConstant: Double = 0.12
        private weak var textView: UITextView?
        private var displayLink: CADisplayLink?
        private var lastTimestamp: CFTimeInterval = 0

        init(onTap: (() -> Void)?, onScrub: ((Double) -> Void)?) {
            self.onTap = onTap
            self.onScrub = onScrub
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

        // MARK: Dragging

        func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
            isUserScrolling = true
            stopEasing()
        }

        func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
            guard !decelerate else { return }
            handOffScroll(scrollView)
        }

        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
            handOffScroll(scrollView)
        }

        /// Hand the resting position back as a line number and take it as the new
        /// target, so the next update has nothing to correct.
        private func handOffScroll(_ scrollView: UIScrollView) {
            guard isUserScrolling else { return }
            isUserScrolling = false

            let offset = scrollView.contentOffset.y
            lastTarget = offset
            onScrub?(layout.line(forOffset: offset))
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
        textView.delegate = context.coordinator
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
        coordinator.onScrub = onScrub
        textView.textContainerInset = UIEdgeInsets(top: topPadding, left: 24, bottom: bottomPadding, right: 24)

        let needsSnap = coordinator.lastSnapToken != snapToken
        coordinator.lastSnapToken = snapToken

        let contentId = content.fullText
        let needsFullRebuild = coordinator.lastContentId != contentId
            || coordinator.lastFontSize != fontSize
            || coordinator.lastCueColor != cueColor
            || coordinator.lastColorScheme != colorScheme

        if needsFullRebuild {
            let rendered = TeleprompterScript.render(
                text: content.fullText,
                fontSize: fontSize,
                cueColor: cueColor,
                isDarkMode: colorScheme == .dark
            )
            textView.attributedText = rendered.attributed
            textView.layoutIfNeeded()

            coordinator.lastContentId = contentId
            coordinator.lastFontSize = fontSize
            coordinator.lastCueColor = cueColor
            coordinator.lastColorScheme = colorScheme
            coordinator.pauses = rendered.pauses
            coordinator.layout = ScriptLayout()
            coordinator.lastLayoutSize = .zero
        }

        // Every label is written to the same width, so a pause counting down leaves
        // every line where it was — but it still goes in before anything measures.
        TeleprompterScript.applyPauseLabels(pauseStates, to: textView.textStorage, pauses: coordinator.pauses)

        // The line the reader is on sits on the reading line, and the text is inset
        // from the top by exactly that distance — so a line's target offset is just
        // its own position within the laid-out text. `.zero` means nothing has been
        // measured yet: the size the coordinator starts on, and the one a rebuild
        // puts it back to.
        let layoutSize = textView.bounds.size
        let isFirstLayout = coordinator.lastLayoutSize == .zero
        if isFirstLayout || coordinator.lastLayoutSize != layoutSize {
            coordinator.lastLayoutSize = layoutSize
            coordinator.layout = ScriptLayout.measure(textView)

            let geometry = ScriptGeometry.from(layout: coordinator.layout, pauses: coordinator.pauses)
            if geometry != coordinator.lastReportedGeometry {
                coordinator.lastReportedGeometry = geometry
                // Out of the layout pass this call is inside.
                DispatchQueue.main.async {
                    onGeometryChange(geometry)
                }
            }
        }

        guard !coordinator.layout.isEmpty else { return }
        let target = coordinator.layout.offset(forLine: linePosition)

        let maxY = max(0, textView.contentSize.height - textView.bounds.height)
        let scrollY = min(max(target, 0), maxY)

        if isFirstLayout || needsFullRebuild || needsSnap {
            coordinator.settle(at: scrollY, in: textView)
            return
        }

        // A drag in progress owns the scroll; playback picks up from wherever it
        // is let go of.
        guard !coordinator.isUserScrolling else { return }

        // Only move when the target itself moved, so a script the reader has
        // dragged by hand while paused stays where they put it.
        guard abs(scrollY - coordinator.lastTarget) > 0.05 else { return }
        coordinator.ease(to: scrollY, in: textView)
    }
}

#Preview {
    TeleprompterView(
        content: TeleprompterParser.parseNotes(""),
        settings: .default
    )
}
