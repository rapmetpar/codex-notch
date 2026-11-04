---
status: active
contract_ids: [CI-VERIFICATION-005]
supersedes: [070-ci-apple-silicon]
superseded_by: null
owner: project-maintainer
created_at: 2026-11-04
---

# Use the Intel runner as an alternative to ARM capacity failures

Following mitigation of the earlier Actions incident, macOS 26 ARM jobs repeatedly
failed to acquire a hosted runner and reported capacity constraints. One ARM
run for source `a2bcd08` completed full verification: 400 tests, five skips,
zero failures, and 127 validated contracts. The later `8865250` commit has the
same tree, but its attempts again experienced allocation failures. The earlier
Intel failures occurred during the earlier Actions incident, so they do not
establish current Intel capacity. GitHub reported a new Actions degradation at
17:40 UTC; these observations do not establish its cause or whether Intel is
available during that incident.

Use supported `macos-26-intel` with the same explicit Xcode 26.2. Retain the
unchanged complete `verify.sh` job named `test`, all tests, source and toolchain
logging, manual ref, protected main and separate ARM packaging. Local ARM full
verification and release artifacts built from the final checked source remain
required. Keep the macOS 14 deployment target. Neither Intel CI nor local ARM
verification proves macOS 14 or 15 GUI behavior.

Risk L2: availability and complete success on this Intel configuration are not
established. A successful exact-source CI run is required before merge and
publication. Never count a runner allocation failure as success, suppress tests
or bypass main protection. Revert the runner selection if needed; no successful
supported run still blocks publication. No product, tests, scripts, package
workflow or release artifacts change here.

Sources: [hosted runner labels](https://docs.github.com/en/actions/reference/runners/github-hosted-runners),
[Intel image inventory](https://github.com/actions/runner-images/blob/main/images/macos/macos-26-Readme.md),
and [Actions incident](https://stspg.io/7pwv28hvkmz8).
