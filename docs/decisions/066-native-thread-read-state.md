---
status: active
contract_ids: [NATIVE-THREAD-ATTENTION-001]
supersedes: [061-native-conversation-read-sync, 065-compact-observed-completions]
owner: project-maintainer
created_at: 2026-11-04
---

# Follow the native client's thread unread list

The native desktop client uses `electron-thread-read-state-v1`, a full list of unread thread IDs by identity and execution host. Its client code adds and removes IDs on unread changes; this list does not include a turn ID. The earlier SQLite receipt table is a different source and can be stale or absent. On one read-only sample, native list and desktop thread listing agreed on 57/57 local entries, including nine read entries without SQLite rows. A separate snapshot had 233 SQLite unread rows absent from the native unread list; these are thread-level comparisons, not proof about the same turn.

A versioned, valid list is scoped to one persisted identity and the local execution host identified by the client's legacy host mapping. Known requested threads are verified against owner account/user metadata in the current home's read-only SQLite database; its identity hash must equal the native list key. Unknown owners, multiple identities, absent host mapping, malformed data or unavailable sources are unknown. This deliberately conservative scope can leave some older or alternate-home threads New. No auth file, message body or other SQLite field is read, and no native state is written. The global JSON parser temporarily reads the file in memory and retains only the required section. Fresh read-only SQLite connections preserve WAL and replacement behavior. Monitor generation invalidates stale asynchronous responses.

At startup, historical completions reflect the native thread snapshot. For a later completion, capture its immutable turn and instant and issue a new generation-scoped lookup. Accept that lookup when thread `updated_at_ms` is at least the completion time (allowing one second for timestamp precision), or when the scoped unread list changes and its file modification time is later than completion. The first lookup cannot use an unknown prior fingerprint as a change. This allows an already-open native conversation to become Viewed even when the unread list did not change. Local opening acknowledgements remain exact. A new task always wins. Compact state uses the same snapshot-derived evidence, so stale SQLite unread rows cannot resurrect a cue. Loss of source removes native evidence; native evidence is never persisted.

The client exposes a thread-level signal, not an ordered per-turn receipt. This freshness test is only a heuristic: a database update or unrelated thread can advance the freshness heuristic before the client processes that completion, so the old read can briefly be associated with the new answer. Conversely, if thread update metadata is unavailable or lags and a fast unread-to-read transition occurs between polls with an unchanged list, the new answer can remain New until a qualifying list change or local opening. The two-second poll has no hard latency guarantee. Initial history, a restart before native publication, account switching and nonstandard homes have the same source limitations. These are accepted tradeoffs of following the native client's available snapshot, not a claim of confirmed consumption or causal per-turn sync.

Rejected: infer read from missing schema/unknown scope; continue trusting stale SQLite unread; use focus or time alone; persist native evidence; claim the fingerprint is a publication token. Real native-client read/new-answer transitions and actual physical-notch behavior require user hardware confirmation.
