import AVKit
import UIKit
import SwiftUI

/// Manager for Picture-in-Picture teleprompter functionality
@MainActor
class TeleprompterPiPManager: NSObject, ObservableObject {
    static let shared = TeleprompterPiPManager()

    // MARK: - Published Properties

    @Published var isPiPActive = false
    @Published var isPiPPossible = false
    @Published var isPlaying = false

    // MARK: - Content Properties

    private(set) var text: String = ""
    private(set) var settings: TeleprompterSettings = .default
    private(set) var timerDuration: Int = 0
    private(set) var elapsedTime: Double = 0
    private(set) var isDarkMode: Bool = true
    /// How long the script runs for, set by the teleprompter from the lines it
    /// rendered and the speed. The overlay wraps the same script into more lines
    /// than the full screen does, so it covers its own content over that time
    /// rather than counting lines of its own — the two stay on the same word.
    var scriptDuration: Double = 0
    private(set) var countdownValue: Int = 0
    private(set) var isCountingDown: Bool = false

    // MARK: - PiP Components

    private var pipController: AVPictureInPictureController?
    private var pipViewController: AVPictureInPictureVideoCallViewController?
    private var teleprompterContentView: TeleprompterPiPContentView?
    private var pipContentView: TeleprompterPiPContentView?
    private var pipWindow: UIWindow?
    private var pipHostViewController: UIViewController?
    /// Where the window hosting the mirrored script sits while the overlay is
    /// running: centred, at the overlay's own shape, so the overlay shrinks out
    /// of a rectangle the same shape it is going to be.
    private var sourceFrame: CGRect = .zero
    /// Frosts the mirrored script on the way out. The overlay and the app lay
    /// the same words out at different sizes, so a straight crossfade shows two
    /// scripts at once — going soft first covers the difference.
    private var handBackBlurView: UIVisualEffectView?
    private var handBackAnimator: UIViewPropertyAnimator?
    /// A picture of the teleprompter, held in the source view for the length of
    /// the return so the overlay has the app itself to open into.
    private var handBackSnapshot: UIView?
    /// Set once that picture is in place, to keep the older centred hand-back
    /// from also running.
    private var isHandingBackToApp = false

    /// Where the window hosting the mirrored script sits: behind the app while
    /// the overlay runs, in front of it for the hand-back.
    private static let hiddenSourceLevel: UIWindow.Level = .normal - 1
    private static let visibleSourceLevel: UIWindow.Level = .normal + 1
    /// How long the mirrored script takes to dissolve after the overlay has
    /// closed into it, and how far it opens out while it goes.
    private static let handBackFadeDuration: TimeInterval = 0.45
    private static let handBackScale: CGFloat = 1.06

    // MARK: - Timers

    private var displayLink: CADisplayLink?
    private var playbackTimer: Timer?
    private var playbackTimerStartDate: Date?
    private var elapsedTimeAtPlaybackStart: Double = 0
    private var needsContentViewUpdate = false
    private var lastRenderTimestamp: CFTimeInterval = 0
    private var lastSourceRenderTimestamp: CFTimeInterval = 0
    private var isRenderingToPiP = false

    // MARK: - Callbacks

    var onPiPClosed: (() -> Void)?
    var onPiPRestoreUI: (() -> Void)?
    var onPlayPauseFromPiP: ((Bool) -> Void)?
    var onRestartFromPiP: (() -> Void)?
    var onExpandFromPiP: (() -> Void)?

    // MARK: - Initialization

    private override init() {
        super.init()
    }

    // MARK: - Public API

    /// Configure the PiP manager with content
    func configure(text: String, settings: TeleprompterSettings, timerDuration: Int, colorScheme: ColorScheme) {
        cleanup()
        self.text = text
        self.settings = settings
        self.timerDuration = timerDuration
        self.elapsedTime = 0
        self.isDarkMode = colorScheme == .dark

        setupPiP()
    }

    /// Update current state from TeleprompterView
    func updateState(elapsedTime: Double, isPlaying: Bool, countdownValue: Int = 0, isCountingDown: Bool = false) {
        self.elapsedTime = elapsedTime
        self.isPlaying = isPlaying
        self.countdownValue = countdownValue
        self.isCountingDown = isCountingDown

        // While the overlay is up it runs its own clock off a start date, so a
        // position pushed from the teleprompter has to carry that anchor with
        // it. Left where it was, the next render overwrites the push with
        // wherever the overlay had got to on its own: a resume jumps the whole
        // of the pause, and a seek snaps back within the frame.
        if isPlaying {
            if playbackTimer != nil {
                playbackTimerStartDate = Date()
                elapsedTimeAtPlaybackStart = elapsedTime
            } else if isRenderingToPiP {
                startPlaybackTimer()
            }
        } else {
            stopPlaybackTimer()
        }

        needsContentViewUpdate = true
    }

    /// Start PiP mode
    @discardableResult
    func startPiP(minimizeApp: Bool = false) -> Bool {
        guard let pipController = pipController else {
            print("PiP controller not available")
            return false
        }

        guard pipController.isPictureInPicturePossible else {
            print("PiP is not possible")
            return false
        }

        hideSourceBehindApp()
        lastSourceRenderTimestamp = 0
        updateContentView()
        pipController.startPictureInPicture()

        if minimizeApp {
            // Minimize the app after a short delay to let PiP start
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self.minimizeApp()
            }
        }

        return true
    }

    /// Minimize the app to background
    func minimizeApp() {
        UIApplication.shared.perform(#selector(NSXPCConnection.suspend))
    }

    /// Expand from PiP - bring app back to foreground
    func expandFromPiP() {
        stopPiP()
        onExpandFromPiP?()
    }

    /// Restart teleprompter from PiP
    func restartFromPiP() {
        stopPlaybackTimer()
        elapsedTime = 0
        isPlaying = false
        onRestartFromPiP?()
        updateContentView()
    }

    /// Toggle play/pause from PiP button
    func togglePlayPauseFromPiP() {
        isPlaying.toggle()
        if isPlaying {
            startPlaybackTimer()
        } else {
            stopPlaybackTimer()
        }
        onPlayPauseFromPiP?(isPlaying)
        updateContentView()
    }

    // MARK: - Playback Timer (for background PiP)

    private func startPlaybackTimer() {
        stopPlaybackTimer()
        playbackTimerStartDate = Date()
        elapsedTimeAtPlaybackStart = elapsedTime
        let interval = 1.0 / 30.0
        let timer = Timer(timeInterval: interval, target: self, selector: #selector(handlePlaybackTimerTick), userInfo: nil, repeats: true)
        RunLoop.main.add(timer, forMode: .common)
        playbackTimer = timer
        needsContentViewUpdate = true
    }

    @objc private func handlePlaybackTimerTick() {
        // Fallback renderer for when the display link is not firing (app in background).
        guard CACurrentMediaTime() - lastRenderTimestamp > 0.05 else { return }
        render()
    }

    private func stopPlaybackTimer() {
        playbackTimer?.invalidate()
        playbackTimer = nil
        playbackTimerStartDate = nil  // Prevents stale Task blocks from writing elapsedTime
    }

    /// Stop PiP mode
    func stopPiP() {
        pipController?.stopPictureInPicture()
    }

    /// Toggle play/pause
    func togglePlayPause() {
        isPlaying.toggle()
        updateContentView()
    }

    /// Seek forward 10 seconds
    func seekForward() {
        let end = scriptDuration > 0 ? scriptDuration : (timerDuration > 0 ? Double(timerDuration + 60) : 3600)
        elapsedTime = min(elapsedTime + 10, end)
        // Reset wall-clock anchor so the playback timer continues from the new position
        if playbackTimerStartDate != nil {
            playbackTimerStartDate = Date()
            elapsedTimeAtPlaybackStart = elapsedTime
        }
        updateContentView()
    }

    /// Seek backward 10 seconds
    func seekBackward() {
        elapsedTime = max(elapsedTime - 10, 0)
        // Reset wall-clock anchor so the playback timer continues from the new position
        if playbackTimerStartDate != nil {
            playbackTimerStartDate = Date()
            elapsedTimeAtPlaybackStart = elapsedTime
        }
        updateContentView()
    }

    /// Cleanup resources
    func cleanup() {
        stopDisplayLink()
        stopPlaybackTimer()
        hideSourceBehindApp()
        pipController?.stopPictureInPicture()
        pipController = nil
        pipViewController = nil
        teleprompterContentView?.removeFromSuperview()
        teleprompterContentView = nil
        handBackBlurView?.removeFromSuperview()
        handBackBlurView = nil
        pipHostViewController = nil
        sourceFrame = .zero
        pipContentView?.removeFromSuperview()
        pipContentView = nil
        pipWindow?.isHidden = true
        pipWindow = nil
        isPiPActive = false
        isRenderingToPiP = false
        lastRenderTimestamp = 0
        lastSourceRenderTimestamp = 0
    }

    /// Shut the overlay down and keep it down for this session. Used by the
    /// remote kill switch, where the point is that nothing offers PiP at all.
    func disable() {
        cleanup()
        isPiPPossible = false
    }

    // MARK: - PiP Setup

    private func setupPiP() {
        guard AVPictureInPictureController.isPictureInPictureSupported() else {
            print("PiP not supported on this device")
            isPiPPossible = false
            return
        }

        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let windowScene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first else {
            print("No window scene available")
            return
        }

        let screenBounds = windowScene.screen.bounds
        let maxWidth = screenBounds.width
        let maxHeight = screenBounds.height
        let ratio = settings.overlayAspectRatio.ratio
        var preferredWidth = maxWidth
        var preferredHeight = preferredWidth / ratio
        if preferredHeight > maxHeight {
            preferredHeight = maxHeight
            preferredWidth = preferredHeight * ratio
        }
        let preferredSize = CGSize(width: preferredWidth, height: preferredHeight)
        let pipWidth = preferredSize.width
        let pipHeight = preferredSize.height

        // Create the teleprompter content view
        let contentView = TeleprompterPiPContentView(frame: CGRect(x: 0, y: 0, width: pipWidth, height: pipHeight))
        contentView.isDarkMode = isDarkMode
        contentView.cueColor = settings.cueColor
        self.teleprompterContentView = contentView

        // Create a host view controller
        let hostVC = UIViewController()
        hostVC.view.addSubview(contentView)
        contentView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            contentView.topAnchor.constraint(equalTo: hostVC.view.topAnchor),
            contentView.bottomAnchor.constraint(equalTo: hostVC.view.bottomAnchor),
            contentView.leadingAnchor.constraint(equalTo: hostVC.view.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: hostVC.view.trailingAnchor)
        ])

        // Sits over the mirrored script doing nothing until the hand-back, when
        // it takes on a blur to soften the script as it goes.
        let blurView = UIVisualEffectView(effect: nil)
        blurView.isUserInteractionEnabled = false
        // The blur is tinted for the interface style it resolves against, and
        // the teleprompter's theme is the app's, not necessarily the system's.
        blurView.overrideUserInterfaceStyle = isDarkMode ? .dark : .light
        blurView.translatesAutoresizingMaskIntoConstraints = false
        hostVC.view.addSubview(blurView)
        NSLayoutConstraint.activate([
            blurView.topAnchor.constraint(equalTo: hostVC.view.topAnchor),
            blurView.bottomAnchor.constraint(equalTo: hostVC.view.bottomAnchor),
            blurView.leadingAnchor.constraint(equalTo: hostVC.view.leadingAnchor),
            blurView.trailingAnchor.constraint(equalTo: hostVC.view.trailingAnchor)
        ])
        self.handBackBlurView = blurView

        // Host the source view in a window behind the app's own. The system
        // animates the overlay out of, and back into, this view's place on
        // screen, so it sits where the script is rather than off-screen —
        // otherwise the overlay flies in from nowhere on the way back.
        let window = UIWindow(windowScene: windowScene)
        sourceFrame = CGRect(
            x: (screenBounds.width - pipWidth) / 2,
            y: (screenBounds.height - pipHeight) / 2,
            width: pipWidth,
            height: pipHeight
        )
        window.frame = sourceFrame
        window.rootViewController = hostVC
        self.pipHostViewController = hostVC
        window.isHidden = false
        window.isUserInteractionEnabled = false
        window.windowLevel = Self.hiddenSourceLevel
        self.pipWindow = window

        // Create the PiP video call view controller
        let pipVC = AVPictureInPictureVideoCallViewController()
        pipVC.preferredContentSize = preferredSize

        // Add content to PiP VC's view
        let pipContent = TeleprompterPiPContentView(frame: .zero)
        pipContent.isDarkMode = isDarkMode
        pipContent.cueColor = settings.cueColor
        pipVC.view.addSubview(pipContent)
        pipContent.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            pipContent.topAnchor.constraint(equalTo: pipVC.view.topAnchor),
            pipContent.bottomAnchor.constraint(equalTo: pipVC.view.bottomAnchor),
            pipContent.leadingAnchor.constraint(equalTo: pipVC.view.leadingAnchor),
            pipContent.trailingAnchor.constraint(equalTo: pipVC.view.trailingAnchor)
        ])
        self.pipContentView = pipContent
        self.pipViewController = pipVC

        // Create the PiP controller with video call content source
        let contentSource = AVPictureInPictureController.ContentSource(
            activeVideoCallSourceView: contentView,
            contentViewController: pipVC
        )

        let controller = AVPictureInPictureController(contentSource: contentSource)
        controller.delegate = self
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        self.pipController = controller

        // Check if PiP is possible after setup
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.isPiPPossible = controller.isPictureInPicturePossible
        }

        // Start rendering
        startDisplayLink()
        updateContentView()
    }

    // MARK: - Hand-back Transition

    /// The window the app itself is drawn in, as opposed to the one holding the
    /// mirrored script.
    private func foregroundAppWindow() -> UIWindow? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first
        return scene?.windows.first(where: { $0 !== pipWindow && !$0.isHidden && $0.windowLevel == .normal })
    }

    /// Put the app itself where the overlay is about to land, so the system's
    /// own animation is the whole transition.
    ///
    /// The overlay always opens into the source view. Left at its running size
    /// that is a rectangle in the middle of the screen, so the return reads as
    /// three separate moves — the overlay grows to the middle, the app arrives
    /// behind it, and the leftover rectangle is cleared. Widening the source to
    /// the whole screen and filling it with a picture of the teleprompter makes
    /// those one move: the overlay opens straight out into the script, and what
    /// it lands on is what is already underneath.
    private func prepareHandBackToApp() -> Bool {
        guard let window = pipWindow,
              let hostView = pipHostViewController?.view,
              let appWindow = foregroundAppWindow(),
              appWindow.bounds.width > 0,
              let snapshot = appWindow.snapshotView(afterScreenUpdates: true) else { return false }

        handBackAnimator?.stopAnimation(true)
        handBackAnimator = nil
        window.layer.removeAllAnimations()
        window.alpha = 1
        window.transform = .identity
        handBackBlurView?.effect = nil

        handBackSnapshot?.removeFromSuperview()
        snapshot.translatesAutoresizingMaskIntoConstraints = false
        hostView.addSubview(snapshot)
        NSLayoutConstraint.activate([
            snapshot.topAnchor.constraint(equalTo: hostView.topAnchor),
            snapshot.bottomAnchor.constraint(equalTo: hostView.bottomAnchor),
            snapshot.leadingAnchor.constraint(equalTo: hostView.leadingAnchor),
            snapshot.trailingAnchor.constraint(equalTo: hostView.trailingAnchor)
        ])
        handBackSnapshot = snapshot

        window.frame = appWindow.frame
        window.layoutIfNeeded()
        window.windowLevel = Self.visibleSourceLevel
        return true
    }

    /// Take the picture away once the overlay has opened into it. Nothing is
    /// animated: the live teleprompter underneath is the same screen, held at
    /// the same line, so the swap has nothing to show.
    private func finishHandBackToApp() {
        resetSourceWindow()
    }

    /// Bring the mirrored script in front of the app for the closing animation.
    /// The system fades the overlay into this view, so it has to be something
    /// the reader can actually see — behind the app window there is nothing to
    /// fade into and the overlay just blinks out at the end of its travel.
    private func showSourceForHandBack() {
        guard let window = pipWindow else { return }
        handBackAnimator?.stopAnimation(true)
        handBackAnimator = nil
        window.layer.removeAllAnimations()
        window.alpha = 1
        window.transform = .identity
        handBackBlurView?.effect = nil
        window.windowLevel = Self.visibleSourceLevel
    }

    /// Dissolve the mirrored script once the overlay has closed into it. It
    /// keeps opening outward the way it was travelling, goes soft, and then
    /// clears — so the overlay reads as widening into the teleprompter rather
    /// than stopping in the middle of the screen and being cut.
    private func fadeOutSourceAfterHandBack() {
        guard let window = pipWindow, window.windowLevel == Self.visibleSourceLevel else { return }

        let animator = UIViewPropertyAnimator(duration: Self.handBackFadeDuration, curve: .easeOut) { [weak self] in
            window.transform = CGAffineTransform(scaleX: Self.handBackScale, y: Self.handBackScale)
            self?.handBackBlurView?.effect = UIBlurEffect(style: .regular)
        }
        // The blur leads and the script clears behind it, so the words go soft
        // before they go away instead of thinning out while still sharp.
        animator.addAnimations({ window.alpha = 0 }, delayFactor: 0.3)
        animator.addCompletion { [weak self] _ in
            self?.resetSourceWindow()
        }
        handBackAnimator = animator
        animator.startAnimation()
    }

    /// Put the window back behind the app, cancelling a dissolve still in flight.
    private func hideSourceBehindApp() {
        handBackAnimator?.stopAnimation(true)
        handBackAnimator = nil
        pipWindow?.layer.removeAllAnimations()
        resetSourceWindow()
    }

    private func resetSourceWindow() {
        handBackAnimator = nil
        handBackBlurView?.effect = nil
        handBackSnapshot?.removeFromSuperview()
        handBackSnapshot = nil
        isHandingBackToApp = false
        guard let window = pipWindow else { return }
        window.windowLevel = Self.hiddenSourceLevel
        window.alpha = 1
        window.transform = .identity
        if sourceFrame != .zero {
            window.frame = sourceFrame
        }
    }

    // MARK: - Content Rendering

    private func startDisplayLink() {
        displayLink = CADisplayLink(target: self, selector: #selector(updateDisplay))
        displayLink?.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
        displayLink?.add(to: .main, forMode: .common)
    }

    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func updateDisplay() {
        guard isRenderingToPiP || needsContentViewUpdate else { return }
        render()
    }

    private func render() {
        if isPlaying, let startDate = playbackTimerStartDate {
            elapsedTime = elapsedTimeAtPlaybackStart + Date().timeIntervalSince(startDate)
        }
        needsContentViewUpdate = false
        lastRenderTimestamp = CACurrentMediaTime()
        updateContentView()
    }

    private func updateContentView() {
        // Off PiP nothing is on screen, so the mirrored views only need to stay
        // roughly current for the transition instead of tracking every frame.
        if !isRenderingToPiP {
            guard CACurrentMediaTime() - lastSourceRenderTimestamp > 0.1 else { return }
            lastSourceRenderTimestamp = CACurrentMediaTime()
        }

        let fontSize = CGFloat(settings.pipFontSize)
        let remainingTime = timerDuration > 0 ? timerDuration - Int(elapsedTime) : Int(elapsedTime)

        // Show countdown value if counting down (in mm:ss format), otherwise show timer
        let timerText = isCountingDown ? TeleprompterParser.formatTime(countdownValue) : TeleprompterParser.formatTime(remainingTime)

        if !isRenderingToPiP {
            teleprompterContentView?.update(
                text: text,
                fontSize: fontSize,
                isPlaying: isPlaying,
                timerText: timerText,
                timerDuration: timerDuration,
                remainingTime: remainingTime,
                elapsedTime: elapsedTime,
                scriptDuration: scriptDuration,
                isCountingDown: isCountingDown
            )
        }

        pipContentView?.update(
            text: text,
            fontSize: fontSize,
            isPlaying: isPlaying,
            timerText: timerText,
            timerDuration: timerDuration,
            remainingTime: remainingTime,
            elapsedTime: elapsedTime,
            scriptDuration: scriptDuration,
            isCountingDown: isCountingDown
        )
    }

    // MARK: - Scroll Timer
    // Intentionally no internal timer; PiP mirrors the teleprompter state.
}

// MARK: - AVPictureInPictureControllerDelegate

extension TeleprompterPiPManager: AVPictureInPictureControllerDelegate {
    nonisolated func pictureInPictureControllerWillStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        Task { @MainActor in
            isPiPActive = true
            isRenderingToPiP = true
            pipContentView?.isLive = true
            // Start playback timer if already playing when PiP starts
            if isPlaying {
                startPlaybackTimer()
            }
        }
    }

    nonisolated func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        Task { @MainActor in
            isPiPActive = true
        }
    }

    nonisolated func pictureInPictureControllerWillStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        Task { @MainActor in
            stopPlaybackTimer()
            isRenderingToPiP = false
            pipContentView?.isLive = false
            lastSourceRenderTimestamp = 0
            updateContentView()
            // Only when the app is not already standing in for the source. A
            // stop from inside the app never goes through the restore handler,
            // so it still hands back through the mirrored script.
            if !isHandingBackToApp {
                showSourceForHandBack()
            }
        }
    }

    nonisolated func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        Task { @MainActor in
            isPiPActive = false
            onPiPClosed?()
            if isHandingBackToApp {
                finishHandBackToApp()
            } else {
                fadeOutSourceAfterHandBack()
            }
        }
    }

    nonisolated func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, failedToStartPictureInPictureWithError error: Error) {
        Task { @MainActor in
            isPiPActive = false
            isRenderingToPiP = false
            pipContentView?.isLive = false
            stopPlaybackTimer()
            hideSourceBehindApp()
            onPiPClosed?()
        }
    }

    nonisolated func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void) {
        Task { @MainActor in
            onPiPRestoreUI?()
            // Let the teleprompter lay out at the position the overlay is on
            // before the picture of it is taken. The overlay opens into that
            // picture, so it has to be showing the line the reader is on —
            // taken straight away it holds the old position, and the script
            // visibly catches up mid-animation.
            try? await Task.sleep(nanoseconds: 30_000_000)
            isHandingBackToApp = prepareHandBackToApp()
            completionHandler(true)
        }
    }
}

// MARK: - Teleprompter PiP Content View

private class TeleprompterPiPContentView: UIView {
    private let textView = UITextView()
    private let timerLabel = UILabel()
    private let topGradientView = UIView()
    private let bottomGradientView = UIView()
    private var topGradientLayer: CAGradientLayer?
    private var bottomGradientLayer: CAGradientLayer?
    private var lastContentId: String = ""
    private var lastTimerText: String?
    private var lastTimerColor: UIColor?

    /// How far the script scrolls over its whole run, and the text view size it
    /// was measured at. Measured from the laid-out text rather than read back
    /// from the text view every frame — see `refreshScrollRange()`.
    private var scrollRange: CGFloat = 0
    private var scrollRangeSize: CGSize = .zero
    private var textHeight: CGFloat = 0
    private var textHeightWidth: CGFloat = -1
    private var needsScrollRange = true
    /// How far into the script the last update put the reader. Kept so a resize
    /// can put the script back at the same place in the text at the new size.
    private var lastScrollFraction: CGFloat = 0
    /// Set when the position has to be taken up without easing: the first
    /// layout, a rebuild, or a resize.
    private var needsSettle = true

    /// The scroll eases toward its target instead of being written straight to
    /// the text view, the same way the full-screen script does. Playback moves
    /// the target in small steps so the easing is invisible; what it takes out
    /// is the jitter from the target being sampled a moment late whenever the
    /// main thread is busy.
    private static let scrollTimeConstant: Double = 0.12
    private var targetOffset: CGFloat = 0
    private var lastScrollTimestamp: CFTimeInterval = 0

    /// True while this view is the copy showing in the overlay. The mirrored
    /// copy behind the app is only kept roughly current, so it takes positions
    /// straight rather than easing toward them.
    var isLive = false {
        didSet {
            guard isLive != oldValue else { return }
            lastScrollTimestamp = 0
        }
    }

    var isDarkMode: Bool = true {
        didSet {
            lastTimerColor = nil
            updateColors()
        }
    }

    var cueColor: CueColor = .default {
        didSet {
            guard cueColor != oldValue else { return }
            lastContentId = ""
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
    }

    private func setupViews() {
        // Touching the layout manager puts the text view on TextKit 1, where the
        // whole script can be laid out up front. Left on TextKit 2 it lays out
        // only what is on screen and estimates the rest, so the height it
        // reports keeps being revised as the script scrolls — and a position
        // measured as a fraction of that height jumps every time it is.
        _ = textView.layoutManager
        textView.isEditable = false
        textView.isSelectable = false
        textView.isScrollEnabled = true
        textView.showsVerticalScrollIndicator = false
        textView.backgroundColor = .clear
        textView.textContainerInset = UIEdgeInsets(top: 40, left: 12, bottom: 40, right: 12)
        textView.textContainer.lineFragmentPadding = 0
        textView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(textView)

        timerLabel.font = .monospacedDigitSystemFont(ofSize: 14, weight: .bold)
        timerLabel.textAlignment = .center
        timerLabel.layer.cornerRadius = 6
        timerLabel.layer.masksToBounds = true
        timerLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(timerLabel)

        // Setup gradient views for fade effect
        topGradientView.translatesAutoresizingMaskIntoConstraints = false
        topGradientView.isUserInteractionEnabled = false
        addSubview(topGradientView)

        bottomGradientView.translatesAutoresizingMaskIntoConstraints = false
        bottomGradientView.isUserInteractionEnabled = false
        addSubview(bottomGradientView)

        NSLayoutConstraint.activate([
            timerLabel.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            timerLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            timerLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 50),
            timerLabel.heightAnchor.constraint(equalToConstant: 24),

            textView.topAnchor.constraint(equalTo: timerLabel.bottomAnchor, constant: 4),
            textView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            textView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            textView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),

            // Top gradient - starts at top of textView
            topGradientView.topAnchor.constraint(equalTo: textView.topAnchor),
            topGradientView.leadingAnchor.constraint(equalTo: textView.leadingAnchor),
            topGradientView.trailingAnchor.constraint(equalTo: textView.trailingAnchor),
            topGradientView.heightAnchor.constraint(equalToConstant: 40),

            // Bottom gradient
            bottomGradientView.bottomAnchor.constraint(equalTo: textView.bottomAnchor),
            bottomGradientView.leadingAnchor.constraint(equalTo: textView.leadingAnchor),
            bottomGradientView.trailingAnchor.constraint(equalTo: textView.trailingAnchor),
            bottomGradientView.heightAnchor.constraint(equalToConstant: 40)
        ])

        updateColors()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        topGradientLayer?.frame = topGradientView.bounds
        bottomGradientLayer?.frame = bottomGradientView.bounds
        refreshScrollRange()
    }

    /// Measure how far the script scrolls, laying the whole of it out to do it.
    /// The measurement only has to be redone when the text view changes size,
    /// and the text itself only when the width changes — a taller or shorter
    /// window reads the same lines.
    private func refreshScrollRange() {
        let size = textView.bounds.size
        guard size.width > 0, size.height > 0 else { return }
        guard needsScrollRange || size != scrollRangeSize else { return }
        needsScrollRange = false
        scrollRangeSize = size

        if textHeightWidth != size.width {
            textHeightWidth = size.width
            // On TextKit 1 this lays the whole script out to answer, which is the
            // point: the height comes back exact and stays put, instead of being
            // an estimate that gets revised as the script scrolls.
            textHeight = textView.sizeThatFits(
                CGSize(width: size.width, height: .greatestFiniteMagnitude)
            ).height
        }

        scrollRange = max(0, textHeight - size.height)
        // A resize keeps the reader on the same part of the script rather than
        // easing across to it from where the old size had them.
        settleScroll(at: lastScrollFraction * scrollRange)
    }

    private func updateColors() {
        let bgColor = isDarkMode ? AppColors.UIColors.Dark.background : AppColors.UIColors.Light.background
        backgroundColor = bgColor
        textView.textColor = isDarkMode ? AppColors.UIColors.Dark.textPrimary : AppColors.UIColors.Light.textPrimary

        // Update top gradient (fades from background to transparent)
        topGradientLayer?.removeFromSuperlayer()
        let topGradient = CAGradientLayer()
        topGradient.colors = [bgColor.cgColor, bgColor.withAlphaComponent(0).cgColor]
        topGradient.locations = [0.0, 1.0]
        topGradient.startPoint = CGPoint(x: 0.5, y: 0.0)
        topGradient.endPoint = CGPoint(x: 0.5, y: 1.0)
        topGradient.frame = topGradientView.bounds
        topGradientView.layer.addSublayer(topGradient)
        topGradientLayer = topGradient

        // Update bottom gradient (fades from transparent to background)
        bottomGradientLayer?.removeFromSuperlayer()
        let bottomGradient = CAGradientLayer()
        bottomGradient.colors = [bgColor.withAlphaComponent(0).cgColor, bgColor.cgColor]
        bottomGradient.locations = [0.0, 1.0]
        bottomGradient.startPoint = CGPoint(x: 0.5, y: 0.0)
        bottomGradient.endPoint = CGPoint(x: 0.5, y: 1.0)
        bottomGradient.frame = bottomGradientView.bounds
        bottomGradientView.layer.addSublayer(bottomGradient)
        bottomGradientLayer = bottomGradient
    }

    func update(
        text: String,
        fontSize: CGFloat,
        isPlaying: Bool,
        timerText: String,
        timerDuration: Int,
        remainingTime: Int,
        elapsedTime: Double,
        scriptDuration: Double,
        isCountingDown: Bool = false
    ) {
        let needsFullRebuild = lastContentId != text

        if needsFullRebuild {
            textView.attributedText = buildAttributedString(text: text, fontSize: fontSize)
            textView.layoutIfNeeded()
            lastContentId = text
            lastTimerText = nil
            lastTimerColor = nil
            textHeightWidth = -1
            needsScrollRange = true
            needsSettle = true
        }

        // Continuous time-based scroll
        refreshScrollRange()
        updateContinuousScroll(elapsedTime: elapsedTime, scriptDuration: scriptDuration)

        if lastTimerText != timerText {
            lastTimerText = timerText
            timerLabel.text = " \(timerText) "
        }

        let timerColor: UIColor
        if isCountingDown {
            timerColor = isDarkMode ? AppColors.UIColors.Dark.pink : AppColors.UIColors.Light.pink
        } else {
            timerColor = AppColors.timerUIColor(
                remainingSeconds: remainingTime,
                totalSeconds: timerDuration,
                isDarkMode: isDarkMode
            )
        }
        if lastTimerColor != timerColor {
            lastTimerColor = timerColor
            timerLabel.textColor = timerColor
            timerLabel.backgroundColor = (isDarkMode ? AppColors.UIColors.Dark.background : AppColors.UIColors.Light.background).withAlphaComponent(0.8)
        }
    }

    private func updateContinuousScroll(elapsedTime: Double, scriptDuration: Double) {
        guard scriptDuration > 0 else { return }

        lastScrollFraction = CGFloat(min(max(elapsedTime / scriptDuration, 0), 1))
        let targetY = lastScrollFraction * scrollRange

        if needsSettle || !isLive {
            needsSettle = false
            settleScroll(at: targetY)
        } else {
            ease(to: targetY)
        }
    }

    /// Take the position up without easing, for a first layout, a rebuild or a
    /// resize — nothing the reader should see the script travel across.
    private func settleScroll(at offset: CGFloat) {
        targetOffset = offset
        lastScrollTimestamp = 0
        guard textView.contentOffset.y != offset else { return }
        textView.contentOffset = CGPoint(x: 0, y: offset)
    }

    /// Move a step of the way toward the target, by however much time has passed
    /// since the last one. This rides the overlay's own render clock rather than
    /// a display link of its own: the display link stops once the app is in the
    /// background, and the overlay carries on from a timer there.
    private func ease(to offset: CGFloat) {
        targetOffset = offset

        let now = CACurrentMediaTime()
        let elapsed = lastScrollTimestamp == 0 ? 0 : now - lastScrollTimestamp
        lastScrollTimestamp = now
        guard elapsed > 0 else { return }

        let distance = targetOffset - textView.contentOffset.y
        guard abs(distance) > 0.05 else {
            textView.contentOffset = CGPoint(x: 0, y: targetOffset)
            return
        }

        let advance = distance * (1 - exp(-elapsed / Self.scrollTimeConstant))
        textView.contentOffset = CGPoint(x: 0, y: textView.contentOffset.y + advance)
    }

    private func buildAttributedString(
        text: String,
        fontSize: CGFloat
    ) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let font = UIFont.systemFont(ofSize: fontSize, weight: .medium)
        let noteFont = UIFont.systemFont(ofSize: fontSize * 0.72, weight: .semibold)
        let noteKern = fontSize * 0.05

        let textColor = isDarkMode ? AppColors.UIColors.Dark.textPrimary : AppColors.UIColors.Light.textPrimary

        let paragraphs = text.components(separatedBy: "\n\n")

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

                let segments = TeleprompterParser.segments(in: line)
                var lineWordIndex = 0

                for segment in segments {
                    switch segment {
                    case .cue(let noteContent):
                        let noteAttrs: [NSAttributedString.Key: Any] = [
                            .font: noteFont,
                            .foregroundColor: cueColor.uiColor(isDarkMode: isDarkMode),
                            .kern: noteKern
                        ]
                        let noteWords = noteContent.split(separator: " ", omittingEmptySubsequences: true)
                        for word in noteWords {
                            if lineWordIndex > 0 {
                                result.append(NSAttributedString(string: " ", attributes: noteAttrs))
                            }
                            result.append(NSAttributedString(string: String(word), attributes: noteAttrs))
                            lineWordIndex += 1
                        }
                    case .text(let textContent):
                        let wordAttrs: [NSAttributedString.Key: Any] = [
                            .font: font,
                            .foregroundColor: textColor
                        ]
                        let words = textContent.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
                        for word in words {
                            if lineWordIndex > 0 {
                                result.append(NSAttributedString(string: " ", attributes: wordAttrs))
                            }
                            result.append(NSAttributedString(string: word, attributes: wordAttrs))
                            lineWordIndex += 1
                        }
                    }
                }
            }
        }

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = fontSize * 0.18
        paragraphStyle.paragraphSpacing = fontSize * 0.45
        if result.length > 0 {
            result.addAttribute(.paragraphStyle, value: paragraphStyle, range: NSRange(location: 0, length: result.length))
        }

        return result
    }
}
