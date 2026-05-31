#!/bin/bash
set -e

echo "Building Stasis..."
xcodebuild -scheme stasis -configuration Debug -derivedDataPath ./build

echo "Killing existing Stasis processes..."
pkill -f "stasis.app/Contents/MacOS/stasis" || true
# Alternatively, match the app name exactly:
pkill -x "stasis" || true
pkill -x "Stasis" || true
sleep 1

echo "Removing old Stasis from /Applications..."
rm -rf /Applications/Stasis.app

echo "Copying new Stasis to /Applications..."
cp -R build/Build/Products/Debug/stasis.app /Applications/Stasis.app

echo "Launching new Stasis app..."
open /Applications/Stasis.app

echo "Done!"
