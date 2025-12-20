//! CueCard - Speaker notes visible only to you
//!
//! This module contains the main backend logic for the CueCard application:
//! - Firebase Authentication with Google provider
//! - Google Slides API integration
//! - Local web server for browser extension communication
//! - Tauri commands for frontend interaction
//! - macOS window management (opacity, screenshot protection)

use axum::{
    extract::Query,
    http::StatusCode,
    response::{Html, Json, Redirect},
    routing::{get, post},
    Router,
};
use once_cell::sync::Lazy;
use parking_lot::RwLock;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::Arc;
use tauri::{AppHandle, Emitter, Manager};
#[cfg(target_os = "macos")]
use tauri::WebviewWindow;
#[cfg(target_os = "macos")]
use tauri_nspanel::{tauri_panel, CollectionBehavior, PanelLevel, StyleMask, WebviewWindowExt};
use tauri_plugin_opener::OpenerExt;
use tauri_plugin_store::StoreExt;
use tower_http::cors::{Any, CorsLayer};

// =============================================================================
// CONSTANTS
// =============================================================================

// OAuth2 Configuration
const GOOGLE_AUTH_URL: &str = "https://accounts.google.com/o/oauth2/v2/auth";
const GOOGLE_TOKEN_URL: &str = "https://oauth2.googleapis.com/token";
const REDIRECT_URI: &str = "http://127.0.0.1:3642/oauth/callback";

// Firebase REST API endpoints
const FIREBASE_SIGNUP_URL: &str = "https://identitytoolkit.googleapis.com/v1/accounts:signUp";
const FIREBASE_SIGNIN_IDP_URL: &str =
    "https://identitytoolkit.googleapis.com/v1/accounts:signInWithIdp";
const FIREBASE_TOKEN_URL: &str = "https://securetoken.googleapis.com/v1/token";

// Scopes
const SCOPE_PROFILE: &str = "openid profile email";
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

/// Wrapper for firebase-config.json structure
#[derive(Debug, Clone, Serialize, Deserialize)]
struct FirebaseConfigFile {
    firebase: FirebaseConfigFileInner,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct FirebaseConfigFileInner {
    api_key: String,
    auth_domain: String,
    project_id: String,
    storage_bucket: Option<String>,
    messaging_sender_id: Option<String>,
    app_id: Option<String>,
}

/// Firebase authentication tokens
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FirebaseTokens {
    pub id_token: String,
    pub refresh_token: String,
    pub expires_at: i64,
    pub email: Option<String>,
    pub local_id: String,
    pub display_name: Option<String>,
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

#[derive(Debug, Deserialize)]
struct FirebaseSignInIdpResponse {
    #[serde(rename = "idToken")]
    id_token: String,
    #[serde(rename = "refreshToken")]
    refresh_token: String,
    #[serde(rename = "expiresIn")]
    expires_in: String,
    #[serde(rename = "localId")]
    local_id: String,
    email: Option<String>,
    #[serde(rename = "displayName")]
    display_name: Option<String>,
}

#[derive(Debug, Deserialize)]
struct FirebaseRefreshResponse {
    id_token: String,
    refresh_token: String,
    expires_in: String,
}

// =============================================================================
// GLOBAL STATE
// =============================================================================

static CURRENT_SLIDE: Lazy<Arc<RwLock<Option<SlideData>>>> =
    Lazy::new(|| Arc::new(RwLock::new(None)));
static SLIDE_NOTES: Lazy<Arc<RwLock<HashMap<String, String>>>> =
    Lazy::new(|| Arc::new(RwLock::new(HashMap::new())));
static CURRENT_PRESENTATION_ID: Lazy<Arc<RwLock<Option<String>>>> =
    Lazy::new(|| Arc::new(RwLock::new(None)));
static APP_HANDLE: Lazy<Arc<RwLock<Option<AppHandle>>>> = Lazy::new(|| Arc::new(RwLock::new(None)));

// Firebase and OAuth state
static FIREBASE_CONFIG: Lazy<Arc<RwLock<Option<FirebaseConfig>>>> =
    Lazy::new(|| Arc::new(RwLock::new(None)));
static FIREBASE_TOKENS: Lazy<Arc<RwLock<Option<FirebaseTokens>>>> =
    Lazy::new(|| Arc::new(RwLock::new(None)));
static OAUTH_CREDENTIALS: Lazy<Arc<RwLock<Option<OAuthCredentials>>>> =
    Lazy::new(|| Arc::new(RwLock::new(None)));
static SLIDES_TOKENS: Lazy<Arc<RwLock<Option<SlidesTokens>>>> =
    Lazy::new(|| Arc::new(RwLock::new(None)));
static PENDING_OAUTH_SCOPE: Lazy<Arc<RwLock<Option<String>>>> =
    Lazy::new(|| Arc::new(RwLock::new(None)));

// =============================================================================
// FIREBASE CONFIGURATION
// =============================================================================

/// Load Firebase configuration from firebase-config.json
fn load_firebase_config(app: &AppHandle) -> Result<FirebaseConfig, String> {
    // Try to find firebase-config.json in the resource directory (bundled app)
    // or relative paths (development mode)
    let resource_dir = app.path().resource_dir().ok();

    let possible_paths = vec![
        resource_dir.as_ref().map(|p| p.join("firebase-config.json")),
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

            return Ok(config);
        }
    }

    Err("firebase-config.json not found".to_string())
}

// =============================================================================
// FIREBASE AUTHENTICATION
// =============================================================================

/// Sign in anonymously to Firebase (for bootstrap)
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

/// Exchange Google ID token for Firebase ID token
async fn exchange_google_token_for_firebase(
    google_id_token: &str,
) -> Result<FirebaseTokens, String> {
    let config = FIREBASE_CONFIG
        .read()
        .clone()
        .ok_or("Firebase config not loaded")?;

    let url = format!("{}?key={}", FIREBASE_SIGNIN_IDP_URL, config.api_key);

    let post_body = format!("id_token={}&providerId=google.com", google_id_token);

    let client = reqwest::Client::new();
    let response = client
        .post(&url)
        .json(&serde_json::json!({
            "postBody": post_body,
            "requestUri": "http://localhost",
            "returnSecureToken": true,
            "returnIdpCredential": true
        }))
        .send()
        .await
        .map_err(|e| format!("Firebase signInWithIdp request failed: {}", e))?;

    if !response.status().is_success() {
        let error_text = response.text().await.unwrap_or_default();
        return Err(format!("Firebase signInWithIdp failed: {}", error_text));
    }

    let idp_response: FirebaseSignInIdpResponse = response
        .json()
        .await
        .map_err(|e| format!("Failed to parse signInWithIdp response: {}", e))?;

    let expires_in: i64 = idp_response.expires_in.parse().unwrap_or(3600);
    let expires_at = chrono::Utc::now().timestamp() + expires_in;

    Ok(FirebaseTokens {
        id_token: idp_response.id_token,
        refresh_token: idp_response.refresh_token,
        expires_at,
        email: idp_response.email,
        local_id: idp_response.local_id,
        display_name: idp_response.display_name,
    })
}

/// Refresh Firebase ID token
async fn refresh_firebase_token() -> Result<(), String> {
    let config = FIREBASE_CONFIG
        .read()
        .clone()
        .ok_or("Firebase config not loaded")?;

    let refresh_token = {
        let tokens = FIREBASE_TOKENS.read();
        tokens
            .as_ref()
            .map(|t| t.refresh_token.clone())
            .ok_or("No Firebase refresh token available")?
    };

    let url = format!("{}?key={}", FIREBASE_TOKEN_URL, config.api_key);

    let client = reqwest::Client::new();
    let response = client
        .post(&url)
        .header("Content-Type", "application/x-www-form-urlencoded")
        .body(format!(
            "grant_type=refresh_token&refresh_token={}",
            refresh_token
        ))
        .send()
        .await
        .map_err(|e| format!("Firebase token refresh failed: {}", e))?;

    if !response.status().is_success() {
        let error_text = response.text().await.unwrap_or_default();
        return Err(format!("Firebase token refresh failed: {}", error_text));
    }

    let refresh_response: FirebaseRefreshResponse = response
        .json()
        .await
        .map_err(|e| format!("Failed to parse refresh response: {}", e))?;

    let expires_in: i64 = refresh_response.expires_in.parse().unwrap_or(3600);
    let expires_at = chrono::Utc::now().timestamp() + expires_in;

    // Update tokens
    {
        let mut tokens = FIREBASE_TOKENS.write();
        if let Some(ref mut t) = *tokens {
            t.id_token = refresh_response.id_token;
            t.refresh_token = refresh_response.refresh_token;
            t.expires_at = expires_at;
        }
    }

    // Save to persistent storage
    if let Some(app) = APP_HANDLE.read().as_ref() {
        save_firebase_tokens_to_store(app);
    }

    Ok(())
}

/// Get valid Firebase ID token (refreshes if needed)
async fn get_valid_firebase_token() -> Option<String> {
    let (id_token, expires_at) = {
        let tokens = FIREBASE_TOKENS.read();
        match tokens.as_ref() {
            Some(t) => (t.id_token.clone(), t.expires_at),
            None => return None,
        }
    };

    // Check if token is expired or about to expire (within 5 minutes)
    let now = chrono::Utc::now().timestamp();
    let is_expired = now >= expires_at - 300;

    if is_expired {
        if let Err(e) = refresh_firebase_token().await {
            eprintln!("Failed to refresh Firebase token: {}", e);
            return None;
        }
        // Return the new token
        let tokens = FIREBASE_TOKENS.read();
        return tokens.as_ref().map(|t| t.id_token.clone());
    }

    Some(id_token)
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

fn save_firebase_tokens_to_store(app: &AppHandle) {
    if let Ok(store) = app.store("cuecard-store.json") {
        let tokens = FIREBASE_TOKENS.read();
        if let Some(ref t) = *tokens {
            if let Ok(json) = serde_json::to_value(t) {
                store.set("firebase_tokens", json);
                let _ = store.save();
            }
        }
    }
}

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

fn clear_all_tokens_from_store(app: &AppHandle) {
    if let Ok(store) = app.store("cuecard-store.json") {
        let _ = store.delete("firebase_tokens");
        let _ = store.delete("slides_tokens");
        let _ = store.delete("oauth_credentials");
        let _ = store.save();
    }
}

fn load_tokens_from_store(app: &AppHandle) {
    if let Ok(store) = app.store("cuecard-store.json") {
        // Load Firebase tokens
        if let Some(tokens_json) = store.get("firebase_tokens") {
            if let Ok(tokens) = serde_json::from_value::<FirebaseTokens>(tokens_json.clone()) {
                let mut firebase = FIREBASE_TOKENS.write();
                *firebase = Some(tokens);
            }
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
// WEB SERVER HANDLERS
// =============================================================================

async fn health_handler() -> Json<serde_json::Value> {
    let is_authenticated = FIREBASE_TOKENS.read().is_some();
    Json(serde_json::json!({
        "status": "ok",
        "server": "cuecard-app",
        "authenticated": is_authenticated
    }))
}

async fn slides_handler(
    Json(slide_data): Json<SlideData>,
) -> Result<Json<ApiResponse>, StatusCode> {
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
        }
        let presentation_id = slide_data.presentation_id.clone();
        tokio::spawn(async move {
            let _ = prefetch_all_notes(&presentation_id).await;
        });
    }

    {
        let mut current = CURRENT_SLIDE.write();
        *current = Some(slide_data.clone());
    }

    let notes = {
        let notes_cache = SLIDE_NOTES.read();
        let key = format!("{}:{}", slide_data.presentation_id, slide_data.slide_id);
        notes_cache.get(&key).cloned()
    };

    let notes = match notes {
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
    };

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

// OAuth login handler - redirects to Google
async fn oauth_login_handler() -> Result<Redirect, StatusCode> {
    let credentials = match OAUTH_CREDENTIALS.read().clone() {
        Some(c) => c,
        None => return Err(StatusCode::INTERNAL_SERVER_ERROR),
    };

    let scope_url = {
        let pending = PENDING_OAUTH_SCOPE.read();
        match pending.as_deref() {
            Some("profile") => SCOPE_PROFILE.to_string(),
            Some("slides") => SCOPE_SLIDES.to_string(),
            _ => format!("{} {}", SCOPE_PROFILE, SCOPE_SLIDES),
        }
    };

    let auth_url = format!(
        "{}?client_id={}&redirect_uri={}&response_type=code&scope={}&access_type=offline&prompt=consent&include_granted_scopes=true",
        GOOGLE_AUTH_URL,
        urlencoding::encode(&credentials.client_id),
        urlencoding::encode(REDIRECT_URI),
        urlencoding::encode(&scope_url)
    );

    Ok(Redirect::temporary(&auth_url))
}

// OAuth callback handler
async fn oauth_callback_handler(Query(params): Query<OAuthCallback>) -> Html<String> {
    if let Some(error) = params.error {
        return Html(format!(
            r#"<!DOCTYPE html>
            <html><head><title>Authentication Failed</title>
            <style>body {{ font-family: system-ui; padding: 40px; text-align: center; }}</style>
            </head><body>
            <h1>Authentication Failed</h1>
            <p>Error: {}</p>
            <p>You can close this window.</p>
            </body></html>"#,
            error
        ));
    }

    let code = match params.code {
        Some(c) => c,
        None => {
            return Html(
                r#"<!DOCTYPE html>
                <html><head><title>Authentication Failed</title>
                <style>body { font-family: system-ui; padding: 40px; text-align: center; }</style>
                </head><body>
                <h1>Authentication Failed</h1>
                <p>No authorization code received.</p>
                <p>You can close this window.</p>
                </body></html>"#
                    .to_string(),
            )
        }
    };

    // Get pending scope
    let pending_scope = {
        let mut pending = PENDING_OAUTH_SCOPE.write();
        pending.take()
    };

    // Exchange code for Google tokens
    match exchange_code_for_google_tokens(&code).await {
        Ok(google_tokens) => {
            let is_profile_scope = pending_scope.as_deref() == Some("profile");

            if is_profile_scope {
                // For profile scope, exchange Google ID token for Firebase token
                if let Some(google_id_token) = &google_tokens.id_token {
                    match exchange_google_token_for_firebase(google_id_token).await {
                        Ok(firebase_tokens) => {
                            let user_name = firebase_tokens.display_name.clone();
                            let user_email = firebase_tokens.email.clone();

                            // Store Firebase tokens
                            {
                                let mut tokens = FIREBASE_TOKENS.write();
                                *tokens = Some(firebase_tokens);
                            }

                            // Save to persistent storage
                            if let Some(app) = APP_HANDLE.read().as_ref() {
                                save_firebase_tokens_to_store(app);
                                save_oauth_credentials_to_store(app);
                            }

                            // Notify frontend
                            if let Some(app) = APP_HANDLE.read().as_ref() {
                                let _ = app.emit(
                                    "auth-status",
                                    serde_json::json!({
                                        "authenticated": true,
                                        "user_name": user_name,
                                        "user_email": user_email,
                                        "requested_scope": pending_scope
                                    }),
                                );
                            }

                            Html(
                                r#"<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>CueCard Authentication</title><style>:root{--bg0:#0b0b0c;--bg1:#121214;--text-strong:rgba(255,255,255,.7);--text-soft:rgba(255,255,255,.55)}html,body{height:100%;margin:0;font-family:ui-sans-serif,system-ui,-apple-system,Segoe UI,Roboto,Helvetica,Arial,"Apple Color Emoji","Segoe UI Emoji"}body{background:radial-gradient(1200px 600px at 50% 45%,#1a1a1f 0%,#0f0f12 55%,#0a0a0b 100%),linear-gradient(180deg,var(--bg1),var(--bg0));display:grid;place-items:center;color:#fff}.wrap{text-align:center;padding:48px 24px;max-width:900px}h1{margin:0 0 26px;font-weight:600;letter-spacing:-.02em;color:var(--text-strong);font-size:clamp(44px,6vw,78px);line-height:1.08}p{margin:0;font-size:clamp(16px,2vw,26px);line-height:1.5;color:var(--text-soft)}</style></head><body><main class="wrap" role="main">
                                <h1>Speak Confidently</h1><p>You're all set up for CueCard. You can now close this window.</p></main></body></html>"#
                                    .to_string(),
                            )
                        }
                        Err(e) => Html(format!(
                            r#"<!DOCTYPE html>
                            <html><head><title>Authentication Failed</title>
                            <style>body {{ font-family: system-ui; padding: 40px; text-align: center; }}</style>
                            </head><body>
                            <h1>Firebase Authentication Failed</h1>
                            <p>Error: {}</p>
                            <p>You can close this window.</p>
                            </body></html>"#,
                            e
                        )),
                    }
                } else {
                    Html(
                        r#"<!DOCTYPE html>
                        <html><head><title>Authentication Failed</title>
                        <style>body { font-family: system-ui; padding: 40px; text-align: center; }</style>
                        </head><body>
                        <h1>Authentication Failed</h1>
                        <p>No ID token received from Google.</p>
                        <p>You can close this window.</p>
                        </body></html>"#
                            .to_string(),
                    )
                }
            } else {
                // For slides scope, store the access token for Slides API
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

                // Save to persistent storage
                if let Some(app) = APP_HANDLE.read().as_ref() {
                    save_slides_tokens_to_store(app);
                }

                // Notify frontend
                if let Some(app) = APP_HANDLE.read().as_ref() {
                    let _ = app.emit(
                        "auth-status",
                        serde_json::json!({
                            "authenticated": true,
                            "slides_authorized": true,
                            "requested_scope": pending_scope
                        }),
                    );
                }

                Html(
                    r#"<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>CueCard Authentication</title><style>:root{--bg0:#0b0b0c;--bg1:#121214;--text-strong:rgba(255,255,255,.7);--text-soft:rgba(255,255,255,.55)}html,body{height:100%;margin:0;font-family:ui-sans-serif,system-ui,-apple-system,Segoe UI,Roboto,Helvetica,Arial,"Apple Color Emoji","Segoe UI Emoji"}body{background:radial-gradient(1200px 600px at 50% 45%,#1a1a1f 0%,#0f0f12 55%,#0a0a0b 100%),linear-gradient(180deg,var(--bg1),var(--bg0));display:grid;place-items:center;color:#fff}.wrap{text-align:center;padding:48px 24px;max-width:900px}h1{margin:0 0 26px;font-weight:600;letter-spacing:-.02em;color:var(--text-strong);font-size:clamp(44px,6vw,78px);line-height:1.08}p{margin:0;font-size:clamp(16px,2vw,26px);line-height:1.5;color:var(--text-soft)}</style></head><body><main class="wrap" role="main">
                    <h1>Speak Confidently</h1><p>You're all set up for Slides Access. You can now close this window.</p></main></body></html>"#
                        .to_string(),
                )
            }
        }
        Err(e) => Html(format!(
            r#"<!DOCTYPE html>
            <html><head><title>Authentication Failed</title>
            <style>body {{ font-family: system-ui; padding: 40px; text-align: center; }}</style>
            </head><body>
            <h1>Authentication Failed</h1>
            <p>Error: {}</p>
            <p>You can close this window.</p>
            </body></html>"#,
            e
        )),
    }
}

async fn auth_status_handler() -> Json<serde_json::Value> {
    let is_authenticated = FIREBASE_TOKENS.read().is_some();
    Json(serde_json::json!({
        "authenticated": is_authenticated
    }))
}

async fn logout_handler() -> Json<serde_json::Value> {
    {
        let mut tokens = FIREBASE_TOKENS.write();
        *tokens = None;
    }
    {
        let mut tokens = SLIDES_TOKENS.write();
        *tokens = None;
    }

    if let Some(app) = APP_HANDLE.read().as_ref() {
        clear_all_tokens_from_store(app);

        let _ = app.emit(
            "auth-status",
            serde_json::json!({
                "authenticated": false,
                "user_name": null
            }),
        );
    }

    Json(serde_json::json!({
        "success": true
    }))
}

async fn start_server() {
    let cors = CorsLayer::new()
        .allow_origin(Any)
        .allow_methods(Any)
        .allow_headers(Any);

    let app = Router::new()
        .route("/health", get(health_handler))
        .route("/slides", post(slides_handler))
        .route("/oauth/login", get(oauth_login_handler))
        .route("/oauth/callback", get(oauth_callback_handler))
        .route("/oauth/status", get(auth_status_handler))
        .route("/oauth/logout", post(logout_handler))
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

    for slide in slides {
        if let Some(obj_id) = slide.get("objectId").and_then(|o| o.as_str()) {
            if let Some(notes_text) = extract_notes_from_slide(slide) {
                let key = format!("{}:{}", presentation_id, obj_id);
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

    let slides = json.get("slides")?.as_array()?;
    for slide in slides {
        let obj_id = slide.get("objectId")?.as_str()?;
        if obj_id == slide_id {
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
        }
    }

    None
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

    if result.is_empty() {
        None
    } else {
        Some(result.trim().to_string())
    }
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
fn get_auth_status() -> bool {
    FIREBASE_TOKENS.read().is_some()
}

#[tauri::command]
fn get_firestore_project_id() -> String {
    FIREBASE_CONFIG
        .read()
        .as_ref()
        .map(|c| c.project_id.clone())
        .unwrap_or_default()
}

#[tauri::command]
async fn get_firebase_id_token() -> Result<String, String> {
    get_valid_firebase_token()
        .await
        .ok_or_else(|| "Not authenticated".to_string())
}

#[tauri::command]
fn has_slides_scope() -> bool {
    SLIDES_TOKENS.read().is_some()
}

#[tauri::command]
async fn get_user_info() -> Result<serde_json::Value, String> {
    let tokens = FIREBASE_TOKENS.read();
    match tokens.as_ref() {
        Some(t) => Ok(serde_json::json!({
            "email": t.email,
            "name": t.display_name,
            "local_id": t.local_id
        })),
        None => Err("Not authenticated".to_string()),
    }
}

#[tauri::command]
async fn start_login(app: AppHandle, scope: String) -> Result<(), String> {
    // Set pending scope
    {
        let mut pending = PENDING_OAUTH_SCOPE.write();
        *pending = Some(scope.clone());
    }

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

    let scope_url = match scope.as_str() {
        "profile" => SCOPE_PROFILE.to_string(),
        "slides" => SCOPE_SLIDES.to_string(),
        _ => format!("{} {}", SCOPE_PROFILE, SCOPE_SLIDES),
    };

    let auth_url = format!(
        "{}?client_id={}&redirect_uri={}&response_type=code&scope={}&access_type=offline&prompt=consent&include_granted_scopes=true",
        GOOGLE_AUTH_URL,
        urlencoding::encode(&credentials.client_id),
        urlencoding::encode(REDIRECT_URI),
        urlencoding::encode(&scope_url)
    );

    app.opener()
        .open_url(&auth_url, None::<&str>)
        .map_err(|e| format!("Failed to open browser: {}", e))?;

    Ok(())
}

#[tauri::command]
fn logout(app: AppHandle) {
    {
        let mut tokens = FIREBASE_TOKENS.write();
        *tokens = None;
    }
    {
        let mut tokens = SLIDES_TOKENS.write();
        *tokens = None;
    }

    clear_all_tokens_from_store(&app);
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

    // Enable shadow on macOS
    let _ = window.set_shadow(true);

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
// WINDOWS WINDOW MANAGEMENT
// =============================================================================

#[cfg(target_os = "windows")]
fn init_windows_window(app_handle: &AppHandle) {
    use windows::Win32::Foundation::HWND;
    use windows::Win32::UI::WindowsAndMessaging::{
        GetWindowLongW, SetWindowLongW, SetWindowPos, GWL_EXSTYLE, HWND_TOPMOST, SWP_NOACTIVATE,
        SWP_NOMOVE, SWP_NOSIZE, WS_EX_APPWINDOW, WS_EX_NOACTIVATE, WS_EX_TOOLWINDOW,
    };

    let window = app_handle.get_webview_window("main").unwrap();

    // Get the native window handle
    if let Ok(hwnd) = window.hwnd() {
        let hwnd = HWND(hwnd.0 as *mut std::ffi::c_void);

        unsafe {
            // Get current extended style
            let ex_style = GetWindowLongW(hwnd, GWL_EXSTYLE);

            // Set WS_EX_TOOLWINDOW to hide from taskbar and alt-tab
            // Remove WS_EX_APPWINDOW to ensure it doesn't show in taskbar
            // Add WS_EX_NOACTIVATE to prevent stealing focus
            let new_ex_style = (ex_style | WS_EX_TOOLWINDOW.0 as i32 | WS_EX_NOACTIVATE.0 as i32)
                & !(WS_EX_APPWINDOW.0 as i32);
            SetWindowLongW(hwnd, GWL_EXSTYLE, new_ex_style);

            // Ensure window stays on top (HWND_TOPMOST)
            let _ = SetWindowPos(
                hwnd,
                HWND_TOPMOST,
                0,
                0,
                0,
                0,
                SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE,
            );
        }
    }
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
        .plugin(tauri_plugin_process::init());

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

            #[cfg(target_os = "windows")]
            init_windows_window(app.app_handle());

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
            get_auth_status,
            get_firestore_project_id,
            get_firebase_id_token,
            has_slides_scope,
            get_user_info,
            start_login,
            logout,
            refresh_notes,
            set_screenshot_protection
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
