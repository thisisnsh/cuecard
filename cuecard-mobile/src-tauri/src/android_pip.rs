// Android PiP FFI bindings
// This module provides the interface to call Kotlin code from Rust via JNI

#[cfg(target_os = "android")]
use jni::{
    objects::{JObject, JValue},
    JNIEnv,
};

#[cfg(target_os = "android")]
fn with_jni<F, R>(f: F) -> Result<R, String>
where
    F: FnOnce(&mut JNIEnv, &JObject) -> Result<R, String>,
{
    let ctx = ndk_context::android_context();
    let vm = unsafe { jni::JavaVM::from_raw(ctx.vm().cast()) }.map_err(|e| e.to_string())?;
    let activity = unsafe { JObject::from_raw(ctx.context().cast()) };
    let mut env = vm.attach_current_thread().map_err(|e| e.to_string())?;

    f(&mut env, &activity)
}

/// Start the Android PiP teleprompter
#[cfg(target_os = "android")]
pub fn start_teleprompter(
    content: &str,
    font_size: u32,
    default_speed: f32,
    opacity: f32,
) -> Result<(), String> {
    log::info!(
        "Android PiP start: content_len={}, font_size={}, speed={}, opacity={}",
        content.len(),
        font_size,
        default_speed,
        opacity
    );

    with_jni(|env, _activity| {
        let content_jstring = env
            .new_string(content)
            .map_err(|e| format!("Failed to create string: {}", e))?;

        env.call_static_method(
            "com/thisisnsh/cuecard/mobile/TeleprompterBridge",
            "startTeleprompter",
            "(Ljava/lang/String;IFF)V",
            &[
                JValue::Object(&content_jstring),
                JValue::Int(font_size as i32),
                JValue::Float(default_speed),
                JValue::Float(opacity),
            ],
        )
        .map_err(|e| format!("Failed to call startTeleprompter: {}", e))?;

        Ok(())
    })
}

/// Pause the Android PiP teleprompter
#[cfg(target_os = "android")]
pub fn pause_teleprompter() -> Result<(), String> {
    log::info!("Android PiP pause");

    with_jni(|env, _activity| {
        env.call_static_method(
            "com/thisisnsh/cuecard/mobile/TeleprompterBridge",
            "pauseTeleprompter",
            "()V",
            &[],
        )
        .map_err(|e| format!("Failed to call pauseTeleprompter: {}", e))?;

        Ok(())
    })
}

/// Resume the Android PiP teleprompter
#[cfg(target_os = "android")]
pub fn resume_teleprompter() -> Result<(), String> {
    log::info!("Android PiP resume");

    with_jni(|env, _activity| {
        env.call_static_method(
            "com/thisisnsh/cuecard/mobile/TeleprompterBridge",
            "resumeTeleprompter",
            "()V",
            &[],
        )
        .map_err(|e| format!("Failed to call resumeTeleprompter: {}", e))?;

        Ok(())
    })
}

/// Stop the Android PiP teleprompter
#[cfg(target_os = "android")]
pub fn stop_teleprompter() -> Result<(), String> {
    log::info!("Android PiP stop");

    with_jni(|env, _activity| {
        env.call_static_method(
            "com/thisisnsh/cuecard/mobile/TeleprompterBridge",
            "stopTeleprompter",
            "()V",
            &[],
        )
        .map_err(|e| format!("Failed to call stopTeleprompter: {}", e))?;

        Ok(())
    })
}

// Stubs for non-Android platforms
#[cfg(not(target_os = "android"))]
pub fn start_teleprompter(
    _content: &str,
    _font_size: u32,
    _default_speed: f32,
    _opacity: f32,
) -> Result<(), String> {
    Err("Android PiP is only available on Android".to_string())
}

#[cfg(not(target_os = "android"))]
pub fn pause_teleprompter() -> Result<(), String> {
    Err("Android PiP is only available on Android".to_string())
}

#[cfg(not(target_os = "android"))]
pub fn resume_teleprompter() -> Result<(), String> {
    Err("Android PiP is only available on Android".to_string())
}

#[cfg(not(target_os = "android"))]
pub fn stop_teleprompter() -> Result<(), String> {
    Err("Android PiP is only available on Android".to_string())
}
