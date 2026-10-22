#!/bin/zsh
# Builds a release DMG of Dial into dist/.
#
#   Scripts/release.sh
#
# Signs with the local "Doey Local" certificate by default: fine for your own
# Macs. To ship to other people, sign with Developer ID and notarise:
#
#   DIAL_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
#   DIAL_NOTARY_PROFILE=dial \
#   Scripts/release.sh
#
# where "dial" is a profile saved once with
#   xcrun notarytool store-credentials dial --apple-id you@example.com --team-id TEAMID
set -euo pipefail

cd "$(dirname "$0")/.."
IDENTITY="${DIAL_SIGN_IDENTITY:-Doey Local}"
NOTARY_PROFILE="${DIAL_NOTARY_PROFILE:-}"
DERIVED=build/release
APP="$DERIVED/Build/Products/Release/Dial.app"

step() { print -P "%F{cyan}==>%f $1"; }

step "Generating the project"
xcodegen --quiet

SIGN_FLAGS=()
if [[ -n "$NOTARY_PROFILE" ]]; then
  # Notarisation needs a secure timestamp on every signature.
  SIGN_FLAGS=(OTHER_CODE_SIGN_FLAGS="--timestamp")
fi

step "Building Release, signed with \"$IDENTITY\""
# Any Mac: a universal build for Apple silicon and Intel.
xcodebuild -scheme Dial -configuration Release -derivedDataPath "$DERIVED" \
  -destination "generic/platform=macOS" \
  CODE_SIGN_IDENTITY="$IDENTITY" "${SIGN_FLAGS[@]}" clean build -quiet

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")
BUILD=$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" "$APP/Contents/Info.plist")

step "Checking the signature of Dial $VERSION ($BUILD)"
codesign --verify --deep --strict --verbose=1 "$APP"
codesign -dv "$APP" 2>&1 | grep -E "Authority|Runtime|Identifier=" || true

notarise() {
  step "Notarising $1"
  xcrun notarytool submit "$1" --keychain-profile "$NOTARY_PROFILE" --wait
}

if [[ -n "$NOTARY_PROFILE" ]]; then
  ZIP="$DERIVED/Dial.zip"
  ditto -c -k --keepParent "$APP" "$ZIP"
  notarise "$ZIP"
  xcrun stapler staple "$APP"
fi

step "Making the disk image"
mkdir -p dist
STAGING="$DERIVED/dmg"
rm -rf "$STAGING"
mkdir -p "$STAGING"
ditto "$APP" "$STAGING/Dial.app"
ln -s /Applications "$STAGING/Applications"
DMG="dist/Dial-$VERSION.dmg"
rm -f "$DMG"
hdiutil create -volname "Dial $VERSION" -srcfolder "$STAGING" -ov -format UDZO "$DMG" -quiet
codesign --sign "$IDENTITY" "${SIGN_FLAGS[@]/OTHER_CODE_SIGN_FLAGS=/}" "$DMG"

if [[ -n "$NOTARY_PROFILE" ]]; then
  notarise "$DMG"
  xcrun stapler staple "$DMG"
  spctl --assess --type open --context context:primary-signature --verbose "$DMG"
fi

step "Done: $DMG"
