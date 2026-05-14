#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="WorkScreenTimeApp"
APP_DIR="$ROOT_DIR/.build/$APP_NAME.app"
STAGING_APP_DIR="$ROOT_DIR/.build/$APP_NAME.app.tmp.$$"
CONTENTS_DIR="$STAGING_APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
FRAMEWORKS_DIR="$CONTENTS_DIR/Frameworks"
DIRECT_DIR="$ROOT_DIR/.build/direct"
APP_EXECUTABLE="$MACOS_DIR/$APP_NAME"
INFO_PLIST="$CONTENTS_DIR/Info.plist"

require_tool() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Required tool not found: $1" >&2
    exit 1
  fi
}

cleanup() {
  rm -rf "$STAGING_APP_DIR"
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

require_tool swift
require_tool swiftc
require_tool plutil

# Auto-increment build number
VERSION_FILE="$ROOT_DIR/VERSION"
if [[ ! -f "$VERSION_FILE" ]]; then
  echo "1" > "$VERSION_FILE"
fi
BUILD=$(( $(tr -d '[:space:]' < "$VERSION_FILE") + 1 ))
echo "$BUILD" > "$VERSION_FILE"
VERSION="1.0.$BUILD"
echo "Version: $VERSION (build $BUILD)"

if ! swift --version >/dev/null; then
  echo "Swift is installed but not usable. If the output mentions the Xcode license, run:" >&2
  echo "  sudo xcodebuild -license" >&2
  echo "Then verify the selected toolchain with:" >&2
  echo "  xcode-select -p" >&2
  echo "  swift --version" >&2
  exit 1
fi

trap cleanup EXIT

rm -rf "$STAGING_APP_DIR" "$DIRECT_DIR"
mkdir -p "$MACOS_DIR" "$FRAMEWORKS_DIR" "$CONTENTS_DIR/Resources"

cd "$ROOT_DIR"

if swift build -c release; then
  BUILT_EXECUTABLE="$ROOT_DIR/.build/release/$APP_NAME"
  if [[ ! -x "$BUILT_EXECUTABLE" ]]; then
    echo "SwiftPM reported success, but no executable was found at $BUILT_EXECUTABLE" >&2
    exit 1
  fi
  install -m 755 "$BUILT_EXECUTABLE" "$APP_EXECUTABLE"
else
  echo "SwiftPM build failed; attempting direct swiftc build..." >&2
  mkdir -p "$DIRECT_DIR"

  CORE_SOURCES=("$ROOT_DIR"/Sources/WorkScreenTimeCore/*.swift)
  APP_SOURCES=("$ROOT_DIR"/Sources/WorkScreenTimeApp/*.swift)
  if [[ ! -e "${CORE_SOURCES[0]}" || ! -e "${APP_SOURCES[0]}" ]]; then
    echo "Source files are missing from Sources/WorkScreenTimeCore or Sources/WorkScreenTimeApp." >&2
    exit 1
  fi

  swiftc -O \
    -emit-library \
    -emit-module \
    -module-name WorkScreenTimeCore \
    -Xlinker -install_name \
    -Xlinker "@rpath/libWorkScreenTimeCore.dylib" \
    "${CORE_SOURCES[@]}" \
    -o "$DIRECT_DIR/libWorkScreenTimeCore.dylib"

  swiftc -O \
    -I "$DIRECT_DIR" \
    -L "$DIRECT_DIR" \
    -lWorkScreenTimeCore \
    -Xlinker -rpath \
    -Xlinker "@executable_path/../Frameworks" \
    "${APP_SOURCES[@]}" \
    -o "$APP_EXECUTABLE"

  cp "$DIRECT_DIR/libWorkScreenTimeCore.dylib" "$FRAMEWORKS_DIR/"
fi

APP_NAME_XML="$(xml_escape "$APP_NAME")"
BUNDLE_NAME_XML="$(xml_escape "Work Screen Time")"
BUNDLE_ID_XML="$(xml_escape "app.workscreentime.WorkScreenTimeApp")"

cat > "$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDisplayName</key>
  <string>$BUNDLE_NAME_XML</string>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME_XML</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID_XML</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>$BUNDLE_NAME_XML</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$VERSION</string>
  <key>CFBundleVersion</key>
  <string>$BUILD</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHumanReadableCopyright</key>
  <string>Local utility</string>
</dict>
</plist>
PLIST

plutil -lint "$INFO_PLIST" >/dev/null
chmod +x "$APP_EXECUTABLE"

rm -rf "$APP_DIR"
mv "$STAGING_APP_DIR" "$APP_DIR"
trap - EXIT

codesign --force --deep --sign - "$APP_DIR"

echo "Built $APP_DIR"

ZIP_PATH="$HOME/Downloads/$APP_NAME.zip"
rm -f "$ZIP_PATH"
(cd "$(dirname "$APP_DIR")" && zip -r "$ZIP_PATH" "$(basename "$APP_DIR")")
echo "Exported to $ZIP_PATH"
