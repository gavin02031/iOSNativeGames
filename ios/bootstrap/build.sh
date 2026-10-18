#!/usr/bin/env bash
# Build only the game-free iPhone shell. It does not package Nintendo code,
# RomFS, decryption keys, signed guest modules, or the native TotK runtime.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT="${IOS_BOOTSTRAP_OUT:-$ROOT/out/ios}"
APP="$OUT/TOTKBootstrap.app"
SOURCE="$ROOT/ios/app/Sources"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "ERROR: building an iOS app requires macOS and Xcode's iPhoneOS SDK." >&2
  echo "Use the GitHub Actions workflow on a macOS runner from Windows." >&2
  exit 2
fi

SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
CLANG="$(xcrun --sdk iphoneos --find clang)"
if [[ ! -d "$SDK" || ! -x "$CLANG" ]]; then
  echo "ERROR: iPhoneOS SDK/clang unavailable; select a full Xcode installation." >&2
  exit 2
fi

rm -rf "$APP"
mkdir -p "$APP"
cp "$ROOT/ios/app/Info.plist" "$APP/Info.plist"

"$CLANG" \
  -arch arm64 \
  -isysroot "$SDK" \
  -miphoneos-version-min=17.0 \
  -O2 -std=gnu11 -fobjc-arc -fblocks \
  -Wall -Wextra -Wno-deprecated-declarations \
  "$SOURCE/main.m" "$SOURCE/touch_controls.m" \
  -framework Foundation -framework UIKit \
  -framework QuartzCore -framework Metal -framework GameController \
  -o "$APP/TOTKBootstrap"

plutil -lint "$APP/Info.plist"
echo "Bootstrap app: $APP"
echo "This is an UNSIGNED Metal+touch test shell, not a playable TotK IPA."
echo "Game files and keys must not be uploaded to the repository or CI."
