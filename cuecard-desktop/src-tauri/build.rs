use std::path::Path;

fn main() {
    // Verify firebase-config.json exists at build time
    let firebase_config_path = Path::new("firebase-config.json");
    if !firebase_config_path.exists() {
        panic!(
            "\n\n\
            ========================================\n\
            ERROR: firebase-config.json not found!\n\
            ========================================\n\n\
            The Firebase configuration file is required for the build.\n\n\
            To fix this:\n\
            1. Copy the example file:\n\
               cp firebase-config.example.json firebase-config.json\n\n\
            2. Fill in your Firebase project settings from:\n\
               Firebase Console -> Project Settings -> Your apps\n\n\
            See README.md for more details.\n\n"
        );
    }

    // Tell Cargo to re-run this build script if firebase-config.json changes
    println!("cargo:rerun-if-changed=firebase-config.json");

    tauri_build::build()
}
