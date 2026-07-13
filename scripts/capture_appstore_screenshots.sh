#!/bin/zsh
# Captures App Store listing screenshots by running AppStoreScreenshotTests on
# each required device class, in light and dark, and exporting the attachments
# as PNGs. See docs/appstore/SCREENSHOT_SHOTLIST.md for the shot definitions.
#
# Usage: scripts/capture_appstore_screenshots.sh [output-dir]
# Output: <output-dir>/<device-slug>/<appearance>/<shot>.png
set -euo pipefail

cd "$(dirname "$0")/.."

OUT="${1:-docs/appstore/screenshots}"
DERIVED="$HOME/Library/Developer/Xcode/DerivedData/TwoOfUs-local"
DEVICES=("iPhone 17 Pro Max" "iPad Pro 13-inch (M5)")
APPEARANCES=(light dark)

make project

for device in "${DEVICES[@]}"; do
  slug=$(echo "$device" | tr '[:upper:] ()' '[:lower:]-' | tr -s '-' | sed 's/-$//')
  xcrun simctl shutdown all 2>/dev/null || true
  xcrun simctl boot "$device"
  # Clean marketing status bar (9:41, full battery/signal).
  xcrun simctl status_bar "$device" override \
    --time "9:41" --batteryLevel 100 --batteryState charged \
    --cellularBars 4 --wifiBars 3 --operatorName ""

  for appearance in "${APPEARANCES[@]}"; do
    echo "=== $device / $appearance ==="
    # Fresh install per pass: the capture test logs a feed, so a persistent
    # store accumulates one extra feed per run and the sizes drift apart.
    xcrun simctl uninstall "$device" com.taylorseale.twoofus 2>/dev/null || true
    xcrun simctl ui "$device" appearance "$appearance"
    result="$DERIVED/screenshots-$slug-$appearance.xcresult"
    rm -rf "$result"
    xcodebuild test -project TwoOfUs.xcodeproj -scheme TwoOfUsUITests \
      -destination "platform=iOS Simulator,name=$device" \
      -derivedDataPath "$DERIVED" \
      -resultBundlePath "$result" \
      -only-testing:TwoOfUsUITests/AppStoreScreenshotTests \
      -quiet

    dest="$OUT/$slug/$appearance"
    rm -rf "$dest" && mkdir -p "$dest"
    tmp=$(mktemp -d)
    xcrun xcresulttool export attachments --path "$result" --output-path "$tmp"
    # manifest.json maps exported file names back to attachment names.
    python3 - "$tmp" "$dest" <<'PY'
import json, shutil, sys, pathlib
tmp, dest = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
manifest = json.loads((tmp / "manifest.json").read_text())
for test in manifest:
    for att in test.get("attachments", []):
        name = att.get("suggestedHumanReadableName") or att["exportedFileName"]
        if not name.lower().endswith(".png"):
            name += ".png"
        shutil.copy(tmp / att["exportedFileName"], dest / name)
        print(f"  {dest / name}")
PY
    rm -rf "$tmp"
  done
done

xcrun simctl status_bar "$device" clear 2>/dev/null || true
echo "Done → $OUT"
