# Interrupt Bug Fix Plan - Critical Issue

**Date:** 2025-10-09
**Priority:** 🔴 P0 CRITICAL
**Impact:** Likely causes Super Mario Bros blank screen

---

## The Bug

### Current Behavior (WRONG)

```
Cycle N:   State = .fetch_opcode
           executeCycle() enters fetch_opcode handler
           ├─> checkInterrupts() finds pending NMI
           ├─> startInterruptSequence() sets state = .interrupt_sequence
           └─> return (opcode fetch NEVER happens)

Cycle N+1: Opcode fetch happens HERE (1 cycle late)
           State = .fetch_opcode (state was reset)
           executeCycle() enters fetch_opcode handler
           └─> Reads opcode from PC, increments PC

Cycle N+2: State = .interrupt_sequence, instruction_cycle = 0
           Interrupt sequence STARTS (dummy read)
```

**Result:** Interrupt delayed by 1 cycle

### Expected Behavior (CORRECT)

```
Cycle N:   State = .fetch_opcode
           executeCycle() enters fetch_opcode handler
           ├─> checkInterrupts() finds pending NMI
           ├─> Dummy read at PC (hijacked opcode fetch)
           ├─> state = .interrupt_sequence, instruction_cycle = 1
           └─> return (PC NOT incremented)

Cycle N+1: State = .interrupt_sequence, instruction_cycle = 1
           Push PCH to stack
```

**Result:** Interrupt starts immediately (0-cycle delay)

---

## Root Cause

**File:** `/home/colin/Development/RAMBO/src/emulation/cpu/execution.zig`

**Problem:** Interrupt check happens at line 154, but opcode fetch happens at line 237. The order is:

1. **Line 154:** Check for interrupts (finds pending NMI)
2. **Line 157:** Start interrupt sequence
3. **Line 227:** Return (state machine exits)
4. **Next cycle:** Re-enter at line 236, opcode fetch happens

The opcode fetch that should be "hijacked" already happened in the previous cycle before the interrupt was detected!

---

## The Fix

### Step 1: Move interrupt check to opcode fetch handler

**File:** `/home/colin/Development/RAMBO/src/emulation/cpu/execution.zig:236-261`

**Replace this:**
```zig
// Cycle 1: Always fetch opcode
if (state.cpu.state == .fetch_opcode) {
    state.cpu.opcode = state.busRead(state.cpu.pc);
    state.cpu.data_bus = state.cpu.opcode;
    state.cpu.pc +%= 1;
    // ... rest of fetch logic ...
}
```

**With this:**
```zig
// Cycle 1: Fetch opcode OR start interrupt
if (state.cpu.state == .fetch_opcode) {
    // CHECK INTERRUPTS FIRST (before any bus access)
    CpuLogic.checkInterrupts(&state.cpu);

    if (state.cpu.pending_interrupt != .none and state.cpu.pending_interrupt != .reset) {
        // Interrupt hijacks the opcode fetch
        // Perform dummy read at PC (this is the "hijacked fetch")
        _ = state.busRead(state.cpu.pc);
        // DO NOT increment PC - interrupt vector will set new PC

        // Start interrupt sequence at cycle 1 (we just did cycle 0)
        state.cpu.state = .interrupt_sequence;
        state.cpu.instruction_cycle = 1;  // ← Start at cycle 1, not 0

        // Debug logging
        if (DEBUG_NMI and state.cpu.pending_interrupt == .nmi) {
            std.debug.print("[NMI] Starting NMI sequence at PC=0x{X:0>4}\n", .{state.cpu.pc});
        }
        if (DEBUG_IRQ and state.cpu.pending_interrupt == .irq) {
            std.debug.print("[IRQ] Starting IRQ sequence at PC=0x{X:0>4}\n", .{state.cpu.pc});
        }

        return;
    }

    // No interrupt - proceed with normal opcode fetch
    state.cpu.opcode = state.busRead(state.cpu.pc);
    state.cpu.data_bus = state.cpu.opcode;
    state.cpu.pc +%= 1;

    const entry = CpuModule.dispatch.DISPATCH_TABLE[state.cpu.opcode];
    state.cpu.address_mode = entry.info.mode;
    // ... rest of existing fetch logic ...
}
```

### Step 2: Remove old interrupt check

**Delete lines 154-172** (the old interrupt check before state machine):

```zig
// DELETE THIS ENTIRE BLOCK:
if (state.cpu.state == .fetch_opcode) {
    CpuLogic.checkInterrupts(&state.cpu);
    if (state.cpu.pending_interrupt != .none and state.cpu.pending_interrupt != .reset) {
        if (DEBUG_IRQ and state.cpu.pending_interrupt == .irq) {
            std.debug.print("[IRQ] Starting IRQ sequence at PC=0x{X:0>4}\n", .{state.cpu.pc});
        }
        CpuLogic.startInterruptSequence(&state.cpu);
        return;
    }

    // Check debugger breakpoints/watchpoints (RT-safe, zero allocations)
    if (state.debugger) |*debugger| {
        if (debugger.shouldBreak(state) catch false) {
            state.debug_break_occurred = true;
            return;
        }
    }
}
```

### Step 3: Update interrupt sequence to start at cycle 1

**File:** `/home/colin/Development/RAMBO/src/emulation/cpu/execution.zig:176-233`

**Replace this:**
```zig
if (state.cpu.state == .interrupt_sequence) {
    const complete = switch (state.cpu.instruction_cycle) {
        0 => blk: {
            // Cycle 1: Dummy read at current PC (hijack opcode fetch)
            _ = state.busRead(state.cpu.pc);
            break :blk false;
        },
        1 => CpuMicrosteps.pushPch(state),      // Cycle 2: Push PC high byte
        2 => CpuMicrosteps.pushPcl(state),      // Cycle 3: Push PC low byte
        // ... rest ...
    };
}
```

**With this:**
```zig
if (state.cpu.state == .interrupt_sequence) {
    const complete = switch (state.cpu.instruction_cycle) {
        // NOTE: Cycle 0 (dummy read) already done in fetch_opcode handler
        1 => CpuMicrosteps.pushPch(state),      // Cycle 2: Push PC high byte
        2 => CpuMicrosteps.pushPcl(state),      // Cycle 3: Push PC low byte
        3 => CpuMicrosteps.pushStatusInterrupt(state), // Cycle 4: Push P (B=0)
        4 => blk: {
            // Cycle 5: Fetch vector low byte
            state.cpu.operand_low = switch (state.cpu.pending_interrupt) {
                .nmi => state.busRead(0xFFFA),
                .irq => state.busRead(0xFFFE),
                .reset => state.busRead(0xFFFC),
                else => unreachable,
            };
            state.cpu.p.interrupt = true; // Set I flag
            break :blk false;
        },
        5 => blk: {
            // Cycle 6: Fetch vector high byte
            state.cpu.operand_high = switch (state.cpu.pending_interrupt) {
                .nmi => state.busRead(0xFFFB),
                .irq => state.busRead(0xFFFF),
                .reset => state.busRead(0xFFFD),
                else => unreachable,
            };
            break :blk false;
        },
        6 => blk: {
            // Cycle 7: Jump to handler
            state.cpu.pc = (@as(u16, state.cpu.operand_high) << 8) |
                @as(u16, state.cpu.operand_low);

            // Acknowledge NMI before clearing pending_interrupt
            const was_nmi = state.cpu.pending_interrupt == .nmi;
            state.cpu.pending_interrupt = .none;

            if (was_nmi) {
                state.vblank_ledger.acknowledgeCpu(state.clock.ppu_cycles);
            }

            break :blk true; // Complete
        },
        else => unreachable,
    };

    if (complete) {
        state.cpu.state = .fetch_opcode;
        state.cpu.instruction_cycle = 0;
    } else {
        state.cpu.instruction_cycle += 1;
    }
    return;
}
```

### Step 4: Move debugger check to after interrupt check

**Add this AFTER the interrupt return in fetch_opcode handler:**

```zig
if (state.cpu.state == .fetch_opcode) {
    // Interrupt check (with early return if interrupt hijacks)
    // ... (new code from Step 1) ...

    // Debugger check (only runs if no interrupt)
    if (state.debugger) |*debugger| {
        if (debugger.shouldBreak(state) catch false) {
            state.debug_break_occurred = true;
            return;
        }
    }

    // Opcode fetch continues...
}
```

---

## Bonus Fix: Mapper IRQ Timing

**File:** `/home/colin/Development/RAMBO/src/emulation/State.zig:464-476`

**Replace this:**
```zig
if (step.cpu_tick) {
    // Update IRQ line from APU sources
    const apu_frame_irq = self.apu.frame_irq_flag;
    const apu_dmc_irq = self.apu.dmc_irq_flag;
    self.cpu.irq_line = apu_frame_irq or apu_dmc_irq;

    const cpu_result = self.stepCpuCycle();

    // Mapper IRQ polled AFTER CPU tick (WRONG)
    if (cpu_result.mapper_irq) {
        self.cpu.irq_line = true;
    }
}
```

**With this:**
```zig
if (step.cpu_tick) {
    // Poll mapper IRQ FIRST (before CPU tick)
    const mapper_irq = self.pollMapperIrq();

    // Compose IRQ line from ALL sources
    const apu_frame_irq = self.apu.frame_irq_flag;
    const apu_dmc_irq = self.apu.dmc_irq_flag;
    self.cpu.irq_line = apu_frame_irq or apu_dmc_irq or mapper_irq;

    // CPU tick with correct IRQ state
    _ = self.stepCpuCycle();
}
```

---

## Testing Plan

### 1. Verify Existing Tests Still Pass

```bash
zig build test
```

**Expected:** All 955 passing tests should still pass (no regressions)

### 2. Test Super Mario Bros

```bash
zig build run
# Load Super Mario Bros (World).nes
```

**Expected:**
- PPUMASK should progress: 0x00 → 0x06 → 0x1E
- Rendering should enable
- Title screen should appear

### 3. Add Interrupt Latency Test

**File:** Create `tests/cpu/interrupt_timing_test.zig`

```zig
test "NMI: Response latency is 7 cycles" {
    var harness = try Harness.init();
    defer harness.deinit();

    // Setup: Enable NMI, VBlank at cycle 1000
    harness.state.ppu.ctrl.nmi_enable = true;
    harness.state.clock.advance(1000);

    // Trigger VBlank
    harness.state.vblank_ledger.recordVBlankSet(1000, true);

    // Step 1 CPU cycle - should detect NMI and start sequence
    harness.state.tickCpu();
    try expect(harness.state.cpu.state == .interrupt_sequence);
    try expect(harness.state.cpu.instruction_cycle == 1);  // ← Should be 1, not 0

    // Step 6 more cycles to complete interrupt
    var i: usize = 0;
    while (i < 6) : (i += 1) {
        harness.state.tickCpu();
    }

    // Should now be in NMI handler
    try expect(harness.state.cpu.state == .fetch_opcode);
    try expect(harness.state.cpu.pc == 0xC000); // NMI vector
}
```

---

## Expected Outcomes

### Before Fix
- ❌ Super Mario Bros blank screen
- ❌ Interrupt latency test fails (expects cycle 1, gets cycle 0)
- ✅ AccuracyCoin passes (doesn't test interrupt timing)

### After Fix
- ✅ Super Mario Bros displays title screen
- ✅ Interrupt latency test passes
- ✅ AccuracyCoin still passes (no regressions)
- ✅ All existing interrupt tests pass

---

## Rollback Plan

If the fix causes regressions:

1. **Revert the changes:**
   ```bash
   git checkout HEAD -- src/emulation/cpu/execution.zig src/emulation/State.zig
   ```

2. **Run tests to verify rollback:**
   ```bash
   zig build test
   ```

3. **Document the issue:**
   - Add notes to audit report
   - Create GitHub issue with reproduction steps
   - Investigate alternative fix approaches

---

## Confidence Level

**Root Cause Diagnosis:** 🔴 **HIGH (75%)**

This bug explains:
- Why Super Mario Bros fails (timing-sensitive initialization)
- Why AccuracyCoin passes (doesn't test interrupt timing)
- Why VBlank polling works (doesn't use NMI)

**Fix Correctness:** 🔴 **HIGH (90%)**

The fix aligns with:
- nesdev.org hardware specification (interrupt hijacks opcode fetch)
- 6502 interrupt sequence documentation (7 cycles total)
- Existing test expectations (tests expect immediate response)

**Regression Risk:** 🟡 **LOW (10%)**

- Fix is localized to interrupt handling
- Existing tests should catch any breakage
- VBlankLedger architecture unchanged

---

**Next Steps:** Apply fix and test immediately!
