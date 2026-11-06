---
status: active
contract_ids: [PRESENTATION-PRIVACY-001, PRIVACY-BOUNDARY-006, SETTINGS-PERSISTENCE-001]
supersedes: []
owner: project-maintainer
created_at: 2026-11-06
---

# Presentation privacy on existing surfaces

An opt-in persisted switch masks app-owned personal labels and artwork on the
existing island, fallback menu and Settings. Project drag previews and
accessibility controls use the same displayed labels. Appearance controls are
hidden while the mode is on so that signatures and library names cannot leak;
existing selections and assets are not rewritten. Navigation to Codex requires
a separate confirmation, with cancel as the default, before opening or recording
an acknowledgement. Quota and activity remain unchanged. This is not protection
for Codex itself, other applications, screenshots or recordings.

Rejected: screen-sharing detection and permissions; mutation of appearance or
library preferences; assuming an island-only mask covers the fallback menu.
Rollback uses the previous Git revision and preserves the existing preferences.
Human privacy review and physical-notch, floating, mirrored and VoiceOver checks
are required before integration.
