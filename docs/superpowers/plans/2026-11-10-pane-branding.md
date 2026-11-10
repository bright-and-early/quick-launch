# Pane branding implementation plan

**Goal:** Rename Quick Launch to Pane and deliver its glass P icon in the installed app, public universal download, and woozy.dev project entry.

**Approved design:** Pane; one translucent glass pane with a bold P. Keep launcher UI, behavior and preferences intact. No foreground native app testing or service changes.

**Architecture:** Keep the existing bundle identifier, executable/module names and persisted preference/report locations for continuity. Change visible branding and bundle name only. Package native icons from the approved PNG; preserve the old install until the new bundle passes signature/revision checks. Keep existing public repository/download URLs compatible and add Pane-named assets. Publish through the existing Sites project and preserve the old project URL with a redirect.

**Tech stack:** Swift/AppKit, iconutil/sips, existing Next.js site and Sites delivery helper.

- [ ] Update visible app labels and README; add deterministic icon generation and bundle assembly, installer migration checks, version 1.6.0.
- [ ] Run core/native checks and optimized architecture builds through shared queue; inspect generated icon at small sizes.
- [ ] Independent review; fetch/integrate main; merge PR; install quietly and verify revision, icon, signature, preferences and hidden panel.
- [ ] Publish universal ZIP with Pane and backwards-compatible asset names; verify anonymous download and digest.
- [ ] Update existing site entry/name/icon/download and old-route redirect in isolated Sites source checkout; review, build, publish, verify live, then sync task-owned changes locally.
