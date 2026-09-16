import AVKit
import UIKit
import SwiftUI

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

    @Published private(set) var playback = TeleprompterPlaybackState()
    @Published private(set) var isPiPActive = false
    @Published private(set) var isPiPPossible = false

    private var settings: TeleprompterSettings = .default
    private var referenceLineStarts: [Int] = []
    private var clockTimer: Timer?
    private var playbackAnchor: CFTimeInterval?
    private var elapsedAtAnchor: Double = 0
    private var scriptAtAnchor: Double = 0
    private var countdownDeadline: CFTimeInterval?

    private var pipController: AVPictureInPictureController?
    private var videoView: TeleprompterPiPVideoView?
    private var pipWindow: UIWindow?
    private var renderer: TeleprompterVideoRenderer?
    private var timebase: CMTimebase?
    private var possibilityObservation: NSKeyValueObservation?
    private var ownsAudioSession = false
    private var isStartingPiP = false
    private var minimizeWhenStarted = false
    private var lastFrameTime: CFTimeInterval = 0
    private var advertisedPlaybackEnd: Double = 60

    private override init() { super.init() }

    private var linesPerSecond: Double { Double(settings.linesPerMinute) / 60 }
    private var scriptDuration: Double {
        guard linesPerSecond > 0 else { return 0 }
        return Double(max(referenceLineStarts.count - 1, 0)) / linesPerSecond
    }
    private var characterPosition: Double {
        TeleprompterTextLayout.characterPosition(
            forLine: playback.scriptTime * linesPerSecond, starts: referenceLineStarts
        )
    }

    func configure(text: String, settings: TeleprompterSettings, timerDuration: Int, colorScheme: ColorScheme) {
        cleanup()
        self.settings = settings
        playback = TeleprompterPlaybackState()
        referenceLineStarts = []
        renderer = TeleprompterVideoRenderer(text: text, settings: settings,
                                            timerDuration: timerDuration, isDarkMode: colorScheme == .dark)
        setupPiP()
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
        refreshVideoTimeline()
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
        refreshVideoTimeline()
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
        stopClock()
        refreshVideoTimeline()
        renderFrame(force: true)
    }

    func restart() {
        stopClock()
        countdownDeadline = nil
        playbackAnchor = nil
        let nextSnap = playback.snapToken + 1
        playback = TeleprompterPlaybackState(snapToken: nextSnap)
        refreshVideoTimeline()
        renderFrame(force: true)
    }

    /// A drag or native skip changes only the script position, never the timer.
    func seek(toLine line: Double) {
        guard line.isFinite, linesPerSecond > 0 else { return }
        seek(toScriptTime: line / linesPerSecond)
    }

    private func seek(toScriptTime seconds: Double) {
        guard seconds.isFinite else { return }
        advanceClock()
        var state = playback
        state.scriptTime = min(max(seconds, 0), scriptDuration)
        state.snapToken += 1
        playback = state
        reanchorPlayback()
        refreshVideoTimeline()
        renderFrame(force: true)
    }

    private func reanchorPlayback() {
        elapsedAtAnchor = playback.elapsedTime
        scriptAtAnchor = playback.scriptTime
        playbackAnchor = playback.isPlaying ? CACurrentMediaTime() : nil
    }

    private func startClock() {
        guard clockTimer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 30, target: self,
                          selector: #selector(clockTick), userInfo: nil, repeats: true)
        RunLoop.main.add(timer, forMode: .common)
        clockTimer = timer
    }

    private func stopClock() {
        clockTimer?.invalidate()
        clockTimer = nil
    }

    /// Use a monotonic anchor, so delayed callbacks do not slow playback or the
    /// countdown. This clock continues across PiP entry, exit and restoration.
    private func advanceClock() {
        let now = CACurrentMediaTime()
        var state = playback
        var countdownFinished = false
        if let deadline = countdownDeadline {
            if now < deadline {
                state.countdownValue = Int(ceil(deadline - now))
            } else {
                state.isCountingDown = false
                state.countdownValue = 0
                state.isPlaying = true
                state.hasStarted = true
                countdownDeadline = nil
                elapsedAtAnchor = state.elapsedTime
                scriptAtAnchor = state.scriptTime
                playbackAnchor = deadline
                countdownFinished = true
            }
        }
        if state.isPlaying, let anchor = playbackAnchor {
            let elapsed = max(0, now - anchor)
            state.elapsedTime = elapsedAtAnchor + elapsed
            // Deliberately unbounded. Only the rendered text clamps at its last
            // line; reaching it must not pause the video or the session clock.
            state.scriptTime = scriptAtAnchor + elapsed
        }
        if state != playback { playback = state }
        if countdownFinished { refreshVideoTimeline() }
    }

    @objc private func clockTick() {
        advanceClock()
        // Extend the finite seekable range well before AVKit reaches its end.
        // The teleprompter is an open-ended session, not a movie whose duration
        // is the time it takes to reach the last line.
        if let timebase, CMTimebaseGetTime(timebase).seconds > advertisedPlaybackEnd - 30 {
            extendPlaybackRange()
        }
        renderFrame()
    }

    private func extendPlaybackRange() {
        let mediaTime = timebase.map { CMTimebaseGetTime($0).seconds } ?? playback.scriptTime
        advertisedPlaybackEnd = max(scriptDuration, max(playback.scriptTime, mediaTime)) + 120
        pipController?.invalidatePlaybackState()
    }

    private func refreshVideoTimeline() {
        if let timebase {
            CMTimebaseSetTime(timebase, time: CMTime(seconds: playback.scriptTime, preferredTimescale: 600))
            CMTimebaseSetRate(timebase, rate: playback.isPlaying || playback.isCountingDown ? 1 : 0)
        }
        videoView?.sampleBufferDisplayLayer.flush()
        extendPlaybackRange()
    }

    private func renderFrame(force: Bool = false) {
        guard let layer = videoView?.sampleBufferDisplayLayer,
              let renderer, let timebase else { return }
        let now = CACurrentMediaTime()
        // Keep an inline frame ready for automatic PiP, at a lower frame rate.
        // The clock already runs at 30 Hz. Applying another 30 Hz threshold
        // drops otherwise valid frames when a timer callback arrives early.
        let renderingPiP = isPiPActive || isStartingPiP
        guard force || renderingPiP || now - lastFrameTime >= 0.2 else { return }
        if layer.status == .failed { layer.flush() }
        guard layer.isReadyForMoreMediaData else { return }
        guard let frame = renderer.frame(characterPosition: characterPosition, state: playback,
                                          presentationTime: CMTimebaseGetTime(timebase),
                                          smoothScrolling: renderingPiP) else { return }
        layer.enqueue(frame)
        lastFrameTime = now
    }

    @discardableResult
    func startPiP(minimizeApp: Bool = false) -> Bool {
        guard !isPiPActive, !isStartingPiP,
              let controller = pipController, controller.isPictureInPicturePossible else { return false }
        advanceClock()
        renderFrame(force: true)
        minimizeWhenStarted = minimizeApp
        isStartingPiP = true
        controller.startPictureInPicture()
        return true
    }

    func stopPiP() { pipController?.stopPictureInPicture() }

    /// Called when returning to the foreground; there is no state to copy back.
    func refreshPresentation() {
        advanceClock()
        renderFrame(force: true)
    }

    func cleanup() {
        stopClock()
        countdownDeadline = nil
        playbackAnchor = nil
        possibilityObservation = nil
        pipController?.delegate = nil
        pipController?.stopPictureInPicture()
        pipController = nil
        videoView?.sampleBufferDisplayLayer.flushAndRemoveImage()
        videoView = nil
        pipWindow?.isHidden = true
        pipWindow = nil
        renderer = nil
        timebase = nil
        isPiPActive = false
        isPiPPossible = false
        isStartingPiP = false
        minimizeWhenStarted = false
        lastFrameTime = 0
        if ownsAudioSession {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            ownsAudioSession = false
        }
    }

    func disable() { cleanup() }

    private func setupPiP() {
        guard AVPictureInPictureController.isPictureInPictureSupported() else { return }
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first,
              let renderer else { return }

        let host = UIViewController()
        host.view.backgroundColor = renderer.backgroundColor
        let source = TeleprompterPiPVideoView()
        source.sampleBufferDisplayLayer.videoGravity = .resizeAspect
        source.translatesAutoresizingMaskIntoConstraints = false
        host.view.addSubview(source)
        NSLayoutConstraint.activate([
            source.leadingAnchor.constraint(equalTo: host.view.leadingAnchor),
            source.trailingAnchor.constraint(equalTo: host.view.trailingAnchor),
            source.topAnchor.constraint(equalTo: host.view.topAnchor),
            source.bottomAnchor.constraint(equalTo: host.view.bottomAnchor)
        ])
        let bounds = scene.screen.bounds
        let width = min(bounds.width, bounds.height * settings.overlayAspectRatio.ratio)
        let height = width / settings.overlayAspectRatio.ratio
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: bounds.midX - width / 2, y: bounds.midY - height / 2, width: width, height: height)
        window.windowLevel = .normal - 1
        window.isUserInteractionEnabled = false
        window.rootViewController = host
        window.isHidden = false
        host.view.layoutIfNeeded()
        pipWindow = window
        videoView = source

        var mediaTimebase: CMTimebase?
        guard CMTimebaseCreateWithSourceClock(allocator: kCFAllocatorDefault,
                                             sourceClock: CMClockGetHostTimeClock(),
                                             timebaseOut: &mediaTimebase) == noErr,
              let mediaTimebase else {
            cleanup()
            return
        }
        timebase = mediaTimebase
        source.sampleBufferDisplayLayer.controlTimebase = mediaTimebase
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .moviePlayback, options: .mixWithOthers)
            try session.setActive(true)
            ownsAudioSession = true
        } catch {
            print("Could not activate PiP audio session: \(error)")
            cleanup()
            return
        }

        let controller = AVPictureInPictureController(contentSource: .init(
            sampleBufferDisplayLayer: source.sampleBufferDisplayLayer, playbackDelegate: self
        ))
        controller.delegate = self
        controller.requiresLinearPlayback = false
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        pipController = controller
        possibilityObservation = controller.observe(\.isPictureInPicturePossible, options: [.initial, .new]) { [weak self] controller, _ in
            Task { @MainActor in
                guard let self, self.pipController === controller else { return }
                self.isPiPPossible = controller.isPictureInPicturePossible
            }
        }
        refreshVideoTimeline()
        renderFrame(force: true)
    }
}

extension TeleprompterPiPManager: @preconcurrency AVPictureInPictureSampleBufferPlaybackDelegate {
    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, setPlaying playing: Bool) {
        guard pipController === pictureInPictureController else { return }
        if playing { play() } else { pause() }
    }

    func pictureInPictureControllerIsPlaybackPaused(_ pictureInPictureController: AVPictureInPictureController) -> Bool {
        !playback.isPlaying && !playback.isCountingDown
    }

    func pictureInPictureControllerTimeRangeForPlayback(_ pictureInPictureController: AVPictureInPictureController) -> CMTimeRange {
        CMTimeRange(start: .zero, duration: CMTime(seconds: advertisedPlaybackEnd, preferredTimescale: 600))
    }

    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, skipByInterval interval: CMTime, completion: @escaping () -> Void) {
        defer { completion() }
        guard pipController === pictureInPictureController, interval.seconds.isFinite else { return }
        advanceClock()
        seek(toScriptTime: min(playback.scriptTime, scriptDuration) + interval.seconds)
    }

    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, didTransitionToRenderSize newRenderSize: CMVideoDimensions) {
        // The video has a fixed logical page and 1280-pixel width. A PiP resize
        // scales that page; it never changes font sizes, wrapping or position.
        guard pipController === pictureInPictureController else { return }
        renderFrame(force: true)
    }
}

extension TeleprompterPiPManager: @preconcurrency AVPictureInPictureControllerDelegate {
    func pictureInPictureControllerWillStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        guard pipController === pictureInPictureController else { return }
        isStartingPiP = true
        advanceClock()
        renderFrame(force: true)
    }

    func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        guard pipController === pictureInPictureController else { return }
        isStartingPiP = false
        isPiPActive = true
        renderFrame(force: true)
        if minimizeWhenStarted {
            minimizeWhenStarted = false
            UIApplication.shared.perform(#selector(NSXPCConnection.suspend))
        }
    }

    func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        guard pipController === pictureInPictureController else { return }
        isPiPActive = false
        isStartingPiP = false
        minimizeWhenStarted = false
        refreshPresentation()
    }

    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, failedToStartPictureInPictureWithError error: Error) {
        guard pipController === pictureInPictureController else { return }
        isStartingPiP = false
        isPiPActive = false
        minimizeWhenStarted = false
        print("Could not start PiP: \(error)")
    }

    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void) {
        guard pipController === pictureInPictureController else {
            completionHandler(false)
            return
        }
        advanceClock()
        var state = playback
        state.snapToken += 1
        playback = state
        // Give SwiftUI one main-queue pass to place the shared reading position.
        DispatchQueue.main.async { completionHandler(true) }
    }
}

private final class TeleprompterPiPVideoView: UIView {
    override class var layerClass: AnyClass { AVSampleBufferDisplayLayer.self }
    var sampleBufferDisplayLayer: AVSampleBufferDisplayLayer { layer as! AVSampleBufferDisplayLayer }
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

/// Draw glyphs directly into the video buffer. Capturing a UITextView's layers
/// captures cached raster tiles, which can be low-resolution or stale offscreen.
@MainActor
private final class TeleprompterVideoRenderer {
    let backgroundColor: UIColor
    private let logicalSize: CGSize
    private let pixelWidth = 1280
    private let pixelHeight: Int
    private let textStorage: NSTextStorage
    private let layoutManager = NSLayoutManager()
    private let textContainer: NSTextContainer
    private var lineStarts: [Int] = []
    private var lineOffsets: [CGFloat] = []
    private let timerDuration: Int
    private let isDarkMode: Bool
    private var pool: CVPixelBufferPool?
    private var format: CMVideoFormatDescription?
    private var displayedOffset: CGFloat?
    private var lastScrollFrameTime: CFTimeInterval = 0
    private var lastSnapToken: Int = -1
    // Match the full-screen scroll response while keeping the shared reading
    // position authoritative. Only the displayed offset is smoothed.
    private static let scrollTimeConstant: Double = 0.12

    init(text: String, settings: TeleprompterSettings, timerDuration: Int, isDarkMode: Bool) {
        self.timerDuration = timerDuration
        self.isDarkMode = isDarkMode
        backgroundColor = isDarkMode ? AppColors.UIColors.Dark.background : AppColors.UIColors.Light.background
        logicalSize = CGSize(width: 320, height: 320 / settings.overlayAspectRatio.ratio)
        pixelHeight = Int((1280 / settings.overlayAspectRatio.ratio).rounded())
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

    func frame(characterPosition: Double, state: TeleprompterPlaybackState, presentationTime: CMTime,
               smoothScrolling: Bool) -> CMSampleBuffer? {
        if pool == nil {
            let attributes: [CFString: Any] = [
                kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey: pixelWidth,
                kCVPixelBufferHeightKey: pixelHeight,
                kCVPixelBufferCGBitmapContextCompatibilityKey: true,
                kCVPixelBufferIOSurfacePropertiesKey: [:]
            ]
            guard CVPixelBufferPoolCreate(kCFAllocatorDefault, nil, attributes as CFDictionary, &pool) == kCVReturnSuccess else { return nil }
        }
        guard let pool else { return nil }
        var buffer: CVPixelBuffer?
        let limits = [kCVPixelBufferPoolAllocationThresholdKey: 3] as CFDictionary
        guard CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(kCFAllocatorDefault, pool, limits, &buffer) == kCVReturnSuccess,
              let buffer else { return nil }
        guard CVPixelBufferLockBaseAddress(buffer, []) == kCVReturnSuccess else { return nil }
        let drewFrame: Bool
        if let context = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: pixelWidth, height: pixelHeight,
                                   bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                                   space: CGColorSpaceCreateDeviceRGB(),
                                   bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue) {
            context.translateBy(x: 0, y: CGFloat(pixelHeight))
            context.scaleBy(x: CGFloat(pixelWidth) / logicalSize.width, y: -CGFloat(pixelHeight) / logicalSize.height)
            UIGraphicsPushContext(context)
            draw(in: context, characterPosition: characterPosition, state: state, smoothScrolling: smoothScrolling)
            UIGraphicsPopContext()
            drewFrame = true
        } else {
            drewFrame = false
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])
        guard drewFrame else { return nil }
        if format == nil {
            guard CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: buffer,
                                                               formatDescriptionOut: &format) == noErr else { return nil }
        }
        guard let format else { return nil }
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 30),
                                        presentationTimeStamp: presentationTime, decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        guard CMSampleBufferCreateReadyWithImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: buffer,
                                                       formatDescription: format, sampleTiming: &timing,
                                                       sampleBufferOut: &sample) == noErr, let sample else { return nil }
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: true) {
            let dictionary = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
            CFDictionarySetValue(dictionary, Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                                 Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
        }
        return sample
    }

    private func draw(in context: CGContext, characterPosition: Double, state: TeleprompterPlaybackState,
                      smoothScrolling: Bool) {
        context.setFillColor(backgroundColor.cgColor)
        context.fill(CGRect(origin: .zero, size: logicalSize))
        let remaining = timerDuration > 0 ? timerDuration - Int(state.elapsedTime) : Int(state.elapsedTime)
        let time = TeleprompterParser.formatTime(state.isCountingDown ? state.countdownValue : remaining)
        let color = state.isCountingDown
            ? (isDarkMode ? AppColors.UIColors.Dark.pink : AppColors.UIColors.Light.pink)
            : AppColors.timerUIColor(remainingSeconds: remaining, totalSeconds: timerDuration, isDarkMode: isDarkMode)
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        (time as NSString).draw(in: CGRect(x: 12, y: 6, width: 296, height: 22), withAttributes: [
            .font: UIFont.monospacedDigitSystemFont(ofSize: 14, weight: .semibold),
            .foregroundColor: color,
            .paragraphStyle: style
        ])

        let viewport = CGRect(x: 12, y: 34, width: 296, height: logicalSize.height - 42)
        let readingY = viewport.height * 0.45
        let position = TeleprompterTextLayout.linePosition(forCharacter: characterPosition, starts: lineStarts)
        let line = min(Int(position), max(lineOffsets.count - 1, 0))
        var offset: CGFloat = 0
        if !lineOffsets.isEmpty {
            offset = lineOffsets[line]
            if line + 1 < lineOffsets.count {
                offset += CGFloat(position - Double(line)) * (lineOffsets[line + 1] - lineOffsets[line])
            }
        }
        offset = scrollOffset(toward: offset, state: state, smoothScrolling: smoothScrolling)
        context.saveGState()
        context.clip(to: viewport)
        context.translateBy(x: viewport.minX, y: viewport.minY + readingY - offset)
        let visibleRect = CGRect(x: 0, y: offset - readingY, width: viewport.width, height: viewport.height)
        let glyphs = layoutManager.glyphRange(forBoundingRect: visibleRect, in: textContainer)
        layoutManager.drawBackground(forGlyphRange: glyphs, at: .zero)
        layoutManager.drawGlyphs(forGlyphRange: glyphs, at: .zero)
        context.restoreGState()

        let colors = [backgroundColor.cgColor, backgroundColor.withAlphaComponent(0).cgColor] as CFArray
        if let fade = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
            context.saveGState()
            context.clip(to: viewport)
            context.drawLinearGradient(fade, start: CGPoint(x: 0, y: viewport.minY),
                                       end: CGPoint(x: 0, y: viewport.minY + 18), options: [])
            context.drawLinearGradient(fade, start: CGPoint(x: 0, y: viewport.maxY),
                                       end: CGPoint(x: 0, y: viewport.maxY - 18), options: [])
            context.restoreGState()
        }
    }

    private func scrollOffset(toward target: CGFloat, state: TeleprompterPlaybackState,
                              smoothScrolling: Bool) -> CGFloat {
        let now = CACurrentMediaTime()
        defer {
            lastScrollFrameTime = now
            lastSnapToken = state.snapToken
        }
        guard smoothScrolling, state.isPlaying,
              lastSnapToken == state.snapToken, let previous = displayedOffset else {
            // Explicit seeks/restarts and restoration must land at the shared
            // position immediately, without animating through skipped text.
            displayedOffset = target
            return target
        }
        // A delayed frame must not move the whole accumulated distance at once.
        let delta = min(max(now - lastScrollFrameTime, 0), 1.0 / 15.0)
        let distance = target - previous
        let next = abs(distance) < 0.05 ? target
            : previous + distance * CGFloat(1 - exp(-delta / Self.scrollTimeConstant))
        displayedOffset = next
        return next
    }
}
