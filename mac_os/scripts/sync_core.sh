#!/usr/bin/env bash
# Rebuild the shared TypeScript core and vendor the bundle into the macOS app's
# resources so `swift build` embeds it (no Node dependency in the Swift build).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CORE_DIR="$ROOT_DIR/shared/core"
DEST="$ROOT_DIR/mac_os/Sources/WorkScreenTimeCore/Resources/core.js"

echo "Building shared core in $CORE_DIR"
( cd "$CORE_DIR" && npm ci --silent && npm run --silent build )

mkdir -p "$(dirname "$DEST")"
cp "$CORE_DIR/dist/core.js" "$DEST"
echo "Vendored core.js -> $DEST"
