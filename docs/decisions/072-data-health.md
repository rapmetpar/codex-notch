---
status: active
contract_ids: [DATA-HEALTH-001, PRIVACY-BOUNDARY-006, NATIVE-THREAD-ATTENTION-001, LOCALIZATION-001, SETTINGS-WINDOW-022]
supersedes: []
owner: project-maintainer
created_at: 2026-11-06
---

# Explain source freshness in a separate window

A failed usage request keeps the last successful quota. Without a timestamp or
failure cue the user cannot distinguish it from a fresh value. Add an explicit
Data Status action in General Settings that opens one reusable, normal window.
Keep the notch layout, preferences and existing navigation unchanged.

The window contains three independent rows: quota, local task monitoring and
native read metadata. Expose only idle/loading/fresh/stale/unavailable states,
last successful check times and fixed localized explanations. Never retain or
display errors, responses, paths, identities, thread IDs or authentication data.
Native metadata availability does not mean a particular answer has been read.
An absent native source still clears native evidence, never fabricating Viewed.
With no completed chats to look up, native monitoring is idle, not failed.

Quota requests are single-flight with at least ten seconds between attempts,
including explicit retries and foreground refreshes. Automatic refresh remains
sixty seconds, including after failure. Cancellation invalidates the request ID
before another generation can start. Ignore late results, keep the last good
snapshot on failure, and never synthesize a zero. Retry only requests quota;
local monitors retain their existing recovery intervals and file-read bounds.
Open Codex uses the existing navigator.

An otherwise successful row becomes stale after two missed quota intervals
(120 seconds), three rollout recovery intervals (15 seconds), or three native
read intervals (6 seconds). These are observation-age limits, not service latency
guarantees. The existing runtime clock updates the window; no new polling timer
or persistence is added. A successful rollout scan means the selected files were
readable, including an empty directory; it does not promise FSEvents delivery.

Rejected: an error badge in the compact quota (unapproved layout), resetting quota
to zero on failure, exposing raw errors, faster automatic retries, or inferring
read receipts from health. Consequences: extra additive Settings entry and small
monitor health callbacks; source-loss and generation guards are mandatory.

L2 acceptance: synthetic success/failure/recovery, retry throttling and cancellation,
local source loss and recovery, preserved Running/read semantics, three-language
copy, full test/build/bundle verification. Real Mac acceptance remains pending:
open/close/reopen, keyboard and VoiceOver, all languages, notch/floating geometry,
motion settings and a synthetic offline case. Do not install or restart the user's
app to infer this acceptance.
