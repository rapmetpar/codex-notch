---
status: active
contract_ids: [ACTIVITY-STATE-008, LOCALIZATION-001, SETTINGS-MOTION-021]
supersedes: [053-count-based-recent-history]
owner: project-maintainer
created_at: 2026-11-01
---

# Expand recent chat history to twenty with a bounded viewport

The user requested a new branch and more than five chats on hover. Offer every
integer from zero to twenty through the existing persisted preference. Keep two
as the default, preserve all existing values and live updates, and keep zero
hiding only the recent list. Twenty is a bounded practical increase; it does not
require scanning the full archive or storing a separate history database.

Replace the shared five-chat discovery and presentation ceilings with the
maximum supported count. Keep chronological metadata cutoffs, distinct thread
counting, child exclusion, six-hour unfinished-task expiry, no completion age
limit, ordered publication, incremental reads and deletion backfill.

Keep the previous one-to-five-row card geometry. Above five rows, use a vertical
SwiftUI ScrollView containing stable thread-identified rows in a five-row
viewport. Quota/reset content and footer controls remain outside it. Both notch
and floating layouts retain the same final canvas, top anchor, transitions and
collapse cleanup. No compact styling, animation redesign, quotas, permissions,
message content or release changes are part of this L2 change.

The prior maximum-five contract ACTIVITY-STATE-007 is superseded by
ACTIVITY-STATE-008; all other history semantics remain inherited. Existing tests
for the old upper bound now exercise twenty, retaining their negative cases.
New guards cover all persisted counts, running priority and deduplication,
restart with twenty old chats, bounded discovery/backfill, unchanged five-row
geometry and a hosted scroll viewport that reaches the final rows.

Run swift test and the full verification script. Rebuild/restart the app.
Physical-notch and floating-bar scroll gestures, clicking the final chat,
expansion/collapse, stationary quota/footer controls and perceived animation
still need real hardware confirmation.

## Rejected alternatives and consequences

A twenty-row window would obscure too much of the screen. Raising only the
settings ceiling would still leave the monitor and reducer returning five.
An unbounded history list would require a separate discovery and pagination
policy. The bounded twenty-chat approach reads more old logs at startup than
five but keeps the existing cutoff and unchanged-file recovery behavior.
