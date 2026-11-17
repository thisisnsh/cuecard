import AVFoundation

// The standalone runner doesn't link Firebase or start a VoiceFollower.
enum AnalyticsEvents {
    static func logButtonClick(_ name: String, screen: String, parameters: [String: String]) {}
}

@main
private enum MicrophoneTests {
    static func main() async throws {
        let microphone = Microphone.shared
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default)
        let camera = UUID()
        await onQueue { microphone.useCamera(camera) }

        // Starting speech while capture owns the mic must never open an engine
        // or reconfigure the audio session, including after configuration changes.
        let first = AudioTarget()
        try await microphone.start(into: first)
        try await microphone.restart()
        await microphone.preparePlayback()
        precondition(!microphone.engine.isRunning)
        precondition(session.category == .playAndRecord)

        // Re-preparing a camera is idempotent; an unrelated suspend cannot
        // release its ownership and let delayed playback change its category.
        await onQueue {
            microphone.useCamera(camera)
            microphone.releaseCamera(UUID())
        }
        microphone.stop(target: first)
        await microphone.preparePlayback()
        precondition(session.category == .playAndRecord)

        // Replace the reader while a previous stop is queued. The stale stop
        // must not clear the new listener, even after the camera closes.
        let second = AudioTarget()
        try await microphone.start(into: second)
        microphone.stop(target: first)
        await onQueue { microphone.releaseCamera(camera) }
        await microphone.preparePlayback()
        precondition(session.category == .playAndRecord)

        // Once both owners have released capture, playback can configure audio.
        microphone.stop(target: second)
        await microphone.preparePlayback()
        precondition(session.category == .playback)
        precondition(!microphone.engine.isRunning)
        print("PASS: camera ownership, restart suppression, delayed playback, duplicate prepare, stale stop, release")
    }

    private static func onQueue(_ work: @escaping @Sendable () -> Void) async {
        await withCheckedContinuation { continuation in
            Microphone.shared.queue.async {
                work()
                continuation.resume()
            }
        }
    }
}
