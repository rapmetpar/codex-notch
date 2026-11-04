# Publisher update workflow

The personal `rapmetpar/codex-notch` fork uses Sparkle 2.9.6 and its own
Ed25519 key. The private key stays in the publisher's login Keychain under
account `com.rapmetpar.codexnotch.sparkle` and service
`https://sparkle-project.org`; only the public key is embedded in the app.
The fork feed and release assets are hosted by that personal repository. The
initial feed has no entries until the first fork archive is published and
verified. The prior upstream publisher's key and feed are separate.

Existing upstream installations must migrate once by manually replacing the
app with a verified fork release; the upstream updater cannot authenticate the
fork's new signing key. Quit all instances, replace only the app, and keep
the stable bundle ID and app-owned
preferences and Application Support files. Confirm settings and imported pets
after migration. Later fork updates can be checked manually in Settings.

## Publish a version

Write GitHub Release titles, release notes, and appcast release notes in English,
including edits to historical releases. Keep notes focused on user-visible changes,
compatibility, and installation instructions. Internal validation logs, pending
checks, and publishing checklists belong outside the public release notes.

1. Increase both `CFBundleShortVersionString` and `CFBundleVersion`; write
   user-facing notes in `docs/releases/<version>.md`.
2. Run `./scripts/verify.sh`, then `RUN_TESTS=0 ./scripts/release.sh` on the
   publisher's Mac. Sparkle's `generate_appcast` may ask for Keychain permission
   on its first use. No private key is exported. The release script independently
   verifies the generated signature against the app's public key.
3. Push the exact release commit and wait for its GitHub `CI` run to finish
   successfully before publishing. CI uses Xcode 16.2 on macOS 15 and runs the
   same full verification. A local pass does not replace a failed, pending,
   cancelled, or missing CI result, even when the failure predates this release.
   After a workflow-only fix, use CI's manual `ref` input to verify the release
   commit or tag; confirm the checkout SHA in the log matches the intended
   release source. Keep the successful run URL with the release verification.
4. When a release is authorized and both checks have passed, upload the generated
   ZIP, DMG and checksums to the matching `v<version>` GitHub Release. Read back
   the public archive URLs.
5. Copy the generated `dist.noindex/appcast.xml` over the tracked `appcast.xml`, submit it through the required PR and merge it
   to personal `main` only after the archive is publicly available.
6. Check for Updates from an older updater-enabled installation; verify the
   offered version, download, installation, relaunch, and saved preferences.

The tracked feed advertises published stable releases. Merely building a release
does not advertise unpublished files or overwrite the production feed. Do not edit
archive bytes after signing. The feed currently advertises full ZIP updates;
it does not generate deltas or beta channels.

## Local contributors and key storage

`swift test`, `build_app.sh`, and `verify.sh` do not need the private key.
Only publisher release signing requires it. Local signing uses the separate
Keychain account above. Never share the private key with users or commit it.
A GitHub Actions Secret is not assumed to exist: provisioning one requires
explicit authorization. No Apple certificates are provisioned.

Apple Developer ID signing/notarization is separate. The app still uses an
ad-hoc signature; updating does not promise to eliminate Gatekeeper prompts.
Rebuild from the appropriate Git revision or obtain a verified rollback release if a test fails. Withdraw a faulty public
feed entry and publish a higher corrective build for users already updated.

## Hosted packaging

The packaging workflow must target `rapmetpar/codex-notch` and a supported
macOS 15 runner with Xcode 16.2, and use the current output paths. It is manual
and read-only, and never publishes. Hosted signing requires the fork private
key in an explicitly authorized Actions Secret. Until that is configured and a
successful run is verified, use the publisher's local Keychain. Never print or
export private key material to a file, upload it as an artifact, or assume an
upstream repository Secret is available to the fork.

## Preserve local choices when replacing the app

Quit all running CodexNotch instances, replace only `CodexNotch.app`, then open
that exact installed path. The released bundle ID stays `com.david.codexnotch`.
Ordinary replacement does not require removing preferences or Application
Support. Uninstall cleaners that delete those files also delete chosen settings,
custom status artwork and imported pet libraries; avoid that cleanup for an
upgrade. Keep app-owned files outside the app bundle. Rebuild from Git or use a
verified rollback release if needed. Launch at login remains the actual macOS registration.

`./scripts/verify.sh` checks bundle identity and runs an isolated preference
replacement/relocation guard with synthetic domains. It does not install the
built app or change your settings. After a real update, confirm Settings and
live display choices, custom artwork, pet selection/library and project order.
The fixture proves process persistence, not Sparkle's actual installation flow.
