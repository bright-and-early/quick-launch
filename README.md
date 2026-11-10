# Quick Launch

A small native macOS application launcher written in Swift and AppKit. No third-party dependencies, web runtime, Spotlight queries, document search, or network access.

Press **Command–Space**, type an application name or abbreviation, then press **Return**. **Tab** completes the selected suggestion, **↑/↓** changes the selection, and **Escape** dismisses the panel. Drag the search icon, empty search field, or window background to reposition it. When a query is present, the field keeps normal text selection. Scroll the results immediately after opening to browse every indexed app; arrow-key selection scrolls into view automatically. Click the menu bar magnifying glass to open the launcher or quit.

The search row also shows one-click logos for AppLab, Atlas, Gimme Job, Matterlab, and Menagerie when installed in `~/Applications`. Hover a logo to identify it; clicking opens that installed app through the same launch flow as a search result.

The index reads app bundles only under `/Applications`, `/System/Applications`, and `~/Applications`, including Utilities. It skips dot-prefixed entries, hidden non-app folders, symlinked folders, and the contents of app bundles. Application links such as Safari are included without scanning their destination folders. It refreshes in the background on first launch and, when opened, after the previous scan is at least 30 seconds old. Searching uses precomputed normalized names in memory; scanning never runs on the main thread. App icons are cached lazily.

## Build and install

Requires macOS 13+ and the Xcode command line tools. On Steven's Mac, use the shared queue for each finite job:

```sh
/Users/steven/.codex/bin/local-check-queue -- swift run CoreChecks
/Users/steven/.codex/bin/local-check-queue -- swift run InteractionChecks
/Users/steven/.codex/bin/local-check-queue -- ./scripts/install.sh
open "$HOME/Applications/Quick Launch.app"
```

The installer builds an optimized executable from this checkout, creates an ad-hoc signed `.app`, records its source revision, verifies the signature, and checks the copied executable hashes. Local signing supports this Mac; distribution to other Macs needs appropriate signing/notarization.

The app runs in the menu bar until Quit. Login startup is not enabled automatically. If Command–Space is already claimed, the app reports registration failure; release the existing shortcut in System Settings → Keyboard → Keyboard Shortcuts → Spotlight, then reopen Quick Launch. No Accessibility permission or key logging is required for the registered shortcut.

Diagnostic commands on the installed executable:

```sh
"$HOME/Applications/Quick Launch.app/Contents/MacOS/QuickLaunch" --benchmark
"$HOME/Applications/Quick Launch.app/Contents/MacOS/QuickLaunch" --inventory
```
