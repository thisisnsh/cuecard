import Foundation
import AVKit

// MARK: - C FFI Bridge for Rust

/// Start the teleprompter PiP
/// - Parameters:
///   - content: Pointer to UTF-8 C string with the notes content
///   - fontSize: Font size in points
///   - defaultSpeed: Default scroll speed multiplier (1.0 = normal)
///   - opacity: Opacity value (0.0 to 1.0)
@_cdecl("swift_start_pip_teleprompter")
public func startPipTeleprompter(
    content: UnsafePointer<CChar>,
    fontSize: UInt32,
    defaultSpeed: Float,
    opacity: Float
) {
    let contentString = String(cString: content)

    DispatchQueue.main.async {
        if #available(iOS 15.0, *) {
            TeleprompterPiPManager.shared.startTeleprompter(
                content: contentString,
                fontSize: CGFloat(fontSize),
                defaultSpeed: CGFloat(defaultSpeed),
                opacity: opacity
            )
        } else {
            print("PiP teleprompter requires iOS 15.0 or later")
        }
    }
}

/// Pause the teleprompter
@_cdecl("swift_pause_pip_teleprompter")
public func pausePipTeleprompter() {
    DispatchQueue.main.async {
        if #available(iOS 15.0, *) {
            TeleprompterPiPManager.shared.pause()
        }
    }
}

/// Resume the teleprompter
@_cdecl("swift_resume_pip_teleprompter")
public func resumePipTeleprompter() {
    DispatchQueue.main.async {
        if #available(iOS 15.0, *) {
            TeleprompterPiPManager.shared.resume()
        }
    }
}

/// Stop the teleprompter and exit PiP
@_cdecl("swift_stop_pip_teleprompter")
public func stopPipTeleprompter() {
    DispatchQueue.main.async {
        if #available(iOS 15.0, *) {
            TeleprompterPiPManager.shared.stop()
        }
    }
}

/// Check if PiP is supported on this device
/// - Returns: 1 if supported, 0 if not
@_cdecl("swift_is_pip_supported")
public func isPipSupported() -> Int32 {
    if #available(iOS 15.0, *) {
        return TeleprompterPiPManager.isPiPSupported() ? 1 : 0
    }
    return 0
}
