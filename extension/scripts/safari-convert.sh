#!/bin/bash
# Safari Web Extension Converter Script
# Converts the built extension for Safari using Xcode tools

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
SAFARI_SRC="$ROOT_DIR/dist/safari"
SAFARI_XCODE="$ROOT_DIR/dist/safari-xcode"

echo "Google Slides Tracker - Safari Converter"
echo "========================================="

# Check if xcrun is available
if ! command -v xcrun &> /dev/null; then
    echo ""
    echo "Error: xcrun not found."
    echo "Please install Xcode from the App Store and run:"
    echo "  xcode-select --install"
    exit 1
fi

# Check if Safari source exists
if [ ! -d "$SAFARI_SRC" ]; then
    echo ""
    echo "Error: Safari build not found at $SAFARI_SRC"
    echo "Please run 'npm run build' first."
    exit 1
fi

# Clean previous Xcode project
if [ -d "$SAFARI_XCODE" ]; then
    echo "Removing previous Xcode project..."
    rm -rf "$SAFARI_XCODE"
fi

echo ""
echo "Converting extension for Safari..."
echo "Source: $SAFARI_SRC"
echo "Output: $SAFARI_XCODE"
echo ""

# Run the Safari web extension converter
xcrun safari-web-extension-converter "$SAFARI_SRC" \
    --project-location "$SAFARI_XCODE" \
    --app-name "SlidesTracker" \
    --bundle-identifier "com.example.slidestracker" \
    --no-open \
    --force

if [ $? -eq 0 ]; then
    echo ""
    echo "========================================="
    echo "Safari extension project created successfully!"
    echo ""
    echo "Next steps:"
    echo "  1. Open Xcode project: open '$SAFARI_XCODE/SlidesTracker/SlidesTracker.xcodeproj'"
    echo "  2. Select your development team in Xcode"
    echo "  3. Build and run the app (Cmd+R)"
    echo "  4. Enable the extension in Safari > Preferences > Extensions"
else
    echo ""
    echo "Error: Safari conversion failed."
    echo "Please check the output above for details."
    exit 1
fi
