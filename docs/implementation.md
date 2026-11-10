# Quick Launch

Build a small native macOS application launcher. Command–Space toggles a focused search panel; typing selects the best application match, Tab completes its name, arrows change selection, Return launches, and Escape dismisses. A menu bar icon provides an alternate entry point and Quit.

Use Swift and AppKit already installed on this Mac, without third-party dependencies or a browser runtime. Search an in-memory list gathered from /Applications, /System/Applications, and ~/Applications, including Utilities and other subfolders. Never descend into app bundles or index document contents, hidden folders, or symlinks escaping those roots. No Spotlight APIs or service dependency.

Acceptance: test prefix/word/initial/fuzzy search, Unicode, deterministic ordering, root boundaries, Utilities discovery, no traversal inside bundles, and deduplication. Measure release search latency against the real inventory. Build a signed local .app, install in ~/Applications, verify hotkey registration and installed runtime, capture actual UI, independently review, merge and publish source. State any native interaction gap plainly.

Implementation sequence:
1. Core model, root-limited index and ranking with focused tests.
2. AppKit panel, keyboard flow, global hotkey and menu bar lifecycle.
3. Queued release build/install and installed acceptance evidence.
4. Independent review, integrate, publish and verify remote revision.

No broad filesystem indexing, network queries, plugins, or launchd service changes. Login startup is not enabled automatically. A shortcut conflict must be reported rather than ignored.
