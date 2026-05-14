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
ZIP_PATH="${ZIP_PATH:-$HOME/Downloads/$APP_NAME.zip}"
CREATE_ZIP=1
APP_VERSION="${APP_VERSION:-}"
APP_BUILD="${APP_BUILD:-}"

usage() {
  cat >&2 <<USAGE
Usage: $0 [--version VERSION] [--build BUILD] [--zip PATH] [--no-zip]

Environment overrides:
  APP_VERSION  Version string for CFBundleShortVersionString
  APP_BUILD    Build number for CFBundleVersion
  ZIP_PATH     Output zip path
USAGE
}

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
require_tool plutil
require_tool ditto
require_tool install_name_tool
require_tool otool

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)
      APP_VERSION="${2:-}"
      shift 2
      ;;
    --build)
      APP_BUILD="${2:-}"
      shift 2
      ;;
    --zip)
      ZIP_PATH="${2:-}"
      shift 2
      ;;
    --no-zip)
      CREATE_ZIP=0
      shift
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

VERSION_FILE="$ROOT_DIR/VERSION"
if [[ ! -f "$VERSION_FILE" ]]; then
  echo "1.0.0" > "$VERSION_FILE"
fi

VERSION="${APP_VERSION:-$(tr -d '[:space:]' < "$VERSION_FILE")}"
if [[ -z "$VERSION" ]]; then
  VERSION="1.0.0"
fi

if [[ -n "$APP_BUILD" ]]; then
  BUILD="$APP_BUILD"
else
  BUILD="${VERSION##*.}"
  if [[ ! "$BUILD" =~ ^[0-9]+$ ]]; then
    BUILD="1"
  fi
fi

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

swift build -c release

BUILT_EXECUTABLE="$ROOT_DIR/.build/release/$APP_NAME"
if [[ ! -x "$BUILT_EXECUTABLE" ]]; then
  echo "SwiftPM reported success, but no executable was found at $BUILT_EXECUTABLE" >&2
  exit 1
fi
install -m 755 "$BUILT_EXECUTABLE" "$APP_EXECUTABLE"
if ! otool -l "$APP_EXECUTABLE" | grep -q "@loader_path/../Frameworks"; then
  install_name_tool -add_rpath "@loader_path/../Frameworks" "$APP_EXECUTABLE"
fi

SPARKLE_FRAMEWORK_SRC="$(find "$ROOT_DIR/.build/artifacts" -path "*/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework" -type d | head -n 1)"
if [[ -z "$SPARKLE_FRAMEWORK_SRC" ]]; then
  echo "Sparkle.framework was not found. Run 'swift package resolve' and try again." >&2
  exit 1
fi
ditto "$SPARKLE_FRAMEWORK_SRC" "$FRAMEWORKS_DIR/Sparkle.framework"

APP_NAME_XML="$(xml_escape "$APP_NAME")"
BUNDLE_NAME_XML="$(xml_escape "Work Screen Time")"
BUNDLE_ID_XML="$(xml_escape "app.workscreentime.WorkScreenTimeApp")"
SPARKLE_FEED_URL_XML="$(xml_escape "https://mrkhntr.com/work-screen-time-monitor/appcast.xml")"
SPARKLE_PUBLIC_KEY_XML="$(xml_escape "JP0FniXbX8CXCxFyv/Q8yGmWaRM9svMSnMXH5NhSuOo=")"

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
  <key>SUAllowsAutomaticUpdates</key>
  <true/>
  <key>SUAutomaticallyUpdate</key>
  <false/>
  <key>SUEnableAutomaticChecks</key>
  <true/>
  <key>SUFeedURL</key>
  <string>$SPARKLE_FEED_URL_XML</string>
  <key>SUPublicEDKey</key>
  <string>$SPARKLE_PUBLIC_KEY_XML</string>
  <key>SUScheduledCheckInterval</key>
  <integer>86400</integer>
  <key>SUVerifyUpdateBeforeExtraction</key>
  <true/>
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

if [[ "$CREATE_ZIP" -eq 1 ]]; then
  mkdir -p "$(dirname "$ZIP_PATH")"
  rm -f "$ZIP_PATH"

  # Create a DMG folder structure
  DMG_STAGING="$ROOT_DIR/.build/dmg_staging"
  rm -rf "$DMG_STAGING"
  mkdir -p "$DMG_STAGING"

  # Use ditto to copy the app to the staging area
  ditto "$APP_DIR" "$DMG_STAGING/$APP_NAME.app"

  # Create a symbolic link to /Applications
  ln -s /Applications "$DMG_STAGING/Applications"

  # Create a zip of the folder containing the app and the Applications link
  ditto -c -k "$DMG_STAGING" "$ZIP_PATH"

  echo "Exported to $ZIP_PATH (contains Applications shortcut)"
fi
