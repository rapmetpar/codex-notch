---
status: active
contract_ids: [COMPACT-ATTENTION-001]
supersedes: []
superseded_by: null
owner: project-maintainer
created_at: 2026-11-02
---

# Compact completion reflects observed unacknowledged answers

The compact reducer used the newest indefinitely retained history entry, even
after native or local read. Loading old history alone therefore created a green
check. Retain history, but distinguish it from an observed compact signal.

The rollout monitor identifies new successful completions after monitor start,
including a start and completion delivered in the same batch. It excludes aborted
turns from compact signals while retaining their existing history behavior.
App-owned bounded preferences retain only thread ID, turn ID and completion
instant. Exact local or native read removes the signal; active work always wins.
A matching native unread marker can also supply the cue, including when the app
was stopped; the marker must have valid metadata and its published turn must
match the displayed completion. Missing native rows remain unknown. Native unread
never overrides an exact local opening acknowledgement. The cutoff is an
observation boundary, not an expiry. Missing timestamps or a clock moving
backwards can prevent detection of a live event without native evidence.

The check is not proof that an answer was consumed; native reads and local
opening are acknowledgement metadata. No Codex data is written. Real native
read-to-island behavior and notch appearance require hardware confirmation.

Some locally observed agent-created threads have no native receipt row. In this
case their read state remains unknown and their history row can remain New even
after opening in Codex. The documented app-server thread list does not establish
a per-turn read mark. Resolving that limitation requires verified native evidence
or an end-to-end user test; no inference from absent rows or focus is used.

A synthetic event-tracking run loop showed that a timer scheduled only in the
default mode can defer native read lookups until tracking ends. One timer now
uses common and explicitly event-tracking modes with a two-second interval.
The database read remains off the main thread, bounded, and read-only. A fixture
checks a lookup during tracking and its eventual presentation after tracking;
it does not prove that ordinary hover enters that mode or that the live GUI
updates during a nested tracking loop. The precise cause of every reported
row-sync failure remains unverified.
