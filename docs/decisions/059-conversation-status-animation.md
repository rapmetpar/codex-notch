---
status: superseded
contract_ids: [CONVERSATION-STATUS-001, ACTIVITY-STATE-007, SETTINGS-MOTION-021]
supersedes: []
superseded_by: 060-conversation-attention
owner: project-maintainer
---

# Per-conversation running and completion motion

Replace the recent-row green pulse with a blue open-ring spinner and a green
closed-ring check. A visible running-to-completed transition draws the check
once over 0.28 seconds. Existing completed history appears immediately; opening
the card is not a new completion event. Another turn restores the spinner.

Use the existing native layer visibility/occlusion/detachment gates and app
animation preference. Continuous motion uses the existing eight-frame cadence.
Static shape and color distinguish both states with motion off. No timer,
quota effect, particle effect, new preference or activity source is introduced.

Recent rows previously used array offsets as their SwiftUI identity. Use their
thread IDs so sort changes preserve the relationship between chat and renderer.
Keep the 16pt icon slot, row sizing, metadata, navigation, compact icons and
window transitions. A SwiftUI forever animation was rejected because native
layers already provide explicit hidden/detached cleanup in this project.

Native tests cover independent chat transitions, finite completion, repeat
configuration, new turns, motion off/on, hidden and detached cleanup, static
geometry, and the SwiftUI environment connection. Full verification is required.
Real-notch animation smoothness and hover appearance still require physical
hardware confirmation; automated animation requests are not visual acceptance.
