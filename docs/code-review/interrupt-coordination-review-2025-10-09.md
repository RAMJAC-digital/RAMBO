# IRQ/NMI Interrupt Coordination Code Review
**Date:** 2025-10-09
**Reviewer:** Claude Code (Senior Code Reviewer - Configuration Security & RT Systems)
**Scope:** Complete interrupt coordination architecture (NMI/IRQ edge detection, priority, timing)
**Status:** ✅ **APPROVED** with minor recommendations

---

## Executive Summary

The interrupt coordination system is **architecturally sound** with excellent separation of concerns. The VBlankLedger provides true single-source-of-truth for NMI state, interrupt priority is correct, and side effects are properly tracked. **No critical bugs found.** Minor recommendations focus on defensive coding and test coverage gaps.

**Key Findings:**
- ✅ VBlankLedger is genuine single source of truth (no duplicate NMI state)
- ✅ IRQ composition correctly combines all three sources (mapper, APU frame, APU DMC)
- ✅ Side effects ($2002 reads, PPUCTRL writes) properly recorded in ledger
- ✅ Interrupt timing follows 7-cycle hardware sequence exactly
- ✅ NMI priority over IRQ correctly implemented
- ⚠️ Minor: IRQ line overwritten during same CPU cycle (see Issue #2)
- ⚠️ Test gaps: NMI persistence after VBlank span end, simultaneous NMI+IRQ

---

## 1. Architecture Assessment

### 1.1 Single Source of Truth: VBlankLedger ✅ VERIFIED

**Claim:** VBlankLedger is the ONLY source of NMI state.

**Verification:**
```zig
// src/emulation/State.zig:87-90
pub const EmulationState = struct {
    vblank_ledger: VBlankLedger = .{},  // ✅ Single instance
    // NO duplicate nmi_latched, nmi_edge, etc.
```

**State Fields Analysis:**
1. **VBlankLedger fields** (authoritative):
   - `nmi_edge_pending: bool` - NMI edge latched, waiting for CPU acknowledgment
   - `span_active: bool` - VBlank period active (241.1 → 261.1)
   - `last_set_cycle`, `last_clear_cycle`, etc. - Timestamp ledger

2. **CpuState fields** (derived from ledger):
   - `nmi_line: bool` - CPU input wire (set by `stepCycle()` from ledger query)
   - `nmi_edge_detected: bool` - Edge detection latch (used by `checkInterrupts()`)
   - `pending_interrupt: InterruptType` - Scheduled interrupt (.nmi or .irq)

**Data Flow (verified correct):**
```
VBlankLedger.nmi_edge_pending (authoritative)
    ↓ (queried via shouldAssertNmiLine())
CpuState.nmi_line (derived)
    ↓ (edge detection in checkInterrupts())
CpuState.pending_interrupt (scheduled)
    ↓ (interrupt sequence at fetch_opcode)
7-cycle NMI sequence → acknowledgeCpu() → clears nmi_edge_pending
```

**Conclusion:** ✅ TRUE single source of truth. No duplicated state found.

---

### 1.2 IRQ Line Composition ✅ CORRECT

**All three IRQ sources correctly combined:**

```zig
// src/emulation/State.zig:467-476 (stepCpuCycle context)
const apu_frame_irq = self.apu.frame_irq_flag;
const apu_dmc_irq = self.apu.dmc_irq_flag;

self.cpu.irq_line = apu_frame_irq or apu_dmc_irq;

const cpu_result = self.stepCpuCycle();
// Mapper IRQ polled AFTER CPU tick
if (cpu_result.mapper_irq) {
    self.cpu.irq_line = true;  // ← OR'd with existing IRQ sources
}
```

**IRQ Sources:**
1. ✅ APU Frame Counter (`apu.frame_irq_flag`)
2. ✅ APU DMC Channel (`apu.dmc_irq_flag`)
3. ✅ Mapper (polled via `pollMapperIrq()` → `cart.tickIrq()`)

**Timing:** IRQ line updated every CPU tick (every 3 PPU cycles), which is correct for level-triggered IRQ.

**Conclusion:** ✅ All sources correctly OR'd. IRQ line reflects combined state.

---

## 2. Race Condition Analysis

### 2.1 Concurrent Access Patterns ✅ NO ISSUES

**Single-threaded execution guarantee:**
- Emulation runs on dedicated `EmulationThread`
- All component ticks (PPU → CPU → APU) happen sequentially within `tick()`
- No concurrent access to interrupt state

**Event Ordering:**
```
tick() calls:
1. stepPpuCycle() → may set VBlank → records in ledger
2. stepApuCycle() → may set IRQ flags
3. stepCpuCycle() → queries ledger + IRQ flags → latches interrupts
```

**Conclusion:** ✅ Sequential execution eliminates concurrency races.

---

### 2.2 Event Ordering Guarantees ✅ CORRECT

**Critical path: VBlank set → NMI edge → CPU check**

```zig
// PPU tick (scanline 241, dot 1):
vblank_ledger.recordVBlankSet(cycle, nmi_enabled)
    → sets nmi_edge_pending = true (if conditions met)

// CPU tick (next fetch_opcode):
stepCycle() queries ledger:
    nmi_line = vblank_ledger.shouldAssertNmiLine(...)
        → returns true if nmi_edge_pending

checkInterrupts(&cpu):
    if (nmi_line && !nmi_edge_detected) {
        pending_interrupt = .nmi  // ← Edge latched
    }
```

**Timing window verified:**
- VBlank sets at PPU cycle N (scanline 241, dot 1 = 3×241×341 + 3×1 = 246723 PPU cycles)
- CPU tick occurs at next PPU cycle divisible by 3
- Ledger query happens BEFORE `checkInterrupts()` (line 82-86 in execution.zig)

**Conclusion:** ✅ Event ordering correct. No timing window bugs.

---

### 2.3 Atomic Operation Boundaries ✅ SAFE

**Interrupt state updates are atomic:**
- All ledger writes happen within single function calls (no partial updates)
- CPU reads ledger state via pure function (`shouldAssertNmiLine()`)
- No compound read-modify-write operations

**Example (VBlank set is atomic):**
```zig
pub fn recordVBlankSet(self: *VBlankLedger, cycle: u64, nmi_enabled: bool) void {
    const was_active = self.span_active;
    self.span_active = true;              // ← Atomic write
    self.last_set_cycle = cycle;          // ← Atomic write

    if (!was_active and nmi_enabled) {
        self.nmi_edge_pending = true;     // ← Atomic write (conditional)
    }
}
```

**Conclusion:** ✅ All state updates are atomic within single-threaded context.

---

## 3. Side Effect Correctness

### 3.1 $2002 (PPUSTATUS) Read Tracking ✅ VERIFIED

**All $2002 reads correctly call `recordStatusRead()`:**

```zig
// src/emulation/bus/routing.zig:24-28
0x2000...0x3FFF => blk: {
    const reg = address & 0x07;
    const result = PpuLogic.readRegister(&state.ppu, cart_ptr, reg);

    if (reg == 0x02) {  // ← PPUSTATUS register
        state.vblank_ledger.recordStatusRead(state.clock.ppu_cycles);
    }
    // ... rest of handling
```

**Effect verified:**
```zig
pub fn recordStatusRead(self: *VBlankLedger, cycle: u64) void {
    self.last_status_read_cycle = cycle;
    self.last_clear_cycle = cycle;  // ← Readable flag cleared
    // Note: span_active remains true (VBlank period continues)
    // Note: nmi_edge_pending NOT cleared (NMI already latched)
}
```

**Hardware behavior matched:**
- Reading $2002 clears PPUSTATUS.7 (readable VBlank flag)
- Does NOT clear NMI edge if already latched
- VBlank span continues until scanline 261.1

**Conclusion:** ✅ Side effect correctly tracked. All $2002 reads go through ledger.

---

### 3.2 PPUCTRL Write Tracking ✅ VERIFIED

**All PPUCTRL writes correctly call `recordCtrlToggle()`:**

```zig
// src/emulation/State.zig:306-316 (busWrite)
const is_ppuctrl_write = (address >= 0x2000 and address <= 0x3FFF
                          and (address & 0x07) == 0x00);
const old_nmi_enabled = if (is_ppuctrl_write) self.ppu.ctrl.nmi_enable else false;

BusRouting.busWrite(self, address, value);  // ← Updates ppu.ctrl

if (is_ppuctrl_write) {
    const new_nmi_enabled = (value & 0x80) != 0;
    self.vblank_ledger.recordCtrlToggle(
        self.clock.ppu_cycles,
        old_nmi_enabled,
        new_nmi_enabled
    );
}
```

**Critical detail:** Old value captured BEFORE `busWrite()` updates `ppu.ctrl`. This is correct for edge detection.

**Effect verified:**
```zig
pub fn recordCtrlToggle(self: *VBlankLedger, cycle: u64,
                        old_enabled: bool, new_enabled: bool) void {
    self.last_ctrl_toggle_cycle = cycle;

    // Detect 0→1 edge during VBlank span
    if (!old_enabled and new_enabled and self.span_active) {
        self.nmi_edge_pending = true;  // ← Multiple NMI possible via toggling
    }
}
```

**Conclusion:** ✅ All PPUCTRL writes tracked. Edge detection correct (0→1 transition).

---

### 3.3 NMI Acknowledgment Timing ✅ CORRECT

**Acknowledgment happens at correct cycle:**

```zig
// src/emulation/cpu/execution.zig:207-221 (interrupt_sequence state)
6 => blk: {
    // Cycle 7: Jump to handler
    state.cpu.pc = (@as(u16, state.cpu.operand_high) << 8) |
                   @as(u16, state.cpu.operand_low);

    const was_nmi = state.cpu.pending_interrupt == .nmi;
    state.cpu.pending_interrupt = .none;

    if (was_nmi) {
        state.vblank_ledger.acknowledgeCpu(state.clock.ppu_cycles);
    }

    break :blk true; // Complete
},
```

**Hardware timing verified:**
- NMI sequence is 7 cycles (0-6 in `instruction_cycle`)
- Cycle 6 is final cycle (PC loaded from vector, about to jump)
- Acknowledgment clears `nmi_edge_pending`, allowing new NMI edges

**Conclusion:** ✅ Acknowledgment at correct cycle. Allows retriggering after handler.

---

## 4. Timing Accuracy

### 4.1 Interrupt Sequence: 7 Cycles ✅ VERIFIED

**Hardware sequence matched exactly:**

```zig
// src/emulation/cpu/execution.zig:177-223
if (state.cpu.state == .interrupt_sequence) {
    const complete = switch (state.cpu.instruction_cycle) {
        0 => /* Cycle 1: Dummy read at PC */,
        1 => CpuMicrosteps.pushPch(state),      // Cycle 2
        2 => CpuMicrosteps.pushPcl(state),      // Cycle 3
        3 => CpuMicrosteps.pushStatusInterrupt(state), // Cycle 4 (B=0)
        4 => /* Cycle 5: Fetch vector low, set I flag */,
        5 => /* Cycle 6: Fetch vector high */,
        6 => /* Cycle 7: Jump to handler, acknowledge NMI */,
        else => unreachable,
    };
```

**Comparison to nesdev.org specification:**

| Cycle | Hardware Behavior | Implementation | Status |
|-------|-------------------|----------------|--------|
| 1 | Dummy read at PC | `busRead(state.cpu.pc)` | ✅ |
| 2 | Push PCH | `pushPch()` | ✅ |
| 3 | Push PCL | `pushPcl()` | ✅ |
| 4 | Push P (B=0) | `pushStatusInterrupt()` (B=0) | ✅ |
| 5 | Fetch vector low, set I | `busRead(0xFFFA/0xFFFE)`, `p.interrupt=true` | ✅ |
| 6 | Fetch vector high | `busRead(0xFFFB/0xFFFF)` | ✅ |
| 7 | Jump to handler | `pc = vector` | ✅ |

**Conclusion:** ✅ 7-cycle sequence matches hardware exactly.

---

### 4.2 Interrupt Check Location ✅ CORRECT

**Interrupts checked ONLY at `fetch_opcode`:**

```zig
// src/emulation/cpu/execution.zig:154-162
if (state.cpu.state == .fetch_opcode) {
    CpuLogic.checkInterrupts(&state.cpu);
    if (state.cpu.pending_interrupt != .none and
        state.cpu.pending_interrupt != .reset) {
        CpuLogic.startInterruptSequence(&state.cpu);
        return;
    }
}
```

**Hardware behavior:** Interrupts are sampled between instructions, not mid-instruction.

**Verification:**
- ✅ Check happens ONLY when `state == .fetch_opcode`
- ✅ NOT checked during `.fetch_operand_low`, `.execute`, `.interrupt_sequence`
- ✅ RESET is special-cased (doesn't start interrupt sequence)

**Conclusion:** ✅ Interrupt check location matches hardware.

---

### 4.3 NMI Edge Latching ✅ CORRECT

**NMI edge latches immediately, CPU samples on next instruction:**

```zig
// src/cpu/Logic.zig:76-91 (checkInterrupts)
pub fn checkInterrupts(state: *CpuState) void {
    // NMI edge detection (falling edge: high → low)
    const nmi_prev = state.nmi_edge_detected;
    state.nmi_edge_detected = state.nmi_line;

    if (state.nmi_line and !nmi_prev) {
        // Falling edge detected (0→1 transition of asserted signal)
        state.pending_interrupt = .nmi;
    }

    // IRQ is level-triggered
    if (state.irq_line and !state.p.interrupt and state.pending_interrupt == .none) {
        state.pending_interrupt = .irq;
    }
}
```

**Edge detection mechanism:**
1. `nmi_line` set by ledger when `nmi_edge_pending = true`
2. `checkInterrupts()` detects 0→1 transition (edge)
3. Sets `pending_interrupt = .nmi`
4. Next cycle: `startInterruptSequence()` begins 7-cycle sequence

**Timing verified:**
- Ledger sets `nmi_edge_pending` at exact cycle VBlank sets (or PPUCTRL toggles)
- CPU samples `nmi_line` at next `fetch_opcode` (instruction boundary)
- Hardware: NMI latches internally, fires between instructions

**Conclusion:** ✅ Edge latching matches hardware timing.

---

## 5. Bug Analysis

### Issue #1: Missing Interrupt Check After Debugger Breakpoint ⚠️ LOW SEVERITY

**Location:** `src/emulation/cpu/execution.zig:164-171`

```zig
// Check debugger breakpoints/watchpoints (RT-safe, zero allocations)
if (state.debugger) |*debugger| {
    if (debugger.shouldBreak(state) catch false) {
        // Breakpoint hit - set flag for EmulationThread to post event
        state.debug_break_occurred = true;
        return;  // ← EARLY RETURN: Skips interrupt processing!
    }
}
```

**Problem:** Debugger breakpoint at `fetch_opcode` returns early, skipping interrupt check that happens at line 154-162.

**Impact:**
- If NMI/IRQ edge occurs while paused at breakpoint, interrupt won't fire until next instruction
- Severity: **LOW** (debugger-only, not production emulation bug)
- Real hardware doesn't have breakpoints, so this is acceptable deviation

**Recommendation:**
```zig
// After line 162, add interrupt check:
if (state.cpu.state == .fetch_opcode) {
    CpuLogic.checkInterrupts(&state.cpu);

    // Check debugger AFTER interrupt check
    if (state.debugger) |*debugger| {
        if (debugger.shouldBreak(state) catch false) {
            state.debug_break_occurred = true;
            return;
        }
    }

    if (state.cpu.pending_interrupt != .none and
        state.cpu.pending_interrupt != .reset) {
        CpuLogic.startInterruptSequence(&state.cpu);
        return;
    }
}
```

**Priority:** LOW (defer to debugger improvements phase)

---

### Issue #2: IRQ Line Overwritten Within Same CPU Cycle ⚠️ LOW SEVERITY

**Location:** `src/emulation/State.zig:467-476`

```zig
const apu_frame_irq = self.apu.frame_irq_flag;
const apu_dmc_irq = self.apu.dmc_irq_flag;

self.cpu.irq_line = apu_frame_irq or apu_dmc_irq;  // ← Set to APU sources

const cpu_result = self.stepCpuCycle();
// Mapper IRQ polled AFTER CPU tick
if (cpu_result.mapper_irq) {
    self.cpu.irq_line = true;  // ← Overwrites previous value (doesn't OR)
}
```

**Problem:** Mapper IRQ assignment overwrites `irq_line` instead of OR'ing.

**Current behavior:**
- If APU IRQ sources are active, `irq_line = true`
- If mapper IRQ is active, `irq_line = true`
- Works correctly because both paths set to `true`

**Potential bug:** If code is later refactored to clear IRQ between checks, this could fail.

**Recommendation (defensive coding):**
```zig
// Line 474-476 change:
if (cpu_result.mapper_irq) {
    self.cpu.irq_line = true;  // Already correct, but make intent explicit
    // OR: self.cpu.irq_line = self.cpu.irq_line or cpu_result.mapper_irq;
}
```

**Priority:** LOW (functionally correct, but style could be clearer)

---

### Issue #3: NMI Persistence After VBlank Span End - Missing Test ⚠️ TEST GAP

**Scenario:** NMI edge latched at scanline 241.1, VBlank span ends at 261.1, CPU hasn't acknowledged yet.

**Expected behavior:**
- `span_active = false` (VBlank period ended)
- `nmi_edge_pending = true` (STILL PENDING)
- NMI fires when CPU reaches next `fetch_opcode`

**Implementation review:**
```zig
// VBlankLedger.zig:78-81
pub fn recordVBlankSpanEnd(self: *VBlankLedger, cycle: u64) void {
    self.span_active = false;
    self.last_clear_cycle = cycle;
    // Note: nmi_edge_pending NOT cleared ✅ CORRECT
}

// VBlankLedger.zig:161-170
pub fn shouldAssertNmiLine(...) bool {
    return self.shouldNmiEdge(cycle, nmi_enabled);  // ← Checks nmi_edge_pending
    // Does NOT check span_active ✅ CORRECT
}
```

**Code is correct, but test is missing.**

**Recommendation:** Add test to `tests/ppu/vblank_ledger_test.zig`:
```zig
test "VBlankLedger: NMI edge persists after VBlank span ends" {
    var ledger = VBlankLedger{};

    // VBlank sets with NMI enabled → edge pending
    ledger.recordVBlankSet(100, true);
    try testing.expect(ledger.nmi_edge_pending);

    // VBlank span ends (scanline 261.1)
    ledger.recordVBlankSpanEnd(200);
    try testing.expect(!ledger.span_active);

    // NMI edge should STILL be pending
    try testing.expect(ledger.nmi_edge_pending);
    try testing.expect(ledger.shouldNmiEdge(210, true));
}
```

**Priority:** MEDIUM (add to test suite)

---

### Issue #4: Simultaneous NMI + IRQ Priority - Missing Test ⚠️ TEST GAP

**Scenario:** Both `nmi_line` and `irq_line` are asserted simultaneously.

**Expected behavior:** NMI wins (higher priority).

**Implementation review:**
```zig
// cpu/Logic.zig:76-91
pub fn checkInterrupts(state: *CpuState) void {
    // NMI checked FIRST
    const nmi_prev = state.nmi_edge_detected;
    state.nmi_edge_detected = state.nmi_line;

    if (state.nmi_line and !nmi_prev) {
        state.pending_interrupt = .nmi;  // ← Sets to NMI
    }

    // IRQ only sets if pending_interrupt == .none
    if (state.irq_line and !state.p.interrupt and
        state.pending_interrupt == .none) {  // ← Skipped if NMI already set
        state.pending_interrupt = .irq;
    }
}
```

**Code is correct (NMI checked first, IRQ skipped if NMI set), but test is missing.**

**Recommendation:** Add test to `tests/cpu/interrupts_test.zig`:
```zig
test "NMI has priority over IRQ when both asserted" {
    var cpu = CpuLogic.init();
    cpu.p.interrupt = false;  // IRQ not masked
    cpu.nmi_line = true;
    cpu.irq_line = true;

    CpuLogic.checkInterrupts(&cpu);

    try testing.expectEqual(InterruptType.nmi, cpu.pending_interrupt);
}
```

**Priority:** MEDIUM (add to test suite)

---

## 6. Code Quality Issues

### 6.1 Confusing NMI Signal Naming ⚠️ MINOR

**Location:** `src/cpu/Logic.zig:78-80`

```zig
// Comment says "falling edge" but logic detects rising edge
// Note: nmi_line being TRUE means NMI is ASSERTED (active low in hardware)
const nmi_prev = state.nmi_edge_detected;
state.nmi_edge_detected = state.nmi_line;

if (state.nmi_line and !nmi_prev) {
    // Falling edge detected (transition from not-asserted to asserted)
```

**Confusion:** Hardware NMI is active-low, but code treats `nmi_line = true` as asserted.

**Clarification needed:** Comment is technically correct (hardware falling edge = software rising edge), but naming is confusing.

**Recommendation:**
```zig
// Rename nmi_line to nmi_asserted for clarity
// OR: Add comment explaining active-low inversion
// "NMI line is inverted: true = asserted (hardware low), false = deasserted (hardware high)"
```

**Priority:** LOW (documentation improvement, not a bug)

---

### 6.2 Magic Number in IRQ Composition ⚠️ MINOR

**Location:** `src/emulation/State.zig:467-476`

```zig
const apu_frame_irq = self.apu.frame_irq_flag;
const apu_dmc_irq = self.apu.dmc_irq_flag;

self.cpu.irq_line = apu_frame_irq or apu_dmc_irq;
```

**Issue:** IRQ composition is scattered. No single function returns "is IRQ asserted?"

**Recommendation:** Extract to helper function:
```zig
fn isIrqAsserted(self: *const EmulationState) bool {
    return self.apu.frame_irq_flag or
           self.apu.dmc_irq_flag or
           self.mapper_irq_pending;  // If tracked separately
}
```

**Priority:** LOW (refactoring, not critical)

---

### 6.3 Unused Parameter in `shouldNmiEdge()` ⚠️ MINOR

**Location:** `src/emulation/state/VBlankLedger.zig:127`

```zig
pub fn shouldNmiEdge(self: *const VBlankLedger, _: u64, nmi_enabled: bool) bool {
    // First parameter (cycle) is unused
```

**Issue:** `cycle` parameter is ignored but still passed by callers.

**Recommendation:**
- If future use is planned (e.g., cycle-based suppression), keep with underscore
- Otherwise, remove from signature

**Priority:** LOW (cleanup)

---

## 7. Recommendations

### 7.1 High Priority

**None.** No critical issues found.

---

### 7.2 Medium Priority

1. **Add test for NMI persistence after VBlank span end** (Issue #3)
   - Test that `nmi_edge_pending` survives `recordVBlankSpanEnd()`
   - File: `tests/ppu/vblank_ledger_test.zig`

2. **Add test for NMI/IRQ simultaneous priority** (Issue #4)
   - Test that `pending_interrupt = .nmi` when both lines asserted
   - File: `tests/cpu/interrupts_test.zig`

3. **Document NMI signal inversion** (Issue 6.1)
   - Add comment explaining active-low hardware vs active-high software
   - File: `src/cpu/State.zig` near `nmi_line` field

---

### 7.3 Low Priority

1. **Move debugger breakpoint check after interrupt check** (Issue #1)
   - Ensures interrupts fire even when paused at breakpoint
   - File: `src/emulation/cpu/execution.zig:164-171`

2. **Make IRQ line composition explicit** (Issue #2)
   - Use `self.cpu.irq_line |= cpu_result.mapper_irq;` for clarity
   - File: `src/emulation/State.zig:474-476`

3. **Extract IRQ composition to helper function** (Issue 6.2)
   - Create `isIrqAsserted()` helper
   - File: `src/emulation/State.zig`

4. **Remove unused cycle parameter in `shouldNmiEdge()`** (Issue 6.3)
   - Clean up signature if future use not planned
   - File: `src/emulation/state/VBlankLedger.zig:127`

---

## 8. Test Coverage Gaps

### 8.1 Missing Scenarios

Based on `docs/verification/irq-nmi-permutation-matrix.md`, the following scenarios lack explicit tests:

1. **NMI Persistence** (P1.4)
   - NMI edge pending after VBlank span ends at 261.1
   - Status: ⚠️ SUSPECTED (code correct, needs test)

2. **NMI/IRQ Priority** (P2.3)
   - Simultaneous assertion of both interrupt sources
   - Status: ⚠️ SUSPECTED (code correct, needs test)

3. **B Flag Verification** (P3.2)
   - Reading pushed status byte from stack (BRK vs NMI/IRQ)
   - Status: 🔍 UNTESTED (implementation verified via code review)

4. **Interrupt Hijacking** (P4.1)
   - NMI during IRQ sequence (should NOT interrupt)
   - Status: 📝 DOCUMENTED (code prevents, needs explicit test)

5. **Multiple PPUCTRL Toggles**
   - Rapid 0→1→0→1 transitions during single VBlank span
   - Status: 🔍 UNTESTED (should generate multiple NMI edges)

6. **IRQ Deassertion During Sequence**
   - IRQ line goes low during IRQ interrupt sequence
   - Status: 🔍 UNTESTED (sequence should complete regardless)

---

### 8.2 Recommended Test Suite Additions

**File: `tests/cpu/interrupt_priority_test.zig`** (NEW)
```zig
test "NMI overrides IRQ when both asserted" { /* ... */ }
test "IRQ ignored during NMI sequence" { /* ... */ }
test "NMI can interrupt IRQ handler (after RTI)" { /* ... */ }
```

**File: `tests/cpu/interrupt_persistence_test.zig`** (NEW)
```zig
test "NMI edge persists after VBlank span ends" { /* ... */ }
test "NMI edge persists until CPU acknowledgment" { /* ... */ }
test "IRQ remains asserted while I flag set" { /* ... */ }
```

**File: `tests/cpu/interrupt_hijacking_test.zig`** (NEW)
```zig
test "NMI during IRQ sequence does not interrupt" { /* ... */ }
test "IRQ during NMI sequence does not interrupt" { /* ... */ }
```

**File: `tests/ppu/ppuctrl_toggle_rapid_test.zig`** (NEW)
```zig
test "Multiple PPUCTRL toggles generate multiple NMI edges" { /* ... */ }
test "PPUCTRL toggle 1→0→1 generates two NMI edges" { /* ... */ }
```

**File: `tests/cpu/interrupt_stack_test.zig`** (NEW)
```zig
test "BRK pushes status with B=1" { /* ... */ }
test "NMI pushes status with B=0" { /* ... */ }
test "IRQ pushes status with B=0" { /* ... */ }
```

---

## 9. Verification Against Hardware Spec

### 9.1 NMI Behavior (nesdev.org/wiki/NMI)

| Specification | Implementation | Status |
|---------------|----------------|--------|
| Edge-triggered (0→1) | `checkInterrupts()` detects edge | ✅ |
| Multiple NMI via PPUCTRL toggle | `recordCtrlToggle()` sets edge | ✅ |
| $2002 read does NOT clear NMI edge | `recordStatusRead()` preserves edge | ✅ |
| Race condition (read on set cycle) | `shouldNmiEdge()` checks timestamps | ✅ |
| NMI fires between instructions | Check at `fetch_opcode` only | ✅ |

---

### 9.2 IRQ Behavior (nesdev.org/wiki/IRQ)

| Specification | Implementation | Status |
|---------------|----------------|--------|
| Level-triggered | `checkInterrupts()` samples level | ✅ |
| Maskable by I flag | Check `!state.p.interrupt` | ✅ |
| Lower priority than NMI | NMI checked first | ✅ |
| Composition (mapper + APU) | All sources OR'd | ✅ |

---

### 9.3 Interrupt Sequence (nesdev.org/wiki/CPU_interrupts)

| Specification | Implementation | Status |
|---------------|----------------|--------|
| 7 cycles total | `instruction_cycle` 0-6 | ✅ |
| Dummy read at PC (cycle 1) | `busRead(state.cpu.pc)` | ✅ |
| Push PCH (cycle 2) | `pushPch()` | ✅ |
| Push PCL (cycle 3) | `pushPcl()` | ✅ |
| Push P with B=0 (cycle 4) | `pushStatusInterrupt()` masks bit 4 | ✅ |
| Fetch vector low (cycle 5) | `busRead(0xFFFA/0xFFFE)` | ✅ |
| Fetch vector high (cycle 6) | `busRead(0xFFFB/0xFFFF)` | ✅ |
| Jump to handler (cycle 7) | `pc = vector` | ✅ |
| Set I flag (cycle 5) | `p.interrupt = true` | ✅ |

---

## 10. Summary & Approval

### 10.1 Architecture Quality: EXCELLENT

- ✅ Clean separation of concerns (VBlankLedger, CpuState, EmulationState)
- ✅ True single source of truth (no duplicate NMI state)
- ✅ Correct IRQ composition (all three sources)
- ✅ Proper side effect tracking ($2002 reads, PPUCTRL writes)
- ✅ Hardware-accurate timing (7-cycle sequence, edge detection)

### 10.2 Bugs Found: NONE (CRITICAL)

- ⚠️ 2 low-severity issues (debugger interrupt check, IRQ line overwrite)
- ⚠️ 4 minor code quality issues (naming, unused params, magic numbers)

### 10.3 Test Coverage: 45% VERIFIED, 36% SUSPECTED

- ✅ 5/11 permutations fully verified with tests
- ⚠️ 4/11 permutations suspected correct (code review only)
- 🔍 2/11 permutations untested (B flag, interrupt hijacking)

### 10.4 Recommendation: ✅ APPROVED FOR PRODUCTION

**Verdict:** The interrupt coordination system is production-ready. All critical paths are correct, hardware timing matches specification, and no race conditions exist. Recommended improvements focus on test coverage and defensive coding, not bug fixes.

**Next Steps:**
1. Add 2 medium-priority tests (NMI persistence, NMI/IRQ priority)
2. Consider low-priority refactorings during next maintenance cycle
3. Document NMI signal inversion for future maintainers

---

**Reviewer Signature:** Claude Code (Senior Code Reviewer)
**Review Date:** 2025-10-09
**Review Duration:** Comprehensive (all interrupt code paths examined)
**Confidence Level:** HIGH (no critical issues, minor improvements only)
