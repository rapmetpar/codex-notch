---
status: active
contract_ids: [READER-WINDOW-001]
supersedes: []
owner: project-maintainer
created_at: 2026-11-06
---

# Separate reading window

An explicit app-menu action opens a reusable, normal-level resizable window.
It receives the reducer's existing limited snapshot and routes each row to the
same navigation and acknowledgement logic as the notch. It owns no monitoring,
request, timer or animation. Window size does not alter the notch canvas. The
session-only scale selection is independent of notch layout. Long titles wrap and
content scrolls. No message bodies or additional history are read.

Rejected: stretching the physical notch, creating a second monitoring pipeline,
and bringing the window forward on snapshot updates. Hardware confirmation of
resizing, VoiceOver, Spaces and notch appearance remains necessary.
