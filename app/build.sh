#!/bin/sh
# Builds build/Sofle.app, signed ad hoc. Needs Xcode (Swift 6, macOS 15 SDK).
set -eu
cd "$(dirname "$0")"

swift build -c release

app=build/Sofle.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp .build/release/Sofle "$app/Contents/MacOS/Sofle"
cp Resources/Info.plist "$app/Contents/Info.plist"
# The keymap as it is in this checkout, for when GitHub can't be reached.
cp ../config/sofle.keymap "$app/Contents/Resources/sofle.keymap"
# SwiftPM doesn't compile string catalogs, so do what Xcode would.
for catalog in Resources/*.xcstrings; do
	xcrun xcstringstool compile "$catalog" --output-directory "$app/Contents/Resources"
done
mkdir -p "$app/Contents/Resources/en.lproj"
codesign --force --sign - "$app"
echo "$app"
