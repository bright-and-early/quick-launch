#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mode="${1:-native}"
case "$mode" in native|universal) ;; *) echo 'Usage: package.sh [native|universal]' >&2; exit 2 ;; esac
bundle="$PWD/.build/Pane.app"
mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources"
if [[ "$mode" == universal ]]; then
    swift build -c release --triple x86_64-apple-macosx13.0
    swift build -c release --triple arm64-apple-macosx13.0
    lipo -create .build/x86_64-apple-macosx/release/QuickLaunch .build/arm64-apple-macosx/release/QuickLaunch -output "$bundle/Contents/MacOS/QuickLaunch"
else
    swift build -c release
    binary_directory="$(swift build -c release --show-bin-path)"
    cp "$binary_directory/QuickLaunch" "$bundle/Contents/MacOS/QuickLaunch"
fi
iconset="$PWD/.build/Pane.iconset"
mkdir -p "$iconset"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" Assets/Pane.png --out "$iconset/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z "$double" "$double" Assets/Pane.png --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$iconset" -o "$bundle/Contents/Resources/Pane.icns"
cat > "$bundle/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>dev.woozy.quick-launch</string>
<key>CFBundleName</key><string>Pane</string>
<key>CFBundleDisplayName</key><string>Pane</string>
<key>CFBundleIconFile</key><string>Pane</string>
<key>CFBundleExecutable</key><string>QuickLaunch</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.6.1</string>
<key>CFBundleVersion</key><string>17</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
<key>NSPrincipalClass</key><string>QuickLaunchApplication</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
git rev-parse HEAD > "$bundle/Contents/Resources/source-revision.txt"
codesign --force --sign - "$bundle"
codesign --verify --strict "$bundle"
echo "Packaged $bundle ($mode)"
