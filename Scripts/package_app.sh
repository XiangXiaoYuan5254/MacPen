#!/usr/bin/env bash
set -euo pipefail

APP_NAME="MacPen"
CONFIGURATION="release"
CREATE_ZIP=1
CREATE_DMG=1
SIGN_APP=1
NOTARIZE=0
# Developer ID certificate in the login Keychain. "-" signs ad hoc, for local builds only.
SIGN_IDENTITY="${MACPEN_SIGN_IDENTITY:-Developer ID Application: Li Ming wang (46AL7LQ9T8)}"
# Notarization credentials saved with: xcrun notarytool store-credentials helloxxy-notary
NOTARY_PROFILE="${MACPEN_NOTARY_PROFILE:-helloxxy-notary}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --configuration)
      CONFIGURATION="${2:-}"
      shift 2
      ;;
    --no-zip)
      CREATE_ZIP=0
      shift
      ;;
    --no-dmg)
      CREATE_DMG=0
      shift
      ;;
    --skip-sign)
      SIGN_APP=0
      shift
      ;;
    --notarize)
      NOTARIZE=1
      shift
      ;;
    -h|--help)
      echo "usage: $0 [--configuration debug|release] [--no-zip] [--no-dmg] [--skip-sign] [--notarize]"
      exit 0
      ;;
    *)
      echo "unknown option: $1" >&2
      exit 2
      ;;
  esac
done

if [[ "$CONFIGURATION" != "debug" && "$CONFIGURATION" != "release" ]]; then
  echo "--configuration must be debug or release" >&2
  exit 2
fi
if [[ "$NOTARIZE" -eq 1 && ( "$SIGN_APP" -eq 0 || "$SIGN_IDENTITY" == "-" ) ]]; then
  echo "--notarize needs a Developer ID signature" >&2
  exit 2
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
FRAMEWORKS_DIR="$CONTENTS_DIR/Frameworks"
APP_BINARY="$MACOS_DIR/$APP_NAME"
ZIP_PATH="$DIST_DIR/$APP_NAME-macos-$(uname -m).zip"
DMG_PATH="$DIST_DIR/$APP_NAME-macos-$(uname -m).dmg"

cd "$ROOT_DIR"

if [[ "$CREATE_DMG" -eq 1 ]] && ! command -v uvx >/dev/null; then
  echo "building the DMG needs uv: brew install uv (or pass --no-dmg)" >&2
  exit 1
fi

# Info.plist is the single source of truth for the version. Sparkle compares
# CFBundleVersion, so it must always match the user-facing version string.
plist_value() {
  /usr/libexec/PlistBuddy -c "Print :$1" "$ROOT_DIR/Info.plist"
}
VERSION="$(plist_value CFBundleShortVersionString)"
BUILD_VERSION="$(plist_value CFBundleVersion)"
if [[ "$VERSION" != "$BUILD_VERSION" ]]; then
  echo "Info.plist version mismatch: CFBundleShortVersionString=$VERSION, CFBundleVersion=$BUILD_VERSION" >&2
  echo "run: bash Scripts/set_version.sh <version>" >&2
  exit 1
fi
for tag in $(git tag --list 'v*' --points-at HEAD 2>/dev/null); do
  if [[ "$tag" != "v$VERSION" ]]; then
    echo "HEAD is tagged $tag but Info.plist says $VERSION" >&2
    exit 1
  fi
done

swift build -c "$CONFIGURATION"
BUILD_DIR="$(swift build -c "$CONFIGURATION" --show-bin-path)"
BUILD_BINARY="$BUILD_DIR/$APP_NAME"

if [[ ! -x "$BUILD_BINARY" ]]; then
  echo "missing built binary: $BUILD_BINARY" >&2
  exit 1
fi

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$FRAMEWORKS_DIR"
cp "$BUILD_BINARY" "$APP_BINARY"
cp "$ROOT_DIR/Info.plist" "$CONTENTS_DIR/Info.plist"
cp "$ROOT_DIR/Assets/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"
ditto "$BUILD_DIR/Sparkle.framework" "$FRAMEWORKS_DIR/Sparkle.framework"
chmod +x "$APP_BINARY"

# notarize <file to upload> <file to staple the ticket to>
notarize() {
  local result
  result="$(xcrun notarytool submit "$1" --keychain-profile "$NOTARY_PROFILE" --wait --output-format json)"
  if [[ "$(plutil -extract status raw -o - - <<<"$result")" != "Accepted" ]]; then
    echo "notarization of $(basename "$1") failed: $result" >&2
    echo "see why with: xcrun notarytool log <id> --keychain-profile $NOTARY_PROFILE" >&2
    exit 1
  fi
  xcrun stapler staple -q "$2"
}

if [[ "$SIGN_APP" -eq 1 ]]; then
  # Sign inside out. Sparkle.framework ships signed ad hoc, so each of its executables gets the
  # app's certificate and the hardened runtime too, or notarization rejects it. No --deep: it
  # would drop the Downloader XPC service's entitlements.
  SIGN_ARGS=(--force --sign "$SIGN_IDENTITY")
  if [[ "$SIGN_IDENTITY" != "-" ]]; then
    SIGN_ARGS+=(--options runtime --timestamp)
  fi
  SPARKLE_DIR="$FRAMEWORKS_DIR/Sparkle.framework/Versions/B"
  codesign "${SIGN_ARGS[@]}" "$SPARKLE_DIR/XPCServices/Installer.xpc"
  codesign "${SIGN_ARGS[@]}" --preserve-metadata=entitlements "$SPARKLE_DIR/XPCServices/Downloader.xpc"
  codesign "${SIGN_ARGS[@]}" "$SPARKLE_DIR/Autoupdate"
  codesign "${SIGN_ARGS[@]}" "$SPARKLE_DIR/Updater.app"
  codesign "${SIGN_ARGS[@]}" "$FRAMEWORKS_DIR/Sparkle.framework"
  codesign "${SIGN_ARGS[@]}" "$APP_DIR"
  codesign --verify --deep --strict "$APP_DIR"
fi

if [[ "$NOTARIZE" -eq 1 ]]; then
  # The ticket goes into the app itself, so the zip, the DMG and Sparkle updates all carry it.
  NOTARY_ZIP="$DIST_DIR/.notarize-$APP_NAME.zip"
  rm -f "$NOTARY_ZIP"
  ditto -c -k --keepParent "$APP_DIR" "$NOTARY_ZIP"
  notarize "$NOTARY_ZIP" "$APP_DIR"
  rm -f "$NOTARY_ZIP"
  # This Mac may have Gatekeeper turned off, which makes spctl accept anything; only the source counts.
  spctl -a -vv -t exec "$APP_DIR" 2>&1 | grep -q "source=Notarized Developer ID" || {
    echo "$APP_DIR is not notarized" >&2
    exit 1
  }
fi

if [[ "$CREATE_ZIP" -eq 1 ]]; then
  rm -f "$ZIP_PATH"
  (cd "$DIST_DIR" && ditto -c -k --sequesterRsrc --keepParent "$APP_NAME.app" "$(basename "$ZIP_PATH")")
fi

if [[ "$CREATE_DMG" -eq 1 ]]; then
  # Laid out like 页间's installer, with an arrow from MacPen to the Applications shortcut
  # (see Scripts/dmg/). dmgbuild runs through uv and must be 1.6.7 or newer: older versions write
  # a background bookmark that makes Finder skip the background picture.
  DMG_WORK_DIR="$ROOT_DIR/.build/dmg"
  swift "$ROOT_DIR/Scripts/dmg/background.swift" "$DMG_WORK_DIR"
  rm -f "$DMG_PATH"
  uvx --python 3.12 --from dmgbuild==1.6.7 dmgbuild -s "$ROOT_DIR/Scripts/dmg/settings.py" \
    -D app="$APP_DIR" \
    -D readme="$ROOT_DIR/Scripts/dmg/安装说明.txt" \
    -D background="$DMG_WORK_DIR/background.png" \
    -D icon="$RESOURCES_DIR/AppIcon.icns" \
    "$APP_NAME" "$DMG_PATH" >/dev/null
  if [[ "$SIGN_APP" -eq 1 && "$SIGN_IDENTITY" != "-" ]]; then
    codesign --force --sign "$SIGN_IDENTITY" --timestamp "$DMG_PATH"
  fi
  if [[ "$NOTARIZE" -eq 1 ]]; then
    notarize "$DMG_PATH" "$DMG_PATH"
  fi
fi

echo "$APP_DIR"
if [[ "$CREATE_ZIP" -eq 1 ]]; then
  echo "$ZIP_PATH"
fi
if [[ "$CREATE_DMG" -eq 1 ]]; then
  echo "$DMG_PATH"
fi
