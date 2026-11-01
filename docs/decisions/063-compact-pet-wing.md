---
status: superseded
contract_ids: [PET-COMPACT-002]
supersedes: [062-pet-companion-stage]
superseded_by: 064-no-expanded-pet-stage
owner: project-maintainer
created_at: 2026-11-01
---

# The selected pet belongs in the compact physical left wing

The user corrected the earlier interpretation: the living companion must
replace the compact ChatGPT/Codex artwork without requiring hover. The original
36pt extension cannot contain a readable 22pt five-hour quota, a separate state
cue and a companion simultaneously. Overlaying them or hiding quota is rejected.

This L2 change adds 42pt only to the visible left wing. In left-to-right order,
reserve 8pt padding, a 22pt quota slot, 4pt gap, a 12pt state slot, 4pt gap, a
30pt pet slot, and 8pt padding. The 88pt content lane replaces the old 46pt lane;
the original extra 10pt into the black camera area remains empty. The pet center
equals the former app-mark center. Its untrimmed cell is bounded inside the
30pt slot and at most 28pt high, retaining authored transparency/aspect. The
state cue is an independent blue open ring while running and green check when
completed; idle has neither false check nor a fabricated waiting state.

Keep the camera-centered internal canvas symmetric, 84pt wider, then crop its
unused 42pt right side from the surface path and actual settled panel. Add the
same 42pt trailing content padding so the weekly quota does not move. This
extends the existing leading-crop model to a trailing crop without per-frame
window changes. The controller retains original screen coordinates while
preparing/settling one canvas; stale collapse callbacks remain rejected. Hidden
recovery stays at the camera sensor. Off removes the extra width and restores
the exact old icon preference, including its original Off crop and quota
priority. During the asynchronous selection/layout handoff, the old lane is
right-aligned inside the allocated pet lane so weekly/status positions do not
jump before the canvas updates.

Do not allocate the wing unless measured auxiliary safe areas contain it,
camera height is at least 24pt, the unshifted camera anchor is valid, and the
expanded canvas is wide enough for the compact floor. Otherwise use the old
compact layout plus the already existing expanded companion scene. This is a
fail-closed fallback, not an assumption that every screen can fit the wing.
Settings describes it. With a selected companion the physical pet wing takes
precedence over the old Left side Off choice; companion Off restores that
choice. No preference keys, defaults, artwork or library contents change.

Compact and expanded physical scenes are mutually exclusive: hover shows the
larger existing stage and leaves its compact pet slot clear, retaining quota
and the state cue in the header. The retained native session/event policy is
unchanged. Sprite motion, the new cue, visibility/occlusion/detachment and both
motion switches retain truthful static states. The existing compact button
still owns click and hover; the character does not intercept them. Floating
styles, read receipts, project groups, count limits, clocks and quotas are
unchanged.

Read-only current metrics on the implementation machine: 1470×956, 32pt camera
height, left safe area x=0…646, camera x=646…825. Old compact is x=607…864;
new visible compact is x=565…864. The native whole-cell pet stays before x=646,
the weekly center stays x=841, and the left extension uses available safe area.
This establishes coordinate capacity only. It does not establish menu crowding,
physical camera appearance, small-character recognizability or animation feel.

Outcome guards first reproduce the missing compact character, then exercise
native views at 24/32/38pt, both quota styles, running/completed/idle, five-hour
presence, motion on/off, old icon Off, exact slot coordinates, fallback, hover
transfer, native no-hover playback, detachment and canvas reclamation. Synthetic
renders and opt-in original-collection fixtures stay local; no personal art is
committed. Full verification and explicit real-user hardware acceptance remain
required before claiming the correction is visually accepted.
