# CPU Test Harness: Reset Sequence Not Completing
**Date:** 2025-10-09
**Status:** Investigation
**Severity:** Medium (Affects test infrastructure, not emulation core)
**Related Test:** `ppustatus_polling_test.zig:228` - "BIT instruction timing"

## Problem Statement

The test harness's `reset()` + `seekToScanlineDot()` sequence doesn't properly complete the CPU reset interrupt handler, leaving the CPU in an intermediate state.

## Symptoms

```
CPU Cycle 1 (fetch_opcode): Before
  State: fetch_operand_low, VBlank: true  ← Expected: fetch_opcode
  After: State: fetch_operand_low, VBlank: true, PC: 0x0002
```

**Expected:** CPU state should be `fetch_opcode` after reset
**Actual:** CPU state is `fetch_operand_low` and never advances

## Root Cause Analysis

### Sequence in Failing Test

```zig
harness.state.reset();                    // Line 244: Start reset sequence (7 CPU cycles)
harness.state.ppu.warmup_complete = true; // Line 245
harness.seekToScanlineDot(241, 0);        // Line 248: Seek advances PPU, but CPU cycles?
```

### CPU Reset Sequence (7 Cycles)

From `src/emulation/cpu/execution.zig:148-197`:
1. **Cycle 0:** Dummy read at PC
2. **Cycle 1:** Push PCH (high byte)
3. **Cycle 2:** Push PCL (low byte)
4. **Cycle 3:** Push status register
5. **Cycle 4:** Fetch reset vector low ($FFFC)
6. **Cycle 5:** Fetch reset vector high ($FFFD)
7. **Cycle 6:** Jump to handler, set `pending_interrupt = .none`, transition to `fetch_opcode`

### Problem

`seekToScanlineDot()` advances the **PPU clock** tick-by-tick, but each `state.tick()` only advances the CPU **every 3 PPU cycles**. The reset sequence may not complete if:
- The seek doesn't advance enough CPU cycles (7 needed)
- The CPU state machine is interrupted mid-sequence

### Hardware 6502 Reset Timing

From `src/emulation/State.zig:195-223`:
```zig
pub fn reset(self: *EmulationState) void {
    self.clock.reset();
    // ...
    const reset_vector = self.busRead16(0xFFFC);
    self.cpu.pc = reset_vector;
    self.cpu.sp = 0xFD;
    self.cpu.p.interrupt = true;
    self.cpu.state = .fetch_opcode;       ← Set to fetch_opcode
    self.cpu.instruction_cycle = 0;
    self.cpu.pending_interrupt = .none;
    // ...
}
```

**Wait!** The `reset()` function **directly** sets `cpu.state = .fetch_opcode` (line 213)! So the CPU should be in `fetch_opcode` immediately after reset, NOT in the interrupt sequence!

This contradicts the symptom. Let me re-check...

## New Hypothesis

If `reset()` sets `state = .fetch_opcode`, but the debug shows `state = fetch_operand_low`, then either:
1. The CPU state is being changed AFTER reset() but BEFORE the test checks it
2. The debug print is showing state from a DIFFERENT execution path
3. There's a timing issue where seek causes the CPU to execute and transition states

Let me check if `seekToScanlineDot()` causes CPU execution...

### seekToScanlineDot() Implementation

From `src/test/Harness.zig:113-129`:
```zig
pub fn seekToScanlineDot(self: *Harness, target_scanline: u16, target_dot: u16) void {
    while (cycles < max_cycles) : (cycles += 1) {
        if (current_sl == target_scanline and current_dot == target_dot) {
            return;
        }
        self.state.tick();  ← Calls full EmulationState.tick()!
    }
}
```

**AHA!** `seekToScanlineDot()` calls `state.tick()`, which executes the **FULL** emulation loop including CPU execution! So:

1. Test calls `reset()` → CPU state = `fetch_opcode`, PC = reset_vector
2. Test calls `seekToScanlineDot(241, 0)` → Advances ~82,000 PPU cycles = ~27,000 CPU cycles
3. During those 27,000 CPU cycles, the CPU **executes instructions** from wherever PC points!
4. If PC points to invalid memory or test_ram isn't set up yet, the CPU reads garbage
5. CPU state machine transitions based on garbage opcodes
6. By the time seek completes, CPU is in an arbitrary state

## The Issue

**test_ram is set AFTER reset but BEFORE seek**, so during seek, the CPU reads from test_ram. But:
- The reset vector ($FFFC-$FFFD) is NOT in test_ram
- reset() reads from cart/bus, gets reset vector (probably 0x0000 or some default)
- PC points to some address
- seek() causes CPU to execute from that address
- CPU reads opcodes from test_ram or open bus
- State machine transitions randomly

## Proper Fix Options

### Option A: Complete Reset Sequence BEFORE Seeking (Recommended)

```zig
harness.state.reset();
harness.state.ppu.warmup_complete = true;

// Execute enough cycles to ensure CPU is stable at PC
// Run 10 CPU cycles to let reset vector load and first instruction fetch
var i: usize = 0;
while (i < 30) : (i += 1) { // 30 PPU cycles = 10 CPU cycles
    harness.state.tick();
}

// NOW seek
harness.seekToScanlineDot(241, 0);
```

### Option B: Set CPU State Manually

```zig
harness.state.reset();
harness.state.ppu.warmup_complete = true;

// Manually ensure CPU is in correct state
harness.state.cpu.state = .fetch_opcode;
harness.state.cpu.pc = 0x0000;

harness.seekToScanlineDot(241, 0);
```

### Option C: Fix Test RAM Setup Order

Set up test_ram BEFORE calling reset():
```zig
// Setup test RAM with reset vector
var test_ram = [_]u8{0} ** 0x8000;
test_ram[0] = 0x2C; // BIT opcode at $0000
// ...
// Setup reset vector to point to $0000
test_ram[0xFFFC & 0x7FFF] = 0x00; // Low byte
test_ram[0xFFFD & 0x7FFF] = 0x00; // High byte

harness.state.bus.test_ram = &test_ram;
harness.state.reset(); // Now reset vector reads correctly
```

## Recommended Solution

**Option A** is safest - always allow reset sequence to complete before seeking. This matches real hardware behavior.

**Option B** is acceptable for tests that need precise control, but feels hacky.

**Option C** requires understanding memory mapping and may not work if test_ram doesn't cover the reset vector range.

## Action Items

- [ ] Document test harness best practices in `src/test/README.md`
- [ ] Add helper function: `harness.resetAndStabilize()`
- [ ] Fix failing "BIT instruction timing" test with Option A
- [ ] Audit other tests using reset() + seek() pattern

## Related Files

- `src/test/Harness.zig` - Test harness implementation
- `src/emulation/cpu/execution.zig:148-197` - Reset interrupt sequence
- `src/emulation/State.zig:195-223` - EmulationState.reset()
- `tests/ppu/ppustatus_polling_test.zig:228` - Failing test

## Status

**Next Steps:** Implement Option A fix in the failing test and verify it resolves the issue.
