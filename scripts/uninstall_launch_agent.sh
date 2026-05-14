#!/usr/bin/env bash
set -euo pipefail

LABEL="app.workscreentime.WorkScreenTimeApp"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
USER_ID="$(id -u)"

if command -v launchctl >/dev/null 2>&1; then
  launchctl bootout "gui/$USER_ID/$LABEL" >/dev/null 2>&1 || launchctl bootout "gui/$USER_ID" "$PLIST" >/dev/null 2>&1 || true
fi

if [[ -e "$PLIST" ]]; then
  rm -f "$PLIST"
  echo "Removed $PLIST"
fi

echo "Uninstalled $LABEL"
