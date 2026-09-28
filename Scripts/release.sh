#!/usr/bin/env bash
set -euo pipefail

# Builds a release and the Sparkle appcasts that installed copies poll for updates.
#
#   bash Scripts/set_version.sh 0.2.0
#   git commit -am "Release 0.2.0" && git tag v0.2.0
#   bash Scripts/release.sh --notes notes.md             # build into dist/ and review
#   bash Scripts/release.sh --notes notes.md --publish   # also push the tag and create the GitHub release
#   bash website/scripts/sync-release.sh                 # copy the zip, DMG and appcast to the website
#
# The app's SUFeedURL is appcast.xml on helloxxy.com: dist/appcast.xml points at the
# zip next to it on the website. 0.2.0 still reads releases/latest/download/appcast.xml
# on GitHub, so every GitHub release also carries dist/github/appcast.xml, which points
# at that release's own zip.

REPO="XiangXiaoYuan5254/MacPen"
APP_NAME="MacPen"
SITE_URL="https://helloxxy.com/works/macpen"
NOTES_FILE=""
PUBLISH=0
DOWNLOAD_BASE_URL=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --notes)
      NOTES_FILE="${2:-}"
      shift 2
      ;;
    --publish)
      PUBLISH=1
      shift
      ;;
    --download-base-url)
      # Only for testing the update flow against a local server.
      DOWNLOAD_BASE_URL="${2:-}"
      shift 2
      ;;
    -h|--help)
      echo "usage: $0 [--notes release-notes.md] [--publish]"
      exit 0
      ;;
    *)
      echo "unknown option: $1" >&2
      exit 2
      ;;
  esac
done

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
SIGN_UPDATE="$ROOT_DIR/.build/artifacts/sparkle/Sparkle/bin/sign_update"
cd "$ROOT_DIR"

plist_value() {
  /usr/libexec/PlistBuddy -c "Print :$1" "$ROOT_DIR/Info.plist"
}
VERSION="$(plist_value CFBundleShortVersionString)"
MIN_SYSTEM_VERSION="$(plist_value LSMinimumSystemVersion)"
TAG="v$VERSION"

if [[ -n "$NOTES_FILE" && ! -f "$NOTES_FILE" ]]; then
  echo "release notes not found: $NOTES_FILE" >&2
  exit 1
fi
if [[ -n "$NOTES_FILE" ]] && grep -q ']]>' "$NOTES_FILE"; then
  echo "release notes must not contain ']]>'" >&2
  exit 1
fi

if [[ -z "$DOWNLOAD_BASE_URL" ]]; then
  # Untracked files only matter if SwiftPM would compile or bundle them.
  if [[ -n "$(git status --porcelain --untracked-files=no)" || -n "$(git ls-files --others --exclude-standard -- Sources Assets)" ]]; then
    echo "working tree has uncommitted changes; commit them before releasing" >&2
    exit 1
  fi
  if [[ "$(git rev-parse -q --verify "refs/tags/$TAG^{commit}" || true)" != "$(git rev-parse HEAD)" ]]; then
    echo "tag $TAG must point at HEAD (Info.plist says $VERSION). Run: git tag $TAG" >&2
    exit 1
  fi
  DOWNLOAD_BASE_URL="$SITE_URL/downloads"
fi

bash "$ROOT_DIR/Scripts/package_app.sh" --configuration release >/dev/null

ARCH="$(uname -m)"
ZIP_NAME="$APP_NAME-macos-$ARCH.zip"
ZIP_PATH="$DIST_DIR/$ZIP_NAME"
DMG_PATH="$DIST_DIR/$APP_NAME-macos-$ARCH.dmg"
APPCAST_PATH="$DIST_DIR/appcast.xml"
GITHUB_APPCAST_PATH="$DIST_DIR/github/appcast.xml"

# Prints: sparkle:edSignature="..." length="..." (private key comes from the login Keychain).
SIGNATURE_ATTRIBUTES="$("$SIGN_UPDATE" "$ZIP_PATH")"

DESCRIPTION=""
if [[ -n "$NOTES_FILE" ]]; then
  DESCRIPTION="      <description sparkle:format=\"markdown\"><![CDATA[
$(cat "$NOTES_FILE")
]]></description>"
fi
PUB_DATE="$(LC_ALL=C date -u "+%a, %d %b %Y %H:%M:%S +0000")"

# write_appcast <path> <base URL of the zip>
write_appcast() {
  mkdir -p "$(dirname "$1")"
  cat > "$1" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>$APP_NAME</title>
    <item>
      <title>$APP_NAME $VERSION</title>
      <link>$SITE_URL/</link>
      <pubDate>$PUB_DATE</pubDate>
      <sparkle:version>$VERSION</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>$MIN_SYSTEM_VERSION</sparkle:minimumSystemVersion>
$DESCRIPTION
      <enclosure url="$2/$ZIP_NAME" type="application/octet-stream" $SIGNATURE_ATTRIBUTES />
    </item>
  </channel>
</rss>
EOF
  xmllint --noout "$1"
}
write_appcast "$APPCAST_PATH" "$DOWNLOAD_BASE_URL"
write_appcast "$GITHUB_APPCAST_PATH" "https://github.com/$REPO/releases/download/$TAG"

echo "$ZIP_PATH"
echo "$DMG_PATH"
echo "$APPCAST_PATH"
echo "$GITHUB_APPCAST_PATH"

if [[ "$PUBLISH" -eq 0 ]]; then
  echo "Review dist/, then rerun with --publish to push $TAG and create the GitHub release."
  exit 0
fi

LATEST_TAG="$(gh release view --repo "$REPO" --json tagName --jq .tagName 2>/dev/null || true)"
if [[ -n "$LATEST_TAG" ]]; then
  LATEST_VERSION="${LATEST_TAG#v}"
  if [[ "$(printf '%s\n%s\n' "$LATEST_VERSION" "$VERSION" | sort -V | tail -1)" != "$VERSION" || "$LATEST_VERSION" == "$VERSION" ]]; then
    echo "$VERSION is not newer than the latest release $LATEST_TAG" >&2
    exit 1
  fi
fi

git push origin "$TAG"
NOTES_ARGS=(--generate-notes)
if [[ -n "$NOTES_FILE" ]]; then
  NOTES_ARGS=(--notes-file "$NOTES_FILE")
fi
gh release create "$TAG" \
  --repo "$REPO" \
  --verify-tag \
  --title "$APP_NAME $VERSION" \
  "${NOTES_ARGS[@]}" \
  "$DMG_PATH" "$ZIP_PATH" "$GITHUB_APPCAST_PATH"
