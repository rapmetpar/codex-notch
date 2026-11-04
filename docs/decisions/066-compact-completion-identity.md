---
status: active
contract_ids: [COMPACT-ATTENTION-001]
supersedes: []
superseded_by: null
owner: project-maintainer
created_at: 2026-11-04
---

# Compare completion identity independently of mutable metadata

The monitor previously compared full session values to detect a new successful
completion. Changing a session's cwd or other metadata can make the same
thread, turn and terminal instant compare unequal and become a candidate for
another compact signal. Compare these three immutable identity fields instead.
The existing bounded delivery gate provides another replay barrier, including
file replacement and removal; the identity check does not depend on the gate
having seen the original event. A new turn or terminal instant still admits a
real successful completion, including a start and finish delivered together.

Native unread remains an independent compact signal under COMPACT-ATTENTION-001.
A stale native unread source can therefore still display a historical check;
repairing that source is separate work. Do not infer that this change alone fixes
all observed ghosts. Native read, local read, persisted observations, running
priority, child exclusion and the pet slot cadence retain their contracts.
Hardware confirmation of the actual check and read transitions remains required.
