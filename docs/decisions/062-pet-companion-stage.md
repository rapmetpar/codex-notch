---
status: superseded
contract_ids: [PET-COMPANION-001]
supersedes: []
superseded_by: 063-compact-pet-wing
owner: project-maintainer
created_at: 2026-11-01
---

# A companion owns a stage, not a status lane

This L2 change adds opt-in companion Settings and presentation policy. It
consumes the separate local catalog/loader and native sprite-renderer interfaces;
it does not duplicate their validation/playback, generate artwork, read account
credentials or application bundles, or implement project grouping.

Physical compact geometry has no safe dedicated character space. Keep those
wings exactly as they are. A selected companion adds 112pt to expanded content:
a 104pt bounded stage and 8pt gap, after the existing camera/header inset and
before quota. Both quota-only and task-expanded frames reserve it before the
surface changes. Off adds zero height. The floating center offers a fifth style;
old modes keep their behavior. An expanded pet center is empty because the
character is on the stage, rather than rendered twice with a shared session.
An unavailable/off companion falls back to the original signature.

The app-owned controller serializes library I/O and atlas decoding on a utility
queue. Successful changes publish a local revision through the existing runtime
preference observer, preparing the final canvas once. A failed import retains
the current library and selection. No art or collection identifiers are embedded
in universal code, and no companion is automatically selected for new users.

A pure policy consumes real active sessions and completion instants. The first
snapshot primes history; later newly discovered old logs stay history. Only an
unseen completion at/after the previous observation can start a finite event.
Running overrides celebrations and greetings; a suppressed completion is not
queued for later. A 1.5-second presentation lifetime prevents reopening a hidden
scene long after an event. Retained renderer/motion event ledgers prevent replay
across view remounts. The unchanged one-second runtime cadence expires events
and provides a four-second stroll during each 24-second idle cycle, alternating
direction. Entering hover may wave once, with a 30-second cooldown. Neither
activity policy nor the scene calls the read-receipt/navigation paths.

Authored native sprite keyframes show idle breathing/work/wave/jump. A stage
samples the renderer's bounded pure motion into native position keyframes at
at most 30Hz; only its child layer moves, with a stable common baseline.
No new app timer or per-frame SwiftUI/NSPanel update is introduced. Visibility,
occlusion and detachment reuse the existing native lifecycle. A retained motion
ledger consumes one-shot jumps; disabled motion does not queue them for later.

The user specifically requested system Reduce Motion for companions. The renderer contract explicitly
supersedes decision 051 only for this feature; existing quota, surface, signature,
and status effects still follow the independent app switch. The companion
requires both app motion enabled and system Reduce Motion off. Settings explains
this exception; no system preference is mutated.

Rejected: a still left-icon replacement; putting art behind the physical camera;
a separate desktop pet window; per-frame window resizing; treating focus as read;
fake waiting/failure states; shipping a personal pet as everyone's default.

Guards cover policy events, restart/selection/Off, adapter timings, hosted
physical/floating layouts, camera clearance, motion gates and detachment, using
synthetic artwork only. Render inspection demonstrates bounded synthetic layout,
not real camera clearance or perceived animation quality. Physical notch,
hover/collapse hit areas, real system accessibility changes and smoothness still
require hardware confirmation. Installation/restart of the user's final app is
owned by the orchestrator; this branch does not install, push or publish.
