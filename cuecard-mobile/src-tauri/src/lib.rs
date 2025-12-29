use once_cell::sync::Lazy;
use parking_lot::RwLock;
use serde::{Deserialize, Serialize};
use std::fs;
use std::path::PathBuf;
use std::sync::Arc;
use tauri::{AppHandle, Emitter, Listener, Manager};
use tauri_plugin_store::StoreExt;

mod teleprompter;
pub use teleprompter::{TeleprompterContent, TeleprompterSegment};

#[cfg(target_os = "ios")]
mod ios_pip;

#[cfg(target_os = "android")]
mod android_pip;

// =============================================================================
// TYPES
// =============================================================================

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Settings {
    #[serde(rename = "fontSize")]
    pub font_size: u32,
    #[serde(rename = "scrollSpeed")]
    pub scroll_speed: f32,
    pub opacity: u32,
}

impl Default for Settings {
    fn default() -> Self {
        Self {
            font_size: 16,
            scroll_speed: 1.0,
            opacity: 100,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UserInfo {
    pub name: String,
    pub email: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FirebaseConfig {
    pub firebase: FirebaseInner,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct FirebaseInner {
    pub api_key: String,
    pub auth_domain: String,
    pub project_id: String,
    pub storage_bucket: String,
    pub messaging_sender_id: String,
    pub app_id: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct FirebaseTokens {
    pub id_token: String,
    pub refresh_token: String,
    pub expires_at: i64,
    pub email: String,
    pub local_id: String,
    pub display_name: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct OAuthCredentials {
    pub client_id: String,
    pub client_secret: String,
}

// =============================================================================
// GLOBAL STATE
// =============================================================================

static FIREBASE_CONFIG: Lazy<RwLock<Option<FirebaseConfig>>> = Lazy::new(|| RwLock::new(None));
static FIREBASE_TOKENS: Lazy<RwLock<Option<FirebaseTokens>>> = Lazy::new(|| RwLock::new(None));
static OAUTH_CREDENTIALS: Lazy<RwLock<Option<OAuthCredentials>>> = Lazy::new(|| RwLock::new(None));

// Storage keys
const STORE_NAME: &str = "cuecard-mobile-store.json";
const KEY_FIREBASE_TOKENS: &str = "firebase_tokens";
const KEY_OAUTH_CREDENTIALS: &str = "oauth_credentials";
const KEY_NOTES: &str = "notes_content";
const KEY_SETTINGS: &str = "settings";

// =============================================================================
// FIREBASE CONFIG LOADING
// =============================================================================

fn load_firebase_config(app: &AppHandle) -> Result<FirebaseConfig, String> {
    // Try resource directory first (bundled app)
    let resource_dir = app.path().resource_dir().ok();

    let paths_to_try: Vec<PathBuf> = vec![
        resource_dir
            .as_ref()
            .map(|p| p.join("firebase-config.json"))
            .unwrap_or_default(),
        PathBuf::from("firebase-config.json"),
        PathBuf::from("src-tauri/firebase-config.json"),
    ];

    for path in paths_to_try {
        if path.exists() {
            let content =
                fs::read_to_string(&path).map_err(|e| format!("Failed to read config: {}", e))?;
            let config: FirebaseConfig = serde_json::from_str(&content)
                .map_err(|e| format!("Failed to parse config: {}", e))?;
            return Ok(config);
        }
    }

    Err("firebase-config.json not found".to_string())
}

// =============================================================================
// STORAGE HELPERS
// =============================================================================

fn get_store(
    app: &AppHandle,
) -> Result<Arc<tauri_plugin_store::Store<tauri::Wry>>, String> {
    app.store(STORE_NAME)
        .map_err(|e| format!("Failed to get store: {}", e))
}

fn save_to_store<T: Serialize>(app: &AppHandle, key: &str, value: &T) -> Result<(), String> {
    let store = get_store(app)?;
    store.set(key, serde_json::to_value(value).map_err(|e| e.to_string())?);
    store
        .save()
        .map_err(|e| format!("Failed to save store: {}", e))?;
    Ok(())
}

fn load_from_store<T: for<'de> Deserialize<'de>>(
    app: &AppHandle,
    key: &str,
) -> Result<Option<T>, String> {
    let store = get_store(app)?;
    match store.get(key) {
        Some(value) => {
            let parsed: T = serde_json::from_value(value.clone())
                .map_err(|e| format!("Failed to parse value: {}", e))?;
            Ok(Some(parsed))
        }
        None => Ok(None),
    }
}

// =============================================================================
// AUTHENTICATION
// =============================================================================

#[tauri::command]
async fn get_auth_status(app: AppHandle) -> Result<bool, String> {
    // Check if we have valid tokens in memory
    let tokens_opt = {
        let tokens = FIREBASE_TOKENS.read();
        tokens.clone()
    };

    if let Some(ref t) = tokens_opt {
        let now = chrono::Utc::now().timestamp();
        if t.expires_at > now + 300 && !t.id_token.is_empty() {
            return Ok(true);
        }
    }

    // Try to load from store
    if let Ok(Some(saved_tokens)) = load_from_store::<FirebaseTokens>(&app, KEY_FIREBASE_TOKENS) {
        let now = chrono::Utc::now().timestamp();
        if saved_tokens.expires_at > now + 300 && !saved_tokens.id_token.is_empty() {
            *FIREBASE_TOKENS.write() = Some(saved_tokens);
            return Ok(true);
        }
        // Token expired, try to refresh
        if refresh_firebase_token(&app).await.is_ok() {
            return Ok(true);
        }
    }

    Ok(false)
}

#[tauri::command]
async fn get_user_info(app: AppHandle) -> Result<Option<UserInfo>, String> {
    // First try memory
    let tokens_opt = {
        let tokens = FIREBASE_TOKENS.read();
        tokens.clone()
    };

    if let Some(ref t) = tokens_opt {
        if !t.email.is_empty() {
            return Ok(Some(UserInfo {
                name: t.display_name.clone(),
                email: t.email.clone(),
            }));
        }
    }

    // Try from store
    if let Ok(Some(saved_tokens)) = load_from_store::<FirebaseTokens>(&app, KEY_FIREBASE_TOKENS) {
        if !saved_tokens.email.is_empty() {
            return Ok(Some(UserInfo {
                name: saved_tokens.display_name,
                email: saved_tokens.email,
            }));
        }
    }

    Ok(None)
}

#[tauri::command]
async fn start_login(app: AppHandle) -> Result<(), String> {
    // Ensure we have OAuth credentials
    ensure_oauth_credentials(&app).await?;

    let auth_url = {
        let credentials = OAUTH_CREDENTIALS.read();
        let creds = credentials
            .as_ref()
            .ok_or("OAuth credentials not available")?;

        // Build OAuth URL with deep link redirect
        let redirect_uri = "cuecard://oauth/callback";
        let scope = "openid email profile";

        format!(
            "https://accounts.google.com/o/oauth2/v2/auth?\
            client_id={}&\
            redirect_uri={}&\
            response_type=code&\
            scope={}&\
            access_type=offline&\
            prompt=consent",
            urlencoding::encode(&creds.client_id),
            urlencoding::encode(redirect_uri),
            urlencoding::encode(scope)
        )
    };

    // Open in system browser
    tauri_plugin_opener::open_url(&auth_url, None::<&str>)
        .map_err(|e| format!("Failed to open browser: {}", e))?;

    Ok(())
}

#[tauri::command]
async fn logout(app: AppHandle) -> Result<(), String> {
    // Clear memory
    *FIREBASE_TOKENS.write() = None;

    // Clear store
    let store = get_store(&app)?;
    store.delete(KEY_FIREBASE_TOKENS);
    store
        .save()
        .map_err(|e| format!("Failed to save store: {}", e))?;

    Ok(())
}

async fn ensure_oauth_credentials(app: &AppHandle) -> Result<(), String> {
    // Check if already loaded
    {
        if OAUTH_CREDENTIALS.read().is_some() {
            return Ok(());
        }
    }

    // Try to load from store
    if let Ok(Some(creds)) = load_from_store::<OAuthCredentials>(app, KEY_OAUTH_CREDENTIALS) {
        *OAUTH_CREDENTIALS.write() = Some(creds);
        return Ok(());
    }

    // Need to fetch from Firestore using anonymous auth
    let (api_key, project_id) = {
        let config = FIREBASE_CONFIG.read();
        let config = config.as_ref().ok_or("Firebase config not loaded")?;
        (
            config.firebase.api_key.clone(),
            config.firebase.project_id.clone(),
        )
    };

    // Sign in anonymously
    let anon_token = sign_in_anonymously(&api_key).await?;

    // Fetch OAuth credentials from Firestore
    let creds = fetch_oauth_credentials(&project_id, &anon_token).await?;

    // Save to store
    save_to_store(app, KEY_OAUTH_CREDENTIALS, &creds)?;
    *OAUTH_CREDENTIALS.write() = Some(creds);

    Ok(())
}

async fn sign_in_anonymously(api_key: &str) -> Result<String, String> {
    let client = reqwest::Client::new();
    let url = format!(
        "https://identitytoolkit.googleapis.com/v1/accounts:signUp?key={}",
        api_key
    );

    let response = client
        .post(&url)
        .json(&serde_json::json!({
            "returnSecureToken": true
        }))
        .send()
        .await
        .map_err(|e| format!("Anonymous sign in failed: {}", e))?;

    let data: serde_json::Value = response
        .json()
        .await
        .map_err(|e| format!("Failed to parse response: {}", e))?;

    data["idToken"]
        .as_str()
        .map(|s| s.to_string())
        .ok_or_else(|| "No idToken in response".to_string())
}

async fn fetch_oauth_credentials(
    project_id: &str,
    token: &str,
) -> Result<OAuthCredentials, String> {
    let client = reqwest::Client::new();
    let url = format!(
        "https://firestore.googleapis.com/v1/projects/{}/databases/(default)/documents/Configs/v-1",
        project_id
    );

    let response = client
        .get(&url)
        .header("Authorization", format!("Bearer {}", token))
        .send()
        .await
        .map_err(|e| format!("Failed to fetch OAuth credentials: {}", e))?;

    let data: serde_json::Value = response
        .json()
        .await
        .map_err(|e| format!("Failed to parse response: {}", e))?;

    let fields = data
        .get("fields")
        .ok_or("No fields in Firestore document")?;

    let client_id = fields
        .get("google_client_id")
        .and_then(|v| v.get("stringValue"))
        .and_then(|v| v.as_str())
        .ok_or("Missing google_client_id")?
        .to_string();

    let client_secret = fields
        .get("google_client_secret")
        .and_then(|v| v.get("stringValue"))
        .and_then(|v| v.as_str())
        .ok_or("Missing google_client_secret")?
        .to_string();

    Ok(OAuthCredentials {
        client_id,
        client_secret,
    })
}

async fn refresh_firebase_token(app: &AppHandle) -> Result<(), String> {
    let tokens = load_from_store::<FirebaseTokens>(app, KEY_FIREBASE_TOKENS)?
        .ok_or("No tokens to refresh")?;

    let api_key = {
        let config = FIREBASE_CONFIG.read();
        let config = config.as_ref().ok_or("Firebase config not loaded")?;
        config.firebase.api_key.clone()
    };

    let client = reqwest::Client::new();
    let url = format!(
        "https://securetoken.googleapis.com/v1/token?key={}",
        api_key
    );

    let response = client
        .post(&url)
        .form(&[
            ("grant_type", "refresh_token"),
            ("refresh_token", &tokens.refresh_token),
        ])
        .send()
        .await
        .map_err(|e| format!("Token refresh failed: {}", e))?;

    let data: serde_json::Value = response
        .json()
        .await
        .map_err(|e| format!("Failed to parse response: {}", e))?;

    let new_id_token = data["id_token"]
        .as_str()
        .ok_or("No id_token in refresh response")?;
    let new_refresh_token = data["refresh_token"]
        .as_str()
        .unwrap_or(&tokens.refresh_token);
    let expires_in = data["expires_in"]
        .as_str()
        .and_then(|s| s.parse::<i64>().ok())
        .unwrap_or(3600);

    let new_tokens = FirebaseTokens {
        id_token: new_id_token.to_string(),
        refresh_token: new_refresh_token.to_string(),
        expires_at: chrono::Utc::now().timestamp() + expires_in,
        email: tokens.email,
        local_id: tokens.local_id,
        display_name: tokens.display_name,
    };

    save_to_store(app, KEY_FIREBASE_TOKENS, &new_tokens)?;
    *FIREBASE_TOKENS.write() = Some(new_tokens);

    Ok(())
}

// Handle OAuth callback from deep link
pub async fn handle_oauth_callback(app: &AppHandle, code: &str) -> Result<(), String> {
    let (client_id, client_secret) = {
        let credentials = OAUTH_CREDENTIALS.read();
        let creds = credentials
            .as_ref()
            .ok_or("OAuth credentials not available")?;
        (creds.client_id.clone(), creds.client_secret.clone())
    };

    let api_key = {
        let config = FIREBASE_CONFIG.read();
        let config = config.as_ref().ok_or("Firebase config not loaded")?;
        config.firebase.api_key.clone()
    };

    let client = reqwest::Client::new();

    // Exchange code for Google tokens
    let token_response = client
        .post("https://oauth2.googleapis.com/token")
        .form(&[
            ("code", code),
            ("client_id", client_id.as_str()),
            ("client_secret", client_secret.as_str()),
            ("redirect_uri", "cuecard://oauth/callback"),
            ("grant_type", "authorization_code"),
        ])
        .send()
        .await
        .map_err(|e| format!("Token exchange failed: {}", e))?;

    let token_data: serde_json::Value = token_response
        .json()
        .await
        .map_err(|e| format!("Failed to parse token response: {}", e))?;

    let google_id_token = token_data["id_token"]
        .as_str()
        .ok_or("No id_token in Google response")?;

    // Exchange Google token for Firebase token
    let firebase_url = format!(
        "https://identitytoolkit.googleapis.com/v1/accounts:signInWithIdp?key={}",
        api_key
    );

    let firebase_response = client
        .post(&firebase_url)
        .json(&serde_json::json!({
            "postBody": format!("id_token={}&providerId=google.com", google_id_token),
            "requestUri": "cuecard://oauth/callback",
            "returnIdpCredential": true,
            "returnSecureToken": true
        }))
        .send()
        .await
        .map_err(|e| format!("Firebase auth failed: {}", e))?;

    let firebase_data: serde_json::Value = firebase_response
        .json()
        .await
        .map_err(|e| format!("Failed to parse Firebase response: {}", e))?;

    let id_token = firebase_data["idToken"]
        .as_str()
        .ok_or("No idToken in Firebase response")?;
    let refresh_token = firebase_data["refreshToken"]
        .as_str()
        .ok_or("No refreshToken in Firebase response")?;
    let expires_in = firebase_data["expiresIn"]
        .as_str()
        .and_then(|s| s.parse::<i64>().ok())
        .unwrap_or(3600);
    let email = firebase_data["email"].as_str().unwrap_or("");
    let local_id = firebase_data["localId"].as_str().unwrap_or("");
    let display_name = firebase_data["displayName"].as_str().unwrap_or("");

    let tokens = FirebaseTokens {
        id_token: id_token.to_string(),
        refresh_token: refresh_token.to_string(),
        expires_at: chrono::Utc::now().timestamp() + expires_in,
        email: email.to_string(),
        local_id: local_id.to_string(),
        display_name: display_name.to_string(),
    };

    save_to_store(app, KEY_FIREBASE_TOKENS, &tokens)?;
    *FIREBASE_TOKENS.write() = Some(tokens);

    // Emit auth status event
    app.emit(
        "auth-status",
        serde_json::json!({
            "authenticated": true,
            "user_name": display_name,
            "user_email": email
        }),
    )
    .map_err(|e| format!("Failed to emit event: {}", e))?;

    Ok(())
}

// =============================================================================
// NOTES STORAGE
// =============================================================================

#[tauri::command]
async fn save_notes(app: AppHandle, content: String) -> Result<(), String> {
    save_to_store(&app, KEY_NOTES, &content)
}

#[tauri::command]
async fn get_notes(app: AppHandle) -> Result<Option<String>, String> {
    load_from_store(&app, KEY_NOTES)
}

// =============================================================================
// SETTINGS STORAGE
// =============================================================================

#[tauri::command]
async fn save_settings(app: AppHandle, settings: Settings) -> Result<(), String> {
    save_to_store(&app, KEY_SETTINGS, &settings)
}

#[tauri::command]
async fn get_settings(app: AppHandle) -> Result<Option<Settings>, String> {
    load_from_store(&app, KEY_SETTINGS)
}

// =============================================================================
// TELEPROMPTER PARSING
// =============================================================================

#[tauri::command]
async fn parse_teleprompter_content(content: String) -> Result<TeleprompterContent, String> {
    Ok(teleprompter::parse_notes_to_segments(&content))
}

// =============================================================================
// PIP TELEPROMPTER (Platform-specific implementations)
// =============================================================================

#[tauri::command]
async fn start_pip_teleprompter(
    _app: AppHandle,
    content: String,
    font_size: u32,
    default_scroll_speed: f32,
    opacity: f32,
) -> Result<(), String> {
    log::info!(
        "start_pip_teleprompter: font_size={}, default_speed={}, opacity={}",
        font_size,
        default_scroll_speed,
        opacity
    );

    // Platform-specific implementation
    #[cfg(target_os = "ios")]
    {
        log::info!("Starting iOS PiP teleprompter");
        return ios_pip::start_teleprompter(&content, font_size, default_scroll_speed, opacity);
    }

    #[cfg(target_os = "android")]
    {
        log::info!("Starting Android PiP teleprompter");
        return android_pip::start_teleprompter(&content, font_size, default_scroll_speed, opacity);
    }

    #[cfg(not(any(target_os = "ios", target_os = "android")))]
    {
        let _ = (content, font_size, default_scroll_speed, opacity); // Suppress unused warnings
        log::warn!("PiP teleprompter is only available on iOS and Android");
        Err("PiP is only available on mobile platforms".to_string())
    }
}

#[tauri::command]
async fn pause_pip_teleprompter(_app: AppHandle) -> Result<(), String> {
    log::info!("pause_pip_teleprompter called");

    #[cfg(target_os = "ios")]
    {
        ios_pip::pause_teleprompter()?;
    }

    #[cfg(target_os = "android")]
    {
        android_pip::pause_teleprompter()?;
    }

    Ok(())
}

#[tauri::command]
async fn resume_pip_teleprompter(_app: AppHandle) -> Result<(), String> {
    log::info!("resume_pip_teleprompter called");

    #[cfg(target_os = "ios")]
    {
        ios_pip::resume_teleprompter()?;
    }

    #[cfg(target_os = "android")]
    {
        android_pip::resume_teleprompter()?;
    }

    Ok(())
}

#[tauri::command]
async fn stop_pip_teleprompter(_app: AppHandle) -> Result<(), String> {
    log::info!("stop_pip_teleprompter called");

    #[cfg(target_os = "ios")]
    {
        ios_pip::stop_teleprompter()?;
    }

    #[cfg(target_os = "android")]
    {
        android_pip::stop_teleprompter()?;
    }

    Ok(())
}

// =============================================================================
// APP INITIALIZATION
// =============================================================================

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_opener::init())
        .plugin(tauri_plugin_store::Builder::default().build())
        .plugin(tauri_plugin_deep_link::init())
        .setup(|app| {
            // Load Firebase config
            match load_firebase_config(app.handle()) {
                Ok(config) => {
                    *FIREBASE_CONFIG.write() = Some(config);
                    log::info!("Firebase config loaded successfully");
                }
                Err(e) => {
                    log::error!("Failed to load Firebase config: {}", e);
                }
            }

            // Setup deep link handler
            #[cfg(any(target_os = "android", target_os = "ios"))]
            {
                let handle = app.handle().clone();
                app.listen("deep-link://new-url", move |event| {
                    let payload = event.payload();
                    if let Ok(parsed_urls) = serde_json::from_str::<Vec<String>>(payload) {
                        for url in parsed_urls {
                            if url.starts_with("cuecard://oauth/callback") {
                                if let Some(code) = url
                                    .split("code=")
                                    .nth(1)
                                    .and_then(|s| s.split('&').next())
                                {
                                    let handle_clone = handle.clone();
                                    let code_owned = code.to_string();
                                    tauri::async_runtime::spawn(async move {
                                        if let Err(e) =
                                            handle_oauth_callback(&handle_clone, &code_owned)
                                                .await
                                        {
                                            log::error!("OAuth callback failed: {}", e);
                                        }
                                    });
                                }
                            }
                        }
                    }
                });
            }

            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            get_auth_status,
            get_user_info,
            start_login,
            logout,
            save_notes,
            get_notes,
            save_settings,
            get_settings,
            parse_teleprompter_content,
            start_pip_teleprompter,
            pause_pip_teleprompter,
            resume_pip_teleprompter,
            stop_pip_teleprompter,
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
