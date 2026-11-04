---
status: active
contract_ids: [APP-UPDATE-004, RELEASE-PACKAGE-003, SETTINGS-PERSISTENCE-001]
supersedes: [066-personal-fork-updates]
superseded_by: null
owner: project-maintainer
created_at: 2026-11-04
last_verified_commit: null
---

# Manual release updates without publisher-key access

The user declined publisher-key access. Settings opens only the personal GitHub
release page, and the manual-only build includes no feed or update public key.
It does not start Sparkle or install updates. The release script builds the
ad-hoc-signed app, verified ZIP and DMG and checksums without touching Keychain;
requests for signed update packaging fail before any key access. Historical
archive-signature verification utilities and fixtures remain for regression.
The workflow packages without repository secrets or publication permissions.

Rejected: bypassing Keychain approval, embedding secrets, an unsigned appcast,
or using the upstream publisher's key. Existing installations require manual
replacement; preserve `com.david.codexnotch` and app-owned data. On failure,
rebuild from Git or use a verified prior release without retaining backups.
The app is not notarized. Checksums detect transfer corruption, not publisher
identity; ordinary ad-hoc codesigning does not establish publisher identity.

L3 acceptance requires full local verification, CI for the exact release
source, human review, a verified local ZIP/DMG without signing prompts, and
real Settings and manual replacement checks. CI, publication and installation
are separate from this decision.
