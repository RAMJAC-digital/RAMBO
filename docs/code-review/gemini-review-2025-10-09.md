# Code Review: RAMBO Emulator Core

**Review Date:** 2025-10-09
**Reviewer:** Gemini

## 1. Overview

This review covers a significant portion of the RAMBO emulator's source code, focusing on architectural patterns, thread safety, performance, and correctness, with a special emphasis on issues highlighted by the failing test suite.

The overall architecture is strong, employing a clean separation of state and logic, a centralized timing model (`MasterClock`), and a robust, mostly lock-free threading model using mailboxes. The use of comptime generics for the cartridge and mapper system is a high-performance, idiomatic Zig solution.

However, several critical timing and hardware accuracy bugs were identified, primarily related to CPU-PPU interaction, which explain the current test failures. This review prioritizes fixing these correctness issues, followed by suggestions for general improvements.

## 2. Critical Issues & Remediation

These issues are the direct cause of the failing tests and prevent many commercial ROMs from booting or rendering correctly.

### 2.1. PPU: VBlank NMI Race Condition

**Severity:** Blocker

**Problem:** The emulator is susceptible to the classic VBlank NMI race condition. A CPU read of the PPU status register (`$2002`) can clear the VBlank flag *before* the CPU has a chance to process the NMI, causing the interrupt to be missed. This is a common cause for games hanging on a black screen while waiting for VBlank. The failing `ppustatus_polling_test` confirms this bug.

**Location:**
- `src/emulation/State.zig`: `refreshPpuNmiLevel()`
- `src/emulation/Ppu.zig`: `tick()`
- `src/ppu/logic/registers.zig`: `readRegister()` for `$2002`

**Analysis:**
The `refreshPpuNmiLevel` function directly ties the CPU's NMI line to the live `ppu.status.vblank` flag.
```zig
// src/emulation/State.zig
fn refreshPpuNmiLevel(self: *EmulationState) void {
    const active = self.ppu.status.vblank and self.ppu.ctrl.nmi_enable;
    self.ppu_nmi_active = active;
    self.cpu.nmi_line = active;
}
```
When `readRegister()` for `$2002` is called, it immediately sets `state.status.vblank = false`. If this happens after the PPU sets the VBlank flag but before the CPU starts its interrupt sequence, `refreshPpuNmiLevel` will see `vblank` as false and de-assert the NMI line, causing the interrupt to be lost.

**Recommendation:**
The NMI signal must be latched independently of the readable VBlank flag.

1.  **Introduce a dedicated NMI latch flag** in `EmulationState`, e.g., `nmi_latched: bool = false`.
2.  In `EmulationState.applyPpuCycleResult()`, when `result.nmi_signal` is true, set both `cpu.nmi_line = true` and `nmi_latched = true`.
3.  The CPU's interrupt sequence should clear `nmi_latched`.
4.  A `$2002` read should *only* clear `ppu.status.vblank`, not the latched NMI signal.

**Suggested Fix:**

```zig
// In src/emulation/State.zig -> EmulationState
pub const EmulationState = struct {
    // ...
    nmi_latched: bool = false,
    // ...

    fn applyPpuCycleResult(self: *EmulationState, result: PpuCycleResult) void {
        // ...
        if (result.nmi_signal) {
            if (self.ppu.ctrl.nmi_enable and self.ppu.status.vblank) {
                self.nmi_latched = true;
            }
        }
        // ...
    }

    fn stepCpuCycle(self: *EmulationState) CpuCycleResult {
        // At the start of the function, before checking for interrupts
        if (self.nmi_latched) {
            self.cpu.nmi_line = true;
        }
        // ... rest of the function
    }

    // In the CPU interrupt sequence for NMI (src/emulation/cpu/execution.zig)
    // After jumping to the handler, clear the latch.
    // ... in the block for cycle 6 of the interrupt sequence
    state.cpu.pending_interrupt = .none;
    state.nmi_latched = false; // Clear the NMI latch
    break :blk true; // Complete
};
```
*Note: A more robust implementation would involve a multi-stage latch to perfectly emulate the hardware, but this provides a functional fix.*

### 2.2. PPU: Odd Frame Skip Timing Error

**Severity:** High (Causes visual artifacts and timing issues)

**Problem:** The odd frame skip logic in `EmulationState.tick()` is slightly incorrect. It advances the clock *before* checking if a skip is needed, causing the PPU to process dot 0 of scanline 0 on odd frames, which is then skipped, resulting in the clock being at dot 1. The hardware should skip the PPU clock for this dot entirely.

**Location:** `src/emulation/State.zig` -> `tick()`

**Analysis:**
```zig
// src/emulation/State.zig
pub fn tick(self: *EmulationState) void {
    // ...
    self.clock.advance(1); // Advances to (0, 0) on frame boundary

    const skip_odd_frame = self.odd_frame and self.rendering_enabled and
        self.clock.scanline() == 0 and self.clock.dot() == 0;

    if (!skip_odd_frame) {
        // PPU is not ticked, but clock was already advanced.
        // Next tick advances to (0, 1), effectively skipping dot 0 processing
        // but not the cycle itself.
        const ppu_result = self.stepPpuCycle();
        self.applyPpuCycleResult(ppu_result);
    }
    // ...
}
```
The test `state_test.test.EmulationState: odd frame skip when rendering enabled` fails because it correctly expects the clock to advance by two dots in one "skipped" tick, landing on dot 1.

**Recommendation:**
The clock should be advanced *after* the `skip_odd_frame` check. If a skip occurs, advance the clock by an additional cycle within the same tick to correctly simulate the skipped PPU cycle.

**Suggested Fix:**

```zig
// In src/emulation/State.zig -> tick()
pub fn tick(self: *EmulationState) void {
    if (self.debuggerShouldHalt()) {
        return;
    }

    // Check for odd frame skip BEFORE advancing the clock
    const skip_odd_frame = self.odd_frame and self.rendering_enabled and
        self.clock.scanline() == 261 and self.clock.dot() == 340;

    // Always advance by at least one cycle
    self.clock.advance(1);

    // If we just crossed the boundary on an odd frame, skip the first dot
    if (skip_odd_frame) {
        self.clock.advance(1); // Advance an extra cycle to skip dot 0
    }

    const cpu_tick = self.clock.isCpuTick();

    // Process PPU at the new clock position
    const ppu_result = self.stepPpuCycle();
    self.applyPpuCycleResult(ppu_result);

    if (cpu_tick) {
        // ... rest of the function
    }
    // ...
}
```
*Note: This logic is simplified. A more accurate model would check the condition at the end of the pre-render scanline and perform a double-tick if needed.*

## 3. Architecture & Design Review

### 3.1. Timing and Clock Management

**Observation:** The use of a single `MasterClock` based on PPU cycles is an excellent design choice. It prevents state divergence and provides a single source of truth for timing.

**Recommendation:** The name `MasterClock` is accurate, but the user suggested `Emulator`. A more descriptive name might be `SystemClock` to reflect that it drives all components. However, the user also mentioned `MasterClock` could be updated to `Emulator`. Given the context, `Emulator` is too generic. I suggest renaming `MasterClock` to `SystemClock` for clarity. The core principle of "one tick, one cycle" is correctly implemented by having `EmulationState.tick()` advance the clock by one.

**Action:** Rename `MasterClock` to `SystemClock` throughout the codebase.
- File: `src/emulation/MasterClock.zig` -> `src/emulation/SystemClock.zig`
- Struct: `MasterClock` -> `SystemClock`

### 3.2. Threading and Mailboxes

**Observation:** The threading model is robust. The use of `std.atomic` for SPSC queues (`SpscRingBuffer`) and `std.Thread.Mutex` for other mailboxes is appropriate. The `FrameMailbox`'s stack-allocated triple-buffer is a standout feature for RT-safety and performance.

**Recommendation:** The use of `libxev` in `EmulationThread` for timer-based frame pacing is a modern and efficient approach. No issues were found with the current threading or mailbox implementation. It appears to be well-designed and thread-safe.

### 3.3. Memory Management

**Observation:** The project demonstrates careful memory management. The use of `ArenaAllocator` for `Config` and the self-contained memory management within `Cartridge` are good patterns.

**Recommendation:** The use of `std.ArrayListUnmanaged` in `src/snapshot/Snapshot.zig` is acceptable but could be replaced with `std.ArrayList` for improved safety, as the performance difference in this non-hot path is negligible. This is a low-priority cleanup task.

## 4. Code-Level Suggestions

### 4.1. CPU Dispatch Table

**Observation:** The CPU dispatch table in `src/cpu/dispatch.zig` is built at comptime, which is excellent for performance. However, the `buildDispatchTable` function is a large monolith.

**Recommendation:** The file already contains a well-structured plan to refactor this into smaller `build...Opcodes` functions. This plan should be executed to improve maintainability.

**Action:** Refactor `buildDispatchTable` in `src/cpu/dispatch.zig` into smaller, category-based helper functions as outlined in the file's comments.

### 4.2. Zig 0.15.1 Idioms

**Observation:** The code is mostly modern. However, the user mentioned Zig 0.15.1 array APIs. While the current code is valid, some parts could be more idiomatic. For example, loops like `for (array, 0..) |item, i|` are fine, but `for (array) |item|` or `for (array, 0..)` is preferred when the index is not strictly needed.

**Recommendation:** This is a low-priority style improvement. A pass could be made over the codebase to simplify loops where possible, but it is not a functional issue.

## 5. Development Plan

**Priority 1: Fix Blocking Bugs (Emulator Correctness)**

1.  **Implement NMI Latching:** Modify `EmulationState` and its related functions to correctly latch the NMI signal, preventing the VBlank read race condition. This will fix the `ppustatus_polling_test` failures and allow many games to boot.
2.  **Correct Odd Frame Skip:** Adjust the logic in `EmulationState.tick()` to correctly simulate the skipped PPU cycle on odd frames. This will fix the `state_test` failure.
    - Detailed clock-scheduling refactor plan is now documented in `docs/code-review/clock-advance-refactor-plan.md` and must be executed before the VBlank ledger work.

**Priority 2: Architectural Improvements**

3.  **Rename `MasterClock`:** Rename the `MasterClock` struct and file to `SystemClock` for better clarity.
4.  **Refactor CPU Dispatch:** Break down the `buildDispatchTable` function in `src/cpu/dispatch.zig` as planned in the file's comments.

**Priority 3: General Cleanup & Future Work**

5.  **Review `ArrayListUnmanaged`:** Consider replacing `ArrayListUnmanaged` with `std.ArrayList` in non-performance-critical areas like the snapshot system.
6.  **Expand Test Suite:** Add more tests for CPU-PPU interaction and mappers beyond NROM.
7.  **Implement `libxev` for Async File I/O:** As noted in `src/cartridge/loader.zig`, replace synchronous file loading with an async version using `libxev` to avoid blocking the main thread.

This plan addresses the critical test failures first, ensuring the emulator can run a wider range of software correctly, before moving on to architectural and quality-of-life improvements.

## 6. Development Plan: VBlank/NMI Cycle Tracking

> **Prerequisite:** Complete the master-clock scheduling refactor outlined in `docs/code-review/clock-advance-refactor-plan.md` so that `EmulationState.tick()` delegates timing decisions to the new helper.

- **Context** Hardware documentation (nesdev.org `PPU_frame_timing`, `Ppu.svg`, Eric Morgan’s quick-start) confirms VBlank asserts across scanlines 241.1–260.340 and deasserts at 261.1; a CPU `BIT`/`LDA` read sees the status byte on its fourth cycle, so a `$2002` poll fired on the exact set cycle invariably clears VBlank before the CPU samples it, masking the NMI edge. The PPU drives `/NMI` low only when `vblank_flag` **and** the NMI output flip-flop (`PPUCTRL.7`) are simultaneously true, meaning software can generate multiple edges inside one VBlank by toggling bit 7 without reading `$2002`.
- **Objective** Replace boolean latching with a master-clock timestamp ledger so level and edge decisions are derived deterministically from recorded cycles while staying within the architecture’s "pure logic + explicit state" boundaries.
- **Intent** Deliver commercial-ROM compatibility by eliminating the race, surface precise timing in tooling (digital-oscilloscope posture), and maintain a clean split between state mutation sites (`EmulationState`, bus) and pure helpers (`CpuLogic`, `PpuLogic`).
- **Constraints** No cross-component hidden state; only `EmulationState` may touch shared timing, timestamps must be monotonic `MasterClock` values, and public APIs remain allocation-free on the hot path.

### Implementation Steps

1. **Establish Baseline Signals** Instrument the failing suites (`zig build test-integration`, `tests/ppu/ppustatus_polling_test.zig`, `tests/integration/cpu_ppu_integration_test.zig`, commercial ROM harness) to capture existing `clock.ppu_cycles`, NMI line transitions, and `$2002` read cadence for regression comparison.
2. **Introduce Timing Ledger** Extend `EmulationState` with a `VBlankWindow` struct that keeps explicit booleans and cycle stamps, for example:

   ```zig
   const VBlankWindow = struct {
       // live state
       span_active: bool = false,
       ctrl_high: bool = false,
       nmi_edge_pending: bool = false,
       cpu_ack_pending: bool = false,

       // timestamps (MasterClock cycles)
       last_set_cycle: u64 = 0,
       last_clear_cycle: u64 = 0,
       last_status_read_cycle: u64 = 0,
       last_ctrl_toggle_cycle: u64 = 0,
       last_cpu_ack_cycle: u64 = 0,
   };
   ```

   Helper methods stamp these fields as events occur; document invariants (e.g., `span_active` implies `last_set_cycle >= last_clear_cycle`).
3. **Stamp PPU Events** Update `applyPpuCycleResult()` to set `last_set_cycle` when `result.nmi_signal` is true and `last_clear_cycle` when `result.vblank_clear` fires; ensure `$2000` writes that toggle `nmi_enable` record `last_ctrl_toggle_cycle` and call a new `recomputeNmiLine()` so multiple toggles in one VBlank produce the expected number of edges without relying on `ppu.status.vblank`.
4. **Track Status Reads** Route `$2002` bus reads through a small side-effect shim (`handlePpuStatusRead()`) that records `last_status_read_cycle` using `clock.ppu_cycles` on the *fourth CPU sub-cycle* (three PPU ticks after the read begins) so timing matches 6502 behavior without polluting `PpuLogic.readRegister()`.
5. **Compute NMI Line Deterministically** Replace `nmi_latched` usage with a pure function `deriveNmiLevel(window, clock)` that keeps the line asserted while `window.ctrl_high` is true, the current cycle is within the recorded VBlank span, and `window.cpu_ack_pending` is false; base decisions solely on the struct’s timestamps so the CPU sees the same edge profile regardless of direct `ppu.status.vblank` reads.
6. **Ack During Interrupt Sequence** When the CPU finishes cycle 6 of the NMI hardware sequence (`cpu/execution.zig:160`), set `last_status_read_cycle` (or a new `last_cpu_ack_cycle`) to the current master cycle so the ledger reflects that the interrupt is in flight even if the handler never reads `$2002`.
7. **Expose Oscilloscope Hooks** Add optional debug capture (behind a comptime flag) that streams `{scanline, dot, vblank, nmi_line, status_read_pending}` samples for waveform visualization, aligning with the "digital oscilloscope" goal without impacting release builds.
8. **Regression & Expansion** Re-run full matrices (`zig build test`, mapper-specific suites, AccuracyCoin traces) and add targeted tests that assert the new timing math: repeated `$2002` polls within one scanline still see VBlank, enabling NMI mid-VBlank after a poll retriggers correctly, and no stale NMI persists past `last_clear_cycle`.

### Validation & Tooling

- **Unit Tests** Extend `tests/ppu/vblank_nmi_timing_test.zig` and `tests/integration/cpu_ppu_integration_test.zig` with cycle-count assertions verifying ledger values alongside observable flags.
- **Property Checks** Add fuzz-style harnesses that randomize poll intervals during VBlank to ensure `deriveNmiLevel` never oscillates outside hardware spec.
- **Documentation** Author a new `docs/implementation/ppu-nmi-latching.md` detailing the timing ledger’s invariants, including diagrams keyed to master-clock positions for future maintainers and explicit coverage of `/NMI` toggling without `$2002` reads.

### Open Questions & Risks

- **CPU Acknowledge Semantics** Confirm whether hardware relies solely on `$2002` read to clear the interrupt, or if the act of starting the NMI sequence implicitly acknowledges; align ledger updates with verified behavior before coding.
- **Mapper Side Effects** Audit MMC3 and other IRQ logic to ensure `last_set_cycle` updates do not disrupt existing A12 edge tracking or frame IRQ cadence; current repository ships only mapper 0 (NROM), but the ledger must be designed to coexist with future mapper IRQs.
- **DMA/OAM Interactions** Double-check that the current OAM DMA (`src/emulation/dma/logic.zig`) cannot trample the new timing ledger, and validate DMC DMA stalls continue to respect `$2002` side effects when repeated reads occur during the stall window.
- **Threaded Front-End** No mailbox changes required; NMI handling remains confined to `EmulationState.tick()` and the existing frame/command mailboxes already operate at frame granularity.
