import AVFoundation
import SwiftUI

/// Keeps the reader full screen and floats the camera above it in a 9:16
/// window styled like Picture in Picture. The reader is never replaced, so its
/// scroll position and controls survive turning the camera on and off.
///
/// It wraps the reader's whole navigation stack so the window passes over the
/// navigation bar while dragged. It settles only inside the area the reader
/// marks with `cameraWindowArea()`, below that bar.
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
    // Only where the window settles lives here. The live drag and pinch stay
    // inside the window so they never re-render the reader.
    @State private var corner = WindowCorner.topTrailing
    @State private var expanded = false
    @State private var previousIdleTimerDisabled = false
    /// The reader's area in global coordinates.
    @State private var area = CGRect.zero

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
        content()
            .environment(\.reportCameraWindowArea, CameraWindowAreaReporter { area = $0 })
            .overlay(alignment: .topLeading) {
                if isPresented, !area.isEmpty {
                    GeometryReader { geometry in
                        let origin = geometry.frame(in: .global).origin
                        FloatingCameraWindow(recorder: recorder,
                                             bounds: area.offsetBy(dx: -origin.x, dy: -origin.y),
                                             corner: $corner, expanded: $expanded,
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
    var action: (CGRect) -> Void = { _ in }
}

private struct CameraWindowAreaKey: EnvironmentKey {
    static let defaultValue = CameraWindowAreaReporter()
}

private extension EnvironmentValues {
    var reportCameraWindowArea: CameraWindowAreaReporter {
        get { self[CameraWindowAreaKey.self] }
        set { self[CameraWindowAreaKey.self] = newValue }
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

/// The camera preview and its controls. Drag to move it, anywhere on screen,
/// and it springs back into the nearest corner of `bounds`; pinch or
/// double-tap to change its size; tap to show or hide the controls.
private struct FloatingCameraWindow: View {
    @ObservedObject var recorder: CameraRecorder
    /// Where the window may settle, in the space it's drawn in.
    let bounds: CGRect
    @Binding var corner: WindowCorner
    @Binding var expanded: Bool
    let onControl: (CameraLink.Control) -> Void
    let onClose: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dragTranslation = CGSize.zero
    @State private var pinchScale: CGFloat = 1
    @State private var showsControls = true

    private static let margin: CGFloat = 16
    /// Space between the window and the navigation bar.
    private static let topMargin: CGFloat = 24
    private static let cornerRadius: CGFloat = 16
    private static let aspect: CGFloat = 16 / 9
    private var snap: Animation { reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.38, dampingFraction: 0.8) }

    var body: some View {
        let size = windowSize
        let origin = origin(for: corner, size: size)
        let compact = size.width < 220
        ZStack {
            CameraPreview(session: recorder.capture.session, device: recorder.device)
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
        .frame(width: size.width, height: size.height)
        .background(.black)
        .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
        .shadow(color: .black.opacity(0.3), radius: 14, y: 6)
        .onTapGesture(count: 2) { withAnimation(snap) { expanded.toggle() } }
        .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { showsControls.toggle() } }
        .gesture(drag(origin: origin, size: size).simultaneously(with: pinch))
        .offset(x: origin.x + dragTranslation.width, y: origin.y + dragTranslation.height)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Camera")
        .accessibilityAction(named: expanded ? "Make Camera Smaller" : "Make Camera Larger") {
            withAnimation(snap) { expanded.toggle() }
        }
        .accessibilityAction(named: "Move to Top") { corner = WindowCorner(leading: corner.isLeading, top: true) }
        .accessibilityAction(named: "Move to Bottom") { corner = WindowCorner(leading: corner.isLeading, top: false) }
        .accessibilityAction(named: "Move to Other Side") { corner = WindowCorner(leading: !corner.isLeading, top: corner.isTop) }
    }

    /// Collapsed and expanded widths, followed live while pinching and always
    /// kept short enough to fit the bounds' height.
    private var windowSize: CGSize {
        let small = min(bounds.width * 0.36, 180)
        let large = min(bounds.width * 0.6, 320)
        let fit = max(1, (bounds.height - Self.topMargin - Self.margin) / Self.aspect)
        let width = min(max((expanded ? large : small) * pinchScale, small * 0.8), large * 1.1, fit)
        return CGSize(width: width, height: width * Self.aspect)
    }

    private func origin(for corner: WindowCorner, size: CGSize) -> CGPoint {
        CGPoint(x: corner.isLeading ? bounds.minX + Self.margin : bounds.maxX - size.width - Self.margin,
                y: corner.isTop ? bounds.minY + Self.topMargin : bounds.maxY - size.height - Self.margin)
    }

    private func drag(origin: CGPoint, size: CGSize) -> some Gesture {
        // Global space: the window's own space moves with it while dragging.
        DragGesture(coordinateSpace: .global)
            .onChanged { dragTranslation = $0.translation }
            .onEnded { value in
                // Throwing the window carries it to the corner it is heading for.
                let x = origin.x + value.predictedEndTranslation.width + size.width / 2
                let y = origin.y + value.predictedEndTranslation.height + size.height / 2
                withAnimation(snap) {
                    corner = WindowCorner(leading: x < bounds.midX, top: y < bounds.midY)
                    dragTranslation = .zero
                }
            }
    }

    private var pinch: some Gesture {
        MagnifyGesture()
            .onChanged { pinchScale = $0.magnification }
            .onEnded { value in
                withAnimation(snap) {
                    if value.magnification > 1.1 { expanded = true }
                    else if value.magnification < 0.9 { expanded = false }
                    pinchScale = 1
                }
            }
    }

    private func controls(compact: Bool) -> some View {
        let icon: CGFloat = compact ? 15 : 18
        return VStack(spacing: 6) {
            HStack(spacing: 4) {
                Button(action: onClose) {
                    Image(systemName: "xmark").frame(width: 32, height: 32)
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
                    Image(systemName: "arrow.triangle.2.circlepath.camera").frame(width: 36, height: 36)
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
                    Image(systemName: "stop.fill").frame(width: 36, height: 36)
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
        // Fills the 9:16 window. A landscape picture shows its centre, the
        // same crop the recording is saved with.
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
