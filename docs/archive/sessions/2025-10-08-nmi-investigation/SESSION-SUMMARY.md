# Session Summary: NMI Interrupt Investigation

**Date:** 2025-10-08
**Duration:** ~4 hours
**Focus:** Commercial ROM blank screen investigation
**Status:** 🔴 **CRITICAL ISSUE DISCOVERED**

---

## Objectives

1. ✅ Investigate why commercial ROMs display blank screens while test ROMs work
2. ✅ Create integration tests for commercial ROM validation
3. ✅ Build framebuffer validation infrastructure
4. ✅ Identify root cause of rendering failures

---

## Key Discoveries

### Primary Finding: NMI Interrupts Not Implemented

**SHOWSTOPPER BUG DISCOVERED:**

All commercial games hang because **NMI interrupt handling is completely missing** from the CPU emulation. The interrupt states are defined in the `ExecutionState` enum but have **zero implementation** in `stepCpuCycle()`.

**Impact:**
- ✅ Test ROMs work (they don't rely on NMI timing)
- ❌ ALL commercial games hang in initialization loops
- ❌ Games never progress past power-on sequence
- ❌ No title screens, no gameplay

### Investigation Process

**Hypothesis 1: PPU Not Rendering**
- ❌ INCORRECT: PPU rendering pipeline works correctly
- Finding: Games output backdrop color (palette index 0) when rendering disabled
- All 61,440 pixels filled (non-zero if backdrop != black)

**Hypothesis 2: PPUMASK Not Enabled**
- ⚠️ PARTIALLY CORRECT: Games set PPUMASK to initialization values only
- Mario: $06 (leftmost 8 pixels only)
- Donkey Kong: $06
- BurgerTime: $00 (all rendering disabled)
- AccuracyCoin: $1E (full rendering enabled)

**Hypothesis 3: PPU Warm-Up Period**
- ⚠️ PARTIALLY CORRECT: Tests incorrectly called `reset()`
- Fix: Power-on initialization without `reset()` preserves warm-up requirement
- Result: Early PPU register writes now correctly ignored

**Hypothesis 4: VBlank Not Setting**
- ❌ INCORRECT: VBlank sets correctly at scanline 241, dot 1
- Clears at scanline 261, dot 1 (hardware behavior)
- Test was checking after frame completion (correct behavior)

**Hypothesis 5: NMI Not Firing**
- ✅ **ROOT CAUSE IDENTIFIED:**
  - PPU VBlank sets correctly ✅
  - assert_nmi set correctly ✅
  - cpu.nmi_line asserted ✅
  - Edge detection works ✅
  - pending_interrupt = .nmi ✅
  - startInterruptSequence() called ✅
  - **BUT NO CODE TO EXECUTE THE INTERRUPT** ❌

---

## Diagnostic Trace Added

Comprehensive debug output at every pipeline stage:

1. **PPU VBlank Set:** `[PPU] VBlank set at scanline 241, dot 1`
2. **Emulation NMI Assert:** `[EMU] NMI asserted! Setting cpu.nmi_line=true`
3. **CPU Edge Detection:** `[CPU] NMI edge detected! Setting pending_interrupt=.nmi`
4. **Interrupt Sequence Start:** `[CPU] Starting interrupt sequence: .nmi`
5. **Execution:** ❌ CPU stuck in `.interrupt_dummy` state forever

---

## Work Completed

### Infrastructure Created

1. **FramebufferValidator Helper** (`tests/helpers/FramebufferValidator.zig`)
   - Pixel counting utilities
   - Framebuffer hashing (CRC32)
   - Diff comparison functions
   - PPM export for visual debugging
   - 10 unit tests passing

2. **Commercial ROM Integration Tests** (`tests/integration/commercial_rom_test.zig`)
   - End-to-end ROM loading
   - Framebuffer validation
   - PPU register tracking
   - NMI execution detection
   - 6 test cases created (currently failing)

### Tests Created

```zig
test "Commercial ROM: AccuracyCoin.nes (baseline validation)"
test "Commercial ROM: Super Mario Bros - loads without crash"
test "Commercial ROM: Super Mario Bros - enables rendering"
test "Commercial ROM: Super Mario Bros - renders graphics"
test "Commercial ROM: Donkey Kong - enables rendering"
test "Commercial ROM: BurgerTime - enables rendering"
test "Commercial ROM: Bomberman - renders something"
```

**Current Status:** All fail due to missing NMI implementation

### Debug Output Added

**Files modified for diagnostics:**
- `src/ppu/Logic.zig` - PPUCTRL/PPUMASK write tracking
- `src/emulation/State.zig` - NMI assertion tracking
- `src/emulation/Ppu.zig` - VBlank set tracking
- `src/cpu/Logic.zig` - NMI edge detection tracking

**Cleanup Required:** Remove all debug output before committing

---

## Technical Analysis

### Missing Implementation Details

**Location:** `src/emulation/State.zig:stepCpuCycle()`

**Current Behavior:**
```zig
if (self.cpu.pending_interrupt != .none) {
    CpuLogic.startInterruptSequence(&self.cpu);  // Sets state to .interrupt_dummy
    return;  // ← CPU STUCK HERE FOREVER
}
```

**Required Implementation:** 7-cycle interrupt sequence

1. **Cycle 1:** Dummy read at current PC
2. **Cycle 2:** Push PCH to stack ($0100 + SP)
3. **Cycle 3:** Push PCL to stack
4. **Cycle 4:** Push P register to stack (with B flag handling)
5. **Cycle 5:** Fetch interrupt vector low byte ($FFFA for NMI, $FFFE for IRQ/BRK)
6. **Cycle 6:** Fetch interrupt vector high byte
7. **Cycle 7:** Jump to handler (PC = vector address)

**Complexity:** Medium
- Similar to RTS/RTI handling already implemented
- Stack push/pull logic exists
- Need to differentiate NMI/IRQ/BRK (vector addresses, B flag)

**Estimated Effort:** 4-6 hours

---

## Test Results

### FramebufferValidator Tests
```
✅ 10/10 tests passing (100%)
```

### Commercial ROM Tests
```
❌ 0/6 tests passing (0% - blocked on NMI implementation)
```

**Diagnostic Output:**
```
Mario 1:
  Frame 60:  PPUCTRL=$90, PPUMASK=$06, NMI executed=0, PC=$8057
  Frame 180: PPUCTRL=$90, PPUMASK=$06, NMI executed=0, PC=$8057
  ↑ Stuck in infinite loop waiting for NMI
```

### Existing Test Suite
```
✅ 896/900 tests passing (99.6%)
  ❌ 3 timing-sensitive threading tests
  ⏭️ 1 skipped test
```

**No regressions** - all previously passing tests still pass.

---

## Files Modified

### New Files Created (2)
1. `tests/helpers/FramebufferValidator.zig` (252 lines)
2. `tests/integration/commercial_rom_test.zig` (356 lines)

### Modified Files (5)
1. `src/ppu/Logic.zig` - Debug output for register writes
2. `src/emulation/State.zig` - Debug output for NMI assertion
3. `src/emulation/Ppu.zig` - Debug output for VBlank
4. `src/cpu/Logic.zig` - Debug output for edge detection
5. `build.zig` - Registered new tests

**Total Lines Changed:** ~650 lines (new code + debug output)

---

## Next Actions

### Immediate (Before Commit)

1. ✅ Document findings in detail
2. ⏳ Remove all debug output
3. ⏳ Update CLAUDE.md with session findings
4. ⏳ Commit all work with comprehensive message

### Short-Term (Next Session)

1. **Plan NMI Implementation** (1-2 hours)
   - Review existing RTS/RTI patterns
   - Design 7-cycle state machine
   - Plan NMI/IRQ/BRK differentiation

2. **Implement Interrupt Handling** (4-6 hours)
   - Add state handling to stepCpuCycle()
   - Implement stack push sequence
   - Implement vector fetch sequence
   - Handle B flag correctly

3. **Test & Validate** (2-3 hours)
   - Create unit tests for NMI sequence
   - Run commercial ROM tests
   - Verify AccuracyCoin still passes
   - Check for timing regressions

**Total Estimated:** 8-11 hours to full commercial ROM support

---

## Lessons Learned

### Effective Debugging Strategy

1. **Start with symptoms** - blank screens, stuck PCs
2. **Form hypotheses** - rendering disabled, warm-up issues, VBlank problems
3. **Add diagnostic output** - trace entire pipeline
4. **Follow the data flow** - PPU → Emulation → CPU
5. **Verify each stage** - don't assume anything works
6. **Narrow down** - eliminate working components
7. **Find the gap** - missing implementation discovered

### Critical Insights

1. **Test ROMs ≠ Commercial Games**
   - Test ROMs may avoid timing-critical paths
   - Commercial games rely on precise hardware behavior
   - Both must pass for full compatibility

2. **State Machine Completeness**
   - Defining states in enum isn't enough
   - Every state needs implementation
   - Silent failures are dangerous

3. **Power-On vs RESET**
   - `reset()` skips PPU warm-up (hardware RESET button)
   - Power-on initialization requires warm-up period
   - Tests must distinguish these scenarios

---

## References

- **nesdev.org:** NES interrupt handling
- **6502 Hardware Manual:** Interrupt timing
- **AccuracyCoin:** Test ROM validation suite
- **Phase 2 Completion:** Lock-free FrameMailbox (2025-10-07)

---

**Session Lead:** Claude Code
**Documentation:** Complete
**Status:** Ready for implementation planning
