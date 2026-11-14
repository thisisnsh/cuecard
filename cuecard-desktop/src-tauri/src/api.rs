//! The notes API: a way for any presentation app to hand CueCard its speaker
//! notes, so Keynote, PowerPoint, Deckset or a script of your own can drive the
//! window the way the Google Slides extension does.
//!
//! Two routes on the local server, next to `/slides`:
//!
//! - `POST /notes` shows the notes it is sent, right away.
//! - `POST /notes/clear` says the presentation is over.
//!
//! `/notes` ends in the same `slide-update` event `/slides` sends, so the
//! window and the teleprompter can't tell the difference. Nothing here talks to
//! Google.
//!
//! These routes put any text they're given in front of the speaker, so two
//! things guard them:
//!
//! - Web pages are turned away. A request a browser sends carries an `Origin`
//!   or `Sec-Fetch-Site` header, and one sent by way of DNS rebinding names
//!   some other host in `Host`. The routes also sit outside the server's CORS
//!   layer, so a page's preflight fails before it gets that far. Web decks
//!   reach CueCard through the browser extension instead.
//! - Each request carries the token kept in the app data folder, which only
//!   the person signed in to the computer can read.
//!
//! See API.md for the details.

use axum::{
    extract::rejection::JsonRejection,
    http::{HeaderMap, StatusCode},
    response::{IntoResponse, Response},
    Json,
};
use once_cell::sync::Lazy;
use parking_lot::RwLock;
use serde::Deserialize;
use std::path::Path;
use tauri::{AppHandle, Emitter, Manager};

use crate::{clean_notes_text, SlideData, SlideUpdateEvent, APP_HANDLE, CURRENT_SLIDE, SLIDE_NOTES};

/// The version of this API, given out by `/health` so a client can tell
/// whether the app it found understands it.
pub const API_VERSION: u32 = 1;

/// The file in the app data folder the token is kept in, where a client on
/// the same computer can read it.
const TOKEN_FILE: &str = "api-token";
const TOKEN_HEADER: &str = "x-cuecard-token";

const MAX_SOURCE_LEN: usize = 64;
const MAX_NAME_LEN: usize = 512;

static TOKEN: Lazy<RwLock<Option<String>>> = Lazy::new(|| RwLock::new(None));

// =============================================================================
// REQUESTS
// =============================================================================

#[derive(Debug, Deserialize)]
pub struct NotesRequest {
    source: String,
    notes: String,
    deck: Option<String>,
    title: Option<String>,
    /// Which slide this is, counting from 1.
    slide: Option<i32>,
    /// How many slides the deck has.
    slides: Option<i32>,
}

#[derive(Debug, Deserialize)]
pub struct ClearRequest {
    source: String,
}

#[derive(Debug, PartialEq)]
pub struct ApiError {
    status: StatusCode,
    message: String,
}

impl ApiError {
    fn new(status: StatusCode, message: impl Into<String>) -> Self {
        Self { status, message: message.into() }
    }

    fn bad_request(message: impl Into<String>) -> Self {
        Self::new(StatusCode::BAD_REQUEST, message)
    }
}

impl IntoResponse for ApiError {
    fn into_response(self) -> Response {
        (self.status, Json(serde_json::json!({ "error": self.message }))).into_response()
    }
}

type ApiResult = Result<Json<serde_json::Value>, ApiError>;

// =============================================================================
// TOKEN
// =============================================================================

/// Read the token from the app data folder, or make one and write it there on
/// first launch. A folder that can't be written to still gets a token for this
/// launch, which the copy button in Settings hands out.
pub fn init_token(app: &AppHandle) {
    let dir = app.path().app_data_dir().ok();
    let token = dir
        .as_deref()
        .and_then(read_token)
        .unwrap_or_else(|| {
            let token = new_token();
            if let Some(dir) = dir.as_deref() {
                if let Err(e) = write_token(dir, &token) {
                    eprintln!("Could not save the notes API token: {}", e);
                }
            }
            token
        });
    *TOKEN.write() = Some(token);
}

fn read_token(dir: &Path) -> Option<String> {
    let token = std::fs::read_to_string(dir.join(TOKEN_FILE)).ok()?;
    let token = token.trim();
    (token.len() >= 32).then(|| token.to_string())
}

/// 244 random bits, as 64 hex characters.
fn new_token() -> String {
    format!("{}{}", uuid::Uuid::new_v4().simple(), uuid::Uuid::new_v4().simple())
}

/// Written so only the person signed in to the computer can read it.
fn write_token(dir: &Path, token: &str) -> std::io::Result<()> {
    use std::io::Write;

    std::fs::create_dir_all(dir)?;
    let mut options = std::fs::OpenOptions::new();
    options.write(true).create(true).truncate(true);
    #[cfg(unix)]
    {
        use std::os::unix::fs::OpenOptionsExt;
        options.mode(0o600);
    }
    let mut file = options.open(dir.join(TOKEN_FILE))?;
    file.write_all(token.as_bytes())?;
    file.write_all(b"\n")
}

/// Turn away anything a web browser sent. Browsers add `Origin` to every POST
/// that isn't same-origin and `Sec-Fetch-Site` to nearly everything; scripts
/// and apps send neither. A page that rebinds its own host name to 127.0.0.1
/// gets past both as same-origin, but its requests still name that host.
fn reject_browsers(headers: &HeaderMap) -> Result<(), ApiError> {
    if headers.contains_key(axum::http::header::ORIGIN) || headers.contains_key("sec-fetch-site") {
        return Err(ApiError::new(
            StatusCode::FORBIDDEN,
            "The notes API doesn't take requests from web pages",
        ));
    }

    let host = headers.get(axum::http::header::HOST).and_then(|v| v.to_str().ok());
    match host {
        None => Ok(()),
        Some(host) if is_local_host(host) => Ok(()),
        Some(_) => Err(ApiError::new(
            StatusCode::FORBIDDEN,
            "The notes API only answers to 127.0.0.1 or localhost",
        )),
    }
}

fn is_local_host(host: &str) -> bool {
    // The name without its port: "[::1]:3642" is "[::1]", "localhost:3642" is "localhost".
    let name = if host.starts_with('[') {
        host.split_inclusive(']').next().unwrap_or(host)
    } else {
        host.split(':').next().unwrap_or(host)
    };
    matches!(name.to_ascii_lowercase().as_str(), "127.0.0.1" | "localhost" | "[::1]")
}

/// The token is sent as `X-CueCard-Token`, or as `Authorization: Bearer …` for
/// clients that only know how to send that.
fn authorize(headers: &HeaderMap) -> Result<(), ApiError> {
    let expected = TOKEN.read().clone();
    let expected = expected.ok_or_else(|| {
        ApiError::new(StatusCode::SERVICE_UNAVAILABLE, "CueCard is still starting up")
    })?;

    let sent = headers
        .get(TOKEN_HEADER)
        .and_then(|v| v.to_str().ok())
        .or_else(|| {
            headers
                .get(axum::http::header::AUTHORIZATION)
                .and_then(|v| v.to_str().ok())
                .and_then(|v| v.strip_prefix("Bearer "))
        })
        .map(str::trim);

    match sent {
        Some(sent) if same_token(sent, &expected) => Ok(()),
        Some(_) => Err(ApiError::new(StatusCode::UNAUTHORIZED, "The token is not the one CueCard has")),
        None => Err(ApiError::new(
            StatusCode::UNAUTHORIZED,
            "Send the token from CueCard's Settings as X-CueCard-Token",
        )),
    }
}

/// Compared without stopping at the first difference, so how long a guess
/// takes to fail says nothing about how close it was.
fn same_token(a: &str, b: &str) -> bool {
    a.len() == b.len() && a.bytes().zip(b.bytes()).fold(0u8, |acc, (x, y)| acc | (x ^ y)) == 0
}

#[tauri::command]
pub fn api_token() -> Option<String> {
    TOKEN.read().clone()
}

// =============================================================================
// HANDLERS
// =============================================================================

pub async fn notes_handler(headers: HeaderMap, body: Result<Json<NotesRequest>, JsonRejection>) -> ApiResult {
    reject_browsers(&headers)?;
    authorize(&headers)?;
    show(body.map_err(rejected)?.0)
}

pub async fn clear_handler(headers: HeaderMap, body: Result<Json<ClearRequest>, JsonRejection>) -> ApiResult {
    reject_browsers(&headers)?;
    authorize(&headers)?;
    clear(body.map_err(rejected)?.0)
}

fn rejected(rejection: JsonRejection) -> ApiError {
    ApiError::new(rejection.status(), rejection.body_text())
}

/// Put the notes on screen, as `/slides` would have.
fn show(request: NotesRequest) -> ApiResult {
    let source = checked_source(&request.source)?;
    let deck = match request.deck.as_deref() {
        Some(deck) => checked_name("deck", deck)?,
        None => source.clone(),
    };
    let title = match request.title.as_deref().map(str::trim) {
        None | Some("") => deck.clone(),
        Some(title) => checked_name("title", title)?,
    };
    let slides = request.slides.map(|n| checked_count("slides", n)).transpose()?;
    let slide = request.slide.map(|n| checked_count("slide", n)).transpose()?;
    if let (Some(slide), Some(slides)) = (slide, slides) {
        if slide > slides {
            return Err(ApiError::bad_request(format!("slide {} is past the end of a {}-slide deck", slide, slides)));
        }
    }

    let presentation_id = format!("{}:{}", source_key(&source), deck);
    // A slide with no number is a new one each time, so the teleprompter starts
    // it from the top rather than treating it as the same slide edited.
    let slide_id = slide
        .map(|n| n.to_string())
        .unwrap_or_else(|| uuid::Uuid::new_v4().simple().to_string());

    let notes = clean_notes_text(&request.notes);
    let notes = (!notes.is_empty()).then_some(notes);

    let slide_data = SlideData {
        presentation_id: presentation_id.clone(),
        slide_id: slide_id.clone(),
        slide_number: slide.unwrap_or(0),
        title,
        mode: "external".to_string(),
        timestamp: chrono::Utc::now().timestamp_millis(),
        url: String::new(),
        force_refresh: None,
        source: Some(source),
        slide_count: slides,
    };

    {
        // Only the slide on screen is kept: nothing asks for another one again.
        let mut cache = SLIDE_NOTES.write();
        let prefix = format!("{}:", presentation_id);
        cache.retain(|key, _| !key.starts_with(&prefix));
        if let Some(n) = &notes {
            cache.insert(format!("{}{}", prefix, slide_id), n.clone());
        }
    }
    *CURRENT_SLIDE.write() = Some(slide_data.clone());

    if let Some(app) = APP_HANDLE.read().as_ref() {
        let _ = app.emit("slide-update", SlideUpdateEvent { slide_data, notes });
    }
    Ok(Json(serde_json::json!({ "received": true })))
}

/// The presentation is over. Only notes the same app sent are taken down, so
/// one app ending its show can't clear another's, or Google's.
fn clear(request: ClearRequest) -> ApiResult {
    let source = checked_source(&request.source)?;

    let cleared = {
        let mut current = CURRENT_SLIDE.write();
        match current.as_ref() {
            Some(slide) if slide.source.as_deref().map(source_key) == Some(source_key(&source)) => {
                // Every deck from that app, not just the one on screen.
                let prefix = format!("{}:", source_key(&source));
                SLIDE_NOTES.write().retain(|key, _| !key.starts_with(&prefix));
                *current = None;
                true
            }
            _ => false,
        }
    };

    if cleared {
        if let Some(app) = APP_HANDLE.read().as_ref() {
            let _ = app.emit("slide-clear", serde_json::json!({ "source": source }));
        }
    }
    Ok(Json(serde_json::json!({ "received": true, "cleared": cleared })))
}

// =============================================================================
// CHECKS
// =============================================================================

/// A source as it identifies its decks: "Keynote" and "keynote" are one app,
/// whichever way it spells its name on screen.
fn source_key(source: &str) -> String {
    source.to_lowercase()
}

fn checked_source(source: &str) -> Result<String, ApiError> {
    let source = source.trim();
    if source.is_empty() {
        return Err(ApiError::bad_request("source can't be empty"));
    }
    if source.chars().count() > MAX_SOURCE_LEN {
        return Err(ApiError::bad_request(format!("source can be at most {} characters", MAX_SOURCE_LEN)));
    }
    Ok(source.to_string())
}

fn checked_name(field: &str, value: &str) -> Result<String, ApiError> {
    let value = value.trim();
    if value.is_empty() {
        return Err(ApiError::bad_request(format!("{} can't be empty", field)));
    }
    if value.chars().count() > MAX_NAME_LEN {
        return Err(ApiError::bad_request(format!("{} can be at most {} characters", field, MAX_NAME_LEN)));
    }
    Ok(value.to_string())
}

fn checked_count(field: &str, value: i32) -> Result<i32, ApiError> {
    if value < 1 {
        return Err(ApiError::bad_request(format!("{} counts from 1", field)));
    }
    Ok(value)
}

// =============================================================================
// TESTS
// =============================================================================

#[cfg(test)]
#[allow(unused_must_use)]
mod tests {
    use super::*;
    use axum::http::HeaderValue;

    // The handlers share the app's global state, so the tests that touch it
    // take turns.
    static SERIAL: parking_lot::Mutex<()> = parking_lot::Mutex::new(());

    fn current() -> Option<(SlideData, Option<String>)> {
        let slide = CURRENT_SLIDE.read().clone()?;
        let key = format!("{}:{}", slide.presentation_id, slide.slide_id);
        let notes = SLIDE_NOTES.read().get(&key).cloned();
        Some((slide, notes))
    }

    fn request(source: &str, notes: &str) -> NotesRequest {
        NotesRequest {
            source: source.into(),
            notes: notes.into(),
            deck: None,
            title: None,
            slide: None,
            slides: None,
        }
    }

    #[test]
    fn notes_are_shown() {
        let _turn = SERIAL.lock();
        show(NotesRequest {
            deck: Some("Talk.md".into()),
            slide: Some(4),
            slides: Some(20),
            ..request("deckset", "Hello\u{000B}there\u{200B}")
        })
        .unwrap();

        let (slide, notes) = current().unwrap();
        assert_eq!(slide.presentation_id, "deckset:Talk.md");
        assert_eq!(slide.slide_number, 4);
        assert_eq!(slide.slide_count, Some(20));
        assert_eq!(slide.title, "Talk.md");
        assert_eq!(slide.source.as_deref(), Some("deckset"));
        assert_eq!(notes.as_deref(), Some("Hello\nthere"));
    }

    #[test]
    fn only_the_slide_on_screen_is_kept() {
        let _turn = SERIAL.lock();
        for slide in 1..=3 {
            show(NotesRequest { deck: Some("Many.key".into()), slide: Some(slide), ..request("keynote", "words") });
        }
        let kept = SLIDE_NOTES.read().keys().filter(|k| k.starts_with("keynote:Many.key:")).count();
        assert_eq!(kept, 1);
    }

    #[test]
    fn notes_without_a_slide_are_a_new_slide_each_time() {
        let _turn = SERIAL.lock();
        show(request("script", "Same words")).unwrap();
        let first = current().unwrap().0.slide_id;
        show(request("script", "Same words")).unwrap();
        let (slide, _) = current().unwrap();
        assert_ne!(first, slide.slide_id);
        assert_eq!(slide.slide_number, 0);
        assert_eq!(slide.title, "script");
    }

    #[test]
    fn clear_only_takes_down_its_own_notes() {
        let _turn = SERIAL.lock();
        show(NotesRequest { slide: Some(1), ..request("keynote", "Hi") }).unwrap();

        let other = clear(ClearRequest { source: "powerpoint".into() }).unwrap();
        assert_eq!(other.0["cleared"], false);
        assert!(current().is_some());

        let own = clear(ClearRequest { source: "KeyNote".into() }).unwrap();
        assert_eq!(own.0["cleared"], true);
        assert!(current().is_none());
        assert!(!SLIDE_NOTES.read().keys().any(|k| k.starts_with("keynote:")));
    }

    #[test]
    fn rejects_bad_fields() {
        let blank_source = show(request("  ", ""));
        assert_eq!(blank_source.unwrap_err().status, StatusCode::BAD_REQUEST);

        let slide_zero = show(NotesRequest { slide: Some(0), ..request("keynote", "") });
        assert_eq!(slide_zero.unwrap_err().status, StatusCode::BAD_REQUEST);

        let past_end = show(NotesRequest { slide: Some(5), slides: Some(4), ..request("keynote", "") });
        assert_eq!(past_end.unwrap_err().status, StatusCode::BAD_REQUEST);
    }

    #[test]
    fn token_check() {
        let _turn = SERIAL.lock();
        *TOKEN.write() = Some("a".repeat(64));

        let mut headers = HeaderMap::new();
        assert_eq!(authorize(&headers).unwrap_err().status, StatusCode::UNAUTHORIZED);

        headers.insert(TOKEN_HEADER, HeaderValue::from_static("wrong"));
        assert_eq!(authorize(&headers).unwrap_err().status, StatusCode::UNAUTHORIZED);

        headers.insert(TOKEN_HEADER, HeaderValue::from_str(&"a".repeat(64)).unwrap());
        assert!(authorize(&headers).is_ok());

        let mut bearer = HeaderMap::new();
        let value = format!("Bearer {}", "a".repeat(64));
        bearer.insert(axum::http::header::AUTHORIZATION, HeaderValue::from_str(&value).unwrap());
        assert!(authorize(&bearer).is_ok());
    }

    #[test]
    fn browsers_are_turned_away() {
        let local = |host: &str| {
            let mut headers = HeaderMap::new();
            headers.insert(axum::http::header::HOST, HeaderValue::from_str(host).unwrap());
            headers
        };

        for host in ["127.0.0.1:3642", "localhost:3642", "LOCALHOST", "[::1]:3642", "127.0.0.1"] {
            assert!(reject_browsers(&local(host)).is_ok(), "{}", host);
        }
        assert!(reject_browsers(&HeaderMap::new()).is_ok());

        // DNS rebinding: the page's own name, pointed at this computer.
        for host in ["evil.example:3642", "127.0.0.1.evil.example", "localhost.evil.example:3642"] {
            assert_eq!(reject_browsers(&local(host)).unwrap_err().status, StatusCode::FORBIDDEN, "{}", host);
        }

        let mut from_page = local("127.0.0.1:3642");
        from_page.insert(axum::http::header::ORIGIN, HeaderValue::from_static("https://example.com"));
        assert_eq!(reject_browsers(&from_page).unwrap_err().status, StatusCode::FORBIDDEN);

        let mut file_page = local("127.0.0.1:3642");
        file_page.insert(axum::http::header::ORIGIN, HeaderValue::from_static("null"));
        assert_eq!(reject_browsers(&file_page).unwrap_err().status, StatusCode::FORBIDDEN);

        let mut fetched = local("127.0.0.1:3642");
        fetched.insert("sec-fetch-site", HeaderValue::from_static("same-origin"));
        assert_eq!(reject_browsers(&fetched).unwrap_err().status, StatusCode::FORBIDDEN);
    }

    #[test]
    fn token_file() {
        let dir = std::env::temp_dir().join(format!("cuecard-api-test-{}", uuid::Uuid::new_v4().simple()));
        assert_eq!(read_token(&dir), None);

        let token = new_token();
        assert_eq!(token.len(), 64);
        write_token(&dir, &token).unwrap();
        assert_eq!(read_token(&dir).as_deref(), Some(token.as_str()));

        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            let mode = std::fs::metadata(dir.join(TOKEN_FILE)).unwrap().permissions().mode();
            assert_eq!(mode & 0o777, 0o600);
        }
        let _ = std::fs::remove_dir_all(&dir);
    }
}
