import AVKit
import UIKit
import CoreMedia
import CoreVideo

/// Segment of teleprompter content with optional timing
struct TeleprompterSegment {
    let text: String
    let durationSeconds: Int?
    let startTimeSeconds: Int
}

/// Manages Picture-in-Picture teleprompter display
@available(iOS 15.0, *)
class TeleprompterPiPManager: NSObject {

    // MARK: - Properties

    private var pipController: AVPictureInPictureController?
    private var displayView: SampleBufferDisplayView?
    private var displayLink: CADisplayLink?

    private var segments: [TeleprompterSegment] = []
    private var currentSegmentIndex: Int = 0
    private var scrollOffset: CGFloat = 0
    private var startTime: Date?
    private var pausedTime: TimeInterval = 0
    private var isPaused: Bool = false

    private var fontSize: CGFloat = 16
    private var defaultScrollSpeed: CGFloat = 50 // pixels per second
    private var opacity: Float = 1.0

    private let pinkColor = UIColor(red: 1.0, green: 0.41, blue: 0.71, alpha: 1.0)
    private let backgroundColor = UIColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1.0)
    private let textColor = UIColor.white
    private let timerColor = UIColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1.0)

    // MARK: - Singleton

    static let shared = TeleprompterPiPManager()

    /// Check if PiP is supported
    static func isPiPSupported() -> Bool {
        return AVPictureInPictureController.isPictureInPictureSupported()
    }

    private override init() {
        super.init()
        setupAudioSession()
    }

    // MARK: - Audio Session (Required for PiP)

    private func setupAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Failed to setup audio session: \(error)")
        }
    }

    // MARK: - Public Methods

    /// Start the teleprompter in PiP mode
    func startTeleprompter(content: String, fontSize: CGFloat, defaultSpeed: CGFloat, opacity: Float) {
        self.fontSize = fontSize
        self.defaultScrollSpeed = defaultSpeed * 50 // Convert speed multiplier to pixels/second
        self.opacity = opacity

        // Parse content into segments
        self.segments = parseContent(content)
        self.currentSegmentIndex = 0
        self.scrollOffset = 0
        self.isPaused = false
        self.pausedTime = 0

        // Create display view
        setupDisplayView()

        // Start rendering
        startTime = Date()
        startDisplayLink()

        // Enter PiP mode
        startPiP()
    }

    /// Pause the teleprompter
    func pause() {
        guard !isPaused, let startTime = startTime else { return }
        isPaused = true
        pausedTime = Date().timeIntervalSince(startTime)
        displayLink?.isPaused = true
    }

    /// Resume the teleprompter
    func resume() {
        guard isPaused else { return }
        isPaused = false
        startTime = Date().addingTimeInterval(-pausedTime)
        displayLink?.isPaused = false
    }

    /// Stop the teleprompter and exit PiP
    func stop() {
        displayLink?.invalidate()
        displayLink = nil
        pipController?.stopPictureInPicture()
        displayView?.removeFromSuperview()
        displayView = nil
    }

    // MARK: - Content Parsing

    private func parseContent(_ content: String) -> [TeleprompterSegment] {
        var segments: [TeleprompterSegment] = []
        var cumulativeTime: Int = 0

        // Regex pattern for [time mm:ss]
        let timePattern = try! NSRegularExpression(pattern: "\\[time\\s+(\\d{1,2}):(\\d{2})\\]", options: [])
        let range = NSRange(content.startIndex..., in: content)

        var lastEnd = content.startIndex
        var pendingDuration: Int? = nil

        timePattern.enumerateMatches(in: content, range: range) { match, _, _ in
            guard let match = match else { return }

            let matchRange = Range(match.range, in: content)!

            // Get text before this [time] tag
            let textBefore = String(content[lastEnd..<matchRange.lowerBound])
            let cleanedText = cleanTextForDisplay(textBefore)

            if !cleanedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                segments.append(TeleprompterSegment(
                    text: cleanedText,
                    durationSeconds: pendingDuration,
                    startTimeSeconds: cumulativeTime
                ))

                if let d = pendingDuration {
                    cumulativeTime += d
                }
            }

            // Parse duration from this [time] tag
            if let minutesRange = Range(match.range(at: 1), in: content),
               let secondsRange = Range(match.range(at: 2), in: content) {
                let minutes = Int(content[minutesRange]) ?? 0
                let seconds = Int(content[secondsRange]) ?? 0
                pendingDuration = minutes * 60 + seconds
            }

            lastEnd = matchRange.upperBound
        }

        // Handle remaining text
        let remainingText = String(content[lastEnd...])
        let cleanedRemaining = cleanTextForDisplay(remainingText)

        if !cleanedRemaining.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            segments.append(TeleprompterSegment(
                text: cleanedRemaining,
                durationSeconds: pendingDuration,
                startTimeSeconds: cumulativeTime
            ))
        }

        // If no segments, create one with all content
        if segments.isEmpty && !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            segments.append(TeleprompterSegment(
                text: cleanTextForDisplay(content),
                durationSeconds: nil,
                startTimeSeconds: 0
            ))
        }

        return segments
    }

    private func cleanTextForDisplay(_ text: String) -> String {
        // Remove [time mm:ss] tags
        let timePattern = try! NSRegularExpression(pattern: "\\[time\\s+\\d{1,2}:\\d{2}\\]", options: [])
        let range = NSRange(text.startIndex..., in: text)
        return timePattern.stringByReplacingMatches(in: text, range: range, withTemplate: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Display Setup

    private func setupDisplayView() {
        displayView = SampleBufferDisplayView(frame: CGRect(x: 0, y: 0, width: 400, height: 300))
        displayView?.backgroundColor = backgroundColor
    }

    private func startPiP() {
        guard AVPictureInPictureController.isPictureInPictureSupported(),
              let displayView = displayView else {
            print("PiP not supported")
            return
        }

        let contentSource = AVPictureInPictureController.ContentSource(
            sampleBufferDisplayLayer: displayView.sampleBufferDisplayLayer,
            playbackDelegate: self
        )

        pipController = AVPictureInPictureController(contentSource: contentSource)
        pipController?.delegate = self
        pipController?.requiresLinearPlayback = true // Hide playback controls

        // Small delay to ensure setup is complete
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.pipController?.startPictureInPicture()
        }
    }

    // MARK: - Rendering

    private func startDisplayLink() {
        displayLink = CADisplayLink(target: self, selector: #selector(renderFrame))
        displayLink?.preferredFramesPerSecond = 30
        displayLink?.add(to: .main, forMode: .common)
    }

    @objc private func renderFrame() {
        guard let displayView = displayView,
              let startTime = startTime else { return }

        let elapsedTime = Date().timeIntervalSince(startTime)

        // Calculate current segment and scroll offset
        var currentSegment: TeleprompterSegment?
        var segmentElapsedTime: TimeInterval = 0
        var accumulatedTime: TimeInterval = 0

        for (index, segment) in segments.enumerated() {
            let segmentDuration = TimeInterval(segment.durationSeconds ?? Int(estimateSegmentDuration(segment)))

            if accumulatedTime + segmentDuration > elapsedTime {
                currentSegment = segment
                currentSegmentIndex = index
                segmentElapsedTime = elapsedTime - accumulatedTime
                break
            }

            accumulatedTime += segmentDuration
        }

        // If we've passed all segments, use the last one
        if currentSegment == nil && !segments.isEmpty {
            currentSegment = segments.last
            currentSegmentIndex = segments.count - 1
        }

        // Render frame
        if let segment = currentSegment {
            let image = renderTeleprompterFrame(
                segment: segment,
                segmentElapsedTime: segmentElapsedTime,
                allSegments: segments,
                currentIndex: currentSegmentIndex
            )

            if let sampleBuffer = createSampleBuffer(from: image) {
                displayView.sampleBufferDisplayLayer.enqueue(sampleBuffer)
            }
        }
    }

    private func estimateSegmentDuration(_ segment: TeleprompterSegment) -> TimeInterval {
        // Estimate based on text length if no explicit duration
        let lineCount = segment.text.components(separatedBy: "\n").count
        let estimatedHeight = CGFloat(lineCount) * fontSize * 1.5
        return TimeInterval(estimatedHeight / defaultScrollSpeed)
    }

    private func renderTeleprompterFrame(
        segment: TeleprompterSegment,
        segmentElapsedTime: TimeInterval,
        allSegments: [TeleprompterSegment],
        currentIndex: Int
    ) -> UIImage {
        let size = CGSize(width: 400, height: 300)
        let renderer = UIGraphicsImageRenderer(size: size)

        return renderer.image { context in
            // Background
            backgroundColor.setFill()
            context.fill(CGRect(origin: .zero, size: size))

            // Calculate scroll offset for this segment
            let segmentDuration = TimeInterval(segment.durationSeconds ?? Int(estimateSegmentDuration(segment)))
            let scrollSpeed: CGFloat

            if let duration = segment.durationSeconds, duration > 0 {
                // Calculate speed based on segment height and duration
                let estimatedHeight = estimateTextHeight(segment.text, width: size.width - 32)
                scrollSpeed = estimatedHeight / CGFloat(duration)
            } else {
                scrollSpeed = defaultScrollSpeed
            }

            let scrollOffset = CGFloat(segmentElapsedTime) * scrollSpeed

            // Render all text with scroll offset
            var yOffset: CGFloat = size.height / 2 - scrollOffset // Start from middle

            // Render previous segments (above current)
            for i in 0..<currentIndex {
                let prevSegment = allSegments[i]
                let height = renderSegmentText(prevSegment.text, at: yOffset, width: size.width - 32, in: context.cgContext)
                yOffset += height + 20
            }

            // Render current segment
            renderSegmentText(segment.text, at: yOffset, width: size.width - 32, in: context.cgContext)

            // Render timer (fixed at top-left)
            if let duration = segment.durationSeconds {
                let remaining = max(0, duration - Int(segmentElapsedTime))
                let minutes = remaining / 60
                let seconds = remaining % 60
                let timerText = String(format: "[%02d:%02d]", minutes, seconds)

                let timerAttributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.monospacedDigitSystemFont(ofSize: 14, weight: .semibold),
                    .foregroundColor: timerColor
                ]

                let timerRect = CGRect(x: 16, y: 16, width: 80, height: 24)

                // Timer background
                UIColor(white: 0, alpha: 0.6).setFill()
                UIBezierPath(roundedRect: timerRect.insetBy(dx: -4, dy: -2), cornerRadius: 4).fill()

                timerText.draw(in: timerRect, withAttributes: timerAttributes)
            }
        }
    }

    @discardableResult
    private func renderSegmentText(_ text: String, at yOffset: CGFloat, width: CGFloat, in context: CGContext) -> CGFloat {
        let notePattern = try! NSRegularExpression(pattern: "\\[note\\s+([^\\]]+)\\]", options: [])
        let range = NSRange(text.startIndex..., in: text)

        let attributedString = NSMutableAttributedString(string: text, attributes: [
            .font: UIFont.systemFont(ofSize: fontSize),
            .foregroundColor: textColor
        ])

        // Highlight [note content] in pink
        notePattern.enumerateMatches(in: text, range: range) { match, _, _ in
            guard let match = match else { return }
            attributedString.addAttribute(.foregroundColor, value: pinkColor, range: match.range)
        }

        // Remove [note ...] brackets, keep content
        var cleanedString = NSMutableAttributedString(attributedString: attributedString)
        let noteMatches = notePattern.matches(in: text, range: range)

        // Replace [note content] with just content (in reverse order to maintain positions)
        for match in noteMatches.reversed() {
            if let fullRange = Range(match.range, in: text),
               let contentRange = Range(match.range(at: 1), in: text) {
                let content = String(text[contentRange])
                let pinkContent = NSAttributedString(string: "[\(content)]", attributes: [
                    .font: UIFont.systemFont(ofSize: fontSize * 0.8, weight: .semibold),
                    .foregroundColor: pinkColor
                ])
                cleanedString.replaceCharacters(in: match.range, with: pinkContent)
            }
        }

        let drawRect = CGRect(x: 16, y: yOffset, width: width, height: 1000)
        cleanedString.draw(in: drawRect)

        return estimateTextHeight(text, width: width)
    }

    private func estimateTextHeight(_ text: String, width: CGFloat) -> CGFloat {
        let font = UIFont.systemFont(ofSize: fontSize)
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let boundingRect = (text as NSString).boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes,
            context: nil
        )
        return ceil(boundingRect.height)
    }

    // MARK: - Sample Buffer Creation

    private func createSampleBuffer(from image: UIImage) -> CMSampleBuffer? {
        guard let cgImage = image.cgImage else { return nil }

        let width = cgImage.width
        let height = cgImage.height

        var pixelBuffer: CVPixelBuffer?
        let attrs: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ]

        CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            attrs as CFDictionary,
            &pixelBuffer
        )

        guard let buffer = pixelBuffer else { return nil }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        )

        context?.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        var formatDescription: CMVideoFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: buffer,
            formatDescriptionOut: &formatDescription
        )

        guard let format = formatDescription else { return nil }

        var sampleTiming = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: 30),
            presentationTimeStamp: CMTime(value: Int64(CACurrentMediaTime() * 1000), timescale: 1000),
            decodeTimeStamp: .invalid
        )

        var sampleBuffer: CMSampleBuffer?
        CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: buffer,
            formatDescription: format,
            sampleTiming: &sampleTiming,
            sampleBufferOut: &sampleBuffer
        )

        return sampleBuffer
    }
}

// MARK: - SampleBufferDisplayView

class SampleBufferDisplayView: UIView {
    override class var layerClass: AnyClass {
        return AVSampleBufferDisplayLayer.self
    }

    var sampleBufferDisplayLayer: AVSampleBufferDisplayLayer {
        return layer as! AVSampleBufferDisplayLayer
    }
}

// MARK: - AVPictureInPictureControllerDelegate

@available(iOS 15.0, *)
extension TeleprompterPiPManager: AVPictureInPictureControllerDelegate {
    func pictureInPictureControllerWillStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        print("PiP will start")
    }

    func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        print("PiP did start")
    }

    func pictureInPictureControllerWillStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        print("PiP will stop")
    }

    func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        print("PiP did stop")
        stop()
    }

    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, failedToStartPictureInPictureWithError error: Error) {
        print("PiP failed to start: \(error)")
    }
}

// MARK: - AVPictureInPictureSampleBufferPlaybackDelegate

@available(iOS 15.0, *)
extension TeleprompterPiPManager: AVPictureInPictureSampleBufferPlaybackDelegate {
    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, setPlaying playing: Bool) {
        if playing {
            resume()
        } else {
            pause()
        }
    }

    func pictureInPictureControllerTimeRangeForPlayback(_ pictureInPictureController: AVPictureInPictureController) -> CMTimeRange {
        // Return total duration if known
        let totalDuration = segments.reduce(0) { $0 + ($1.durationSeconds ?? 60) }
        return CMTimeRange(
            start: .zero,
            duration: CMTime(seconds: Double(totalDuration), preferredTimescale: 1)
        )
    }

    func pictureInPictureControllerIsPlaybackPaused(_ pictureInPictureController: AVPictureInPictureController) -> Bool {
        return isPaused
    }

    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, didTransitionToRenderSize newRenderSize: CMVideoDimensions) {
        // Handle size change
    }

    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, skipByInterval skipInterval: CMTime, completion completionHandler: @escaping () -> Void) {
        completionHandler()
    }
}
