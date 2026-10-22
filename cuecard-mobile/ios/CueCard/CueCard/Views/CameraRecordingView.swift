import AVFoundation
import SwiftUI

/// Keeps the reader full screen and floats the camera above it in a 9:16
/// window styled like Picture in Picture. The reader is never replaced, so its
/// scroll position and controls survive turning the camera on and off.
struct CameraRecordingView<Reader: View>: View {
    @Binding var isPresented: Bool
    let scriptID: UUID?
    var onRecordingActiveChange: (Bool) -> Void = { _ in }
    @ViewBuilder let reader: () -> Reader
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var recorder = CameraRecorder()
    // Only where the window settles lives here. The live drag and pinch stay
    // inside the window so they never re-render the reader.
    @State private var corner = WindowCorner.topTrailing
    @State private var expanded = false
    @State private var previousIdleTimerDisabled = false

    var body: some View {
        reader()
            .overlay(alignment: .topLeading) {
                if isPresented {
                    GeometryReader { geometry in
                        FloatingCameraWindow(recorder: recorder, container: geometry.size,
                                             corner: $corner, expanded: $expanded,
                                             onClose: { isPresented = false },
                                             onStop: { onRecordingActiveChange(false) })
                    }
                    .transition(.opacity)
                }
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: isPresented)
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
                    onRecordingActiveChange(false)
                    UIApplication.shared.isIdleTimerDisabled = previousIdleTimerDisabled
                }
            }
            .onChange(of: recorder.isRecording) { _, _ in updatePromptPlayback() }
            .onChange(of: recorder.isPaused) { _, _ in updatePromptPlayback() }
            .onChange(of: scenePhase) { _, phase in
                guard isPresented else { return }
                if phase == .background {
                    recorder.suspend()
                    onRecordingActiveChange(false)
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
                    onRecordingActiveChange(false)
                    UIApplication.shared.isIdleTimerDisabled = previousIdleTimerDisabled
                }
            }
    }

    private func updatePromptPlayback() {
        guard isPresented else { return }
        onRecordingActiveChange(scenePhase == .active && recorder.isRecording && !recorder.isPaused)
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

/// The camera preview and its controls. Drag to move it, it snaps to the
/// nearest corner; pinch or double-tap to change its size; tap to show or hide
/// the controls.
private struct FloatingCameraWindow: View {
    @ObservedObject var recorder: CameraRecorder
    let container: CGSize
    @Binding var corner: WindowCorner
    @Binding var expanded: Bool
    let onClose: () -> Void
    let onStop: () -> Void
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var rotation: AVCaptureDevice.RotationCoordinator?
    @State private var dragTranslation = CGSize.zero
    @State private var pinchScale: CGFloat = 1
    @State private var showsControls = true

    private static let margin: CGFloat = 12
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
        .shadow(color: .black.opacity(0.3), radius: 16, y: 6)
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
        .onChange(of: recorder.device, initial: true) { _, device in
            rotation = device.map { AVCaptureDevice.RotationCoordinator(device: $0, previewLayer: nil) }
        }
    }

    /// Collapsed and expanded widths, followed live while pinching and always
    /// kept short enough to fit the container's height.
    private var windowSize: CGSize {
        let small = min(container.width * 0.36, 180)
        let large = min(container.width * 0.6, 320)
        let fit = max(1, (container.height - Self.margin * 2) / Self.aspect)
        let width = min(max((expanded ? large : small) * pinchScale, small * 0.8), large * 1.1, fit)
        return CGSize(width: width, height: width * Self.aspect)
    }

    private func origin(for corner: WindowCorner, size: CGSize) -> CGPoint {
        CGPoint(x: corner.isLeading ? Self.margin : container.width - size.width - Self.margin,
                y: corner.isTop ? Self.margin : container.height - size.height - Self.margin)
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
                    corner = WindowCorner(leading: x < container.width / 2, top: y < container.height / 2)
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
            if recorder.pendingURL != nil || recorder.needsSettings {
                pendingActions
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
                    onStop()
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

    private var pendingActions: some View {
        HStack(spacing: 4) {
            if let url = recorder.pendingURL {
                Button { Task { await recorder.savePending() } } label: {
                    Image(systemName: "square.and.arrow.down").frame(width: 32, height: 32)
                }
                .accessibilityLabel("Save to Photos")
                ShareLink(item: url) {
                    Image(systemName: "square.and.arrow.up").frame(width: 32, height: 32)
                }
                .accessibilityLabel("Share Video")
                Button { recorder.keepPendingForLater() } label: {
                    Image(systemName: "record.circle").frame(width: 32, height: 32)
                }
                .accessibilityLabel("Record Another")
            }
            if recorder.needsSettings {
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                } label: {
                    Image(systemName: "gearshape").frame(width: 32, height: 32)
                }
                .accessibilityLabel("Open Settings")
            }
        }
        .padding(.horizontal, 4)
        .background(.black.opacity(0.5), in: Capsule())
        .disabled(recorder.isBusy)
    }

    private func recordButton(diameter: CGFloat) -> some View {
        Button {
            if recorder.isRecording { recorder.togglePause() }
            else { recorder.start(rotation: rotation?.videoRotationAngleForHorizonLevelCapture ?? 90) }
        } label: {
            ZStack {
                Circle().fill(.red).frame(width: diameter, height: diameter)
                Circle().stroke(.white, lineWidth: 2).frame(width: diameter + 6, height: diameter + 6)
                if recorder.isBusy { ProgressView().tint(.white) }
                else { Image(systemName: recorder.isRecording && !recorder.isPaused ? "pause.fill" : "play.fill") }
            }
        }
        .accessibilityLabel(recorder.isRecording ? (recorder.isPaused ? "Resume Recording" : "Pause Recording") : "Record Video")
        .disabled(recorder.isBusy || (!recorder.isRecording && (!recorder.isReady || recorder.pendingURL != nil)))
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

    /// Steps through 1×, 2× and 3×, as far as the camera allows.
    private var zoomButton: some View {
        let steps = [1.0, 2.0, 3.0].filter { $0 <= recorder.maxZoom }
        let next = steps.first { $0 > recorder.zoom + 0.05 } ?? 1
        return Button { recorder.setZoom(next) } label: {
            Text("\(Int(recorder.zoom.rounded()))×")
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
