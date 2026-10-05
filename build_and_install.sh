#!/bin/bash
set -e

echo "Building Stasis..."
# Ad-hoc signed: this fork has no Apple Developer team. Restricted entitlements and hardened-runtime
# flags from the Xcode signing step make launchd refuse the helper daemon (EX_CONFIG), so the
# helper and app are re-signed below the same way the release workflow does.
xcodebuild -scheme stasis -configuration Debug -derivedDataPath ./build \
    CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= PROVISIONING_PROFILE_SPECIFIER=

BUILT_APP=build/Build/Products/Debug/Stasis.app
codesign --force --sign - "$BUILT_APP/Contents/Library/LaunchServices/com.dinanathdash.stasis.charging-helper"
codesign --force --deep --sign - "$BUILT_APP"
codesign --force --sign - -r req.txt "$BUILT_APP"

echo "Killing existing Stasis processes..."
pkill -f "stasis.app/Contents/MacOS/stasis" || true
# Alternatively, match the app name exactly:
pkill -x "stasis" || true
pkill -x "Stasis" || true
sleep 1

echo "Removing old Stasis from /Applications..."
rm -rf /Applications/Stasis.app

echo "Copying new Stasis to /Applications..."
cp -R "$BUILT_APP" /Applications/Stasis.app

echo "Registering app with Launch Services & resetting App Intents cache..."
xattr -cr /Applications/Stasis.app 2>/dev/null || true
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f /Applications/Stasis.app 2>/dev/null || true
killall -9 shortcutsd intentsd 2>/dev/null || true
sleep 1

echo "Launching new Stasis app..."
open /Applications/Stasis.app

echo "Done!"
