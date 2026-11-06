---
status: active
contract_ids: [NOTCH-ACTIVATION-010]
supersedes: []
superseded_by: null
owner: project-maintainer
created_at: 2026-11-06
---

# Optional click disclosure

Hover remains the default. The opt-in click setting changes the compact header
into a disclosure control; chat navigation remains on the rows. The same
fixed-canvas transition is used. Pointer movement does not open or dismiss the
card. Outside mouse clicks and Escape dismiss it; the nonactivating panel can
become key only while this mode's card is open. This avoids a global keyboard
monitor and any new permission. Disabled display keeps its hover sensor in
hover mode, while click mode makes the hidden sensor non-interactive and uses
the existing visibility shortcut or menu for recovery. No opening event marks a
conversation read.

Rejected: changing the default click meaning; global keyboard monitoring;
per-frame window resizing; auto-opening on session updates. Physical hardware
must still verify keyboard focus, outside clicks, Space changes, rapid reentry,
perceived motion, camera clearance and reclaimed hit areas.
