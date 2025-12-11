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
use tauri::{AppHandle, Emitter};
use tauri_plugin_opener::OpenerExt;
use tower_http::cors::{Any, CorsLayer};

// OAuth2 Configuration - Set these via environment variables
const GOOGLE_AUTH_URL: &str = "https://accounts.google.com/o/oauth2/v2/auth";
const GOOGLE_TOKEN_URL: &str = "https://oauth2.googleapis.com/token";
const REDIRECT_URI: &str = "http://127.0.0.1:3000/oauth/callback";
const SCOPES: &str = "https://www.googleapis.com/auth/presentations.readonly";

// Global state
static CURRENT_SLIDE: Lazy<Arc<RwLock<Option<SlideData>>>> =
    Lazy::new(|| Arc::new(RwLock::new(None)));
static SLIDE_NOTES: Lazy<Arc<RwLock<HashMap<String, String>>>> =
    Lazy::new(|| Arc::new(RwLock::new(HashMap::new())));
static APP_HANDLE: Lazy<Arc<RwLock<Option<AppHandle>>>> =
    Lazy::new(|| Arc::new(RwLock::new(None)));
static OAUTH_TOKENS: Lazy<Arc<RwLock<Option<OAuthTokens>>>> =
    Lazy::new(|| Arc::new(RwLock::new(None)));

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct OAuthTokens {
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
struct GoogleTokenResponse {
    access_token: String,
    refresh_token: Option<String>,
    expires_in: Option<i64>,
}

// Health check endpoint
async fn health_handler() -> Json<serde_json::Value> {
    let is_authenticated = OAUTH_TOKENS.read().is_some();
    Json(serde_json::json!({
        "status": "ok",
        "server": "cuecard-app",
        "authenticated": is_authenticated
    }))
}

// Slides endpoint (POST) - receives slide data from extension
async fn slides_handler(Json(slide_data): Json<SlideData>) -> Result<Json<ApiResponse>, StatusCode> {
    println!("Received slide change: {:?}", slide_data);

    // Store the current slide
    {
        let mut current = CURRENT_SLIDE.write();
        *current = Some(slide_data.clone());
    }

    // Fetch notes from Google Slides API
    let notes = fetch_slide_notes(&slide_data.presentation_id, &slide_data.slide_id).await;

    // Cache the notes
    if let Some(ref note_text) = notes {
        let mut notes_cache = SLIDE_NOTES.write();
        let key = format!("{}:{}", slide_data.presentation_id, slide_data.slide_id);
        notes_cache.insert(key, note_text.clone());
    }

    // Emit event to frontend
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

// OAuth2 login - redirects to Google
async fn oauth_login_handler() -> Result<Redirect, StatusCode> {
    let client_id = std::env::var("GOOGLE_CLIENT_ID").map_err(|_| {
        eprintln!("GOOGLE_CLIENT_ID not set");
        StatusCode::INTERNAL_SERVER_ERROR
    })?;

    let auth_url = format!(
        "{}?client_id={}&redirect_uri={}&response_type=code&scope={}&access_type=offline&prompt=consent",
        GOOGLE_AUTH_URL,
        urlencoding::encode(&client_id),
        urlencoding::encode(REDIRECT_URI),
        urlencoding::encode(SCOPES)
    );

    Ok(Redirect::temporary(&auth_url))
}

// OAuth2 callback - exchanges code for tokens
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

    // Exchange code for tokens
    match exchange_code_for_tokens(&code).await {
        Ok(tokens) => {
            // Store tokens
            {
                let mut oauth = OAUTH_TOKENS.write();
                *oauth = Some(tokens);
            }

            // Notify frontend
            if let Some(app) = APP_HANDLE.read().as_ref() {
                let _ = app.emit("auth-status", serde_json::json!({"authenticated": true}));
            }

            Html(
                r#"<!DOCTYPE html>
                <html><head><title>Authentication Successful</title>
                <style>
                    body { font-family: system-ui; padding: 40px; text-align: center; background: #f0fdf4; }
                    .success { color: #166534; }
                </style>
                </head><body>
                <h1 class="success">Authentication Successful!</h1>
                <p>You can now close this window and return to CueCard.</p>
                <script>setTimeout(() => window.close(), 2000);</script>
                </body></html>"#
                    .to_string(),
            )
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

// Exchange authorization code for tokens
async fn exchange_code_for_tokens(code: &str) -> Result<OAuthTokens, String> {
    let client_id = std::env::var("GOOGLE_CLIENT_ID").map_err(|_| "GOOGLE_CLIENT_ID not set")?;
    let client_secret =
        std::env::var("GOOGLE_CLIENT_SECRET").map_err(|_| "GOOGLE_CLIENT_SECRET not set")?;

    let client = reqwest::Client::new();
    let response = client
        .post(GOOGLE_TOKEN_URL)
        .form(&[
            ("code", code),
            ("client_id", &client_id),
            ("client_secret", &client_secret),
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

    let expires_at = token_response
        .expires_in
        .map(|secs| chrono::Utc::now().timestamp() + secs);

    Ok(OAuthTokens {
        access_token: token_response.access_token,
        refresh_token: token_response.refresh_token,
        expires_at,
    })
}

// Refresh access token
async fn refresh_access_token() -> Result<(), String> {
    let refresh_token = {
        let tokens = OAUTH_TOKENS.read();
        tokens
            .as_ref()
            .and_then(|t| t.refresh_token.clone())
            .ok_or("No refresh token available")?
    };

    let client_id = std::env::var("GOOGLE_CLIENT_ID").map_err(|_| "GOOGLE_CLIENT_ID not set")?;
    let client_secret =
        std::env::var("GOOGLE_CLIENT_SECRET").map_err(|_| "GOOGLE_CLIENT_SECRET not set")?;

    let client = reqwest::Client::new();
    let response = client
        .post(GOOGLE_TOKEN_URL)
        .form(&[
            ("refresh_token", refresh_token.as_str()),
            ("client_id", &client_id),
            ("client_secret", &client_secret),
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

    // Update tokens (keep existing refresh token if new one not provided)
    {
        let mut tokens = OAUTH_TOKENS.write();
        if let Some(ref mut t) = *tokens {
            t.access_token = token_response.access_token;
            if token_response.refresh_token.is_some() {
                t.refresh_token = token_response.refresh_token;
            }
            t.expires_at = expires_at;
        }
    }

    Ok(())
}

// Get valid access token (refreshes if needed)
async fn get_valid_access_token() -> Option<String> {
    let (access_token, expires_at, has_refresh) = {
        let tokens = OAUTH_TOKENS.read();
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
        if let Err(e) = refresh_access_token().await {
            eprintln!("Failed to refresh token: {}", e);
            return None;
        }
        // Return the new token
        let tokens = OAUTH_TOKENS.read();
        return tokens.as_ref().map(|t| t.access_token.clone());
    }

    Some(access_token)
}

// Fetch notes from Google Slides API using OAuth2
async fn fetch_slide_notes(presentation_id: &str, slide_id: &str) -> Option<String> {
    let access_token = match get_valid_access_token().await {
        Some(token) => token,
        None => {
            println!("Not authenticated. Please sign in with Google.");
            return None;
        }
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
        let status = response.status();
        let error_body = response.text().await.unwrap_or_default();
        eprintln!("Slides API error: {} - Response body: {}", status, error_body);
        eprintln!("Presentation ID: {}, Slide ID: {}", presentation_id, slide_id);
        return None;
    }

    let json: serde_json::Value = match response.json().await {
        Ok(j) => j,
        Err(e) => {
            eprintln!("Failed to parse slides response: {}", e);
            return None;
        }
    };

    // Find the slide and extract speaker notes
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

// Extract text content from Google Slides text elements
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

// Auth status endpoint
async fn auth_status_handler() -> Json<serde_json::Value> {
    let is_authenticated = OAUTH_TOKENS.read().is_some();
    Json(serde_json::json!({
        "authenticated": is_authenticated
    }))
}

// Logout endpoint
async fn logout_handler() -> Json<serde_json::Value> {
    {
        let mut tokens = OAUTH_TOKENS.write();
        *tokens = None;
    }

    if let Some(app) = APP_HANDLE.read().as_ref() {
        let _ = app.emit("auth-status", serde_json::json!({"authenticated": false}));
    }

    Json(serde_json::json!({
        "success": true
    }))
}

// Start the web server
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

    let listener = tokio::net::TcpListener::bind("127.0.0.1:3000")
        .await
        .expect("Failed to bind to port 3000");

    println!("Server running on http://127.0.0.1:3000");

    axum::serve(listener, app).await.expect("Server error");
}

// Tauri command to get current slide data
#[tauri::command]
fn get_current_slide() -> Option<SlideData> {
    CURRENT_SLIDE.read().clone()
}

// Tauri command to get notes for current slide
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

// Tauri command to check auth status
#[tauri::command]
fn get_auth_status() -> bool {
    OAUTH_TOKENS.read().is_some()
}

// Tauri command to initiate login - opens browser directly
#[tauri::command]
async fn start_login(app: AppHandle) -> Result<(), String> {
    println!("Starting OAuth2 login flow...");

    let client_id = std::env::var("GOOGLE_CLIENT_ID").map_err(|_| "GOOGLE_CLIENT_ID not set")?;
    println!("Using Client ID: {}", client_id);

    let auth_url = format!(
        "{}?client_id={}&redirect_uri={}&response_type=code&scope={}&access_type=offline&prompt=consent",
        GOOGLE_AUTH_URL,
        urlencoding::encode(&client_id),
        urlencoding::encode(REDIRECT_URI),
        urlencoding::encode(SCOPES)
    );
    println!("Opening browser to URL: {}", auth_url);

    app.opener()
        .open_url(&auth_url, None::<&str>)
        .map_err(|e| format!("Failed to open browser: {}", e))?;

    Ok(())
}

// Tauri command to logout
#[tauri::command]
fn logout() {
    let mut tokens = OAUTH_TOKENS.write();
    *tokens = None;
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_opener::init())
        .setup(|app| {
            // Store app handle for emitting events
            {
                let mut handle = APP_HANDLE.write();
                *handle = Some(app.handle().clone());
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
            get_auth_status,
            start_login,
            logout
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
