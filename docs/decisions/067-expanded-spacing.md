---
status: active
contract_ids: [EXPANDED-SPACING-001]
supersedes: []
superseded_by: null
owner: project-maintainer
created_at: 2026-11-04
---

# Bound expanded card gaps to their intended spacing

The previous height budget left roughly 35pt of surplus after the expanded pet
stage was removed. Three flexible spacers distributed that surplus between the
quota/reset area, recent heading, project list and footer. This was visible even
without a pet. Replace those spacers with fixed 16/8/6pt spaces and reduce the
base quota and conversation height budgets by 35pt. The five-hour increment is
55pt, matching the rendered additional row. Existing per-project, scroll and
reset-detail allowances remain. The existing geometry test retains its anchor and
frame checks, with the two former 202/322pt heights updated to 167/287pt under
this explicit height-budget correction. The top anchor, compact dimensions and panel
animation architecture do not change.

A hosted native regression measures the actual production view at its production
budget in both island modes, all three languages, 0/1/5/20 chats, unavailable,
weekly and five-hour quotas, and collapsed/expanded reset details. It checks
content bounds and all gaps. Existing tests cover grouped scrolling and footer
stability. Synthetic renders do not prove camera clearance, hover animation or
hit reclamation on physical hardware; those require user confirmation.
