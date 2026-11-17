import AVFoundation
import Speech

/// Runs on macOS without accessing a microphone or starting recognition.
/// Compile with the production AudioTarget.swift (see run-audio-tests.sh).
private final class RequestSpy: SFSpeechAudioBufferRecognitionRequest {
    private let lock = NSLock()
    private var pcmCount = 0
    private var sampleCount = 0

    var counts: (pcm: Int, samples: Int) { lock.withLock { (pcmCount, sampleCount) } }

    override func append(_ audioPCMBuffer: AVAudioPCMBuffer) {
        lock.withLock { pcmCount += 1 }
    }

    override func appendAudioSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        lock.withLock { sampleCount += 1 }
    }
}

@main
private enum AudioTargetTests {
    static func main() throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!
        let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 16)!
        pcm.frameLength = 16
        var sample: CMSampleBuffer?
        let status = CMSampleBufferCreate(allocator: kCFAllocatorDefault, dataBuffer: nil,
                                         dataReady: true, makeDataReadyCallback: nil, refcon: nil,
                                         formatDescription: nil, sampleCount: 0,
                                         sampleTimingEntryCount: 0, sampleTimingArray: nil,
                                         sampleSizeEntryCount: 0, sampleSizeArray: nil,
                                         sampleBufferOut: &sample)
        precondition(status == noErr)
        let camera = sample!
        let target = AudioTarget()

        // Voice first, then camera: only the selected source reaches recognition.
        let voiceRequest = RequestSpy()
        target.set(voiceRequest)
        target.append(pcm)
        target.append(camera)
        precondition(voiceRequest.counts == (1, 0))
        target.select(.camera)
        target.append(pcm)
        target.append(camera)
        precondition(voiceRequest.counts == (1, 0), "Handoff must detach the old-format request")

        let cameraRequest = RequestSpy()
        target.set(cameraRequest)
        target.append(pcm) // A late engine callback must be discarded.
        target.append(camera)
        precondition(cameraRequest.counts == (0, 1))

        // Pausing Follow Me detaches recognition without changing camera ownership.
        target.set(nil)
        target.append(camera)
        precondition(cameraRequest.counts == (0, 1))
        let resumed = RequestSpy()
        target.set(resumed)
        target.append(pcm)
        target.append(camera)
        precondition(resumed.counts == (0, 1))

        // Closing the camera: reject queued camera buffers after the handoff.
        target.select(.engine)
        let voiceAgain = RequestSpy()
        target.set(voiceAgain)
        target.append(camera)
        target.append(pcm)
        precondition(voiceAgain.counts == (1, 0))

        // Camera first: the engine must not feed the initial request either.
        let cameraFirst = AudioTarget()
        cameraFirst.select(.camera)
        let initial = RequestSpy()
        cameraFirst.set(initial)
        cameraFirst.append(pcm)
        cameraFirst.append(camera)
        precondition(initial.counts == (0, 1))

        // A source switch waits for in-flight append calls. Once it returns,
        // no callback can append to the detached request.
        let concurrent = AudioTarget()
        let old = RequestSpy()
        concurrent.set(old)
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async {
            for _ in 0..<10_000 { concurrent.append(pcm) }
            group.leave()
        }
        concurrent.select(.camera)
        let detachedCounts = old.counts
        group.wait()
        precondition(old.counts == detachedCounts)

        print("PASS: voice-first, camera-first, pause/resume, camera close, late buffers, concurrent handoff")
    }
}
