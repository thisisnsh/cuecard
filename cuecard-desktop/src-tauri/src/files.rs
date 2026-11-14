//! Files the window can't reach on its own: the images placed in scripts,
//! kept in the app's own storage, and the storage folder the user picks, where
//! saved scripts are also kept as text files — the same folder the phone app
//! keeps them in, so a folder in iCloud Drive brings them to both.
//!
//! The folder is given as a path on each call. Everything else names a file
//! at its top, or in its `.cuecard-images` folder, and is never a path, so
//! nothing outside the folder can be reached through it.
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

// =============================================================================
// THE STORAGE FOLDER
// =============================================================================

/// The folder the images placed in scripts are kept in, inside the storage folder.
const FOLDER_IMAGES: &str = ".cuecard-images";

/// The largest file read as a script. Far more than any script runs to.
const MAX_SCRIPT_BYTES: u64 = 10 * 1024 * 1024;

/// A name at the top of a folder: never empty, never a path.
fn is_plain_name(name: &str) -> bool {
    !name.is_empty() && name != "." && name != ".." && !name.contains('/') && !name.contains('\\')
}

/// The storage folder, if it's there and is a folder.
fn folder_dir(folder: &str) -> Result<PathBuf, String> {
    let path = PathBuf::from(folder);
    if !path.is_absolute() {
        return Err("The storage folder isn't a full path".into());
    }
    if !path.is_dir() {
        return Err("The storage folder can't be reached".into());
    }
    Ok(path)
}

fn folder_file(folder: &str, name: &str) -> Result<PathBuf, String> {
    if !is_plain_name(name) {
        return Err(format!("“{}” isn't a file name", name));
    }
    Ok(folder_dir(folder)?.join(name))
}

/// An image in the folder's image folder: its name, or the stand-in iCloud
/// Drive leaves for one that isn't downloaded, `.name.icloud`.
fn folder_image(folder: &str, name: &str) -> Result<PathBuf, String> {
    let inner = name
        .strip_prefix('.')
        .and_then(|n| n.strip_suffix(".icloud"))
        .unwrap_or(name);
    if !is_image_name(inner) {
        return Err(format!("“{}” isn't an image name", name));
    }
    Ok(folder_dir(folder)?.join(FOLDER_IMAGES).join(name))
}

#[derive(Serialize)]
pub struct FolderEntry {
    name: String,
    #[serde(rename = "isDir")]
    is_dir: bool,
    size: u64,
    modified: Option<f64>,
    created: Option<f64>,
}

/// Whether the folder is there to be used.
#[tauri::command]
pub async fn folder_check(folder: String) -> bool {
    folder_dir(&folder).is_ok()
}

/// Whether the folder is in iCloud Drive, so the phone can share it.
#[tauri::command]
pub async fn folder_is_icloud(folder: String) -> bool {
    folder.contains("/Library/Mobile Documents/") || folder.contains("iCloudDrive")
}

/// Everything at the top of the folder, hidden files included, or an error if
/// it can't be listed — which is not the same as being empty.
#[tauri::command]
pub async fn folder_list(folder: String) -> Result<Vec<FolderEntry>, String> {
    let dir = folder_dir(&folder)?;
    let entries = fs::read_dir(&dir).map_err(|e| format!("Couldn't list the storage folder: {}", e))?;
    Ok(entries
        .flatten()
        .filter_map(|entry| {
            let name = entry.file_name().to_str()?.to_string();
            let metadata = entry.metadata().ok()?;
            Some(FolderEntry {
                is_dir: metadata.is_dir(),
                size: metadata.len(),
                modified: modified_ms(&metadata),
                created: metadata
                    .created()
                    .ok()
                    .and_then(|t| t.duration_since(UNIX_EPOCH).ok())
                    .map(|d| d.as_secs_f64() * 1000.0),
                name,
            })
        })
        .collect())
}

/// A file's text. Not UTF-8, it's read as near as it can be. Null if it's
/// missing or too large to be a script.
#[tauri::command]
pub async fn folder_read_text(folder: String, name: String) -> Result<Option<String>, String> {
    let path = folder_file(&folder, &name)?;
    let Ok(metadata) = fs::metadata(&path) else {
        return Ok(None);
    };
    if metadata.len() > MAX_SCRIPT_BYTES {
        return Ok(None);
    }
    let Ok(data) = fs::read(&path) else {
        return Ok(None);
    };
    Ok(Some(match String::from_utf8(data) {
        Ok(text) => text,
        Err(error) => String::from_utf8_lossy(error.as_bytes()).into_owned(),
    }))
}

/// Write a file whole, and say when it was last changed once written.
#[tauri::command]
pub async fn folder_write_text(folder: String, name: String, text: String) -> Result<Option<f64>, String> {
    let path = folder_file(&folder, &name)?;
    write_atomic(&path, text.as_bytes())?;
    Ok(fs::metadata(&path).ok().as_ref().and_then(modified_ms))
}

/// Rename a file at the top of the folder. Never over one that's there.
#[tauri::command]
pub async fn folder_rename(folder: String, from: String, to: String) -> Result<(), String> {
    let source = folder_file(&folder, &from)?;
    let target = folder_file(&folder, &to)?;
    // A change of case alone is the same file on most disks.
    if target.exists() && from.to_lowercase() != to.to_lowercase() {
        return Err(format!("“{}” is already there", to));
    }
    fs::rename(&source, &target).map_err(|e| format!("Couldn't rename “{}”: {}", from, e))
}

/// Delete a file, and its iCloud Drive stand-in if it isn't downloaded. True
/// once neither is there.
#[tauri::command]
pub async fn folder_remove(folder: String, name: String) -> Result<bool, String> {
    let dir = folder_dir(&folder)?;
    if !is_plain_name(&name) {
        return Err(format!("“{}” isn't a file name", name));
    }
    let gone = [name.clone(), format!(".{}.icloud", name)].iter().all(|candidate| {
        let path = dir.join(candidate);
        !path.exists() || fs::remove_file(&path).is_ok()
    });
    Ok(gone)
}

/// Ask iCloud Drive for a file that isn't downloaded yet. It's taken in on a
/// later sync, once it's arrived. Anywhere else this does nothing.
#[tauri::command]
pub async fn folder_download(folder: String, name: String) -> Result<(), String> {
    #[cfg(target_os = "macos")]
    {
        let path = if name.starts_with(FOLDER_IMAGES) {
            let image = name.trim_start_matches(FOLDER_IMAGES).trim_start_matches('/');
            folder_image(&folder, image)?
        } else {
            folder_file(&folder, &name)?
        };
        let _ = std::process::Command::new("/usr/bin/brctl")
            .arg("download")
            .arg(&path)
            .stdout(std::process::Stdio::null())
            .stderr(std::process::Stdio::null())
            .spawn();
    }
    #[cfg(not(target_os = "macos"))]
    let _ = (folder, name);
    Ok(())
}

/// The names in the folder's image folder, iCloud Drive's stand-ins included.
#[tauri::command]
pub async fn folder_images_list(folder: String) -> Result<Vec<String>, String> {
    let dir = folder_dir(&folder)?.join(FOLDER_IMAGES);
    let Ok(entries) = fs::read_dir(&dir) else {
        return Ok(Vec::new());
    };
    Ok(entries
        .flatten()
        .filter_map(|entry| entry.file_name().to_str().map(str::to_string))
        .collect())
}

/// An image's bytes from the folder, or an error if it isn't there yet.
#[tauri::command]
pub async fn folder_image_read(folder: String, name: String) -> Result<Response, String> {
    let path = folder_image(&folder, &name)?;
    let data = fs::read(&path).map_err(|_| format!("No image “{}” in the folder", name))?;
    Ok(Response::new(data))
}

/// Copy an image into the folder, sent as the raw body with the folder and the
/// name in the `x-folder` and `x-image-name` headers. One there already is left.
#[tauri::command]
pub async fn folder_image_write(request: Request<'_>) -> Result<(), String> {
    let header = |key: &str| {
        request
            .headers()
            .get(key)
            .and_then(|value| value.to_str().ok())
            .map(|value| urlencoding::decode(value).map(|v| v.into_owned()).unwrap_or_default())
            .ok_or_else(|| format!("No {}", key))
    };
    let folder = header("x-folder")?;
    let name = header("x-image-name")?;
    let InvokeBody::Raw(data) = request.body() else {
        return Err("Expected the image's bytes".into());
    };
    let path = folder_image(&folder, &name)?;
    if path.exists() {
        return Ok(());
    }
    fs::create_dir_all(folder_dir(&folder)?.join(FOLDER_IMAGES))
        .map_err(|e| format!("Couldn't make the folder's image folder: {}", e))?;
    write_atomic(&path, data)
}

/// Delete an image from the folder, or its iCloud Drive stand-in.
#[tauri::command]
pub async fn folder_image_remove(folder: String, name: String) -> Result<(), String> {
    let path = folder_image(&folder, &name)?;
    match fs::remove_file(&path) {
        Ok(()) => Ok(()),
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(()),
        Err(e) => Err(format!("Couldn't delete “{}”: {}", name, e)),
    }
}
