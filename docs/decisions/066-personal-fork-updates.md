---
status: superseded
contract_ids: [APP-UPDATE-003, RELEASE-SIGNING-002, SETTINGS-PERSISTENCE-001]
supersedes: [047-sparkle-in-app-updates, 057-actions-release-signing]
superseded_by: 067-manual-updates
owner: project-maintainer
created_at: 2026-11-04
last_verified_commit: null
---

# Independent update identity for the personal fork

The upstream feed and key belong to a different publisher. This fork uses its
own Ed25519 public key, Keychain account `com.rapmetpar.codexnotch.sparkle`,
feed on `rapmetpar/codex-notch` main, and release assets in that repository.
The initial feed is empty until a verified archive has been published. The old
upstream key cannot authenticate this fork's update; existing users need a
one-time manual replacement. Keep the same `com.david.codexnotch` bundle ID and
app-owned data. Subsequent fork updates use manual Sparkle checks.

The personal private key stays in Keychain. CI Secret provisioning is a separate
explicit action; this change does not provision one or claim hosted packaging.
Verify the signed ZIP using the embedded public key before publication. Do not
publish the feed until the release assets are public and independently checked.

Rejected: pointing the fork to upstream (wrong publisher and potential downgrade),
sharing an upstream signing key, or publishing a feed for an absent archive.

L3 acceptance requires local full verification, CI on the exact release source,
manual migration with settings and pets intact, and a subsequent real Sparkle
update and tamper rejection. None is implied by this decision. Roll back by
rebuilding the appropriate Git revision or using a verified prior release without deleting preferences or support files;
withdraw a faulty feed entry, and use a higher build for corrective releases.
Apple notarization is separate.
