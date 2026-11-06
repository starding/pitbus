#!/bin/zsh
# Build the package for colleagues: dist/pitbus-<date>.zip with the code, a prebuilt universal PitBus.app and the
# guide, so installing needs no Xcode. Only files git tracks go in: no data, tokens, dossiers or config.
set -euo pipefail

ROOT=${0:A:h}
STAGE=$(mktemp -d)/pitbus
OUT="$ROOT/dist/pitbus-$(date +%Y%m%d).zip"
mkdir -p "$STAGE" "$ROOT/dist" "$ROOT/menubar/build"

# the working tree as git sees it (tracked and new files, edits included; nothing it ignores)
git -C "$ROOT" ls-files -z --cached --others --exclude-standard | (cd "$ROOT" && xargs -0 tar -cf -) | tar -xf - -C "$STAGE"

# one binary for Apple Silicon and Intel, signed ad hoc (Apple Silicon runs nothing unsigned)
for arch in arm64 x86_64; do
  swiftc -O -target "$arch-apple-macos12" "$ROOT"/menubar/*.swift -o "$ROOT/menubar/build/PitBus-$arch"
done
mkdir -p "$STAGE/PitBus.app/Contents/MacOS"
lipo -create -output "$STAGE/PitBus.app/Contents/MacOS/PitBus" "$ROOT"/menubar/build/PitBus-{arm64,x86_64}
sh "$ROOT/menubar/info-plist.sh" > "$STAGE/PitBus.app/Contents/Info.plist"
codesign --force --sign - "$STAGE/PitBus.app"

rm -f "$OUT"
(cd "${STAGE:h}" && zip -qry -X "$OUT" pitbus)
rm -rf "${STAGE:h}"
echo "$OUT ($(du -h "$OUT" | cut -f1))"
