# CPU Timing Fix Investigation - 2025-10-06

## Status: Phase 1-2 Complete | Phase 3+ Ready to Begin

---

## Executive Summary

**Problem:** Systematic +1 cycle timing deviation for indexed addressing modes (absolute,X/Y, indirect,Y).

**Root Cause:** Our architecture separates operand reading (addressing state) from execution (execute state). Hardware combines the final operand read with execution in the same cycle.

**Impact:** AccuracyCoin test suite requires cycle-accurate timing. Current deviations will cause failures.

**Solution:** Conditional fallthrough - allow non-RMW instructions to execute in the same tick as final addressing cycle.

---

## Phase 1: Hardware Research - ✅ COMPLETE

### Hardware Timing Reference Created

**File:** `tests/cpu/reference/absolute_x_timing_spec.md`

**Key Findings:**
1. LDA absolute,X (no page cross): **4 cycles** (we have 5)
2. LDA absolute,X (page cross): **5 cycles** (we have 6)
3. Final operand read + execution happen **in same cycle** on hardware
4. Write instructions always take 5 cycles (no conditional timing)
5. RMW instructions correctly take 7 cycles (we're correct here)

**Authoritative Sources:**
- NESdev 6502 CPU Reference (https://www.nesdev.org/6502_cpu.txt)
- Visual 6502 project
- NESdev Wiki timing tables

### Addressing Mode Comparison - ✅ COMPLETE

**File:** `tests/cpu/reference/addressing_mode_comparison.md`

**Why These Work:**
- ✅ Immediate (2 cycles): Execute reads operand inline
- ✅ Zero Page (3 cycles): Execute reads from ZP address
- ✅ Absolute (4 cycles): Execute reads from absolute address

**Why Absolute,X Fails:**
- ❌ Addressing state reads operand into temp_value
- ❌ Execute state uses cached temp_value
- ❌ Addressing + Execute = two separate ticks (+1 cycle)

**Pattern:**
- Working modes: Execute READS the operand (read + execute = same tick)
- Broken mode: Addressing READS, execute USES (two ticks)

---

## Phase 2: Diagnostic Tests - ✅ COMPLETE

### Cycle-by-Cycle Trace Tests Created

**File:** `tests/cpu/diagnostics/timing_trace_test.zig`

**Coverage:**
1. ✅ LDA absolute,X (no page cross) - documents current 5-cycle behavior
2. ✅ LDA absolute,X (page cross) - documents current 6-cycle behavior
3. ✅ LDA immediate - verifies correct 2-cycle behavior
4. ✅ ASL absolute,X (RMW) - verifies correct 7-cycle behavior

**Purpose:**
- Document exact cycle-by-cycle state progression
- Validate fix when implemented
- Prevent regressions

**Key Test Insights:**
```zig
// Current behavior (WRONG):
// Cycle 4: calcAbsoluteX reads operand → temp_value
// Cycle 5: Execute uses temp_value

// Expected behavior (CORRECT):
// Cycle 4: Read operand + Execute LDA (SAME CYCLE)
```

---

## Phase 3: Root Cause Analysis (Next Step)

### Identified Issues

**Issue 1: Redundant Bus Reads (Page Cross Case)**

Current flow for LDA abs,X with page cross:
1. Cycle 4: calcAbsoluteX - dummy read at wrong address → temp_value
2. Cycle 5: fixHighByte - dummy read at CORRECT address (discarded!)
3. Cycle 6: Execute - reads AGAIN at correct address

**Hardware only reads twice. We read THREE times!**

**Issue 2: Addressing Stores Operand Value**

```zig
// calcAbsoluteX stores the read value:
self.cpu.temp_value = self.busRead(dummy_addr);

// Execute then uses it:
.absolute_x => if (self.cpu.page_crossed)
    self.busRead(self.cpu.effective_address)  // ← Another read!
else
    self.cpu.temp_value,  // ← Uses cached value
```

This pattern violates the principle that **addressing calculates addresses**, not values.

---

## Proposed Solution: Conditional Fallthrough

### Architecture Changes

**1. Fix fixHighByte to Read Real Value (Page Cross Case)**

```zig
fn fixHighByte(self: *EmulationState) bool {
    if (self.cpu.page_crossed) {
        // Do REAL read, not dummy
        self.cpu.temp_value = self.busRead(self.cpu.effective_address);
    } else {
        // No page cross - temp_value already has correct value from calcAbsoluteX
    }
    return false;
}
```

**2. Execute Always Uses temp_value for Indexed Modes**

```zig
// Never re-read for absolute_x/y:
.absolute_x, .absolute_y, .indirect_indexed => self.cpu.temp_value,
```

**3. Enable Conditional Fallthrough**

```zig
if (addressing_done) {
    self.cpu.state = .execute;

    // For non-RMW instructions, fall through to execute in same tick
    const entry = CpuModule.dispatch.DISPATCH_TABLE[self.cpu.opcode];
    if (entry.is_rmw or entry.is_pull or entry.is_push) {
        return;  // These need separate execute cycle
    }
    // Fall through to execute state
}
```

### Why This Works

**No Page Cross (4 cycles):**
1. Fetch opcode
2. Fetch low
3. Fetch high
4. calcAbsoluteX (reads value → temp_value) **+ Execute (uses temp_value)** ← SAME TICK

**Page Cross (5 cycles):**
1. Fetch opcode
2. Fetch low
3. Fetch high
4. calcAbsoluteX (dummy read at wrong address)
5. fixHighByte (read at correct address → temp_value) **+ Execute (uses temp_value)** ← SAME TICK

---

## Implementation Plan

### Phase 4: Architecture Design & QA Review (Next)

1. **Refine Conditional Fallthrough Logic**
   - Identify all instruction types that can/cannot fall through
   - Verify RMW instructions unaffected
   - Check push/pull instructions

2. **QA Review with `qa-code-review-pro` Agent**
   - Review proposed changes
   - Verify state isolation maintained
   - Check for side effects
   - Identify edge cases

### Phase 5: Incremental TDD Implementation

1. **Fix absolute,X (no page cross) only**
   - Write failing test expecting 4 cycles
   - Implement fixHighByte changes
   - Implement execute state changes
   - Enable conditional fallthrough
   - Verify test passes
   - Run full suite (check no regressions)

2. **Extend to page-cross case**
   - Verify 5 cycles for page cross
   - Ensure fixHighByte does real read

3. **Extend to absolute,Y and indirect,Y**
   - Apply same pattern
   - Verify timing

4. **Verify RMW unaffected**
   - ASL, INC, DEC still 7 cycles
   - No fallthrough for RMW

### Phase 6: Comprehensive Verification

1. **All 562 tests must pass**
2. **Zero timing deviations**
3. **State isolation audit**
4. **Documentation update**

---

## Success Criteria

✅ LDA abs,X (no page cross) = **4 cycles** (currently 5)
✅ LDA abs,X (page cross) = **5 cycles** (currently 6)
✅ STA abs,X = **5 cycles** (currently 6)
✅ ASL abs,X = **7 cycles** (currently 7 - unchanged)
✅ All 562 tests passing
✅ Zero regressions
✅ Clean architecture maintained

---

## Next Steps

1. Complete Phase 3: Detailed root cause analysis in State.zig
2. Phase 4: Get QA review approval for conditional fallthrough approach
3. Phase 5: Implement fix incrementally with TDD
4. Phase 6: Comprehensive verification

**Estimated Time Remaining:** 12-18 hours

---

## Files Created

1. ✅ `tests/cpu/reference/absolute_x_timing_spec.md` - Hardware timing reference
2. ✅ `tests/cpu/reference/addressing_mode_comparison.md` - Why other modes work
3. ✅ `tests/cpu/diagnostics/timing_trace_test.zig` - Cycle-by-cycle validation tests
4. ✅ `docs/code-review/TIMING-FIX-INVESTIGATION-2025-10-06.md` - This document
