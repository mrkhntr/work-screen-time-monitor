#!/usr/bin/env bash
set -euo pipefail

VERSION="$1"
TAG_NAME="$2"
OUTPUT_FILE="$3"

BODY=$(gh release view "$TAG_NAME" --json body --jq '.body' || echo "See GitHub for release notes.")
HTML_CONTENT=$(gh api -X POST /markdown -f text="$BODY" --header "Accept: application/vnd.github.v3+json" || echo "<p>Could not fetch release notes.</p>")

cat <<HTML > "$OUTPUT_FILE"
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <title>Release Notes: Work Screen Time $VERSION</title>
  <style>
    body {
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
      font-size: 13px;
      line-height: 1.5;
      color: var(--textColor, #333);
      padding: 16px;
      background: var(--backgroundColor, #fff);
      word-wrap: break-word;
    }
    @media (prefers-color-scheme: dark) {
      body {
        --textColor: #ccc;
        --backgroundColor: #1e1e1e;
      }
      a { color: #58a6ff; }
      h1, h2, h3, h4, h5, h6 { color: #eee; }
    }
    a { color: #0366d6; text-decoration: none; }
    a:hover { text-decoration: underline; }
    h1, h2, h3, h4, h5, h6 { margin-top: 24px; margin-bottom: 16px; font-weight: 600; line-height: 1.25; }
    p { margin-top: 0; margin-bottom: 16px; }
    ul, ol { margin-top: 0; margin-bottom: 16px; padding-left: 2em; }
    code { font-family: ui-monospace, SFMono-Regular, SF Mono, Menlo, Consolas, Liberation Mono, monospace; padding: 0.2em 0.4em; margin: 0; font-size: 85%; background-color: rgba(175,184,193,0.2); border-radius: 6px; }
  </style>
</head>
<body>
  <h2>What's new in v$VERSION</h2>
  $HTML_CONTENT
</body>
</html>
HTML

echo "Generated $OUTPUT_FILE"
