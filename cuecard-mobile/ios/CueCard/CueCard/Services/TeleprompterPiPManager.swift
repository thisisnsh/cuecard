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
    private(set) var currentWordIndex: Int = 0
    private(set) var isDarkMode: Bool = true
    private(set) var totalWords: Int = 0
    private(set) var countdownValue: Int = 0
    private(set) var isCountingDown: Bool = false

    // MARK: - PiP Components

    private var pipController: AVPictureInPictureController?
    private var pipViewController: AVPictureInPictureVideoCallViewController?
    private var teleprompterContentView: TeleprompterPiPContentView?
    private var pipContentView: TeleprompterPiPContentView?
    private var pipWindow: UIWindow?

    // MARK: - Timers

    private var displayLink: CADisplayLink?
    private var playbackTimer: Timer?

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
        self.currentWordIndex = 0
        self.isDarkMode = colorScheme == .dark

        let parsedContent = TeleprompterParser.parseNotes(text)
        totalWords = parsedContent.words.count

        setupPiP()
    }

    /// Update current state from TeleprompterView
    func updateState(elapsedTime: Double, isPlaying: Bool, currentWordIndex: Int = 0, countdownValue: Int = 0, isCountingDown: Bool = false) {
        self.elapsedTime = elapsedTime
        self.isPlaying = isPlaying
        self.currentWordIndex = currentWordIndex
        self.countdownValue = countdownValue
        self.isCountingDown = isCountingDown
        updateContentView()
    }

    /// Start PiP mode
    func startPiP(minimizeApp: Bool = false) {
        guard let pipController = pipController else {
            print("PiP controller not available")
            return
        }

        guard pipController.isPictureInPicturePossible else {
            print("PiP is not possible")
            return
        }

        pipController.startPictureInPicture()

        if minimizeApp {
            // Minimize the app after a short delay to let PiP start
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self.minimizeApp()
            }
        }
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
        currentWordIndex = 0
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
        let interval = 1.0 / 30.0
        playbackTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self, self.isPlaying else { return }
                self.elapsedTime += interval
                self.updateCurrentWordIndex()
                self.updateContentView()
            }
        }
    }

    private func stopPlaybackTimer() {
        playbackTimer?.invalidate()
        playbackTimer = nil
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
        elapsedTime = min(elapsedTime + 10, timerDuration > 0 ? Double(timerDuration + 60) : 3600)
        updateCurrentWordIndex()
        updateContentView()
    }

    /// Seek backward 10 seconds
    func seekBackward() {
        elapsedTime = max(elapsedTime - 10, 0)
        updateCurrentWordIndex()
        updateContentView()
    }

    /// Cleanup resources
    func cleanup() {
        stopDisplayLink()
        stopPlaybackTimer()
        pipController?.stopPictureInPicture()
        pipController = nil
        pipViewController = nil
        teleprompterContentView?.removeFromSuperview()
        teleprompterContentView = nil
        pipContentView?.removeFromSuperview()
        pipContentView = nil
        pipWindow?.isHidden = true
        pipWindow = nil
        isPiPActive = false
    }

    // MARK: - PiP Setup

    private func setupPiP() {
        guard AVPictureInPictureController.isPictureInPictureSupported() else {
            print("PiP not supported on this device")
            isPiPPossible = false
            return
        }

        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene else {
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

        // Create a hidden window to host the source view
        let window = UIWindow(windowScene: windowScene)
        window.frame = CGRect(x: -1000, y: -1000, width: pipWidth, height: pipHeight)
        window.rootViewController = hostVC
        window.isHidden = false
        window.windowLevel = .normal - 1
        self.pipWindow = window

        // Create the PiP video call view controller
        let pipVC = AVPictureInPictureVideoCallViewController()
        pipVC.preferredContentSize = preferredSize

        // Add content to PiP VC's view
        let pipContent = TeleprompterPiPContentView(frame: .zero)
        pipContent.isDarkMode = isDarkMode
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

    // MARK: - Content Rendering

    private func startDisplayLink() {
        displayLink = CADisplayLink(target: self, selector: #selector(updateDisplay))
        displayLink?.preferredFrameRateRange = CAFrameRateRange(minimum: 15, maximum: 30)
        displayLink?.add(to: .main, forMode: .common)
    }

    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func updateDisplay() {
        updateContentView()
    }

    private func updateContentView() {
        let fontSize = CGFloat(settings.pipFontSize)
        let remainingTime = timerDuration > 0 ? timerDuration - Int(elapsedTime) : Int(elapsedTime)

        // Show countdown value if counting down (in mm:ss format), otherwise show timer
        let timerText = isCountingDown ? TeleprompterParser.formatTime(countdownValue) : TeleprompterParser.formatTime(remainingTime)

        let wordsPerSecond = Double(settings.wordsPerMinute) / 60.0
        let highlightProgress = settings.autoScroll
            ? ((elapsedTime == 0 && !isPlaying) ? -Double.greatestFiniteMagnitude : (elapsedTime * wordsPerSecond))
            : Double.greatestFiniteMagnitude

        teleprompterContentView?.update(
            text: text,
            fontSize: fontSize,
            isPlaying: isPlaying,
            timerText: timerText,
            timerDuration: timerDuration,
            remainingTime: remainingTime,
            currentWordIndex: currentWordIndex,
            highlightProgress: highlightProgress,
            autoScroll: settings.autoScroll,
            isCountingDown: isCountingDown
        )

        pipContentView?.update(
            text: text,
            fontSize: fontSize,
            isPlaying: isPlaying,
            timerText: timerText,
            timerDuration: timerDuration,
            remainingTime: remainingTime,
            currentWordIndex: currentWordIndex,
            highlightProgress: highlightProgress,
            autoScroll: settings.autoScroll,
            isCountingDown: isCountingDown
        )
    }

    private func updateCurrentWordIndex() {
        guard totalWords > 0 else {
            currentWordIndex = 0
            return
        }
        let wordsPerSecond = Double(settings.wordsPerMinute) / 60.0
        let newWordIndex = min(Int(Double(elapsedTime) * wordsPerSecond), totalWords - 1)
        currentWordIndex = max(newWordIndex, 0)
    }

    // MARK: - Scroll Timer
    // Intentionally no internal timer; PiP mirrors the teleprompter state.
}

// MARK: - AVPictureInPictureControllerDelegate

extension TeleprompterPiPManager: AVPictureInPictureControllerDelegate {
    nonisolated func pictureInPictureControllerWillStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        Task { @MainActor in
            isPiPActive = true
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
        }
    }

    nonisolated func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        Task { @MainActor in
            isPiPActive = false
            onPiPClosed?()
        }
    }

    nonisolated func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void) {
        Task { @MainActor in
            onPiPRestoreUI?()
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
    private var lastWordIndex: Int = -1
    private var lastProgressBucket: Double = -1

    var isDarkMode: Bool = true {
        didSet {
            updateColors()
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
        currentWordIndex: Int,
        highlightProgress: Double,
        autoScroll: Bool,
        isCountingDown: Bool = false
    ) {
        let contentId = text
        let progressBucket = (highlightProgress * 10).rounded(.down) / 10
        let needsFullRebuild = lastContentId != contentId
        let needsHighlightUpdate = lastWordIndex != currentWordIndex || lastProgressBucket != progressBucket

        if needsFullRebuild || needsHighlightUpdate {
            let savedOffset = textView.contentOffset
            textView.attributedText = buildAttributedString(
                text: text,
                fontSize: fontSize,
                currentWordIndex: currentWordIndex,
                highlightProgress: highlightProgress
            )
            textView.layoutIfNeeded()

            if needsFullRebuild {
                textView.contentOffset = .zero
            } else {
                textView.setContentOffset(savedOffset, animated: false)
            }

            lastContentId = contentId
            lastWordIndex = currentWordIndex
            lastProgressBucket = progressBucket
        }

        if autoScroll && currentWordIndex > 0 {
            let wordRanges = getWordRanges(from: text)
            if currentWordIndex < wordRanges.count {
                let range = wordRanges[currentWordIndex]
                let glyphRange = textView.layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
                let rect = textView.layoutManager.boundingRect(forGlyphRange: glyphRange, in: textView.textContainer)

                let targetY = rect.origin.y + textView.textContainerInset.top - (textView.bounds.height / 3)
                let maxY = textView.contentSize.height - textView.bounds.height
                let scrollY = max(0, min(targetY, maxY))

                UIView.animate(withDuration: 0.55, delay: 0, options: [.curveEaseInOut, .allowUserInteraction]) {
                    self.textView.contentOffset = CGPoint(x: 0, y: scrollY)
                }
            }
        }

        timerLabel.text = " \(timerText) "
        if isCountingDown {
            timerLabel.textColor = isDarkMode ? AppColors.UIColors.Dark.pink : AppColors.UIColors.Light.pink
        } else {
            timerLabel.textColor = AppColors.timerUIColor(
                remainingSeconds: remainingTime,
                totalSeconds: timerDuration,
                isDarkMode: isDarkMode
            )
        }
        timerLabel.backgroundColor = (isDarkMode ? AppColors.UIColors.Dark.background : AppColors.UIColors.Light.background).withAlphaComponent(0.8)
    }

    private func buildAttributedString(
        text: String,
        fontSize: CGFloat,
        currentWordIndex: Int,
        highlightProgress: Double
    ) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let font = UIFont.systemFont(ofSize: fontSize, weight: .medium)
        let noteFont = UIFont.systemFont(ofSize: fontSize * 0.72, weight: .semibold)
        let noteKern = fontSize * 0.05
        let fadeRange = 2.0

        func smoothstep(_ edge0: Double, _ edge1: Double, _ x: Double) -> Double {
            let t = min(max((x - edge0) / (edge1 - edge0), 0.0), 1.0)
            return t * t * (3.0 - 2.0 * t)
        }

        func highlightAlpha(for index: Int) -> CGFloat {
            let distance = highlightProgress - Double(index)
            let blend = smoothstep(-fadeRange, 0.0, distance)
            return 0.3 + CGFloat(blend) * 0.7
        }

        let textColor = isDarkMode ? AppColors.UIColors.Dark.textPrimary : AppColors.UIColors.Light.textPrimary
        let pinkColor = isDarkMode ? AppColors.UIColors.Dark.pink : AppColors.UIColors.Light.pink

        var globalWordIndex = 0
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

                if line.contains("[note") {
                    let noteContent = extractNoteContent(from: line)
                    let noteAttrs: [NSAttributedString.Key: Any] = [
                        .font: noteFont,
                        .foregroundColor: pinkColor,
                        .kern: noteKern
                    ]
                    let noteWords = noteContent.split(separator: " ", omittingEmptySubsequences: true)
                    for (wordIndex, word) in noteWords.enumerated() {
                        if wordIndex > 0 {
                            result.append(NSAttributedString(string: " ", attributes: noteAttrs))
                        }
                        result.append(NSAttributedString(string: String(word), attributes: noteAttrs))
                        globalWordIndex += 1
                    }
                } else {
                    let words = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)

                    for (wordIndex, word) in words.enumerated() {
                        if wordIndex > 0 {
                            result.append(NSAttributedString(string: " ", attributes: [
                                .font: font,
                                .foregroundColor: textColor
                            ]))
                        }

                        let alpha = highlightAlpha(for: globalWordIndex)
                        let color = textColor.withAlphaComponent(alpha)

                        let attrs: [NSAttributedString.Key: Any] = [
                            .font: font,
                            .foregroundColor: color
                        ]
                        result.append(NSAttributedString(string: word, attributes: attrs))

                        globalWordIndex += 1
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

    private func getWordRanges(from text: String) -> [NSRange] {
        var ranges: [NSRange] = []
        let fullText = NSMutableString()
        let paragraphs = text.components(separatedBy: "\n\n")

        for (paragraphIndex, paragraph) in paragraphs.enumerated() {
            if paragraphIndex > 0 {
                fullText.append("\n")
            }

            let lines = paragraph.components(separatedBy: "\n")

            for (lineIndex, line) in lines.enumerated() {
                if lineIndex > 0 {
                    fullText.append("\n")
                }

                if line.isEmpty { continue }

                if line.contains("[note") {
                    let noteContent = extractNoteContent(from: line)
                    let noteWords = noteContent.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
                    for (wordIndex, word) in noteWords.enumerated() {
                        if wordIndex > 0 {
                            fullText.append(" ")
                        }
                        let location = fullText.length
                        fullText.append(word)
                        ranges.append(NSRange(location: location, length: word.count))
                    }
                } else {
                    let words = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)

                    for (wordIndex, word) in words.enumerated() {
                        if wordIndex > 0 {
                            fullText.append(" ")
                        }
                        let location = fullText.length
                        fullText.append(word)
                        ranges.append(NSRange(location: location, length: word.count))
                    }
                }
            }
        }

        return ranges
    }

    private func extractNoteContent(from line: String) -> String {
        let pattern = #"\[note\s+([^\]]+)\]"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              let contentRange = Range(match.range(at: 1), in: line) else {
            return line
        }
        return String(line[contentRange])
    }
}
