# Super Mario Bros Rendering Fix Session (CONTINUED)
**Date:** 2025-10-XX
**Status:** IN PROGRESS - Phase 10 Investigation

## Session Summary

Multi-phase investigation into Super Mario Bros rendering failure. Identified and fixed VBlank detection, NMI coordination, and discovered deeper execution issues.

---

## Phase 10: VBlank Signal Generation Fix (CURRENT)

### Initial State
- Phase 1-9 identified warmup and NMI bugs (fixed)
- Commercial ROM tests still showed: VBlank count = 0, PC = 0xFFFA

### Subagent Analysis Results

Three specialized agents analyzed VBlank generation path:

1. **zig-systems-pro**: Suspected NMI line update dead zone
2. **qa-code-review-pro**: Identified clock timing bug (POST vs PRE advance)
3. **debugger**: Found test logic bug (checks LEVEL not EDGE)

### Fixes Implemented

#### Fix 1: Test Logic - VBlank Edge Detection ✅
**File:** `tests/integration/commercial_rom_test.zig:119-141`

**Problem:** Test checked VBlank LEVEL (currently active) after `emulateFrame()`, but VBlank clears at scanline 261 before frame completes.

**Solution:** Implement edge detection by tracking cycle count changes:
```zig
var prev_vblank_set_cycle: u64 = 0;

// Inside frame loop:
if (state.vblank_ledger.last_set_cycle > prev_vblank_set_cycle) {
    vblank_count += 1;  // VBlank EDGE detected
}
prev_vblank_set_cycle = state.vblank_ledger.last_set_cycle;
```

**Result:** ✅ **VBlank count now 180** (was 0) - VBlank IS setting!

#### Fix 2: NMI Line Latching Bug ✅
**File:** `src/emulation/cpu/execution.zig:105-114`

**Problem:** Original code used `if... else if` which left `nmi_line` unchanged when:
- VBlank active BUT NMI disabled (`nmi_conditions_met = false`)
- VBlank not yet cleared (`last_clear >= last_set = false`)

This caused NMI line to latch HIGH even after PPUCTRL disabled NMI.

**Solution:** Change to `if... else` to ALWAYS explicitly set NMI line:
```zig
if (nmi_conditions_met) {
    state.cpu.nmi_line = true;
} else {
    state.cpu.nmi_line = false;  // Always clear when conditions not met
}
```

#### Fix 3: IRQ Line Initialization ✅
**File:** `src/emulation/State.zig:206,236`

**Problem:** `power_on()` and `reset()` cleared `nmi_line` but not `irq_line`.

**Solution:** Added `self.cpu.irq_line = false;` after `nmi_line` initialization.

#### Fix 4: Clock Timing (REVERTED) ⚠️
**File:** `src/emulation/State.zig:545-546`

**Initial Analysis:** Subagent suggested PPU should see PRE-advance coordinates from `TimingStep`.

**Testing:** Caused unit test failures - PPU needs POST-advance coordinates to process at exact timing points (e.g., scanline 241, dot 1 for VBlank set).

**Decision:** Reverted - original code was correct. PPU must see where clock IS, not where it WAS.

---

## Phase 10.5: BRK Execution Mystery (NEW CRITICAL ISSUE)

### Discovery

After VBlank fix, commercial ROM tests still fail with NEW symptom:

**Test Output:**
```
[ROM Debug] NMI Stats:
  Frames rendered: 180
  VBlank count: 180       ✅ VBlank NOW sets!
  NMI executed: 0         ❌ NMI never executes
  NMI vector: 0x8082      ✅ Valid ROM address
  Current PC: 0xFFFA      ❌ Stuck in vector table
  IRQ vector: 0xFFF0      ❌ INVALID (points to vector table)

PC history (first 10 frames):
  Frame 0: PC = $8012     ✅ Normal ROM execution
  Frame 1: PC = $90E0     ✅ Normal
  Frame 2: PC = $90D6     ✅ Normal
  Frame 3: PC = $8E15     ✅ Normal
  Frame 4: PC = $FFFE     ❌ IRQ vector address!
  Frame 5: PC = $FFF4     ❌ Vector table space
  Frame 6: PC = $FFFA     ❌ Vector table space
  ...
  Frame 179: PC = $FFFA   ❌ Still stuck
```

### Debug Instrumentation Added

**User added extensive debugging:**
1. PC history tracking (first/last 10 frames)
2. IRQ execution detection
3. Interrupt start logging
4. BRK instruction tracking
5. IRQ line assertion logging

**Code locations:**
- `tests/integration/commercial_rom_test.zig:121-177` - PC history + IRQ tracking
- `src/emulation/cpu/execution.zig:167-169` - Interrupt start debug
- `src/emulation/cpu/execution.zig:325-326` - BRK tracking
- `src/emulation/State.zig:576-582` - IRQ line assertion debug

### Critical Debug Output

```
[BRK] BRK instruction at PC=$0000    ← First BRK in zero page RAM!
[BRK] BRK instruction at PC=$3434    ← Infinite loop
[BRK] BRK instruction at PC=$3434
... (repeats)
[TEST] FIRST IRQ executed at frame 19
  IRQ vector: 0xFFF0
  APU frame_counter_cycles: 28805
  APU irq_inhibit: true               ← IRQ should be inhibited!
  APU frame_irq_flag: false           ← No APU IRQ
  APU dmc_irq_flag: false             ← No DMC IRQ
  CPU p.interrupt: true               ← CPU interrupts disabled!
  CPU irq_line: false                 ← IRQ line not asserted
  CPU pending_interrupt: .none        ← No pending interrupt
```

### Analysis

**Key Findings:**
1. **BRK Execution**: CPU executes BRK (0x00 opcode) at $0000 (zero page RAM)
2. **Invalid Memory**: PC at $0000, $3434 are NOT ROM space ($8000-$FFFF)
3. **Software Interrupt**: BRK triggers jump to IRQ vector (not hardware IRQ)
4. **Corrupted Vector**: IRQ vector = 0xFFF0 (inside vector table, contains garbage)
5. **Infinite Loop**: 0xFFF0 contains 0x00 (BRK), creating infinite BRK loop
6. **Timing**: Happens at frame 4 (after ~119,520 CPU cycles)

**ROM Vectors (from memory dump):**
```
$FFFA-$FFFB: 0x8082  ← NMI vector (valid)
$FFFC-$FFFD: 0x8000  ← RESET vector (valid)
$FFFE-$FFFF: 0xFFF0  ← IRQ vector (INVALID - uninitialized?)
```

**QA Agent Assessment:**
- IRQ line never asserts (hardware working correctly)
- No APU interrupts (frame_irq_flag = false, irq_inhibit = true)
- CPU interrupt flag set (p.interrupt = true, IRQs disabled)
- **Conclusion**: Not a hardware IRQ, but BRK execution

### Hypotheses

**Why PC jumps to $0000:**
1. **Stack Corruption**: RTS/RTI returns to invalid address
2. **Indirect Jump**: JMP ($XXXX) through uninitialized zero page
3. **Paging Bug**: Memory mapping incorrect for ROM reads
4. **Addressing Mode Bug**: Indirect addressing calculates wrong address

**Why IRQ vector is 0xFFF0:**
- ROM file may be corrupted/truncated
- iNES loader not properly initializing vector table
- Cartridge mapping bug (vectors in wrong bank?)

---

## Current Investigation Tasks

### 1. Memory Mapping Verification
- [ ] Check ROM loading at $8000-$FFFF
- [ ] Verify vector table at $FFFA-$FFFF mapped to ROM
- [ ] Test bus reads at various addresses
- [ ] Confirm NROM mapper behavior

### 2. Stack Integrity Check
- [ ] Add stack pointer logging
- [ ] Track push/pop operations frames 0-4
- [ ] Verify RTS/RTI stack usage
- [ ] Check for stack overflow/underflow

### 3. Indirect Addressing Audit
- [ ] Review JMP indirect implementation
- [ ] Check zero page wrapping in indirect modes
- [ ] Verify indexed indirect addressing
- [ ] Test indirect indexed addressing

### 4. Execution Trace
- [ ] Log every instruction execution frames 3-4
- [ ] Capture opcode + operands + PC
- [ ] Track register state changes
- [ ] Identify exact jump to $0000

---

## Architecture Insights

`★ Insight ─────────────────────────────────────`
**Debugging Progression Reveals Layered Issues:**

1. **Layer 1 - VBlank Generation**: PPU timing works correctly
2. **Layer 2 - Test Logic**: Tests must check EDGE not LEVEL for VBlank
3. **Layer 3 - NMI Coordination**: NMI line must always be explicitly set
4. **Layer 4 - Execution Flow**: PC enters invalid memory space, exposing:
   - ROM execution starts correctly ($8012)
   - Fails after ~119K cycles
   - Falls into zero page RAM
   - Executes garbage (0x00 = BRK)
   - Jumps through invalid IRQ vector

The issue is NOT interrupt handling, but **execution flow integrity**.
`─────────────────────────────────────────────────`

---

## Files Modified

### Phase 10 Fixes
- `tests/integration/commercial_rom_test.zig:123-141` - VBlank edge detection
- `src/emulation/cpu/execution.zig:105-114` - NMI line latching fix
- `src/emulation/State.zig:206,236` - IRQ line initialization
- `src/cpu/State.zig:164` - Added nmi_enable_prev field (Phase 9)

### Debug Instrumentation (User Added)
- `tests/integration/commercial_rom_test.zig:121-177` - PC history tracking
- `src/emulation/cpu/execution.zig:167-169` - Interrupt logging
- `src/emulation/cpu/execution.zig:325-326` - BRK tracking
- `src/emulation/State.zig:576-582` - IRQ line assertion logging

---

## Test Results

### Unit Tests
- Status: Not fully tested (some tests timeout)
- VBlank tests: Need retest after revert

### Commercial ROMs
- **VBlank**: ✅ Sets correctly (count = 180)
- **Rendering**: ❌ Never enabled (PPUMASK = 0x00)
- **NMI**: ❌ Never executes (PC stuck in vector table)
- **Execution**: ❌ BRK loop starting frame 4

---

## Next Session Recommendations

### Immediate Priority (P0)
1. **Execution Trace Analysis**
   - Add comprehensive logging for frames 3-4
   - Capture every instruction + addressing mode
   - Identify exact moment PC jumps to $0000

2. **Memory Mapping Verification**
   - Test ROM reads at $8000-$FFFF
   - Verify vector table mapping
   - Check NROM mapper correctness

3. **Stack Integrity Investigation**
   - Log SP changes
   - Track RTS/RTI behavior
   - Check for stack corruption

### Secondary Priority (P1)
4. Remove debug instrumentation after fixing
5. Re-run full test suite
6. Verify AccuracyCoin still passes

---

## Command Reference

```bash
# Run commercial ROM tests with debug output
zig build test -- tests/integration/commercial_rom_test.zig 2>&1 | tee debug.log

# Search debug output for specific events
grep -E "\[BRK\]|\[INT\]|\[EMU\]" debug.log

# Run unit tests
zig build test-unit

# Run AccuracyCoin baseline
zig build test -- tests/integration/accuracycoin_execution_test.zig
```

---

**Session Status:** ACTIVE INVESTIGATION - BRK execution mystery
**Code Quality:** All Phase 10 changes follow project conventions
**Test Coverage:** VBlank detection now working, commercial ROMs blocked on execution flow bug
**Documentation:** Comprehensive debug output captured, ready for ULTRATHINK analysis
