---
status: active
contract_ids: [SETTINGS-PERSISTENCE-001, SETTINGS-MOTION-021, SETTINGS-APPEARANCE-024, APP-LOGIN-001]
supersedes: []
owner: project-maintainer
created_at: 2026-11-01
---

# Keep preference identity stable across packaging and development launches

A user reports choices resetting after reinstall. Inspection found no installer
preference deletion or launch-time default rewrite. The installed bundle and
source both identify as `com.david.codexnotch`. A synthetic packaged-process
reproduction shows the old implementation already retains all choices when a
same-ID app is deleted/replaced and relocated. Therefore the exact reported
ordinary reinstall remains unconfirmed; do not describe it as reproduced.

The reproducible defect is a split preference domain: the app relied on
`UserDefaults.standard` everywhere, while an unbundled SwiftPM executable has
no bundle identifier. Switching between a development executable and the app
then appears to reset choices. `AppPreferences` pins the existing released
domain, retaining all canonical values and unknown future keys in place.
Foundation rejects opening one's own current bundle ID with `suiteName`, so
packaged launches use `.standard` when it already denotes the canonical domain;
unbundled launches explicitly open that same domain as a suite. Neither the
bundle path, worktree, executable name nor version determines the store.

The App's command-language storage, Settings root, live island root, runtime
preferences, read acknowledgements and fallback menu use the same store.
Leaf views still inherit `defaultAppStorage`, preserving isolated test stores
and live SwiftUI observation. Injected runtime stores reach its hosted view.
All existing keys/defaults remain unchanged, including false/zero choices,
category order, floating text's raw spaces and normalized custom artwork.

There is no schema migration because released values already occupy the chosen
domain. Do not import arbitrary executable/test/foreign domains: provenance is
ambiguous and a later import could overwrite new choices or revive an explicit
reset. Missing/corrupt values retain existing per-setting fallback behavior.
The app never calls `synchronize`; the process guard uses it only as a test
persistence barrier. Login-item state remains owned by SMAppService; Sparkle's
own defaults remain Sparkle-owned, with no manual copying or registration.

Pet artwork/library and selection belong outside the bundle in their own
Application Support store; project order should use the injected app defaults.
These features are implemented independently and are not part of this patch.

The bundle verifier rejects CFBundleIdentifier drift. Full verification also
compiles the production preference factory into disposable fixture apps. An
old standard-domain writer, a replacement generation and a relocated bundle
verify exact persisted synthetic values in fresh processes. A separate
unbundled process reproduces the old failure, verifies the fix both directions,
preserves a zero count and verifies explicit reset. UUID-scoped domains are
removed afterward; neither HOME nor real preferences are changed. This checks
CFPreferences/bundle replacement behavior, not the real Settings UI or Sparkle
installer end to end. The actual user installation and chosen UI values still
need confirmation after integration; do not delete settings while investigating.
