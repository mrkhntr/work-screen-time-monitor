#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ACCOUNT="work-screen-time-monitor"
SECRET_NAME="SPARKLE_PRIVATE_KEY"
GENERATE_KEYS="$ROOT_DIR/.build/artifacts/sparkle/Sparkle/bin/generate_keys"

require_tool() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Required tool not found: $1" >&2
    exit 1
  fi
}

require_tool gh

if [[ ! -x "$GENERATE_KEYS" ]]; then
  echo "Sparkle generate_keys tool not found. Run 'swift package resolve' first." >&2
  exit 1
fi

PRIVATE_KEY_FILE="$(mktemp -u)"
cleanup() {
  rm -f "$PRIVATE_KEY_FILE"
}
trap cleanup EXIT

"$GENERATE_KEYS" --account "$ACCOUNT" -x "$PRIVATE_KEY_FILE" >/dev/null
gh secret set "$SECRET_NAME" < "$PRIVATE_KEY_FILE"

echo "Set GitHub Actions secret $SECRET_NAME from Sparkle account $ACCOUNT."
