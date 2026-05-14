#!/usr/bin/env bash
set -euo pipefail

ACCOUNT="work-screen-time-monitor"
BUILD=""
DOWNLOAD_URL=""
OUTPUT_PATH=""
RELEASE_NOTES_URL=""
SIGN_UPDATE_PATH=""
TITLE="Work Screen Time"
VERSION=""
ZIP_PATH=""

usage() {
  cat >&2 <<USAGE
Usage: $0 --version VERSION --build BUILD --zip PATH --download-url URL --release-notes-url URL --output PATH --sign-update PATH

If SPARKLE_PRIVATE_KEY is set, it is passed to sign_update through stdin.
Otherwise, sign_update uses the local Keychain account.
USAGE
}

xml_escape() {
  local value="$1"
  value="${value//&/&amp;}"
  value="${value//</&lt;}"
  value="${value//>/&gt;}"
  value="${value//\"/&quot;}"
  value="${value//\'/&apos;}"
  printf '%s' "$value"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --account)
      ACCOUNT="${2:-}"
      shift 2
      ;;
    --build)
      BUILD="${2:-}"
      shift 2
      ;;
    --download-url)
      DOWNLOAD_URL="${2:-}"
      shift 2
      ;;
    --output)
      OUTPUT_PATH="${2:-}"
      shift 2
      ;;
    --release-notes-url)
      RELEASE_NOTES_URL="${2:-}"
      shift 2
      ;;
    --sign-update)
      SIGN_UPDATE_PATH="${2:-}"
      shift 2
      ;;
    --title)
      TITLE="${2:-}"
      shift 2
      ;;
    --version)
      VERSION="${2:-}"
      shift 2
      ;;
    --zip)
      ZIP_PATH="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage
      exit 64
      ;;
  esac
done

if [[ -z "$VERSION" || -z "$BUILD" || -z "$ZIP_PATH" || -z "$DOWNLOAD_URL" || -z "$RELEASE_NOTES_URL" || -z "$OUTPUT_PATH" || -z "$SIGN_UPDATE_PATH" ]]; then
  usage
  exit 64
fi

if [[ ! -f "$ZIP_PATH" ]]; then
  echo "Zip file not found: $ZIP_PATH" >&2
  exit 1
fi

if [[ ! -x "$SIGN_UPDATE_PATH" ]]; then
  echo "sign_update not found or not executable: $SIGN_UPDATE_PATH" >&2
  exit 1
fi

if [[ -n "${SPARKLE_PRIVATE_KEY:-}" ]]; then
  SIGNATURE_OUTPUT="$(printf '%s' "$SPARKLE_PRIVATE_KEY" | "$SIGN_UPDATE_PATH" --ed-key-file - "$ZIP_PATH")"
else
  SIGNATURE_OUTPUT="$("$SIGN_UPDATE_PATH" --account "$ACCOUNT" "$ZIP_PATH")"
fi

PUB_DATE="$(LC_ALL=C TZ=UTC date '+%a, %d %b %Y %H:%M:%S +0000')"
mkdir -p "$(dirname "$OUTPUT_PATH")"

TITLE_XML="$(xml_escape "$TITLE")"
VERSION_XML="$(xml_escape "$VERSION")"
BUILD_XML="$(xml_escape "$BUILD")"
DOWNLOAD_URL_XML="$(xml_escape "$DOWNLOAD_URL")"
RELEASE_NOTES_URL_XML="$(xml_escape "$RELEASE_NOTES_URL")"

cat > "$OUTPUT_PATH" <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0"
  xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"
  xmlns:dc="http://purl.org/dc/elements/1.1/">
  <channel>
    <title>$TITLE_XML Updates</title>
    <link>https://workscreen.mrkhntr.com/releases/work-screen-time/appcast.xml</link>
    <description>Updates for $TITLE_XML.</description>
    <language>en</language>
    <item>
      <title>Version $VERSION_XML</title>
      <pubDate>$PUB_DATE</pubDate>
      <sparkle:version>$BUILD_XML</sparkle:version>
      <sparkle:shortVersionString>$VERSION_XML</sparkle:shortVersionString>
      <sparkle:releaseNotesLink>$RELEASE_NOTES_URL_XML</sparkle:releaseNotesLink>
      <enclosure url="$DOWNLOAD_URL_XML" type="application/octet-stream" $SIGNATURE_OUTPUT />
    </item>
  </channel>
</rss>
XML

echo "Wrote $OUTPUT_PATH"
