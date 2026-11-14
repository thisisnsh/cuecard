//! Files the window can't reach on its own: the images placed in scripts,
//! kept in the app's own storage.
//!
//! Images are read and written as raw bytes, so a photo crosses the bridge as
//! one buffer rather than a JSON array of numbers.

use serde::Serialize;
use std::fs;
use std::path::{Path, PathBuf};
use std::time::UNIX_EPOCH;
use tauri::ipc::{InvokeBody, Request, Response};
use tauri::{AppHandle, Manager};

/// Whether `name` could be one of the image store's files: letters, digits and
/// dashes, then an extension, as an `[image …]` tag allows. Never a path.
pub fn is_image_name(name: &str) -> bool {
    let Some((stem, ext)) = name.rsplit_once('.') else {
        return false;
    };
    !stem.is_empty()
        && !ext.is_empty()
        && stem.chars().all(|c| c.is_ascii_alphanumeric() || c == '-')
        && ext.chars().all(|c| c.is_ascii_alphanumeric())
}

/// When a file was last changed, in milliseconds since 1970, to the fraction.
pub fn modified_ms(metadata: &fs::Metadata) -> Option<f64> {
    let modified = metadata.modified().ok()?;
    Some(modified.duration_since(UNIX_EPOCH).ok()?.as_secs_f64() * 1000.0)
}

/// Write a file whole or not at all: to a temporary file beside it, then moved
/// over it, so nothing ever reads half of one.
pub fn write_atomic(path: &Path, data: &[u8]) -> Result<(), String> {
    let name = path
        .file_name()
        .and_then(|n| n.to_str())
        .ok_or("The file has no name")?;
    let temp = path.with_file_name(format!(".{}.cuecard-{}", name, uuid::Uuid::new_v4().simple()));
    fs::write(&temp, data).map_err(|e| format!("Couldn't write {}: {}", name, e))?;
    fs::rename(&temp, path).map_err(|e| {
        let _ = fs::remove_file(&temp);
        format!("Couldn't save {}: {}", name, e)
    })
}

// =============================================================================
// THE IMAGE STORE
// =============================================================================

fn images_dir(app: &AppHandle) -> Result<PathBuf, String> {
    let base = app
        .path()
        .app_data_dir()
        .map_err(|e| format!("No app data folder: {}", e))?;
    Ok(base.join("ScriptImages"))
}

fn image_path(app: &AppHandle, name: &str) -> Result<PathBuf, String> {
    if !is_image_name(name) {
        return Err(format!("“{}” isn't an image name", name));
    }
    Ok(images_dir(app)?.join(name))
}

#[derive(Serialize)]
pub struct StoredImage {
    name: String,
    modified: Option<f64>,
}

/// Keep an image under `name`, sent as the raw body with the name in the
/// `x-image-name` header. A file already kept under that name is left as it
/// is: names are taken from what's in the file.
#[tauri::command]
pub async fn images_save(app: AppHandle, request: Request<'_>) -> Result<(), String> {
    let name = request
        .headers()
        .get("x-image-name")
        .and_then(|value| value.to_str().ok())
        .ok_or("The image has no name")?
        .to_string();
    let InvokeBody::Raw(data) = request.body() else {
        return Err("Expected the image's bytes".into());
    };
    let path = image_path(&app, &name)?;
    if path.exists() {
        return Ok(());
    }
    fs::create_dir_all(images_dir(&app)?).map_err(|e| format!("Couldn't make the image folder: {}", e))?;
    write_atomic(&path, data)
}

/// An image's bytes, or an error if it isn't kept here.
#[tauri::command]
pub async fn images_read(app: AppHandle, name: String) -> Result<Response, String> {
    let path = image_path(&app, &name)?;
    let data = fs::read(&path).map_err(|_| format!("No image “{}”", name))?;
    Ok(Response::new(data))
}

/// Every image kept, with when each was last changed.
#[tauri::command]
pub async fn images_list(app: AppHandle) -> Result<Vec<StoredImage>, String> {
    let dir = images_dir(&app)?;
    let Ok(entries) = fs::read_dir(&dir) else {
        return Ok(Vec::new());
    };
    Ok(entries
        .flatten()
        .filter_map(|entry| {
            let name = entry.file_name().to_str()?.to_string();
            if !is_image_name(&name) {
                return None;
            }
            let modified = entry.metadata().ok().as_ref().and_then(modified_ms);
            Some(StoredImage { name, modified })
        })
        .collect())
}

#[tauri::command]
pub async fn images_remove(app: AppHandle, name: String) -> Result<(), String> {
    let path = image_path(&app, &name)?;
    match fs::remove_file(&path) {
        Ok(()) => Ok(()),
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(()),
        Err(e) => Err(format!("Couldn't delete “{}”: {}", name, e)),
    }
}
