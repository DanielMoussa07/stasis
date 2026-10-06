#!/bin/bash
# Builds an ad-hoc signed Release app and packs it into dist/Stasis.dmg without touching /Applications.
set -e

xcodebuild -scheme stasis -configuration Release -derivedDataPath ./build-release \
    CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= PROVISIONING_PROFILE_SPECIFIER=

BUILT_APP=build-release/Build/Products/Release/Stasis.app
codesign --force --sign - "$BUILT_APP/Contents/Library/LaunchServices/com.dinanathdash.stasis.charging-helper"
codesign --force --deep --sign - "$BUILT_APP"
codesign --verify --deep --strict "$BUILT_APP"

rm -rf dist/dmg_root dist/Stasis.dmg
mkdir -p dist/dmg_root
cp -R "$BUILT_APP" dist/dmg_root/Stasis.app
ln -s /Applications dist/dmg_root/Applications
hdiutil create -volname "Stasis" -srcfolder dist/dmg_root -ov -format UDZO dist/Stasis.dmg
rm -rf dist/dmg_root
shasum -a 256 dist/Stasis.dmg
