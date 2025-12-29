# Android PiP Teleprompter Setup

## Prerequisites

1. Install Android Studio from https://developer.android.com/studio
2. Install Android SDK (API 26+ for PiP support)
3. Set ANDROID_HOME environment variable

## Initialize Android Target

```bash
cd /Users/thisisnsh/Projects/cuecard/cuecard-mobile
npm run tauri android init
```

## Copy Template Files

After initialization, copy the Kotlin files to your Android project:

```bash
# Find the generated package path (usually gen/android/app/src/main/java/com/cuecard/mobile/)
ANDROID_SRC="/Users/thisisnsh/Projects/cuecard/cuecard-mobile/src-tauri/gen/android/app/src/main/java/com/cuecard/mobile"

# Copy the template files
cp /Users/thisisnsh/Projects/cuecard/cuecard-mobile/src-tauri/android-templates/TeleprompterPiPService.kt "$ANDROID_SRC/"
cp /Users/thisisnsh/Projects/cuecard/cuecard-mobile/src-tauri/android-templates/TeleprompterBridge.kt "$ANDROID_SRC/"
```

## Modify MainActivity

Add the TeleprompterBridge initialization to your MainActivity.kt:

```kotlin
import com.cuecard.mobile.TeleprompterBridge

class MainActivity : TauriActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Initialize the teleprompter bridge
        TeleprompterBridge.initialize(this)
    }

    // Handle PiP mode changes
    override fun onPictureInPictureModeChanged(isInPictureInPictureMode: Boolean) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode)
        // Handle PiP state changes if needed
    }
}
```

## Update AndroidManifest.xml

Add PiP support to your activity in AndroidManifest.xml:

```xml
<activity
    android:name=".MainActivity"
    android:supportsPictureInPicture="true"
    android:configChanges="screenSize|smallestScreenSize|screenLayout|orientation"
    ...>
</activity>
```

## Update android_pip.rs

Replace the stub implementation in `src-tauri/src/android_pip.rs` with actual JNI calls:

```rust
use jni::JNIEnv;
use jni::objects::{JClass, JString};

#[cfg(target_os = "android")]
pub fn start_teleprompter(content: &str, font_size: u32, default_speed: f32, opacity: f32) -> Result<(), String> {
    // Get JNI env from tauri
    // This requires setting up the JNI bridge properly with Tauri Android

    // Example JNI call:
    // env.call_static_method(
    //     "com/cuecard/mobile/TeleprompterBridge",
    //     "startTeleprompter",
    //     "(Ljava/lang/String;IFF)V",
    //     &[
    //         JValue::Object(content_jstring.into()),
    //         JValue::Int(font_size as i32),
    //         JValue::Float(default_speed),
    //         JValue::Float(opacity),
    //     ],
    // )

    Ok(())
}
```

## Build and Run

```bash
npm run tauri android build
npm run tauri android dev
```

## Notes

- PiP requires Android 8.0 (API 26) or higher
- The teleprompter renders at 30 FPS using a SurfaceView
- Play/pause controls appear in the PiP window
- Timer is fixed at top-left corner
- [note content] is highlighted in pink
- [time mm:ss] controls scroll speed for following content
