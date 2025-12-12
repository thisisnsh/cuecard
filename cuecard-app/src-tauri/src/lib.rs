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
use tauri_plugin_opener::OpenerExt;
use tower_http::cors::{Any, CorsLayer};

#[cfg(target_os = "macos")]
#[macro_use]
extern crate objc;

// OAuth2 Configuration - Set these via environment variables
const GOOGLE_AUTH_URL: &str = "https://accounts.google.com/o/oauth2/v2/auth";
const GOOGLE_TOKEN_URL: &str = "https://oauth2.googleapis.com/token";
const REDIRECT_URI: &str = "http://127.0.0.1:3000/oauth/callback";
const SCOPES: &str = "https://www.googleapis.com/auth/presentations.readonly https://www.googleapis.com/auth/userinfo.profile";

// Global state
static CURRENT_SLIDE: Lazy<Arc<RwLock<Option<SlideData>>>> =
    Lazy::new(|| Arc::new(RwLock::new(None)));
static SLIDE_NOTES: Lazy<Arc<RwLock<HashMap<String, String>>>> =
    Lazy::new(|| Arc::new(RwLock::new(HashMap::new())));
static CURRENT_PRESENTATION_ID: Lazy<Arc<RwLock<Option<String>>>> =
    Lazy::new(|| Arc::new(RwLock::new(None)));
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

    // Check if presentation changed - if so, prefetch all notes
    let presentation_changed = {
        let current_pres = CURRENT_PRESENTATION_ID.read();
        current_pres.as_ref() != Some(&slide_data.presentation_id)
    };

    if presentation_changed {
        println!("New presentation detected: {}", slide_data.presentation_id);
        // Update current presentation ID
        {
            let mut current_pres = CURRENT_PRESENTATION_ID.write();
            *current_pres = Some(slide_data.presentation_id.clone());
        }
        // Clear old notes cache and prefetch all notes for new presentation
        {
            let mut notes_cache = SLIDE_NOTES.write();
            notes_cache.clear();
        }
        // Prefetch all notes in the background
        let presentation_id = slide_data.presentation_id.clone();
        tokio::spawn(async move {
            let _ = prefetch_all_notes(&presentation_id).await;
        });
    }

    // Store the current slide
    {
        let mut current = CURRENT_SLIDE.write();
        *current = Some(slide_data.clone());
    }

    // Try to get notes from cache first, otherwise fetch
    let notes = {
        let notes_cache = SLIDE_NOTES.read();
        let key = format!("{}:{}", slide_data.presentation_id, slide_data.slide_id);
        notes_cache.get(&key).cloned()
    };

    let notes = match notes {
        Some(n) => Some(n),
        None => {
            // Not in cache, fetch and cache it
            let fetched = fetch_slide_notes(&slide_data.presentation_id, &slide_data.slide_id).await;
            if let Some(ref note_text) = fetched {
                let mut notes_cache = SLIDE_NOTES.write();
                let key = format!("{}:{}", slide_data.presentation_id, slide_data.slide_id);
                notes_cache.insert(key, note_text.clone());
            }
            fetched
        }
    };

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

            // Fetch user info to get the name
            let user_name = if let Some(access_token) = get_valid_access_token().await {
                let client = reqwest::Client::new();
                if let Ok(response) = client
                    .get("https://www.googleapis.com/oauth2/v2/userinfo")
                    .header("Authorization", format!("Bearer {}", access_token))
                    .send()
                    .await
                {
                    if let Ok(user_info) = response.json::<serde_json::Value>().await {
                        user_info.get("name").and_then(|n| n.as_str()).map(|s| s.to_string())
                    } else {
                        None
                    }
                } else {
                    None
                }
            } else {
                None
            };

            // Notify frontend
            if let Some(app) = APP_HANDLE.read().as_ref() {
                let _ = app.emit("auth-status", serde_json::json!({
                    "authenticated": true,
                    "user_name": user_name
                }));
            }

            Html(
                r#"<!DOCTYPE html>
                <html><head><title>Authentication Successful</title>
                <style>
                    body { font-family: system-ui; padding: 40px; text-align: center; background: #fff; }
                    .success { color: #000; }
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

// Prefetch all notes for a presentation
async fn prefetch_all_notes(presentation_id: &str) -> Result<(), String> {
    let access_token = match get_valid_access_token().await {
        Some(token) => token,
        None => {
            println!("Not authenticated. Cannot prefetch notes.");
            return Err("Not authenticated".to_string());
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
            eprintln!("Error fetching slides API for prefetch: {}", e);
            return Err(e.to_string());
        }
    };

    if !response.status().is_success() {
        let status = response.status();
        let error_body = response.text().await.unwrap_or_default();
        eprintln!("Slides API error during prefetch: {} - {}", status, error_body);
        return Err(format!("API error: {}", status));
    }

    let json: serde_json::Value = match response.json().await {
        Ok(j) => j,
        Err(e) => {
            eprintln!("Failed to parse slides response during prefetch: {}", e);
            return Err(e.to_string());
        }
    };

    // Extract notes for all slides
    let slides = match json.get("slides").and_then(|s| s.as_array()) {
        Some(s) => s,
        None => return Ok(()),
    };

    let mut notes_cache = SLIDE_NOTES.write();
    let mut count = 0;

    for slide in slides {
        if let Some(obj_id) = slide.get("objectId").and_then(|o| o.as_str()) {
            if let Some(notes_text) = extract_notes_from_slide(slide) {
                let key = format!("{}:{}", presentation_id, obj_id);
                notes_cache.insert(key, notes_text);
                count += 1;
            }
        }
    }

    println!("Prefetched {} slide notes for presentation {}", count, presentation_id);
    Ok(())
}

// Extract notes from a single slide JSON object
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
        let _ = app.emit("auth-status", serde_json::json!({
            "authenticated": false,
            "user_name": null
        }));
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

// Tauri command to get user info from Google
#[tauri::command]
async fn get_user_info() -> Result<serde_json::Value, String> {
    let access_token = match get_valid_access_token().await {
        Some(token) => token,
        None => return Err("Not authenticated".to_string()),
    };

    let client = reqwest::Client::new();
    let response = client
        .get("https://www.googleapis.com/oauth2/v2/userinfo")
        .header("Authorization", format!("Bearer {}", access_token))
        .send()
        .await
        .map_err(|e| format!("Failed to fetch user info: {}", e))?;

    if !response.status().is_success() {
        return Err(format!("Failed to fetch user info: {}", response.status()));
    }

    let user_info: serde_json::Value = response
        .json()
        .await
        .map_err(|e| format!("Failed to parse user info: {}", e))?;

    Ok(user_info)
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

// Tauri command to refresh notes for current slide/presentation
#[tauri::command]
async fn refresh_notes(app: AppHandle) -> Result<Option<String>, String> {
    let current_slide = {
        CURRENT_SLIDE.read().clone()
    };

    let slide_data = match current_slide {
        Some(s) => s,
        None => return Err("No current slide".to_string()),
    };

    // Clear cache for this presentation and refetch all notes
    {
        let mut notes_cache = SLIDE_NOTES.write();
        // Remove all notes for this presentation
        notes_cache.retain(|k, _| !k.starts_with(&format!("{}:", slide_data.presentation_id)));
    }

    // Refetch all notes
    let _ = prefetch_all_notes(&slide_data.presentation_id).await;

    // Get notes for current slide
    let notes = {
        let notes_cache = SLIDE_NOTES.read();
        let key = format!("{}:{}", slide_data.presentation_id, slide_data.slide_id);
        notes_cache.get(&key).cloned()
    };

    // Emit event to frontend with refreshed notes
    let event = SlideUpdateEvent {
        slide_data: slide_data.clone(),
        notes: notes.clone(),
    };
    let _ = app.emit("slide-update", event);

    Ok(notes)
}

// Tauri command to set window opacity/transparency
#[tauri::command]
fn set_window_opacity(app: AppHandle, opacity: f64) -> Result<(), String> {
    let window = app.get_webview_window("main").ok_or("Failed to get main window")?;

    // Clamp opacity between 0.1 and 1.0
    let clamped_opacity = opacity.max(0.1).min(1.0);

    #[cfg(target_os = "macos")]
    {
        use cocoa::appkit::NSWindow;
        use cocoa::base::id;

        let ns_window = window.ns_window().map_err(|e| format!("Failed to get NSWindow: {}", e))? as id;
        unsafe {
            ns_window.setAlphaValue_(clamped_opacity);
        }
    }

    #[cfg(target_os = "windows")]
    {
        use windows::Win32::Foundation::HWND;
        use windows::Win32::Graphics::Gdi::UpdateWindow;
        use windows::Win32::UI::WindowsAndMessaging::{
            GetWindowLongW, SetLayeredWindowAttributes, SetWindowLongW, GWL_EXSTYLE, LWA_ALPHA,
            WS_EX_LAYERED,
        };

        let hwnd = HWND(window.hwnd().map_err(|e| format!("Failed to get HWND: {}", e))?.0 as _);

        unsafe {
            // Get current extended style
            let ex_style = GetWindowLongW(hwnd, GWL_EXSTYLE);

            // Add WS_EX_LAYERED style if not present
            SetWindowLongW(hwnd, GWL_EXSTYLE, ex_style | WS_EX_LAYERED.0 as i32);

            // Set the opacity (0-255)
            let alpha = (clamped_opacity * 255.0) as u8;
            SetLayeredWindowAttributes(hwnd, None, alpha, LWA_ALPHA)
                .map_err(|e| format!("Failed to set window opacity: {}", e))?;

            let _ = UpdateWindow(hwnd);
        }
    }

    #[cfg(target_os = "linux")]
    {
        // On Linux, transparency is handled by the compositor
        // We can try to set the opacity hint, but it depends on the window manager
        // For now, we'll just acknowledge the request
        let _ = clamped_opacity;
        println!("Note: Dynamic opacity control on Linux depends on your window manager/compositor");
    }

    Ok(())
}

// Tauri command to get current window opacity
#[tauri::command]
fn get_window_opacity(app: AppHandle) -> Result<f64, String> {
    let window = app.get_webview_window("main").ok_or("Failed to get main window")?;

    #[cfg(target_os = "macos")]
    {
        use cocoa::appkit::NSWindow;
        use cocoa::base::id;

        let ns_window = window.ns_window().map_err(|e| format!("Failed to get NSWindow: {}", e))? as id;
        let opacity = unsafe { ns_window.alphaValue() };
        Ok(opacity)
    }

    #[cfg(target_os = "windows")]
    {
        use windows::Win32::Foundation::HWND;
        use windows::Win32::UI::WindowsAndMessaging::{GetLayeredWindowAttributes, GWL_EXSTYLE, GetWindowLongW, WS_EX_LAYERED};

        let hwnd = HWND(window.hwnd().map_err(|e| format!("Failed to get HWND: {}", e))?.0 as _);

        unsafe {
            let ex_style = GetWindowLongW(hwnd, GWL_EXSTYLE);
            if (ex_style & WS_EX_LAYERED.0 as i32) != 0 {
                let mut alpha: u8 = 255;
                let _ = GetLayeredWindowAttributes(hwnd, None, Some(&mut alpha), None);
                Ok(alpha as f64 / 255.0)
            } else {
                Ok(1.0)
            }
        }
    }

    #[cfg(target_os = "linux")]
    {
        let _ = window;
        Ok(1.0) // Default to fully opaque on Linux
    }
}

// Tauri command to enable/disable screenshot protection
#[tauri::command]
fn set_screenshot_protection(app: AppHandle, enabled: bool) -> Result<(), String> {
    let window = app.get_webview_window("main").ok_or("Failed to get main window")?;

    #[cfg(target_os = "macos")]
    {
        use cocoa::base::id;

        let ns_window = window.ns_window().map_err(|e| format!("Failed to get NSWindow: {}", e))? as id;
        unsafe {
            if enabled {
                // NSWindowSharingNone = 0 prevents the window from being captured
                let _: () = msg_send![ns_window, setSharingType: 0u64];
            } else {
                // NSWindowSharingReadOnly = 1 allows capturing
                let _: () = msg_send![ns_window, setSharingType: 1u64];
            }
        }
    }

    #[cfg(target_os = "windows")]
    {
        use windows::Win32::Foundation::HWND;
        use windows::Win32::UI::WindowsAndMessaging::{SetWindowDisplayAffinity, WDA_EXCLUDEFROMCAPTURE, WDA_NONE};

        let hwnd = HWND(window.hwnd().map_err(|e| format!("Failed to get HWND: {}", e))?.0 as _);

        unsafe {
            let affinity = if enabled {
                WDA_EXCLUDEFROMCAPTURE // Exclude from screen capture
            } else {
                WDA_NONE // Allow screen capture
            };

            SetWindowDisplayAffinity(hwnd, affinity)
                .map_err(|e| format!("Failed to set display affinity: {}", e))?;
        }
    }

    #[cfg(target_os = "linux")]
    {
        let _ = (window, enabled);
        println!("Warning: Screenshot protection is not reliably supported on Linux");
        println!("Linux screenshot protection depends on compositor support and may not work");
        // On Linux, there's no standard way to prevent screenshots across all desktop environments
        // Some compositors might support _NET_WM_STATE_HIDDEN or similar, but it's not universal
    }

    Ok(())
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

            // Enable screenshot protection and full-screen overlay by default
            #[cfg(target_os = "macos")]
            {
                use cocoa::appkit::NSApplication;
                use cocoa::base::{nil, NO};

                // Set application activation policy to Accessory (non-activating)
                // NSApplicationActivationPolicyAccessory = 1
                unsafe {
                    let ns_app = NSApplication::sharedApplication(nil);
                    let _: () = msg_send![ns_app, setActivationPolicy: 1i64];
                }

                if let Some(window) = app.get_webview_window("main") {
                    use cocoa::base::id;

                    if let Ok(ns_window) = window.ns_window() {
                        let ns_window = ns_window as id;
                        unsafe {
                            // NSWindowSharingNone = 0 prevents the window from being captured
                            let _: () = msg_send![ns_window, setSharingType: 0u64];

                            // Set collection behavior to show over full-screen apps and ignore activation cycle
                            // NSWindowCollectionBehaviorCanJoinAllSpaces = 1 << 0
                            // NSWindowCollectionBehaviorFullScreenAuxiliary = 1 << 8
                            // NSWindowCollectionBehaviorIgnoresCycle = 1 << 6 (prevents window from being activated by window cycling)
                            let collection_behavior: u64 = (1 << 0) | (1 << 8) | (1 << 6);
                            let _: () = msg_send![ns_window, setCollectionBehavior: collection_behavior];

                            // Set window level to floating to keep it on top without activation
                            // NSFloatingWindowLevel = 3
                            let _: () = msg_send![ns_window, setLevel: 3i32];

                            // Prevent the window from hiding when it "deactivates"
                            let _: () = msg_send![ns_window, setHidesOnDeactivate: NO];

                            // Set style mask to include non-activating panel behavior
                            // This prevents the window from becoming key when clicked
                            let current_style: u64 = msg_send![ns_window, styleMask];
                            // NSWindowStyleMaskNonactivatingPanel = 1 << 7
                            let new_style = current_style | (1 << 7);
                            let _: () = msg_send![ns_window, setStyleMask: new_style];
                        }
                    }
                }
            }

            // Enable screenshot protection and non-activating style by default on Windows
            #[cfg(target_os = "windows")]
            {
                if let Some(window) = app.get_webview_window("main") {
                    use windows::Win32::Foundation::HWND;
                    use windows::Win32::UI::WindowsAndMessaging::{
                        SetWindowDisplayAffinity, WDA_EXCLUDEFROMCAPTURE,
                        GetWindowLongW, SetWindowLongW, GWL_EXSTYLE, WS_EX_NOACTIVATE
                    };

                    if let Ok(hwnd_wrapper) = window.hwnd() {
                        let hwnd = HWND(hwnd_wrapper.0 as _);
                        unsafe {
                            // Enable screenshot protection
                            let _ = SetWindowDisplayAffinity(hwnd, WDA_EXCLUDEFROMCAPTURE);

                            // Set WS_EX_NOACTIVATE to prevent activation
                            let ex_style = GetWindowLongW(hwnd, GWL_EXSTYLE);
                            SetWindowLongW(hwnd, GWL_EXSTYLE, ex_style | WS_EX_NOACTIVATE.0 as i32);
                        }
                    }
                }
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
            get_user_info,
            start_login,
            logout,
            refresh_notes,
            set_window_opacity,
            get_window_opacity,
            set_screenshot_protection
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
