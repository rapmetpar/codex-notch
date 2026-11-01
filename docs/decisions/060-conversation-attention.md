---
status: active
contract_ids: [CONVERSATION-STATUS-002, ACTIVITY-STATE-007, LOCALIZATION-001, SETTINGS-MOTION-021, PRIVACY-BOUNDARY-006]
supersedes: [059-conversation-status-animation]
superseded_by: null
owner: project-maintainer
created_at: 2026-11-01
---

# Distinguish running, new and viewed conversations

The user requested a new branch because working chats, unseen answers and
already viewed chats were hard to distinguish. This is L2. Preserve the existing
running-first order, history limit, stable thread identity, 40pt row hit areas,
window geometry, quota semantics, compact completion and animation preference.

Use three explicit labels in English, Chinese and Russian. Running retains the
blue native open-ring spinner. A completed answer that has not been opened from
CodexNotch gets the green completion mark, a New capsule, a stronger title and a
faint green row fill. Viewed uses a static gray check and quiet regular title.
This overrides only the inherited completed-row styling and metadata placement;
completion time, elapsed time and project remain visible on the second line.
Hover and press change only the row background, without scaling or resizing.
VoiceOver names the state, and tooltips explain what Viewed means locally.

CodexNotch has no verified source of reading inside Codex. Do not call app
activation proof of reading, guess from hover, or mark every chat viewed when
Codex becomes frontmost. A successful thread-link handoff acknowledges only the
completion captured when that row/header was clicked. Running chats are never
acknowledged. Match both turn ID and completion instant, so another completed
turn or an updated completion becomes New again. Initial history is New until
acknowledged locally. An accepted URL is an opening acknowledgement, not proof
that the reader consumed the answer or that Codex selected it successfully.

Store only thread IDs, turn IDs and completion instants in the app's own
UserDefaults, under a versioned key. Never write to Codex files or cache titles,
messages, paths, quota or authentication data. Retain at most 512 receipts,
always including the just-opened chat; evict the oldest other completion when
full. Evicted receipts may cause older chats to show New again. Corrupt data
falls back to no acknowledgements. The existing preference observer ignores
receipt writes; the navigation handler requests the state refresh explicitly.

Rejected: color alone, changing list order on acknowledgement, adding more
settings or sources of conversation content, changing compact completion,
and claiming synchronization with native Codex read state.

Validation covers handoff success/fallback, hover/frontmost non-acknowledgement,
restart, new turns, running priority, order/limit preservation, corrupt/bounded
storage, metadata minimization, all three languages and native row layout with
motion off. Existing native animation guards remain in place. Full verification
and a local preview are required. Real notch clearance, hover, navigation,
VoiceOver and perceived animation still require hardware confirmation.

Work is isolated on `codex/chat-list-states` in
`/Users/rapmet/Documents/codex-notch/.worktrees/chat-list-states` because other
chats were editing and switching branches in the original worktree. Copied
appearance and extended-history changes were excluded from this branch before
final verification; their original worktrees remain untouched. The native row
animation implementation and guards are retained as part of the status design.

## Local verification

Full verification passed with 266 tests, zero failures and two existing opt-in
animation captures skipped; 102 contracts, release bundle, resources and signing
checks passed. The toolchain's resource-layout incompatibility required a local
PATH wrapper adding `--build-system native`; no project build scripts or checks
were disabled. The copied dependency cache was restored with symlinks preserved
before final bundle verification. New state tests reproduced and fixed eviction
of a just-opened old completion when the 512-receipt bound is reached.

A native bitmap preview of the three production Russian rows with motion off
was inspected for readable text and distinctions. The finite animation guard
uses explicit layer timing, non-restarted playback, its settled full check and
detachment cleanup; it does not assume XCTest's compositor removes the
inspectable CAAnimation object after a wall-clock sleep. Physical camera
clearance, real hover/collapse hit regions, actual thread selection, VoiceOver
and perceived animation remain for real-hardware confirmation.
