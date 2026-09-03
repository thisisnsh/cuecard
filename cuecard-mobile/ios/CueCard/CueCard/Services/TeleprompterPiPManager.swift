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
    /// How the script wrapped on the full screen, and where the cues that hold it
    /// landed. The overlay wraps the same script into more lines than the full
    /// screen does, so it works out its own place from these lines by character
    /// rather than counting lines of its own — the two stay on the same word.
    var geometry = ScriptGeometry()
    /// Where the script was last placed by hand. The overlay keeps its own copy so
    /// it can carry playback on alone while the app is in the background.
    private(set) var playback = ScriptPlayback()
    private(set) var countdownValue: Int = 0
    private(set) var isCountingDown: Bool = false

    // MARK: - PiP Components

    private var pipController: AVPictureInPictureController?
    private var pipViewController: AVPictureInPictureVideoCallViewController?
    private var teleprompterContentView: TeleprompterPiPContentView?
    private var pipContentView: TeleprompterPiPContentView?
    private var pipWindow: UIWindow?
    /// Frosts the mirrored script on the way out. The overlay and the app lay
    /// the same words out at different sizes, so a straight crossfade shows two
    /// scripts at once — going soft first covers the difference.
    private var handBackBlurView: UIVisualEffectView?
    private var handBackAnimator: UIViewPropertyAnimator?

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
    func updateState(
        elapsedTime: Double,
        isPlaying: Bool,
        playback: ScriptPlayback,
        countdownValue: Int = 0,
        isCountingDown: Bool = false
    ) {
        self.elapsedTime = elapsedTime
        self.isPlaying = isPlaying
        self.playback = playback
        self.countdownValue = countdownValue
        self.isCountingDown = isCountingDown
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
        playback = ScriptPlayback()
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
        window.frame = CGRect(
            x: (screenBounds.width - pipWidth) / 2,
            y: (screenBounds.height - pipHeight) / 2,
            width: pipWidth,
            height: pipHeight
        )
        window.rootViewController = hostVC
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
        guard let window = pipWindow else { return }
        window.windowLevel = Self.hiddenSourceLevel
        window.alpha = 1
        window.transform = .identity
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

        // The same sum the full screen does, over the lines the full screen
        // measured — then handed over as a character, which is the one thing the
        // two layouts have in common.
        let position = playback.position(
            at: elapsedTime,
            linesPerMinute: Double(settings.linesPerMinute),
            holds: geometry.holds,
            lineCount: geometry.lineCount
        )
        let character = geometry.map.character(forLine: position.line)

        // Show countdown value if counting down (in mm:ss format), otherwise show timer
        let timerText = isCountingDown ? TeleprompterParser.formatTime(countdownValue) : TeleprompterParser.formatTime(remainingTime)

        if !isRenderingToPiP {
            teleprompterContentView?.update(
                text: text,
                fontSize: fontSize,
                timerText: timerText,
                timerDuration: timerDuration,
                remainingTime: remainingTime,
                characterPosition: character,
                isCountingDown: isCountingDown
            )
        }

        pipContentView?.update(
            text: text,
            fontSize: fontSize,
            timerText: timerText,
            timerDuration: timerDuration,
            remainingTime: remainingTime,
            characterPosition: character,
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
            lastSourceRenderTimestamp = 0
            updateContentView()
            showSourceForHandBack()
        }
    }

    nonisolated func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        Task { @MainActor in
            isPiPActive = false
            onPiPClosed?()
            fadeOutSourceAfterHandBack()
        }
    }

    nonisolated func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, failedToStartPictureInPictureWithError error: Error) {
        Task { @MainActor in
            isPiPActive = false
            isRenderingToPiP = false
            stopPlaybackTimer()
            hideSourceBehindApp()
            onPiPClosed?()
        }
    }

    nonisolated func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void) {
        Task { @MainActor in
            onPiPRestoreUI?()
            // Let the teleprompter lay out at the position the overlay is on
            // before the system animates back into it. Reporting the restore
            // done straight away hands over a screen still showing the old
            // position, and the script visibly catches up mid-animation.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) {
                completionHandler(true)
            }
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
    /// The script as this view has it laid out — its own wrapping, which is much
    /// tighter than the full screen's.
    private var layout = ScriptLayout()
    private var lastRenderKey: String = ""
    private var lastLayoutSize: CGSize = .zero
    private var lastTimerText: String?
    private var lastTimerColor: UIColor?

    var isDarkMode: Bool = true {
        didSet {
            guard isDarkMode != oldValue else { return }
            // The script is drawn in these colors, so it has to be drawn again.
            lastRenderKey = ""
            lastTimerColor = nil
            updateColors()
        }
    }

    var cueColor: CueColor = .default {
        didSet {
            guard cueColor != oldValue else { return }
            lastRenderKey = ""
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
        textView.isEditable = false
        textView.isSelectable = false
        textView.isScrollEnabled = true
        textView.showsVerticalScrollIndicator = false
        textView.backgroundColor = .clear
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
        updateTextInsets()
    }

    /// Hold the reading line at the same height through the overlay as through the
    /// full screen, by insetting the text down to it. A line's own position in the
    /// laid-out text is then the offset that brings it there — see `ScriptLayout`.
    private func updateTextInsets() {
        let height = textView.bounds.height
        guard height > 0 else { return }

        let top = height * TeleprompterLayout.readingLineFraction
        guard abs(textView.textContainerInset.top - top) > 0.5 else { return }

        textView.textContainerInset = UIEdgeInsets(top: top, left: 12, bottom: height - top, right: 12)
        lastLayoutSize = .zero
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
        timerText: String,
        timerDuration: Int,
        remainingTime: Int,
        characterPosition: Double,
        isCountingDown: Bool = false
    ) {
        let renderKey = "\(fontSize)\n\(text)"
        if lastRenderKey != renderKey {
            lastRenderKey = renderKey
            textView.attributedText = TeleprompterScript.render(
                text: text,
                fontSize: fontSize,
                cueColor: cueColor,
                isDarkMode: isDarkMode
            ).attributed
            textView.layoutIfNeeded()
            lastLayoutSize = .zero
            lastTimerText = nil
            lastTimerColor = nil
        }

        scroll(toCharacter: characterPosition)

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

    /// Bring the character the reader is on to the reading line. The full screen
    /// says which character that is; where it falls in the overlay's own, much
    /// narrower lines is this view's business.
    private func scroll(toCharacter character: Double) {
        if lastLayoutSize != textView.bounds.size {
            lastLayoutSize = textView.bounds.size
            layout = ScriptLayout.measure(textView)
        }
        guard !layout.isEmpty else { return }

        let target = layout.offset(forLine: layout.map.line(forCharacter: character))
        let maxY = max(0, textView.contentSize.height - textView.bounds.height)
        let targetY = min(max(target, 0), maxY)

        // The target is an exact function of where the reader is, so track it directly.
        if abs(textView.contentOffset.y - targetY) > 0.01 {
            textView.contentOffset = CGPoint(x: 0, y: targetY)
        }
    }
}
