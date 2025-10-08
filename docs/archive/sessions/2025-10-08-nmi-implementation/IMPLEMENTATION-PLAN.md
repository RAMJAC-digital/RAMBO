# NMI/IRQ Interrupt Implementation Plan

**Date:** 2025-10-08
**Status:** Ready for Implementation
**Estimated Time:** 6-8 hours
**Priority:** P0 BLOCKER - All commercial games blocked

---

## Overview

Commercial games (Mario 1, Donkey Kong, BurgerTime) are stuck in infinite loops because NMI/IRQ interrupt sequences are not implemented. The interrupt states are defined but have zero implementation in `executeCpuCycle()`.

**Root Cause:** When `startInterruptSequence()` sets `state = .interrupt_sequence`, the CPU gets stuck forever because no code handles this state.

---

## Implementation Strategy

### Pattern: Inline Microsteps

Follow the existing BRK pattern exactly (lines 1229-1238 in `src/emulation/State.zig`):
- **Inline switch** in `executeCpuCycle()` (NOT a separate method)
- **Single state** (`.interrupt_sequence`) with cycle counter
- **Microstep helpers** for atomic operations (pushPch, pullPcl, etc.)

### Code Changes (3 files, ~80 lines)

#### 1. Rename State Enum

**File:** `src/cpu/State.zig:116`

```zig
// BEFORE
interrupt_dummy,

// AFTER
interrupt_sequence,  // Hardware interrupt (NMI/IRQ/RESET) - 7 cycles
```

#### 2. Update CpuLogic

**File:** `src/cpu/Logic.zig:97`

```zig
pub fn startInterruptSequence(state: *CpuState) void {
    state.state = .interrupt_sequence;  // ← Update to new name
    state.instruction_cycle = 0;
}
```

#### 3. Add Inline Interrupt Handling

**File:** `src/emulation/State.zig` **after line 1152**

```zig
// Handle hardware interrupts (NMI/IRQ/RESET) - 7 cycles
// Pattern matches BRK (software interrupt) at line 1229-1238
if (self.cpu.state == .interrupt_sequence) {
    const complete = switch (self.cpu.instruction_cycle) {
        0 => blk: {
            // Cycle 1: Dummy read at current PC (hijack opcode fetch)
            _ = self.busRead(self.cpu.pc);
            break :blk false;
        },
        1 => self.pushPch(),  // Cycle 2: Push PC high byte
        2 => self.pushPcl(),  // Cycle 3: Push PC low byte
        3 => self.pushStatusInterrupt(),  // Cycle 4: Push P (B=0)
        4 => blk: {
            // Cycle 5: Fetch vector low byte
            self.cpu.operand_low = switch (self.cpu.pending_interrupt) {
                .nmi => self.busRead(0xFFFA),
                .irq => self.busRead(0xFFFE),
                .reset => self.busRead(0xFFFC),
                else => unreachable,
            };
            self.cpu.p.interrupt = true;  // Set I flag
            break :blk false;
        },
        5 => blk: {
            // Cycle 6: Fetch vector high byte
            self.cpu.operand_high = switch (self.cpu.pending_interrupt) {
                .nmi => self.busRead(0xFFFB),
                .irq => self.busRead(0xFFFF),
                .reset => self.busRead(0xFFFD),
                else => unreachable,
            };
            break :blk false;
        },
        6 => blk: {
            // Cycle 7: Jump to handler
            self.cpu.pc = (@as(u16, self.cpu.operand_high) << 8) |
                          @as(u16, self.cpu.operand_low);
            self.cpu.pending_interrupt = .none;
            break :blk true;  // Complete
        },
        else => unreachable,
    };

    if (complete) {
        self.cpu.state = .fetch_opcode;
        self.cpu.instruction_cycle = 0;
    } else {
        self.cpu.instruction_cycle += 1;
    }
    return;
}
```

#### 4. Add Helper Method

**File:** `src/emulation/State.zig` **after line ~946** (after `pushStatusBrk()`)

```zig
/// Push status register to stack (for NMI/IRQ - B flag clear)
fn pushStatusInterrupt(self: *EmulationState) bool {
    const stack_addr = 0x0100 | @as(u16, self.cpu.sp);
    const status = self.cpu.p.toByte() | 0x20;  // B=0, unused=1
    self.busWrite(stack_addr, status);
    self.cpu.sp -%= 1;
    return false;
}
```

---

## Testing Strategy

### Phase 1: Unit Tests (CpuLogic - Pure Functions)

**File:** `tests/cpu/interrupt_logic_test.zig` (NEW)

**Tests (5):**
1. NMI edge detection (falling edge triggers)
2. NMI no re-trigger (level held doesn't fire again)
3. IRQ level detection (triggers while line high)
4. IRQ masked by I flag
5. startInterruptSequence sets state

**Run:** `zig test tests/cpu/interrupt_logic_test.zig`

### Phase 2: Integration Tests (Microstep Execution)

**File:** `tests/integration/interrupt_execution_test.zig` (NEW)

**Tests (3):**
1. NMI 7-cycle sequence (verify each cycle's operation)
2. BRK vs NMI: B flag differentiation
3. IRQ blocked by I flag

**Run:** `zig build test-integration`

### Phase 3: Commercial ROM Tests

**File:** `tests/integration/commercial_rom_test.zig` (UPDATE)

**Add NMI execution counting:**
```zig
const nmi_vector = state.busRead16(0xFFFA);
var nmi_executed_count: usize = 0;
var last_pc = state.cpu.pc;

while (frames_rendered < num_frames) {
    if (state.cpu.pc == nmi_vector and last_pc != nmi_vector) {
        nmi_executed_count += 1;
    }
    last_pc = state.cpu.pc;
    // ... frame execution ...
}
```

**Tests (4):**
1. Mario 1: ≥3 NMIs in 3 frames
2. Mario 1: Rendering enabled (PPUMASK != $00)
3. Mario 1: Graphics visible (>1000 pixels)
4. AccuracyCoin: No regressions ($00 $00 $00 $00)

**Run:** `zig build test`

### Phase 4: Regression Tests

**Run:** `zig build test` (all 896 tests must pass)

---

## Implementation Phases

### Phase 1: State Rename (15 minutes)
- [ ] Update `src/cpu/State.zig:116`
- [ ] Update `src/cpu/Logic.zig:97`
- [ ] Compile and verify no errors

### Phase 2: Helper Method (15 minutes)
- [ ] Add `pushStatusInterrupt()` in `src/emulation/State.zig`
- [ ] Compile and verify signature

### Phase 3: Inline Interrupt Handling (1 hour)
- [ ] Add interrupt sequence switch after line 1152
- [ ] Compile and verify no errors
- [ ] Run existing tests (should still pass)

### Phase 4: Unit Tests (1-2 hours)
- [ ] Create `tests/cpu/interrupt_logic_test.zig`
- [ ] Write 5 tests for CpuLogic
- [ ] All unit tests pass

### Phase 5: Integration Tests (2-3 hours)
- [ ] Create `tests/integration/interrupt_execution_test.zig`
- [ ] Write 3 tests for execution
- [ ] All integration tests pass

### Phase 6: Commercial ROM Tests (1-2 hours)
- [ ] Update `commercial_rom_test.zig` with NMI counting
- [ ] Write 4 tests for end-to-end validation
- [ ] Mario 1 displays title screen

### Phase 7: Regression Testing (30 minutes)
- [ ] Run full test suite (`zig build test`)
- [ ] Verify 896/900 tests still pass
- [ ] Fix any regressions

### Phase 8: Documentation (30 minutes)
- [ ] Update CLAUDE.md (remove P0 blocker status)
- [ ] Add inline comments
- [ ] Create completion summary

**Total: 6-8 hours**

---

## Hardware Specification Compliance

**Reference:** nesdev.org - Interrupt Handling

**7-Cycle Sequence:**
1. Dummy read at current PC
2. Push PCH to stack ($0100 + SP)
3. Push PCL to stack
4. Push P to stack (B=0 for hardware, B=1 for BRK)
5. Fetch vector low byte (NMI=$FFFA, IRQ=$FFFE, RESET=$FFFC)
6. Fetch vector high byte
7. Jump to handler, set I flag

**Vector Addresses:**
- NMI: $FFFA-$FFFB
- RESET: $FFFC-$FFFD
- IRQ/BRK: $FFFE-$FFFF

**B Flag Behavior:**
- Hardware interrupts (NMI/IRQ): B=0
- Software interrupt (BRK): B=1

---

## Success Criteria

### Code
- [ ] Compiles without errors
- [ ] Follows inline microstep pattern
- [ ] No architectural violations

### Tests
- [ ] All 5 unit tests pass
- [ ] All 3 integration tests pass
- [ ] All 4 commercial ROM tests pass
- [ ] All 896 regression tests pass

### Commercial ROMs
- [ ] Mario 1 executes NMI handlers
- [ ] Mario 1 enables rendering
- [ ] Mario 1 displays title screen
- [ ] AccuracyCoin status: $00 $00 $00 $00

---

## Risk Mitigation

**Low Risk:**
- Follows proven BRK pattern exactly
- Pure functions already correct
- Helper methods already exist
- Additive change (no modifications to existing code)

**Medium Risk:**
- Timing must be exact (7 cycles)
- B flag handling critical

**Mitigation:**
- Comprehensive testing at each phase
- Verify against hardware spec
- Run regression tests continuously

---

## References

- **Architecture:** `CORRECTED-ARCHITECTURE-ANALYSIS.md` (comprehensive deep-dive)
- **Investigation:** `docs/archive/sessions/2025-10-08-nmi-investigation/`
- **Hardware Spec:** nesdev.org - Interrupt Handling
- **BRK Pattern:** `src/emulation/State.zig:1229-1238`

---

**Status:** ✅ Ready for Implementation
**Blockers:** None
**Next Step:** Phase 1 - State Rename
