# MMC3 IRQ Bug - Visual Timeline

**Date:** 2025-10-17
**Critical Bug:** IRQ line cleared every cycle, preventing CPU from seeing IRQ

---

## The Bug in Action

### Current Implementation (BROKEN)

```
Cycle N: Mapper counter hits 0
├─ Mapper4.ppuA12Rising() sets: irq_pending = true
└─ (End of PPU cycle)

Cycle N+1 (CPU tick):
├─ Line 619: cpu.irq_line = apu_frame_irq OR apu_dmc_irq
│            cpu.irq_line = false OR false
│            cpu.irq_line = FALSE  ⚠️ CLEARED!
│
├─ Line 621: stepCpuCycle()
│   ├─ executeCycle() called
│   ├─ checkInterrupts() sees: irq_line = FALSE  ⚠️
│   └─ No IRQ detected! (irq_line is false)
│
├─ Line 623: if (cpu_result.mapper_irq) {  ✅ mapper_irq = true
│                cpu.irq_line = true;      ✅ Set to true
│            }
└─ (End of cycle with irq_line = true)

Cycle N+2 (CPU tick):
├─ Line 619: cpu.irq_line = apu_frame_irq OR apu_dmc_irq
│            cpu.irq_line = FALSE  ⚠️ CLEARED AGAIN!
│
├─ Line 621: stepCpuCycle()
│   ├─ checkInterrupts() sees: irq_line = FALSE  ⚠️
│   └─ No IRQ detected!
│
└─ Line 623: cpu.irq_line = true (set again, too late)

Cycle N+3 (CPU tick):
├─ Line 619: cpu.irq_line = FALSE  ⚠️ CLEARED
├─ stepCpuCycle() → checkInterrupts() sees FALSE
└─ ...

RESULT: IRQ NEVER FIRES!
```

---

## Why It Fails

### The Timing Problem

```
Line 619:  cpu.irq_line = APU_SOURCES_ONLY  ← Sets line (missing mapper!)
           ↓
Line 621:  stepCpuCycle()                   ← CPU checks irq_line HERE
           ├─ executeCycle()
           └─ checkInterrupts() reads cpu.irq_line
           ↓
Line 623:  if (mapper_irq) {                ← Mapper IRQ checked AFTER
               cpu.irq_line = true           ← Too late! CPU already ran
           }
```

**Key Issue:** CPU checks `irq_line` at Line 621, but mapper IRQ isn't added until Line 623!

### Code Flow

```zig
// src/emulation/State.zig:612-625

if (step.cpu_tick) {
    const apu_frame_irq = self.apu.frame_irq_flag;
    const apu_dmc_irq = self.apu.dmc_irq_flag;

    // ⚠️ BUG: Overwrites previous irq_line state, missing mapper
    self.cpu.irq_line = apu_frame_irq or apu_dmc_irq;

    // CPU checks irq_line inside stepCpuCycle()
    const cpu_result = self.stepCpuCycle();

    // ⚠️ BUG: Mapper IRQ added AFTER CPU already checked
    if (cpu_result.mapper_irq) {
        self.cpu.irq_line = true;  // Too late!
    }
}
```

---

## The Fix

### Option A: Poll Mapper BEFORE CPU Execution (RECOMMENDED)

```zig
// src/emulation/State.zig:612-625

if (step.cpu_tick) {
    const apu_frame_irq = self.apu.frame_irq_flag;
    const apu_dmc_irq = self.apu.dmc_irq_flag;
    const mapper_irq = self.pollMapperIrq();  // ✅ Poll BEFORE

    // ✅ Include all sources
    self.cpu.irq_line = apu_frame_irq or apu_dmc_irq or mapper_irq;

    // CPU sees correct irq_line state
    const cpu_result = self.stepCpuCycle();

    // No longer need to handle mapper_irq here
}
```

**Timeline with fix:**
```
Cycle N+1:
├─ pollMapperIrq() returns TRUE (mapper.irq_pending = true)
├─ cpu.irq_line = false OR false OR TRUE
├─ cpu.irq_line = TRUE  ✅
├─ stepCpuCycle()
│   └─ checkInterrupts() sees: irq_line = TRUE  ✅
│       └─ pending_interrupt = .irq  ✅
└─ IRQ FIRES! ✅
```

### Option B: Use Accumulation Pattern

```zig
// src/emulation/State.zig:612-625

if (step.cpu_tick) {
    const apu_frame_irq = self.apu.frame_irq_flag;
    const apu_dmc_irq = self.apu.dmc_irq_flag;

    self.cpu.irq_line = apu_frame_irq or apu_dmc_irq;

    const cpu_result = self.stepCpuCycle();

    // ✅ Accumulate instead of overwrite
    self.cpu.irq_line = self.cpu.irq_line or cpu_result.mapper_irq;
}
```

**Problem with Option B:**
- Mapper IRQ still polled AFTER CPU execution
- IRQ won't fire until NEXT cycle (1-cycle delay)
- Less consistent with NMI handling pattern

**Recommendation:** Use Option A

---

## Why Previous Fixes Didn't Work

### Your Fix #1: Clear irq_pending on $E001

**Status:** ✅ Correct but insufficient

```zig
// src/cartridge/mappers/Mapper4.zig:145
self.irq_pending = false;  // ✅ Correct behavior
```

**Why it didn't help:**
- The mapper `irq_pending` flag is set correctly
- The mapper polling works correctly
- But the IRQ **line** is never seen by the CPU due to timing bug

### Your Fix #3: A12 Filter Delay

**Status:** ✅ Correct but insufficient

```zig
// src/ppu/Logic.zig:244
if (!state.a12_state and current_a12 and state.a12_filter_delay >= 6) {
    flags.a12_rising = true;  // ✅ Correct
}
```

**Why it didn't help:**
- A12 edges are detected correctly
- Mapper counter decrements correctly
- `irq_pending` is set correctly
- But the IRQ line management bug prevents CPU from seeing it

---

## Comparison: APU vs Mapper IRQ

### APU IRQ (Works Correctly) ✅

```zig
// APU sets flags directly in APU state
self.apu.frame_irq_flag = true;

// Later, in tick():
const apu_frame_irq = self.apu.frame_irq_flag;  // Read flag
self.cpu.irq_line = apu_frame_irq or ...;       // Include in line
```

**Why it works:**
- APU flags are persistent state
- Read BEFORE CPU execution
- Included in initial line computation

### Mapper IRQ (Broken) ❌

```zig
// Mapper sets flag in mapper state
self.irq_pending = true;

// Later, in tick():
self.cpu.irq_line = apu_sources;     // ⚠️ Mapper NOT included
const cpu_result = self.stepCpuCycle();  // CPU runs
if (cpu_result.mapper_irq) {         // ⚠️ Checked AFTER
    self.cpu.irq_line = true;        // Too late!
}
```

**Why it fails:**
- Mapper IRQ polled AFTER CPU execution
- Not included in initial line computation
- Creates 1-cycle timing gap

---

## Root Cause Summary

### Three Compounding Issues

1. **Mapper IRQ polled at wrong time**
   - Polled AFTER CPU execution instead of before
   - Located in: `stepCycle()` return value

2. **IRQ line overwritten every cycle**
   - Line 619 sets line from APU sources only
   - Doesn't preserve mapper IRQ state from previous cycle

3. **Timing mismatch**
   - CPU checks `irq_line` inside `stepCpuCycle()`
   - Mapper IRQ added to line AFTER `stepCpuCycle()` returns
   - Creates 1-cycle gap where IRQ is invisible

### The Solution

Poll mapper IRQ BEFORE CPU execution and include in initial line computation.

**Change 3 lines of code:**
```diff
+ const mapper_irq = self.pollMapperIrq();
- self.cpu.irq_line = apu_frame_irq or apu_dmc_irq;
+ self.cpu.irq_line = apu_frame_irq or apu_dmc_irq or mapper_irq;

  const cpu_result = self.stepCpuCycle();
- if (cpu_result.mapper_irq) {
-     self.cpu.irq_line = true;
- }
```

---

## Impact Assessment

### What Will Work After Fix

- ✅ Super Mario Bros. 3 (split-screen status bar)
- ✅ Mega Man 3-6 (raster effects)
- ✅ Kirby's Adventure (dialog boxes)
- ✅ All MMC3 games using IRQ-based effects

### Testing Checklist

1. **SMB3:** Status bar should stay visible
2. **Kirby:** Dialog boxes should render
3. **Mega Man 3:** Screen transitions should work
4. **Existing tests:** All tests should still pass

### Regression Risk

**Low Risk:**
- Change is minimal (3 lines)
- Aligns IRQ handling pattern with NMI
- Makes all IRQ sources consistent
- No breaking changes to API

---

**Recommendation:** Apply Option A fix immediately. This is the root cause of MMC3 IRQ failures.
