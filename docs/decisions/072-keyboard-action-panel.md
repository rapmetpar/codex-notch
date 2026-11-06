---
status: active
contract_ids: [ACTION-PANEL-001, NOTCH-MOTION-009, NATIVE-THREAD-ATTENTION-001, LOCALIZATION-001, SETTINGS-WINDOW-022, PRIVACY-BOUNDARY-006]
supersedes: []
owner: project-maintainer
created_at: 2026-11-06
---

# Separate keyboard action panel

A user-requested key window presents the existing limited, ordered conversation
snapshot alongside quota and Settings. It is separate from the non-key notch and
uses the existing thread-opening handler so an acknowledgement is produced only
when that handler accepts the link. Focus is keyed by thread ID. Escape restores
the application active when the window was opened without invoking navigation.
The app menu remains available if the optional global shortcut cannot register.
The shortcut is session-only and explicitly enabled; it does not read input events
outside the registered combination. Both Carbon handlers filter their own IDs.

Rejected: making the notch key, intercepting arbitrary input, reading more history,
and acknowledging a row merely because it gained focus. Real keyboard, VoiceOver,
Space and display behavior requires hardware confirmation.
