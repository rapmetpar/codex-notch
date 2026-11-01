---
status: active
contract_ids: [PET-LIBRARY-001, PRIVACY-APP-BUNDLE-040, PRIVACY-BOUNDARY-006]
supersedes: []
owner: project-maintainer
created_at: 2026-11-01
---

# Portable local pet library, separate from rendering and account services

Use a versioned manifest directory selected by the user, not another app's
resources or private storage. The universal app contains no personal atlas,
collection ID, account inventory, network client or authentication integration.
`PetLibraryStore` accepts an injected app-owned root for tests; production uses
Application Support/CodexNotch/PetLibrary. Its Foundation/ImageIO models expose
stable IDs, names, owned URLs, explicit v1/v2 geometry and standard clip timing.
The renderer and scene policy are separate and consume validated descriptors.

A package has manifest.json (schemaVersion 1) and listed PNG/WebP files. Accept
only the documented 8x9 v1 or 8x11 v2 geometry, 192x208 cells, nine standard
clips with exact timings, and 0/16 look directions respectively. Validate MIME,
complete PNG chunks/CRC or WebP RIFF/chunk lengths, full decode, exact
dimensions, single-image count, bounded name/ID fields,
unique IDs/resource paths, manifest <=256 KiB, atlas <=20 MiB, <=64 pets and
<=128 MiB total. ImageIO accepts some truncated PNGs as recovered pixels; explicit container
completion/CRC validation rejects those before any state change. Animated
PNG/WebP containers are rejected independently of decoder image count.
Artistic semantics, clip occupancy and transparent RGB hygiene
are separate export QA; runtime compatibility is not a claim of authoring QA.
Legacy WebP may retain RGB under alpha zero; preserve original encoded bytes.

Descriptor-relative O_NOFOLLOW reads reject symbolic links at every package
path component, unsafe paths, nonregular files and oversized resources before
allocation. Open the validated inode once and copy those bytes, rather than
validating a path and reopening it later. Only manifest-listed atlas bytes and
re-encoded known manifest fields are imported; extra transport/account fields
and unlisted files are discarded. No zip extraction or network URL import.

Validate all inputs before touching the previous library. Write a private UUID
generation and atomically replace the small state.json only after it is fully
written. Failed writes remove the unfinished generation and retain the previous
state. Selection is an app-owned stable ID, never an atlas URL; preserve it on
reimport when present, otherwise turn off. No import enables pets by default.
Corrupt saved state fails closed; UI should display the local error and keep its
last good snapshot or disable the companion. Explicit import can be retried once
the app-owned corrupt state is repaired; it must not follow a corrupted pointer.

Old immutable generations remain valid for a renderer retaining a prior URL;
this avoids deleting an in-use image during import. Automatic generation garbage
collection is deferred; each import is bounded but repeated imports consume disk
until the app-owned library is removed. Store operations are synchronous and must
be serialized by their caller. UI should import on a utility queue and publish
one snapshot on the main actor; no polling, network or credentials are needed.

Rejected: signed transport URLs as identity, runtime collection scraping,
shipping private artwork, decoding a static icon as a sprite atlas, trusting
manifest dimensions without decoding, per-file partial catalog updates, archive
extraction and implicit selection on first import.

Validation: synthetic v1/v2 packages, restart after source deletion, preserved
selection/rename/removal, malformed metadata, traversal, URLs, symlinks, corrupt
state, dimensions, format/truncation, oversize files, duplicate IDs/paths and
unknown-field stripping. An opt-in test imports an explicitly exported personal
package and decodes every original atlas without keeping it in Git. Full verify
checks the existing app; no installed UI/hardware outcome is claimed here.
