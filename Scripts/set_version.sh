#!/usr/bin/env bash
set -euo pipefail

# Sets both version keys in Info.plist. Sparkle compares CFBundleVersion, so it
# is kept identical to the user-facing CFBundleShortVersionString.

VERSION="${1:-}"
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "usage: $0 <major.minor.patch>" >&2
  exit 2
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLIST="$ROOT_DIR/Info.plist"

# sed keeps the file's formatting; PlistBuddy/plutil would rewrite the whole file.
sed -i '' -E "/<key>CFBundle(ShortVersionString|Version)<\/key>/{n;s#<string>[^<]*</string>#<string>$VERSION</string>#;}" "$PLIST"

for key in CFBundleShortVersionString CFBundleVersion; do
  value="$(/usr/libexec/PlistBuddy -c "Print :$key" "$PLIST")"
  if [[ "$value" != "$VERSION" ]]; then
    echo "failed to set $key (got $value)" >&2
    exit 1
  fi
done

echo "Info.plist version set to $VERSION"
