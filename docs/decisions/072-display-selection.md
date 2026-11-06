---
status: active
contract_ids: [DISPLAY-SELECTION-001, DISPLAY-TRANSITION-010, SETTINGS-PERSISTENCE-001]
supersedes: []
superseded_by: null
owner: project-maintainer
created_at: 2026-11-06
---

# Select the island display

Settings offers Automatic and currently drawable displays. The app persists the
system's opaque display UUID, never the serial or the selected frame. Automatic
keeps the existing notch-first choice. When the selected display is unavailable,
the current automatic route is used without changing the preference. A mirror
member resolves to the current drawable master; every render uses that screen's
current metrics and the existing single panel.

Rejected alternatives: saving coordinates makes topology and scale changes
unsafe; overriding system mirroring exceeds the feature; creating a panel per
screen changes the interaction. The screen list and selection are local and do
not require new permissions.

Synthetic tests guard fallback, restoration, mirror routing, negative origins and
settings persistence. Physical notch, external display, mirroring, clamshell,
primary display changes and hover/click regions remain hardware acceptance work.
