# CueCard App

Desktop client built with Tauri that keeps your speaker notes on top of every other window while staying invisible to screen sharing, screenshots, and recordings.

### Highlights

- **Cross-platform:** macOS and Windows support
- Always-on-top window visible across all workspaces
- Screenshot protection (notes won't appear in screen shares)
- Google OAuth for syncing notes
- Auto-update support

### Architecture

- **Frontend:** vanilla HTML/JS in `src/`
- **Tauri shell:** `src-tauri/` Rust crate exposes commands for auth, timers, notes, and window control
- **Local store:** `tauri-plugin-store` caches Google and Firebase tokens, timers, and preferences
- **Firebase REST bridge:** Rust code exchanges Google OAuth tokens for Firebase custom tokens and fetches notes from Firestore

### Platform-Specific Features

| Feature | macOS | Windows |
|---------|-------|---------|
| **Always-on-top** | NSPanel with `full_screen_auxiliary` | `HWND_TOPMOST` |
| **Hide from dock/taskbar** | `ActivationPolicy::Accessory` | `WS_EX_TOOLWINDOW` |
| **Screen capture protection** | `set_content_protected` | `SetWindowDisplayAffinity` |
| **No focus stealing** | `nonactivating_panel` | `WS_EX_NOACTIVATE` |
| **Visible on all workspaces** | NSPanel collection behavior | Always-on-top behavior |

### Firebase Configuration

The desktop app expects a `firebase-config.json` file that mirrors `firebase-config-example.json`. It is packaged as part of the Tauri bundle so the Rust backend can bootstrap Firebase SDK calls.

1. Copy the example file:
   ```bash
   cp firebase-config-example.json firebase-config.json
   ```
2. Fill every field under the `firebase` key with the values from your Firebase project settings (Project Settings → General → Your apps).

Without this file the app cannot exchange Google tokens for Firebase ID tokens, so syncing notes from the browser extension will fail.

### Run in Development

```bash
npm run tauri dev
```

### Build for Production

#### macOS (Universal, macOS 11+)

CueCard targets macOS 11.0 and later and ships as a universal binary (Intel + Apple Silicon).

```bash
npm run tauri build -- --target universal-apple-darwin
```

Build artifacts are written to: `src-tauri/target/universal-apple-darwin/release/bundle/`

Artifacts:
- `dmg/CueCard_<version>_universal.dmg` — distributable installer

#### Windows (Windows 10+)

CueCard targets Windows 10 and later. Supported architectures:
- x64 (Intel / AMD) — primary target
- ARM64 — optional (Surface, Snapdragon)

```bash
# 64-bit Intel/AMD
npm run tauri build -- --target x86_64-pc-windows-msvc

# ARM64 (Surface, Snapdragon)
npm run tauri build -- --target aarch64-pc-windows-msvc
```

Build artifacts are written to: `src-tauri/target/<arch>/release/bundle/`

Artifacts:
- `msi/CueCard_<version>_<arch>.msi` — Windows Installer (enterprise-friendly)
- `nsis/CueCard_<version>_<arch>-setup.exe` — Consumer installer

Note: 32-bit (x86) Windows builds are intentionally not supported.

## Release Process

### Generating Updater Manifests (latest.json)

Tauri 2.x no longer auto-generates `latest.json` files. You must create them manually for each platform/architecture before uploading to GitHub Releases.

**Template files in `latest/` folder:**
- `latest/darwin-x86_64-latest.example.json` — macOS (universal binary serves both x86_64 and aarch64)
- `latest/windows-x86_64-latest.example.json` — Windows x64
- `latest/windows-aarch64-latest.example.json` — Windows ARM64

**To create a manifest:**

1. Copy the appropriate example file:
   ```bash
   cp latest/darwin-x86_64-latest.example.json latest/darwin-x86_64-latest.json
   ```

2. Update the fields:
   - `version`: Must match the version in `src-tauri/tauri.conf.json`
   - `notes`: Release notes (can be brief or detailed)
   - `pub_date`: ISO 8601 timestamp (e.g., `2024-01-15T12:00:00Z`)
   - `url`: Direct download URL from GitHub Releases (use the latest release URL format)
   - `signature`: Paste the **contents** of the `.sig` file (not the file path)

3. Get the signature content:
   ```bash
   # macOS
   cat src-tauri/target/universal-apple-darwin/release/bundle/macos/CueCard.app.tar.gz.sig

   # Windows x64
   cat src-tauri/target/x86_64-pc-windows-msvc/release/bundle/nsis/CueCard_<version>_x64-setup.exe.sig

   # Windows ARM64
   cat src-tauri/target/aarch64-pc-windows-msvc/release/bundle/nsis/CueCard_<version>_arm64-setup.exe.sig
   ```

**Example manifest (darwin-x86_64-latest.json):**
```json
{
  "version": "1.0.1",
  "notes": "Bug fixes and performance improvements",
  "pub_date": "2024-01-15T12:00:00Z",
  "url": "https://github.com/thisisnsh/cuecard/releases/latest/download/CueCard.app.tar.gz",
  "signature": "dW50cnVzdGVkIGNvbW1lbnQ6IHNpZ25hdHVyZSBmcm9tIHRhdXJpIHNlY3JldCBrZXkKUlVUbkVYSjhEVTFtNW..."
}
```

### macOS

1. Generate signing keys (first time only):
   ```bash
   npm run tauri signer generate -- -w ~/.tauri/cuecard.key
   ```

2. Build with signing:
   ```bash
   APPLE_SIGNING_IDENTITY="" \
   APPLE_ID="" \
   APPLE_PASSWORD="" \
   APPLE_TEAM_ID="" \
   TAURI_SIGNING_PRIVATE_KEY="" \
   TAURI_SIGNING_PRIVATE_KEY_PASSWORD="" \
   npm run tauri build -- --target universal-apple-darwin
   ```

3. Locate build artifacts in `src-tauri/target/universal-apple-darwin/release/bundle/`:
   - `dmg/CueCard_<version>_universal.dmg` - Disk image for distribution
   - `macos/CueCard.app.tar.gz` - Updater payload
   - `macos/CueCard.app.tar.gz.sig` - Updater signature

4. Generate the updater manifest:
   ```bash
   cp latest/darwin-x86_64-latest.example.json latest/darwin-x86_64-latest.json
   # Edit latest/darwin-x86_64-latest.json with correct version, notes, pub_date, and signature
   ```

5. Create GitHub Release:
   - Tag the release: `git tag v<version>`
   - Push tag: `git push origin v<version>`
   - Create release on GitHub
   - Upload:
      | Local build artifact path                                                                    | Upload as                         | Notes                      |
      | -------------------------------------------------------------------------------------------- | --------------------------------- | -------------------------- |
      | `src-tauri/target/universal-apple-darwin/release/bundle/dmg/CueCard_<version>_universal.dmg` | `CueCard_<version>_universal.dmg` | Manual installer for users |
      | `src-tauri/target/universal-apple-darwin/release/bundle/macos/CueCard.app.tar.gz`            | `CueCard.app.tar.gz`              | **Updater payload**        |
      | `src-tauri/target/universal-apple-darwin/release/bundle/macos/CueCard.app.tar.gz.sig`        | `CueCard.app.tar.gz.sig`          | Updater signature          |
      | `latest/darwin-x86_64-latest.json`                                                           | `darwin-x86_64-latest.json`       | macOS updater feed         |


### Windows

1. Generate signing keys (first time only):
   ```bash
   npm run tauri signer generate -- -w ~/.tauri/cuecard.key
   ```

2. Build for all Windows architectures:
   ```bash
   # x64 (64-bit Intel/AMD)
   TAURI_SIGNING_PRIVATE_KEY="" \
   TAURI_SIGNING_PRIVATE_KEY_PASSWORD="" \
   npm run tauri build -- --target x86_64-pc-windows-msvc

   # ARM64 (Surface, Snapdragon)
   TAURI_SIGNING_PRIVATE_KEY="" \
   TAURI_SIGNING_PRIVATE_KEY_PASSWORD="" \
   npm run tauri build -- --target aarch64-pc-windows-msvc
   ```

3. Locate build artifacts in `src-tauri/target/<arch>/release/bundle/`:
   - `msi/CueCard_<version>_<arch>.msi` - Windows Installer
   - `nsis/CueCard_<version>_<arch>-setup.exe` - NSIS Installer
   - `nsis/CueCard_<version>_<arch>-setup.exe.sig` - Updater signature

4. Sign Artifacts
   ```bash
   # Windows code signing (run on a Windows machine with Windows SDK installed)

   # Path to your code signing certificate (.pfx)
   $CERT_PATH="C:\path\to\CueCard.pfx"

   # Certificate password (avoid hardcoding in CI)
   $CERT_PASSWORD="YOUR_CERT_PASSWORD"

   # Timestamp server (example: DigiCert)
   $TIMESTAMP_URL="http://timestamp.digicert.com"

   # Sign NSIS installer (.exe)
   signtool sign `
   /f $CERT_PATH `
   /p $CERT_PASSWORD `
   /fd SHA256 `
   /tr $TIMESTAMP_URL `
   /td SHA256 `
   "src-tauri\target\x86_64-pc-windows-msvc\release\bundle\nsis\CueCard_1.0.1_x64-setup.exe"

   # Sign MSI installer (.msi)
   signtool sign `
   /f $CERT_PATH `
   /p $CERT_PASSWORD `
   /fd SHA256 `
   /tr $TIMESTAMP_URL `
   /td SHA256 `
   "src-tauri\target\x86_64-pc-windows-msvc\release\bundle\msi\CueCard_1.0.1_x64.msi"
   ```

5. Generate the updater manifests:
   ```bash
   # Windows x64
   cp latest/windows-x86_64-latest.example.json latest/windows-x86_64-latest.json
   # Edit latest/windows-x86_64-latest.json with correct version, notes, pub_date, and signature

   # Windows ARM64
   cp latest/windows-aarch64-latest.example.json latest/windows-aarch64-latest.json
   # Edit latest/windows-aarch64-latest.json with correct version, notes, pub_date, and signature
   ```

6. Create GitHub Release:
   - Tag the release: `git tag v<version>`
   - Push tag: `git push origin v<version>`
   - Create release on GitHub
   - Upload: (x64)
      | Local build artifact path                                                                         | Upload as                             | Notes                             |
      | ------------------------------------------------------------------------------------------------- | ------------------------------------- | --------------------------------- |
      | `src-tauri/target/x86_64-pc-windows-msvc/release/bundle/nsis/CueCard_<version>_x64-setup.exe`     | `CueCard_<version>_x64-setup.exe`     | NSIS installer (manual + updater) |
      | `src-tauri/target/x86_64-pc-windows-msvc/release/bundle/nsis/CueCard_<version>_x64-setup.exe.sig` | `CueCard_<version>_x64-setup.exe.sig` | Updater signature                 |
      | `src-tauri/target/x86_64-pc-windows-msvc/release/bundle/msi/CueCard_<version>_x64.msi`            | `CueCard_<version>_x64.msi`           | MSI installer (manual only)       |
      | `src-tauri/target/x86_64-pc-windows-msvc/release/bundle/msi/CueCard_<version>_x64.msi.sig`        | `CueCard_<version>_x64.msi.sig`       | MSI signature                     |
      | `latest/windows-x86_64-latest.json`                                                               | `windows-x86_64-latest.json`          | Windows x64 updater feed          |
   - Upload: (ARM64)
      | Local build artifact path                                                                            | Upload as                               | Notes                             |
      | ---------------------------------------------------------------------------------------------------- | --------------------------------------- | --------------------------------- |
      | `src-tauri/target/aarch64-pc-windows-msvc/release/bundle/nsis/CueCard_<version>_arm64-setup.exe`     | `CueCard_<version>_arm64-setup.exe`     | NSIS installer (manual + updater) |
      | `src-tauri/target/aarch64-pc-windows-msvc/release/bundle/nsis/CueCard_<version>_arm64-setup.exe.sig` | `CueCard_<version>_arm64-setup.exe.sig` | Updater signature                 |
      | `src-tauri/target/aarch64-pc-windows-msvc/release/bundle/msi/CueCard_<version>_arm64.msi`            | `CueCard_<version>_arm64.msi`           | MSI installer (manual only)       |
      | `src-tauri/target/aarch64-pc-windows-msvc/release/bundle/msi/CueCard_<version>_arm64.msi.sig`        | `CueCard_<version>_arm64.msi.sig`       | MSI signature                     |
      | `latest/windows-aarch64-latest.json`                                                                 | `windows-aarch64-latest.json`           | Windows ARM64 updater feed        |


### Notes

- macOS builds are signed and notarized as part of the macOS release process described above.
- Windows installers (.exe and .msi) should be Authenticode code-signed to avoid SmartScreen warnings.
- Tauri updater signatures (.sig files) are separate from OS-level code signing and are required for auto-updates.
