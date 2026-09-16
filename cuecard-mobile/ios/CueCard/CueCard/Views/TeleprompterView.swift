import SwiftUI
import UIKit
import FirebaseAnalytics
import FirebaseCrashlytics

struct TeleprompterView: View {
    let content: TeleprompterContent

    @EnvironmentObject var settingsService: SettingsService
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    @StateObject private var pipManager = TeleprompterPiPManager.shared

    private var isPlaying: Bool { pipManager.playback.isPlaying }
    private var elapsedTime: Double { pipManager.playback.elapsedTime }
    private var scriptTime: Double { pipManager.playback.scriptTime }
    private var isCountingDown: Bool { pipManager.playback.isCountingDown }
    private var countdownValue: Int { pipManager.playback.countdownValue }
    /// During the countdown the play button shows the seconds left, in the cue
    /// color, and switches to the pause icon once playback starts. It still
    /// pauses while showing a number.
    private var showsCountdownNumber: Bool { isCountingDown }
    @State private var referenceLineStarts: [Int] = []
    @State private var hasConfiguredSession = false
    @State private var showControls = true
    @State private var controlsTimer: Timer?
    @State private var showingSettings = false
    @Environment(\.scenePhase) private var scenePhase

    /// Settings are read live, so a size or speed changed mid-run shows at once.
    private var settings: TeleprompterSettings { settingsService.settings }

    /// Playing or counting down to it. Settings is only offered while neither.
    private var isRunning: Bool { isPlaying || isCountingDown }

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
                        linePosition: scriptTime * Double(settings.linesPerMinute) / 60.0,
                        colorScheme: colorScheme,
                        topPadding: geometry.size.height * Self.readingLineFraction,
                        bottomPadding: geometry.size.height * (1 - Self.readingLineFraction),
                        snapToken: pipManager.playback.snapToken,
                        restorationRequest: pipManager.restorationRequest,
                        onRestorationReady: { request in
                            pipManager.completeRestoration(request)
                        },
                        onLayoutChange: { starts in
                            referenceLineStarts = starts
                            pipManager.updateReferenceLayout(starts)
                        },
                        onHandOff: { line in
                            handOff(toLine: line)
                        },
                        onTap: {
                            withAnimation(controlsFade) {
                                showControls.toggle()
                            }
                            resetControlsTimer()
                        }
                    )
                    // Lines arrive and leave through a fade rather than being cut
                    // off flat against the toolbar and the controls.
                    .scriptEdgeFade(for: colorScheme, top: Self.topFade, bottom: Self.bottomFade)

                    // Controls overlay. Always laid out and faded rather than
                    // added and removed, so the glass fades with the icons
                    // instead of popping in.
                    VStack {
                        Spacer()

                        HStack(spacing: 24) {
                            // PiP toggle button. Kept in the stack even when
                            // PiP is unavailable — taking it out shifts the
                            // play button off centre — and only made invisible.
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
                            .opacity(pipManager.isPiPPossible ? 1 : 0)
                            .disabled(!pipManager.isPiPPossible)
                            .accessibilityHidden(!pipManager.isPiPPossible)

                            // Play/Pause button
                            Button(action: {
                                AnalyticsEvents.logButtonClick((isPlaying || isCountingDown) ? "pause" : "play", screen: "teleprompter")
                                togglePlayPause()
                            }) {
                                ZStack {
                                    if showsCountdownNumber {
                                        Text("\(countdownValue)")
                                            .font(.system(size: 30, weight: .bold, design: .rounded))
                                            .monospacedDigit()
                                            .transition(.opacity)
                                    } else {
                                        Image(systemName: (isPlaying || isCountingDown) ? "pause.fill" : "play.fill")
                                            .font(.system(size: 28, weight: .semibold))
                                            .transition(.opacity)
                                    }
                                }
                                .foregroundStyle(colorScheme == .dark ? .black : .white)
                                .frame(width: 72, height: 72)
                                .background(
                                    Circle()
                                        .fill(showsCountdownNumber
                                              ? settings.cueColor.color(for: colorScheme)
                                              : AppColors.green(for: colorScheme))
                                )
                                .glassedEffect(in: Circle())
                                .animation(.easeInOut(duration: 0.12), value: showsCountdownNumber)
                            }
                            .accessibilityLabel(isCountingDown
                                                ? "Pause, starting in \(countdownValue)"
                                                : (isPlaying ? "Pause" : "Play"))

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
                    .fadedOut(!showControls)
                }
                .onAppear {
                    setupPiP()
                    // A read is a stretch of looking without touching, which is
                    // exactly what the idle timer takes for absence. Hold the
                    // screen for as long as the prompter is up.
                    UIApplication.shared.isIdleTimerDisabled = true
                    Analytics.logEvent("teleprompter_started", parameters: [
                        "word_count": content.words.count,
                        "timer_duration": timerDuration
                    ])
                }
            }
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
                    .accessibilityLabel("Close")
                    // Comes and goes with the play, restart and floating window buttons.
                    .fadedOut(!showControls)
                }
                ToolbarItem(placement: .principal) {
                    Text(timeDisplay)
                        .font(.system(size: 16, weight: .bold, design: .monospaced))
                        .foregroundStyle(timerColor)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: {
                        AnalyticsEvents.logButtonClick("settings", screen: "teleprompter")
                        showingSettings = true
                    }) {
                        Image(systemName: "gearshape")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(AppColors.textPrimary(for: colorScheme))
                    }
                    .accessibilityLabel("Settings")
                    // Only offered while paused, even when a tap has brought
                    // the other controls back mid-run.
                    .fadedOut(isRunning)
                }
            }
            .numberPadDoneButton()
        }
        .sheet(isPresented: $showingSettings) {
            TeleprompterSettingsView()
        }
        .persistentSystemOverlays(.hidden)
        .onDisappear {
            stopControlsTimer()
            UIApplication.shared.isIdleTimerDisabled = false
        }
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .background && !pipManager.isPiPActive && pipManager.isPiPPossible {
                // Auto-start PiP when app goes to background (like YouTube)
                startPiP(minimizeApp: false)
            } else if newPhase == .active {
                // Catch an appearance change made while the app was away.
                pipManager.update(settings: settings, colorScheme: colorScheme)
                pipManager.refreshPresentation()
            }
        }
        .onChange(of: settingsService.settings) { newSettings in
            pipManager.update(settings: newSettings, colorScheme: colorScheme)
        }
        .onChange(of: colorScheme) { newScheme in
            // Going to the background, the system snapshots the app in the other
            // appearance as well, and the environment flips there and back. The
            // floating window keeps the appearance the reader last saw on screen.
            guard scenePhase == .active else { return }
            pipManager.update(settings: settings, colorScheme: newScheme)
        }
        .onChange(of: isPlaying) { playing in
            if playing { resetControlsTimer() } else { stopControlsTimer() }
        }
    }

    // MARK: - Shared Playback Session

    private func setupPiP() {
        guard !hasConfiguredSession else { return }
        hasConfiguredSession = true
        pipManager.configure(
            text: content.fullText,
            settings: settings,
            timerDuration: timerDuration,
            colorScheme: colorScheme
        )
        pipManager.updateReferenceLayout(referenceLineStarts)
    }

    private func startPiP(minimizeApp: Bool = false) {
        if pipManager.startPiP(minimizeApp: minimizeApp) {
            Analytics.logEvent("teleprompter_pip_started", parameters: nil)
        }
    }

    private func togglePiP() {
        if pipManager.isPiPActive {
            pipManager.stopPiP()
            Analytics.logEvent("teleprompter_pip_stopped", parameters: nil)
        } else {
            startPiP(minimizeApp: true)
        }
    }

    private func togglePlayPause() {
        let wasRunning = isPlaying || isCountingDown
        pipManager.togglePlayPause()
        Analytics.logEvent(wasRunning ? "teleprompter_pause" : "teleprompter_play", parameters: nil)
        resetControlsTimer()
    }

    private func restart() {
        pipManager.restart()
        Analytics.logEvent("teleprompter_restart", parameters: nil)
    }

    private func handOff(toLine line: Double) {
        pipManager.seek(toLine: line)
    }

    private func stopAndDismiss() {
        pipManager.cleanup()
        Analytics.logEvent("teleprompter_closed", parameters: ["elapsed_time": Int(elapsedTime)])
        ReviewPromptService.shared.recordCompletedSession()
        dismiss()
    }

    // MARK: - Controls Timer

    private func resetControlsTimer() {
        stopControlsTimer()
        if isPlaying {
            controlsTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { _ in
                Task { @MainActor in
                    withAnimation(controlsFade) {
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

/// How the teleprompter's buttons, top and bottom, fade out and back in.
private let controlsFade = Animation.easeInOut(duration: 0.3)

private extension View {
    /// Fade controls out and back in, and take them out of reach of taps and
    /// VoiceOver while they're gone.
    func fadedOut(_ isHidden: Bool) -> some View {
        opacity(isHidden ? 0 : 1)
            .allowsHitTesting(!isHidden)
            .accessibilityHidden(isHidden)
            .animation(controlsFade, value: isHidden)
    }
}

/// Reveal the PiP landing surface before AVKit returns the video, then fade it
/// away over the already-positioned reader once the system transition finishes.
final class TeleprompterReaderHostView: UIView {
    let textView = UITextView(usingTextLayoutManager: false)
    var onLayoutChange: (() -> Void)?
    private weak var videoSource: UIView?
    private var lastLayoutSize: CGSize = .zero
    private var restorationAnimation: UUID?

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        textView.frame = bounds
        textView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(textView)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.size != lastLayoutSize else { return }
        lastLayoutSize = bounds.size
        onLayoutChange?()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil { onLayoutChange?() }
    }

    func installVideoSource(_ source: UIView) {
        guard videoSource !== source else { return }
        videoSource?.removeFromSuperview()
        source.removeFromSuperview()
        source.frame = bounds
        source.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        source.isUserInteractionEnabled = false
        insertSubview(source, belowSubview: textView)
        videoSource = source
    }

    func prepareVideoRestoration() -> Bool {
        guard window != nil, let videoSource else { return false }
        cancelVideoRestoration()
        bringSubviewToFront(videoSource)
        return true
    }

    func finishVideoRestoration(completion: @escaping () -> Void) {
        guard window != nil, let videoSource else {
            cancelVideoRestoration()
            completion()
            return
        }
        let animation = UUID()
        restorationAnimation = animation
        UIView.animate(withDuration: UIAccessibility.isReduceMotionEnabled ? 0 : 0.25,
                       delay: 0, options: [.beginFromCurrentState, .curveEaseInOut, .allowUserInteraction]) {
            videoSource.alpha = 0
        } completion: { [weak self] _ in
            guard let self, self.restorationAnimation == animation else { return }
            self.cancelVideoRestoration()
            completion()
        }
    }

    func cancelVideoRestoration() {
        restorationAnimation = nil
        guard let videoSource else { return }
        videoSource.layer.removeAllAnimations()
        // Keep the source opaque and attached for the next automatic PiP start.
        insertSubview(videoSource, belowSubview: textView)
        videoSource.alpha = 1
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
    /// Changes when the position was set from outside this view's own clock —
    /// coming back from the overlay. The script settles at the new position
    /// instead of easing there.
    let snapToken: Int
    let restorationRequest: UUID?
    let onRestorationReady: (UUID) -> Void
    /// UTF-16 starts of the full-screen lines define scroll speed and let PiP
    /// find the same text despite using a different font and line wrapping.
    let onLayoutChange: ([Int]) -> Void
    /// Reports the line the reader left on the reading line, so playback can carry
    /// on from there.
    let onHandOff: (Double) -> Void
    let onTap: (() -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(onTap: onTap, onHandOff: onHandOff)
    }

    @MainActor
    class Coordinator: NSObject, UITextViewDelegate {
        var updateReader: (() -> Void)?
        private var pendingUpdate: DispatchWorkItem?
        var lastContentId: String?
        var lastFontSize: CGFloat = 0
        var lastCueColor: CueColor?
        var lastColorScheme: ColorScheme = .dark
        /// The scroll offset that puts each rendered line on the reading line.
        var lineOffsets: [CGFloat] = []
        var lastLayoutSize: CGSize = .zero
        var lastReportedLineStarts: [Int] = []
        var lastTarget: CGFloat = -1
        var lastSnapToken = 0
        var lastRestorationRequest: UUID?
        /// True from the moment a drag starts until the script comes to rest, so
        /// playback leaves the scroll alone while the reader has hold of it.
        var isUserScrolling = false
        var isScrollSuspended = false
        var onTap: (() -> Void)?
        var onHandOff: ((Double) -> Void)?

        /// The scroll eases toward the target on its own display link rather than
        /// being written straight to the text view. Playback moves the target in
        /// small steps and the easing is invisible; a restart or a drag moves it a
        /// long way and the same easing carries the script there smoothly.
        private static let timeConstant: Double = 0.12
        private weak var textView: UITextView?
        private var displayLink: CADisplayLink?
        private var lastTimestamp: CFTimeInterval = 0

        init(onTap: (() -> Void)?, onHandOff: ((Double) -> Void)?) {
            self.onTap = onTap
            self.onHandOff = onHandOff
        }

        /// UIKit layout and AVKit setup can invalidate SwiftUI's layout graph.
        /// Coalesce updates and run them after its current update/layout pass.
        func scheduleUpdate() {
            guard pendingUpdate == nil else { return }
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.pendingUpdate = nil
                self.updateReader?()
            }
            pendingUpdate = work
            DispatchQueue.main.async(execute: work)
        }

        func cancelUpdates() {
            pendingUpdate?.cancel()
            pendingUpdate = nil
            updateReader = nil
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
        /// target, so the next update has nothing to correct. Only the script's own
        /// position is handed over — the timer is untouched, so going back for a
        /// line costs nothing on it.
        private func handOffScroll(_ scrollView: UIScrollView) {
            guard isUserScrolling else { return }
            isUserScrolling = false

            let offset = scrollView.contentOffset.y
            lastTarget = offset
            onHandOff?(linePosition(forOffset: offset))
        }

        /// The inverse of the line-to-offset map: which line, fractionally, sits on
        /// the reading line at this scroll offset.
        private func linePosition(forOffset offset: CGFloat) -> Double {
            guard lineOffsets.count > 1 else { return 0 }
            guard offset > lineOffsets[0] else { return 0 }
            guard offset < lineOffsets[lineOffsets.count - 1] else { return Double(lineOffsets.count - 1) }

            var low = 0
            var high = lineOffsets.count - 1
            while low + 1 < high {
                let mid = (low + high) / 2
                if lineOffsets[mid] <= offset {
                    low = mid
                } else {
                    high = mid
                }
            }

            let span = lineOffsets[low + 1] - lineOffsets[low]
            guard span > 0 else { return Double(low) }
            return Double(low) + Double((offset - lineOffsets[low]) / span)
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

    func makeUIView(context: Context) -> TeleprompterReaderHostView {
        let host = TeleprompterReaderHostView()
        let textView = host.textView
        textView.isEditable = false
        textView.isSelectable = false
        textView.backgroundColor = colorScheme == .dark ? AppColors.UIColors.Dark.background : AppColors.UIColors.Light.background
        textView.delegate = context.coordinator
        textView.showsVerticalScrollIndicator = false
        textView.alwaysBounceVertical = true
        textView.textContainerInset = UIEdgeInsets(top: topPadding, left: 24, bottom: bottomPadding, right: 24)
        textView.textContainer.lineFragmentPadding = 0

        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap))
        tapGesture.cancelsTouchesInView = false
        textView.addGestureRecognizer(tapGesture)
        host.onLayoutChange = { [weak coordinator = context.coordinator] in
            coordinator?.scheduleUpdate()
        }
        return host
    }

    static func dismantleUIView(_ uiView: TeleprompterReaderHostView, coordinator: Coordinator) {
        uiView.onLayoutChange = nil
        coordinator.cancelUpdates()
        coordinator.stopEasing()
        uiView.cancelVideoRestoration()
    }

    func updateUIView(_ host: TeleprompterReaderHostView, context: Context) {
        let coordinator = context.coordinator
        coordinator.updateReader = { [weak host, weak coordinator] in
            guard let host, let coordinator else { return }
            updateReader(host, coordinator: coordinator)
        }
        coordinator.scheduleUpdate()
    }

    private func updateReader(_ host: TeleprompterReaderHostView, coordinator: Coordinator) {
        guard host.window != nil, host.bounds.width > 0, host.bounds.height > 0 else { return }
        // PiP owns presentation while the app is in the background. Updating
        // the hidden UITextView and its display link competes with video frames.
        if UIApplication.shared.applicationState == .background && restorationRequest == nil {
            coordinator.stopEasing()
            coordinator.isScrollSuspended = true
            return
        }
        let textView = host.textView
        host.layoutIfNeeded()
        TeleprompterPiPManager.shared.attachReader(host)
        textView.backgroundColor = colorScheme == .dark ? AppColors.UIColors.Dark.background : AppColors.UIColors.Light.background
        coordinator.onTap = onTap
        coordinator.onHandOff = onHandOff
        textView.textContainerInset = UIEdgeInsets(top: topPadding, left: 24, bottom: bottomPadding, right: 24)

        let needsSnap = coordinator.lastSnapToken != snapToken || coordinator.isScrollSuspended
        coordinator.isScrollSuspended = false
        coordinator.lastSnapToken = snapToken
        let needsRestoration = restorationRequest != nil
            && coordinator.lastRestorationRequest != restorationRequest

        let contentId = content.fullText
        let needsFullRebuild = coordinator.lastContentId != contentId
            || coordinator.lastFontSize != fontSize
            || coordinator.lastCueColor != cueColor
            || coordinator.lastColorScheme != colorScheme

        if needsFullRebuild {
            textView.attributedText = TeleprompterTextLayout.attributedString(
                text: content.fullText, fontSize: fontSize, cueColor: cueColor, isDarkMode: colorScheme == .dark
            )
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
            let layout = layoutLines(for: textView)
            coordinator.lineOffsets = layout.offsets

            if layout.starts != coordinator.lastReportedLineStarts {
                coordinator.lastReportedLineStarts = layout.starts
                // This entire update is already outside SwiftUI's layout pass.
                onLayoutChange(layout.starts)
            }
        }

        let offsets = coordinator.lineOffsets
        guard textView.bounds.width > 0, textView.bounds.height > 0 else { return }
        guard offsets.count > 1 else {
            if needsRestoration {
                restoreReader(host, coordinator: coordinator, at: offsets.first ?? 0)
            }
            return
        }

        let position = min(max(linePosition, 0), Double(offsets.count - 1))
        let line = min(Int(position), offsets.count - 2)
        let fraction = CGFloat(position - Double(line))
        let target = offsets[line] + (offsets[line + 1] - offsets[line]) * fraction

        let maxY = max(0, textView.contentSize.height - textView.bounds.height)
        let scrollY = min(max(target, 0), maxY)

        if needsRestoration {
            restoreReader(host, coordinator: coordinator, at: scrollY)
            return
        }

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

    private func restoreReader(_ host: TeleprompterReaderHostView, coordinator: Coordinator, at offset: CGFloat) {
        let textView = host.textView
        guard let request = restorationRequest,
              let scene = textView.window?.windowScene,
              scene.activationState == .foregroundActive || scene.activationState == .foregroundInactive else { return }
        guard host.prepareVideoRestoration() else { return }
        coordinator.lastRestorationRequest = request
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        CATransaction.setCompletionBlock {
            DispatchQueue.main.async {
                onRestorationReady(request)
            }
        }
        coordinator.settle(at: offset, in: textView)
        textView.layoutIfNeeded()
        CATransaction.commit()
    }

    /// The scroll offset that puts each rendered line on the reading line, one
    /// entry per line the script actually wraps into on this screen.
    private func layoutLines(for textView: UITextView) -> (offsets: [CGFloat], starts: [Int]) {
        let layoutManager = textView.layoutManager
        let container = textView.textContainer
        layoutManager.ensureLayout(for: container)

        // Line fragments are measured inside the text container, which is already
        // the offset that line should be scrolled to.
        var offsets: [CGFloat] = []
        var starts: [Int] = []
        let glyphRange = layoutManager.glyphRange(for: container)
        var glyphIndex = glyphRange.location

        while glyphIndex < NSMaxRange(glyphRange) {
            var lineRange = NSRange(location: 0, length: 0)
            let fragment = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: &lineRange)
            offsets.append(fragment.origin.y)
            starts.append(layoutManager.characterIndexForGlyph(at: glyphIndex))

            guard lineRange.length > 0 else { break }
            glyphIndex = NSMaxRange(lineRange)
        }

        return (offsets, starts)
    }

}

#Preview {
    TeleprompterView(content: TeleprompterParser.parseNotes(""))
        .environmentObject(SettingsService.shared)
}
