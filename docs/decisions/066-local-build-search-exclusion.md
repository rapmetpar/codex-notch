---
status: active
owner: project-maintainer
created_at: 2026-11-04
contract_ids: [PACKAGE-SEARCH-002, PACKAGE-VERIFY-006, PACKAGE-DMG-018, SETTINGS-PERSISTENCE-001]
supersedes: []
superseded_by: null
---

# Keep the current local build outside application search

Spotlight returned eight bundles with com.david.codexnotch: the installed app,
the current dist app and six backups. Launch Services also retained development
and temporary bundles. Only /Applications/CodexNotch.app was running. These
were separate copies of version 0.2.5, not eight installed release versions.

Default build, verification and release output now uses dist.noindex, with one
shared path resolver. Keep explicit argument and environment overrides for
existing packaging integrations; a caller choosing an indexed directory remains
responsible for its search visibility. CI artifact paths and current usage docs
follow the default. Historical plans and decisions retain their original paths.

For the existing machine, unregister only duplicate CodexNotch bundles from
Launch Services and rename the indexed dist directory to dist.noindex. The user
subsequently explicitly requested deleting existing backups and retaining none
in future. Remove known backups of app bundles, preferences and pet libraries,
including hidden previous-app and temporary replaced-app copies. Keep the
installed app and current build; obtain older code from Git and rebuild when
needed. Do not create persistent backup copies during packaging or installation.
Disposable test fixtures must still be removed after verification. Packaging
scripts do not perform historical cleanup themselves. Do not alter installed app bytes,
preferences, login items or global search settings. The shared-path guard checks
the default, explicit output precedence and participation of all entry points;
full verification checks the actual bundle at the new location. A live Spotlight
query checks the migration separately; the user's launcher may need a refreshed
query to drop cached results.

Rejected: retaining backups against the user's explicit instruction, changing development bundle IDs
(splits preference identity), modifying signed app contents to hide bundles
(affects delivery), resetting Launch Services or disabling global indexing
(unrelated applications would be affected).
