---
status: superseded
contract_ids: [CI-VERIFICATION-002]
supersedes: [059-supported-ci-runner]
superseded_by: 069-ci-current-image
owner: project-maintainer
created_at: 2026-11-04
---

# Use the supported Intel pool for the full CI job

The ARM macos-15 jobs for PR 5 remained queued without a runner or executed
steps. This establishes allocation delay, not a code failure or a proven
infrastructure cause. GitHub's supported runner table offers macos-15-intel;
its image inventory includes /Applications/Xcode_16.2.app. No arm64 assumption
was found in the full verification pipeline; the separate package workflow
still requires ARM. Sparkle's dependency supports both architectures.

Change only the CI runner label. Preserve job name test, explicit SDK selection,
source logging, exact-ref input, all tests and the complete verify.sh pipeline.
The distributed archive remains the locally verified Apple Silicon package.
Intel CI does not establish ARM execution: retain local ARM full verification
and compare the release's application sources with that verified source.

Risk L2. Acceptance is actual full CI success on the exact PR/release source,
not an assumption about pool availability. Reverting the runner change remains
possible; an unavailable runner still blocks merge and publication. No branch
protection, test coverage, signing policy, application behavior or data changes.

Sources: [runner labels](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)
and [Intel image inventory](https://github.com/actions/runner-images/blob/main/images/macos/macos-15-Readme.md).
