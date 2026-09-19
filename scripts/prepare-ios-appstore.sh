#!/usr/bin/env bash
set -euo pipefail
export PATH="/opt/homebrew/bin:/usr/bin:/bin:$PATH"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "==> Disable Swift Package Manager for Flutter plugins"
flutter config --no-enable-swift-package-manager >/dev/null || true

echo "==> flutter clean + pub get"
flutter clean
flutter pub get

echo "==> pod install (all plugins via CocoaPods)"
cd ios
pod install --repo-update
cd ..

echo "==> Done. Next: open ios/Runner.xcworkspace and Product → Archive"
echo "    Or run: flutter build ipa"
