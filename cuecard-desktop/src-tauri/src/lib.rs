//! CueCard - Speaker notes visible only to you
//!
//! This module contains the main backend logic for the CueCard application:
//! - Google Slides sign-in, the one thing an account is ever asked for
//! - Google Slides API integration
//! - Local web server for browser extension communication
//! - Tauri commands for frontend interaction
//! - macOS window management (opacity, screenshot protection)

use axum::{
    extract::Query,
    http::StatusCode,
    response::{Html, Json},
    routing::{get, post},
    Router,
};
use once_cell::sync::Lazy;
use parking_lot::RwLock;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::net::IpAddr::V4;
use std::sync::Arc;
#[cfg(target_os = "macos")]
use tauri::WebviewWindow;
use tauri::{AppHandle, Emitter, Manager};
#[cfg(target_os = "macos")]
use tauri_nspanel::{tauri_panel, CollectionBehavior, PanelLevel, StyleMask, WebviewWindowExt};
use tauri_plugin_global_shortcut::{Code, GlobalShortcutExt, Modifiers, Shortcut};
use tauri_plugin_opener::OpenerExt;
use tauri_plugin_store::StoreExt;
use tower_http::cors::{Any, CorsLayer};
use uuid::Uuid;

// =============================================================================
// CONSTANTS
// =============================================================================

// OAuth2 Configuration
const GOOGLE_AUTH_URL: &str = "https://accounts.google.com/o/oauth2/v2/auth";
const GOOGLE_TOKEN_URL: &str = "https://oauth2.googleapis.com/token";
const REDIRECT_URI: &str = "http://127.0.0.1:3642/oauth/callback";

// Firebase REST API endpoints
const FIREBASE_SIGNUP_URL: &str = "https://identitytoolkit.googleapis.com/v1/accounts:signUp";
/// The worker the phone apps read their notices from. Shared with them on
/// purpose: one list, filtered on each device.
const NOTIFICATIONS_URL: &str = "https://cuecard-mobile.thisisnsh.workers.dev/v2/notifications";

// Analytics
const GA_COLLECT_URL: &str = "https://www.google-analytics.com/mp/collect";
const ANALYTICS_CLIENT_ID_KEY: &str = "analytics_client_id";
const ANALYTICS_FIRST_OPEN_KEY: &str = "analytics_first_open_sent";

// The only thing the app ever asks Google for: the deck being presented.
const SCOPE_SLIDES: &str = "https://www.googleapis.com/auth/presentations.readonly";

// =============================================================================
// DATA TYPES
// =============================================================================

/// Firebase configuration loaded from firebase-config.json
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FirebaseConfig {
    pub api_key: String,
    pub auth_domain: String,
    pub project_id: String,
    pub storage_bucket: Option<String>,
    pub messaging_sender_id: Option<String>,
    pub app_id: Option<String>,
}

/// Analytics configuration (separate Firebase project for security)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AnalyticsConfig {
    pub api_secret: String,
    pub measurement_id: String,
}

#[derive(Debug, Clone)]
struct AnalyticsState {
    measurement_id: String,
    api_secret: String,
    client_id: String,
    platform: Option<String>,
    operating_system: Option<String>,
    ip_override: Option<String>,
    app_version: Option<String>,
    session_id: String,
}

/// Wrapper for firebase-config.json structure
#[derive(Debug, Clone, Serialize, Deserialize)]
struct FirebaseConfigFile {
    firebase: FirebaseConfigInner,
    analytics: AnalyticsConfigInner,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct FirebaseConfigInner {
    api_key: String,
    auth_domain: String,
    project_id: String,
    storage_bucket: Option<String>,
    messaging_sender_id: Option<String>,
    app_id: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct AnalyticsConfigInner {
    measurement_id: String,
    api_secret: String,
}

/// OAuth credentials fetched from Firestore
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct OAuthCredentials {
    pub client_id: String,
    pub client_secret: String,
}

/// Slides API tokens (separate from Firebase auth)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SlidesTokens {
    pub access_token: String,
    pub refresh_token: Option<String>,
    pub expires_at: Option<i64>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SlideData {
    pub presentation_id: String,
    pub slide_id: String,
    pub slide_number: i32,
    pub title: String,
    pub mode: String,
    pub timestamp: i64,
    pub url: String,
    pub force_refresh: Option<bool>,
}

#[derive(Debug, Serialize)]
pub struct ApiResponse {
    received: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    notes: Option<String>,
}

#[derive(Debug, Serialize, Clone)]
pub struct SlideUpdateEvent {
    pub slide_data: SlideData,
    pub notes: Option<String>,
}

#[derive(Debug, Deserialize)]
pub struct OAuthCallback {
    code: Option<String>,
    error: Option<String>,
}

#[derive(Debug, Deserialize)]
#[allow(dead_code)]
struct GoogleTokenResponse {
    access_token: String,
    id_token: Option<String>,
    refresh_token: Option<String>,
    expires_in: Option<i64>,
    scope: Option<String>,
}

#[derive(Debug, Deserialize)]
#[allow(dead_code)]
struct FirebaseSignUpResponse {
    #[serde(rename = "idToken")]
    id_token: String,
    #[serde(rename = "refreshToken")]
    refresh_token: String,
    #[serde(rename = "expiresIn")]
    expires_in: String,
    #[serde(rename = "localId")]
    local_id: String,
}

// =============================================================================
// GLOBAL STATE
// =============================================================================

static CURRENT_SLIDE: Lazy<Arc<RwLock<Option<SlideData>>>> =
    Lazy::new(|| Arc::new(RwLock::new(None)));
static SLIDE_NOTES: Lazy<Arc<RwLock<HashMap<String, String>>>> =
    Lazy::new(|| Arc::new(RwLock::new(HashMap::new())));
/// Where each slide sits in its deck, keyed as the notes are. Google tells the
/// extension which slide is on screen but never which number it is, so the deck
/// is what the number gets counted from.
static SLIDE_NUMBERS: Lazy<Arc<RwLock<HashMap<String, i32>>>> =
    Lazy::new(|| Arc::new(RwLock::new(HashMap::new())));
static CURRENT_PRESENTATION_ID: Lazy<Arc<RwLock<Option<String>>>> =
    Lazy::new(|| Arc::new(RwLock::new(None)));
static APP_HANDLE: Lazy<Arc<RwLock<Option<AppHandle>>>> = Lazy::new(|| Arc::new(RwLock::new(None)));

// Firebase and OAuth state
static FIREBASE_CONFIG: Lazy<Arc<RwLock<Option<FirebaseConfig>>>> =
    Lazy::new(|| Arc::new(RwLock::new(None)));
static ANALYTICS_CONFIG: Lazy<Arc<RwLock<Option<AnalyticsConfig>>>> =
    Lazy::new(|| Arc::new(RwLock::new(None)));
static ANALYTICS_STATE: Lazy<Arc<RwLock<Option<AnalyticsState>>>> =
    Lazy::new(|| Arc::new(RwLock::new(None)));
static OAUTH_CREDENTIALS: Lazy<Arc<RwLock<Option<OAuthCredentials>>>> =
    Lazy::new(|| Arc::new(RwLock::new(None)));
static SLIDES_TOKENS: Lazy<Arc<RwLock<Option<SlidesTokens>>>> =
    Lazy::new(|| Arc::new(RwLock::new(None)));

// =============================================================================
// FIREBASE CONFIGURATION
// =============================================================================

/// Load Firebase and Analytics configuration from firebase-config.json
fn load_firebase_config(app: &AppHandle) -> Result<FirebaseConfig, String> {
    // Try to find firebase-config.json in the resource directory (bundled app)
    // or relative paths (development mode)
    let resource_dir = app.path().resource_dir().ok();

    let possible_paths = vec![
        resource_dir
            .as_ref()
            .map(|p| p.join("firebase-config.json")),
        Some(std::path::PathBuf::from("firebase-config.json")),
        Some(std::path::PathBuf::from("src-tauri/firebase-config.json")),
    ];

    for path in possible_paths.into_iter().flatten() {
        if path.exists() {
            let content = std::fs::read_to_string(&path)
                .map_err(|e| format!("Failed to read firebase-config.json: {}", e))?;
            let config_file: FirebaseConfigFile = serde_json::from_str(&content)
                .map_err(|e| format!("Failed to parse firebase-config.json: {}", e))?;

            let config = FirebaseConfig {
                api_key: config_file.firebase.api_key,
                auth_domain: config_file.firebase.auth_domain,
                project_id: config_file.firebase.project_id,
                storage_bucket: config_file.firebase.storage_bucket,
                messaging_sender_id: config_file.firebase.messaging_sender_id,
                app_id: config_file.firebase.app_id,
            };

            // Load analytics config (only store if properly configured)
            let analytics = config_file.analytics;
            if !analytics.measurement_id.trim().is_empty()
                && !analytics.measurement_id.starts_with("G-XXXX")
            {
                let analytics_config = AnalyticsConfig {
                    measurement_id: analytics.measurement_id,
                    api_secret: analytics.api_secret,
                };
                let mut ac = ANALYTICS_CONFIG.write();
                *ac = Some(analytics_config);
            }

            return Ok(config);
        }
    }

    Err("firebase-config.json not found".to_string())
}

// =============================================================================
// FIREBASE BOOTSTRAP
// =============================================================================

/// Sign in anonymously to Firebase, which is only ever a way in to the OAuth
/// credentials below. Nobody is asked for an account.
async fn sign_in_anonymously() -> Result<String, String> {
    let config = FIREBASE_CONFIG
        .read()
        .clone()
        .ok_or("Firebase config not loaded")?;

    let url = format!("{}?key={}", FIREBASE_SIGNUP_URL, config.api_key);

    let client = reqwest::Client::new();
    let response = client
        .post(&url)
        .json(&serde_json::json!({"returnSecureToken": true}))
        .send()
        .await
        .map_err(|e| format!("Anonymous sign-in request failed: {}", e))?;

    if !response.status().is_success() {
        let error_text = response.text().await.unwrap_or_default();
        return Err(format!("Anonymous sign-in failed: {}", error_text));
    }

    let sign_up_response: FirebaseSignUpResponse = response
        .json()
        .await
        .map_err(|e| format!("Failed to parse sign-up response: {}", e))?;

    Ok(sign_up_response.id_token)
}

/// Fetch OAuth credentials from Firestore Configs/v-1
async fn fetch_oauth_credentials(firebase_token: &str) -> Result<OAuthCredentials, String> {
    let config = FIREBASE_CONFIG
        .read()
        .clone()
        .ok_or("Firebase config not loaded")?;

    let url = format!(
        "https://firestore.googleapis.com/v1/projects/{}/databases/(default)/documents/Configs/v-1",
        config.project_id
    );

    let client = reqwest::Client::new();
    let response = client
        .get(&url)
        .header("Authorization", format!("Bearer {}", firebase_token))
        .send()
        .await
        .map_err(|e| format!("Failed to fetch OAuth credentials: {}", e))?;

    if !response.status().is_success() {
        let status = response.status();
        let error_text = response.text().await.unwrap_or_default();
        return Err(format!(
            "Failed to fetch Configs/v-1: {} - {}",
            status, error_text
        ));
    }

    let doc: serde_json::Value = response
        .json()
        .await
        .map_err(|e| format!("Failed to parse Firestore response: {}", e))?;

    // Extract fields from Firestore document format
    let fields = doc
        .get("fields")
        .ok_or("No fields in Configs/v-1 document")?;

    let client_id = fields
        .get("googleClientId")
        .and_then(|v| v.get("stringValue"))
        .and_then(|v| v.as_str())
        .ok_or("googleClientId not found in Configs/v-1")?
        .to_string();

    let client_secret = fields
        .get("googleClientSecret")
        .and_then(|v| v.get("stringValue"))
        .and_then(|v| v.as_str())
        .ok_or("googleClientSecret not found in Configs/v-1")?
        .to_string();

    Ok(OAuthCredentials {
        client_id,
        client_secret,
    })
}

// =============================================================================
// GOOGLE OAUTH (for Slides API)
// =============================================================================

/// Exchange authorization code for Google tokens
async fn exchange_code_for_google_tokens(code: &str) -> Result<GoogleTokenResponse, String> {
    let credentials = OAUTH_CREDENTIALS
        .read()
        .clone()
        .ok_or("OAuth credentials not available")?;

    let client = reqwest::Client::new();
    let response = client
        .post(GOOGLE_TOKEN_URL)
        .form(&[
            ("code", code),
            ("client_id", &credentials.client_id),
            ("client_secret", &credentials.client_secret),
            ("redirect_uri", REDIRECT_URI),
            ("grant_type", "authorization_code"),
        ])
        .send()
        .await
        .map_err(|e| format!("Token request failed: {}", e))?;

    if !response.status().is_success() {
        let error_text = response.text().await.unwrap_or_default();
        return Err(format!("Token exchange failed: {}", error_text));
    }

    let token_response: GoogleTokenResponse = response
        .json()
        .await
        .map_err(|e| format!("Failed to parse token response: {}", e))?;

    Ok(token_response)
}

/// Refresh Slides API access token
async fn refresh_slides_token() -> Result<(), String> {
    let credentials = OAUTH_CREDENTIALS
        .read()
        .clone()
        .ok_or("OAuth credentials not available")?;

    let refresh_token = {
        let tokens = SLIDES_TOKENS.read();
        tokens
            .as_ref()
            .and_then(|t| t.refresh_token.clone())
            .ok_or("No Slides refresh token available")?
    };

    let client = reqwest::Client::new();
    let response = client
        .post(GOOGLE_TOKEN_URL)
        .form(&[
            ("refresh_token", refresh_token.as_str()),
            ("client_id", &credentials.client_id),
            ("client_secret", &credentials.client_secret),
            ("grant_type", "refresh_token"),
        ])
        .send()
        .await
        .map_err(|e| format!("Token refresh failed: {}", e))?;

    if !response.status().is_success() {
        let error_text = response.text().await.unwrap_or_default();
        return Err(format!("Token refresh failed: {}", error_text));
    }

    let token_response: GoogleTokenResponse = response
        .json()
        .await
        .map_err(|e| format!("Failed to parse token response: {}", e))?;

    let expires_at = token_response
        .expires_in
        .map(|secs| chrono::Utc::now().timestamp() + secs);

    // Update tokens
    {
        let mut tokens = SLIDES_TOKENS.write();
        if let Some(ref mut t) = *tokens {
            t.access_token = token_response.access_token;
            if token_response.refresh_token.is_some() {
                t.refresh_token = token_response.refresh_token;
            }
            t.expires_at = expires_at;
        }
    }

    // Save to persistent storage
    if let Some(app) = APP_HANDLE.read().as_ref() {
        save_slides_tokens_to_store(app);
    }

    Ok(())
}

/// Get valid Slides API access token (refreshes if needed)
async fn get_valid_slides_token() -> Option<String> {
    let (access_token, expires_at, has_refresh) = {
        let tokens = SLIDES_TOKENS.read();
        match tokens.as_ref() {
            Some(t) => (
                t.access_token.clone(),
                t.expires_at,
                t.refresh_token.is_some(),
            ),
            None => return None,
        }
    };

    // Check if token is expired or about to expire (within 5 minutes)
    let now = chrono::Utc::now().timestamp();
    let is_expired = expires_at.map(|exp| now >= exp - 300).unwrap_or(false);

    if is_expired && has_refresh {
        if let Err(e) = refresh_slides_token().await {
            eprintln!("Failed to refresh Slides token: {}", e);
            return None;
        }
        // Return the new token
        let tokens = SLIDES_TOKENS.read();
        return tokens.as_ref().map(|t| t.access_token.clone());
    }

    Some(access_token)
}

// =============================================================================
// TOKEN STORAGE
// =============================================================================

fn save_slides_tokens_to_store(app: &AppHandle) {
    if let Ok(store) = app.store("cuecard-store.json") {
        let tokens = SLIDES_TOKENS.read();
        if let Some(ref t) = *tokens {
            if let Ok(json) = serde_json::to_value(t) {
                store.set("slides_tokens", json);
                let _ = store.save();
            }
        }
    }
}

fn save_oauth_credentials_to_store(app: &AppHandle) {
    if let Ok(store) = app.store("cuecard-store.json") {
        let creds = OAUTH_CREDENTIALS.read();
        if let Some(ref c) = *creds {
            if let Ok(json) = serde_json::to_value(c) {
                store.set("oauth_credentials", json);
                let _ = store.save();
            }
        }
    }
}

fn load_tokens_from_store(app: &AppHandle) {
    if let Ok(store) = app.store("cuecard-store.json") {
        // A sign-in from an older version leaves its tokens behind. Nothing
        // reads them any more, so they go on the way past.
        if store.get("firebase_tokens").is_some() {
            let _ = store.delete("firebase_tokens");
            let _ = store.save();
        }

        // Load Slides tokens
        if let Some(tokens_json) = store.get("slides_tokens") {
            if let Ok(tokens) = serde_json::from_value::<SlidesTokens>(tokens_json.clone()) {
                let mut slides = SLIDES_TOKENS.write();
                *slides = Some(tokens);
            }
        }

        // Load OAuth credentials
        if let Some(creds_json) = store.get("oauth_credentials") {
            if let Ok(creds) = serde_json::from_value::<OAuthCredentials>(creds_json.clone()) {
                let mut oauth = OAUTH_CREDENTIALS.write();
                *oauth = Some(creds);
            }
        }
    }
}

// =============================================================================
// ANALYTICS
// =============================================================================

fn get_or_init_analytics_state(app: &AppHandle) -> Option<AnalyticsState> {
    if ANALYTICS_CONFIG.read().is_none() {
        return None;
    }

    let mut analytics_state = ANALYTICS_STATE.write();
    if let Some(ref state) = *analytics_state {
        return Some(state.clone());
    }

    let config = ANALYTICS_CONFIG.read().clone()?;
    // The device is the identity: this id is made once and kept in the store,
    // so every launch reports as the same client without anyone signing in.
    let client_id = load_or_create_client_id(app);

    // Generate session_id from current timestamp (GA4 uses timestamp as session identifier)
    let session_id = chrono::Utc::now().timestamp_millis().to_string();

    // Get app version from Tauri context
    let app_version = app.config().version.clone();

    let state = AnalyticsState {
        measurement_id: config.measurement_id,
        api_secret: config.api_secret,
        client_id,
        platform: None,
        operating_system: None,
        ip_override: None,
        app_version,
        session_id,
    };

    *analytics_state = Some(state.clone());
    Some(state)
}

fn load_or_create_client_id(app: &AppHandle) -> String {
    if let Ok(store) = app.store("cuecard-store.json") {
        if let Some(value) = store.get(ANALYTICS_CLIENT_ID_KEY) {
            if let Some(client_id) = value.as_str() {
                if !client_id.is_empty() {
                    return client_id.to_string();
                }
            }
        }

        let client_id = generate_client_id();
        store.set(ANALYTICS_CLIENT_ID_KEY, serde_json::json!(client_id));
        let _ = store.save();
        return client_id;
    }

    generate_client_id()
}

fn generate_client_id() -> String {
    Uuid::new_v4().to_string()
}

// =============================================================================
// WEB SERVER HANDLERS
// =============================================================================

async fn health_handler() -> Json<serde_json::Value> {
    Json(serde_json::json!({
        "status": "ok",
        "server": "cuecard-desktop"
    }))
}

async fn slides_handler(
    Json(mut slide_data): Json<SlideData>,
) -> Result<Json<ApiResponse>, StatusCode> {
    let force_refresh = slide_data.force_refresh.unwrap_or(false);

    // Check if presentation changed
    let presentation_changed = {
        let current_pres = CURRENT_PRESENTATION_ID.read();
        current_pres.as_ref() != Some(&slide_data.presentation_id)
    };

    if presentation_changed {
        {
            let mut current_pres = CURRENT_PRESENTATION_ID.write();
            *current_pres = Some(slide_data.presentation_id.clone());
        }
        {
            let mut notes_cache = SLIDE_NOTES.write();
            notes_cache.clear();
            SLIDE_NUMBERS.write().clear();
        }
        let presentation_id = slide_data.presentation_id.clone();
        tokio::spawn(async move {
            let _ = prefetch_all_notes(&presentation_id).await;
        });
    }

    let notes = if force_refresh {
        let fetched = fetch_slide_notes(&slide_data.presentation_id, &slide_data.slide_id).await;
        if let Some(ref note_text) = fetched {
            let mut notes_cache = SLIDE_NOTES.write();
            let key = format!("{}:{}", slide_data.presentation_id, slide_data.slide_id);
            notes_cache.insert(key, note_text.clone());
        }
        fetched
    } else {
        let notes = {
            let notes_cache = SLIDE_NOTES.read();
            let key = format!("{}:{}", slide_data.presentation_id, slide_data.slide_id);
            notes_cache.get(&key).cloned()
        };

        match notes {
            Some(n) => Some(n),
            None => {
                let fetched =
                    fetch_slide_notes(&slide_data.presentation_id, &slide_data.slide_id).await;
                if let Some(ref note_text) = fetched {
                    let mut notes_cache = SLIDE_NOTES.write();
                    let key = format!("{}:{}", slide_data.presentation_id, slide_data.slide_id);
                    notes_cache.insert(key, note_text.clone());
                }
                fetched
            }
        }
    };

    // The extension can only guess the slide's number off Google's own markup;
    // the deck, once it has been read, is what settles it.
    {
        let numbers = SLIDE_NUMBERS.read();
        let key = format!("{}:{}", slide_data.presentation_id, slide_data.slide_id);
        if let Some(number) = numbers.get(&key) {
            slide_data.slide_number = *number;
        }
    }

    {
        let mut current = CURRENT_SLIDE.write();
        *current = Some(slide_data.clone());
    }

    if let Some(app) = APP_HANDLE.read().as_ref() {
        let event = SlideUpdateEvent {
            slide_data: slide_data.clone(),
            notes: notes.clone(),
        };
        let _ = app.emit("slide-update", event);
    }

    Ok(Json(ApiResponse {
        received: true,
        notes,
    }))
}

/// The page Google sends the browser back to, either way it went.
fn browser_page(heading: &str, message: &str) -> Html<String> {
    Html(format!(
        r#"<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>CueCard</title><style>:root{{--bg0:#0b0b0c;--bg1:#121214;--text-strong:rgba(255,255,255,.7);--text-soft:rgba(255,255,255,.55)}}html,body{{height:100%;margin:0;font-family:ui-sans-serif,system-ui,-apple-system,Segoe UI,Roboto,Helvetica,Arial,"Apple Color Emoji","Segoe UI Emoji"}}body{{background:radial-gradient(1200px 600px at 50% 45%,#1a1a1f 0%,#0f0f12 55%,#0a0a0b 100%),linear-gradient(180deg,var(--bg1),var(--bg0));display:grid;place-items:center;color:#fff}}.wrap{{text-align:center;padding:48px 24px;max-width:900px}}h1{{margin:0 0 26px;font-weight:600;letter-spacing:-.02em;color:var(--text-strong);font-size:clamp(44px,6vw,78px);line-height:1.08}}p{{margin:0;font-size:clamp(16px,2vw,26px);line-height:1.5;color:var(--text-soft)}}</style></head><body><main class="wrap" role="main">
        <h1>{}</h1><p>{}</p></main></body></html>"#,
        heading, message
    ))
}

/// Google comes back here with the code for the Slides scope, and nothing else:
/// this is the one thing the app ever signs in for.
async fn oauth_callback_handler(Query(params): Query<OAuthCallback>) -> Html<String> {
    if let Some(error) = params.error {
        return browser_page(
            "Something went wrong",
            &format!("{}. You can close this window.", error),
        );
    }

    let code = match params.code {
        Some(c) => c,
        None => {
            return browser_page(
                "Something went wrong",
                "Google sent no authorization code. You can close this window.",
            )
        }
    };

    let google_tokens = match exchange_code_for_google_tokens(&code).await {
        Ok(tokens) => tokens,
        Err(e) => {
            return browser_page(
                "Something went wrong",
                &format!("{}. You can close this window.", e),
            )
        }
    };

    let expires_at = google_tokens
        .expires_in
        .map(|secs| chrono::Utc::now().timestamp() + secs);

    {
        let mut tokens = SLIDES_TOKENS.write();
        *tokens = Some(SlidesTokens {
            access_token: google_tokens.access_token,
            refresh_token: google_tokens.refresh_token,
            expires_at,
        });
    }

    if let Some(app) = APP_HANDLE.read().as_ref() {
        save_slides_tokens_to_store(app);
        save_oauth_credentials_to_store(app);
        let _ = app.emit(
            "slides-authorized",
            serde_json::json!({ "authorized": true }),
        );
    }

    browser_page(
        "Speak Confidently",
        "You're all set up for Slides Access. You can now close this window.",
    )
}

async fn start_server() {
    let cors = CorsLayer::new()
        .allow_origin(Any)
        .allow_methods(Any)
        .allow_headers(Any);

    let app = Router::new()
        .route("/health", get(health_handler))
        .route("/slides", post(slides_handler))
        .route("/oauth/callback", get(oauth_callback_handler))
        .layer(cors);

    let listener = tokio::net::TcpListener::bind("127.0.0.1:3642")
        .await
        .expect("Failed to bind to port 3642");

    axum::serve(listener, app).await.expect("Server error");
}

// =============================================================================
// GOOGLE SLIDES API
// =============================================================================

async fn prefetch_all_notes(presentation_id: &str) -> Result<(), String> {
    let access_token = match get_valid_slides_token().await {
        Some(token) => token,
        None => return Err("Not authenticated for Slides".to_string()),
    };

    let url = format!(
        "https://slides.googleapis.com/v1/presentations/{}",
        presentation_id
    );

    let client = reqwest::Client::new();
    let response = match client
        .get(&url)
        .header("Authorization", format!("Bearer {}", access_token))
        .send()
        .await
    {
        Ok(r) => r,
        Err(e) => {
            eprintln!("Error fetching slides API for prefetch: {}", e);
            return Err(e.to_string());
        }
    };

    if !response.status().is_success() {
        let status = response.status();
        let error_body = response.text().await.unwrap_or_default();
        eprintln!(
            "Slides API error during prefetch: {} - {}",
            status, error_body
        );
        return Err(format!("API error: {}", status));
    }

    let json: serde_json::Value = match response.json().await {
        Ok(j) => j,
        Err(e) => {
            eprintln!("Failed to parse slides response during prefetch: {}", e);
            return Err(e.to_string());
        }
    };

    let slides = match json.get("slides").and_then(|s| s.as_array()) {
        Some(s) => s,
        None => return Ok(()),
    };

    let mut notes_cache = SLIDE_NOTES.write();
    let mut numbers = SLIDE_NUMBERS.write();

    for (index, slide) in slides.iter().enumerate() {
        if let Some(obj_id) = slide.get("objectId").and_then(|o| o.as_str()) {
            let key = format!("{}:{}", presentation_id, obj_id);
            numbers.insert(key.clone(), index as i32 + 1);
            if let Some(notes_text) = extract_notes_from_slide(slide) {
                notes_cache.insert(key, notes_text);
            }
        }
    }

    Ok(())
}

fn extract_notes_from_slide(slide: &serde_json::Value) -> Option<String> {
    let notes = slide
        .get("slideProperties")?
        .get("notesPage")?
        .get("pageElements")?
        .as_array()?;

    for element in notes {
        if let Some(shape) = element.get("shape") {
            if let Some(placeholder) = shape.get("placeholder") {
                if placeholder.get("type")?.as_str()? == "BODY" {
                    if let Some(text) = shape.get("text") {
                        return extract_text_from_text_elements(text);
                    }
                }
            }
        }
    }

    None
}

async fn fetch_slide_notes(presentation_id: &str, slide_id: &str) -> Option<String> {
    let access_token = match get_valid_slides_token().await {
        Some(token) => token,
        None => return None,
    };

    let url = format!(
        "https://slides.googleapis.com/v1/presentations/{}",
        presentation_id
    );

    let client = reqwest::Client::new();
    let response = match client
        .get(&url)
        .header("Authorization", format!("Bearer {}", access_token))
        .send()
        .await
    {
        Ok(r) => r,
        Err(e) => {
            eprintln!("Error fetching slides API: {}", e);
            return None;
        }
    };

    if !response.status().is_success() {
        eprintln!("Slides API error: {}", response.status());
        return None;
    }

    let json: serde_json::Value = match response.json().await {
        Ok(j) => j,
        Err(e) => {
            eprintln!("Failed to parse slides response: {}", e);
            return None;
        }
    };

    // The whole deck came back, so every slide's number is here to be had, not
    // just the one being asked about.
    let slides = json.get("slides")?.as_array()?;
    let mut numbers = SLIDE_NUMBERS.write();
    let mut wanted = None;

    for (index, slide) in slides.iter().enumerate() {
        let obj_id = match slide.get("objectId").and_then(|o| o.as_str()) {
            Some(id) => id,
            None => continue,
        };
        numbers.insert(
            format!("{}:{}", presentation_id, obj_id),
            index as i32 + 1,
        );
        if obj_id == slide_id {
            wanted = extract_notes_from_slide(slide);
        }
    }

    wanted
}

fn extract_text_from_text_elements(text: &serde_json::Value) -> Option<String> {
    let elements = text.get("textElements")?.as_array()?;
    let mut result = String::new();

    for element in elements {
        if let Some(text_run) = element.get("textRun") {
            if let Some(content) = text_run.get("content").and_then(|c| c.as_str()) {
                result.push_str(content);
            }
        }
    }

    let result = clean_notes_text(&result);
    if result.is_empty() {
        None
    } else {
        Some(result)
    }
}

/// Speaker notes as a script can read them.
///
/// Google writes a line break inside a paragraph as a vertical tab, and the odd
/// zero-width or formatting character finds its way into notes besides. None of
/// them have a glyph, so left in they reach the prompter as empty boxes: the
/// breaks become the line breaks they stand for, the rest go.
fn clean_notes_text(text: &str) -> String {
    text.replace("\r\n", "\n")
        .chars()
        .filter_map(|c| match c {
            '\n' | '\t' => Some(c),
            '\u{000B}' | '\u{000C}' | '\r' | '\u{2028}' | '\u{2029}' => Some('\n'),
            '\u{200B}'..='\u{200F}' | '\u{FEFF}' => None,
            c if c.is_control() => None,
            c => Some(c),
        })
        .collect::<String>()
        .trim()
        .to_string()
}

// =============================================================================
// TAURI COMMANDS
// =============================================================================

#[tauri::command]
fn get_current_slide() -> Option<SlideData> {
    CURRENT_SLIDE.read().clone()
}

#[tauri::command]
fn get_current_notes() -> Option<String> {
    let current = CURRENT_SLIDE.read();
    if let Some(ref slide) = *current {
        let notes = SLIDE_NOTES.read();
        let key = format!("{}:{}", slide.presentation_id, slide.slide_id);
        notes.get(&key).cloned()
    } else {
        None
    }
}

#[tauri::command]
async fn init_analytics(
    app: AppHandle,
    platform: Option<String>,
    operating_system: Option<String>,
) -> Result<(), String> {
    if get_or_init_analytics_state(&app).is_none() {
        return Ok(());
    }

    // Perform IP lookup before acquiring the lock to avoid holding it across await
    let ip_override = if let Ok(response) = public_ip_address::perform_lookup(None).await {
        if let V4(ipv4) = response.ip {
            Some(ipv4.to_string())
        } else {
            None
        }
    } else {
        None
    };

    let mut analytics_state = ANALYTICS_STATE.write();
    if let Some(ref mut state) = *analytics_state {
        state.platform = platform;
        state.operating_system = operating_system;
        state.ip_override = ip_override;
    }
    Ok(())
}

#[tauri::command]
async fn send_event(
    app: AppHandle,
    event_name: String,
    params: Option<HashMap<String, serde_json::Value>>,
) -> Result<(), String> {
    let state = match get_or_init_analytics_state(&app) {
        Some(state) => state,
        None => return Ok(()),
    };

    let AnalyticsState {
        measurement_id,
        api_secret,
        client_id,
        platform,
        operating_system,
        ip_override,
        app_version,
        session_id,
    } = state;

    let mut event_params = params.unwrap_or_default();

    // Add required GA4 parameters for proper tracking
    // engagement_time_msec is required for user activity to display in reports
    if !event_params.contains_key("engagement_time_msec") {
        event_params.insert(
            "engagement_time_msec".to_string(),
            serde_json::Value::Number(serde_json::Number::from(100)),
        );
    }

    // session_id connects events to the same session
    event_params.insert(
        "session_id".to_string(),
        serde_json::Value::String(session_id),
    );

    let mut payload = serde_json::json!({
        "client_id": client_id,
        "events": [{
            "name": event_name,
            "params": event_params
        }]
    });

    // Add ip_override for geo location
    if let Some(ip) = ip_override {
        payload["ip_override"] = serde_json::Value::String(ip);
    }

    // Add user_properties for app_version and platform info
    let mut user_properties = serde_json::json!({});

    if let Some(ref version) = app_version {
        user_properties["app_version"] = serde_json::json!({
            "value": version
        });
    }

    if let Some(ref os) = operating_system {
        user_properties["operating_system"] = serde_json::json!({
            "value": os
        });
    }

    if let Some(ref plat) = platform {
        user_properties["platform"] = serde_json::json!({
            "value": plat
        });
    }

    payload["user_properties"] = user_properties;

    let url = format!(
        "{}?measurement_id={}&api_secret={}",
        GA_COLLECT_URL, measurement_id, api_secret
    );

    let client = reqwest::Client::new();
    let response = client.post(&url).json(&payload).send().await;

    match response {
        Ok(result) => {
            if !result.status().is_success() {
                eprintln!("Analytics send_event failed: {}", result.status());
            }
        }
        Err(error) => {
            eprintln!("Analytics send_event failed: {}", error);
        }
    }

    Ok(())
}

#[tauri::command]
fn check_and_mark_first_open(app: AppHandle) -> bool {
    if let Ok(store) = app.store("cuecard-store.json") {
        // Check if first_open was already sent
        if let Some(value) = store.get(ANALYTICS_FIRST_OPEN_KEY) {
            if value.as_bool().unwrap_or(false) {
                return false; // Not first open
            }
        }

        // Mark as sent
        store.set(ANALYTICS_FIRST_OPEN_KEY, serde_json::json!(true));
        let _ = store.save();
        return true; // This is the first open
    }
    false
}

/// Fetch the notifications payload and hand back the raw JSON.
///
/// The web view cannot do this itself: the worker serves the phone apps over
/// native HTTP and sends no `Access-Control-Allow-Origin`, so a `fetch` from the
/// window is blocked before the body can be read. Asking for it here sidesteps
/// the browser's rules and leaves the mobile worker as it is.
#[tauri::command]
async fn fetch_notifications() -> Result<String, String> {
    let client = reqwest::Client::new();

    let response = client
        .get(NOTIFICATIONS_URL)
        .header("Accept", "application/json")
        .timeout(std::time::Duration::from_secs(5))
        .send()
        .await
        .map_err(|e| format!("Could not reach the notifications worker: {}", e))?;

    if !response.status().is_success() {
        return Err(format!("Notifications worker returned {}", response.status()));
    }

    response
        .text()
        .await
        .map_err(|e| format!("Could not read the notifications response: {}", e))
}

#[tauri::command]
fn has_slides_scope() -> bool {
    SLIDES_TOKENS.read().is_some()
}

/// Open the browser for the one sign-in the app has: read access to the deck
/// being presented. Everything else works without it.
#[tauri::command]
async fn connect_slides(app: AppHandle) -> Result<(), String> {
    // Check if we have OAuth credentials
    let has_credentials = OAUTH_CREDENTIALS.read().is_some();

    if !has_credentials {
        // Bootstrap: sign in anonymously and fetch credentials
        let anon_token = sign_in_anonymously().await?;
        let credentials = fetch_oauth_credentials(&anon_token).await?;

        // Store credentials
        {
            let mut creds = OAUTH_CREDENTIALS.write();
            *creds = Some(credentials.clone());
        }
    }

    // Now build the OAuth URL
    let credentials = OAUTH_CREDENTIALS
        .read()
        .clone()
        .ok_or("OAuth credentials not available")?;

    let auth_url = format!(
        "{}?client_id={}&redirect_uri={}&response_type=code&scope={}&access_type=offline&prompt=consent&include_granted_scopes=true",
        GOOGLE_AUTH_URL,
        urlencoding::encode(&credentials.client_id),
        urlencoding::encode(REDIRECT_URI),
        urlencoding::encode(SCOPE_SLIDES)
    );

    app.opener()
        .open_url(&auth_url, None::<&str>)
        .map_err(|e| format!("Failed to open browser: {}", e))?;

    Ok(())
}

#[tauri::command]
async fn refresh_notes(app: AppHandle) -> Result<Option<String>, String> {
    let current_slide = { CURRENT_SLIDE.read().clone() };

    let slide_data = match current_slide {
        Some(s) => s,
        None => return Err("No current slide".to_string()),
    };

    {
        let mut notes_cache = SLIDE_NOTES.write();
        notes_cache.retain(|k, _| !k.starts_with(&format!("{}:", slide_data.presentation_id)));
    }

    let _ = prefetch_all_notes(&slide_data.presentation_id).await;

    let notes = {
        let notes_cache = SLIDE_NOTES.read();
        let key = format!("{}:{}", slide_data.presentation_id, slide_data.slide_id);
        notes_cache.get(&key).cloned()
    };

    let event = SlideUpdateEvent {
        slide_data: slide_data.clone(),
        notes: notes.clone(),
    };
    let _ = app.emit("slide-update", event);

    Ok(notes)
}

// =============================================================================
// WINDOW MANAGEMENT
// =============================================================================

#[tauri::command]
fn set_screenshot_protection(app: AppHandle, enabled: bool) -> Result<(), String> {
    let window = app
        .get_webview_window("main")
        .ok_or("Failed to get main window")?;
    window
        .set_content_protected(enabled)
        .map_err(|e| format!("Failed to update content protection: {}", e))?;
    Ok(())
}

// =============================================================================
// MACOS SCREENSHOT PROTECTION
// =============================================================================

#[cfg(target_os = "macos")]
#[allow(deprecated, unexpected_cfgs)]
fn init_nspanel(app_handle: &AppHandle) {
    tauri_panel! {
        panel!(CueCardPanel {
            config: {
                can_become_key_window: true,
                is_floating_panel: true
            }
        })
    }

    let window: WebviewWindow = app_handle.get_webview_window("main").unwrap();

    let panel = window.to_panel::<CueCardPanel>().unwrap();

    // Set floating window level
    panel.set_level(PanelLevel::Floating.value());

    // Prevent panel from activating the app (required for fullscreen display)
    panel.set_style_mask(StyleMask::empty().nonactivating_panel().resizable().into());

    // Allow panel to display over fullscreen windows and join all spaces
    panel.set_collection_behavior(
        CollectionBehavior::new()
            .full_screen_auxiliary()
            .can_join_all_spaces()
            .into(),
    );

    // Prevent panel from hiding when app deactivates
    panel.set_hides_on_deactivate(false);
}

// =============================================================================
// APPLICATION ENTRY POINT
// =============================================================================

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    #[cfg_attr(not(target_os = "macos"), allow(unused_mut))]
    let mut builder = tauri::Builder::default()
        .plugin(tauri_plugin_opener::init())
        .plugin(tauri_plugin_store::Builder::default().build())
        .plugin(tauri_plugin_updater::Builder::default().build())
        .plugin(tauri_plugin_process::init())
        .plugin(tauri_plugin_dialog::init())
        .plugin(tauri_plugin_fs::init())
        .plugin(
            tauri_plugin_global_shortcut::Builder::new()
                .with_handler(|app, shortcut, event| {
                    if event.state() == tauri_plugin_global_shortcut::ShortcutState::Pressed {
                        let action = match shortcut.id() {
                            // General controls: Control+Option (Mac) / Control+Alt (Windows)
                            id if id == Shortcut::new(Some(Modifiers::ALT | Modifiers::CONTROL), Code::KeyC).id() => "toggle-visibility",
                            id if id == Shortcut::new(Some(Modifiers::ALT | Modifiers::CONTROL), Code::Minus).id() => "opacity-down",
                            id if id == Shortcut::new(Some(Modifiers::ALT | Modifiers::CONTROL), Code::Equal).id() => "opacity-up",
                            id if id == Shortcut::new(Some(Modifiers::ALT | Modifiers::CONTROL), Code::Space).id() => "timer-toggle",
                            id if id == Shortcut::new(Some(Modifiers::ALT | Modifiers::CONTROL), Code::Digit0).id() => "timer-reset",
                            // Movement: Control+Option+Arrow (Mac) / Control+Alt+Arrow (Windows)
                            id if id == Shortcut::new(Some(Modifiers::ALT | Modifiers::CONTROL), Code::ArrowLeft).id() => "move-left",
                            id if id == Shortcut::new(Some(Modifiers::ALT | Modifiers::CONTROL), Code::ArrowRight).id() => "move-right",
                            id if id == Shortcut::new(Some(Modifiers::ALT | Modifiers::CONTROL), Code::ArrowUp).id() => "move-up",
                            id if id == Shortcut::new(Some(Modifiers::ALT | Modifiers::CONTROL), Code::ArrowDown).id() => "move-down",
                            _ => return,
                        };
                        let _ = app.emit("shortcut-triggered", action);
                    }
                })
                .build(),
        );

    #[cfg(target_os = "macos")]
    {
        builder = builder.plugin(tauri_nspanel::init());
    }

    builder
        .setup(|app| {
            // Set activation policy to Accessory to prevent the app icon from showing on the dock (macOS only)
            #[cfg(target_os = "macos")]
            app.set_activation_policy(tauri::ActivationPolicy::Accessory);

            // Store app handle for emitting events
            {
                let mut handle = APP_HANDLE.write();
                *handle = Some(app.handle().clone());
            }

            // Load Firebase configuration
            match load_firebase_config(app.handle()) {
                Ok(config) => {
                    let mut firebase_config = FIREBASE_CONFIG.write();
                    *firebase_config = Some(config);
                }
                Err(e) => {
                    eprintln!("Warning: Failed to load Firebase config: {}", e);
                }
            }

            // Load stored tokens from persistent storage
            load_tokens_from_store(app.handle());

            // Platform-specific window initialization
            #[cfg(target_os = "macos")]
            init_nspanel(app.app_handle());

            // Register global shortcuts
            // All shortcuts use Control+Option (Mac) / Control+Alt (Windows)
            let shortcuts = [
                // General controls: Control+Option (Mac) / Control+Alt (Windows)
                Shortcut::new(Some(Modifiers::ALT | Modifiers::CONTROL), Code::KeyC),       // Toggle visibility
                Shortcut::new(Some(Modifiers::ALT | Modifiers::CONTROL), Code::Minus),      // Opacity down
                Shortcut::new(Some(Modifiers::ALT | Modifiers::CONTROL), Code::Equal),      // Opacity up
                Shortcut::new(Some(Modifiers::ALT | Modifiers::CONTROL), Code::Space),      // Timer toggle
                Shortcut::new(Some(Modifiers::ALT | Modifiers::CONTROL), Code::Digit0),     // Timer reset
                // Movement: Control+Option+Arrow (Mac) / Control+Alt+Arrow (Windows)
                Shortcut::new(Some(Modifiers::ALT | Modifiers::CONTROL), Code::ArrowLeft),  // Move left
                Shortcut::new(Some(Modifiers::ALT | Modifiers::CONTROL), Code::ArrowRight), // Move right
                Shortcut::new(Some(Modifiers::ALT | Modifiers::CONTROL), Code::ArrowUp),    // Move up
                Shortcut::new(Some(Modifiers::ALT | Modifiers::CONTROL), Code::ArrowDown),  // Move down
            ];

            if let Err(e) = app.global_shortcut().register_multiple(shortcuts) {
                eprintln!("Failed to register global shortcuts: {}", e);
            }

            // Start the web server in a background thread
            std::thread::spawn(|| {
                let rt = tokio::runtime::Runtime::new().unwrap();
                rt.block_on(start_server());
            });

            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            get_current_slide,
            get_current_notes,
            fetch_notifications,
            init_analytics,
            send_event,
            check_and_mark_first_open,
            has_slides_scope,
            connect_slides,
            refresh_notes,
            set_screenshot_protection
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
