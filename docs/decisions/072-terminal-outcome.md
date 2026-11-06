---
status: active
contract_ids: [TURN-OUTCOME-001, NATIVE-THREAD-ATTENTION-001, PET-SPRITE-001, PRIVACY-BOUNDARY-006, LOCALIZATION-001]
owner: project-maintainer
created_at: 2026-11-06
---

# Terminal outcomes remain separate from attention

Carry recognized lifecycle events through the existing history snapshot. A valid
completion event means only that an end event was observed, not that work
succeeded. An explicit abort is interrupted; an end event without a valid
instant is unknown. Neither stale unfinished work nor a replaced turn is
invented as a terminal event. Show the outcome in the existing metadata line,
with an explanation in the tooltip and accessibility hint. Use a neutral icon
for interrupted and unknown rows so that an attention badge cannot be mistaken
for a completion check. Keep the existing attention badge, sorting, receipts,
compact source policy and row height. A pet celebration requires the timestamped
completion event, while its identity remains the existing turn and instant.
A compact signal sourced by a native unread receipt remains available, but its
completion echo and quota fireworks are suppressed for interrupted or unknown
outcomes; other quota motion is unchanged.

Rejected: inferring task quality from messages, a fourth attention category,
changing the compact signal source or adding new layout. Physical-notch and
VoiceOver acceptance, including long Russian and Chinese titles, remains pending.
