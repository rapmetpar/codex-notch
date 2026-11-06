---
status: active
contract_ids: [COMPLETION-SOUND-001, NATIVE-THREAD-ATTENTION-001, SETTINGS-PERSISTENCE-001, PRIVACY-BOUNDARY-006]
supersedes: []
owner: project-maintainer
created_at: 2026-11-06
---

# Optional live completion sound

Use the existing live successful-completion callback, not rendered or native
read state. An independent bounded in-memory identity ledger and monotonic
cooldown suppress repeated events and bursts. The default is off; mute lasts
only until app exit. Preview is an explicit action and works independently of
mute and the opt-in switch. Use a quiet system sound without network access,
speech, or permissions. No audio device must leave monitoring unaffected.

Rejected: history-derived signals, persistent sound event metadata, speech,
notifications, and coupling sound to the animation setting. The mocked sink
cannot establish audibility or volume; target Mac and headphone checks remain
pending.
