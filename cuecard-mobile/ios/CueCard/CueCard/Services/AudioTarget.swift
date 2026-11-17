import AVFoundation
import Speech

/// The request the microphone's audio goes to, set on the main thread and
/// read on the audio thread.
final class AudioTarget: @unchecked Sendable {
    enum Source { case engine, camera }
    private let lock = NSLock()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var source = Source.engine

    func select(_ source: Source) {
        lock.withLock {
            self.source = source
            request = nil
        }
    }

    func set(_ request: SFSpeechAudioBufferRecognitionRequest?) {
        lock.withLock { self.request = request }
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        lock.withLock {
            guard source == .engine else { return }
            request?.append(buffer)
        }
    }

    func append(_ buffer: CMSampleBuffer) {
        lock.withLock {
            guard source == .camera else { return }
            request?.appendAudioSampleBuffer(buffer)
        }
    }
}
