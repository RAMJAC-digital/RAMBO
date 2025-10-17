# FCEUX TAS Playback Design (Skeleton)

**Status:** Deferred / Backlog  
**Owner:** Unassigned  
**Purpose:** Placeholder outline for future TAS (FM2) playback feature.

> NOTE: This document intentionally contains high-level scaffolding only. Detailed design to be completed when feature is reprioritized.

## 1. Problem Statement
- Allow RAMBO to consume FCEUX TAS recordings (FM2) and drive controller input deterministically.
- Maintain fidelity with original recordings while preserving emulator determinism guarantees.

## 2. Constraints & Assumptions *(to validate later)*
- Initial scope limited to single-controller FM2 files without binary attachments.
- No live editing, rerecord UI, or multi-track branching in first pass.
- Parsing implemented in Zig; no Python tooling required at runtime.

## 3. Proposed Architecture (Draft)
1. **Parser Layer** – Stream FM2 text, emit normalized metadata + per-frame button timeline. TBD: location under `src/input/tas/`.
2. **Playback Engine** – Manage frame cursor, looping, pauses, and integration with controller mailbox.
3. **Integration Hooks** – CLI/debugger flags to load/unload TAS, handshake with main loop input source selection.

## 4. Open Questions
- How to represent lag frames and sub-frame events from FM2 within current frame-based input system?
- Should TAS playback bypass keyboard input entirely or allow blending?
- Required validation level (ROM checksum, emu version compatibility)?
- Storage format for large TAS files (stream vs. full pre-load)?

## 5. Future Work Items
- Flesh out detailed spec, state diagrams, and test plan.
- Gather sample FM2 corpus and licensing info.
- Coordinate with debugger roadmap for TAS controls (seek, pause, markers).

---
*This outline will be expanded once TAS playback moves off the backlog.*
