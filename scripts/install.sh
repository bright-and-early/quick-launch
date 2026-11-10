#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/package.sh
# Do not replace a running launcher or its privileged helper.
if pgrep -f '/(Pane|Quick Launch)\.app/Contents/MacOS/QuickLaunch( |$)' >/dev/null; then
    echo 'Quit Pane (formerly Quick Launch) before installing a new revision.' >&2
    exit 1
fi
mkdir -p "$HOME/Applications"
staging="$(mktemp -d "$HOME/Applications/.Pane-install.XXXXXX")"
trap 'rm -rf "$staging"' EXIT
bundle="$PWD/.build/Pane.app"
destination="$HOME/Applications/Pane.app"
ditto "$bundle" "$staging/Pane.app"
codesign --verify --strict "$staging/Pane.app"
cmp "$bundle/Contents/Resources/source-revision.txt" "$staging/Pane.app/Contents/Resources/source-revision.txt"
if [[ -e "$destination" ]]; then
    if [[ "$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$destination/Contents/Info.plist" 2>/dev/null || true)" != dev.woozy.quick-launch ]]; then
        echo 'A different app already exists at ~/Applications/Pane.app; leaving it unchanged.' >&2
        exit 1
    fi
    mv "$destination" "$staging/Previous.app"
fi
if ! mv "$staging/Pane.app" "$destination"; then
    if [[ -e "$staging/Previous.app" ]]; then mv "$staging/Previous.app" "$destination"; fi
    exit 1
fi
legacy="$HOME/Applications/Quick Launch.app"
if [[ -d "$legacy" ]] && [[ "$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$legacy/Contents/Info.plist" 2>/dev/null || true)" == dev.woozy.quick-launch ]]; then
    mv "$legacy" "$staging/Quick Launch.app"
fi
shasum -a 256 "$bundle/Contents/MacOS/QuickLaunch" "$destination/Contents/MacOS/QuickLaunch"
echo "Installed $destination ($(cat "$destination/Contents/Resources/source-revision.txt"))"
