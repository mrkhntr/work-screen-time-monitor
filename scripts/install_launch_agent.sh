#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH="${1:-$ROOT_DIR/.build/WorkScreenTimeApp.app}"
LABEL="app.workscreentime.WorkScreenTimeApp"
LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"
LOG_DIR="$HOME/Library/Logs"
PLIST="$LAUNCH_AGENTS_DIR/$LABEL.plist"
USER_ID="$(id -u)"

usage() {
  echo "Usage: $0 [path/to/WorkScreenTimeApp.app]" >&2
}

require_tool() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Required tool not found: $1" >&2
    exit 1
  fi
}

absolute_path() {
  local path="$1"
  local dir
  local base

  if [[ "$path" != /* ]]; then
    path="$PWD/$path"
  fi

  dir="$(dirname "$path")"
  base="$(basename "$path")"
  if [[ ! -d "$dir" ]]; then
    echo "Directory not found: $dir" >&2
    exit 1
  fi

  dir="$(cd "$dir" && pwd -P)"
  printf '%s/%s' "$dir" "$base"
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

if [[ $# -gt 1 ]]; then
  usage
  exit 64
fi

require_tool launchctl
require_tool plutil

APP_PATH="$(absolute_path "$APP_PATH")"
APP_EXECUTABLE="$APP_PATH/Contents/MacOS/WorkScreenTimeApp"
INFO_PLIST="$APP_PATH/Contents/Info.plist"

if [[ ! -x "$APP_EXECUTABLE" ]]; then
  echo "App executable not found at $APP_EXECUTABLE" >&2
  echo "Run scripts/build_app.sh first, or pass the path to WorkScreenTimeApp.app." >&2
  exit 1
fi

if [[ ! -f "$INFO_PLIST" ]]; then
  echo "App Info.plist not found at $INFO_PLIST" >&2
  exit 1
fi

plutil -lint "$INFO_PLIST" >/dev/null

mkdir -p "$LAUNCH_AGENTS_DIR" "$LOG_DIR"

LABEL_XML="$(xml_escape "$LABEL")"
APP_EXECUTABLE_XML="$(xml_escape "$APP_EXECUTABLE")"
STDOUT_XML="$(xml_escape "$LOG_DIR/$LABEL.out.log")"
STDERR_XML="$(xml_escape "$LOG_DIR/$LABEL.err.log")"

cat > "$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$LABEL_XML</string>
  <key>LimitLoadToSessionType</key>
  <string>Aqua</string>
  <key>ProgramArguments</key>
  <array>
    <string>$APP_EXECUTABLE_XML</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <false/>
  <key>StandardOutPath</key>
  <string>$STDOUT_XML</string>
  <key>StandardErrorPath</key>
  <string>$STDERR_XML</string>
</dict>
</plist>
PLIST

plutil -lint "$PLIST" >/dev/null

launchctl bootout "gui/$USER_ID/$LABEL" >/dev/null 2>&1 || launchctl bootout "gui/$USER_ID" "$PLIST" >/dev/null 2>&1 || true
launchctl bootstrap "gui/$USER_ID" "$PLIST"
launchctl enable "gui/$USER_ID/$LABEL"
launchctl kickstart -k "gui/$USER_ID/$LABEL" >/dev/null 2>&1 || true

echo "Installed and started $LABEL"
echo "LaunchAgent plist: $PLIST"
echo "Executable: $APP_EXECUTABLE"
echo "Logs: $LOG_DIR/$LABEL.out.log and $LOG_DIR/$LABEL.err.log"
