#!/usr/bin/env bash
set -euo pipefail

APP_PATH=$(python3 - <<'PY'
from pathlib import Path
matches = sorted(Path('.build/DerivedData/Build/Products/Debug-iphonesimulator').glob('*.app'))
if not matches:
    raise SystemExit('Built simulator app not found')
print(matches[0])
PY
)

RUNTIME_ID=$(xcrun simctl list runtimes available --json | python3 -c '
import json, re, sys
items = [item for item in json.load(sys.stdin)["runtimes"] if item.get("isAvailable") and item.get("name", "").startswith("iOS ")]
if not items:
    raise SystemExit("No available iOS runtime")
def version(item):
    return tuple(int(value) for value in re.findall(r"\d+", item.get("version", "0")))
print(max(items, key=version)["identifier"])
')

DEVICE_TYPE_ID=$(xcrun simctl list devicetypes --json | python3 -c '
import json, sys
items = json.load(sys.stdin)["devicetypes"]
preferences = ("iPhone 16 Pro", "iPhone 17 Pro", "iPhone 15 Pro")
for preferred in preferences:
    match = next((item for item in items if item["name"] == preferred), None)
    if match:
        print(match["identifier"])
        break
else:
    candidates = [item for item in items if "iPhone" in item["name"] and "Pro" in item["name"] and "Max" not in item["name"]]
    if not candidates:
        candidates = [item for item in items if "iPhone" in item["name"]]
    if not candidates:
        raise SystemExit("No available iPhone device type")
    print(candidates[-1]["identifier"])
')

UDID=$(xcrun simctl create 'WHOX Visual QA' "$DEVICE_TYPE_ID" "$RUNTIME_ID")
cleanup() {
    xcrun simctl shutdown "$UDID" >/dev/null 2>&1 || true
    xcrun simctl delete "$UDID" >/dev/null 2>&1 || true
}
trap cleanup EXIT

xcrun simctl boot "$UDID"
xcrun simctl bootstatus "$UDID" -b
defaults write com.apple.iphonesimulator ConnectHardwareKeyboard -bool false >/dev/null 2>&1 || true
xcrun simctl install "$UDID" "$APP_PATH"
xcrun simctl status_bar "$UDID" override --time '9:41' --batteryState charged --batteryLevel 100 >/dev/null 2>&1 || true
mkdir -p .build/screenshots

for appearance in light dark; do
    xcrun simctl ui "$UDID" appearance "$appearance"
    xcrun simctl terminate "$UDID" com.whox.whoxos >/dev/null 2>&1 || true
    xcrun simctl launch "$UDID" com.whox.whoxos
    sleep 3
    xcrun simctl io "$UDID" screenshot --type=png ".build/screenshots/login-${appearance}.png"

    xcrun simctl terminate "$UDID" com.whox.whoxos >/dev/null 2>&1 || true
    xcrun simctl launch "$UDID" com.whox.whoxos --visual-review-chat-empty
    sleep 2
    xcrun simctl io "$UDID" screenshot --type=png ".build/screenshots/chat-empty-${appearance}.png"

    xcrun simctl terminate "$UDID" com.whox.whoxos >/dev/null 2>&1 || true
    xcrun simctl launch "$UDID" com.whox.whoxos --visual-review-composer-typed
    sleep 3
    xcrun simctl io "$UDID" screenshot --type=png ".build/screenshots/composer-typed-${appearance}.png"

    xcrun simctl terminate "$UDID" com.whox.whoxos >/dev/null 2>&1 || true
    xcrun simctl launch "$UDID" com.whox.whoxos --visual-review-directory
    sleep 2
    xcrun simctl io "$UDID" screenshot --type=png ".build/screenshots/directory-${appearance}.png"

    xcrun simctl terminate "$UDID" com.whox.whoxos >/dev/null 2>&1 || true
    xcrun simctl launch "$UDID" com.whox.whoxos --visual-review-chat
    sleep 2
    xcrun simctl io "$UDID" screenshot --type=png ".build/screenshots/chat-${appearance}.png"

    xcrun simctl terminate "$UDID" com.whox.whoxos >/dev/null 2>&1 || true
    xcrun simctl launch "$UDID" com.whox.whoxos --visual-review-settings
    sleep 2
    xcrun simctl io "$UDID" screenshot --type=png ".build/screenshots/settings-${appearance}.png"
done

sips -g pixelWidth -g pixelHeight .build/screenshots/*.png
