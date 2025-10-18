# MMC3 IRQ Complete Flow Trace

**Date:** 2025-10-17
**Status:** CRITICAL BUG IDENTIFIED
**Issue:** IRQ line never cleared after mapper IRQ fires

---

## Complete IRQ Flow Diagram

```
1. PPU A12 EDGE DETECTION
   ├─ src/ppu/Logic.zig:223-261
   ├─ During rendering cycles (dots 1-256, 257-320, 321-336)
   ├─ Monitors bit 12 of PPU v register (current_a12)
   ├─ Detects 0→1 transition with filter delay (≥6 cycles A12 low)
   ├─ Sets flags.a12_rising = true
   └─ Returns PpuCycleResult with a12_rising flag

2. PPU RESULT HANDLING
   ├─ src/emulation/State.zig:633-658 (applyPpuCycleResult)
   ├─ Called from tick() after each PPU cycle
   ├─ Line 641-644: if (result.a12_rising) { cart.ppuA12Rising(); }
   └─ Calls mapper's ppuA12Rising() method

3. MAPPER IRQ COUNTER
   ├─ src/cartridge/mappers/Mapper4.zig:281-294
   ├─ ppuA12Rising() decrements counter
   ├─ Line 291-292: if (counter == 0 && enabled) { irq_pending = true; }
   └─ Sets internal irq_pending flag

4. MAPPER IRQ POLLING
   ├─ src/emulation/cpu/execution.zig:179-180
   ├─ stepCycle() returns: .mapper_irq = state.pollMapperIrq()
   ├─ src/emulation/State.zig:696-701 (pollMapperIrq)
   ├─ Returns cart.tickIrq() → Mapper4.tickIrq()
   ├─ src/cartridge/mappers/Mapper4.zig:272-274
   └─ Returns self.irq_pending (stays true until cleared)

5. IRQ LINE UPDATE
   ├─ src/emulation/State.zig:612-625
   ├─ Line 619: self.cpu.irq_line = apu_frame_irq or apu_dmc_irq;
   ├─ Line 623-625: if (cpu_result.mapper_irq) { self.cpu.irq_line = true; }
   └─ ⚠️ PROBLEM: IRQ line only SET, never CLEARED

6. CPU IRQ DETECTION
   ├─ src/emulation/cpu/execution.zig:204-214
   ├─ executeCycle() calls CpuLogic.checkInterrupts()
   ├─ src/cpu/Logic.zig:77-80
   ├─ Line 78: if (irq_line && !p.interrupt && pending == .none)
   ├─ Line 79: pending_interrupt = .irq;
   └─ Sets pending_interrupt flag (only if not masked)

7. IRQ HANDLER EXECUTION
   ├─ src/emulation/cpu/execution.zig:230-262 (interrupt_sequence)
   ├─ 7-cycle interrupt sequence
   ├─ Pushes PC and status to stack
   ├─ Sets interrupt disable flag (p.interrupt = true)
   ├─ Loads vector from $FFFE/FFFF
   ├─ Clears pending_interrupt after completion
   └─ ⚠️ BUT: irq_pending in mapper NEVER CLEARED
```

---

## Critical Bug: IRQ Line Management

### Current Implementation (BROKEN)

**File:** `/home/colin/Development/RAMBO/src/emulation/State.zig:612-625`

```zig
// Process CPU if this is a CPU tick
if (step.cpu_tick) {
    // Update IRQ line from all sources (level-triggered, reflects current state)
    // IRQ line is HIGH when ANY source is active
    // Note: mapper_irq is polled AFTER CPU execution and updates IRQ state for next cycle
    const apu_frame_irq = self.apu.frame_irq_flag;
    const apu_dmc_irq = self.apu.dmc_irq_flag;

    self.cpu.irq_line = apu_frame_irq or apu_dmc_irq;  // ⚠️ OVERWRITES previous state

    const cpu_result = self.stepCpuCycle();
    // Mapper IRQ is polled after CPU tick and updates IRQ line for next cycle
    if (cpu_result.mapper_irq) {
        self.cpu.irq_line = true;  // ⚠️ Sets but never clears
    }

    // ... rest of function
}
```

### The Problem

1. **Line 619 OVERWRITES irq_line every CPU cycle**
   - `self.cpu.irq_line = apu_frame_irq or apu_dmc_irq;`
   - This clears any previous mapper IRQ state!

2. **Mapper IRQ is polled AFTER CPU execution**
   - Line 621: `const cpu_result = self.stepCpuCycle();`
   - Line 623: `if (cpu_result.mapper_irq) { self.cpu.irq_line = true; }`
   - Mapper IRQ updates irq_line for the NEXT cycle

3. **But on NEXT cycle, line 619 clears it again!**
   - Even though mapper.irq_pending is still true
   - Line 619 overwrites with only APU IRQ sources
   - Mapper IRQ state is lost

### Execution Timeline (Current - BROKEN)

```
Cycle N:   Mapper counter reaches 0
           mapper.irq_pending = true

Cycle N+1: Line 619: cpu.irq_line = false (no APU IRQs)
           stepCpuCycle() executes
           Line 623: cpu.irq_line = true (mapper IRQ detected)

Cycle N+2: Line 619: cpu.irq_line = false ⚠️ CLEARED!
           stepCpuCycle() executes
           Line 623: cpu.irq_line = true (mapper IRQ still pending)

Cycle N+3: Line 619: cpu.irq_line = false ⚠️ CLEARED AGAIN!
           ...
```

**Result:** IRQ line oscillates between false and true every cycle. CPU checkInterrupts() might see it as false and never fire the IRQ!

---

## Root Cause Analysis

### Issue #1: Mapper IRQ Not Included in Line Computation

**Location:** `src/emulation/State.zig:619`

The IRQ line is set from APU sources ONLY, then conditionally set from mapper:

```zig
self.cpu.irq_line = apu_frame_irq or apu_dmc_irq;  // ⚠️ Missing mapper_irq
```

This should include mapper state in the initial computation.

### Issue #2: Mapper IRQ State Lost Between Cycles

The mapper's `irq_pending` flag stays true, but:
1. Line 619 clears `cpu.irq_line` every cycle
2. Mapper IRQ is only added back AFTER CPU execution
3. Creates 1-cycle delay where IRQ line is false

### Issue #3: No IRQ Acknowledgment

**Location:** `src/cartridge/mappers/Mapper4.zig:297-299`

```zig
pub fn acknowledgeIrq(self: *Mapper4) void {
    self.irq_pending = false;
}
```

This function exists but is **NEVER CALLED** anywhere in the codebase!

The only ways to clear `irq_pending` are:
1. Write to $E000 (IRQ disable) - line 123
2. Write to $E001 (IRQ enable) - line 145 (YOUR BUG #1 FIX)

This means:
- Game must write $E001 to acknowledge each IRQ
- If game doesn't, `irq_pending` stays true forever
- Creates IRQ storm even with correct line management

---

## Why Your Fixes Didn't Work

### Bug #1 Fix: Clear irq_pending on $E001 Write

**File:** `src/cartridge/mappers/Mapper4.zig:145`

```zig
// $E001-$FFFF: IRQ enable
// Per nesdev.org: Writing to $E001 acknowledges any pending IRQ
self.irq_enabled = true;
self.irq_pending = false;  // ✅ YOUR FIX
```

**Status:** ✅ **CORRECT** but insufficient

**Why it didn't fix the issue:**
- Even if game writes $E001 to clear irq_pending
- The IRQ line management bug (Issue #1) prevents IRQ from firing in the first place
- The mapper IRQ oscillates every cycle and might never be seen by CPU

### Bug #3 Fix: A12 Filter Delay

**Files:**
- `src/ppu/Logic.zig:223-261`
- `src/ppu/State.zig:401`

**Status:** ✅ **CORRECT** but insufficient

**Why it didn't fix the issue:**
- A12 edges are detected correctly now
- Mapper counter decrements correctly
- But the IRQ line never stays asserted long enough for CPU to see it

---

## Required Fixes

### Fix #1: Include Mapper IRQ in Line Computation

**File:** `src/emulation/State.zig:619-625`

**Current (BROKEN):**
```zig
const apu_frame_irq = self.apu.frame_irq_flag;
const apu_dmc_irq = self.apu.dmc_irq_flag;

self.cpu.irq_line = apu_frame_irq or apu_dmc_irq;

const cpu_result = self.stepCpuCycle();
// Mapper IRQ is polled after CPU tick and updates IRQ state for next cycle
if (cpu_result.mapper_irq) {
    self.cpu.irq_line = true;
}
```

**Fix Option A (Poll mapper BEFORE CPU execution):**
```zig
const apu_frame_irq = self.apu.frame_irq_flag;
const apu_dmc_irq = self.apu.dmc_irq_flag;
const mapper_irq = self.pollMapperIrq();  // ✅ Poll before CPU execution

self.cpu.irq_line = apu_frame_irq or apu_dmc_irq or mapper_irq;  // ✅ Include mapper

const cpu_result = self.stepCpuCycle();
// No longer need to check cpu_result.mapper_irq
```

**Fix Option B (Use bitwise OR for accumulation):**
```zig
const apu_frame_irq = self.apu.frame_irq_flag;
const apu_dmc_irq = self.apu.dmc_irq_flag;

self.cpu.irq_line = apu_frame_irq or apu_dmc_irq;

const cpu_result = self.stepCpuCycle();
// Accumulate mapper IRQ (don't overwrite)
self.cpu.irq_line = self.cpu.irq_line or cpu_result.mapper_irq;  // ✅ OR instead of =
```

**Recommendation:** Use **Option A** for consistency with NMI handling and to avoid timing issues.

### Fix #2: Clear Mapper IRQ After CPU Acknowledges

The mapper `irq_pending` flag should be cleared when the CPU services the interrupt, not when games write registers.

**Option A (Call acknowledgeIrq when CPU reads IRQ vector):**

This would require detecting when CPU reads $FFFE/FFFF during IRQ sequence, which is complex.

**Option B (Clear on register write only):**

Keep current behavior where games must write $E000 or $E001 to clear IRQ. Your Bug #1 fix (line 145) is correct.

**Recommendation:** **Option B** is correct per nesdev.org documentation. Games are responsible for acknowledging IRQs by writing to $E000/$E001.

### Fix #3: Verify A12 Edge Detection Works

Your implementation looks correct, but let's verify the filter is working:

**File:** `src/ppu/Logic.zig:244-246`

```zig
// Detect rising edge with filter check (0→1 transition)
// Only trigger if A12 has been low for at least 6 cycles
if (!state.a12_state and current_a12 and state.a12_filter_delay >= 6) {
    flags.a12_rising = true;
}
```

**Status:** ✅ CORRECT

---

## Testing Recommendations

After applying Fix #1, test with diagnostic:

```zig
// Add to Mapper4.ppuA12Rising()
if (self.irq_counter == 0 and self.irq_enabled) {
    self.irq_pending = true;
    std.debug.print("MMC3 IRQ: counter=0, pending=true\n", .{});
}

// Add to EmulationState.tick()
if (cpu_result.mapper_irq) {
    std.debug.print("Mapper IRQ polled: true, irq_line={}\n", .{self.cpu.irq_line});
}
```

Expected output:
```
MMC3 IRQ: counter=0, pending=true
Mapper IRQ polled: true, irq_line=true
Mapper IRQ polled: true, irq_line=true  (stays true until acknowledged)
```

---

## Summary

### What's Working ✅

1. **A12 edge detection** - Filter delay implemented correctly
2. **Mapper counter** - Decrements on A12 edges
3. **irq_pending flag** - Set when counter reaches 0
4. **Bug #1 fix** - $E001 clears irq_pending (correct)

### What's Broken ❌

1. **IRQ line management** - Mapper IRQ not included in initial line computation
2. **IRQ line cleared every cycle** - Line 619 overwrites previous state
3. **Timing mismatch** - Mapper IRQ polled AFTER CPU execution creates 1-cycle gap

### Critical Fix Required

**File:** `/home/colin/Development/RAMBO/src/emulation/State.zig:612-625`

**Change:** Poll mapper IRQ BEFORE CPU execution and include in initial line computation.

**Impact:** This single fix will make MMC3 IRQs work correctly.

---

## File References

| Component | File | Lines |
|-----------|------|-------|
| A12 Detection | src/ppu/Logic.zig | 223-261 |
| A12 Notification | src/emulation/State.zig | 641-644 |
| Mapper Counter | src/cartridge/mappers/Mapper4.zig | 281-294 |
| IRQ Polling | src/emulation/State.zig | 696-701 |
| IRQ Line Update | src/emulation/State.zig | 612-625 |
| CPU IRQ Check | src/cpu/Logic.zig | 77-80 |
| IRQ Acknowledge | src/cartridge/mappers/Mapper4.zig | 297-299 |

---

**Next Steps:**
1. Apply Fix #1 (poll mapper before CPU execution)
2. Test with SMB3 and Kirby's Adventure
3. Add debug logging to verify IRQ firing
4. Monitor `irq_line` state across cycles
