#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
bundle="$PWD/.build/Quick Launch.app"
mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources"
cp .build/release/QuickLaunch "$bundle/Contents/MacOS/QuickLaunch"
cat > "$bundle/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>dev.woozy.quick-launch</string>
<key>CFBundleName</key><string>Quick Launch</string>
<key>CFBundleDisplayName</key><string>Quick Launch</string>
<key>CFBundleExecutable</key><string>QuickLaunch</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.0.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
revision="$(git rev-parse HEAD)"
printf '%s\n' "$revision" > "$bundle/Contents/Resources/source-revision.txt"
codesign --force --sign - "$bundle"
# Installer always builds this checkout before replacing the exact destination.
destination="$HOME/Applications/Quick Launch.app"
if pgrep -f '/Quick Launch.app/Contents/MacOS/QuickLaunch$' >/dev/null; then
    echo 'Quit Quick Launch before installing a new revision.' >&2
    exit 1
fi
mkdir -p "$HOME/Applications"
rm -rf "$destination"
ditto "$bundle" "$destination"
codesign --verify --strict "$destination"
shasum -a 256 "$bundle/Contents/MacOS/QuickLaunch" "$destination/Contents/MacOS/QuickLaunch"
echo "Installed $destination ($revision)"
