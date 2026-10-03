#!/usr/bin/env bash
# Builds the Mac App Store package: a sandboxed universal CueCard.app signed
# for distribution, wrapped in a signed .pkg ready for Transporter.
#
#   scripts/build-appstore.sh            # build the .pkg
#   scripts/build-appstore.sh --upload   # build, then upload to App Store Connect
#
# Optional environment:
#   BUILD_NUMBER             CFBundleVersion; defaults to the current date and time
#   APP_SIGNING_IDENTITY     defaults to "Apple Distribution: Nishant Hada (983LBM5U6B)"
#   INSTALLER_IDENTITY       defaults to "3rd Party Mac Developer Installer: Nishant Hada (983LBM5U6B)"
#   APPLE_API_KEY_ID, APPLE_API_ISSUER   App Store Connect API key, needed for --upload;
#                            the key file goes in ~/.appstoreconnect/private_keys/AuthKey_<id>.p8
set -euo pipefail

cd "$(dirname "$0")/.."

PROFILE="src-tauri/appstore/embedded.provisionprofile"
BUILD_NUMBER="${BUILD_NUMBER:-$(date +%Y%m%d.%H%M)}"
APP_SIGNING_IDENTITY="${APP_SIGNING_IDENTITY:-Apple Distribution: Nishant Hada (983LBM5U6B)}"
INSTALLER_IDENTITY="${INSTALLER_IDENTITY:-3rd Party Mac Developer Installer: Nishant Hada (983LBM5U6B)}"
VERSION=$(node -p "require('./src-tauri/tauri.conf.json').version")
BUNDLE_DIR="src-tauri/target/universal-apple-darwin/release/bundle/macos"
PKG="src-tauri/target/universal-apple-darwin/release/bundle/appstore/CueCard_${VERSION}_${BUILD_NUMBER}.pkg"

if [[ ! -f "$PROFILE" ]]; then
  echo "Missing $PROFILE — download the Mac App Store Connect profile for com.thisisnsh.cuecard.ios and save it there." >&2
  exit 1
fi

echo "Building CueCard $VERSION ($BUILD_NUMBER) for the Mac App Store"

# Notarization credentials are left out: App Store builds are not notarized
env -u APPLE_ID -u APPLE_PASSWORD -u APPLE_API_KEY -u APPLE_API_ISSUER -u APPLE_API_KEY_PATH \
  APPLE_SIGNING_IDENTITY="$APP_SIGNING_IDENTITY" \
  npm run tauri build -- \
    --target universal-apple-darwin \
    --config src-tauri/tauri.appstore.conf.json \
    --config "{\"bundle\":{\"macOS\":{\"bundleVersion\":\"$BUILD_NUMBER\"}}}"

mkdir -p "$(dirname "$PKG")"
xcrun productbuild --sign "$INSTALLER_IDENTITY" --component "$BUNDLE_DIR/CueCard.app" /Applications "$PKG"

echo "Package: $PKG"

if [[ "${1:-}" == "--upload" ]]; then
  xcrun altool --upload-app --type macos --file "$PKG" \
    --apiKey "$APPLE_API_KEY_ID" --apiIssuer "$APPLE_API_ISSUER"
else
  echo "Upload it with Transporter, or rerun with --upload."
fi
