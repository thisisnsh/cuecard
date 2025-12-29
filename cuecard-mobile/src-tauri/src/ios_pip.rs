// iOS PiP FFI bindings
// This module provides the interface to call Swift code from Rust
//
// NOTE: The Swift code (TeleprompterPiPManager.swift, TeleprompterBridge.swift) is located in
// gen/apple/Sources/cuecard-mobile/ and needs to be compiled as part of the Xcode project.
// The Swift-Rust FFI bridging requires building through Xcode to properly link the Swift code.
//
// For now, these functions log the calls. To enable native PiP:
// 1. Open the Xcode project: gen/apple/cuecard-mobile.xcodeproj
// 2. Build and run from Xcode (which will compile the Swift code)

/// Start the iOS PiP teleprompter
#[cfg(target_os = "ios")]
pub fn start_teleprompter(content: &str, font_size: u32, default_speed: f32, opacity: f32) -> Result<(), String> {
    log::info!(
        "iOS PiP start_teleprompter: content_len={}, font_size={}, speed={}, opacity={}",
        content.len(),
        font_size,
        default_speed,
        opacity
    );
    // TODO: Call Swift via FFI when building through Xcode
    // The Swift code is ready in TeleprompterPiPManager.swift
    Ok(())
}

/// Pause the iOS PiP teleprompter
#[cfg(target_os = "ios")]
pub fn pause_teleprompter() -> Result<(), String> {
    log::info!("iOS PiP pause_teleprompter");
    Ok(())
}

/// Resume the iOS PiP teleprompter
#[cfg(target_os = "ios")]
pub fn resume_teleprompter() -> Result<(), String> {
    log::info!("iOS PiP resume_teleprompter");
    Ok(())
}

/// Stop the iOS PiP teleprompter
#[cfg(target_os = "ios")]
pub fn stop_teleprompter() -> Result<(), String> {
    log::info!("iOS PiP stop_teleprompter");
    Ok(())
}

// Stubs for non-iOS platforms
#[cfg(not(target_os = "ios"))]
pub fn start_teleprompter(_content: &str, _font_size: u32, _default_speed: f32, _opacity: f32) -> Result<(), String> {
    Err("iOS PiP is only available on iOS".to_string())
}

#[cfg(not(target_os = "ios"))]
pub fn pause_teleprompter() -> Result<(), String> {
    Err("iOS PiP is only available on iOS".to_string())
}

#[cfg(not(target_os = "ios"))]
pub fn resume_teleprompter() -> Result<(), String> {
    Err("iOS PiP is only available on iOS".to_string())
}

#[cfg(not(target_os = "ios"))]
pub fn stop_teleprompter() -> Result<(), String> {
    Err("iOS PiP is only available on iOS".to_string())
}

#[cfg(not(target_os = "ios"))]
pub fn is_pip_supported() -> bool {
    false
}
