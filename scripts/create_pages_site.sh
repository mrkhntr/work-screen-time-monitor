#!/usr/bin/env bash
set -euo pipefail

APPCAST_PATH=""
DOWNLOAD_URL=""
OUTPUT_DIR=""
RELEASE_NOTES_URL=""
VERSION=""

usage() {
  cat >&2 <<USAGE
Usage: $0 --output DIR --appcast PATH --version VERSION --download-url URL --release-notes-url URL
USAGE
}

html_escape() {
  local value="$1"
  value="${value//&/&amp;}"
  value="${value//</&lt;}"
  value="${value//>/&gt;}"
  value="${value//\"/&quot;}"
  value="${value//\'/&#39;}"
  printf '%s' "$value"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --appcast)
      APPCAST_PATH="${2:-}"
      shift 2
      ;;
    --download-url)
      DOWNLOAD_URL="${2:-}"
      shift 2
      ;;
    --output)
      OUTPUT_DIR="${2:-}"
      shift 2
      ;;
    --release-notes-url)
      RELEASE_NOTES_URL="${2:-}"
      shift 2
      ;;
    --version)
      VERSION="${2:-}"
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

if [[ -z "$OUTPUT_DIR" || -z "$APPCAST_PATH" || -z "$VERSION" || -z "$DOWNLOAD_URL" || -z "$RELEASE_NOTES_URL" ]]; then
  usage
  exit 64
fi

if [[ ! -f "$APPCAST_PATH" ]]; then
  echo "Appcast file not found: $APPCAST_PATH" >&2
  exit 1
fi

mkdir -p "$OUTPUT_DIR"
cp "$APPCAST_PATH" "$OUTPUT_DIR/appcast.xml"
touch "$OUTPUT_DIR/.nojekyll"

VERSION_HTML="$(html_escape "$VERSION")"
DOWNLOAD_URL_HTML="$(html_escape "$DOWNLOAD_URL")"
RELEASE_NOTES_URL_HTML="$(html_escape "$RELEASE_NOTES_URL")"

cat > "$OUTPUT_DIR/index.html" <<HTML
<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>Work Screen Time</title>
    <link rel="alternate" type="application/rss+xml" href="appcast.xml">
    <style>
      :root {
        color-scheme: light dark;
        --background: #101114;
        --foreground: #f6f2ea;
        --muted: #c6c0b7;
        --button: #2f7d4f;
        --button-hover: #38985f;
        --border: #343941;
      }

      * {
        box-sizing: border-box;
      }

      body {
        min-height: 100vh;
        margin: 0;
        display: grid;
        place-items: center;
        padding: 32px;
        background: var(--background);
        color: var(--foreground);
        font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
      }

      main {
        width: min(680px, 100%);
      }

      h1 {
        margin: 0;
        font-size: clamp(44px, 8vw, 84px);
        line-height: 0.92;
        letter-spacing: 0;
      }

      p {
        margin: 24px 0 0;
        color: var(--muted);
        font-size: 19px;
        line-height: 1.55;
      }

      .actions {
        display: flex;
        flex-wrap: wrap;
        align-items: center;
        gap: 14px;
        margin-top: 34px;
      }

      .button {
        display: inline-flex;
        align-items: center;
        justify-content: center;
        min-height: 48px;
        padding: 0 22px;
        border-radius: 8px;
        background: var(--button);
        color: white;
        font-weight: 700;
        text-decoration: none;
      }

      .button:hover {
        background: var(--button-hover);
      }

      .version {
        color: var(--muted);
        font-size: 15px;
      }

      .notes {
        margin-top: 36px;
        padding-top: 24px;
        border-top: 1px solid var(--border);
      }

      a {
        color: inherit;
      }
    </style>
  </head>
  <body>
    <main>
      <h1>Work Screen Time</h1>
      <p>A small macOS menu bar app that helps you stop working when the boundary you set has arrived.</p>
      <div class="actions">
        <a class="button" href="$DOWNLOAD_URL_HTML">Download for Mac</a>
        <span class="version">Version $VERSION_HTML</span>
      </div>
      <div class="notes">
        <p>After downloading, unzip the app and open it. Because this build is not Developer ID signed, macOS may ask you to right-click the app and choose Open the first time.</p>
        <p>Already installed? The app checks for updates daily. You can also use Check for Updates from the menu bar app.</p>
        <p><a href="$RELEASE_NOTES_URL_HTML">Release notes</a> · <a href="appcast.xml">Sparkle appcast</a></p>
      </div>
    </main>
  </body>
</html>
HTML

echo "Wrote GitHub Pages site to $OUTPUT_DIR"
