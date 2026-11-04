# Manual release workflow

CodexNotch releases use manual installation. Settings opens the personal
[GitHub Releases page](https://github.com/rapmetpar/codex-notch/releases/latest);
the app does not download or install updates. The build contains no update feed
or update public key. There is no Sparkle archive-signing or Keychain step.
The legacy signed-update verification utilities and tests remain for regression;
the release script rejects `SIGN_UPDATES=1` before accessing any key.

## Prepare and publish

1. Update both bundle version values and write English user-facing notes in
   `docs/releases/<version>.md`.
2. Run `./scripts/verify.sh` and `RUN_TESTS=0 ./scripts/release.sh` on the
   intended source. The latter builds a verified app, ZIP, DMG and SHA-256 files
   under `dist.noindex`. Both checks are local and do not publish anything.
3. Require a passing CI run on the exact release source. Confirm its checkout SHA
   and record the run URL. A local pass does not substitute for CI.

CI uses macOS 26 Apple Silicon with explicitly selected Xcode 26.2. Local full
verification and distribution use Apple Silicon. The app still targets macOS
14; the current CI image does not prove GUI behavior on older macOS versions.
4. After review and authorization, publish the ZIP, DMG and checksums to the
   matching personal GitHub Release, then verify the downloaded assets. Do not
   publish an unsigned appcast entry. The tracked appcast remains empty.
5. Test manual replacement on the intended Mac and confirm Settings and pets.

The manual package workflow runs on the personal repository's main branch using
macOS 15 and Xcode 16.2. It uploads artifacts without an update-signing secret;
it does not publish a release. Verify the source SHA in the artifact and the
separate CI run. Hosted and local packages are ad-hoc signed, not Apple Developer
ID signed or notarized. Checksums detect corruption but do not establish publisher
identity. macOS may display a first-launch security warning.

## Replace the app

Quit all CodexNotch instances, then replace only `CodexNotch.app` and launch the
installed path. This applies to both upstream and prior fork installations. The
bundle ID remains `com.david.codexnotch`; leave preferences and Application
Support files in place to keep settings, custom artwork and pet libraries. Do
not use uninstall cleaners during an upgrade. Launch at login remains managed by
macOS. If a rollback is needed, rebuild the required revision from Git or obtain
a verified prior release without retaining backups.

`./scripts/verify.sh` uses synthetic preference fixtures; it does not replace the
installed app or prove the actual installation and settings transition. Confirm
settings, custom artwork, pets and project order after a real replacement.
