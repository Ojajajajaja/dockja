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
# identifier. Prefer a stable self-signed identity so the Accessibility grant
# survives rebuilds — ad-hoc signatures get a new cdhash every build, which
# invalidates the TCC grant and forces re-granting each time.
SIGN_ID="${DOCKJA_SIGN_ID:-dockja-dev}"
if security find-identity -v -p codesigning 2>/dev/null | grep -q "$SIGN_ID"; then
    codesign --force --sign "$SIGN_ID" --identifier "$BUNDLE_ID" "$APP"
    echo "Signed with stable identity '$SIGN_ID' — Accessibility grant will persist across rebuilds."
else
    codesign --force --sign - --identifier "$BUNDLE_ID" "$APP"
    echo "WARNING: no '$SIGN_ID' code-signing identity found — signed ad-hoc."
    echo "         The Accessibility grant will reset on every rebuild."
    echo "         Run ./scripts/dev-cert.sh once to create a stable identity."
fi

echo "Built $APP"
echo "Launch:  open $APP"
