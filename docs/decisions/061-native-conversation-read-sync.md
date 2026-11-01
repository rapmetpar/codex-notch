---
status: active
contract_ids: [CONVERSATION-STATUS-003, ACTIVITY-STATE-008, PRIVACY-BOUNDARY-006, PRIVACY-APP-BUNDLE-040]
supersedes: [060-conversation-attention]
superseded_by: null
owner: project-maintainer
created_at: 2026-11-01
---

# Synchronize native read marks for the exact published answer

This L2 session-state change extends the local-only acknowledgements in decision
060. Preserve its local receipts, running priority, row design, fixed geometry,
motion and navigation. Category sorting is a separate change. No authentication,
permissions, other application bundles, installation or public release is involved.

## Source and matching rule

Codex's local `state_5.sqlite.thread_read_receipts` exposes four small metadata
fields. The upstream [migration](https://github.com/openai/codex/blob/main/codex-rs/state/migrations/0061_thread_read_state.sql)
defines SQL NULL as read and the empty string as manually unread. The
[read-state implementation](https://github.com/openai/codex/blob/main/codex-rs/state/src/runtime/thread_read_state.rs)
retains the published terminal-event turn ID across read edits, changes the
revision for new publications and read edits, and rejects edits with stale
revisions. Revision is an opaque concurrency token, not an ordered timestamp.
No-row handling in the upstream read API is not used as evidence of reading.

Minimal read-only local validation on November 1 compared twelve receipt rows
with lifecycle turn IDs only: eleven publication keys matched the latest
completion; one matched an earlier completion. All twelve matched a completion.
No identifiers, titles, message bodies or database copies were retained. This
correlation supports exact turn matching; it is not an observed UI read action.

Require a valid text revision, SQL NULL first-unread marker, and an exact
`last_published_turn == completedSession.session.turnID` match. A receipt for
turn A cannot clear turn B, even when the native read marker is still NULL.
Both nonempty unread markers and the explicit empty marker are unread.
Missing/legacy publication keys are unknown. The native store has no completion
timestamp: its acknowledgement is turn-scoped. Existing local acknowledgements
continue to require both turn ID and completion instant.

Combine sources with OR. A successful CodexNotch thread-link handoff remains
valid even while Codex's receipt is unread or unavailable. Native unread does
not revoke local opening acknowledgement; native manual-unread mirroring is
outside this feature. Viewed means a native read mark or accepted local opening,
not confirmed consumption. Running rows bypass both sources and retain priority.

## Read-only live refresh and fallback

Query only requested completed-thread IDs and these four columns. Validate SQL
types, UTF-8 and bounded identifiers. Use parameter binding, a 25ms busy timeout
and a utility queue; no database work runs on the UI thread. Open a fresh
`SQLITE_OPEN_READONLY` connection each refresh, with normal WAL semantics rather
than `immutable=1`. Closing each connection observes both WAL commits and atomic
replacement without depending on database modification timestamps.

The monitor refreshes on a changed tracked thread set and every five seconds,
independent of rollout, title or frontmost-app updates. The runtime renders
receipt changes directly, including the menu-bar fallback. Serial requests,
generation checks and stop invalidation prevent superseded responses from
restoring old state. Duplicate results do not trigger a render. The cadence is
eventual consistency, not a hard UI latency guarantee.

Native acknowledgements live only in memory. Missing rows/schema/database,
malformed records, locks or corruption remove native evidence and return to
the existing local state. They are never persisted into ConversationReadStore,
so source loss cannot leave a stale imported mark across restarts. The global
state JSON's key names do not establish a per-turn acknowledgement and that
file is not a runtime source. No database writes, auth/message queries, private
dumps, bundle reads, focus heuristics or new permissions are introduced.

## Rejected alternatives and consequences

- NULL alone or any historical read: hides answers published after an old read.
- Infer from an open window: does not establish that this answer was selected.
- Import into local persistent receipts: leaves native evidence after source loss.
- Reuse the title refresh interval/cache: unnecessarily delays read marks and may
  retain stale metadata after WAL or database replacement.
- Parse global-state unread keys as receipts: no verified exact-turn guarantee.
- Write native read marks after local navigation: unnecessary mutation of Codex.

A missing or incompatible native store can leave a genuinely read answer New
until opened from CodexNotch. This conservative fallback is preferable to hiding
an unseen answer. Only matching native read marks are imported; arbitrary manual
unread changes do not reverse existing local acknowledgements.

## Validation

Synthetic SQLite outcome tests exercise exact read to Viewed, new-turn New,
active priority, both unread forms, absent/old/malformed receipts, schema loss,
locks/corruption, parameterized scope, unchanged database bytes, WAL commits,
atomic replacement, disappearance/recovery, unchanged compact/order/limits,
timer-driven changes without a restart, and stopped/superseded async responses.
Existing attention, native animation and navigation regression tests are retained.

Run `swift test` and `./scripts/verify.sh` on this isolated baseline. Combined
category sorting and the final integrated tree require their own full check.
Native-client selection to island transition, real camera clearance, hover,
floating layout, VoiceOver and perceived motion require real-hardware confirmation;
neither the metadata probe nor synthetic tests establish that end-to-end result.

### Isolated verification, November 1

The new outcome tests first reproduced unchanged New state despite an exact
native read mark. After the fix, all thirteen native-read tests passed.
Full verification passed: 284 tests, zero failures, two existing opt-in motion
captures skipped; 104 contracts, release build, resources, bundle and signature
checks passed. The initial sandboxed run could not exercise existing native
window/compositor and FSEvents guards; the unchanged checks passed outside that
sandbox. No tests were removed or relaxed. A local-only PATH wrapper selected
the toolchain's native build system and redirected compiler caches under the
isolated directory; project scripts were unchanged. No installation or native
Codex UI-to-notch/hardware acceptance was performed.
