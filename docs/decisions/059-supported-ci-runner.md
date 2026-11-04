---
status: superseded
contract_ids: [CI-VERIFICATION-002]
supersedes: [053-explicit-ci-toolchain]
superseded_by: 068-ci-intel-runner
owner: project-maintainer
created_at: 2026-11-01
---

# Move CI off the retiring macOS 14 runner

[PR 1 CI](https://github.com/rapmetpar/codex-notch/actions/runs/41317612859)
was cancelled before checkout because of the scheduled macOS 14 image brownout.
GitHub's [retirement notice](https://github.com/actions/runner-images/issues/13518)
removes that image on November 2, 2026 and recommends macOS 15 as a replacement.
Both [Intel](https://github.com/actions/runner-images/blob/main/images/macos/macos-15-Readme.md)
and [Apple Silicon](https://github.com/actions/runner-images/blob/main/images/macos/macos-15-arm64-Readme.md)
image inventories list the existing `/Applications/Xcode_16.2.app` installation.

Change only CI's runner label to `macos-15`. Preserve the explicit Xcode 16.2
selection, exact-source workflow_dispatch input, source/toolchain logging and
the complete unmodified `scripts/verify.sh` pipeline. Update the CI contract
and current documentation; retain the former contract and decision as history.
The app still targets macOS 14. No app behavior, dependencies, signing keys,
branch protections, release publication or upstream release workflow changes
are part of this L2 repair.

The previous cancelled run is the reproduction. Acceptance requires contract
validation, full local verification and a successful GitHub CI run for the
updated PR source, including all tests, release build, resources and signing.
No test is removed or skipped to accommodate the new runner. This change has
no UI effect; Russian layout and VoiceOver acceptance remain pending as already
recorded in decision 058. Rollback is reverting this workflow/documentation
commit; an unavailable runner still blocks merging under the user's condition.
