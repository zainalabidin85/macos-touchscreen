#!/bin/sh
# Build a universal (arm64 + x86_64) release zip into dist/.
#   ./package.sh 1.0.0
set -e
VERSION="${1:?usage: package.sh <version>}"
DIR="$(cd "$(dirname "$0")" && pwd)"
NAME="touchmouse-v$VERSION-macos"
OUT="$DIR/dist/$NAME"
TMP="$(mktemp -d)"

rm -rf "$DIR/dist/$NAME" "$DIR/dist/$NAME.zip"
mkdir -p "$OUT"

# macOS 13 is the oldest target whose Swift runtime ships in the OS, so no arch-specific
# compatibility libraries are needed to link the x86_64 slice.
for arch in arm64 x86_64; do
    swiftc -O -target "$arch-apple-macos13.0" "$DIR/touchmouse.swift" -o "$TMP/touchmouse-$arch"
done
lipo -create "$TMP/touchmouse-arm64" "$TMP/touchmouse-x86_64" -output "$OUT/touchmouse"
codesign -s - -f --identifier com.touchmouse "$OUT/touchmouse"

cp "$DIR/install.sh" "$DIR/README.md" "$DIR/LICENSE" "$OUT/"
(cd "$DIR/dist" && zip -qr "$NAME.zip" "$NAME")
(cd "$DIR/dist" && shasum -a 256 "$NAME.zip" > "$NAME.zip.sha256")
rm -rf "$TMP"
echo "Built dist/$NAME.zip"
lipo -info "$OUT/touchmouse"
