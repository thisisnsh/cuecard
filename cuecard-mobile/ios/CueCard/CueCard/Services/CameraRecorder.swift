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
    @Published private(set) var isBusy = false
    @Published private(set) var startedAt: Date?
    @Published private(set) var pendingURL: URL?
    @Published var message: String?
    @Published private(set) var needsSettings = false
    let capture = CameraCapture()
    private var isVisible = false
    private var isPreparing = false
    private var scriptID: UUID?
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid

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
        guard !isPreparing else { return }
        isPreparing = true
        defer { isPreparing = false }
        needsSettings = false
        for media in [AVMediaType.video, .audio] {
            let granted: Bool
            switch AVCaptureDevice.authorizationStatus(for: media) {
            case .authorized: granted = true
            case .notDetermined: granted = await AVCaptureDevice.requestAccess(for: media)
            default: granted = false
            }
            guard isVisible, !Task.isCancelled else { return }
            guard granted else {
                needsSettings = true
                message = String(localized: "Allow camera and microphone access in Settings to record videos.")
                return
            }
        }
        do {
            let activeDevice = try await capture.prepare()
            guard isVisible, !Task.isCancelled else {
                capture.suspend()
                return
            }
            device = activeDevice
            isReady = true
            if pendingURL == nil { message = nil }
        } catch {
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
            startedAt = Date()
            capture.start(url: url, rotation: rotation)
        } catch { message = error.localizedDescription }
    }

    func stop() {
        guard isRecording || (isBusy && startedAt != nil) else { return }
        isBusy = true
        beginBackgroundTask()
        capture.stop()
    }

    func suspend() {
        isVisible = false
        isReady = false
        if isRecording || startedAt != nil { beginBackgroundTask() }
        capture.suspend()
    }

    func switchCamera() async {
        guard isReady, !isBusy, !isRecording else { return }
        isBusy = true
        defer { isBusy = false }
        do { device = try await capture.switchCamera() }
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
            isRecording = true
            isBusy = false
        case let .finished(url, error):
            let start = startedAt ?? Date()
            startedAt = nil
            isRecording = false
            isBusy = false
            if let error {
                message = error
                // Keep even an unsuccessful file available for recovery.
                if FileManager.default.fileExists(atPath: url.path) { pendingURL = url }
                endBackgroundTask()
            } else {
                pendingURL = url
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
        guard backgroundTask == .invalid else { return }
        backgroundTask = UIApplication.shared.beginBackgroundTask { [weak self] in
            Task { @MainActor in self?.endBackgroundTask() }
        }
    }

    private func endBackgroundTask() {
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
            self.recordingRequested = true
            self.output.startRecording(to: url, recordingDelegate: self)
        }
    }

    func stop() {
        queue.async { self.stopOnQueue() }
    }

    private func stopOnQueue() {
        stopRequested = true
        if output.isRecording { output.stopRecording() }
    }

    func suspend() {
        queue.async {
            self.stopOnQueue()
            self.session.stopRunning()
        }
    }

    func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL, from connections: [AVCaptureConnection]) {
        queue.async {
            self.onEvent?(.started)
            if self.stopRequested { self.output.stopRecording() }
        }
    }

    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL,
                    from connections: [AVCaptureConnection], error: Error?) {
        queue.async {
            self.recordingRequested = false
            let nsError = error as NSError?
            let succeeded = error == nil || (nsError?.userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool == true)
            self.onEvent?(.finished(outputFileURL, succeeded ? nil : error?.localizedDescription))
        }
    }

    private enum CameraError: LocalizedError {
        case unavailable
        var errorDescription: String? { String(localized: "Camera or microphone unavailable. Try again on a device with a camera.") }
    }
}
