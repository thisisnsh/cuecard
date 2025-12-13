fn main() {
    // Load .env file from the project root (2 levels up from src-tauri)
    let root_dir = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .unwrap()
        .parent()
        .unwrap()
        .to_path_buf();
    let env_path = root_dir.join(".env");

    // Try to load .env file
    if env_path.exists() {
        match dotenvy::from_path(&env_path) {
            Ok(_) => {
                println!("cargo:warning=Loaded .env file from {}", env_path.display());

                // Read environment variables and set them as compile-time env vars
                if let Ok(client_id) = std::env::var("GOOGLE_CLIENT_ID") {
                    println!("cargo:rustc-env=GOOGLE_CLIENT_ID={}", client_id);
                }
                if let Ok(client_secret) = std::env::var("GOOGLE_CLIENT_SECRET") {
                    println!("cargo:rustc-env=GOOGLE_CLIENT_SECRET={}", client_secret);
                }
                if let Ok(project_id) = std::env::var("FIRESTORE_PROJECT_ID") {
                    println!("cargo:rustc-env=FIRESTORE_PROJECT_ID={}", project_id);
                }
            }
            Err(e) => {
                println!("cargo:warning=Failed to load .env file: {}", e);
            }
        }
    } else {
        println!(
            "cargo:warning=No .env file found at {}. Using system environment variables.",
            env_path.display()
        );
    }

    // Tell cargo to rerun if .env changes
    println!("cargo:rerun-if-changed={}", env_path.display());

    tauri_build::build()
}
