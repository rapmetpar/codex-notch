---
status: active
contract_ids: [PET-SPRITE-001]
supersedes: []
owner: project-maintainer
created_at: 2026-11-01
---

# Native generic pet sprite playback

This L2 library change adds no catalog, preferences, artwork, account access,
window geometry or island state policy. It consumes an explicit local URL or
CGImage plus validated geometry and clips. Decode is bounded before allocation;
whole pixel cells are cropped once. No alpha bounding-box trim or interpolation
into adjacent cells is permitted. Published rows 0–8 share exact timing in v2
8x11 and metadata-confirmed legacy 8x9. Look-direction rows are static poses,
not guessed animation clips. Transparent frames remain transparent.

Use native discrete CALayer contents keyframes, not per-frame SwiftUI updates,
display-link callbacks, NSPanel timers or a global scheduler. One visible
renderer has at most one contents animation and no application timers. Author
holds, including the final frame, are represented by cumulative keyTimes and a
duplicate terminal image. Native compositor cadence is capped at 30 Hz; this
is a scheduling bound, not a claim of 30 distinct authored frames per second.

A scene owner retains one PetSpritePlaybackSession beyond view remounts. Tokens
identify genuine one-shot events; configuration, ordering, position changes or
history reopen cannot invent a new token. Paused playback resumes its elapsed
phase, never restarts. Leaving a clip consumes its token; returning later shows
the settled frame. Tokens are bounded to 256 UTF-8 bytes, memory to 512 events;
a saturated session fails closed (static subsequent events), never evicts old
events and then replays them. The scene can create a new session for a new
lifetime, but must not recreate one on every body evaluation. Loop clocks and
one-shot events are independent of application preferences and task semantics.

Detach, hidden ancestry, occlusion, caller visibility and zero-size views stop
native animation. The pet also honors the app motion input AND system Reduce
Motion, a narrow user-requested exception to SETTINGS-MOTION-021. Existing quota,
status, hover and Settings animation behavior remains independent of system
Reduce Motion. Motion off consumes pending one-shot playback and shows an
authored recognizable static cell, so reenable does not celebrate old work.

Movement is a separate pure sampler, in y-down stage coordinates. It preserves
an explicit baseline and starting contact, clamps whole cells into a supplied
safe rect, scales oversize sprites to fit, bounds smooth walk excursions before
sampling and reserves jump anticipation/settle contact. Scene owners retain
startingX and baseline across clip/pet changes. To retarget midway, pass the
previous sample's bottomContact.x as startingX and reset local movement elapsed;
never reset to the stage center. This API never moves an NSWindow.

Tests cover all states/timings, transparent frames, top-left crop orientation,
validation budgets, one-shot identity and saturation, native animation bounds,
backing scale, visibility/Reduce Motion/detachment and sampled floor/bounds.
Local previews demonstrate sampled pixels and motion only. Installed physical
notch smoothness, camera clearance and real-world CPU/GPU need hardware review;
no screenshot or automated layer request proves them.
