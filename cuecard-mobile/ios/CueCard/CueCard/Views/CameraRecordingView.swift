import AVFoundation
import SwiftUI

/// An in-app camera with a draggable reader above its preview. Only the capture
/// session is written to the movie; the reader and controls stay on screen.
struct CameraRecordingView: View {
    enum Prompt {
        case teleprompter(TeleprompterContent)
        case cards
    }
    let prompt: Prompt
    let scriptID: UUID?
    @EnvironmentObject private var settingsService: SettingsService
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @StateObject private var recorder = CameraRecorder()
    @State private var rotation: AVCaptureDevice.RotationCoordinator?
    @State private var showingStopConfirmation = false
    @State private var panelOrigin = CGPoint(x: 12, y: 68)
    @GestureState private var panelDrag = CGSize.zero
    @State private var expanded = false
    @State private var minimized = false
    @State private var previousIdleTimerDisabled = false
    @State private var controlsHeight: CGFloat = 112

    private var title: String {
        switch prompt {
        case .teleprompter: String(localized: "Teleprompter")
        case .cards: String(localized: "Cards")
        }
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                CameraPreview(session: recorder.capture.session, device: recorder.device)
                    .ignoresSafeArea()
                Color.black.opacity(0.12).ignoresSafeArea().allowsHitTesting(false)

                VStack {
                    topBar
                    Spacer(minLength: 0)
                    recordingControls
                        .frame(width: geometry.size.width > geometry.size.height ? landscapeControlsWidth(in: geometry.size) : nil)
                        .background(GeometryReader { controls in
                            Color.clear.preference(key: RecordingControlsHeight.self, value: controls.size.height)
                        })
                        .frame(maxWidth: .infinity, alignment: geometry.size.width > geometry.size.height ? .trailing : .center)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)

                floatingPanel(in: geometry.size)
            }
            .background(.black)
            .onPreferenceChange(RecordingControlsHeight.self) { controlsHeight = $0 }
        }
        .preferredColorScheme(.dark)
        .interactiveDismissDisabled()
        .statusBarHidden()
        .task {
            previousIdleTimerDisabled = UIApplication.shared.isIdleTimerDisabled
            UIApplication.shared.isIdleTimerDisabled = true
            await recorder.prepare(scriptID: scriptID)
        }
        .onChange(of: recorder.device) { _, device in
            rotation = device.map { AVCaptureDevice.RotationCoordinator(device: $0, previewLayer: nil) }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                recorder.suspend()
                pausePrompt()
            } else if phase == .active {
                Task { await recorder.prepare(scriptID: scriptID) }
            }
        }
        .onDisappear {
            recorder.suspend()
            pausePrompt()
            UIApplication.shared.isIdleTimerDisabled = previousIdleTimerDisabled
        }
        .confirmationDialog("Stop recording and save this video?", isPresented: $showingStopConfirmation, titleVisibility: .visible) {
            Button("Stop and Save") { recorder.stop(); pausePrompt() }
            Button("Keep Recording", role: .cancel) { }
        }
    }

    private var topBar: some View {
        HStack {
            Button {
                if recorder.isRecording { showingStopConfirmation = true }
                else { dismiss() }
            } label: {
                Image(systemName: "xmark").frame(width: 44, height: 44)
                    .background(.black.opacity(0.55), in: Circle())
            }
            .accessibilityLabel("Close Camera")
            .disabled(recorder.isBusy)
            Spacer()
            if let start = recorder.startedAt {
                TimelineView(.periodic(from: start, by: 1)) { context in
                    Label(TeleprompterParser.formatTime(max(0, Int(context.date.timeIntervalSince(start)))), systemImage: "record.circle.fill")
                        .monospacedDigit()
                        .foregroundStyle(.red)
                        .padding(10)
                        .background(.black.opacity(0.75), in: Capsule())
                }
                .accessibilityLabel("Recording duration")
            } else {
                Text("Camera").font(.headline)
            }
            Spacer()
            Button {
                Task { await recorder.switchCamera() }
            } label: {
                Image(systemName: "arrow.triangle.2.circlepath.camera")
                    .frame(width: 44, height: 44)
                    .background(.black.opacity(0.55), in: Circle())
            }
            .accessibilityLabel("Switch Camera")
            .disabled(!recorder.isReady || recorder.isBusy || recorder.isRecording)
        }
        .foregroundStyle(.white)
    }

    private var recordingControls: some View {
        VStack(spacing: 10) {
            if let message = recorder.message {
                Text(message)
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .padding(10)
                    .background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityAddTraits(.updatesFrequently)
            }
            if let url = recorder.pendingURL {
                HStack {
                    Button("Save to Photos") { Task { await recorder.savePending() } }
                    ShareLink(item: url) { Label("Share Video", systemImage: "square.and.arrow.up") }
                }
                .font(.subheadline.weight(.semibold))
                .buttonStyle(.borderedProminent)
                .disabled(recorder.isBusy)
                Button("Record Another") { recorder.keepPendingForLater() }
                    .font(.footnote)
                    .disabled(recorder.isBusy)
            }
            if recorder.needsSettings {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
                .buttonStyle(.bordered)
            }
            Button {
                if recorder.isRecording {
                    recorder.stop()
                    pausePrompt()
                } else {
                    recorder.start(rotation: rotation?.videoRotationAngleForHorizonLevelCapture ?? 90)
                }
            } label: {
                ZStack {
                    Circle().stroke(.white, lineWidth: 4).frame(width: 76, height: 76)
                    if recorder.isBusy {
                        ProgressView().tint(.white)
                    } else {
                        RoundedRectangle(cornerRadius: recorder.isRecording ? 6 : 32)
                            .fill(.red)
                            .frame(width: recorder.isRecording ? 30 : 62, height: recorder.isRecording ? 30 : 62)
                    }
                }
                .frame(width: 88, height: 88)
            }
            .accessibilityLabel(recorder.isRecording ? "Stop Recording" : "Record Video")
            .disabled(recorder.isBusy || (!recorder.isRecording && (!recorder.isReady || recorder.pendingURL != nil)))
            .opacity(!recorder.isReady && !recorder.isRecording ? 0.5 : 1)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .onChange(of: recorder.isRecording) { _, recording in
            if recording, scenePhase == .active, recorder.isReady, case .teleprompter = prompt {
                TeleprompterPiPManager.shared.play()
            } else if !recording {
                pausePrompt()
            }
        }
    }

    private func floatingPanel(in size: CGSize) -> some View {
        let landscape = size.width > size.height
        let availableWidth = landscape ? size.width - landscapeControlsWidth(in: size) - 48 : size.width - 24
        let width = min(max(0, availableWidth), expanded ? 540 : 340)
        let availableHeight = max(100, size.height - (landscape ? 84 : controlsHeight + 84))
        let height: CGFloat = minimized ? 44 : min(expanded ? 430 : 290, availableHeight)
        let origin = clampedOrigin(panelOrigin, drag: panelDrag, size: size, panel: CGSize(width: width, height: height))
        return VStack(spacing: 0) {
            HStack(spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "line.3.horizontal")
                    Text(title).font(.caption.weight(.semibold))
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
                .gesture(DragGesture()
                    .updating($panelDrag) { value, state, _ in state = value.translation }
                    .onEnded { value in
                        panelOrigin = clampedOrigin(panelOrigin, drag: value.translation, size: size,
                                                    panel: CGSize(width: width, height: height))
                    })
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Move floating prompt")
                .accessibilityHint("Drag to reposition the window")
                .accessibilityAction(named: "Move to Top") { panelOrigin = CGPoint(x: 12, y: 68) }
                .accessibilityAction(named: "Move to Bottom") { panelOrigin = CGPoint(x: 12, y: size.height - height - 120) }
                Button { expanded.toggle(); minimized = false } label: {
                    Image(systemName: expanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel(expanded ? "Make Prompt Smaller" : "Make Prompt Larger")
                Button { minimized.toggle() } label: {
                    Image(systemName: minimized ? "chevron.down" : "minus").frame(width: 44, height: 44)
                }
                .accessibilityLabel(minimized ? "Expand Prompt" : "Minimize Prompt")
            }
            .padding(.leading, 14)
            if !minimized {
                Divider()
                switch prompt {
                case let .teleprompter(content):
                    RecordingTeleprompter(content: content)
                case .cards:
                    RecordingCards()
                }
            }
        }
        .foregroundStyle(.white)
        .frame(width: width, height: height)
        .background(.black.opacity(0.88), in: RoundedRectangle(cornerRadius: 20))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(.white.opacity(0.25)))
        .shadow(color: .black.opacity(0.4), radius: 16, y: 8)
        .offset(x: origin.x, y: origin.y)
    }

    private func clampedOrigin(_ point: CGPoint, drag: CGSize, size: CGSize, panel: CGSize) -> CGPoint {
        let landscape = size.width > size.height
        let rightInset: CGFloat = landscape ? landscapeControlsWidth(in: size) + 36 : 12
        let bottomInset: CGFloat = landscape ? 12 : controlsHeight + 24
        return CGPoint(x: min(max(12, point.x + drag.width), max(12, size.width - panel.width - rightInset)),
                       y: min(max(60, point.y + drag.height), max(60, size.height - panel.height - bottomInset)))
    }

    private func landscapeControlsWidth(in size: CGSize) -> CGFloat {
        min(320, size.width * 0.4)
    }

    private func pausePrompt() {
        if case .teleprompter = prompt { TeleprompterPiPManager.shared.pause() }
    }
}

private struct RecordingTeleprompter: View {
    let content: TeleprompterContent
    @EnvironmentObject private var settingsService: SettingsService
    @ObservedObject private var playback = TeleprompterPiPManager.shared
    private var settings: TeleprompterSettings { settingsService.settings }
    private var running: Bool { playback.playback.isPlaying || playback.playback.isCountingDown }

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geometry in
                AttributedTextView(
                    content: content, cueColor: settings.cueColor,
                    fontSize: CGFloat(min(settings.fontSize, 32)),
                    linePosition: playback.playback.scriptTime * Double(settings.linesPerMinute) / 60,
                    colorScheme: .dark, topPadding: geometry.size.height * 0.3,
                    bottomPadding: geometry.size.height * 0.7,
                    snapToken: playback.playback.snapToken, restorationRequest: nil,
                    onRestorationReady: { _ in },
                    onLayoutChange: { playback.updateReferenceLayout($0) },
                    onHandOff: { playback.seek(toLine: $0) }, onTap: nil,
                    attachesPiPSource: false
                )
                .scaleEffect(x: playback.isMirrored ? -1 : 1, y: 1)
            }
            HStack {
                Button { playback.restart() } label: {
                    Image(systemName: "arrow.counterclockwise").frame(width: 44, height: 44)
                }.accessibilityLabel("Restart Prompt")
                Spacer()
                Button { playback.togglePlayPause() } label: {
                    if playback.playback.isCountingDown {
                        Text("\(playback.playback.countdownValue)").frame(width: 44, height: 44)
                    } else {
                        Image(systemName: running ? "pause.fill" : "play.fill").frame(width: 44, height: 44)
                    }
                }.accessibilityLabel(running ? "Pause Prompt" : "Play Prompt")
                Spacer()
                Menu {
                    Button("Slower") { settingsService.settings.linesPerMinute = max(TeleprompterSettings.lpmRange.lowerBound, settings.linesPerMinute - 5) }
                    Button("Faster") { settingsService.settings.linesPerMinute = min(TeleprompterSettings.lpmRange.upperBound, settings.linesPerMinute + 5) }
                    Button("Mirror Text") { playback.toggleMirroring() }
                } label: {
                    Image(systemName: "slider.horizontal.3").frame(width: 44, height: 44)
                }.accessibilityLabel("Prompt Controls")
            }
            .padding(.horizontal, 12)
        }
    }
}

private struct RecordingCards: View {
    @EnvironmentObject private var settingsService: SettingsService
    @ObservedObject private var session = CueCardsSession.shared

    var body: some View {
        VStack(spacing: 0) {
            Group {
                if session.isFinished {
                    Text("All cards done").font(.headline).frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        CueCards.runs(for: session.cards[session.index])
                            .text(primary: .white, cue: settingsService.settings.cards.cueColor.color(for: .dark),
                                  cueFont: .system(size: 20, weight: .semibold))
                            .font(.system(size: min(CGFloat(settingsService.settings.cards.fontSize), 28)))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16)
                    }
                    .id(session.index)
                }
            }
            .contentShape(Rectangle())
            .simultaneousGesture(DragGesture(minimumDistance: 20).onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height), abs(value.translation.width) > 45 else { return }
                if value.translation.width < 0 { session.next() } else { session.previous() }
            })
            HStack {
                Button { session.previous() } label: {
                    Image(systemName: "chevron.left").frame(width: 44, height: 44)
                }
                .disabled(session.index == 0)
                .accessibilityLabel("Previous Card")
                Spacer()
                Text(session.isFinished ? String(localized: "Done") : "\(session.index + 1) / \(session.cards.count)")
                    .font(.caption.monospacedDigit())
                Spacer()
                Button {
                    if session.isFinished { session.restart() } else { session.next() }
                } label: {
                    Image(systemName: session.isFinished ? "arrow.counterclockwise" : "chevron.right")
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel(session.isFinished ? "Restart Cards" : "Next Card")
            }
            .padding(.horizontal, 12)
        }
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
    static var defaultValue: CGFloat = 112
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
