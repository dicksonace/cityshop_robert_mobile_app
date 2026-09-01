#!/usr/bin/env bash
# Build a signed Android App Bundle (.aab) for Google Play upload.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ANDROID_DIR="$ROOT/android"
KEY_PROPS="$ANDROID_DIR/key.properties"
KEYSTORE="$ANDROID_DIR/app/cityshop-release.keystore"
OUT_DIR="$ROOT/build/playstore"
AAB_SRC="$ROOT/build/app/outputs/bundle/release/app-release.aab"

cd "$ROOT"

if [[ ! -f "$KEY_PROPS" ]] || [[ ! -f "$KEYSTORE" ]]; then
  echo "Release signing not set up."
  echo "Run first: bash scripts/generate-release-keystore.sh"
  exit 1
fi

if [[ -z "${JAVA_HOME:-}" ]] && [[ -d "/Applications/Android Studio.app/Contents/jbr/Contents/Home" ]]; then
  export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
  export PATH="$JAVA_HOME/bin:$PATH"
fi

VERSION="$(grep '^version:' pubspec.yaml | sed 's/version: //')"
BUILD_NAME="${VERSION%%+*}"
BUILD_NUMBER="${VERSION#*+}"

echo "Building CityShop $VERSION (signed release AAB)..."
flutter pub get
flutter build appbundle --release \
  --build-name="$BUILD_NAME" \
  --build-number="$BUILD_NUMBER"

mkdir -p "$OUT_DIR"
DEST="$OUT_DIR/CityShop-${BUILD_NAME}-${BUILD_NUMBER}.aab"
cp -f "$AAB_SRC" "$DEST"

echo ""
echo "Play Store upload file ready:"
echo "  $DEST"
echo "  $(ls -lh "$DEST" | awk '{print $5}')"
echo ""
echo "Upload this .aab in Google Play Console → Testing → Internal testing → Create release."
