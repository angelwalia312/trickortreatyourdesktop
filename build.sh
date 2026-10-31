#!/bin/bash
# Builds "Trick or Treat.app" and a DMG. Needs only Apple's Command Line Tools, not Xcode.
#
#   ./build.sh
#       Ad-hoc signed build. Runs on this Mac; other Macs will show a security warning.
#
#   SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" NOTARY_PROFILE=trickortreat ./build.sh
#       Signed and notarized build that anyone can download and open.
#       (One-time setup: xcrun notarytool store-credentials trickortreat)
set -euo pipefail
cd "$(dirname "$0")"

NAME="Trick or Treat"
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/App-Info.plist)
BUILD=build
APP="$BUILD/$NAME.app"
EXT="$APP/Contents/PlugIns/TrickOrTreatFinder.appex"
DMG="$BUILD/TrickOrTreat-$VERSION.dmg"
MIN_OS=13.0
IDENTITY="${SIGN_IDENTITY:--}"
SDK=$(xcrun --show-sdk-path)

rm -rf "$BUILD"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$EXT/Contents/MacOS" "$BUILD/obj"

echo "› Compiling app"
for arch in arm64 x86_64; do
  swiftc -swift-version 5 -O -sdk "$SDK" -target "$arch-apple-macos$MIN_OS" -module-name TrickOrTreat \
    Sources/App/*.swift -o "$BUILD/obj/app-$arch"
done
lipo -create "$BUILD"/obj/app-* -output "$APP/Contents/MacOS/TrickOrTreat"

echo "› Compiling Finder extension"
for arch in arm64 x86_64; do
  swiftc -swift-version 5 -O -sdk "$SDK" -target "$arch-apple-macos$MIN_OS" -module-name TrickOrTreatFinder \
    -parse-as-library -application-extension -Xlinker -e -Xlinker _NSExtensionMain -framework FinderSync \
    Sources/Extension/*.swift -o "$BUILD/obj/ext-$arch"
done
lipo -create "$BUILD"/obj/ext-* -output "$EXT/Contents/MacOS/TrickOrTreatFinder"

echo "› Assembling bundle"
cp Resources/App-Info.plist "$APP/Contents/Info.plist"
cp Resources/Extension-Info.plist "$EXT/Contents/Info.plist"
cp Resources/Sounds/*.m4a "$APP/Contents/Resources/"
printf "APPL????" > "$APP/Contents/PkgInfo"
"$APP/Contents/MacOS/TrickOrTreat" --make-icon "$BUILD/obj/AppIcon.iconset"
iconutil -c icns "$BUILD/obj/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"

echo "› Signing with: $IDENTITY"
if [ "$IDENTITY" = "-" ]; then TIMESTAMP=--timestamp=none; else TIMESTAMP=--timestamp; fi
codesign --force --options runtime "$TIMESTAMP" --entitlements Resources/Extension.entitlements --sign "$IDENTITY" "$EXT"
codesign --force --options runtime "$TIMESTAMP" --sign "$IDENTITY" "$APP"
codesign --verify --deep --strict "$APP"

echo "› Packaging DMG"
STAGE="$BUILD/obj/dmg"
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/$NAME.app"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "$NAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
if [ "$IDENTITY" != "-" ]; then codesign --force "$TIMESTAMP" --sign "$IDENTITY" "$DMG"; fi

# Keep build copies out of Launch Services so trickortreat:// links always reach the installed app.
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
rm -rf "$STAGE"
"$LSREGISTER" -u "$STAGE/$NAME.app" "$APP" 2>/dev/null || true

if [ -n "${NOTARY_PROFILE:-}" ]; then
  echo "› Notarizing (usually a few minutes)"
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG"
fi

# The website serves the DMG straight from docs/, so GitHub Pages hosts the download too.
cp "$DMG" docs/TrickOrTreat.dmg

echo "✓ $APP"
echo "✓ $DMG"
echo "✓ docs/TrickOrTreat.dmg"
