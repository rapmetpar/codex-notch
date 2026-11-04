---
status: superseded
contract_ids: [CI-VERIFICATION-004]
supersedes: [069-ci-current-image]
superseded_by: 071-ci-intel-reserve
owner: project-maintainer
created_at: 2026-11-04
---

# Run the unchanged CI verification on Apple Silicon

The macOS 15 Intel job and two macOS 26 Intel attempts failed before any step,
with the hosted runner not acquired after multiple attempts. Earlier macOS 15
ARM jobs also waited unassigned. These are allocation failures, not evidence of
source or test failures; their underlying cause is not established.

Use the standard `macos-26` Apple Silicon runner with the same explicit Xcode
26.2. Keep `test`, every test, `verify.sh`, source and toolchain logging, manual
ref, protected main and separate packaging unchanged. The runner uses the
architecture of the distributed app. Allocation and success are not guaranteed.
Retain local full ARM verification and rebuild release archives from the final
checked source. Keep the macOS 14 deployment target. Current-image CI does not
prove GUI behavior on macOS 14 or 15.

Risk L2: hosted allocation and the full CI result remain unverified. A complete
successful exact-source run is required before merge and release; never count an
unassigned job as success or skip a check. Revert the runner selection if needed,
but a missing successful supported run still blocks publication. Product code,
tests, package workflow, user data and release assets are outside this change.

Sources: [GitHub hosted runner labels](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)
and [Apple Silicon image inventory](https://github.com/actions/runner-images/blob/main/images/macos/macos-26-arm64-Readme.md).
