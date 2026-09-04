#!/usr/bin/env bash
# Build a signed iOS archive (.ipa) for App Store / TestFlight upload.
# Requires: Xcode, Apple Developer account ($99/yr), signing configured in Xcode.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT_DIR="$ROOT/build/appstore"
TEAM_ID="${APPLE_TEAM_ID:-}"

cd "$ROOT"

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "Xcode is required. Install from the Mac App Store."
  exit 1
fi

VERSION="$(grep '^version:' pubspec.yaml | sed 's/version: //')"
BUILD_NAME="${VERSION%%+*}"
BUILD_NUMBER="${VERSION#*+}"

echo "Building CityShop iOS $VERSION for App Store..."
flutter pub get

BUILD_ARGS=(
  --release
  --build-name="$BUILD_NAME"
  --build-number="$BUILD_NUMBER"
)

if [[ -n "$TEAM_ID" ]]; then
  BUILD_ARGS+=(--export-options-plist="$ROOT/ios/ExportOptions.plist")
  echo "Using Apple Team ID: $TEAM_ID"
fi

flutter build ipa "${BUILD_ARGS[@]}"

mkdir -p "$OUT_DIR"
IPA_SRC="$(ls -t "$ROOT/build/ios/ipa/"*.ipa 2>/dev/null | head -1 || true)"
if [[ -n "$IPA_SRC" ]]; then
  DEST="$OUT_DIR/CityShop-${BUILD_NAME}-${BUILD_NUMBER}.ipa"
  cp -f "$IPA_SRC" "$DEST"
  echo ""
  echo "App Store upload file ready:"
  echo "  $DEST"
  echo "  $(ls -lh "$DEST" | awk '{print $5}')"
  echo ""
  echo "Upload with Transporter app or: xcrun altool --upload-app -f \"$DEST\""
else
  echo ""
  echo "IPA build finished. Check: build/ios/ipa/"
  echo "If signing failed, open ios/Runner.xcworkspace in Xcode and set your Team under Signing."
fi
