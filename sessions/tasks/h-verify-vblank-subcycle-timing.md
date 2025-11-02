---
name: h-verify-vblank-subcycle-timing
branch: none
status: pending
created: 2025-11-02
---

# Verify VBlank Sub-Cycle Timing Implementation

## Problem/Goal

Verify that RAMBO's CPU/PPU sub-cycle execution order matches hardware behavior and Mesen2's reference implementation. The critical timing race condition occurs at scanline 241, dot 1 when CPU reads $2002 (PPUSTATUS) at the exact same PPU cycle that VBlank is set. Hardware executes CPU memory operations BEFORE PPU flag updates within that cycle.

**Current Implementation (LOCKED):** `src/emulation/State.zig:tick()` lines 617-699
- CPU executes (including $2002 reads)
- PPU flag updates happen AFTER CPU execution

**Verification Goal:** Confirm this ordering matches Mesen2's implementation and hardware specification.

## Success Criteria
- [ ] **Mesen2 sub-cycle order analyzed** - Read Mesen2's `Core/NES/NesPpu.cpp` and `NesCpu.cpp` to understand when VBlank flag is set relative to CPU $2002 reads
- [ ] **RAMBO ordering verified against Mesen2** - Confirm RAMBO's execution order (CPU step → applyPpuCycleResult) matches Mesen2's pattern
- [ ] **Race condition handling compared** - Verify how Mesen2 handles scanline 241, dot 1 same-cycle reads vs. RAMBO's approach
- [ ] **Hardware citations cross-referenced** - Confirm both implementations match nesdev.org PPU frame timing specification
- [ ] **Debug logging verification** - Add temporary debug logging to verify race detection at scanline 241, dot 1 works as expected
- [ ] **Test semantics documented** - Document `seekTo()` positioning behavior and relationship to hardware "same-cycle" concept
- [ ] **Findings documented in Work Log** - Document comparison results, any discrepancies found, and confirmation of correctness

## Context Manifest

### Hardware Specification: CPU/PPU Sub-Cycle Execution Order

**CRITICAL HARDWARE TIMING:** The NES executes CPU and PPU operations within the same cycle in a specific order.

According to the NES hardware documentation (https://www.nesdev.org/wiki/PPU_frame_timing), when both CPU and PPU operate during the same PPU cycle, the hardware executes operations in this sequence:

1. **CPU Read Operations** (if CPU is active this cycle)
2. **CPU Write Operations** (if CPU is active this cycle)
3. **PPU Events** (VBlank flag set, sprite evaluation, etc.)
4. **End of cycle**

**Critical Race Condition - Scanline 241, Dot 1:**

VBlank flag is set by the PPU at scanline 241, dot 1. If the CPU reads PPUSTATUS ($2002) at **exactly the same PPU cycle**, the hardware sub-cycle ordering means:
- CPU read executes FIRST (reads VBlank bit = 0, flag not set yet)
- PPU sets VBlank flag SECOND (after CPU has already read)
- **Result:** CPU misses seeing the VBlank flag (same-cycle race)
- **Side Effect:** NMI is suppressed for this VBlank period

**Why This Matters:**

Games exploit this timing for synchronization. AccuracyCoin test ROM (verified on real hardware) tests this exact race condition. Any deviation from hardware ordering causes games to malfunction.

**Hardware Citations:**
- Primary: https://www.nesdev.org/wiki/PPU_frame_timing
- VBlank timing: https://www.nesdev.org/wiki/PPU_registers#PPUSTATUS (bit 7 behavior)
- NMI suppression: https://www.nesdev.org/wiki/NMI (race condition section)

---

### RAMBO's Current Implementation

**LOCKED IMPLEMENTATION - DO NOT MODIFY WITHOUT VERIFICATION**

RAMBO implements this sub-cycle ordering in `src/emulation/State.zig:tick()` (lines 617-699).

**Execution Flow Within Single PPU Cycle:**

File: `src/emulation/State.zig`

```zig
pub fn tick(self: *EmulationState) void {
    // Lines 617-646: PPU rendering executes FIRST
    const scanline = self.clock.scanline();
    const dot = self.clock.dot();
    var ppu_result = self.stepPpuCycle(scanline, dot);  // PPU PROCESSES but doesn't update flags yet

    // Lines 656-692: CPU memory operations execute SECOND
    if (step.cpu_tick) {
        // CPU executes including $2002 reads
        // busRead() at line 268 handles race detection
        _ = self.stepCpuCycle();
    }

    // Lines 694-698: PPU flag updates execute LAST (AFTER CPU)
    self.applyPpuCycleResult(ppu_result);  // VBlank timestamps set HERE
}
```

**Key Implementation Details:**

1. **PPU Result Buffering** (lines 646-653):
   - `stepPpuCycle()` returns a `PpuCycleResult` struct
   - Contains signals: `nmi_signal`, `nmi_clear`, `vblank_clear`
   - Flags NOT applied immediately - held until after CPU executes

2. **CPU Execution** (lines 676-692):
   - CPU executes BEFORE `applyPpuCycleResult()`
   - CPU reads $2002 via `busRead()` at line 268
   - Race detection happens during CPU execution (lines 288-319)

3. **Race Detection** (`busRead()` lines 288-319):
   ```zig
   if (is_status_read) {
       // Same-cycle read: CPU reading at exact cycle VBlank will be set
       if (scanline == 241 and dot == 1) {
           // Record race for NMI suppression tracking
           const vblank_set_cycle = self.clock.ppu_cycles;
           self.vblank_ledger.last_race_cycle = vblank_set_cycle;
       }
   }
   ```

4. **VBlank Ledger Timestamp Update** (line 698):
   ```zig
   fn applyPpuCycleResult(self: *EmulationState, result: PpuCycleResult) void {
       if (result.nmi_signal) {
           // VBlank timestamps set AFTER CPU has executed
           self.vblank_ledger.last_set_cycle = self.clock.ppu_cycles;
       }
   }
   ```

**Critical Insight:** The VBlank flag becomes "visible" to subsequent reads AFTER `applyPpuCycleResult()` completes, but CPU memory operations during the SAME tick see the OLD state. This matches hardware behavior.

**Related Files:**

- `src/emulation/State.zig:617-699` - Main tick loop (LOCKED)
- `src/emulation/State.zig:268-367` - busRead() with race detection
- `src/emulation/State.zig:701-750` - applyPpuCycleResult()
- `src/emulation/VBlankLedger.zig` - VBlank timestamp tracking (pure data)
- `src/ppu/logic/registers.zig:54-175` - readRegister() builds PPUSTATUS byte

---

### Mesen2 Reference Implementation

**Purpose:** Verify RAMBO's ordering matches Mesen2's proven implementation.

**Mesen2 Files to Examine:**

1. **PPU Execution Entry Point:**
   - File: `/home/colin/Development/Mesen2/Core/NES/NesPpu.cpp`
   - Function: `template<class T> void NesPpu<T>::Exec()` (line 1331)
   - Key behavior: Increments cycle counter FIRST, then processes events

2. **VBlank Flag Set Logic:**
   - File: `/home/colin/Development/Mesen2/Core/NES/NesPpu.cpp`
   - Lines 1339-1344:
   ```cpp
   if(_cycle == 1 && _scanline == _nmiScanline) {
       if(!_preventVblFlag) {
           _statusFlags.VerticalBlank = true;
           BeginVBlank();  // Sets NMI flag
       }
       _preventVblFlag = false;
   }
   ```

3. **PPUSTATUS ($2002) Read Handling:**
   - File: `/home/colin/Development/Mesen2/Core/NES/NesPpu.cpp`
   - Function: `template<class T> uint8_t NesPpu<T>::ReadRam(uint16_t addr)` (line 332)
   - Lines 337-348:
   ```cpp
   case PpuRegisters::Status:
       _writeToggle = false;
       returnValue = (
           ((uint8_t)_statusFlags.SpriteOverflow << 5) |
           ((uint8_t)_statusFlags.Sprite0Hit << 6) |
           ((uint8_t)_statusFlags.VerticalBlank << 7)
       );
       UpdateStatusFlag();  // Clears VBlank flag and sets _preventVblFlag
   ```

4. **Race Condition Prevention:**
   - File: `/home/colin/Development/Mesen2/Core/NES/NesPpu.cpp`
   - Function: `template<class T> void NesPpu<T>::UpdateStatusFlag()` (line 585)
   - Lines 590-593:
   ```cpp
   if(_scanline == _nmiScanline && _cycle == 0) {
       //"Reading one PPU clock before reads it as clear and never sets the flag or generates NMI for that frame."
       _preventVblFlag = true;
   }
   ```
   - **NOTE:** Mesen2 checks cycle == 0, not cycle == 1!

5. **CPU/PPU Coordination:**
   - File: `/home/colin/Development/Mesen2/Core/NES/NesPpu.cpp`
   - Line 1365: `_emu->ProcessPpuCycle<CpuType::Nes>();`
   - This calls back to emulator AFTER PPU processes its cycle
   - File: `/home/colin/Development/Mesen2/Core/Shared/Emulator.h`
   - Line 309: `template<CpuType type> __forceinline void ProcessPpuCycle()`

**Key Questions for Verification:**

1. **Cycle Increment Timing:** When does Mesen2 increment `_cycle`?
   - Line 1335: `_cycle++;` BEFORE processing VBlank check
   - This means at scanline 241, cycle is incremented TO 1, THEN VBlank is set
   - Compare to RAMBO: Does RAMBO process VBlank AFTER or BEFORE clock advance?

2. **CPU Execution Relative to PPU Flag Updates:**
   - When does CPU execute relative to `_statusFlags.VerticalBlank = true`?
   - Does `ProcessPpuCycle()` execute CPU BEFORE or AFTER VBlank flag set?

3. **Race Detection Differences:**
   - Mesen2 checks `_cycle == 0` (line 590)
   - RAMBO checks `dot == 1` (State.zig line 301)
   - Which is correct for same-cycle race?

---

### Test Infrastructure

**AccuracyCoin Test - VBlank Beginning:**

File: `tests/integration/accuracy/vblank_beginning_test.zig`

**Test Purpose:** Verifies VBlank flag timing at scanline 241, dot 1 using AccuracyCoin ROM.

**Test Flow:**
1. Boot to AccuracyCoin main menu (helper: `bootToMainMenu()`)
2. Setup PPU timing suite (helper: `setupPpuTimingSuite()`)
3. Run VBlank beginning test via ROM's RunTest function
4. Check result byte at $0450 (0x00 = PASS)

**Helper Functions (tests/integration/accuracy/helpers.zig):**

- `bootToMainMenu(h: *Harness)` - Runs ROM initialization (~20M cycles)
- `setupPpuTimingSuite(h: *Harness)` - Parses suite table, populates ZP arrays
- `runPpuTimingTest(h: *Harness, which: PpuTimingTest)` - Executes specific test
- `decodeResult(raw: u8)` - Decodes result byte (status bits + error code)

**Test Harness Helper - seekTo():**

File: `src/test/Harness.zig`

```zig
pub fn seekTo(self: *Harness, target_scanline: u16, target_dot: u16) void {
    while (self.state.clock.scanline() != target_scanline or
           self.state.clock.dot() != target_dot) {
        self.state.tick();  // Tick until position reached
    }
}
```

**CRITICAL UNDERSTANDING:** `seekTo()` behavior:
- Ticks UNTIL scanline/dot match
- After `seekTo(241, 1)` completes, emulator is AT position (241, 1)
- Clock has advanced, `tick()` has completed, `applyPpuCycleResult()` has run
- VBlank flag IS visible because tick completed
- To test "same-cycle" race, CPU must read DURING the tick, not after

**VBlank Ledger Tests:**

File: `tests/emulation/state/vblank_ledger_test.zig`

Key tests:
- Line 23: "Flag is set at scanline 241, dot 1"
- Line 47: "First read clears flag, subsequent read sees cleared"
- Line 67: "Flag is cleared at scanline 261, dot 1"
- Line 90: "Race condition - read on same cycle as set"

**Helper Function:**
```zig
fn isVBlankSet(h: *Harness) bool {
    const status_byte = h.state.busRead(0x2002);
    return (status_byte & 0x80) != 0;
}
```

---

### Verification Approach

**Recommended Steps:**

1. **Analyze Mesen2 Cycle Ordering:**
   - Trace `NesPpu::Exec()` → `ProcessPpuCycle()` → CPU execution
   - Determine: Does CPU execute BEFORE or AFTER `_statusFlags.VerticalBlank = true`?
   - Document exact sequence with line numbers

2. **Compare to RAMBO Ordering:**
   - RAMBO: `stepPpuCycle()` → `stepCpuCycle()` → `applyPpuCycleResult()`
   - Mesen2: `_cycle++` → VBlank check → `ProcessPpuCycle()`
   - Are they equivalent?

3. **Cycle == 0 vs Dot == 1 Mystery:**
   - Mesen2 checks `_cycle == 0` for race prevention (line 590)
   - But sets VBlank at `_cycle == 1` (line 1339)
   - Reconcile: Does Mesen2 increment cycle BEFORE or AFTER event checks?

4. **Debug Logging Verification (Optional):**
   - Add temporary logging to RAMBO's `tick()` at scanline 241, dot 1
   - Log: Clock position, VBlank flag state before/after `applyPpuCycleResult()`
   - Verify flag updates AFTER CPU execution

5. **Test Semantics Documentation:**
   - Document `seekTo()` postcondition clearly
   - Explain difference between:
     - Reading DURING tick (same-cycle race)
     - Reading AFTER tick completes (flag visible)

**Files to Modify (Documentation Only):**

- This task file (Context Manifest section) - Add findings
- `src/emulation/State.zig` - Add Mesen2 comparison comments if helpful
- Consider adding nesdev.org citation comments to reinforce correctness

**Expected Outcome:**

Either:
- **CONFIRMED:** RAMBO's ordering matches Mesen2 and hardware spec → Document confirmation
- **DISCREPANCY FOUND:** Identify exact difference → File new task to investigate

---

### State/Logic Separation (Not Applicable)

This is a **verification task**, not an implementation task. No State.zig or Logic.zig changes required.

**Components Involved:**
- `EmulationState` (orchestration) - READ ONLY
- `VBlankLedger` (pure data) - READ ONLY
- `MasterClock` (timing) - READ ONLY
- PPU register logic (read handling) - READ ONLY

**Verification Focus:** Understanding existing architecture, not modifying it.

---

### Hardware References Summary

**Primary Citations:**
- PPU frame timing: https://www.nesdev.org/wiki/PPU_frame_timing
- PPUSTATUS register: https://www.nesdev.org/wiki/PPU_registers#PPUSTATUS
- NMI behavior: https://www.nesdev.org/wiki/NMI
- Sub-cycle execution: Inferred from hardware behavior documented across nesdev.org

**AccuracyCoin Test ROM:**
- Verified on real NES hardware
- Tests exact cycle timing of VBlank flag
- Result: PASS requires correct sub-cycle ordering

**Mesen2 Reference:**
- Proven accurate emulator (used as reference by emulation community)
- Source available at /home/colin/Development/Mesen2/Core/NES/
- Well-documented code with hardware behavior comments

## User Notes
<!-- Any specific notes or requirements from the developer -->

## Work Log
<!-- Updated as work progresses -->
- [YYYY-MM-DD] Started task, initial research
