import AVFoundation
import Photos
import UIKit

/// UI state lives on the main actor; capture configuration and file recording
/// are serialized on CameraCapture's queue so starting a camera never blocks UI.
@MainActor
final class CameraRecorder: ObservableObject {
    @Published private(set) var device: AVCaptureDevice?
    @Published private(set) var isReady = false
    @Published private(set) var isRecording = false
    @Published private(set) var isPaused = false
    @Published private(set) var zoom: Double = 1
    @Published private(set) var maxZoom: Double = 1
    private var pausedAt: Date?
    private var pausedDuration: TimeInterval = 0
    @Published private(set) var isBusy = false
    @Published private(set) var startedAt: Date?
    @Published private(set) var pendingURL: URL?
    @Published var message: String?
    @Published private(set) var needsSettings = false
    let capture = CameraCapture()
    private var isVisible = false
    private var isStartingRecording = false
    private var preparationID = UUID()
    private var scriptID: UUID?
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    /// Keeps the recorder alive while a take is saved, even after the reader
    /// it was recorded over has closed.
    private var savingSelf: CameraRecorder?

    init() {
        capture.onEvent = { [weak self] event in
            Task { @MainActor in self?.handle(event) }
        }
        pendingURL = (try? FileManager.default.contentsOfDirectory(
            at: Self.recordingsFolder, includingPropertiesForKeys: nil
        ))?.first(where: { $0.pathExtension == "mov" })
    }

    static var recordingsFolder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PendingRecordings", isDirectory: true)
    }

    func prepare(scriptID: UUID?) async {
        isVisible = true
        self.scriptID = scriptID
        let request = UUID()
        preparationID = request
        if !isRecording, !isBusy, pendingURL == nil {
            pendingURL = (try? FileManager.default.contentsOfDirectory(
                at: Self.recordingsFolder, includingPropertiesForKeys: nil
            ))?.first(where: { $0.pathExtension == "mov" })
        }
        needsSettings = false
        for media in [AVMediaType.video, .audio] {
            let granted: Bool
            switch AVCaptureDevice.authorizationStatus(for: media) {
            case .authorized: granted = true
            case .notDetermined: granted = await AVCaptureDevice.requestAccess(for: media)
            default: granted = false
            }
            guard isVisible, preparationID == request, !Task.isCancelled else { return }
            guard granted else {
                needsSettings = true
                message = String(localized: "Allow camera and microphone access in Settings to record videos.")
                return
            }
        }
        do {
            let activeDevice = try await capture.prepare()
            guard isVisible, preparationID == request, !Task.isCancelled else {
                if !isVisible { capture.suspend() }
                return
            }
            updateDevice(activeDevice)
            isReady = true
            if pendingURL == nil { message = nil }
        } catch {
            guard preparationID == request, isVisible else { return }
            message = error.localizedDescription
        }
    }

    func start(rotation: CGFloat) {
        guard isReady, !isBusy, !isRecording, pendingURL == nil else { return }
        do {
            try FileManager.default.createDirectory(at: Self.recordingsFolder, withIntermediateDirectories: true)
            let url = Self.recordingsFolder.appendingPathComponent(UUID().uuidString).appendingPathExtension("mov")
            message = nil
            isBusy = true
            isStartingRecording = true
            pausedAt = nil
            pausedDuration = 0
            isPaused = false
            capture.start(url: url, rotation: rotation)
        } catch { message = error.localizedDescription }
    }

    func recordedDuration(at date: Date) -> TimeInterval {
        guard let startedAt else { return 0 }
        return max(0, (pausedAt ?? date).timeIntervalSince(startedAt) - pausedDuration)
    }

    func togglePause() {
        guard isRecording, !isBusy else { return }
        isBusy = true
        capture.setPaused(!isPaused)
    }

    func setZoom(_ value: Double) {
        guard isReady else { return }
        zoom = min(max(1, value), maxZoom)
        capture.setZoom(zoom)
    }

    private func updateDevice(_ device: AVCaptureDevice) {
        self.device = device
        maxZoom = min(6, Double(device.maxAvailableVideoZoomFactor))
        zoom = Double(device.videoZoomFactor)
    }

    func stop() {
        guard isRecording || isStartingRecording else { return }
        isBusy = true
        beginBackgroundTask()
        capture.stop()
    }

    func suspend() {
        isVisible = false
        preparationID = UUID()
        isReady = false
        if isRecording || isStartingRecording { beginBackgroundTask() }
        capture.suspend()
    }

    func switchCamera() async {
        guard isReady, !isBusy, !isRecording else { return }
        isBusy = true
        defer { isBusy = false }
        do { updateDevice(try await capture.switchCamera()) }
        catch { message = error.localizedDescription }
    }

    func keepPendingForLater() {
        guard !isBusy, pendingURL != nil else { return }
        pendingURL = nil
        message = String(localized: "Video kept in CueCard. Reopen the camera to save or share it later.")
    }

    func savePending() async {
        guard let url = pendingURL, !isBusy else { return }
        isBusy = true
        defer {
            isBusy = false
            endBackgroundTask()
        }
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            needsSettings = true
            message = String(localized: "Your video is kept in CueCard. Allow Photos access to save it, or use Share Video.")
            return
        }
        do {
            let created = (try? url.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date()
            try await PHPhotoLibrary.shared().performChanges {
                let request = PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
                request?.creationDate = created
            }
            try? FileManager.default.removeItem(at: url)
            pendingURL = (try? FileManager.default.contentsOfDirectory(
                at: Self.recordingsFolder, includingPropertiesForKeys: nil
            ))?.first(where: { $0.pathExtension == "mov" })
            message = String(localized: "Video saved to Photos")
            needsSettings = false
        } catch {
            message = String(localized: "Your video is kept in CueCard. Saving failed; try again or use Share Video.")
        }
    }

    private func handle(_ event: CameraCapture.Event) {
        switch event {
        case .started:
            isStartingRecording = false
            if startedAt == nil { startedAt = Date() }
            isRecording = true
            isBusy = false
        case .paused:
            pausedAt = Date()
            isPaused = true
            isBusy = false
        case .recordingResumed:
            if let pausedAt { pausedDuration += Date().timeIntervalSince(pausedAt) }
            pausedAt = nil
            isPaused = false
            isBusy = false
        case .saving:
            // The camera has stopped; only the file is still being written.
            isRecording = false
            isPaused = false
            pausedAt = nil
            message = String(localized: "Saving video…")
        case let .finished(url, error):
            isStartingRecording = false
            let start = startedAt ?? Date()
            startedAt = nil
            isRecording = false
            isPaused = false
            pausedAt = nil
            isBusy = false
            if let error {
                message = error
                // Keep even an unsuccessful file available for recovery.
                if FileManager.default.fileExists(atPath: url.path) { pendingURL = url }
                endBackgroundTask()
            } else {
                pendingURL = url
                message = nil
                if let scriptID {
                    TakeStore.shared.recordSession(scriptID: scriptID, start: start, end: Date())
                }
                Task { await savePending() }
            }
        case let .unavailable(reason):
            isReady = false
            message = reason
        case .resumed:
            isReady = isVisible
        }
    }

    private func beginBackgroundTask() {
        savingSelf = self
        guard backgroundTask == .invalid else { return }
        backgroundTask = UIApplication.shared.beginBackgroundTask { [weak self] in
            Task { @MainActor in self?.endBackgroundTask() }
        }
    }

    private func endBackgroundTask() {
        savingSelf = nil
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }
}

/// All mutable capture state is confined to queue. The preview layer is the
/// only consumer of session outside it, as required by AVFoundation.
final class CameraCapture: NSObject, @unchecked Sendable, AVCaptureFileOutputRecordingDelegate {
    enum Event {
        case started
        case paused
        case recordingResumed
        /// Recording ended, and the take is being joined or cropped.
        case saving
        case finished(URL, String?)
        case unavailable(String)
        case resumed
    }
    let session = AVCaptureSession()
    var onEvent: ((Event) -> Void)?
    private let queue = DispatchQueue(label: "com.thisisnsh.cuecard.camera")
    private let output = AVCaptureMovieFileOutput()
    private var videoInput: AVCaptureDeviceInput?
    private var recordingRequested = false
    private var stopRequested = false
    // iOS 17 has no native movie pause. Keep its segments until a successful
    // export joins them without the paused intervals; never discard failed takes.
    private var fallbackPauseRequested = false
    private var fallbackPaused = false
    private var segments: [URL] = []
    private var recordingRotation: CGFloat = 90
    private var observers: [NSObjectProtocol] = []

    override init() {
        super.init()
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: AVCaptureSession.wasInterruptedNotification, object: session, queue: nil) { [weak self] _ in
            self?.stop()
            self?.onEvent?(.unavailable(String(localized: "Camera interrupted. Recording will stop and save.")))
        })
        observers.append(center.addObserver(forName: AVCaptureSession.interruptionEndedNotification, object: session, queue: nil) { [weak self] _ in
            self?.onEvent?(.resumed)
        })
        observers.append(center.addObserver(forName: AVCaptureSession.runtimeErrorNotification, object: session, queue: nil) { [weak self] _ in
            self?.stop()
            self?.onEvent?(.unavailable(String(localized: "The camera stopped. Close and reopen the camera to try again.")))
        })
    }

    deinit { observers.forEach(NotificationCenter.default.removeObserver) }

    func prepare() async throws -> AVCaptureDevice {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    if self.videoInput == nil { try self.configure() }
                    self.session.startRunning()
                    guard self.session.isRunning, let device = self.videoInput?.device else { throw CameraError.unavailable }
                    continuation.resume(returning: device)
                } catch { continuation.resume(throwing: error) }
            }
        }
    }

    private func configure() throws {
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        // Roll back partial configuration if an input cannot be added.
        session.inputs.forEach { session.removeInput($0) }
        session.outputs.forEach { session.removeOutput($0) }
        if session.canSetSessionPreset(.hd1920x1080) { session.sessionPreset = .hd1920x1080 }
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
                ?? AVCaptureDevice.default(for: .video),
              let microphone = AVCaptureDevice.default(for: .audio) else { throw CameraError.unavailable }
        let video = try AVCaptureDeviceInput(device: camera)
        let audio = try AVCaptureDeviceInput(device: microphone)
        guard session.canAddInput(video) else { throw CameraError.unavailable }
        session.addInput(video)
        guard session.canAddInput(audio) else { throw CameraError.unavailable }
        session.addInput(audio)
        guard session.canAddOutput(output) else { throw CameraError.unavailable }
        session.addOutput(output)
        videoInput = video
    }

    func switchCamera() async throws -> AVCaptureDevice {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    guard !self.recordingRequested, let old = self.videoInput,
                          let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video,
                                                               position: old.device.position == .front ? .back : .front)
                    else { throw CameraError.unavailable }
                    let input = try AVCaptureDeviceInput(device: device)
                    self.session.beginConfiguration()
                    self.session.removeInput(old)
                    if self.session.canAddInput(input) {
                        self.session.addInput(input)
                        self.videoInput = input
                        self.session.commitConfiguration()
                        continuation.resume(returning: device)
                    } else {
                        self.session.addInput(old)
                        self.session.commitConfiguration()
                        throw CameraError.unavailable
                    }
                } catch { continuation.resume(throwing: error) }
            }
        }
    }

    func setZoom(_ value: Double) {
        queue.async {
            guard let device = self.videoInput?.device else { return }
            do {
                try device.lockForConfiguration()
                defer { device.unlockForConfiguration() }
                device.videoZoomFactor = min(max(CGFloat(value), device.minAvailableVideoZoomFactor),
                                             device.maxAvailableVideoZoomFactor)
            } catch {
                // Zoom failure should not interrupt a recording.
            }
        }
    }

    func setPaused(_ paused: Bool) {
        queue.async {
            guard self.recordingRequested, !self.stopRequested else { return }
            if #available(iOS 18.0, *) {
                if paused { self.output.pauseRecording() } else { self.output.resumeRecording() }
            } else if paused {
                self.fallbackPauseRequested = true
                self.output.stopRecording()
            } else {
                guard self.fallbackPaused, let first = self.segments.first else { return }
                self.fallbackPaused = false
                let url = first.deletingLastPathComponent().appendingPathComponent(UUID().uuidString).appendingPathExtension("mov")
                self.segments.append(url)
                if let connection = self.output.connection(with: .video),
                   connection.isVideoRotationAngleSupported(self.recordingRotation) {
                    connection.videoRotationAngle = self.recordingRotation
                }
                self.output.startRecording(to: url, recordingDelegate: self)
            }
        }
    }

    func start(url: URL, rotation: CGFloat) {
        queue.async {
            guard self.session.isRunning, !self.recordingRequested,
                  let connection = self.output.connection(with: .video), connection.isActive else {
                self.onEvent?(.finished(url, String(localized: "Camera is not ready. Try again.")))
                return
            }
            if connection.isVideoRotationAngleSupported(rotation) { connection.videoRotationAngle = rotation }
            if connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = false
            }
            self.stopRequested = false
            self.fallbackPauseRequested = false
            self.fallbackPaused = false
            self.segments = [url]
            self.recordingRotation = rotation
            self.recordingRequested = true
            self.output.startRecording(to: url, recordingDelegate: self)
        }
    }

    func stop() {
        queue.async { self.stopOnQueue() }
    }

    private func stopOnQueue() {
        stopRequested = true
        if fallbackPaused {
            fallbackPaused = false
            finishRecording(error: nil)
        } else if output.isRecording {
            output.stopRecording()
        } else if #available(iOS 18.0, *), output.isRecordingPaused {
            output.stopRecording()
        }
    }

    func suspend() {
        queue.async {
            self.stopOnQueue()
            self.session.stopRunning()
        }
    }

    func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL, from connections: [AVCaptureConnection]) {
        queue.async {
            self.onEvent?(self.segments.count > 1 ? .recordingResumed : .started)
            if self.stopRequested { self.output.stopRecording() }
        }
    }

    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL,
                    from connections: [AVCaptureConnection], error: Error?) {
        queue.async {
            let nsError = error as NSError?
            let succeeded = error == nil || (nsError?.userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool == true)
            if self.fallbackPauseRequested, !self.stopRequested, succeeded {
                self.fallbackPauseRequested = false
                self.fallbackPaused = true
                self.onEvent?(.paused)
            } else {
                self.finishRecording(error: succeeded ? nil : error?.localizedDescription)
            }
        }
    }

    @available(iOS 18.0, *)
    func fileOutput(_ output: AVCaptureFileOutput, didPauseRecordingTo fileURL: URL, from connections: [AVCaptureConnection]) {
        queue.async { self.onEvent?(.paused) }
    }

    @available(iOS 18.0, *)
    func fileOutput(_ output: AVCaptureFileOutput, didResumeRecordingTo fileURL: URL, from connections: [AVCaptureConnection]) {
        queue.async { self.onEvent?(.recordingResumed) }
    }

    private func finishRecording(error: String?) {
        recordingRequested = false
        guard let first = segments.first else { return }
        let files = segments
        segments = []
        // Takes are always 9:16. Portrait capture already is; a landscape one
        // keeps its centre, matching the floating preview.
        let crops = Int(recordingRotation) % 180 == 0
        guard error == nil, files.count > 1 || crops else {
            onEvent?(.finished(first, error))
            return
        }
        onEvent?(.saving)
        // Below the reader's priority, so the script keeps scrolling smoothly.
        Task(priority: .utility) {
            do {
                let merged = try await Self.export(files, cropToPortrait: crops)
                files.forEach { try? FileManager.default.removeItem(at: $0) }
                onEvent?(.finished(merged, nil))
            } catch where files.count == 1 {
                // An uncropped take beats none.
                onEvent?(.finished(first, nil))
            } catch {
                onEvent?(.finished(first, String(localized: "Could not join the recording. Your video segments are kept in CueCard for saving or sharing.")))
            }
        }
    }

    private static func export(_ files: [URL], cropToPortrait: Bool) async throws -> URL {
        let composition = AVMutableComposition()
        guard let video = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
              let audio = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        else { throw CameraError.unavailable }
        var cursor = CMTime.zero
        var transform = CGAffineTransform.identity
        var naturalSize = CGSize.zero
        var frameRate: Float = 30
        for file in files {
            let asset = AVURLAsset(url: file)
            let duration = try await asset.load(.duration)
            guard let sourceVideo = try await asset.loadTracks(withMediaType: .video).first else { throw CameraError.unavailable }
            if cursor == .zero {
                (transform, naturalSize, frameRate) = try await sourceVideo.load(.preferredTransform, .naturalSize, .nominalFrameRate)
            }
            try video.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: sourceVideo, at: cursor)
            if let sourceAudio = try await asset.loadTracks(withMediaType: .audio).first {
                let audioRange = try await sourceAudio.load(.timeRange)
                let range = CMTimeRangeGetIntersection(audioRange, otherRange: CMTimeRange(start: .zero, duration: duration))
                try audio.insertTimeRange(range, of: sourceAudio, at: cursor + range.start)
            }
            cursor = cursor + duration
        }
        let url = files[0].deletingLastPathComponent().appendingPathComponent(UUID().uuidString).appendingPathExtension("mov")
        guard let exporter = AVAssetExportSession(
            asset: composition,
            presetName: cropToPortrait ? AVAssetExportPresetHighestQuality : AVAssetExportPresetPassthrough
        ) else { throw CameraError.unavailable }
        if cropToPortrait {
            // Stand the frame upright, then slide its centre 9:16 into view.
            let upright = CGRect(origin: .zero, size: naturalSize).applying(transform)
            let width = (upright.height * 9 / 16 / 2).rounded() * 2
            let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: video)
            layer.setTransform(transform.concatenating(CGAffineTransform(
                translationX: -upright.minX - (upright.width - width) / 2, y: -upright.minY)), at: .zero)
            let instruction = AVMutableVideoCompositionInstruction()
            instruction.timeRange = CMTimeRange(start: .zero, duration: cursor)
            instruction.layerInstructions = [layer]
            let videoComposition = AVMutableVideoComposition()
            videoComposition.renderSize = CGSize(width: width, height: upright.height)
            videoComposition.frameDuration = CMTime(value: 1, timescale: CMTimeScale(frameRate > 0 ? frameRate.rounded() : 30))
            videoComposition.instructions = [instruction]
            exporter.videoComposition = videoComposition
        } else {
            video.preferredTransform = transform
        }
        exporter.outputURL = url
        exporter.outputFileType = .mov
        await exporter.export()
        guard exporter.status == .completed else {
            try? FileManager.default.removeItem(at: url)
            throw exporter.error ?? CameraError.unavailable
        }
        return url
    }

    private enum CameraError: LocalizedError {
        case unavailable
        var errorDescription: String? { String(localized: "Camera or microphone unavailable. Try again on a device with a camera.") }
    }
}
