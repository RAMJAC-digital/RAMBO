# IRQ/NMI Permutation Verification Matrix
**Date**: 2025-10-09
**Purpose**: Systematic verification of all IRQ/NMI flag combinations against NES hardware spec
**Status**: 🔄 In Progress

## Overview

This matrix tracks **verified** combinations of IRQ/NMI flags, states, and timing conditions to ensure hardware-accurate emulation. Each permutation is tested against known behavior and marked with verification status.

## Matrix Dimensions

### Dimension 1: NMI State
- `nmi_line` (CPU input): false/true
- `nmi_edge_detected` (CPU latch): false/true
- `nmi_enable` (PPUCTRL.7): false/true
- `vblank_flag` (PPUSTATUS.7): false/true
- `span_active` (VBlankLedger): false/true
- `nmi_edge_pending` (VBlankLedger): false/true

### Dimension 2: IRQ State
- `irq_line` (CPU input): false/true
- `interrupt_flag` (CPU P.I): false/true
- `mapper_irq`: false/true
- `apu_frame_irq`: false/true
- `apu_dmc_irq`: false/true

### Dimension 3: Timing Context
- Cycle within instruction
- VBlank timing (241.1, 261.1)
- $2002 read timing (same cycle as VBlank set, after)
- PPUCTRL write timing (during VBlank, outside)

### Dimension 4: Execution Context
- `pending_interrupt`: none/nmi/irq/reset
- `state`: fetch_opcode/fetch_operand_low/execute/interrupt_sequence
- `instruction_cycle`: 0-7

## Verification Status Legend

- ✅ **VERIFIED** - Tested against hardware spec, matches expected behavior
- ⚠️ **SUSPECTED** - Likely correct but needs explicit test verification
- ❌ **FAILING** - Known to not match hardware spec
- 🔍 **UNTESTED** - Not yet verified
- 📝 **DOCUMENTED** - Behavior documented in nesdev.org but not tested

---

## Critical Permutations (Priority 1)

### P1.1: NMI Edge Detection - VBlank Set with NMI Pre-Enabled ✅ VERIFIED

**Condition:**
- `nmi_enable` = true (PPUCTRL.7 already set)
- VBlank sets at scanline 241.1
- No $2002 read on same cycle

**Expected Behavior:**
- `vblank_flag` = true (PPUSTATUS.7)
- `span_active` = true (VBlankLedger)
- `nmi_edge_pending` = true (VBlankLedger)
- `nmi_line` = true (CPU input)
- NMI fires on next fetch_opcode

**Implementation:**
```zig
// VBlankLedger.zig:57-66
pub fn recordVBlankSet(self: *VBlankLedger, cycle: u64, nmi_enabled: bool) void {
    const was_active = self.span_active;
    self.span_active = true;
    self.last_set_cycle = cycle;

    if (!was_active and nmi_enabled) {
        self.nmi_edge_pending = true; // ✅ CORRECT
    }
}
```

**Verification:**
- Test: `tests/ppu/vblank_ledger_test.zig:228-233`
- Status: ✅ PASSING
- Hardware Ref: nesdev.org/wiki/NMI (Section: "NMI edge detection")

---

### P1.2: NMI Edge Detection - PPUCTRL Toggle During VBlank ✅ VERIFIED

**Condition:**
- VBlank already active (`span_active` = true)
- PPUCTRL.7 transitions 0 → 1

**Expected Behavior:**
- `nmi_edge_pending` = true (new edge latched)
- NMI fires on next fetch_opcode

**Implementation:**
```zig
// VBlankLedger.zig:104-111
pub fn recordCtrlToggle(self: *VBlankLedger, cycle: u64, old_enabled: bool, new_enabled: bool) void {
    self.last_ctrl_toggle_cycle = cycle;

    if (!old_enabled and new_enabled and self.span_active) {
        self.nmi_edge_pending = true; // ✅ CORRECT
    }
}
```

**Verification:**
- Test: `tests/ppu/vblank_ledger_test.zig:208-218`
- Status: ✅ PASSING
- Hardware Ref: nesdev.org/wiki/NMI (Section: "Multiple NMI via PPUCTRL toggle")

---

### P1.3: NMI Suppression - $2002 Read on Exact VBlank Set Cycle ✅ VERIFIED

**Condition:**
- VBlank sets at cycle N
- $2002 read occurs at cycle N (same cycle)

**Expected Behavior:**
- `vblank_flag` cleared immediately
- `nmi_edge_pending` set, but race condition detected
- `shouldNmiEdge()` returns false (NMI suppressed)

**Implementation:**
```zig
// VBlankLedger.zig:127-139
pub fn shouldNmiEdge(self: *const VBlankLedger, _: u64, nmi_enabled: bool) bool {
    if (!nmi_enabled) return false;
    if (!self.nmi_edge_pending) return false;

    // Race condition check
    const read_on_set = self.last_status_read_cycle == self.last_set_cycle;
    if (read_on_set) return false; // ✅ CORRECT

    return true;
}
```

**Verification:**
- Test: `tests/ppu/vblank_ledger_test.zig:258-272`
- Status: ✅ PASSING
- Hardware Ref: nesdev.org/wiki/PPU_frame_timing (Section: "VBlank flag race")

---

### P1.4: NMI Persistence - Edge Pending After VBlank Span Ends ⚠️ SUSPECTED

**Condition:**
- NMI edge latched during VBlank span
- VBlank span ends at scanline 261.1
- CPU has NOT yet acknowledged NMI

**Expected Behavior:**
- `span_active` = false (VBlank period ended)
- `nmi_edge_pending` = true (STILL PENDING)
- `nmi_line` = true (CPU input still asserted)
- NMI fires when CPU reaches fetch_opcode

**Implementation:**
```zig
// VBlankLedger.zig:78-81
pub fn recordVBlankSpanEnd(self: *VBlankLedger, cycle: u64) void {
    self.span_active = false;
    self.last_clear_cycle = cycle;
    // NOTE: nmi_edge_pending NOT cleared ✅ CORRECT
}

// VBlankLedger.zig:161-170
pub fn shouldAssertNmiLine(...) bool {
    // NMI line asserted when edge pending (regardless of span_active)
    return self.shouldNmiEdge(cycle, nmi_enabled); // ✅ CORRECT
}
```

**Verification:**
- Test: **MISSING** - Need explicit test for this case
- Status: ⚠️ SUSPECTED (implementation looks correct, needs test)
- Hardware Ref: nesdev.org/wiki/NMI (Section: "NMI latch persists until CPU acknowledgment")

**TODO:** Create test for NMI persistence after VBlank span end

---

### P1.5: NMI Acknowledgment - CPU Interrupt Sequence Cycle 6 ✅ VERIFIED

**Condition:**
- NMI interrupt sequence reaches cycle 6 (final cycle)
- CPU jumps to NMI vector

**Expected Behavior:**
- `nmi_edge_pending` cleared (acknowledged)
- `pending_interrupt` cleared
- `nmi_line` becomes false on next cycle

**Implementation:**
```zig
// execution.zig:207-221
6 => blk: {
    // Cycle 7: Jump to handler
    state.cpu.pc = (@as(u16, state.cpu.operand_high) << 8) |
        @as(u16, state.cpu.operand_low);

    const was_nmi = state.cpu.pending_interrupt == .nmi;
    state.cpu.pending_interrupt = .none;

    if (was_nmi) {
        state.vblank_ledger.acknowledgeCpu(state.clock.ppu_cycles); // ✅ CORRECT
    }

    break :blk true; // Complete
},
```

**Verification:**
- Test: `tests/ppu/vblank_ledger_test.zig:245-256`
- Status: ✅ PASSING
- Hardware Ref: nesdev.org/wiki/CPU_interrupts (Section: "Interrupt sequence")

---

## IRQ Permutations (Priority 2)

### P2.1: IRQ Level-Triggered - Asserted When I Flag Clear ⚠️ SUSPECTED

**Condition:**
- `irq_line` = true (mapper/APU asserting IRQ)
- `interrupt_flag` (P.I) = false (interrupts enabled)
- No pending NMI (NMI has priority)

**Expected Behavior:**
- `pending_interrupt` = .irq
- IRQ sequence starts on next fetch_opcode

**Implementation:**
```zig
// Logic.zig:76-91
pub fn checkInterrupts(state: *CpuState) void {
    // NMI has highest priority (lines 80-86)
    const nmi_prev = state.nmi_edge_detected;
    state.nmi_edge_detected = state.nmi_line;

    if (state.nmi_line and !nmi_prev) {
        state.pending_interrupt = .nmi;
    }

    // IRQ is level-triggered and can be masked
    if (state.irq_line and !state.p.interrupt and state.pending_interrupt == .none) {
        state.pending_interrupt = .irq; // ✅ CORRECT
    }
}
```

**Verification:**
- Test: `tests/cpu/interrupts_test.zig:*` (multiple tests)
- Status: ⚠️ SUSPECTED (tests pass, needs hardware comparison)
- Hardware Ref: nesdev.org/wiki/IRQ (Section: "Level-triggered behavior")

---

### P2.2: IRQ Masking - I Flag Set Blocks IRQ ✅ VERIFIED

**Condition:**
- `irq_line` = true
- `interrupt_flag` (P.I) = true (interrupts disabled)

**Expected Behavior:**
- IRQ does NOT latch
- `pending_interrupt` remains .none

**Implementation:**
```zig
// Logic.zig:89-91
if (state.irq_line and !state.p.interrupt and state.pending_interrupt == .none) {
    state.pending_interrupt = .irq;
}
// If p.interrupt == true, condition fails ✅ CORRECT
```

**Verification:**
- Test: `tests/cpu/interrupts_test.zig:*`
- Status: ✅ VERIFIED
- Hardware Ref: nesdev.org/wiki/Status_flags (Section: "I flag")

---

### P2.3: IRQ Priority - NMI Overrides IRQ ⚠️ SUSPECTED

**Condition:**
- Both `nmi_line` and `irq_line` true
- NMI edge detected

**Expected Behavior:**
- `pending_interrupt` = .nmi (NMI wins)
- IRQ deferred until after NMI handler

**Implementation:**
```zig
// Logic.zig:76-91
pub fn checkInterrupts(state: *CpuState) void {
    // NMI checked FIRST (lines 80-86)
    if (state.nmi_line and !nmi_prev) {
        state.pending_interrupt = .nmi; // Sets to NMI
    }

    // IRQ only sets if pending_interrupt == .none
    if (state.irq_line and !state.p.interrupt and state.pending_interrupt == .none) {
        state.pending_interrupt = .irq; // ✅ Skipped if NMI set
    }
}
```

**Verification:**
- Test: **MISSING** - Need explicit test for NMI/IRQ priority
- Status: ⚠️ SUSPECTED (logic correct, needs test)
- Hardware Ref: nesdev.org/wiki/CPU_interrupts (Section: "Interrupt priority")

**TODO:** Create test for simultaneous NMI + IRQ

---

## Edge Cases (Priority 3)

### P3.1: $2002 Read Does NOT Clear NMI Edge Pending ✅ VERIFIED

**Condition:**
- NMI edge already latched (`nmi_edge_pending` = true)
- CPU reads $2002

**Expected Behavior:**
- `vblank_flag` cleared (PPUSTATUS.7 = 0)
- `nmi_edge_pending` UNCHANGED (NMI still pending)
- NMI fires on next fetch_opcode

**Implementation:**
```zig
// VBlankLedger.zig:91-100
pub fn recordStatusRead(self: *VBlankLedger, cycle: u64) void {
    self.last_status_read_cycle = cycle;
    self.last_clear_cycle = cycle;

    // Note: span_active remains true until scanline 261.1
    // Note: nmi_edge_pending is NOT cleared ✅ CORRECT
}
```

**Verification:**
- Test: `tests/ppu/vblank_ledger_test.zig:274-286`
- Status: ✅ PASSING
- Hardware Ref: nesdev.org/wiki/PPUSTATUS (Section: "Reading $2002")

---

### P3.2: BRK Sets B Flag in Pushed Status, Hardware Interrupts Do Not 🔍 UNTESTED

**Condition:**
- Compare BRK (software interrupt) vs NMI/IRQ (hardware interrupt)
- Status pushed to stack

**Expected Behavior:**
- BRK: Bit 4 (B flag) = 1 in pushed status
- NMI/IRQ: Bit 4 (B flag) = 0 in pushed status

**Implementation:**
```zig
// microsteps.zig (BRK - software interrupt)
pub fn pushStatusBrk(state: anytype) bool {
    var flags = state.cpu.p;
    flags.break_flag = true;  // ✅ Set B flag for BRK
    flags.unused = true;
    // ... push to stack
}

// execution.zig:185 (NMI/IRQ - hardware interrupt)
3 => CpuMicrosteps.pushStatusInterrupt(state), // Cycle 4: Push P (B=0)

// microsteps.zig (hardware interrupt)
pub fn pushStatusInterrupt(state: anytype) bool {
    var flags = state.cpu.p;
    flags.break_flag = false; // ✅ Clear B flag for hardware interrupt
    flags.unused = true;
    // ... push to stack
}
```

**Verification:**
- Test: **MISSING** - Need explicit test reading pushed status from stack
- Status: 🔍 UNTESTED (implementation correct per code review)
- Hardware Ref: nesdev.org/wiki/Status_flags (Section: "B flag")

**TODO:** Create test to verify B flag in pushed status

---

## Timing-Critical Permutations (Priority 4)

### P4.1: Interrupt Hijacking - NMI During IRQ Sequence 📝 DOCUMENTED

**Condition:**
- IRQ sequence in progress (cycles 0-6)
- NMI edge occurs during sequence

**Expected Behavior:**
- IRQ sequence continues (already committed)
- NMI edge latches but doesn't fire yet
- After IRQ handler RTI, NMI fires immediately

**Implementation:**
```zig
// execution.zig:154-163
if (state.cpu.state == .fetch_opcode) {
    CpuLogic.checkInterrupts(&state.cpu);
    if (state.cpu.pending_interrupt != .none and state.cpu.pending_interrupt != .reset) {
        CpuLogic.startInterruptSequence(&state.cpu);
        return;
    }
}
// Interrupts only checked at fetch_opcode, NOT during interrupt_sequence ✅ CORRECT
```

**Verification:**
- Test: **MISSING** - Complex scenario requiring precise timing
- Status: 📝 DOCUMENTED (logic prevents hijacking)
- Hardware Ref: nesdev.org/wiki/CPU_interrupts (Section: "Interrupt hijacking")

**TODO:** Create test for interrupt hijacking prevention

---

## Summary Statistics

| Category | Total | ✅ Verified | ⚠️ Suspected | ❌ Failing | 🔍 Untested |
|----------|-------|-------------|--------------|------------|-------------|
| NMI Edge Detection | 5 | 3 | 2 | 0 | 0 |
| IRQ Level Trigger | 3 | 1 | 2 | 0 | 0 |
| Edge Cases | 2 | 1 | 0 | 0 | 1 |
| Timing-Critical | 1 | 0 | 0 | 0 | 1 |
| **TOTAL** | **11** | **5** | **4** | **0** | **2** |

**Verification Coverage:** 45% (5/11) fully verified, 36% (4/11) suspected correct

---

## Next Steps

### Immediate (Priority 1)
1. Create test for P1.4: NMI persistence after VBlank span end
2. Create test for P2.3: NMI/IRQ simultaneous assertion priority
3. Verify P3.2: B flag differentiation in pushed status

### Short-term (Priority 2)
4. Create timing-critical test for P4.1: Interrupt hijacking
5. Hardware comparison testing for all ⚠️ SUSPECTED cases
6. Expand matrix to cover all 2^12 = 4096 theoretical permutations

### Long-term (Priority 3)
7. Automated verification: Generate tests from matrix
8. Hardware test ROM: AccuracyCoin-style interrupt test suite
9. Commercial ROM validation: Test against known interrupt-heavy games

---

## Test Coverage Gaps

### Missing Test Scenarios
1. **NMI Edge Persistence**: Edge pending after VBlank span ends at 261.1
2. **NMI/IRQ Priority**: Simultaneous assertion of both interrupt sources
3. **B Flag Verification**: Reading pushed status byte from stack (BRK vs hardware)
4. **Interrupt Hijacking**: NMI during IRQ sequence (and vice versa)
5. **Multiple PPUCTRL Toggles**: 0→1→0→1 during single VBlank span
6. **IRQ Deassertion**: IRQ line goes low during IRQ sequence
7. **Mapper IRQ Timing**: MMC3 scanline counter IRQ accuracy

### Recommended Test Suite Additions
- `tests/cpu/interrupt_priority_test.zig` - NMI vs IRQ priority
- `tests/cpu/interrupt_persistence_test.zig` - Edge/level persistence
- `tests/cpu/interrupt_hijacking_test.zig` - Mid-sequence behavior
- `tests/ppu/ppuctrl_toggle_rapid_test.zig` - Multiple NMI edges per frame

---

**Document Version:** 1.0
**Last Updated:** 2025-10-09
**Maintainer:** RAMBO Emulation Team
**Related Documents:**
- `docs/KNOWN-ISSUES.md` (Known interrupt bugs)
- `docs/dot/cpu-module-structure.dot` (CPU interrupt architecture)
- `docs/dot/emulation-coordination.dot` (VBlank ledger integration)
- `src/emulation/state/VBlankLedger.zig` (NMI edge detection implementation)
- `src/cpu/Logic.zig` (CPU interrupt checking logic)
