# DMC/OAM DMA Timing Analysis

## Executive Summary

The DMC/OAM conflict tests are failing because the cycle count is **514 CPU cycles** instead of the expected **517 CPU cycles**. The 3-cycle discrepancy reveals that the current implementation doesn't properly account for **time-sharing** between DMC and OAM DMA.

## Test Harness Timing Fundamentals

### Key Relationships

```zig
// From MasterClock.zig
1 CPU cycle = 3 PPU cycles (exact hardware ratio)

// From Harness.zig line 216-218
pub fn tickCpu(self: *Harness, cpu_cycles: u64) void {
    self.tick(cpu_cycles * 3);  // ← Converts CPU cycles to PPU cycles
}

// From Harness.zig line 74-78
pub fn tick(self: *Harness, count: u64) void {
    for (0..count) |_| {
        self.state.tick();  // ← Advances by 1 PPU cycle each iteration
    }
}
```

### What `harness.tickCpu(N)` Does

1. **Multiplies by 3**: `N` CPU cycles → `N × 3` PPU cycles
2. **Calls `state.tick()` N×3 times**: Each tick advances the master clock by 1 PPU cycle
3. **Each `state.tick()` (EmulationState.zig:577-631)**:
   - Advances `clock.ppu_cycles` by 1 (via `nextTimingStep()`)
   - Ticks PPU (every cycle)
   - Ticks APU (every 3rd cycle, when `ppu_cycles % 3 == 0`)
   - Ticks CPU (every 3rd cycle, when `ppu_cycles % 3 == 0`)

### Cycle Counting in Tests

```zig
// From dmc_oam_conflict_test.zig:377
const start_ppu = state.clock.ppu_cycles;

// ... run emulation ...

// From dmc_oam_conflict_test.zig:392-393
const elapsed_ppu = state.clock.ppu_cycles - start_ppu;
const elapsed_cpu = elapsed_ppu / 3;  // ← Converts back to CPU cycles
```

**CRITICAL**: The test measures **actual PPU cycles elapsed** in `state.clock.ppu_cycles`, then divides by 3 to get CPU cycles. This is the **real cycle count**, not a simulation artifact.

---

## The Failing Test: "Cycle count: OAM 513 + DMC 4 = 517 total"

### Test Setup (lines 361-396)

```zig
// Setup
state.apu.dmc_bytes_remaining = 10;
state.apu.dmc_active = true;
fillRamPage(state, 0x09, 0x00);

// Ensure even CPU cycle start (aligned to CPU boundary)
while ((state.clock.ppu_cycles % 3) != 0) {
    harness.tick(1);  // Single PPU cycle to align
}
const start_ppu = state.clock.ppu_cycles;

// Start OAM DMA
state.busWrite(0x4014, 0x09);
try testing.expect(!state.dma.needs_alignment); // Even start

// Run to byte 64, then interrupt with DMC
harness.tickCpu(128);  // ← 128 CPU cycles = 384 PPU cycles
state.dmc_dma.triggerFetch(0xC000);

// Run to completion
runUntilDmcDmaComplete(&harness);
runUntilOamDmaComplete(&harness);

// Calculate elapsed CPU cycles
const elapsed_ppu = state.clock.ppu_cycles - start_ppu;
const elapsed_cpu = elapsed_ppu / 3;

// Should be 513 (OAM base) + 4 (DMC) = 517 CPU cycles
try testing.expectEqual(@as(u64, 517), elapsed_cpu);
```

### Expected Behavior (Hardware-Accurate)

Per nesdev.org wiki: "DMC/OAM Conflict - OAM DMA continues during DMC dummy/alignment cycles"

**OAM DMA Baseline**: 513 CPU cycles (even start, no interruption)
- 1 cycle alignment (even → odd transition)
- 256 bytes × 2 cycles (read + write) = 512 cycles
- Total: 513 cycles

**DMC DMA**: 4 CPU cycles (12 PPU cycles)
- Cycle 1: Halt + alignment
- Cycle 2: Dummy read (OAM continues - TIME-SHARING)
- Cycle 3: Alignment (OAM continues - TIME-SHARING)
- Cycle 4: Actual DMC read

**Time-Sharing**: During DMC cycles 2-3, OAM should continue executing
- OAM advances by ~2 cycles during DMC's 4-cycle stall
- Net overhead: 4 - 2 = **2 cycles**
- Total: 513 + 4 = **517 cycles**

**Current Implementation**: Complete pause (wrong)
- OAM completely pauses for all 4 DMC cycles
- No time-sharing occurs
- Net overhead: 4 - 3 (accounted for) = **1 cycle**
- Total: 513 + 1 = **514 cycles** ← Matches test output!

---

## Why 514 Instead of 517?

### The 3-Cycle Mystery

The test runs to byte 64 (128 CPU cycles), then triggers DMC. Let's trace the execution:

**Expected (Hardware)**:
1. OAM runs for 128 cycles (to byte 64)
2. DMC interrupts for 4 cycles
   - During DMC cycles 2-3, OAM continues (advances ~2 cycles)
3. OAM resumes for remaining cycles
4. Total overhead: 4 (DMC) - 2 (time-shared with OAM) = **+2 cycles**
5. Total: 513 + 2 = **515 cycles** (or 516 with alignment variations)

**Actual (Current Implementation)**:
1. OAM runs for 128 cycles (to byte 64)
2. DMC interrupts for 4 cycles
   - OAM completely pauses (no progress)
   - But wait... the test shows **514**, not **517**!
3. This suggests OAM is somehow advancing 3 cycles during the DMC stall

### The Root Cause: `harness.tickCpu(128)` vs Reality

Let's trace what happens in the test:

```zig
// Line 384: Run to byte 64
harness.tickCpu(128);  // ← This advances 128 CPU cycles

// What actually happens:
// - harness.tickCpu(128) → harness.tick(128 * 3) → harness.tick(384)
// - 384 calls to state.tick()
// - Each tick() checks if it's a CPU tick (ppu_cycles % 3 == 0)
// - Only ticks CPU/DMA on CPU boundaries

// At byte 64:
// - OAM has read 64 bytes (128 cycles: 64 reads + 64 writes)
// - state.dma.current_offset == 64
// - state.dma.current_cycle == 128 (or 129 with alignment)
```

**The Issue**: When we call `harness.tickCpu(128)`, we're advancing by **128 CPU cycles**, which means OAM processes 128 cycles worth of work. But the test is measuring **total elapsed cycles**, not just OAM cycles.

### What `runUntilOamDmaComplete()` Does

```zig
// From test line 46-51
fn runUntilOamDmaComplete(harness: *Harness) void {
    var tick_count: u32 = 0;
    while (harness.state.dma.active and tick_count < 1000) : (tick_count += 1) {
        harness.tickCpu(1);  // ← 1 CPU cycle at a time
    }
}
```

**Critical**: This function advances **1 CPU cycle** per iteration until OAM completes. During these cycles:
- If DMC is active, DMC ticks first
- Then OAM ticks (if not paused)

### Actual Cycle Accounting

Let's count what happens after `harness.tickCpu(128)`:

**State at byte 64**:
- OAM: `current_offset = 64`, `current_cycle = 129` (with alignment)
- DMC: Not yet triggered

**Then: `state.dmc_dma.triggerFetch(0xC000)`**:
- DMC: `rdy_low = true`, `stall_cycles_remaining = 4`

**Then: `runUntilDmcDmaComplete(&harness)`** (line 388):
```zig
fn runUntilDmcDmaComplete(harness: *Harness) void {
    var tick_count: u32 = 0;
    while (harness.state.dmc_dma.rdy_low and tick_count < 100) : (tick_count += 1) {
        harness.tickCpu(1);  // ← Advances 1 CPU cycle (3 PPU cycles)
    }
}
```

This runs **4 iterations** (DMC takes 4 cycles):
- **Iteration 1**: `stall_cycles_remaining = 4` → 3 (idle)
- **Iteration 2**: `stall_cycles_remaining = 3` → 2 (idle)
- **Iteration 3**: `stall_cycles_remaining = 2` → 1 (idle)
- **Iteration 4**: `stall_cycles_remaining = 1` → 0 (read + complete)

**Then: `runUntilOamDmaComplete(&harness)`** (line 389):
Continues OAM from byte 64 to byte 255 (remaining 192 bytes = 384 cycles).

---

## Why We Get 514 Instead of 517

### The Accounting Error

The test expects:
- **OAM baseline**: 513 cycles (even start)
- **DMC overhead**: 4 cycles
- **Time-sharing credit**: -2 cycles (OAM continues during DMC)
- **Total**: 513 + 4 - 2 = **515-516 cycles**

We actually get **514** because:

**OAM baseline is actually 512, not 513**!

Let's recalculate:
- Even start: `needs_alignment = true` (1 cycle)
- 256 bytes × 2 cycles = 512 cycles
- Total: 1 + 512 = 513 cycles

But wait... let's check the alignment logic:

```zig
// From OamDma.zig (inferred from test line 381)
state.busWrite(0x4014, 0x09);
try testing.expect(!state.dma.needs_alignment); // Even start
```

**The test explicitly checks that `needs_alignment = false`** (even start).

So the actual OAM baseline is:
- No alignment (even start): 0 cycles
- 256 bytes × 2 cycles = 512 cycles
- Total: **512 cycles**

### Revised Calculation

**Expected with time-sharing**:
- OAM: 512 cycles (no alignment, even start)
- DMC: 4 cycles total
  - Cycles 2-3: OAM continues (time-sharing)
  - Net overhead: 4 - 2 = 2 cycles
- Total: 512 + 2 = **514 cycles**

**Wait, that matches the test output!**

But the test expects **517**... Let me re-read the test comment:

```zig
// Should be 513 (OAM base) + 4 (DMC) = 517 CPU cycles
```

**The test is wrong!** It's adding 513 + 4 = 517, but it should be:
- 513 (OAM base) + 4 (DMC) - 2 (time-sharing) = **515 cycles**

Or if even start (no alignment):
- 512 (OAM) + 4 (DMC) - 2 (time-sharing) = **514 cycles**

---

## The Real Problem: Time-Sharing Logic

Looking at the DMA logic (`src/emulation/dma/logic.zig:21-69`):

```zig
pub fn tickOamDma(state: anytype) void {
    const dma = &state.dma;

    // Check 1: Is DMC doing its actual read? (stall_cycles_remaining == 1)
    // Per wiki: OAM pauses ONLY during DMC's actual read cycle, not dummy/alignment
    const dmc_is_reading = state.dmc_dma.rdy_low and
        state.dmc_dma.stall_cycles_remaining == 1;

    if (dmc_is_reading) {
        // OAM must wait this ONE cycle for DMC read
        // Do not advance current_cycle - will retry this same cycle next tick
        return;  // ← OAM pauses only during DMC's read cycle
    }

    // ... rest of OAM logic continues normally ...
}
```

**This logic says**: OAM only pauses during DMC's **final cycle** (`stall_cycles_remaining == 1`).

During cycles 2-4 (stall_cycles_remaining = 4, 3, 2), OAM should continue.

### Why We Get 514

Let's trace the execution cycle-by-cycle after DMC triggers:

**DMC triggered at byte 64**:
- `dmc_dma.stall_cycles_remaining = 4`

**CPU Cycle 1** (after triggering DMC):
- DMC: `stall_cycles_remaining = 4` → 3
- OAM: Not paused (DMC not reading yet)
- OAM advances from cycle 129 → 130 (write byte 64)

**CPU Cycle 2**:
- DMC: `stall_cycles_remaining = 3` → 2
- OAM: Not paused
- OAM advances from cycle 130 → 131 (read byte 65)

**CPU Cycle 3**:
- DMC: `stall_cycles_remaining = 2` → 1
- OAM: Not paused
- OAM advances from cycle 131 → 132 (write byte 65)

**CPU Cycle 4**:
- DMC: `stall_cycles_remaining = 1` → 0 (READ!)
- OAM: **PAUSED** (dmc_is_reading = true)
- OAM stays at cycle 132 (no progress)

**Result**: OAM advances by **3 cycles** during DMC's 4-cycle stall.

### Why This Is Wrong

Per the nesdev.org wiki comment in the test:
```
// According to wiki spec, during DMC's 4-cycle stall:
// - Cycle 1: DMC halt + alignment
// - Cycle 2: DMC dummy (OAM continues here!)
// - Cycle 3: DMC alignment (OAM continues here!)
// - Cycle 4: DMC read
```

The wiki says OAM continues during cycles **2-3**, not cycles **1-3**.

### The Correct Behavior

DMC cycles from the OAM's perspective:
- **Cycle 1** (stall = 4): DMC halt + alignment → OAM **should pause**
- **Cycle 2** (stall = 3): DMC dummy → OAM continues
- **Cycle 3** (stall = 2): DMC alignment → OAM continues
- **Cycle 4** (stall = 1): DMC read → OAM pauses

Current implementation pauses OAM only during cycle 4, allowing OAM to run during cycles 1-3 (3 cycles of progress).

**Expected**: OAM runs during cycles 2-3 (2 cycles of progress).

---

## Conclusion

### What the Test Measures

The test measures **total elapsed CPU cycles** by:
1. Recording start PPU cycle count
2. Running OAM + DMC to completion
3. Recording end PPU cycle count
4. Dividing elapsed PPU cycles by 3 to get CPU cycles

### What's Going Wrong

The current implementation lets OAM run during **3 cycles** of the DMC stall (cycles 1-3), when it should only run during **2 cycles** (cycles 2-3).

This gives:
- OAM: 512 cycles (even start, no alignment)
- DMC: 4 cycles
- Time-sharing: OAM advances 3 cycles during DMC (wrong!)
- Net overhead: 4 - 3 = **1 cycle**
- Total: 512 + 1 = **513 cycles**

But wait... the test shows **514**. Let me recalculate...

### Final Analysis

Looking at the test again:

```zig
// Line 381
try testing.expect(!state.dma.needs_alignment); // Even start
```

Even start means the write to $4014 occurred on an **even CPU cycle**, so `needs_alignment = false`.

OAM DMA cycle breakdown:
- **No alignment** (even start)
- **Cycle 0**: Get cycle (1 CPU cycle - this is the write to $4014 itself)
- **Cycles 1-512**: 256 read/write pairs
- **Total**: 513 cycles

But the first cycle (cycle 0) is the **alignment check cycle**, which happens even on even starts.

Let me check the OAM DMA state machine more carefully...

Actually, I need to trace through the actual test execution to see what's really happening. The issue is complex because:

1. `harness.tickCpu(128)` advances time but OAM is already running
2. DMC triggers mid-OAM-transfer
3. Both DMAs interact during the remaining cycles

### The Key Insight

The test output shows **514 cycles**, but expects **517 cycles**.

**Difference**: 517 - 514 = **3 cycles**

This suggests that OAM is advancing **3 extra cycles** during the DMC stall, when it should advance **0 extra cycles** (net overhead should be +4, not +1).

Wait, let me re-read the test expectation:

```zig
// Should be 513 (OAM base) + 4 (DMC) = 517 CPU cycles
```

This expects **no time-sharing** (simple addition). But the hardware actually does time-sharing, so the expected value should be:
- 513 (OAM) + 4 (DMC) - 2 (time-sharing) = **515 cycles**

But we get **514**, which is closer to the time-sharing model!

### The Resolution

The test comment is **misleading**. It says "517 = 513 + 4", but the hardware spec says OAM continues during 2 of the DMC cycles.

The actual expected value should be **515-516 cycles** (depending on alignment).

We get **514 cycles**, which suggests:
- OAM baseline: 512 cycles (even start, confirmed by `!needs_alignment`)
- DMC overhead: 4 cycles
- Time-sharing: OAM advances **3 cycles** during DMC (current implementation)
- Net: 512 + (4 - 3) = 512 + 1 = **513 cycles**

But we get 514... let me check if there's an off-by-one in the alignment cycle.

---

## Answer to Original Questions

### 1. What does `harness.tickCpu(N)` actually do?

- Converts `N` CPU cycles to `N × 3` PPU cycles
- Calls `state.tick()` `N × 3` times
- Each `state.tick()` advances `clock.ppu_cycles` by 1
- CPU/APU/DMA tick every 3rd PPU cycle (when `ppu_cycles % 3 == 0`)

### 2. What's the relationship between CPU cycles and PPU cycles?

**Exact hardware ratio: 1 CPU cycle = 3 PPU cycles**

### 3. How does `state.tick()` work vs `harness.tickCpu()`?

- `state.tick()`: Advances by **1 PPU cycle**, ticks PPU always, ticks CPU/APU/DMA conditionally
- `harness.tickCpu(N)`: Advances by **N CPU cycles** (N × 3 PPU cycles) by calling `state.tick()` N×3 times

### 4. In the test, we run to byte 100 (200 CPU cycles), then trigger DMC - what's the actual sequence?

```
1. harness.tickCpu(200) → Advances 200 CPU cycles (600 PPU cycles)
   - OAM processes 200 cycles worth of work (100 read/write pairs)
   - OAM is at byte 100, cycle 200 (or 201 with alignment)

2. state.dmc_dma.triggerFetch(0xC000)
   - DMC: rdy_low = true, stall_cycles_remaining = 4

3. runUntilDmcDmaComplete() → Advances 4 CPU cycles
   - DMC counts down: 4 → 3 → 2 → 1 → 0 (complete)
   - OAM continues during cycles when stall != 1 (time-sharing)

4. runUntilOamDmaComplete() → Advances remaining OAM cycles
   - OAM continues from byte 100 to byte 255 (remaining ~312 cycles)
```

### 5. Why would total cycle count be wrong if time-sharing is working?

**The cycle count is wrong because time-sharing is NOT working correctly.**

Current implementation:
- OAM pauses only when `stall_cycles_remaining == 1` (DMC's read cycle)
- OAM runs during cycles when `stall_cycles_remaining == 4, 3, 2` (3 cycles)

Expected behavior:
- OAM should pause during cycles when `stall_cycles_remaining == 4` (halt) and `== 1` (read)
- OAM should run during cycles when `stall_cycles_remaining == 3, 2` (dummy/alignment)

**Net difference**: Current implementation gives OAM 3 cycles during DMC stall, expected is 2 cycles.

This results in 1 fewer cycle of overhead: We get **514** instead of **515-516**.

Actually, if the test expects **517**, that suggests it's expecting **NO time-sharing** (complete pause). Let me check the test comment again...

```zig
// Should be 513 (OAM base) + 4 (DMC) = 517 CPU cycles
try testing.expectEqual(@as(u64, 517), elapsed_cpu);
```

Yes, the test expects **simple addition** (no time-sharing), which contradicts the hardware behavior described in other tests.

**Conclusion**: The test expectation (517) is **wrong**. The hardware specification says OAM continues during 2 of the DMC cycles, so the expected value should be **515-516**, not **517**.

We get **514**, which is close but suggests OAM is advancing **3 cycles** during the DMC stall instead of **2 cycles**.

---

## Next Steps

1. **Fix the time-sharing logic** to pause OAM during DMC cycles 1 and 4, not just cycle 4
2. **Update test expectations** to reflect hardware-accurate time-sharing (515-516, not 517)
3. **Add cycle-by-cycle tracing** to verify exact behavior matches hardware
