---
status: active
contract_ids: [NOTCH-MOTION-009, SETTINGS-MOTION-021, NOTCH-HEIGHT-001]
supersedes: [045-hover-response-and-shadow]
superseded_by: null
owner: project-maintainer
created_at: 2026-11-01
---

# Restrained hover motion with continuous landing geometry

The user reported jerky hover expansion and requested smoother motion. This
L2 change replaces the inherited surface timing only. Preserve final geometry,
hover intent delays, downward top-centered expansion, camera/icon clearance,
stable-size text, shadow, quota/task behavior and the independent app animation
switch. Settings, artwork, data access and release publication are out of scope.

The former opening spring used response 0.48 and damping 0.68. Its large
overshoot was then compressed by the landing bounds. Closing instead used a
0.50s Bézier curve with a nonzero initial slope, producing a strong initial
movement. Compact hover also started with a nonzero slope. Card opening,
reentry and expanded resizing now use a native SwiftUI spring, response 0.48
and damping 0.86. Compact feedback retains its finite 0.20s curve, now with a
zero initial slope and a small settling return. Closing retains its finite
0.50s duration and small return but uses control points (0.2, 0), (0.32, 1.1)
to start at rest. Keep the content transitions independent and unscaled.
There is no custom frame timer.

Using springs for compact feedback and closing failed the existing native
capture's hit-area recovery guards: `.removed` callbacks outlasted visible
motion. Keep those phases finite without advancing controller settlement
ahead of actual animation completion. Opening can retain its natural spring
tail because its canvas remains interactive while the card is open.

The regression test reproduced another discontinuity: reversing an opening
removed its non-animatable landing limit immediately. The same proposed size
429x334 changed from a bounded 425.43x327.53 to 429x334 before any travel. Keep
the maximum landing bounds through interrupted transitions and clock updates.
Allow the next opening to replace them only after the latest surface
animation's `.removed` completion. Keep the last ceiling while compact so
releasing it cannot perturb a final presented frame.
A generation identifier prevents an interrupted animation's completion from
clearing the current bounds. Disabled motion and layout-route changes bypass
the retained bounds. Expanded content shrink still starts at its full size.

Keep the plain AppKit canvas, pre-animation centering, independent controller
completion identifiers and post-collapse reclamation. The 0.65/0.50s controller
timeouts remain fallback behavior only; production uses actual completion.
Detail offset/opacity/blur transitions and the compact header are unchanged.

Rejected: increasing only the animation duration; using a timer to animate
NSPanel frames; removing camera floors; or scaling text with the shell.

`NotchCollapseMotionTests` now verifies a gentle first frame, bounded per-frame
travel, a small landing return, camera/icon limits and continuous reversal.
The previous requirement to match a supplied video's close samples is
explicitly superseded by NOTCH-MOTION-009; its initial movement remains a
comparison in the updated trajectory guard. Existing native hosting,
completion, reentry, app-switch and geometry guards remain in place.

The opt-in native recording fixture covers brief hover, opening, closing and
reentry with synthetic data. Its panels now sit above the installed app so
live conversation data cannot obscure the recording. Native recordings and
automated checks do not establish perceived smoothness or physical-camera
clearance; those still require real-hardware user confirmation.

## Verification

The reversal guard failed before the fix with the measured size jump above.
The final native hover capture passed all existing brief-hover, closing and
reentry hit-area recovery assertions without extending their deadlines.
Frame inspection of the synthetic recording confirmed stable-size text and
the fixed top anchor; it is not subjective animation acceptance.

Full `scripts/verify.sh` passed 101 contracts, 256 tests (254 passed, two
existing opt-in skips), release build, bundle/resource and signing checks.
The installed Xcode builder nests copied resources differently and failed
five existing asset checks, so the successful full run used SwiftPM's native
builder via an external temporary command wrapper; no packaging or resource
source was changed. The rebuilt app was launched from this isolated worktree
with the existing animation preference enabled. Physical-notch icon/camera
clearance, installed-app pointer behavior and perceived smoothness still need
the user's hardware confirmation.
