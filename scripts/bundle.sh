#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

APP="build/Mac Max.app"
BINARY=".build/release/MacMax"

if [ ! -x "$BINARY" ]; then
    echo "missing $BINARY — run 'swift build -c release' first" >&2
    exit 1
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BINARY" "$APP/Contents/MacOS/MacMax"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>            <string>Mac Max</string>
    <key>CFBundleDisplayName</key>     <string>Mac Max</string>
    <key>CFBundleIdentifier</key>      <string>com.nielsvaes.MacMax</string>
    <key>CFBundleExecutable</key>      <string>MacMax</string>
    <key>CFBundlePackageType</key>     <string>APPL</string>
    <key>CFBundleShortVersionString</key> <string>1.0</string>
    <key>CFBundleVersion</key>         <string>1</string>
    <key>LSMinimumSystemVersion</key>  <string>14.0</string>
    <key>LSUIElement</key>             <true/>
    <key>NSHumanReadableCopyright</key><string>Niels Vaes</string>
</dict>
</plist>
PLIST

# A stable signing identity keeps the Accessibility permission across rebuilds.
# Ad-hoc signatures change every build, so macOS asks again each time. Create one
# once with Keychain Access ▸ Certificate Assistant ▸ Create a Certificate,
# named "Mac Max Dev", type "Code Signing", self-signed.
IDENTITY="${MACMAX_SIGN_IDENTITY:-}"
if [ -z "$IDENTITY" ] && security find-identity -v -p codesigning 2>/dev/null | grep -q "Mac Max Dev"; then
    IDENTITY="Mac Max Dev"
fi
codesign --force --sign "${IDENTITY:--}" "$APP"

if [ -n "$IDENTITY" ]; then
    echo "built $APP, signed with \"$IDENTITY\""
else
    echo "built $APP, ad-hoc signed — expect to re-grant Accessibility after rebuilds"
fi
