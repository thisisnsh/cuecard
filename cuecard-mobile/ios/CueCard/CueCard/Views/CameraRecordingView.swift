import AVFoundation
import SwiftUI

/// Keeps the same reader mounted at its original layout size. Camera mode only
/// scales and moves that view, preserving its scroll position and all controls.
/// The enclosing navigation bar stays outside this container.
struct CameraRecordingView<Reader: View>: View {
    @Binding var isPresented: Bool
    let scriptID: UUID?
    var onRecordingActiveChange: (Bool) -> Void = { _ in }
    @ViewBuilder let reader: () -> Reader
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openURL) private var openURL
    @StateObject private var recorder = CameraRecorder()
    @State private var rotation: AVCaptureDevice.RotationCoordinator?
    @State private var panelOrigin = CGPoint(x: 12, y: 12)
    @GestureState private var panelDrag = CGSize.zero
    @State private var expanded = false
    @State private var previousIdleTimerDisabled = false
    @State private var controlsHeight: CGFloat = 168

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let scale = readerScale(in: size)
            let panel = CGSize(width: size.width * scale, height: size.height * scale + 36)
            let origin = clampedOrigin(panelOrigin, drag: panelDrag, size: size, panel: panel)
            ZStack(alignment: .topLeading) {
                if isPresented {
                    CameraPreview(session: recorder.capture.session, device: recorder.device)
                        .background(.black)
                        .ignoresSafeArea()
                    VStack {
                        Spacer(minLength: 0)
                        recordingControls
                            .background(GeometryReader { controls in
                                Color.clear.preference(key: RecordingControlsHeight.self, value: controls.size.height)
                            })
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
                }

                // Never branch or replace the reader when entering camera mode.
                reader()
                    .frame(width: size.width, height: size.height)
                    .clipped()
                    .scaleEffect(isPresented ? scale : 1, anchor: .topLeading)
                    .frame(width: isPresented ? panel.width : size.width,
                           height: isPresented ? panel.height - 36 : size.height, alignment: .topLeading)
                    .padding(.top, isPresented ? 36 : 0)
                    .background(isPresented ? Color.black : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: isPresented ? 20 : 0))
                    .overlay(alignment: .top) {
                        if isPresented { panelHandle(size: size, panel: panel) }
                    }
                    .overlay {
                        if isPresented {
                            RoundedRectangle(cornerRadius: 20).stroke(.white.opacity(0.3))
                        }
                    }
                    .shadow(color: .black.opacity(isPresented ? 0.35 : 0), radius: 12, y: 6)
                    .offset(x: isPresented ? origin.x : 0, y: isPresented ? origin.y : 0)
            }
            .onPreferenceChange(RecordingControlsHeight.self) { height in
                if height > 0 { controlsHeight = height }
            }
        }
        .background {
            if !isPresented { AppColors.background(for: colorScheme).ignoresSafeArea() }
        }
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
        .onChange(of: recorder.device) { _, device in
            rotation = device.map { AVCaptureDevice.RotationCoordinator(device: $0, previewLayer: nil) }
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

    private var recordingControls: some View {
        VStack(spacing: 8) {
            if let message = recorder.message {
                Text(message).font(.footnote).multilineTextAlignment(.center)
                    .accessibilityAddTraits(.updatesFrequently)
            }
            if let url = recorder.pendingURL {
                HStack {
                    Button("Save to Photos") { Task { await recorder.savePending() } }
                    ShareLink(item: url) { Label("Share Video", systemImage: "square.and.arrow.up") }
                    Button("Record Another") { recorder.keepPendingForLater() }
                }
                .font(.caption.weight(.semibold))
                .disabled(recorder.isBusy)
            }
            if recorder.needsSettings {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 24) {
                    zoomControls.frame(width: 180)
                    captureControls.frame(minWidth: 300)
                }
                VStack(spacing: 8) {
                    zoomControls
                    captureControls
                }
            }
        }
        .foregroundStyle(.white)
        .tint(.white)
        .padding(12)
        .background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 24))
    }

    private var zoomControls: some View {
        HStack(spacing: 12) {
            Image(systemName: "minus.magnifyingglass")
            Slider(value: Binding(get: { recorder.zoom }, set: { recorder.setZoom($0) }),
                   in: 1...max(1.01, recorder.maxZoom))
                .accessibilityLabel("Camera Zoom")
                .disabled(!recorder.isReady || recorder.maxZoom <= 1)
            Text(String(format: "%.1f×", recorder.zoom)).monospacedDigit().font(.caption)
        }
    }

    private var captureControls: some View {
        HStack(spacing: 24) {
            Button { Task { await recorder.switchCamera() } } label: {
                Image(systemName: "arrow.triangle.2.circlepath.camera").frame(width: 48, height: 48)
            }
            .accessibilityLabel("Flip Camera")
            .disabled(!recorder.isReady || recorder.isBusy || recorder.isRecording)
            Spacer(minLength: 0)
            Button {
                if recorder.isRecording { recorder.togglePause() }
                else { recorder.start(rotation: rotation?.videoRotationAngleForHorizonLevelCapture ?? 90) }
            } label: {
                ZStack {
                    Circle().fill(.red).frame(width: 64, height: 64)
                    if recorder.isBusy { ProgressView().tint(.white) }
                    else { Image(systemName: recorder.isRecording && !recorder.isPaused ? "pause.fill" : "play.fill") }
                }
            }
            .accessibilityLabel(recorder.isRecording ? (recorder.isPaused ? "Resume Recording" : "Pause Recording") : "Record Video")
            .disabled(recorder.isBusy || (!recorder.isRecording && (!recorder.isReady || recorder.pendingURL != nil)))
            Button {
                recorder.stop()
                onRecordingActiveChange(false)
            } label: {
                Image(systemName: "stop.fill").frame(width: 48, height: 48)
            }
            .accessibilityLabel("Stop Recording")
            .disabled(!recorder.isRecording || recorder.isBusy)
            Spacer(minLength: 0)
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(TeleprompterParser.formatTime(Int(recorder.recordedDuration(at: context.date))))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(recorder.isPaused ? .yellow : .white)
            }
            .accessibilityLabel(recorder.isPaused ? "Recording paused" : "Recording duration")
        }
        .font(.system(size: 22, weight: .semibold))
    }

    private func panelHandle(size: CGSize, panel: CGSize) -> some View {
        HStack(spacing: 0) {
            Image(systemName: "line.3.horizontal")
                .frame(maxWidth: .infinity, minHeight: 36)
                .contentShape(Rectangle())
                .gesture(DragGesture()
                    .updating($panelDrag) { value, state, _ in state = value.translation }
                    .onEnded { value in
                        panelOrigin = clampedOrigin(panelOrigin, drag: value.translation, size: size, panel: panel)
                    })
                .accessibilityLabel("Move floating reader")
                .accessibilityAction(named: "Move to Top") { panelOrigin = CGPoint(x: 12, y: 12) }
                .accessibilityAction(named: "Move to Bottom") { panelOrigin = CGPoint(x: 12, y: size.height) }
            Button { expanded.toggle() } label: {
                Image(systemName: expanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                    .frame(width: 44, height: 36)
            }
            .accessibilityLabel(expanded ? "Make Reader Smaller" : "Make Reader Larger")
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.white)
    }

    private func readerScale(in size: CGSize) -> CGFloat {
        guard isPresented, size.width > 0, size.height > 0 else { return 1 }
        let availableHeight = max(1, size.height - controlsHeight - 68)
        return max(0.01, min(expanded ? 0.85 : 0.65, (size.width - 24) / size.width, availableHeight / size.height))
    }

    private func clampedOrigin(_ point: CGPoint, drag: CGSize, size: CGSize, panel: CGSize) -> CGPoint {
        CGPoint(x: min(max(12, point.x + drag.width), max(12, size.width - panel.width - 12)),
                y: min(max(12, point.y + drag.height), max(12, size.height - panel.height - controlsHeight - 20)))
    }
}

private struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    let device: AVCaptureDevice?

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
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

private struct RecordingControlsHeight: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}
