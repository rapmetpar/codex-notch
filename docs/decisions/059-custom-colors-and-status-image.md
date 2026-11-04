---
status: active
contract_ids: [SETTINGS-APPEARANCE-024, SETTINGS-MOTION-021, PRIVACY-APP-BUNDLE-040]
supersedes: [028-share-weekly-quota-theme]
owner: project-maintainer
created_at: 2026-11-01
---

# Local custom quota color and status artwork

Appearance Settings offers an opt-in native color picker for quota rings,
wave fills, expanded progress rows, the running halo, inner glint and status
echo. Default mode keeps the existing quota-dependent palette and critical
neutral echo. Custom mode uses one opaque sRGB color at every available quota
level; the Settings footer explains that it replaces warning colors. Missing
quota remains neutral. Completion checkmarks retain green meaning. Turning
custom color off restores the palette while remembering the chosen color;
Restore default colors also resets that stored choice.

Add `custom` alongside `codex`, `chatgpt` and `off` in `statusIconStyle`.
Choose a PNG or JPEG through the system file importer, accept up to 8 MiB,
decode a thumbnail bounded to 128px, and re-encode PNG without copying source
metadata. Store only these pixels in local preferences, without a source
path, security-scoped bookmark or external app-bundle access. Render the
original colors and transparency with aspect fit inside the existing mark
frame. The running echo uses the same alpha silhouette and updates artwork
without restarting its animation. Missing or corrupt artwork falls back to
the embedded Codex template. Invalid import or cancellation preserves the
previous selection. Removing artwork selects Codex and clears stored pixels.

Both preferences update live through AppStorage and the view environment.
The existing five-hour quota priority applies to custom artwork as well.
This changes neither Dock/Finder identity nor task/quota state, runtime
monitoring, notch geometry, display routing or motion policy.

Rejected alternatives: saving an absolute file path would break after moving
the image; retaining the source image would keep unnecessary metadata and
large data; tinting the foreground would discard the pet's original colors;
reading another app's pet storage introduces an unrelated integration.

Consequences: custom colors intentionally remove quota warning hues, with
percentages and reset times unchanged. Imported artwork is static; animated
pet sheets are not interpreted. A user can export a single transparent pet
image and select it. No network service or new permissions are required.

Verification: retain inherited geometry, motion and icon guards; add image
normalization, persistence after source deletion, invalid-input fallback,
original-color rendering, quota tint and echo-phase guards. Run the full
verification script and rebuild/restart the app. Settings layout, camera
clearance and continuous motion require confirmation on physical hardware.

## Local verification

On 2026-11-01, all 101 contracts and 259 tests passed (two existing opt-in
skips), followed by the production build, installed-resource lookup and
codesign checks. The six new appearance tests cover imported original-color
pixels, transparency, size limits, corrupt fallback, preference persistence
after source deletion, unchanged runtime preferences, five-hour priority,
quota rendering and unchanged echo animation phase.

This machine uses Swift 6.4.2 with the new default `swiftbuild` engine. That
engine nests the copied resource directory under Contents/Resources/Resources,
causing five existing asset assertions to fail. Full verification passed with
a temporary PATH wrapper appending `--build-system native` to `swift test`
and `swift build`; repository build scripts and resource packaging were not
changed. The native engine is deprecated by this toolchain, so compatibility
with the new default engine remains a separate existing packaging issue.

A temporary native-hosted capture of Russian Appearance Settings confirmed
readable image/color controls in the existing form. Its test profile, capture
helper and temporary tab selection were removed before full verification.
No real user preferences were changed. Camera clearance, safe-area centering,
downward hover expansion, collapse hit regions, running/completed legibility
and continuous motion still need physical-notch confirmation; static renders
and automated layer checks do not prove those outcomes.

The verified app also stayed running during a three-second smoke launch with
an empty temporary CODEX_HOME, then only that test process was terminated.
Its runtime log was empty. This did not replace the concurrently running app
from another feature worktree or verify authenticated quota on real hardware.

## Test capture on hosted macOS runners

The Intel CI runner aborted inside the custom-image test with a Metal loader
assertion. Its log did not contain a stack trace, so the exact triggering call
is unconfirmed. The test's SwiftUI `ImageRenderer.cgImage` was a candidate;
the production ImageIO import does not use it. Snapshot tests now capture the
same production views through NSHostingView into a 2x bitmap, retaining pixel,
alpha, color and outline-area assertions and the negative solid-flower guard.
The same host capture replaces optional preview-only ImageRenderer uses. This
changes no production image code or UI. A local Apple Silicon run cannot prove
that the Intel runner's Metal assertion is resolved; the full CI run must do so.
