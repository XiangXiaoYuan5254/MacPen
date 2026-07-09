#!/usr/bin/env bash
set -euo pipefail

APP_NAME="MacPen"
CONFIGURATION="release"
CREATE_ZIP=1
SIGN_APP=1

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
    --skip-sign)
      SIGN_APP=0
      shift
      ;;
    -h|--help)
      echo "usage: $0 [--configuration debug|release] [--no-zip] [--skip-sign]"
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

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
APP_BINARY="$MACOS_DIR/$APP_NAME"
ZIP_PATH="$DIST_DIR/$APP_NAME-macos-$(uname -m).zip"

cd "$ROOT_DIR"
swift build -c "$CONFIGURATION"
BUILD_DIR="$(swift build -c "$CONFIGURATION" --show-bin-path)"
BUILD_BINARY="$BUILD_DIR/$APP_NAME"

if [[ ! -x "$BUILD_BINARY" ]]; then
  echo "missing built binary: $BUILD_BINARY" >&2
  exit 1
fi

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp "$BUILD_BINARY" "$APP_BINARY"
cp "$ROOT_DIR/Info.plist" "$CONTENTS_DIR/Info.plist"
cp "$ROOT_DIR/Assets/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"
chmod +x "$APP_BINARY"

if [[ "$SIGN_APP" -eq 1 ]]; then
  codesign --force --deep --sign - "$APP_DIR" >/dev/null
fi

if [[ "$CREATE_ZIP" -eq 1 ]]; then
  rm -f "$ZIP_PATH"
  (cd "$DIST_DIR" && ditto -c -k --sequesterRsrc --keepParent "$APP_NAME.app" "$(basename "$ZIP_PATH")")
fi

echo "$APP_DIR"
if [[ "$CREATE_ZIP" -eq 1 ]]; then
  echo "$ZIP_PATH"
fi
