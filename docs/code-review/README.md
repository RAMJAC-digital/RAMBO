# RAMBO Code Review Hub - 2025-10-05

**Status:** 🔴 **CRITICAL** - Active Bug Fixes & Test Restoration In Progress.

## 1. Overview

This directory contains the complete and up-to-date code review analysis of the RAMBO project as of 2025-10-05.

A deep review has revealed a **critical situation** that halts all new feature development (including the video subsystem). While the project's "pure functional" CPU architecture is sound, a major refactoring effort led to two critical issues:

1.  **Critical Bug:** The `SBC` (Subtract with Carry) instruction was implemented incorrectly, producing wrong results for all subtraction operations. **This bug has been fixed.**
2.  **Critical Test Regression:** 166 opcode-specific unit tests were deleted and not migrated during the refactoring, leaving the CPU's core logic almost entirely unverified at a unit level.

The immediate and sole priority of the project is to restore full test coverage for the CPU to ensure correctness and prevent future bugs.

## 2. Primary Planning Document

All outstanding tasks are consolidated into a single, authoritative planning document. This plan supersedes all previous cleanup plans.

*   **[STATUS.md](./STATUS.md):** The prioritized roadmap for fixing all critical issues and addressing remaining cleanup tasks.

## 3. Code Review Status Summary

*   **Architecture:** ✅ **Excellent.** The core State/Logic separation and pure functional CPU patterns are well-designed and robust.
*   **CPU Implementation:** 🔴 **Critical.** The `SBC` bug, while now fixed, highlights the danger of the missing tests. 4 opcodes (JSR, RTS, RTI, BRK) are still unimplemented.
*   **Testing:** 🔴 **Critical.** The deletion of 166 unit tests is a major regression. The remaining integration tests are insufficient to guarantee correctness, as proven by the `SBC` bug. A full test restoration effort is mandatory.
*   **PPU & Bus:** 🟡 **Good, but with pending tasks.** The PPU and Bus systems are functional but have several important `TODO` items required for full accuracy (e.g., DMA timing, four-screen mirroring).
*   **Configuration & Async I/O:** ✅ **Good.** The configuration parser and async I/O architecture are sound foundations for future work.

## 4. Detailed Review Documents

*   **[STATUS.md](./STATUS.md):** Master action plan.
*   **[CPU.md](./CPU.md):** Detailed analysis of the CPU implementation.
*   **[TESTING.md](./TESTING.md):** Report on the test regression and restoration plan.
*   **[PPU.md](./PPU.md):** Review of the PPU.
*   **[MEMORY_AND_BUS.md](./MEMORY_AND_BUS.md):** Analysis of the memory bus.
*   **[ASYNC_AND_IO.md](./ASYNC_AND_IO.md):** Review of the threading and I/O architecture.
*   **[CONFIGURATION.md](./CONFIGURATION.md):** Findings on the configuration system.
*   **[CODE_SAFETY.md](./CODE_SAFETY.md):** General code quality and best practices.
