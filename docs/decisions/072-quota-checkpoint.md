---
status: active
contract_ids: [QUOTA-CHECKPOINT-001]
supersedes: []
owner: project-maintainer
created_at: 2026-11-06
---

# Compare quota in a session-only window

A separate menu window captures one in-memory snapshot and independently compares
5-hour and weekly remaining values. It uses existing refreshes, rejects failed or
more than 120-second-old readings and requires the same ID, kind and future reset.
An increase or reset cannot be interpreted as consumption. Stop clears all state.
The compact and expanded notch remain unchanged. English, Russian and Simplified
Chinese describe percentage-point change without attributing it to a task.

Persistent history, extra polling and additional notch rows were rejected: they
extend data retention, network activity or the approved surface. The freshness
threshold is a conservative two refresh intervals, not a server guarantee.
Tests cover matching and invalid windows, failures, age and clearing. Real-window
legibility, menu access and VoiceOver remain to be checked on hardware.
