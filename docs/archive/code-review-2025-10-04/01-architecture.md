# 01 - Architecture Review

**Date:** 2025-10-03
**Status:** Completed

## 1. Summary

The initial architecture proposed a fully asynchronous, message-passing design for all components of the NES emulator. A thorough multi-agent review identified critical flaws in this approach that would make cycle-accurate emulation impossible.

The key takeaway is that the NES hardware is fundamentally synchronous. The CPU, PPU, and APU are tightly coupled and rely on immediate, predictable access to the system bus. Introducing message-passing latency for core emulation tasks breaks this fundamental requirement.

## 2. The New Hybrid Architecture

The project is now adopting a **hybrid architecture** that combines the best of both synchronous and asynchronous designs:

*   **Synchronous Emulation Core:** The CPU, PPU, APU, and other core components will run in a single, deterministic, single-threaded loop. This ensures cycle-accurate timing and predictable behavior.

*   **Asynchronous I/O Layer:** All I/O operations (input, video, audio, file loading) will be handled by a separate, asynchronous layer, likely using `libxev`. This prevents I/O latency from affecting emulation accuracy and keeps the UI responsive.

This hybrid model is the new standard for the project and all future development should adhere to it.

## 3. Actionable Items

### 3.1. Solidify the Hybrid Architecture

*   **Action:** Formally document the hybrid architecture, including the synchronous emulation core and the asynchronous I/O layer. The document `docs/06-implementation-notes/design-decisions/final-hybrid-architecture.md` is an excellent start and should be considered the primary architectural guide.
*   **Rationale:** A clear architectural document is essential for guiding development and ensuring that all team members are aligned.
*   **Status:** **DONE**. The `final-hybrid-architecture.md` document is comprehensive.

### 3.2. Refactor Existing Code to Fit the Hybrid Model

*   **Action:** Audit the existing codebase and identify any remaining vestiges of the fully asynchronous design. Refactor this code to fit the new hybrid model. This may involve removing message-passing queues, replacing asynchronous calls with direct function calls, and ensuring that the core emulation logic is purely synchronous.
*   **Rationale:** The codebase must be consistent with the new architecture to avoid confusion and bugs.
*   **Status:** **DONE** (Completed in Phases 1-3: commits 1ceb301, 73f9279, 2fba2fa, 2dc78b8)
*   **Completion Notes:**
    *   Phase 1: Bus State/Logic separation established hybrid architecture pattern
    *   Phase 2: PPU State/Logic separation applied consistent pattern
    *   Phase A: Backward compatibility cleanup, ComponentState naming (CpuState/BusState/PpuState)
    *   Phase 3: VTable elimination with comptime duck typing (Mapper.zig, ChrProvider.zig deleted)
    *   All 375 tests passing with new hybrid architecture
    *   See: `docs/code-review/REFACTORING-ROADMAP.md` for implementation details

### 3.3. Supersede Old Architectural Documents

*   **Action:** Mark any documents related to the old, fully asynchronous architecture as "SUPERSEDED". This includes `docs/06-implementation-notes/design-decisions/async-architecture-design.md`.
*   **Rationale:** This will prevent developers from accidentally referencing outdated information.
*   **Status:** **TODO**.
