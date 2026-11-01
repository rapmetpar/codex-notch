---
status: active
contract_ids: [LOCALIZATION-001, SETTINGS-WINDOW-022, SETTINGS-MOTION-021, ACTIVITY-STATE-007]
supersedes: []
owner: project-maintainer
created_at: 2026-11-01
---

# Add Russian through the existing language preference

The user requested localization in Russian. Add Русский (`ru`) to the native
language picker and translate all app-owned copy, including settings explanations,
compact and expanded task states, quota and reset labels, accessibility text,
floating previews and the menu-bar fallback.

Retain the current AppLanguage helper and require its Russian argument. A missing
translation then fails compilation instead of silently selecting Chinese. Use a
three-case switch instead of the original English-versus-Chinese conditional.
The small existing inline catalog does not need a resource-format migration for
this additive change; moving it to keyed resources can be considered separately
if language coverage grows.

Keep English as the default and unknown-value fallback. Preserve the existing
appLanguage key, language codes and live AppStorage/runtime-preference path.
Use Russian forms for the six supported chat counts and abbreviated relative-time
units. Preserve quota values, exact timestamp format and seconds, timezone handling,
service-provided reset titles and user conversation names. System errors and
Sparkle-owned dialogs continue using their system/framework localization.

This is L2. Geometry, animations, task detection, data access, other preferences,
updater behavior and releases are out of scope. AppLanguageTests covers Russian
selection/persistence, original language fallbacks, unchanged preferences, quota
semantics, time text and count forms; existing tests protect the original languages.
Run full verification and rebuild/restart the app. Real-screen acceptance remains
required for text fitting, all tabs, menus, VoiceOver and live language switching
on physical-notch and floating displays; compilation does not establish these.

## Local verification

Validated 100 contracts and ran 253 tests: zero failures, two existing opt-in
skips. The release app passed resource, Info.plist and codesign checks through
the full verification script. The installed toolchain defaults to `swiftbuild`,
which nests copied resources differently and fails existing resource tests.
Verification therefore used a temporary PATH adapter adding `--build-system native`
to Swift build/test commands; no checks were disabled and project build scripts
were left unchanged. This environment compatibility issue remains separate work.

Live Russian text fitting, popup interactions, VoiceOver and physical-notch
confirmation remain pending.
