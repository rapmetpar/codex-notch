---
status: active
contract_ids: [CI-VERIFICATION-003]
supersedes: [068-ci-intel-runner]
superseded_by: null
owner: project-maintainer
created_at: 2026-11-04
---

# Run full CI on a supported current image with an explicit SDK

After the ImageRenderer test-path repair, both macOS 15 Intel jobs remained
unassigned for over twenty minutes. Earlier ARM jobs had also waited without
executing steps. This is evidence of allocation delay, not a proven underlying
service cause. The previous Intel run compiled the application with Xcode 16.2
before the test renderer aborted; application sources have not changed since.

Use the standard public macos-26-intel image and explicitly select its installed
Xcode 26.2. Keep the entire verify.sh pipeline, all tests and job name test.
Preserve main protection and exact-source success before publication. Rebuild
the ARM release from the final checked commit instead of relabeling an old
archive as a build from a new commit. Keep local ARM full verification and the
macOS 14 deployment target. The separate ARM packaging workflow is unchanged.

Risk L2: the SDK and AppKit runtime change, so actual full CI success is required.
The prior 16.2 compilation does not prove macOS 15 GUI behavior after the test
repair; neither a current-image pass nor a local ARM pass establishes older-OS
GUI acceptance. Do not skip tests or count queued/cancelled runs as success.
The image can be reverted, but lack of a successful supported run still blocks
merge and publication. Application behavior, private data and signing policy
remain outside this change.

Sources: [supported runner labels](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)
and [current Intel image inventory](https://github.com/actions/runner-images/blob/main/images/macos/macos-26-Readme.md).
