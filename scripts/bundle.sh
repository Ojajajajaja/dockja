#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)/dockja"

APP="dockja.app"
BUNDLE_ID="com.ojajajajaja.dockja"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp "$BIN" "$APP/Contents/MacOS/dockja"

# Sign the WHOLE bundle (binds Info.plist + bundle id) so macOS reads the real
# identifier. A stable, trusted identity keeps the cdhash-independent designated
# requirement constant across rebuilds, so the Accessibility grant survives them.
# Priority: explicit DOCKJA_SIGN_ID, else the first valid keychain identity
# (Apple Development / Developer ID / trusted self-signed). Ad-hoc as last resort.
SIGN_ID="${DOCKJA_SIGN_ID:-}"
if [ -z "$SIGN_ID" ]; then
    SIGN_ID="$(security find-identity -v -p codesigning | awk '/[0-9]+\) [0-9A-F]{40}/ {print $2; exit}')"
fi

if [ -n "$SIGN_ID" ] && security find-identity -v -p codesigning | grep -q "$SIGN_ID"; then
    codesign --force --sign "$SIGN_ID" --identifier "$BUNDLE_ID" "$APP"
    echo "Signed with identity: $SIGN_ID"
    echo "Accessibility grant will persist across rebuilds (re-grant once after this signature change)."
else
    codesign --force --sign - --identifier "$BUNDLE_ID" "$APP"
    echo "WARNING: no valid code-signing identity found — signed ad-hoc."
    echo "         The Accessibility grant will reset on every rebuild."
fi

echo "Built $APP"
echo "Launch:  open $APP"
