---
status: active
contract_ids: [SETTINGS-APPEARANCE-UNDO-001, SETTINGS-PERSISTENCE-001, SETTINGS-APPEARANCE-024, SETTINGS-TEXT-023, SETTINGS-WINDOW-022, PET-SPRITE-001]
supersedes: []
owner: project-maintainer
created_at: 2026-11-06
---

# Session-only undo for discrete appearance choices

Settings offers explicit Undo and Redo for five discrete appearance controls:
quota style, icon style, floating center style, the custom-color switch and the app animation switch.
An in-memory UndoManager holds at most 30 actions and is cleared on Settings
closure. Each write uses the same app preference domain and updates live.
Exact old raw values and absent keys are retained, rather than converting
unknown choices to defaults. The manager accepts only an enum of allowed
scalar keys; it does not retain or write artwork or other preference keys.

Before a history action, compare tracked values, custom color and custom artwork with the
last observed state. On mismatch discard the history; a new choice starts a
fresh sequence. Image import and removal explicitly clear history. This is a
conservative conflict policy, not a cross-process atomic transaction. The
buttons have no keyboard shortcuts and do not modify the native text editor.

Continuous color selection and its two-key reset are deliberately excluded
from this first increment: native ColorPicker does not expose an established
gesture boundary in this view. Treating every intermediate value as a user
action or grouping an entire color panel session would give misleading undo.
No backups or persistence of history are introduced. Color undo requires a
separately verified interaction design.

Automated isolated-domain guards cover exact values, missing keys, redo,
30-action bounds, conflicts, artwork, closure cleanup and rejected input.
Manual hardware acceptance remains necessary for button layout, live preview,
color and popup focus, native text editing, and physical-notch appearance.
