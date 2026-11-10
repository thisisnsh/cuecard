import AVFoundation
import os
import Photos
import UIKit

/// How the camera records: what the sensor captures and how it's encoded, as
/// in the Camera app's video settings. Chosen in Settings, for both modes.
/// Nothing here changes the picture's look.
struct CameraSettings: Codable, Equatable, Sendable {
    enum Resolution: Int, Codable, CaseIterable, Sendable {
        case hd720 = 720, hd1080 = 1080, uhd4K = 2160
    }

    enum DynamicRange: String, Codable, CaseIterable, Sendable {
        case sdr, hdr, appleLog, appleLog2
    }

    enum Codec: String, Codable, CaseIterable, Sendable {
        case hevc, h264, proRes
    }

    enum Stabilization: String, Codable, CaseIterable, Sendable {
        case off, standard, cinematic, extended
    }

    var resolution = Resolution.hd1080
    var frameRate = 30
    var dynamicRange = DynamicRange.sdr
    var codec = Codec.hevc
    var stabilization = Stabilization.off
    /// Records the front camera as the preview shows it, like a mirror.
    var mirrorsFrontCamera = false

    /// The frame rates offered, where the camera has them. Faster ones are slow motion.
    static let frameRates = [24, 25, 30, 60, 120]

    private static let key = "cameraSettings"

    /// Posted when Settings saves a change, so an open camera can follow it.
    static let didChange = Notification.Name("CameraSettings.didChange")

    static var saved: CameraSettings {
        guard let data = UserDefaults.standard.data(forKey: key),
              let settings = try? JSONDecoder().decode(CameraSettings.self, from: data) else { return CameraSettings() }
        return settings
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) { UserDefaults.standard.set(data, forKey: Self.key) }
        NotificationCenter.default.post(name: Self.didChange, object: nil)
    }
}

extension CameraSettings.DynamicRange {
    /// The camera's color space for it; none for Log 2 before iOS 26.
    var colorSpace: AVCaptureColorSpace? {
        switch self {
        case .sdr: .sRGB
        case .hdr: .HLG_BT2020
        case .appleLog: .appleLog
        case .appleLog2: if #available(iOS 26.0, *) { .appleLog2 } else { nil }
        }
    }

    var isLog: Bool { self == .appleLog || self == .appleLog2 }

    func isSupported(by format: AVCaptureDevice.Format) -> Bool {
        colorSpace.map(format.supportedColorSpaces.contains) ?? false
    }
}

extension CameraSettings.Stabilization {
    var mode: AVCaptureVideoStabilizationMode {
        switch self {
        case .off: .off
        case .standard: .standard
        case .cinematic: .cinematic
        case .extended: .cinematicExtended
        }
    }
}

/// The settings a camera can record with, given the rest.
struct CameraOptions: Equatable, Sendable {
    var resolutions: [CameraSettings.Resolution] = [.hd1080]
    var frameRates = [30]
    var dynamicRanges: [CameraSettings.DynamicRange] = [.sdr]
    var codecs: [CameraSettings.Codec] = [.hevc]
    var stabilizations: [CameraSettings.Stabilization] = [.off]
    var isFrontCamera = true
}

/// The camera in use.
struct CameraState: @unchecked Sendable {
    let device: AVCaptureDevice
}

/// UI state lives on the main actor; capture configuration and file recording
/// are serialized on CameraCapture's queue so starting a camera never blocks UI.
@MainActor
final class CameraRecorder: ObservableObject {
    @Published private(set) var device: AVCaptureDevice?
    @Published private(set) var isReady = false
    @Published private(set) var isRecording = false
    @Published private(set) var isPaused = false
    /// As the Camera app counts it: 1× is the main lens, 0.5× the ultra wide.
    @Published private(set) var zoom: Double = 1
    /// The Camera app's zoom stops this camera has, smallest first.
    @Published private(set) var zoomSteps: [Double] = [1]
    @Published private(set) var maxZoom: Double = 1
    /// The reader's choice in Settings; each camera records the nearest it can.
    private var preferredSettings = CameraSettings.saved
    /// The device zoom factor that shows as 1×.
    private var zoomBase: Double = 1
    /// Keeps a recording level with the horizon, however the phone is held.
    private var rotation: AVCaptureDevice.RotationCoordinator?
    private var pausedAt: Date?
    private var pausedDuration: TimeInterval = 0
    @Published private(set) var isBusy = false
    @Published private(set) var startedAt: Date?
    /// A finished take not yet in Photos.
    private var pendingURL: URL?
    @Published var message: String?
    let capture = CameraCapture()
    private var isVisible = false
    private var isStartingRecording = false
    private var preparationID = UUID()
    private var scriptID: UUID?
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    /// Keeps the recorder alive while a take is saved, even after the reader
    /// it was recorded over has closed.
    private var savingSelf: CameraRecorder?
    private var settingsObserver: NSObjectProtocol?

    init() {
        capture.onEvent = { [weak self] event in
            Task { @MainActor in self?.handle(event) }
        }
        pendingURL = Self.leftoverTake()
        // Settings can open over the reader while the camera is on.
        settingsObserver = NotificationCenter.default.addObserver(forName: CameraSettings.didChange,
                                                                  object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.applySavedSettings() }
        }
    }

    deinit {
        if let settingsObserver { NotificationCenter.default.removeObserver(settingsObserver) }
    }

    /// Records with the choices saved in Settings: right away, or once the
    /// take under way has finished.
    private func applySavedSettings() {
        guard isReady, !isRecording, !isStartingRecording else { return }
        let saved = CameraSettings.saved
        guard saved != preferredSettings else { return }
        let previous = preferredSettings
        preferredSettings = saved
        Task {
            if let state = await capture.apply(saved) { update(state) }
            // A take started first; try again once it's done.
            else { preferredSettings = previous }
        }
    }

    /// A take still in CueCard's folder, from a save that failed or never ran.
    private static func leftoverTake() -> URL? {
        (try? FileManager.default.contentsOfDirectory(at: recordingsFolder, includingPropertiesForKeys: nil))?
            .first { $0.pathExtension == "mov" }
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
            pendingURL = Self.leftoverTake()
        }
        for media in [AVMediaType.video, .audio] {
            let granted: Bool
            switch AVCaptureDevice.authorizationStatus(for: media) {
            case .authorized: granted = true
            case .notDetermined: granted = await AVCaptureDevice.requestAccess(for: media)
            default: granted = false
            }
            guard isVisible, preparationID == request, !Task.isCancelled else { return }
            guard granted else {
                message = String(localized: "Allow camera and microphone access in Settings to record videos.")
                return
            }
        }
        // Settings may have changed since the camera was last on.
        if !isRecording, !isStartingRecording { preferredSettings = CameraSettings.saved }
        do {
            let state = try await capture.prepare(settings: preferredSettings)
            guard isVisible, preparationID == request, !Task.isCancelled else {
                if !isVisible { capture.suspend() }
                return
            }
            update(state)
            isReady = true
            message = nil
            // A take that didn't reach Photos last time goes there now.
            await savePending()
        } catch {
            guard preparationID == request, isVisible else { return }
            message = error.localizedDescription
        }
    }

    /// Starts a recording, or resumes a paused one.
    func record() {
        if isRecording { setPaused(false) } else { start() }
    }

    func start() {
        guard isReady, !isBusy, !isRecording else { return }
        do {
            try FileManager.default.createDirectory(at: Self.recordingsFolder, withIntermediateDirectories: true)
            let url = Self.recordingsFolder.appendingPathComponent(UUID().uuidString).appendingPathExtension("mov")
            message = nil
            isBusy = true
            isStartingRecording = true
            pausedAt = nil
            pausedDuration = 0
            isPaused = false
            capture.start(url: url, rotation: rotation?.videoRotationAngleForHorizonLevelCapture ?? 90)
        } catch { message = error.localizedDescription }
    }

    func recordedDuration(at date: Date) -> TimeInterval {
        guard let startedAt else { return 0 }
        return max(0, (pausedAt ?? date).timeIntervalSince(startedAt) - pausedDuration)
    }

    func togglePause() {
        setPaused(!isPaused)
    }

    func setPaused(_ paused: Bool) {
        guard isRecording, !isBusy, paused != isPaused else { return }
        isBusy = true
        capture.setPaused(paused)
    }

    func setZoom(_ value: Double) {
        guard isReady else { return }
        zoom = min(max(zoomSteps[0], value), maxZoom)
        capture.setZoom(zoom * zoomBase)
    }

    private func update(_ state: CameraState) {
        let device = state.device
        self.device = device
        rotation = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: nil)
        zoomBase = Double(CameraCapture.mainLensZoomFactor(of: device))
        let minZoom = Double(device.minAvailableVideoZoomFactor) / zoomBase
        maxZoom = min(Double(device.maxAvailableVideoZoomFactor) / zoomBase, 10)
        // Each lens the camera switches to, and 2× from the main lens as the
        // Camera app offers it, rounded the way it labels them.
        let lenses = device.virtualDeviceSwitchOverVideoZoomFactors.map { $0.doubleValue / zoomBase }
        zoomSteps = Set(([minZoom, 1, 2] + lenses).map { ($0 * 10).rounded() / 10 })
            .filter { $0 >= minZoom - 0.01 && $0 <= maxZoom + 0.01 }
            .sorted()
        zoom = Double(device.videoZoomFactor) / zoomBase
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
        do { update(try await capture.switchCamera()) }
        catch { message = error.localizedDescription }
    }

    /// Move every take still in CueCard into Photos. One that can't go stays
    /// in CueCard and is tried again the next time the camera opens.
    func savePending() async {
        // Never while a take is still being written: it sits in the same folder.
        guard pendingURL != nil, !isBusy, startedAt == nil, !isStartingRecording else { return }
        isBusy = true
        defer {
            isBusy = false
            endBackgroundTask()
        }
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            message = String(localized: "Your video is kept in CueCard. Allow Photos access in Settings to save it.")
            return
        }
        while let url = pendingURL {
            do {
                let created = (try? url.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date()
                try await PHPhotoLibrary.shared().performChanges {
                    let request = PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
                    request?.creationDate = created
                }
                try? FileManager.default.removeItem(at: url)
                let next = Self.leftoverTake()
                pendingURL = next == url ? nil : next
            } catch {
                message = String(localized: "Your video is kept in CueCard. Saving failed; it will try again when you next open the camera.")
                return
            }
        }
        message = String(localized: "Video saved to Photos")
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
            // Anything changed in Settings during the take.
            applySavedSettings()
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
        /// Recording ended, and the take's segments are being joined.
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
    /// What the reader asked for; each camera records the nearest it can.
    private var preferred = CameraSettings()

    /// Whether a camera is on. It sets up the app's audio session for its
    /// video, and Follow Me AI then leaves that alone.
    static let isOn = OSAllocatedUnfairLock(initialState: false)

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

    func prepare(settings: CameraSettings) async throws -> CameraState {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    let isNew = self.videoInput == nil
                    if isNew { try self.configure() }
                    if isNew || (settings != self.preferred && !self.recordingRequested) {
                        self.preferred = settings
                        self.applySettings()
                    }
                    Self.isOn.withLock { $0 = true }
                    self.session.startRunning()
                    guard self.session.isRunning, let device = self.videoInput?.device else { throw CameraError.unavailable }
                    continuation.resume(returning: CameraState(device: device))
                } catch { continuation.resume(throwing: error) }
            }
        }
    }

    /// Records with these settings from the next take, as near as this camera
    /// can. None once a take has been asked for.
    func apply(_ settings: CameraSettings) async -> CameraState? {
        await withCheckedContinuation { continuation in
            queue.async {
                guard !self.recordingRequested, let device = self.videoInput?.device else {
                    continuation.resume(returning: nil)
                    return
                }
                self.preferred = settings
                self.applySettings()
                continuation.resume(returning: CameraState(device: device))
            }
        }
    }

    /// What this iPhone's cameras can record with, for Settings, where no
    /// camera is on: every choice either camera has, given the rest, with the
    /// reader's choices moved to the nearest of those. Each camera then
    /// records the nearest it can.
    static func offered(for preferred: CameraSettings) -> (settings: CameraSettings, options: CameraOptions) {
        typealias Settings = CameraSettings
        let cameras = Self.cameras
        var options = CameraOptions(resolutions: [], frameRates: [], dynamicRanges: [], codecs: [],
                                    stabilizations: [], isFrontCamera: cameras.contains { $0.position == .front })
        for device in cameras {
            var settings = preferred
            var own = CameraOptions()
            _ = format(of: device, for: &settings, options: &own)
            options.resolutions += own.resolutions
            options.frameRates += own.frameRates
            options.dynamicRanges += own.dynamicRanges
            options.stabilizations += own.stabilizations
        }
        if cameras.isEmpty {
            options = CameraOptions(isFrontCamera: false)
        }
        func ordered<T: CaseIterable & Equatable>(_ values: [T]) -> [T] { T.allCases.filter(values.contains) }
        options.resolutions = ordered(options.resolutions)
        options.dynamicRanges = ordered(options.dynamicRanges)
        options.stabilizations = ordered(options.stabilizations)
        options.frameRates = Settings.frameRates.filter(options.frameRates.contains)

        var settings = preferred
        settings.resolution = nearest(settings.resolution, in: options.resolutions)
        if !options.dynamicRanges.contains(settings.dynamicRange), let first = options.dynamicRanges.first {
            settings.dynamicRange = first
        }
        if !options.frameRates.contains(settings.frameRate), let first = options.frameRates.first {
            settings.frameRate = options.frameRates.last { $0 <= settings.frameRate } ?? first
        }
        settings.stabilization = nearest(settings.stabilization, in: options.stabilizations)

        // The same rules as the camera's encoder, below.
        var codecs: [Settings.Codec] = [.hevc]
        if settings.dynamicRange == .sdr { codecs.append(.h264) }
        if recordsProRes(cameras) { codecs.append(.proRes) }
        if settings.dynamicRange.isLog, codecs.contains(.proRes) { codecs = [.proRes] }
        if !codecs.contains(settings.codec) { settings.codec = codecs[0] }
        options.codecs = codecs
        return (settings, options)
    }

    /// The cameras the window switches between. Looked up once: Settings
    /// asks on every change.
    private static let cameras: [AVCaptureDevice] = [AVCaptureDevice.Position.front, .back].compactMap(camera(at:))

    /// Whether this iPhone records ProRes, which the encoder only says once a
    /// camera is on. Every iPhone that records Apple Log does, and so do the
    /// 13 Pro and 14 Pro, from before Log.
    private static func recordsProRes(_ cameras: [AVCaptureDevice]) -> Bool {
        DeviceModel.recordsProResWithoutLog || cameras.contains { device in
            device.formats.contains(where: CameraSettings.DynamicRange.appleLog.isSupported(by:))
        }
    }

    /// Sets the camera's format, frame rate and color, then the encoder and
    /// stabilization, to the nearest this camera has to what was asked for.
    private func applySettings() {
        guard let device = videoInput?.device else { return }
        var settings = preferred
        var options = CameraOptions(isFrontCamera: device.position == .front)
        let format = Self.format(of: device, for: &settings, options: &options)
        if let format, (try? device.lockForConfiguration()) != nil {
            let zoom = device.videoZoomFactor
            if device.activeFormat != format { device.activeFormat = format }
            if let space = settings.dynamicRange.colorSpace, format.supportedColorSpaces.contains(space) {
                device.activeColorSpace = space
            }
            let duration = CMTime(value: 1, timescale: CMTimeScale(settings.frameRate))
            device.activeVideoMinFrameDuration = duration
            device.activeVideoMaxFrameDuration = duration
            // A new format starts zoomed out; stay on the lens that was in use.
            device.videoZoomFactor = min(max(zoom, device.minAvailableVideoZoomFactor), device.maxAvailableVideoZoomFactor)
            device.unlockForConfiguration()
        }
        // What the encoder offers depends on the format now in use.
        let available = output.availableVideoCodecTypes
        var codecs: [CameraSettings.Codec] = []
        if available.contains(.hevc) { codecs.append(.hevc) }
        // H.264 can't carry HDR or Log.
        if settings.dynamicRange == .sdr, available.contains(.h264) { codecs.append(.h264) }
        if Self.proRes(in: available) != nil { codecs.append(.proRes) }
        // Log is recorded in ProRes, as in the Camera app.
        if settings.dynamicRange.isLog, codecs.contains(.proRes) { codecs = [.proRes] }
        if !codecs.contains(settings.codec), let first = codecs.first { settings.codec = first }
        if let connection = output.connection(with: .video) {
            let type: AVVideoCodecType? = switch settings.codec {
            case .hevc: available.contains(.hevc) ? .hevc : nil
            case .h264: available.contains(.h264) ? .h264 : nil
            case .proRes: Self.proRes(in: available)
            }
            if let type { output.setOutputSettings([AVVideoCodecKey: type], for: connection) }
            if connection.isVideoStabilizationSupported {
                connection.preferredVideoStabilizationMode = settings.stabilization.mode
            }
            if connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = mirrorsRecording
            }
        }
    }

    private var mirrorsRecording: Bool {
        preferred.mirrorsFrontCamera && videoInput?.device.position == .front
    }

    /// The best of the camera's formats for the settings, after moving each
    /// setting it can't do to the nearest it can, in order: resolution,
    /// dynamic range, frame rate, then stabilization. Fills in what it offers.
    private static func format(of device: AVCaptureDevice, for settings: inout CameraSettings,
                               options: inout CameraOptions) -> AVCaptureDevice.Format? {
        typealias Settings = CameraSettings
        let byResolution = Dictionary(grouping: device.formats.filter { resolution(of: $0) != nil }) { resolution(of: $0)! }
        let resolutions = Settings.Resolution.allCases.filter { byResolution[$0] != nil }
        guard !resolutions.isEmpty else { return nil }
        settings.resolution = nearest(settings.resolution, in: resolutions)
        options.resolutions = resolutions

        let sized = byResolution[settings.resolution] ?? []
        let ranges = Settings.DynamicRange.allCases.filter { range in
            sized.contains { range.isSupported(by: $0) }
        }
        guard !ranges.isEmpty else { return nil }
        if !ranges.contains(settings.dynamicRange) { settings.dynamicRange = ranges[0] }
        options.dynamicRanges = ranges

        let colored = sized.filter { settings.dynamicRange.isSupported(by: $0) }
        let rates = Settings.frameRates.filter { rate in colored.contains { supports($0, frameRate: rate) } }
        guard !rates.isEmpty else { return nil }
        if !rates.contains(settings.frameRate) {
            settings.frameRate = rates.last { $0 <= settings.frameRate } ?? rates[0]
        }
        options.frameRates = rates

        let timed = colored.filter { supports($0, frameRate: settings.frameRate) }
        let modes = Settings.Stabilization.allCases.filter { mode in
            mode == .off || timed.contains { $0.isVideoStabilizationModeSupported(mode.mode) }
        }
        settings.stabilization = nearest(settings.stabilization, in: modes)
        options.stabilizations = modes

        // Full sensor readout first, then the stabilization asked for, then
        // 8-bit for SDR unless it's ProRes (10-bit is for HDR, Log and ProRes),
        // then the least headroom above the frame rate, which keeps the most detail.
        let wants8Bit = settings.dynamicRange == .sdr && settings.codec != .proRes
        return timed.min { a, b in
            func rank(_ format: AVCaptureDevice.Format) -> (Int, Int, Int, Double) {
                (format.isVideoBinned ? 1 : 0,
                 format.isVideoStabilizationModeSupported(settings.stabilization.mode) ? 0 : 1,
                 wants8Bit && !is8Bit(format) ? 1 : 0,
                 format.videoSupportedFrameRateRanges.map(\.maxFrameRate).max() ?? 0)
            }
            return rank(a) < rank(b)
        }
    }

    /// The resolution of a 16:9 format, the only shape the window shows.
    private static func resolution(of format: AVCaptureDevice.Format) -> CameraSettings.Resolution? {
        let size = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
        guard let resolution = CameraSettings.Resolution(rawValue: Int(size.height)),
              Int(size.width) == resolution.rawValue * 16 / 9 else { return nil }
        return resolution
    }

    private static func supports(_ format: AVCaptureDevice.Format, frameRate: Int) -> Bool {
        format.videoSupportedFrameRateRanges.contains {
            $0.minFrameRate <= Double(frameRate) + 0.01 && Double(frameRate) <= $0.maxFrameRate + 0.01
        }
    }

    private static func is8Bit(_ format: AVCaptureDevice.Format) -> Bool {
        [kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange, kCVPixelFormatType_420YpCbCr8BiPlanarFullRange]
            .contains(CMFormatDescriptionGetMediaSubType(format.formatDescription))
    }

    /// The closest the camera has: the next one down, or else the lowest.
    private static func nearest<T: CaseIterable & Equatable>(_ value: T, in available: [T]) -> T {
        guard !available.contains(value) else { return value }
        let all = Array(T.allCases)
        let index = all.firstIndex(of: value) ?? 0
        return available.last { (all.firstIndex(of: $0) ?? 0) < index } ?? available[0]
    }

    /// ProRes as the Camera app records it, 422 HQ, or the next best on offer.
    private static func proRes(in available: [AVVideoCodecType]) -> AVVideoCodecType? {
        [.proRes422HQ, .proRes422, .proRes422LT].first { available.contains($0) }
    }

    private func configure() throws {
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        // Roll back partial configuration if an input cannot be added.
        session.inputs.forEach { session.removeInput($0) }
        session.outputs.forEach { session.removeOutput($0) }
        if session.canSetSessionPreset(.hd1920x1080) { session.sessionPreset = .hd1920x1080 }
        // The color space follows the settings: SDR, HDR or Log.
        session.automaticallyConfiguresCaptureDeviceForWideColor = false
        guard let camera = Self.camera(at: .front) ?? AVCaptureDevice.default(for: .video),
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
        Self.zoomToMainLens(camera)
    }

    /// The camera on that side as the Camera app uses it. On the back, every
    /// lens sits behind one device that switches between them as it zooms.
    private static func camera(at position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        let types: [AVCaptureDevice.DeviceType] = position == .back
            ? [.builtInTripleCamera, .builtInDualWideCamera, .builtInDualCamera, .builtInWideAngleCamera]
            : [.builtInWideAngleCamera]
        return types.lazy.compactMap { AVCaptureDevice.default($0, for: .video, position: position) }.first
    }

    /// The zoom factor of the main lens, the Camera app's 1×. A device with an
    /// ultra wide starts at it, 0.5×, and reaches the main lens at its first switch.
    static func mainLensZoomFactor(of device: AVCaptureDevice) -> CGFloat {
        guard device.constituentDevices.contains(where: { $0.deviceType == .builtInUltraWideCamera }),
              let main = device.virtualDeviceSwitchOverVideoZoomFactors.first else { return 1 }
        return CGFloat(truncating: main)
    }

    private static func zoomToMainLens(_ device: AVCaptureDevice) {
        guard (try? device.lockForConfiguration()) != nil else { return }
        device.videoZoomFactor = mainLensZoomFactor(of: device)
        device.unlockForConfiguration()
    }

    func switchCamera() async throws -> CameraState {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    guard !self.recordingRequested, let old = self.videoInput,
                          let device = Self.camera(at: old.device.position == .front ? .back : .front)
                    else { throw CameraError.unavailable }
                    let input = try AVCaptureDeviceInput(device: device)
                    self.session.beginConfiguration()
                    self.session.removeInput(old)
                    if self.session.canAddInput(input) {
                        self.session.addInput(input)
                        self.videoInput = input
                        self.session.commitConfiguration()
                        Self.zoomToMainLens(device)
                        self.applySettings()
                        continuation.resume(returning: CameraState(device: device))
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
                connection.isVideoMirrored = self.mirrorsRecording
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
            Self.isOn.withLock { $0 = false }
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
        guard error == nil, files.count > 1 else {
            onEvent?(.finished(first, error))
            return
        }
        onEvent?(.saving)
        // Below the reader's priority, so the script keeps scrolling smoothly.
        Task(priority: .utility) {
            do {
                let merged = try await Self.joinSegments(files)
                files.forEach { try? FileManager.default.removeItem(at: $0) }
                onEvent?(.finished(merged, nil))
            } catch {
                onEvent?(.finished(first, String(localized: "Could not join the recording. Your video segments are kept in CueCard for saving or sharing.")))
            }
        }
    }

    private static func joinSegments(_ files: [URL]) async throws -> URL {
        let composition = AVMutableComposition()
        guard let video = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
              let audio = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        else { throw CameraError.unavailable }
        var cursor = CMTime.zero
        for file in files {
            let asset = AVURLAsset(url: file)
            let duration = try await asset.load(.duration)
            guard let sourceVideo = try await asset.loadTracks(withMediaType: .video).first else { throw CameraError.unavailable }
            if cursor == .zero { video.preferredTransform = try await sourceVideo.load(.preferredTransform) }
            try video.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: sourceVideo, at: cursor)
            if let sourceAudio = try await asset.loadTracks(withMediaType: .audio).first {
                let audioRange = try await sourceAudio.load(.timeRange)
                let range = CMTimeRangeGetIntersection(audioRange, otherRange: CMTimeRange(start: .zero, duration: duration))
                try audio.insertTimeRange(range, of: sourceAudio, at: cursor + range.start)
            }
            cursor = cursor + duration
        }
        let url = files[0].deletingLastPathComponent().appendingPathComponent(UUID().uuidString).appendingPathExtension("mov")
        guard let exporter = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough)
        else { throw CameraError.unavailable }
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
