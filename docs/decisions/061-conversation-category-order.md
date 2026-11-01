---
status: active
contract_ids: [CONVERSATION-ORDER-001, CONVERSATION-STATUS-003, ACTIVITY-STATE-008, LOCALIZATION-001, SETTINGS-MOTION-021]
supersedes: []
owner: project-maintainer
created_at: 2026-11-01
---

# Let the user order running, new and viewed chat categories

This L2 change adds three rows with native up/down buttons in General Settings.
The default is Running → Completed (new) → Viewed; every permutation is reachable
with the same compact controls. Labels and accessible button names support
English, Russian and Chinese. Edge buttons are disabled, with no wrapping.
A six-value enum rejects incomplete, repeated, unknown or corrupt stored values
and falls back to the default. Its app-owned versioned UserDefaults key stores
only category names and survives restart. The existing preference observer sees
the changed runtime-preference value and immediately renders it without a new
polling timer or app restart.

Use the existing ConversationAttention running/unread/viewed classification.
This feature does not produce or synchronize read receipts. In particular,
Viewed still means the acknowledgement supplied by the attention source, not
proof that an answer was consumed. A separate native-read integration can change
that source without changing this order policy.

The reducer gathers distinct thread IDs, preferring an active thread over its
completion and the newest completion over older turns. It groups all candidates
before both the shared twenty-row ceiling and the configured 0–20 display limit.
Within running, use descending lastActivityAt; within completed categories, use
descending completedAt. Equal timestamps use ascending thread ID, so dictionary enumeration changes
or restart cannot shuffle tied rows. Stable thread IDs
keep navigation and row motion attached to their conversations. The selected
order governs only the expanded list, including the scrolling portion. The
header and compact status retain their existing running priority and completion
behavior, even when Running is the last category or the list is hidden.

CONVERSATION-ORDER-001 supersedes only chronological/running-first list ordering
in CONVERSATION-STATUS-003 and ACTIVITY-STATE-008. All their other guarantees are
inherited: attention semantics, count defaults and persistence, bounded discovery,
five-row viewport, zero hiding, privacy, navigation and state motion. The existing
attention regression keeps its compact-state assertions and now expects unread
before viewed under the new default; no regression guard is removed.

Rejected: a long popup containing all six full permutations, three independent
rank fields that allow duplicates, sorting after the display limit, and changing
compact status to match the first list category. Reordering changes which
available candidates fit a small display limit intentionally. Discovery remains
bounded by the inherited monitor: this does not search beyond its retained
completion candidates to fill a category from the entire archive.

Outcome guards cover the default and six custom orders, chronological and stable
tie behavior, deduplication and active precedence, category-before-limit with
more than twenty active candidates, every count, zero hiding, compact/header
priority, valid/invalid persisted settings and localized native control sizing.
Full verification is required. On real notch and floating hardware, confirm live
button changes, keyboard/VoiceOver access, restart persistence, scrolling and
navigation to the final row, and inherited camera clearance, collapse hit regions
and motion behavior. Automated rendering is not hardware or animation acceptance.

## Local verification

Full `./scripts/verify.sh` passed with 282 tests, zero failures and the two
existing opt-in animation-capture skips; all 104 contracts, the release bundle,
resources, Info.plist and code signatures passed. Eleven new tests cover the
order policy, including a mounted AppStorage control observing a live change
and unchanged preference values. The native controls were rendered in EN/RU/ZH
and the resulting text and arrows inspected; real button/keyboard/VoiceOver
interaction and installed-app/hardware acceptance remain pending.

The local Xcode toolchain required a temporary external PATH adapter adding
`--build-system native` to Swift build/test commands and relocating module caches
to writable temporary directories. Native UI-layer and filesystem-event tests
ran outside the restricted execution sandbox; no project scripts or regression
checks were weakened. No application was installed or launched. Verification
covers this isolated baseline plus the order feature; the combined native-read
integration must run its own full verification.

## Combined read and order integration

CONVERSATION-ORDER-001 inherits native receipt semantics from
CONVERSATION-STATUS-003 and supersedes only its list ordering. The earlier native
read guard now expects unread before viewed while retaining compact-state and
zero-limit assertions. A combined SQLite-backed guard checks native read
reclassification before a one-row limit, custom Viewed-first order, a new turn
with a stale receipt, and compact running priority.
