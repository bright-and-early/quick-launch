# Quick Launch

A small native macOS application launcher written in Swift and AppKit. No third-party dependencies, web runtime, Spotlight search queries, or network requests. The default index contains applications only; explicitly added folders can include files and folders.

Press **Command–Space**, type an application name or abbreviation, then press **Return**. **Tab** completes the selected suggestion, **↑/↓** changes the selection, and **Escape** dismisses the panel. Drag the search icon, empty search field, or window background to reposition it. When a query is present, the field keeps normal text selection. Scroll the results immediately after opening to browse every indexed app; arrow-key selection scrolls into view automatically. Click the menu bar magnifying glass to open the launcher or quit.

The search row also shows project logos for AppLab, Gimme Job, Matterlab, and Menagerie when installed in `~/Applications`. Hover a logo to identify it; clicking brings that app forward, or hides it if it was already frontmost. Atlas remains searchable but is not pinned. Escape closes the launcher from any control, and clicking outside dismisses it.

Press **Right Arrow** with the caret at the end of the search text to focus the first project logo. **Left/Right Arrow** or **Tab/Shift–Tab** move between logos; **Return** or **Space** activates the focused logo. Left Arrow from the first logo returns to search; Right Arrow or Tab after the last logo reaches Settings, and Tab after Settings returns to search. Hover adds a subtle background, and keyboard focus adds an accent outline. Tab in the search field completes an unfinished selected application name; with the caret at the end, it moves to the project logos when the name is already complete or there are no results.

By default the index reads app bundles only under `/Applications`, `/System/Applications`, and `~/Applications`, including Utilities. It skips dot-prefixed entries, hidden non-app folders, symlinked folders, and the contents of app bundles. Application links such as Safari are included without scanning their destination folders. It refreshes in the background on first launch and, when opened, after the previous scan is at least 30 seconds old. Searching uses precomputed normalized names in memory; scanning never runs on the main thread. App icons are cached lazily.

The initial app list is alphabetical. Successful opens through Quick Launch are counted locally and saved between launches; the empty search list orders by most opens, then alphabetically. Typed searches keep match relevance first, then use open count and alphabetical order to break ties. Project-logo opens and restores count; hiding a project, cancelled transitions, and failed launches do not. Opens outside Quick Launch are not monitored.

The gear after the project logos flips the launcher 180° to its reverse settings face. Choose a highlight color (System accent, Blue, Indigo, Purple, Pink, Coral, Orange, Amber, Lime, Green, Teal, or Cyan); the choice is saved locally and applies to result selection and keyboard-focus accents. **Back to search** flips back without clearing the query. The turn lasts 280 ms; Reduce Motion uses an 80 ms fade. Escape or an outside click dismisses either face, and the next opening starts on search.

## Shortcut, folders, and Spotlight

The reverse settings face records a custom global hotkey. Click the current shortcut, then press a combination containing Command, Option, or Control. Escape cancels recording. A conflicting combination leaves the previous working shortcut active. Command–Space remains the default.

Indexed folders lists the three default Applications locations, each in app-only mode. Add folder chooses explicit additional directories and includes their visible files, folders, and app bundles. Remove drops the selected location; Apps only restores the defaults. Extra results open with their default application or Finder and reveal their path on hover. Hidden directories, symlink directory traversal, and app internals remain excluded. Background refreshes coalesce configuration edits and discard superseded inventory results.

Spotlight services opens a separate review sheet only after a deliberate click. It discovers matching loaded jobs and saved launch overrides in system, current GUI, and current user domains. The catalog follows the Spotlight/metadata workers and search-suggestion services in macos-service-manager; general filesystem/backup services are excluded. Individual domain/label rows remain separate.

Review the selected rows and choose Disable selected or Enable selected. The workflow explains the effects and then requests macOS administrator authorization. Disable saves a launch override, unloads the exact job, and verifies both independently; partial success and protected-service refusals are shown per row. Enable verifies the enabled policy and allows normal loading at login/reboot, without forcibly starting jobs. Before each mutation, the privileged helper synchronizes the fresh original state to an exclusive, root-owned journal under `/Library/Application Support/QuickLaunch/SpotlightReports`, then journals each outcome. A failed journal write prevents further changes. The settings workflow also saves a user-readable summary under `~/Library/Application Support/QuickLaunch/SpotlightReports` with the same operation ID. Batches have a two-minute command deadline, and the authorization wrapper waits for completion rather than timing out independently; an interrupted wrapper keeps the workflow busy while its helper remains active. No service changes occur at startup, during index refresh, or in automated checks. System Integrity Protection is never changed.

The installed executable's `--spotlight-status` mode reads discovery state without changing it. `--spotlight-apply` is a privileged internal command accepting only validated Spotlight catalog targets; normal settings operations invoke it through the macOS authorization dialog.

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

## Project window transitions

Project-logo clicks animate an in-memory preview of the app's primary window into or out of the clicked logo. This uses ScreenCaptureKit on macOS 14+ and asks for Screen Recording access only when you deliberately click a project logo or choose **Enable Window Animations…** from the menu. No capture or permission prompt happens at startup, and no preview is saved to disk. Until access is granted, or when no window can be captured, the same app-wide hide/show toggle works without a preview. Search-result launches remain immediate.

Transitions last 220 ms and animate layer position, scale and opacity. Reduce Motion uses an 80 ms fade. Escape/outside-click cancels pending capture or motion without activating a project over the app you just selected. Local app builds are ad-hoc signed, so macOS may ask you to re-enable capture permission after an update.

For quiet delivery or startup, launch the installed executable with `--background` (or `open -g ... --args --background`); this registers the shortcut and menu without showing the panel. Reopening an already-visible launcher leaves its query intact.
