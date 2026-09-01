#!/usr/bin/env bash
# Generate the Play Store upload keystore (run once, keep backups forever).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ANDROID_DIR="$ROOT/android"
KEYSTORE="$ANDROID_DIR/app/cityshop-release.keystore"
KEY_PROPS="$ANDROID_DIR/key.properties"
CREDS_FILE="$ANDROID_DIR/PLAYSTORE_SIGNING.local.txt"

if [[ -f "$KEYSTORE" ]]; then
  echo "Keystore already exists: $KEYSTORE"
  echo "Delete it first only if you are intentionally creating a new one."
  exit 1
fi

if ! command -v keytool >/dev/null 2>&1; then
  echo "keytool not found. Install JDK (Android Studio includes one)."
  exit 1
fi

# Generate a strong random password if not provided.
STORE_PASS="${PLAYSTORE_STORE_PASSWORD:-$(python3 -c "import secrets; print(secrets.token_urlsafe(18))")}"
KEY_PASS="${PLAYSTORE_KEY_PASSWORD:-$STORE_PASS}"

echo "Creating release keystore..."
keytool -genkey -v \
  -keystore "$KEYSTORE" \
  -alias cityshop \
  -keyalg RSA \
  -keysize 2048 \
  -validity 10000 \
  -storepass "$STORE_PASS" \
  -keypass "$KEY_PASS" \
  -dname "CN=CityShop, OU=Mobile, O=CityUnlock, L=Accra, ST=Greater Accra, C=GH"

cat > "$KEY_PROPS" <<EOF
storePassword=$STORE_PASS
keyPassword=$KEY_PASS
keyAlias=cityshop
storeFile=app/cityshop-release.keystore
EOF

cat > "$CREDS_FILE" <<EOF
CityShop Play Store signing credentials — BACK UP AND NEVER COMMIT TO GIT
Generated: $(date -u +"%Y-%m-%d %H:%M UTC")

Keystore file: $KEYSTORE
Key alias: cityshop
Store password: $STORE_PASS
Key password: $KEY_PASS

If you lose this file and keystore, you cannot update the app on Play Store.
Upload the keystore backup to secure storage (1Password, encrypted drive, etc.).
EOF

chmod 600 "$KEY_PROPS" "$CREDS_FILE" 2>/dev/null || true

echo ""
echo "Done."
echo "  Keystore: $KEYSTORE"
echo "  key.properties: $KEY_PROPS"
echo "  Credentials saved: $CREDS_FILE"
echo ""
echo "Next: bash scripts/build-playstore-bundle.sh"
