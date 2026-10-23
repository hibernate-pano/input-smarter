#!/bin/bash
# Build input-smarter into a launchable .app bundle.
#
# The machine only has the Command Line Tools, so there is no Xcode project:
# the SwiftPM binary is copied into a hand-built bundle and ad-hoc signed.
#
# The signature carries a fixed designated requirement (`identifier "…"`).
# Without it an ad-hoc signature's requirement is the code hash, and TCC
# binds the Accessibility grant to it — every rebuild would change the hash
# and the user would have to grant the permission again.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Input Smarter"
BUNDLE_ID="com.panbo.input-smarter"
CONFIG="release"
INSTALL=0
LAUNCH_AT_LOGIN=1

for argument in "$@"; do
    case "$argument" in
        release|debug)
            CONFIG="$argument"
            ;;
        --install)
            INSTALL=1
            ;;
        --launch-at-login)
            LAUNCH_AT_LOGIN=1
            ;;
        --no-launch-at-login)
            LAUNCH_AT_LOGIN=0
            ;;
        *)
            echo "unknown argument: $argument" >&2
            echo "usage: $0 [release|debug] [--install] [--launch-at-login|--no-launch-at-login]" >&2
            exit 2
            ;;
    esac
done

BUILD_DIR="$ROOT/.build/$CONFIG"
DEST="$ROOT/build/$APP_NAME.app"
REQUIREMENT="$ROOT/build/requirement.txt"

echo "==> Building ($CONFIG)"
cd "$ROOT"
swift build -c "$CONFIG"

echo "==> Assembling bundle at $DEST"
rm -rf "$DEST"
mkdir -p "$DEST/Contents/MacOS" "$DEST/Contents/Resources"
cp "$BUILD_DIR/input-smarter" "$DEST/Contents/MacOS/input-smarter"

cat > "$DEST/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>zh_CN</string>
	<key>CFBundleExecutable</key>
	<string>input-smarter</string>
	<key>CFBundleIdentifier</key>
	<string>$BUNDLE_ID</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>$APP_NAME</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>0.0.1</string>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>LSMinimumSystemVersion</key>
	<string>13.0</string>
	<key>LSUIElement</key>
	<true/>
	<key>NSPrincipalClass</key>
	<string>NSApplication</string>
</dict>
</plist>
PLIST

# The requirement has to survive every rebuild, so it is written out and
# passed to codesign instead of letting it default to the code hash.
mkdir -p "$ROOT/build"
printf 'designated => identifier "%s"\n' "$BUNDLE_ID" > "$REQUIREMENT"

echo "==> Signing (ad-hoc, fixed designated requirement)"
codesign --force --sign - --timestamp=none -r "$REQUIREMENT" "$DEST" 2>&1 | sed 's/^/    /'
codesign -d -r- "$DEST" 2>&1 | grep designated | sed 's/^/    /'

echo "==> Done"
echo "    $DEST"

if [ "$INSTALL" = "1" ]; then
    INSTALL_DIR="$HOME/Applications"
    echo "==> Installing to $INSTALL_DIR"
    mkdir -p "$INSTALL_DIR"
    rm -rf "$INSTALL_DIR/$APP_NAME.app"
    cp -R "$DEST" "$INSTALL_DIR/"
    codesign --force --sign - --timestamp=none -r "$REQUIREMENT" "$INSTALL_DIR/$APP_NAME.app" 2>&1 | sed 's/^/    /'
    echo "    installed: $INSTALL_DIR/$APP_NAME.app"
    if [ "$LAUNCH_AT_LOGIN" = "1" ]; then
        # SMAppService only accepts bundles in /Applications or ~/Applications.
        echo "==> Enabling launch at login"
        "$INSTALL_DIR/$APP_NAME.app/Contents/MacOS/input-smarter" --launch-at-login on | sed 's/^/    /'
    fi
fi

echo "    open \"$DEST\"   # launch"
echo "    Then grant Accessibility in System Settings > Privacy & Security > Accessibility."
