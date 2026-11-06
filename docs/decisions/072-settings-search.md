---
status: active
contract_ids: [SETTINGS-SEARCH-001, SETTINGS-WINDOW-022, SETTINGS-PERSISTENCE-001, SETTINGS-TEXT-023, LOCALIZATION-001, APP-LOGIN-001]
supersedes: []
owner: project-maintainer
created_at: 2026-11-06
---

# Find settings through static metadata and navigate to the original control

The four Settings tabs contain infrequently used choices. A local search field
above the existing tabs finds labels and synonyms in English, Russian and
Simplified Chinese. This addresses a code-level discoverability gap; improved
user search speed has not been measured.

`SettingsSearchID` is the typed registry and tab destination. Its inputs are
compile-time copy only, never current preference values, filenames, signatures,
pet names or runtime services. Every query term must match, after case, diacritic
and width folding. Results retain registry order and show labels in the current
interface language. Matching all three languages permits finding a choice even
before changing the UI language. Empty/whitespace queries show no results.

`SettingsSearchState` holds only the query, tab and transient navigation request.
Return in the native field selects the first match; keyboard users can also tab
to a result button. Escape clears results, or leaves the empty search field.
Result selection closes the overlay, switches the tab and emits a fresh request
so selecting the same control later scrolls again. The existing Form uses a
ScrollViewReader and a typed target modifier to scroll, highlight and request
keyboard/VoiceOver focus. It never calls the target's action. No window activation
or front-order call is added. A pending navigation task checks cancellation before
moving focus; normal typing remains with the native text field and input method.

Conditional image import, color picker and signature text lead to the existing
controlling choice. Search does not enable custom artwork/color or change the
floating style merely to reveal a field. Existing controls and bindings remain
in their original sections; the window remains 560×580. The search results are a
bounded overlay with wrapping labels and native scrolling. The query has no
storage key, network request or logging path and is discarded on disappearance.

Rejected: duplicated controls in results (two editing surfaces); indexing live
values (unnecessary privacy exposure); changing preferences to expose hidden
controls; rebuilding Settings or rearranging tabs; activation when navigating
(a regression risk for native popup tracking).

L2 validation includes search/navigation outcomes in all languages, negative
queries and unchanged synthetic preferences, and a hosted native UI guard for
the real companion import target using an isolated empty library. Full tests,
contract validation and app verification are required. Real keyboard/VoiceOver,
Chinese IME candidate confirmation, popup tracking after navigation, long Russian
labels and physical-notch appearance remain hardware acceptance; automated hosted
views cannot establish those outcomes. No installation or release is part of this
change.
