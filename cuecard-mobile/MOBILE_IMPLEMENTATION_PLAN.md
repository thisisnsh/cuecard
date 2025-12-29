# CueCard Mobile Implementation Plan

## Current Status

### Completed
- [x] Tauri mobile project initialized with iOS target
- [x] Frontend with paste notes view and syntax highlighting
- [x] Firebase OAuth with deep link callbacks
- [x] Local persistence for notes and settings (tauri-plugin-store)
- [x] Settings UI for font size, scroll speed, opacity
- [x] Rust backend compiles successfully

### Remaining (Requires Native Development)
- [ ] iOS Picture-in-Picture teleprompter plugin (Swift)
- [ ] Android Picture-in-Picture teleprompter plugin (Kotlin)
- [ ] Dynamic scroll speed based on [time mm:ss] segments
- [ ] Android Studio setup and Android SDK installation

---

## Updated Requirements

### Unified PiP Teleprompter (Both Platforms)

Both Android and iOS will use **native Picture-in-Picture** for the teleprompter:
- **iOS**: `AVPictureInPictureController` with `AVSampleBufferDisplayLayer`
- **Android**: Native PiP mode (Android 8.0+ `enterPictureInPictureMode`)

### Text Formatting in PiP

1. **`[note content]`** - Highlighted in pink, stays visible in teleprompter
2. **`[time mm:ss]`** - Controls scroll speed for the section below it

### Dynamic Scroll Speed Algorithm

```
For each section of text:
1. If section starts with [time mm:ss]:
   - Calculate: scroll_speed = section_height / (mm*60 + ss) pixels/second
   - Timer shows countdown on top-left (fixed position)

2. If no [time mm:ss]:
   - Use default scroll speed from settings
   - No timer shown on top-left
```

**Example:**
```
Welcome everyone! [time 00:30]     <- This section scrolls in 30 seconds
I'm excited to be here today.
Let me introduce myself.

[time 01:00]                       <- This section scrolls in 1 minute
Now let's talk about our main topic.
[note pause for effect]
This is very important...

Final thoughts.                    <- No timer, uses default speed
Thank you!
```

### PiP UI Layout

```
┌─────────────────────────────────┐
│ [00:28]  ←── Fixed timer        │
│                                 │
│  Welcome everyone!              │  ← Text scrolls up
│  I'm excited to be here today.  │
│  Let me introduce myself.       │
│                                 │
│  [pause for effect] ← pink      │
│                                 │
└─────────────────────────────────┘
```

- **Timer (top-left)**: Fixed position, counts down
- **Text**: Scrolls upward at calculated speed
- **[note]**: Displayed in pink, scrolls with text
- **[time mm:ss]**: Hidden from display, only controls speed

### Playback Controls

Both platforms support:
- **Play/Pause** - Native PiP controls
- **Close** - Exit PiP mode

---

## Implementation Details

### Phase 1: Parse Notes into Segments

```typescript
interface Segment {
  text: string;           // Text content (with [note] but without [time])
  duration: number | null; // Seconds, or null for default speed
  startTime: number;       // Cumulative start time
}

function parseNotesIntoSegments(notes: string): Segment[] {
  // Split by [time mm:ss] pattern
  // Calculate durations and start times
  // Preserve [note content] for pink highlighting
}
```

### Phase 2: iOS Swift Plugin (`PiPManager.swift`)

```swift
class TeleprompterPiPManager {
    private var pipController: AVPictureInPictureController?
    private var displayLayer: AVSampleBufferDisplayLayer
    private var segments: [Segment]
    private var currentSegmentIndex: Int
    private var scrollOffset: CGFloat
    private var isPaused: Bool

    func startTeleprompter(content: String, fontSize: CGFloat, defaultSpeed: CGFloat)
    func pauseTeleprompter()
    func resumeTeleprompter()
    func stopTeleprompter()

    private func renderFrame() {
        // 1. Calculate current segment based on elapsed time
        // 2. Update timer display
        // 3. Calculate scroll offset based on segment speed
        // 4. Render text with pink [note] highlights
        // 5. Convert to CMSampleBuffer and enqueue
    }
}
```

### Phase 3: Android Kotlin Plugin (`PiPTeleprompterPlugin.kt`)

```kotlin
class PiPTeleprompterActivity : AppCompatActivity() {
    private var segments: List<Segment>
    private var currentSegmentIndex: Int
    private var scrollOffset: Float
    private var isPaused: Boolean

    override fun onPictureInPictureModeChanged(isInPipMode: Boolean) {
        // Handle PiP mode changes
    }

    fun enterPiPMode() {
        val params = PictureInPictureParams.Builder()
            .setAspectRatio(Rational(16, 9))
            .setActions(listOf(playPauseAction))
            .build()
        enterPictureInPictureMode(params)
    }

    private fun renderTeleprompter() {
        // Similar logic to iOS
        // Use SurfaceView or custom View for rendering
    }
}
```

### Phase 4: Segment Speed Calculation

```rust
// In lib.rs
struct Segment {
    text: String,
    duration_seconds: Option<u32>,
    height_pixels: f32,  // Calculated after rendering
}

impl Segment {
    fn scroll_speed(&self, default_speed: f32) -> f32 {
        match self.duration_seconds {
            Some(duration) if duration > 0 => {
                self.height_pixels / duration as f32
            }
            _ => default_speed
        }
    }
}
```

---

## File Structure

```
cuecard-mobile/
├── src/
│   ├── main.ts                    # Frontend (already created)
│   └── styles.css                 # Styling (already created)
├── src-tauri/
│   ├── src/
│   │   ├── lib.rs                 # Main Rust code
│   │   └── teleprompter.rs        # Segment parsing logic
│   ├── gen/
│   │   ├── android/
│   │   │   └── app/src/main/
│   │   │       ├── java/.../
│   │   │       │   ├── PiPTeleprompterPlugin.kt
│   │   │       │   └── TeleprompterActivity.kt
│   │   │       └── AndroidManifest.xml
│   │   └── apple/
│   │       └── Sources/
│   │           ├── PiPPlugin.swift
│   │           └── TeleprompterPiPManager.swift
```

---

## Android PiP Requirements

### Manifest
```xml
<activity
    android:name=".TeleprompterActivity"
    android:supportsPictureInPicture="true"
    android:configChanges="screenSize|smallestScreenSize|screenLayout|orientation"
    android:launchMode="singleTask">
</activity>
```

### Min SDK
- Android 8.0 (API 26) for basic PiP
- Android 12 (API 31) for seamless resize

---

## iOS PiP Requirements

### Info.plist
```xml
<key>UIBackgroundModes</key>
<array>
    <string>audio</string>
</array>
```

### Audio Session
```swift
try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
try AVAudioSession.sharedInstance().setActive(true)
```

---

## Next Steps

1. Create `teleprompter.rs` for segment parsing
2. Update `lib.rs` to pass segments to native code
3. Implement iOS `TeleprompterPiPManager.swift`
4. Set up Android Studio and implement `PiPTeleprompterPlugin.kt`
5. Test on physical devices (PiP requires real device)
