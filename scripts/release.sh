#!/bin/zsh
# Builds Release and packages dist/NotchKeeper-<version>.zip and .dmg (ad-hoc signed, no notarization).
set -euo pipefail
cd "$(dirname "$0")/.."

~/.local/bin/xcodegen -q
xcodebuild -scheme NotchKeeper -configuration Release -derivedDataPath build clean build 2>&1 \
  | grep -E "error:|BUILD" || true

APP=build/Build/Products/Release/NotchKeeper.app
[[ -d $APP ]] || { echo "build failed"; exit 1; }
codesign --verify --deep --strict "$APP"
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")

mkdir -p dist
rm -f "dist/NotchKeeper-$VERSION.zip" "dist/NotchKeeper-$VERSION.dmg"
ditto -c -k --keepParent "$APP" "dist/NotchKeeper-$VERSION.zip"

STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -quiet -volname "NotchKeeper $VERSION" -srcfolder "$STAGE" -fs HFS+ -format UDZO "dist/NotchKeeper-$VERSION.dmg"

ls -lh dist/NotchKeeper-$VERSION.*
