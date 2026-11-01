---
status: superseded
contract_ids: [PET-EXPANDED-003]
supersedes: [063-compact-pet-wing]
superseded_by: 064-compact-shared-slot
owner: project-maintainer
created_at: 2026-11-01
---

# Expanded cards have no companion stage

The user's screenshot and direct correction remove the large companion scene.
PET-EXPANDED-003 inherits earlier companion guarantees except expanded stage,
hover transfer and expanded fallback. This L2 correction removes the actual
expanded scene and its 104pt height plus 8pt gap. Both runtime canvas sizes now
come directly from the existing quota/task sizing functions, regardless of pet
selection. Window preparation, downward inner-surface expansion and delayed
collapse reclamation are unchanged. The native sprite renderer and optional
floating compact Companion style remain available.

Reject hiding artwork while keeping reserved space, compensating with negative
padding, and resizing the NSPanel every animation frame. Do not change compact
left presentation or spinner here: a separate correction owns that behavior.
Earlier stage-specific integration assertions are superseded explicitly; native
compact, policy, motion, quota, project and geometry guards are retained.

Synthetic hosted guards compare actual quota/project/footer layout for a selected
pet and Off at original card heights, and require no large companion stage in
expanded states (a separate compact/header correction may retain its small slot). Real notch clearance, hover/collapse hit regions, compact
appearance and perceived animation still require hardware confirmation. This
isolated branch does not install, push or publish.

## Isolated validation

Full `./scripts/verify.sh` passed on this isolated branch: 114 contracts,
361 tests, five pre-existing opt-in skips and zero failures; release app,
resources, signature and the preference replacement/relocation fixture passed.
The new native body guard covers physical/floating cards, 0/1/5/20 chats,
missing/weekly/both quota windows and idle/running/completed headers, comparing
selected against Off without the extra stage allocation. It checks a 200pt
scroll viewport for long lists and identical body pixels/footer controls.
The original-base negative-control clone fails the hover guard with a mounted
104pt scene outside the header. Synthetic quota-only and twenty-chat renders were
inspected locally. Personal collection fixtures were not enabled.

Local Swift 6.4 used an external native-builder wrapper and fresh writable
caches; the successful full run had WindowServer/compositor access. The initial
restricted run's live-layer failures did not recur with that access. No project
script, existing regression, real preference domain, library or artwork was
changed to obtain the result. The temporary-source negative-control approach
was rejected by automatic approval review for interruption/data-loss risk;
a separate disposable clone produced the negative result without rewriting the
working fix. Physical notch/manual acceptance remains outstanding.
