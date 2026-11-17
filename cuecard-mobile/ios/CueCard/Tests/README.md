# Recording audio regression checks

Run from `cuecard-mobile/ios`:

```sh
bash CueCard/Tests/run-audio-tests.sh
bash CueCard/Tests/run-microphone-tests.sh <booted-iOS-simulator-UDID>
```

The first runner compiles the production audio forwarding code on macOS and
checks both startup orders, recognition pause/resume, closing the camera,
discarding callbacks from the previous source, and concurrent handoff. Requests
are spies; it does not perform speech recognition or access the microphone.

The simulator runner compiles the production microphone coordinator and checks
that camera ownership prevents engine startup, restart, and playback-only audio
configuration. It also checks duplicate preparation, unrelated camera release,
and a previous reader's delayed stop. It does not open a microphone or camera.

## Code paths reviewed

| Path | Audio behavior |
| --- | --- |
| Follow Me before camera | Stop the engine on the shared queue before configuring capture; replace the recognition request for camera buffers. |
| Camera before Follow Me | Attach recognition to camera buffers without changing the audio session. |
| Follow Me toggled during a take | Attach/detach recognition; leave the movie input and audio session alone. |
| Camera close, background, or preparation failure | Release camera ownership after capture stops; a listening reader can restart its engine. |
| Reopen, switch camera, or change video settings | Capture work uses the same queue as microphone ownership. Switching cameras retains the audio input. |
| Route or engine configuration change | Replace the recognition request; rebuild the engine tap only when no camera owns audio. |
| Camera interruption/runtime error | Existing capture handlers stop the take and report the interruption; speech cannot start a competing engine while capture owns audio. |
| iOS 18+ pause/resume | Movie output handles pausing; recognition keeps receiving camera samples. Verify the movie audio connection before resuming. |
| iOS 17 pause/resume | Separate movie segments retain the same capture input; joining copies each audio track at its corresponding timeline offset. |
| Save or recover a pending take | Save the movie directly to Photos; warn if audio tracks are absent or have no positive duration. This does not detect silence encoded inside a valid track. |
| Dismiss a loading take player | Cancellation prevents playback; shared queue ownership prevents delayed playback setup from changing recording audio. |

Movie and audio-data outputs can coexist on the supported iOS versions; see
[Apple's capture-session output restrictions](https://developer.apple.com/documentation/avfoundation/avcapturesession/canaddoutput(_:)).
Speech accepts camera sample buffers through
[`appendAudioSampleBuffer`](https://developer.apple.com/documentation/speech/sfspeechaudiobufferrecognitionrequest/appendaudiosamplebuffer(_:)).

## Device validation still required

Use a physical iPhone with the built-in mic, then repeat with Bluetooth and a
USB mic if available. Speak recognizable words and listen to each saved movie
in Photos as well as the app's take player.

- Start Follow Me first, then open the camera and record; repeat in reverse order.
- Toggle Follow Me and pause/resume it during a continuous recording.
- Pause/resume recording several times; include iOS 17 to exercise segment joining.
- Close and reopen the camera while Follow Me is listening; switch front/back cameras.
- Disconnect/reconnect the external mic, interrupt with a call, and background/foreground the app.
- Deny microphone or speech permission and verify that no silent take starts.
- Open a take that loads slowly, dismiss it, and immediately start a new recording.
- Verify ordinary recordings without Follow Me and the saved video settings still work.
