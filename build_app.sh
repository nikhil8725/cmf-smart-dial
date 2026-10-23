#!/usr/bin/env bash
# Automated Build Script for CMF Smart Dial (Dial Pro) on macOS
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

APP_NAME="Dial"
BUILD_DIR="$SCRIPT_DIR/build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
CONTENTS="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS/MacOS"
HELPERS_DIR="$CONTENTS/Helpers"
RESOURCES_DIR="$CONTENTS/Resources"

# Locate SDK: prefer MacOSX26.5.sdk for pure swiftc CLI compatibility without Xcode plugins
SDK_PATH="/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk"
if [ ! -d "$SDK_PATH" ]; then
    SDK_PATH="$(xcrun --show-sdk-path 2>/dev/null || echo '/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk')"
fi
MODULE_CACHE="/tmp/module-cache"
mkdir -p "$MODULE_CACHE"

echo "=================================================="
echo " Building $APP_NAME for macOS (Apple Silicon arm64)"
echo " SDK: $SDK_PATH"
echo "=================================================="

# Clean build directory
rm -rf "$BUILD_DIR"
mkdir -p "$MACOS_DIR" "$HELPERS_DIR" "$RESOURCES_DIR"

echo "==> 1/4 Compiling dial-remote helper..."
swiftc -sdk "$SDK_PATH" \
    -module-cache-path "$MODULE_CACHE" \
    -target arm64-apple-macos14.0 \
    -framework AppKit \
    -framework AVFoundation \
    -framework MediaPlayer \
    DialRemote/main.swift \
    -o "$HELPERS_DIR/dial-remote"

echo "==> 2/4 Compiling Dial main application (47 Swift modules)..."
SWIFT_FILES=$(find Dial -name "*.swift")
swiftc -sdk "$SDK_PATH" \
    -module-cache-path "$MODULE_CACHE" \
    -target arm64-apple-macos14.0 \
    -parse-as-library \
    $SWIFT_FILES \
    -o "$MACOS_DIR/$APP_NAME"

echo "==> 3/4 Assembling app bundle resources and Info.plist..."
sed -e 's/\$(EXECUTABLE_NAME)/Dial/g' \
    -e 's/\$(PRODUCT_BUNDLE_IDENTIFIER)/com.art.dial/g' \
    -e 's/\$(PRODUCT_NAME)/Dial/g' \
    -e 's/\$(DEVELOPMENT_LANGUAGE)/en/g' \
    -e 's/\$(MARKETING_VERSION)/1.0/g' \
    -e 's/\$(CURRENT_PROJECT_VERSION)/1/g' \
    Dial/Info.plist > "$CONTENTS/Info.plist"

# Ensure PkgInfo is present
printf "APPL????" > "$CONTENTS/PkgInfo"

# Copy icons and asset catalog
if [ -f "Dial/AppIcon.icns" ]; then
    cp "Dial/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"
fi
if [ -d "/Applications/Dial.app/Contents/Resources" ]; then
    cp -R /Applications/Dial.app/Contents/Resources/Assets.car "$RESOURCES_DIR/" 2>/dev/null || true
fi

# Prevent Spotlight from indexing local build directory so only /Applications/Dial.app appears
touch "$BUILD_DIR/.noindex"

# Ad-hoc code sign so macOS Accessibility permissions work reliably
echo "==> 4/4 Ad-hoc code signing app bundle..."
codesign -s - --force --deep "$APP_BUNDLE" 2>/dev/null || true

echo "=================================================="
echo "✅ Build Complete: $APP_BUNDLE"
echo "=================================================="
