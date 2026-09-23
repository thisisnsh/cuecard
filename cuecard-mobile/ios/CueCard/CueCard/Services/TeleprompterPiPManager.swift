import AVKit
import UIKit
import SwiftUI
#if DEBUG
import os

private let pipPerformanceLog = OSLog(subsystem: "com.thisisnsh.cuecard.ios", category: .pointsOfInterest)
#endif

/// The app and PiP read this same snapshot. Neither presentation owns a clock.
struct TeleprompterPlaybackState: Equatable {
    var elapsedTime: Double = 0
    var scriptTime: Double = 0
    var isPlaying = false
    var isCountingDown = false
    var countdownValue = 0
    var hasStarted = false
    var snapToken = 0
}

@MainActor
final class TeleprompterPiPManager: NSObject, ObservableObject {
    static let shared = TeleprompterPiPManager()

    @Published private(set) var playback = TeleprompterPlaybackState() {
        didSet {
            syncLiveActivity()
            syncWatch()
        }
    }
    @Published private(set) var isPiPActive = false
    @Published private(set) var isPiPPossible = false
    /// A restoration request belongs to the full-screen presentation only. The
    /// still-visible overlay carries on scrolling through it.
    @Published private(set) var restorationRequest: UUID?
    private var restorationCompletion: ((Bool) -> Void)?
    private var restorationTimeout: DispatchWorkItem?

    private var settings: TeleprompterSettings = .default
    private var text = ""
    private var isDarkMode = false
    private var referenceLineStarts: [Int] = []
    private var clockTimer: Timer?
    private var playbackAnchor: CFTimeInterval?
    private var elapsedAtAnchor: Double = 0
    private var scriptAtAnchor: Double = 0
    private var overlayLineAtAnchor: Double = 0
    private var countdownDeadline: CFTimeInterval?

    private var pipController: AVPictureInPictureController?
    private var sourceView: UIView?
    private var pipViewController: AVPictureInPictureVideoCallViewController?
    private var contentView: TeleprompterPiPContentView?
    private weak var readerHost: TeleprompterReaderHostView?
    private var isRestoringToReader = false
    private var renderer: TeleprompterOverlayRenderer?
    private var possibilityObservation: NSKeyValueObservation?
    private var isStartingPiP = false
    private var minimizeWhenStarted = false
    private var lastFrameTime: CFTimeInterval = 0
    private let liveActivity = TeleprompterActivityController()
    private var isInBackground = false
    /// What the watch was last told, so it is only told again on a change.
    private var watchTimer: TeleprompterTimerState?

    /// The overlay is repainted on the clock's tick. It is a view rather than a
    /// video, so there is no queue to fill ahead of time: each tick draws the
    /// position the clock is at when it fires.
    private static let paintRate: Double = 1.0 / 30

    private override init() { super.init() }

    private var linesPerSecond: Double { Double(settings.linesPerMinute) / 60 }
    private var scriptDuration: Double {
        guard linesPerSecond > 0 else { return 0 }
        return Double(max(referenceLineStarts.count - 1, 0)) / linesPerSecond
    }
    private var characterPosition: Double { characterPosition(for: playback) }
    private func characterPosition(for state: TeleprompterPlaybackState) -> Double {
        TeleprompterTextLayout.characterPosition(
            forLine: state.scriptTime * linesPerSecond, starts: referenceLineStarts
        )
    }

    /// The presentation being watched moves at a steady rate in its own lines;
    /// the other follows it through the shared character position. Lines wrap
    /// differently in the two layouts, so a position driven by the full-screen
    /// lines lurches in the floating window at every line break, and vice versa.
    private var overlayDrives: Bool { isPiPActive || isStartingPiP }
    /// The lines/minute pace, converted so both layouts cover the script in the
    /// same time.
    private var overlayLinesPerSecond: Double {
        guard let renderer, renderer.lineCount > 1, referenceLineStarts.count > 1 else { return linesPerSecond }
        return linesPerSecond * Double(renderer.lineCount - 1) / Double(referenceLineStarts.count - 1)
    }
    private func overlayLine(for state: TeleprompterPlaybackState) -> Double {
        renderer?.linePosition(forCharacter: characterPosition(for: state)) ?? 0
    }
    private func scriptTime(forOverlayLine line: Double) -> Double {
        guard let renderer, linesPerSecond > 0 else { return playback.scriptTime }
        let character = renderer.characterPosition(forLine: line)
        return TeleprompterTextLayout.linePosition(forCharacter: character, starts: referenceLineStarts) / linesPerSecond
    }

    private struct Projection {
        var state: TeleprompterPlaybackState
        var overlayLine: Double
    }

    func configure(text: String, settings: TeleprompterSettings, timerDuration: Int, colorScheme: ColorScheme) {
        cleanup()
        self.settings = settings
        self.text = text
        isDarkMode = colorScheme == .dark
        playback = TeleprompterPlaybackState()
        referenceLineStarts = []
        renderer = TeleprompterOverlayRenderer(text: text, settings: settings,
                                            timerDuration: timerDuration, isDarkMode: isDarkMode)
        setupPiP()
        syncLiveActivity()
        syncWatch()
    }

    /// Settings changed mid-session. The reader stays on the same line through
    /// a speed change, and the floating window is redrawn for anything it shows.
    func update(settings newSettings: TeleprompterSettings, colorScheme: ColorScheme) {
        let newIsDarkMode = colorScheme == .dark
        guard newSettings != settings || newIsDarkMode != isDarkMode else { return }
        advanceClock()
        let line = playback.scriptTime * linesPerSecond
        let needsRedraw = newSettings.pipFontSize != settings.pipFontSize
            || newSettings.overlayAspectRatio != settings.overlayAspectRatio
            || newSettings.cueColor != settings.cueColor
            || newSettings.timerDurationSeconds != settings.timerDurationSeconds
            || newIsDarkMode != isDarkMode
        let speedChanged = newSettings.linesPerMinute != settings.linesPerMinute
        settings = newSettings
        isDarkMode = newIsDarkMode

        if speedChanged && linesPerSecond > 0 {
            var state = playback
            state.scriptTime = line / linesPerSecond
            playback = state
        }
        if needsRedraw && renderer != nil {
            let redrawn = TeleprompterOverlayRenderer(text: text, settings: settings,
                                                    timerDuration: settings.timerDurationSeconds, isDarkMode: isDarkMode)
            renderer = redrawn
            sourceView?.backgroundColor = redrawn.backgroundColor
            contentView?.renderer = redrawn
            pipViewController?.view.backgroundColor = redrawn.backgroundColor
            pipViewController?.preferredContentSize = redrawn.logicalSize
        }
        if speedChanged || needsRedraw {
            // A new overlay layout changes its line count and pace as well.
            reanchorPlayback()
            repaintOverlay()
            renderFrame(force: true)
        }
        syncLiveActivity()
    }

    /// Full-screen line starts are the definition of the lines/minute setting.
    /// Both layouts address the same UTF-16 text, including cues and whitespace.
    func updateReferenceLayout(_ starts: [Int]) {
        guard starts != referenceLineStarts else { return }
        advanceClock()
        let character = characterPosition
        let hadLayout = !referenceLineStarts.isEmpty
        referenceLineStarts = starts
        if hadLayout && linesPerSecond > 0 {
            var state = playback
            state.scriptTime = TeleprompterTextLayout.linePosition(forCharacter: character, starts: starts) / linesPerSecond
            state.snapToken += 1
            playback = state
            reanchorPlayback()
        }
        repaintOverlay()
        renderFrame(force: true)
    }

    func togglePlayPause() {
        if playback.isPlaying || playback.isCountingDown { pause() } else { play() }
    }

    /// Native PiP Play and the in-app Play button follow the same start delay.
    func play() {
        guard !playback.isPlaying, !playback.isCountingDown else { return }
        var state = playback
        if !state.hasStarted && settings.countdownSeconds > 0 {
            state.isCountingDown = true
            state.countdownValue = settings.countdownSeconds
            countdownDeadline = CACurrentMediaTime() + Double(settings.countdownSeconds)
        } else {
            state.isPlaying = true
            state.hasStarted = true
        }
        playback = state
        reanchorPlayback()
        startClock()
        repaintOverlay()
        renderFrame(force: true)
    }

    func pause() {
        advanceClock()
        var state = playback
        state.isPlaying = false
        state.isCountingDown = false
        state.countdownValue = 0
        playback = state
        countdownDeadline = nil
        playbackAnchor = nil
        syncClock()
        repaintOverlay()
        renderFrame(force: true)
    }

    func restart() {
        countdownDeadline = nil
        playbackAnchor = nil
        let nextSnap = playback.snapToken + 1
        playback = TeleprompterPlaybackState(snapToken: nextSnap)
        syncClock()
        repaintOverlay()
        renderFrame(force: true)
    }

    /// A drag or native skip changes only the script position, never the timer.
    func seek(toLine line: Double) {
        guard line.isFinite, linesPerSecond > 0 else { return }
        seek(toScriptTime: line / linesPerSecond)
    }

    /// A script is open in the teleprompter, so there is playback to control.
    var hasSession: Bool { renderer != nil }

    /// The overlay always owns its timer on non-island devices, and takes it
    /// back if the Live Activity is unavailable or dismissed.
    var showsTimerInPiP: Bool {
        !TeleprompterActivityController.hasDynamicIsland || !liveActivity.isActive
    }

    /// Move the script by a number of its seconds, from where it shows now.
    /// Playing on past the last line leaves the text resting there, so a skip
    /// back from the end counts from the last line rather than the clock.
    func skip(bySeconds seconds: Double) {
        advanceClock()
        seek(toScriptTime: min(playback.scriptTime, scriptDuration) + seconds)
    }

    private func seek(toScriptTime seconds: Double) {
        guard seconds.isFinite else { return }
        advanceClock()
        var state = playback
        state.scriptTime = min(max(seconds, 0), scriptDuration)
        state.snapToken += 1
        playback = state
        reanchorPlayback()
        repaintOverlay()
        renderFrame(force: true)
    }

    /// Opening a reader is not playback. Begin on Play (including its start
    /// delay), retain controls while paused, and end on restart or dismissal.
    private func syncLiveActivity() {
        let hasBegun = playback.hasStarted || playback.isCountingDown
        pipController?.canStartPictureInPictureAutomaticallyFromInline = hasBegun
        guard hasSession, hasBegun,
              !isInBackground || isPiPActive || isStartingPiP || isRestoringToReader else {
            liveActivity.end()
            return
        }
        liveActivity.sync(playback,
                          countdownRemaining: countdownDeadline.map { max(0, $0 - CACurrentMediaTime()) },
                          timerDuration: settings.timerDurationSeconds)
    }

    /// A background app without a floating reader cannot keep prompting.
    /// Called from the app scene, so it also runs if the reader was dismissed.
    func sceneDidChange(to phase: ScenePhase) {
        switch phase {
        case .background:
            isInBackground = true
            if hasSession, playback.hasStarted || playback.isCountingDown,
               !isPiPActive, !isStartingPiP {
                _ = startPiP()
            }
            pauseIfNoPresentation()
        case .active:
            isInBackground = false
            refreshPresentation()
        default:
            break
        }
        syncLiveActivity()
    }

    private func pauseIfNoPresentation() {
        guard isInBackground, !isPiPActive, !isStartingPiP, !isRestoringToReader else { return }
        pause()
        liveActivity.end()
    }

    func waitForLiveActivity() async {
        await liveActivity.waitForUpdates()
    }

    /// The session timer as the watch shows it. Nil while no script is open.
    var timerState: TeleprompterTimerState? {
        guard hasSession else { return nil }
        return TeleprompterActivityController.contentState(
            for: playback,
            countdownRemaining: countdownDeadline.map { max(0, $0 - CACurrentMediaTime()) },
            timerDuration: settings.timerDurationSeconds
        )
    }

    /// Like the island, the watch ticks the running time itself, so it is
    /// only told when what it shows changes.
    private func syncWatch() {
        let state = timerState
        switch (state, watchTimer) {
        case (nil, nil):
            return
        case let (state?, last?) where state.matches(last):
            return
        default:
            watchTimer = state
            WatchSessionService.shared.stateChanged()
        }
    }

    private func reanchorPlayback() {
        elapsedAtAnchor = playback.elapsedTime
        scriptAtAnchor = playback.scriptTime
        overlayLineAtAnchor = overlayLine(for: playback)
        playbackAnchor = playback.isPlaying ? CACurrentMediaTime() : nil
    }

    /// The clock timer also paints the floating window, so it keeps running
    /// while that window is up even with playback paused. A paused window that
    /// loses its picture is repainted on the next tick instead of staying black
    /// until something happens to redraw it.
    private var needsClock: Bool {
        playback.isPlaying || playback.isCountingDown || isPiPActive || isStartingPiP
    }

    private func syncClock() {
        if needsClock { startClock() } else { stopClock() }
    }

    private func startClock() {
        guard clockTimer == nil else { return }
        let timer = Timer(timeInterval: Self.paintRate, target: self,
                          selector: #selector(clockTick), userInfo: nil, repeats: true)
        RunLoop.main.add(timer, forMode: .common)
        clockTimer = timer
    }

    private func stopClock() {
        clockTimer?.invalidate()
        clockTimer = nil
    }

    /// Playback as it stands at any host time, past or future, without touching
    /// the shared state. The same projection serves the clock and the frames
    /// queued ahead of it, so a frame's content depends only on its own time.
    private func projection(at hostTime: CFTimeInterval) -> Projection {
        var state = playback
        var anchor = playbackAnchor
        var elapsedBase = elapsedAtAnchor
        var scriptBase = scriptAtAnchor
        var overlayBase = overlayLineAtAnchor
        if let deadline = countdownDeadline {
            if hostTime < deadline {
                let remaining = deadline - hostTime
                state.countdownValue = Int(ceil(remaining))
                return Projection(state: state, overlayLine: overlayLine(for: state))
            }
            state.isCountingDown = false
            state.countdownValue = 0
            state.isPlaying = true
            state.hasStarted = true
            anchor = deadline
            elapsedBase = state.elapsedTime
            scriptBase = state.scriptTime
            overlayBase = overlayLine(for: state)
        }
        guard state.isPlaying, let anchor else {
            return Projection(state: state, overlayLine: overlayLine(for: state))
        }
        let elapsed = max(0, hostTime - anchor)
        state.elapsedTime = elapsedBase + elapsed
        if overlayDrives {
            let line = overlayBase + overlayLinesPerSecond * elapsed
            state.scriptTime = scriptTime(forOverlayLine: line)
            return Projection(state: state, overlayLine: line)
        }
        // Deliberately unbounded. Only the rendered text clamps at its last
        // line; reaching it must not pause the video or the session clock.
        state.scriptTime = scriptBase + elapsed
        return Projection(state: state, overlayLine: overlayLine(for: state))
    }

    /// Use a monotonic anchor, so delayed callbacks do not slow playback or the
    /// countdown. This clock continues across PiP entry, exit and restoration.
    private func advanceClock() {
        let now = CACurrentMediaTime()
        let state = projection(at: now).state
        var countdownFinished = false
        if let deadline = countdownDeadline, now >= deadline {
            elapsedAtAnchor = playback.elapsedTime
            scriptAtAnchor = playback.scriptTime
            overlayLineAtAnchor = overlayLine(for: playback)
            playbackAnchor = deadline
            countdownDeadline = nil
            countdownFinished = true
        }
        if state != playback { playback = state }
        if countdownFinished { repaintOverlay() }
    }

    /// Bring the clock up to date under the outgoing driver before a change of
    /// presentation; re-anchoring after the change paces from there.
    private func switchDriver() {
        advanceClock()
    }

    @objc private func clockTick() {
        #if DEBUG
        if isPiPActive || isStartingPiP {
            os_signpost(.event, log: pipPerformanceLog, name: "PiP clock tick")
        }
        #endif
        advanceClock()
        renderFrame()
    }

    /// Every jump in the shared position comes through here. The overlay holds
    /// no queued frames, so a jump is simply the next paint.
    private func repaintOverlay() {
        renderFrame(force: true)
    }

    /// Paint the overlay at the position the clock is at now. The floating
    /// window is a hosted view, not a video: there is no queue to fill ahead and
    /// nothing in the media pipeline for another app to take away, which is what
    /// let a camera recording blank the old sample-buffer window.
    private func renderFrame(force: Bool = false) {
        guard let contentView, let renderer else { return }
        // Non-island phones always retain the overlay timer. On an island
        // phone, hide it only after ActivityKit actually accepted the timer.
        renderer.showsTimer = showsTimerInPiP
        let hostNow = CACurrentMediaTime()
        let renderingPiP = isPiPActive || isStartingPiP || isRestoringToReader
        #if DEBUG
        let signpostID = OSSignpostID(log: pipPerformanceLog)
        os_signpost(.begin, log: pipPerformanceLog, name: "PiP render", signpostID: signpostID)
        defer { os_signpost(.end, log: pipPerformanceLog, name: "PiP render", signpostID: signpostID) }
        #endif
        // Off the overlay the mirrored view only has to stay roughly current for
        // the transition into it; on it, every tick is a frame of the scroll.
        if !renderingPiP && !force {
            guard hostNow - lastFrameTime >= 0.2 else { return }
        }
        contentView.present(linePosition: overlayLine(for: playback), state: playback)
        #if DEBUG
        os_signpost(.event, log: pipPerformanceLog, name: "PiP frame submitted")
        #endif
        lastFrameTime = hostNow
    }

    @discardableResult
    func startPiP(minimizeApp: Bool = false) -> Bool {
        guard !isPiPActive, !isStartingPiP,
              let controller = pipController, controller.isPictureInPicturePossible else { return false }
        switchDriver()
        renderFrame(force: true)
        minimizeWhenStarted = minimizeApp
        isStartingPiP = true
        reanchorPlayback()
        controller.startPictureInPicture()
        return true
    }

    func stopPiP() { pipController?.stopPictureInPicture() }

    /// Called when returning to the foreground; there is no state to copy back.
    func refreshPresentation() {
        advanceClock()
        renderFrame(force: true)
    }

    func attachReader(_ host: TeleprompterReaderHostView) {
        readerHost = host
        if let sourceView {
            host.installVideoSource(sourceView)
        } else if renderer != nil {
            setupPiP()
        }
    }

    func completeRestoration(_ request: UUID, restored: Bool = true) {
        guard restorationRequest == request else { return }
        let completion = restorationCompletion
        restorationCompletion = nil
        restorationTimeout?.cancel()
        restorationTimeout = nil
        restorationRequest = nil
        if !restored {
            isRestoringToReader = false
            readerHost?.cancelVideoRestoration()
        }
        completion?(restored)
    }

    func cleanup() {
        if let request = restorationRequest { completeRestoration(request, restored: false) }
        stopClock()
        liveActivity.end()
        countdownDeadline = nil
        playbackAnchor = nil
        possibilityObservation = nil
        pipController?.delegate = nil
        pipController?.stopPictureInPicture()
        pipController = nil
        contentView?.removeFromSuperview()
        contentView = nil
        pipViewController = nil
        sourceView?.removeFromSuperview()
        sourceView = nil
        readerHost?.cancelVideoRestoration()
        isRestoringToReader = false
        renderer = nil
        isPiPActive = false
        isPiPPossible = false
        isStartingPiP = false
        minimizeWhenStarted = false
        lastFrameTime = 0
        syncWatch()
    }

    func disable() { cleanup() }

    private func setupPiP() {
        guard AVPictureInPictureController.isPictureInPictureSupported() else { return }
        guard pipController == nil, let host = readerHost, let renderer else { return }
        // The source view is what AVKit animates the overlay out of and back
        // into. It stays in the reader's own hierarchy and bounds, so the
        // transition lands on the script rather than flying in from nowhere.
        let source = UIView()
        source.backgroundColor = renderer.backgroundColor
        host.installVideoSource(source)
        sourceView = source

        // A video-call overlay hosts this app's own views. Nothing goes through
        // the media pipeline, so no other app's recording can take it away, and
        // no audio session is needed to hold it open.
        let controller = AVPictureInPictureVideoCallViewController()
        controller.preferredContentSize = renderer.logicalSize
        controller.view.backgroundColor = renderer.backgroundColor
        let content = TeleprompterPiPContentView(renderer: renderer)
        content.translatesAutoresizingMaskIntoConstraints = false
        controller.view.addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: controller.view.topAnchor),
            content.bottomAnchor.constraint(equalTo: controller.view.bottomAnchor),
            content.leadingAnchor.constraint(equalTo: controller.view.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: controller.view.trailingAnchor)
        ])
        pipViewController = controller
        contentView = content

        let pip = AVPictureInPictureController(contentSource: .init(
            activeVideoCallSourceView: source, contentViewController: controller
        ))
        pip.delegate = self
        pip.canStartPictureInPictureAutomaticallyFromInline = playback.hasStarted || playback.isCountingDown
        pipController = pip
        possibilityObservation = pip.observe(\.isPictureInPicturePossible, options: [.initial, .new]) { [weak self] controller, _ in
            Task { @MainActor in
                guard let self, self.pipController === controller else { return }
                self.isPiPPossible = controller.isPictureInPicturePossible
            }
        }
        renderFrame(force: true)
    }
}

extension TeleprompterPiPManager: @preconcurrency AVPictureInPictureControllerDelegate {
    func pictureInPictureControllerWillStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        guard pipController === pictureInPictureController else { return }
        if let request = restorationRequest { completeRestoration(request, restored: false) }
        readerHost?.cancelVideoRestoration()
        isRestoringToReader = false
        switchDriver()
        isStartingPiP = true
        reanchorPlayback()
        syncClock()
        renderFrame(force: true)
    }

    func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        guard pipController === pictureInPictureController else { return }
        isStartingPiP = false
        isPiPActive = true
        syncLiveActivity()
        // The window is now this app's to keep painting, paused or not.
        syncClock()
        renderFrame(force: true)
        if minimizeWhenStarted {
            minimizeWhenStarted = false
            UIApplication.shared.perform(#selector(NSXPCConnection.suspend))
        }
    }

    func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        guard pipController === pictureInPictureController else { return }
        switchDriver()
        if let request = restorationRequest { completeRestoration(request, restored: false) }
        isPiPActive = false
        isStartingPiP = false
        minimizeWhenStarted = false
        reanchorPlayback()
        syncClock()
        refreshPresentation()
        if isRestoringToReader, let readerHost {
            readerHost.finishVideoRestoration { [weak self] in
                guard self?.pipController === pictureInPictureController else { return }
                self?.isRestoringToReader = false
            }
        } else {
            isRestoringToReader = false
        }
        pauseIfNoPresentation()
        syncLiveActivity()
    }

    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, failedToStartPictureInPictureWithError error: Error) {
        guard pipController === pictureInPictureController else { return }
        switchDriver()
        isStartingPiP = false
        isPiPActive = false
        minimizeWhenStarted = false
        isRestoringToReader = false
        reanchorPlayback()
        syncClock()
        readerHost?.cancelVideoRestoration()
        print("Could not start PiP: \(error)")
        pauseIfNoPresentation()
        syncLiveActivity()
    }

    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void) {
        guard pipController === pictureInPictureController else {
            completionHandler(false)
            return
        }
        advanceClock()
        if let request = restorationRequest { completeRestoration(request, restored: false) }
        let request = UUID()
        isRestoringToReader = true
        restorationCompletion = completionHandler
        restorationRequest = request
        // A detached/dismissed reader must not leave AVKit waiting forever.
        // Success comes only from the reader's committed layout, not a delay.
        let timeout = DispatchWorkItem { [weak self] in
            self?.completeRestoration(request, restored: false)
        }
        restorationTimeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: timeout)
    }
}

/// The overlay's page, hosted as a view. This is the same drawing the video
/// renderer did, going to a layer the system composites instead of to a sample
/// buffer — which is what keeps it painting while another app uses the camera.
@MainActor
private final class TeleprompterPiPContentView: UIView {
    var renderer: TeleprompterOverlayRenderer {
        didSet {
            backgroundColor = renderer.backgroundColor
            setNeedsDisplay()
        }
    }
    private var linePosition: Double = 0
    private var state = TeleprompterPlaybackState()

    init(renderer: TeleprompterOverlayRenderer) {
        self.renderer = renderer
        super.init(frame: CGRect(origin: .zero, size: renderer.logicalSize))
        backgroundColor = renderer.backgroundColor
        isOpaque = true
        isUserInteractionEnabled = false
        contentMode = .redraw
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func present(linePosition: Double, state: TeleprompterPlaybackState) {
        guard linePosition != self.linePosition || state != self.state else { return }
        self.linePosition = linePosition
        self.state = state
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext(), bounds.width > 0, bounds.height > 0 else { return }
        // The page keeps a fixed logical size, as it did as a video: resizing the
        // overlay scales the page rather than re-wrapping the script, so the line
        // being read never moves under the reader when the window changes size.
        let size = renderer.logicalSize
        let scale = min(bounds.width / size.width, bounds.height / size.height)
        context.saveGState()
        context.translateBy(x: (bounds.width - size.width * scale) / 2,
                            y: (bounds.height - size.height * scale) / 2)
        context.scaleBy(x: scale, y: scale)
        renderer.draw(in: context, linePosition: linePosition, state: state)
        context.restoreGState()
    }
}

/// Shared text construction is essential: character offsets cannot synchronize
/// two layouts if one preserves spaces and the other splits text into words.
@MainActor
enum TeleprompterTextLayout {
    static func attributedString(text: String, fontSize: CGFloat, cueColor: CueColor, isDarkMode: Bool) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let textAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: fontSize, weight: .medium),
            .foregroundColor: isDarkMode ? AppColors.UIColors.Dark.textPrimary : AppColors.UIColors.Light.textPrimary
        ]
        let cueAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: fontSize * 0.72, weight: .semibold),
            .foregroundColor: cueColor.uiColor(isDarkMode: isDarkMode),
            .kern: fontSize * 0.05
        ]
        for (paragraphIndex, paragraph) in text.components(separatedBy: "\n\n").enumerated() {
            if paragraphIndex > 0 { result.append(NSAttributedString(string: "\n")) }
            for (lineIndex, line) in paragraph.components(separatedBy: "\n").enumerated() {
                if lineIndex > 0 { result.append(NSAttributedString(string: "\n")) }
                for (index, segment) in TeleprompterParser.segments(in: line).enumerated() {
                    if index > 0 { result.append(NSAttributedString(string: " ", attributes: textAttributes)) }
                    switch segment {
                    case .text(let text):
                        result.append(NSAttributedString(string: text, attributes: textAttributes))
                    case .cue(let cue):
                        result.append(NSAttributedString(string: cue, attributes: cueAttributes))
                    }
                }
            }
        }
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = fontSize * 0.18
        paragraphStyle.paragraphSpacing = fontSize * 0.45
        result.addAttribute(.paragraphStyle, value: paragraphStyle, range: NSRange(location: 0, length: result.length))
        return result
    }

    static func characterPosition(forLine position: Double, starts: [Int]) -> Double {
        guard let last = starts.last else { return 0 }
        let line = max(position, 0)
        guard line < Double(starts.count - 1) else { return Double(last) }
        let index = Int(line)
        return Double(starts[index]) + (line - Double(index)) * Double(starts[index + 1] - starts[index])
    }

    static func linePosition(forCharacter position: Double, starts: [Int]) -> Double {
        guard starts.count > 1 else { return 0 }
        if position <= Double(starts[0]) { return 0 }
        if position >= Double(starts[starts.count - 1]) { return Double(starts.count - 1) }
        var low = 0
        var high = starts.count - 1
        while low + 1 < high {
            let middle = (low + high) / 2
            if Double(starts[middle]) <= position { low = middle } else { high = middle }
        }
        let length = starts[low + 1] - starts[low]
        return Double(low) + (length > 0 ? (position - Double(starts[low])) / Double(length) : 0)
    }
}

/// Draw glyphs directly into the overlay's context. Capturing a UITextView's
/// layers captures cached raster tiles, which can be low-resolution or stale
/// offscreen, which is what used to make the script flicker and drop out.
@MainActor
private final class TeleprompterOverlayRenderer {
    let backgroundColor: UIColor
    let logicalSize: CGSize
    /// The fade is rasterized at the resolution the page was drawn at when it
    /// was a video, which is comfortably above any size the overlay is shown at.
    private let rasterWidth: CGFloat = 1280
    private let edgeFade: UIImage
    private let textStorage: NSTextStorage
    private let layoutManager = NSLayoutManager()
    private let textContainer: NSTextContainer
    private var lineStarts: [Int] = []
    private var lineOffsets: [CGFloat] = []
    var lineCount: Int { lineStarts.count }
    private let timerDuration: Int
    private let timerFont: UIFont
    /// Updated by the session when the island can actually carry the timer.
    var showsTimer = true
    private let isDarkMode: Bool
    /// The in-app timer is 16 pt over 28 pt text by default. The overlay keeps
    /// that proportion to its own text size, so the timer never outgrows it.
    private static let timerToTextRatio: CGFloat = 16.0 / 28.0

    init(text: String, settings: TeleprompterSettings, timerDuration: Int, isDarkMode: Bool) {
        self.timerDuration = timerDuration
        // The same face as the in-app timer: SF Mono, bold.
        timerFont = UIFont.monospacedSystemFont(
            ofSize: CGFloat(settings.pipFontSize) * Self.timerToTextRatio, weight: .bold
        )
        self.isDarkMode = isDarkMode
        backgroundColor = isDarkMode ? AppColors.UIColors.Dark.background : AppColors.UIColors.Light.background
        logicalSize = CGSize(width: 320, height: 320 / settings.overlayAspectRatio.ratio)
        // The fade never changes during playback. Rasterize it once at video
        // resolution instead of evaluating two gradients on every frame.
        let fadeFormat = UIGraphicsImageRendererFormat()
        fadeFormat.scale = rasterWidth / logicalSize.width
        fadeFormat.opaque = false
        fadeFormat.preferredRange = .standard
        let colors = [backgroundColor.cgColor, backgroundColor.withAlphaComponent(0).cgColor] as CFArray
        edgeFade = UIGraphicsImageRenderer(size: CGSize(width: 296, height: 18), format: fadeFormat).image { context in
            if let fade = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
                context.cgContext.drawLinearGradient(fade, start: .zero, end: CGPoint(x: 0, y: 18), options: [])
            }
        }
        textStorage = NSTextStorage(attributedString: TeleprompterTextLayout.attributedString(
            text: text, fontSize: CGFloat(settings.pipFontSize), cueColor: settings.cueColor, isDarkMode: isDarkMode
        ))
        textContainer = NSTextContainer(size: CGSize(width: 296, height: CGFloat.greatestFiniteMagnitude))
        textContainer.lineFragmentPadding = 0
        layoutManager.addTextContainer(textContainer)
        textStorage.addLayoutManager(layoutManager)
        layoutManager.ensureLayout(for: textContainer)
        let glyphs = layoutManager.glyphRange(for: textContainer)
        layoutManager.enumerateLineFragments(forGlyphRange: glyphs) { [self] rect, _, _, range, _ in
            lineStarts.append(layoutManager.characterIndexForGlyph(at: range.location))
            lineOffsets.append(rect.minY)
        }
    }

    func linePosition(forCharacter position: Double) -> Double {
        TeleprompterTextLayout.linePosition(forCharacter: position, starts: lineStarts)
    }

    func characterPosition(forLine position: Double) -> Double {
        TeleprompterTextLayout.characterPosition(forLine: position, starts: lineStarts)
    }

    /// Draw the script with `linePosition` (fractional, in this layout's lines)
    /// on the reading line, into a context already scaled to `logicalSize`.
    func draw(in context: CGContext, linePosition: Double, state: TeleprompterPlaybackState) {
        context.setFillColor(backgroundColor.cgColor)
        context.fill(CGRect(origin: .zero, size: logicalSize))
        var viewportTop: CGFloat = 8
        if showsTimer {
            let remaining = timerDuration > 0 ? timerDuration - Int(state.elapsedTime) : Int(state.elapsedTime)
            let time = TeleprompterParser.formatTime(state.isCountingDown ? state.countdownValue : remaining)
            let color = state.isCountingDown
                ? (isDarkMode ? AppColors.UIColors.Dark.pink : AppColors.UIColors.Light.pink)
                : AppColors.timerUIColor(remainingSeconds: remaining, totalSeconds: timerDuration, isDarkMode: isDarkMode)
            let style = NSMutableParagraphStyle()
            style.alignment = .center
            let timerHeight = ceil(timerFont.lineHeight)
            (time as NSString).draw(in: CGRect(x: 12, y: 6, width: 296, height: timerHeight), withAttributes: [
                .font: timerFont,
                .foregroundColor: color,
                .paragraphStyle: style
            ])
            viewportTop = 6 + timerHeight + 6
        }
        let viewport = CGRect(x: 12, y: viewportTop, width: 296, height: logicalSize.height - viewportTop - 8)
        let readingY = viewport.height * 0.45
        let position = min(max(linePosition, 0), Double(max(lineOffsets.count - 1, 0)))
        let line = min(Int(position), max(lineOffsets.count - 1, 0))
        var offset: CGFloat = 0
        if !lineOffsets.isEmpty {
            offset = lineOffsets[line]
            if line + 1 < lineOffsets.count {
                offset += CGFloat(position - Double(line)) * (lineOffsets[line + 1] - lineOffsets[line])
            }
        }
        context.saveGState()
        context.clip(to: viewport)
        context.translateBy(x: viewport.minX, y: viewport.minY + readingY - offset)
        let visibleRect = CGRect(x: 0, y: offset - readingY, width: viewport.width, height: viewport.height)
        let glyphs = layoutManager.glyphRange(forBoundingRect: visibleRect, in: textContainer)
        layoutManager.drawBackground(forGlyphRange: glyphs, at: .zero)
        layoutManager.drawGlyphs(forGlyphRange: glyphs, at: .zero)
        context.restoreGState()

        edgeFade.draw(in: CGRect(x: viewport.minX, y: viewport.minY, width: viewport.width, height: 18))
        context.saveGState()
        context.translateBy(x: viewport.minX, y: viewport.maxY)
        context.scaleBy(x: 1, y: -1)
        edgeFade.draw(in: CGRect(x: 0, y: 0, width: viewport.width, height: 18))
        context.restoreGState()
    }
}
