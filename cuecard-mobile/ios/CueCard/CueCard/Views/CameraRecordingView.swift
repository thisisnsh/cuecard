import AVFoundation
import Observation
import SwiftUI

/// Keeps the reader full screen and floats the camera above it in a window
/// styled like Picture in Picture, 9:16 or 16:9 to fit the picture. The reader
/// is never replaced, so its scroll position and controls survive turning the
/// camera on and off.
///
/// It wraps the reader's whole navigation stack so the window passes over the
/// navigation bar while dragged. It settles only inside the area the reader
/// marks with `cameraWindowArea()`, below that bar.
///
/// The window up here only takes the gestures and draws the controls. The
/// picture itself is drawn by the reader with `CameraBackdrop`, between its
/// background and its text, so the script stays in view over the camera.
struct CameraRecordingView<Content: View>: View {
    @Binding var isPresented: Bool
    let scriptID: UUID?
    /// Lets the reader start and pause the recording from its own buttons.
    let link: CameraLink?
    /// Called after the camera's record, pause or stop button is tapped.
    let onControl: (CameraLink.Control) -> Void
    @ViewBuilder let content: () -> Content
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var recorder = CameraRecorder()
    // Read here only for the reader's area, so the live drag and pinch
    // re-render the window and the picture but never the reader.
    @State private var placement = CameraWindowPlacement()
    @State private var previousIdleTimerDisabled = false

    init(isPresented: Binding<Bool>, scriptID: UUID?, link: CameraLink? = nil,
         onControl: @escaping (CameraLink.Control) -> Void = { _ in },
         @ViewBuilder content: @escaping () -> Content) {
        _isPresented = isPresented
        self.scriptID = scriptID
        self.link = link
        self.onControl = onControl
        self.content = content
    }

    var body: some View {
        let isShown = isPresented && !placement.area.isEmpty
        content()
            .environment(\.reportCameraWindowArea, CameraWindowAreaReporter { [placement] in placement.area = $0 })
            .environment(\.cameraBackdrop, isShown ? CameraBackdropSource(recorder: recorder, placement: placement) : nil)
            .overlay(alignment: .topLeading) {
                if isShown {
                    GeometryReader { geometry in
                        FloatingCameraWindow(recorder: recorder, placement: placement,
                                             origin: geometry.frame(in: .global).origin,
                                             onControl: onControl,
                                             onClose: { isPresented = false })
                    }
                    .transition(.opacity)
                }
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: isPresented)
            .onAppear { link?.recorder = recorder }
            .task(id: isPresented) {
                if isPresented {
                    previousIdleTimerDisabled = UIApplication.shared.isIdleTimerDisabled
                    UIApplication.shared.isIdleTimerDisabled = true
                    await recorder.prepare(scriptID: scriptID)
                } else {
                    recorder.suspend()
                }
            }
            .onChange(of: isPresented) { _, presented in
                if !presented {
                    UIApplication.shared.isIdleTimerDisabled = previousIdleTimerDisabled
                }
            }
            .onChange(of: scenePhase) { _, phase in
                guard isPresented else { return }
                if phase == .background {
                    recorder.suspend()
                } else if phase == .active {
                    Task {
                        guard isPresented else { return }
                        await recorder.prepare(scriptID: scriptID)
                    }
                }
            }
            .onDisappear {
                recorder.suspend()
                if isPresented {
                    UIApplication.shared.isIdleTimerDisabled = previousIdleTimerDisabled
                }
            }
    }
}

/// Ties a reader's play and pause to the floating camera's recording. The
/// reader starts and pauses the camera through it; the camera's own buttons
/// reach the reader through `CameraRecordingView`'s `onControl`.
@MainActor
final class CameraLink {
    enum Control { case record, pause, stop }

    fileprivate weak var recorder: CameraRecorder?

    /// Starts a recording, or resumes a paused one.
    func record() { recorder?.record() }

    func pause() { recorder?.setPaused(true) }
}

extension View {
    /// Marks the reader below its navigation bar: where the floating camera
    /// window settles.
    func cameraWindowArea() -> some View { modifier(CameraWindowArea()) }
}

private struct CameraWindowArea: ViewModifier {
    @Environment(\.reportCameraWindowArea) private var report

    func body(content: Content) -> some View {
        content.background {
            GeometryReader { geometry in
                Color.clear.onChange(of: geometry.frame(in: .global), initial: true) { _, frame in
                    report.action(frame)
                }
            }
        }
    }
}

private struct CameraWindowAreaReporter {
    var action: @MainActor (CGRect) -> Void = { _ in }
}

private struct CameraWindowAreaKey: EnvironmentKey {
    static let defaultValue = CameraWindowAreaReporter()
}

/// What the reader's `CameraBackdrop` draws: there only while the camera is.
private struct CameraBackdropSource {
    let recorder: CameraRecorder
    let placement: CameraWindowPlacement
}

private struct CameraBackdropKey: EnvironmentKey {
    static let defaultValue: CameraBackdropSource? = nil
}

private extension EnvironmentValues {
    var reportCameraWindowArea: CameraWindowAreaReporter {
        get { self[CameraWindowAreaKey.self] }
        set { self[CameraWindowAreaKey.self] = newValue }
    }

    var cameraBackdrop: CameraBackdropSource? {
        get { self[CameraBackdropKey.self] }
        set { self[CameraBackdropKey.self] = newValue }
    }
}

/// The floating camera's picture. The reader puts it between its background
/// and its text, so the words are drawn over the camera rather than under it.
/// It draws nothing while the camera is off.
struct CameraBackdrop: View {
    @Environment(\.cameraBackdrop) private var source

    var body: some View {
        if let source {
            CameraBackdropPicture(recorder: source.recorder, placement: source.placement)
                .transition(.opacity)
        }
    }
}

private struct CameraBackdropPicture: View {
    @ObservedObject var recorder: CameraRecorder
    let placement: CameraWindowPlacement

    var body: some View {
        GeometryReader { geometry in
            let origin = geometry.frame(in: .global).origin
            let frame = placement.frame
            let picture = placement.largestSize
            let shape = RoundedRectangle(cornerRadius: CameraWindowPlacement.cornerRadius, style: .continuous)
            CameraPreview(session: recorder.capture.session, device: recorder.device)
                .frame(width: picture.width, height: picture.height)
                .scaleEffect(frame.width / picture.width)
                .frame(width: frame.width, height: frame.height)
                .background(.black)
                .clipShape(shape)
                .shadow(color: .black.opacity(0.3), radius: 14, y: 6)
                .offset(x: frame.minX - origin.x, y: frame.minY - origin.y)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private enum WindowCorner {
    case topLeading, topTrailing, bottomLeading, bottomTrailing

    init(leading: Bool, top: Bool) {
        switch (leading, top) {
        case (true, true): self = .topLeading
        case (false, true): self = .topTrailing
        case (true, false): self = .bottomLeading
        case (false, false): self = .bottomTrailing
        }
    }

    var isLeading: Bool { self == .topLeading || self == .bottomLeading }
    var isTop: Bool { self == .topLeading || self == .topTrailing }
}

/// Where the floating camera is, in global coordinates: shared by the window,
/// which takes the gestures and draws the controls, and the reader's
/// `CameraBackdrop`, which draws the picture.
@MainActor @Observable
private final class CameraWindowPlacement {
    /// The reader's area: where the window settles.
    var area = CGRect.zero
    var corner = WindowCorner.topTrailing
    var expanded = false
    var dragTranslation = CGSize.zero
    var pinchScale: CGFloat = 1

    static let margin: CGFloat = 16
    /// Space between the window and the navigation bar.
    static let topMargin: CGFloat = 24
    static let cornerRadius: CGFloat = 16
    /// The long side over the short one.
    static let aspect: CGFloat = 16 / 9

    /// Wide when the app is: the picture stays level with the horizon, so it's
    /// landscape on screen whenever the app is laid out in landscape.
    var isLandscape: Bool { area.width > area.height }

    private var small: CGFloat { min(min(area.width, area.height) * 0.36, 180) }
    private var large: CGFloat { min(min(area.width, area.height) * 0.6, 320) }

    /// Collapsed and expanded short sides, followed live while pinching and
    /// always kept small enough to fit the area.
    var size: CGSize {
        size(short: min(max((expanded ? large : small) * pinchScale, small * 0.8), large * 1.1))
    }

    /// The largest the window gets. The picture is laid out at this size and
    /// scaled down to the window: a preview layer resized mid-animation shows
    /// black until its video catches up, while a scaled one stays smooth.
    var largestSize: CGSize { size(short: large * 1.1) }

    private func size(short: CGFloat) -> CGSize {
        let height = area.height - Self.topMargin - Self.margin
        let width = area.width - 2 * Self.margin
        let fit = max(1, isLandscape ? min(height, width / Self.aspect) : min(width, height / Self.aspect))
        let short = min(short, fit)
        let long = short * Self.aspect
        return isLandscape ? CGSize(width: long, height: short) : CGSize(width: short, height: long)
    }

    func origin(for corner: WindowCorner, size: CGSize) -> CGPoint {
        CGPoint(x: corner.isLeading ? area.minX + Self.margin : area.maxX - size.width - Self.margin,
                y: corner.isTop ? area.minY + Self.topMargin : area.maxY - size.height - Self.margin)
    }

    /// Where the window is drawn, following the finger while dragged.
    var frame: CGRect {
        let size = size
        let origin = origin(for: corner, size: size)
        return CGRect(origin: CGPoint(x: origin.x + dragTranslation.width, y: origin.y + dragTranslation.height),
                      size: size)
    }
}

/// The camera's controls, over the picture the reader draws. Drag to move it,
/// anywhere on screen, and it springs back into the nearest corner of the
/// reader's area; pinch or double-tap to change its size; tap to show or hide
/// the controls.
private struct FloatingCameraWindow: View {
    @ObservedObject var recorder: CameraRecorder
    let placement: CameraWindowPlacement
    /// The space it's drawn in, in global coordinates.
    let origin: CGPoint
    let onControl: (CameraLink.Control) -> Void
    let onClose: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showsControls = true

    private var snap: Animation { reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.38, dampingFraction: 0.8) }

    var body: some View {
        let frame = placement.frame
        let compact = min(frame.width, frame.height) < 220
        let shape = RoundedRectangle(cornerRadius: CameraWindowPlacement.cornerRadius, style: .continuous)
        ZStack {
            if showsControls {
                controls(compact: compact)
                    .transition(.opacity)
            } else if recorder.isRecording {
                VStack {
                    duration(compact: compact)
                    Spacer(minLength: 0)
                }
                .padding(8)
                .transition(.opacity)
            }
        }
        .frame(width: frame.width, height: frame.height)
        .clipShape(shape)
        .contentShape(shape)
        .onTapGesture(count: 2) { withAnimation(snap) { placement.expanded.toggle() } }
        .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { showsControls.toggle() } }
        .gesture(drag.simultaneously(with: pinch))
        .offset(x: frame.minX - origin.x, y: frame.minY - origin.y)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Camera")
        .accessibilityAction(named: placement.expanded ? "Make Camera Smaller" : "Make Camera Larger") {
            withAnimation(snap) { placement.expanded.toggle() }
        }
        .accessibilityAction(named: "Move to Top") { placement.corner = WindowCorner(leading: placement.corner.isLeading, top: true) }
        .accessibilityAction(named: "Move to Bottom") { placement.corner = WindowCorner(leading: placement.corner.isLeading, top: false) }
        .accessibilityAction(named: "Move to Other Side") { placement.corner = WindowCorner(leading: !placement.corner.isLeading, top: placement.corner.isTop) }
    }

    private var drag: some Gesture {
        // Global space: the window's own space moves with it while dragging.
        DragGesture(coordinateSpace: .global)
            .onChanged { placement.dragTranslation = $0.translation }
            .onEnded { value in
                // Throwing the window carries it to the corner it is heading for.
                let size = placement.size
                let origin = placement.origin(for: placement.corner, size: size)
                let area = placement.area
                let x = origin.x + value.predictedEndTranslation.width + size.width / 2
                let y = origin.y + value.predictedEndTranslation.height + size.height / 2
                withAnimation(snap) {
                    placement.corner = WindowCorner(leading: x < area.midX, top: y < area.midY)
                    placement.dragTranslation = .zero
                }
            }
    }

    private var pinch: some Gesture {
        MagnifyGesture()
            .onChanged { placement.pinchScale = $0.magnification }
            .onEnded { value in
                withAnimation(snap) {
                    if value.magnification > 1.1 { placement.expanded = true }
                    else if value.magnification < 0.9 { placement.expanded = false }
                    placement.pinchScale = 1
                }
            }
    }

    private func controls(compact: Bool) -> some View {
        let icon: CGFloat = compact ? 15 : 18
        return VStack(spacing: 6) {
            HStack(spacing: 4) {
                Button(action: onClose) {
                    circledIcon("xmark", size: 32)
                }
                .accessibilityLabel("Close Camera")
                Spacer(minLength: 0)
                if recorder.isRecording { duration(compact: compact) }
                Spacer(minLength: 0)
                zoomButton
            }
            Spacer(minLength: 0)
            if let message = recorder.message {
                Text(message)
                    .font(.caption2)
                    .multilineTextAlignment(.center)
                    .lineLimit(compact ? 4 : 6)
                    .minimumScaleFactor(0.8)
                    .padding(6)
                    .background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .accessibilityAddTraits(.updatesFrequently)
            }
            HStack {
                Button { Task { await recorder.switchCamera() } } label: {
                    circledIcon("arrow.triangle.2.circlepath.camera", size: 36)
                }
                .accessibilityLabel("Flip Camera")
                .disabled(!recorder.isReady || recorder.isBusy || recorder.isRecording)
                Spacer(minLength: 0)
                recordButton(diameter: compact ? 44 : 56)
                Spacer(minLength: 0)
                Button {
                    recorder.stop()
                    onControl(.stop)
                } label: {
                    circledIcon("stop.fill", size: 36)
                }
                .accessibilityLabel("Stop Recording")
                .disabled(!recorder.isRecording || recorder.isBusy)
            }
        }
        .font(.system(size: icon, weight: .semibold))
        .foregroundStyle(.white)
        .tint(.white)
        .padding(8)
        .background {
            // A light scrim, like the system player's, keeps white glyphs
            // readable over a bright picture.
            LinearGradient(colors: [.black.opacity(0.45), .black.opacity(0.1), .black.opacity(0.1), .black.opacity(0.5)],
                           startPoint: .top, endPoint: .bottom)
                .allowsHitTesting(false)
        }
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
    }

    /// A glyph on the same dark disc as the zoom button, so it stays readable
    /// over a bright picture.
    private func circledIcon(_ name: String, size: CGFloat) -> some View {
        Image(systemName: name)
            .frame(width: size - 4, height: size - 4)
            .background(.black.opacity(0.5), in: Circle())
            .frame(width: size, height: size)
    }

    private func recordButton(diameter: CGFloat) -> some View {
        Button {
            let control: CameraLink.Control = recorder.isRecording && !recorder.isPaused ? .pause : .record
            if recorder.isRecording { recorder.togglePause() }
            else { recorder.start() }
            onControl(control)
        } label: {
            ZStack {
                Circle().fill(.red).frame(width: diameter, height: diameter)
                Circle().stroke(.white, lineWidth: 2).frame(width: diameter + 6, height: diameter + 6)
                if recorder.isBusy { ProgressView().tint(.white) }
                else { Image(systemName: recorder.isRecording && !recorder.isPaused ? "pause.fill" : "play.fill") }
            }
        }
        .accessibilityLabel(recorder.isRecording ? (recorder.isPaused ? "Resume Recording" : "Pause Recording") : "Record Video")
        .disabled(recorder.isBusy || (!recorder.isRecording && !recorder.isReady))
    }

    private func duration(compact: Bool) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            HStack(spacing: 4) {
                Circle().fill(recorder.isPaused ? .yellow : .red).frame(width: 6, height: 6)
                Text(TeleprompterParser.formatTime(Int(recorder.recordedDuration(at: context.date))))
                    .font((compact ? Font.caption2 : .caption).monospacedDigit().weight(.semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(.black.opacity(0.5), in: Capsule())
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(recorder.isPaused ? "Recording paused" : "Recording duration")
    }

    /// Steps through the Camera app's stops this camera has, such as 0.5×, 1×,
    /// 2× and 5×, switching lenses on the way.
    private var zoomButton: some View {
        let steps = recorder.zoomSteps
        let next = steps.first { $0 > recorder.zoom + 0.05 } ?? steps[0]
        return Button { recorder.setZoom(next) } label: {
            Text(verbatim: recorder.zoom.formatted(.number.precision(.fractionLength(0...1))) + "×")
                .font(.caption2.monospacedDigit().weight(.bold))
                .frame(width: 28, height: 28)
                .background(.black.opacity(0.5), in: Circle())
                .frame(width: 32, height: 32)
        }
        .accessibilityLabel("Camera Zoom")
        .accessibilityValue(String(format: "%.1f×", recorder.zoom))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: recorder.setZoom(recorder.zoom + 0.5)
            case .decrement: recorder.setZoom(recorder.zoom - 0.5)
            @unknown default: break
            }
        }
        .opacity(steps.count > 1 ? 1 : 0)
        .disabled(!recorder.isReady || steps.count < 2)
    }
}

private struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    let device: AVCaptureDevice?

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        // The window turns to match the picture, so this only trims rounding.
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ view: PreviewView, context: Context) { view.update(device: device) }

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
        private var device: AVCaptureDevice?
        private var rotation: AVCaptureDevice.RotationCoordinator?
        private var observation: NSKeyValueObservation?

        func update(device: AVCaptureDevice?) {
            guard self.device != device else { return }
            self.device = device
            observation = nil
            guard let device else { rotation = nil; return }
            let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: previewLayer)
            rotation = coordinator
            observation = coordinator.observe(\.videoRotationAngleForHorizonLevelPreview, options: [.initial, .new]) { [weak self] coordinator, _ in
                let angle = coordinator.videoRotationAngleForHorizonLevelPreview
                DispatchQueue.main.async { self?.apply(angle: angle) }
            }
        }

        private func apply(angle: CGFloat) {
            guard let connection = previewLayer.connection else { return }
            if connection.isVideoRotationAngleSupported(angle) { connection.videoRotationAngle = angle }
            if connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = device?.position == .front
            }
        }
    }
}
