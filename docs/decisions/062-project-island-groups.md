---
status: active
contract_ids: [PROJECT-GROUPS-001, CONVERSATION-ORDER-001, CONVERSATION-STATUS-003, ACTIVITY-STATE-008, NOTCH-MOTION-009, PRIVACY-BOUNDARY-006]
supersedes: []
owner: project-maintainer
created_at: 2026-11-01
---

# Projects are the outer list order; headings own project priority

Feature B is a session/UI/settings change with read-only metadata exposure (L2).
Project headings live inside the island's recent-chat list and accept actual
SwiftUI Transferable drag/drop. Dropping on a heading moves the dragged project
into that heading's original rank in either direction. Native up/down buttons
provide a keyboard and VoiceOver alternative, including moving a visible project
below a project whose chats were outside the global display limit. Navigation
remains exclusively on chat rows. No Settings-only ordering screen is involved.

The existing local state schema has threads.project_id and projects.id/name.
Select these three fields for parameter-bound known thread IDs only. Do not read
project roots/positions/metadata, messages or auth. Fresh read-only connections
with 25ms busy timeout observe WAL and replacement; metadata refresh runs on the
existing utility title queue/cadence. Filter late results to still-known threads
and invalidate across stop. Missing schema/database/rows, malformed project IDs,
locks and corruption return to canonical rollout cwd identity or Unassigned.
An orphan native project reference retains its stable native identity and a cwd
label; source loss can change grouping but cannot drop its chats. Native IDs and
canonical cwd paths have separate SHA-256 namespaces. Persist/transfer only these
opaque keys; readable names and paths are never in the drag token or preference.
Renaming a native project therefore preserves its rank. Same names receive short
opaque distinguishing suffixes when presented together.

App-owned versioned UserDefaults hold ordered keys, retaining dormant keys so
ordinary disappearance does not reset priorities. Newly discovered projects
append in deterministic name/key order; explicit moves preserve current visible
priority, keeping dormant keys afterward in their prior relative order. Invalid,
repeated, wrong-type or oversized preferences fail closed. Storage is capped at
4096 keys without capping in-memory candidate grouping. Discovery remains bounded
by existing activity/history monitoring, rather than scanning more chat bodies
or native tables to populate groups. Unknown projects use one localized group.

Project sort runs over all deduplicated candidates before either twenty-chat
ceiling or user limit 0-20. Existing category policy applies within each group,
with existing newest and thread tie rules. Active wins over completion; newest
completion wins over older turns. The compact/header state still uses activity
priority, independent of either list order; read receipt semantics are unchanged.
Headers count as pixels, never chat slots. Zero removes the entire recent section.

PROJECT-GROUPS-001 supersedes CONVERSATION-ORDER-001 only for outer project sorting
and the grouped viewport, inheriting its other guarantees. The viewport includes
32pt headings plus 40pt rows, capped at the former 200pt maximum. Small lists grow
by measured header pixels up to that cap. The outgoing zero-to-five-unscrolled
test now checks zero-to-twenty using this explicit superseding contract: four
chats and one heading fit, five scroll. Quota/reset/footer remain stationary.
No frame-per-tick panel changes or pet scene APIs are introduced. The controller
still prepares the final canvas once and reclaims it on collapse.

Rejected: raw cwd as drag ID, basename as identity, native project reordering,
sorting after either limit, headers consuming chat slots, Settings-only reorder,
and increasing maximum card height for twenty headings. Synthetic scene and drag
preview use invented data only. Native hosted UI/scroll integration, production
model drop routing and full verification are required. Real drag gestures,
keyboard/VoiceOver behavior, physical-notch/floating camera clearance, animation
smoothness and collapse hit regions require hardware confirmation. Rendering or
synthetic tests alone do not establish those outcomes. No installation is part
of this isolated feature delivery.

## Native transfer registration and accessibility

Declare the dedicated data type `app.codexnotch.project-order` in Info.plist;
its only conformance is public.data, without file/URL tags or bundle identity
changes. CodableRepresentation is own-process only. A real NSItemProvider
register/load roundtrip feeds the production drop handler, rather than testing
only an independently reimplemented reorder function.

The island remains a non-key panel. AppKit buttons expose a direct accessibility
press action for keyboard use through VoiceOver, plus mouse up/down controls;
normal Tab traversal on the non-key island is not asserted. Disabled edge moves
are disabled in both SwiftUI environment and AppKit so bridging cannot re-enable
an impossible move. A native-panel guard presses the enabled button, rejects the
disabled button, and observes the actual model order callback in EN/RU/ZH.

## Isolated validation

Full `./scripts/verify.sh` passed with 320 tests, zero failures and the two
existing opt-in motion-capture skips. All 108 behavior contracts, production
build, bundled resources, Info.plist and code-signature checks passed. Fifteen
new tests cover the project feature, including all 36 outer/inner permutations,
every display limit, scoped read-only SQLite/WAL/replacement/fallback, native
read receipt integration, live/persisted order, invalid payloads, NSItemProvider
transfer, non-key AppKit accessibility actions and bounded native scrolling.
Synthetic notch/floating scenes and drag previews were rendered and inspected;
they are local artifacts, without private account assets or metadata.

Local Swift 6.4 required an external native-build adapter and isolated writable
caches. Full verification ran outside the restricted sandbox for the unchanged
WindowServer/compositor and FSEvents guards. No tests or project scripts were
weakened. The work only produced an isolated local dist bundle; no installation,
launch of that application, push, PR or release occurred. Actual drag gestures,
VoiceOver keyboard interaction, camera clearance, hover/collapse hit regions and
perceived animation on physical-notch/floating hardware remain unverified.
