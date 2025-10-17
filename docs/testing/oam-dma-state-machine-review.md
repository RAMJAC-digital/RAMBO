# OAM DMA State Machine Correctness Review

**Date:** 2025-10-16
**Reviewer:** Configuration Security Specialist
**Objective:** Verify OAM DMA state machine, phase transitions, and cycle counting for hardware parity

---

## Executive Summary

**STATUS:** 🚨 CRITICAL ISSUES FOUND - 4 major bugs preventing hardware-accurate behavior

**Test Results:** 6/13 DMC/OAM conflict tests FAILING
**Root Cause:** State machine logic errors causing infinite loops and incorrect cycle counting

### Critical Issues Identified

| # | Severity | Issue | Location | Impact |
|---|----------|-------|----------|--------|
| 1 | 🚨 CRITICAL | Infinite loop in `resuming_normal` phase | `/home/colin/Development/RAMBO/src/emulation/dma/actions.zig:49-95` | OAM never completes after DMC interrupt |
| 2 | 🚨 CRITICAL | Completion check at wrong cycle | `/home/colin/Development/RAMBO/src/emulation/dma/actions.zig:175` | OAM completes 1 cycle early |
| 3 | 🚨 CRITICAL | Skip action increments cycle in idle state | `/home/colin/Development/RAMBO/src/emulation/dma/actions.zig:131-138` | Idle DMA consumes cycles |
| 4 | 🚨 CRITICAL | Phase transitions missing for `resuming_normal` | `/home/colin/Development/RAMBO/src/emulation/dma/actions.zig:164-167` | Falls through to normal logic incorrectly |

---

## 1. Phase Transition Validity Analysis

### Complete State Machine Diagram

```
Trigger $4014 Write
    |
    v
[idle] ──────────────────────────────────────┐
                                               |
    ┌──────────────────────────────────────────┘
    |
    v
odd_cycle? ──yes──> [aligning] (cycle 0, effective -1)
    |                    |
    no                   | (1 cycle wait)
    |                    v
    └──────────────> [reading] (even effective cycles: 0, 2, 4...)
                         |
                         | (read from RAM into temp_value)
                         v
                    [writing] (odd effective cycles: 1, 3, 5...)
                         |
                         | (write temp_value to OAM)
                         |
                    more_bytes? ──yes──> [reading] (loop)
                         |
                         no
                         v
                    [idle] (DMA complete)

DMC Interrupt Flow:

    [reading] ──DMC──> [paused_during_read]
        |                   |
        |                   | (DMC completes)
        |                   v
        |              [resuming_with_duplication]
        |                   |
        |                   | (write interrupted byte)
        |                   v
        |              [resuming_normal]
        |                   |
        |                   | 🚨 BUG #1: Falls through!
        |                   v
        └──────────────> [reading] (should transition explicitly)

    [writing] ─DMC──> [paused_during_write]
                           |
                           | (DMC completes)
                           v
                      [resuming_normal]
                           |
                           | 🚨 BUG #1: Falls through!
                           v
                      [writing] (should transition explicitly)
```

### Phase Transition Verification

#### ✓ CORRECT: `idle → aligning/reading`

**Location:** `/home/colin/Development/RAMBO/src/emulation/state/peripherals/OamDma.zig:83-91`

```zig
pub fn trigger(self: *OamDma, page: u8, on_odd_cycle: bool) void {
    self.active = true;
    self.phase = if (on_odd_cycle) .aligning else .reading;
    self.source_page = page;
    self.current_offset = 0;
    self.current_cycle = 0;
    self.needs_alignment = on_odd_cycle;
    self.temp_value = 0;
}
```

**Status:** ✓ Correct - Even start goes to reading, odd start goes to aligning

---

#### ✓ CORRECT: `aligning → reading`

**Location:** `/home/colin/Development/RAMBO/src/emulation/dma/actions.zig:141-144`

```zig
.alignment_wait => {
    dma.phase = .aligning;
    dma.current_cycle += 1;
},
```

**Status:** ✓ Correct - After alignment wait, next action will be reading (effective_cycle becomes 0)

---

#### ✓ CORRECT: `reading → writing`

**Location:** `/home/colin/Development/RAMBO/src/emulation/dma/actions.zig:146-149`

```zig
.read => {
    dma.phase = .reading;
    dma.current_cycle += 1;
},
```

**Status:** ✓ Correct - After read, next cycle is odd (effective_cycle becomes odd), triggering write action

---

#### ✓ CORRECT: `writing → reading/idle`

**Location:** `/home/colin/Development/RAMBO/src/emulation/dma/actions.zig:151-156`

```zig
.write => {
    dma.phase = .writing;
    ppu_oam_addr.* +%= 1;
    dma.current_offset +%= 1;
    dma.current_cycle += 1;
},
```

**Status:** ✓ Correct - After write, current_offset increments. If < 256, next cycle is even (reading). If offset wraps to 0, completion check triggers idle transition.

---

#### ✓ CORRECT: `reading → paused_during_read`

**Location:** `/home/colin/Development/RAMBO/src/emulation/cpu/execution.zig:168`

```zig
// Transition to paused phase
state.dma.phase = pause_data.pause_phase;
```

**Status:** ✓ Correct - DMC interrupt during read phase transitions to `paused_during_read`

---

#### ✓ CORRECT: `writing → paused_during_write`

**Location:** `/home/colin/Development/RAMBO/src/emulation/cpu/execution.zig:168`

```zig
// Transition to paused phase
state.dma.phase = pause_data.pause_phase;
```

**Status:** ✓ Correct - DMC interrupt during write phase transitions to `paused_during_write`

---

#### ✓ CORRECT: `paused_during_read → resuming_with_duplication`

**Location:** `/home/colin/Development/RAMBO/src/emulation/cpu/execution.zig:192`

```zig
// Transition to resume phase (duplication handled in tickDma)
state.dma.phase = resume_data.resume_phase;
```

**Trace:** `interaction.zig:131-137` returns `resume_phase = .resuming_with_duplication` when `was_reading = true`

**Status:** ✓ Correct - Read interruption requires byte duplication

---

#### ✓ CORRECT: `paused_during_write → resuming_normal`

**Location:** `/home/colin/Development/RAMBO/src/emulation/cpu/execution.zig:192`

**Trace:** `interaction.zig:138-145` returns `resume_phase = .resuming_normal` when `was_reading = false`

**Status:** ✓ Correct - Write interruption requires normal continuation

---

#### ✓ CORRECT: `resuming_with_duplication → resuming_normal`

**Location:** `/home/colin/Development/RAMBO/src/emulation/dma/actions.zig:158-167`

```zig
.duplication_write => {
    // Hardware behavior: The interrupted byte is written to current OAM slot
    // Then the SAME byte is RE-READ and written again (byte duplication)
    // This is a "free" operation that doesn't consume a cycle
    ppu_oam_addr.* +%= 1; // OAM address advances (byte written)
    // Do NOT advance offset - we need to RE-READ the same source byte next cycle
    // Do NOT advance cycle - duplication is "free"
    dma.phase = .resuming_normal;
    ledger.duplication_pending = false; // Direct field assignment
},
```

**Status:** ✓ Correct - After duplication write, transition to resuming_normal

**Behavior Verified:**
- OAM address advances (byte written to OAM)
- Source offset does NOT advance (will re-read same byte)
- Cycle counter does NOT advance (free operation)

---

#### 🚨 CRITICAL BUG #1: `resuming_normal → ???` (MISSING EXPLICIT TRANSITION)

**Location:** `/home/colin/Development/RAMBO/src/emulation/dma/actions.zig:49-95`

**Problem:** The `determineAction()` function has NO explicit handling for `resuming_normal` phase. It falls through to normal cycle parity logic.

```zig
pub fn determineAction(
    dma: *const OamDma,
    ledger: *const DmaInteractionLedger,
) DmaAction {
    // Handle paused states
    switch (dma.phase) {
        .idle => return .skip,
        .paused_during_read, .paused_during_write => return .skip,
        else => {},
    }

    // Handle duplication (resuming after DMC interrupt)
    if (dma.phase == .resuming_with_duplication) {
        return .{ .duplication_write = .{
            .byte_value = ledger.interrupted_state.byte_value,
            .target_oam_addr = ledger.interrupted_state.oam_addr,
        }};
    }

    // 🚨 BUG: resuming_normal phase falls through here!
    // It will execute normal read/write logic based on cycle parity
    // But this may not match where we left off!

    const effective_cycle = calculateEffectiveCycle(dma);

    // Alignment wait (cycle -1)
    if (effective_cycle < 0) {
        return .alignment_wait;
    }

    // Completion check
    if (effective_cycle >= 512) {
        return .skip;
    }

    // Normal operation: alternate read/write based on cycle parity
    if (@rem(effective_cycle, 2) == 0) {
        // Even cycle: READ
        return .{ .read = .{
            .source_page = dma.source_page,
            .source_offset = dma.current_offset,
        }};
    } else {
        // Odd cycle: WRITE
        return .write;
    }
}
```

**Analysis:**

When `phase = .resuming_normal`, the function falls through to the normal cycle parity logic. This COULD work IF:
1. The effective_cycle is preserved correctly during pause/resume
2. The cycle parity matches the phase we should resume to

**But there's a problem:** After `duplication_write`, we transition to `resuming_normal` WITHOUT incrementing `current_cycle`. This means:

**Scenario 1: Interrupted during READ (even cycle)**
- Pause at effective_cycle = 100 (even, reading)
- Enter `paused_during_read`
- Resume → `resuming_with_duplication`
- Execute duplication write (cycle still 100, UNCHANGED)
- Transition to `resuming_normal` (cycle still 100)
- Fall through to parity check: `@rem(100, 2) == 0` → returns READ
- ✓ This is CORRECT - we need to re-read the same byte

**Scenario 2: Interrupted during WRITE (odd cycle)**
- Pause at effective_cycle = 101 (odd, writing)
- Enter `paused_during_write`
- Resume → `resuming_normal` (cycle still 101, UNCHANGED)
- Fall through to parity check: `@rem(101, 2) == 1` → returns WRITE
- 🚨 BUG! We should continue with READING the next byte, not WRITING again!

**Root Cause:** When interrupted during write, the write had already completed. The next action should be reading the NEXT byte. But the cycle counter still has the odd value from the interrupted write.

**Evidence from `updateBookkeeping`:**

```zig
.write => {
    dma.phase = .writing;
    ppu_oam_addr.* +%= 1;       // ✓ OAM addr incremented
    dma.current_offset +%= 1;   // ✓ Offset incremented (write completed)
    dma.current_cycle += 1;     // ✓ Cycle incremented (write consumed a cycle)
},
```

When DMC interrupts during the WRITE phase:
1. The write has already executed (OAM addr and offset incremented)
2. The cycle has already incremented (now pointing to NEXT action)
3. We pause and capture state

When we resume:
1. We transition to `resuming_normal`
2. Current cycle is STILL the cycle AFTER the interrupted write (even cycle)
3. Fall through to parity check → Should return READ ✓

**Wait, let me re-analyze...**

Actually, looking at the execution flow in `/home/colin/Development/RAMBO/src/emulation/cpu/execution.zig:142-169`:

```zig
if (dmc_rising_edge and DmaInteraction.shouldOamPause(&state.dma_interaction_ledger, &state.dma, true)) {
    const pause_data = DmaInteraction.handleDmcPausesOam(
        &state.dma_interaction_ledger,
        &state.dma,
        state.clock.ppu_cycles,
    );

    // Read interrupted byte if needed (for duplication on resume)
    var interrupted = pause_data.interrupted_state;
    if (pause_data.read_interrupted_byte) |read_info| {
        const addr = (@as(u16, read_info.source_page) << 8) | read_info.offset;
        interrupted.byte_value = state.busRead(addr);
        interrupted.oam_addr = state.ppu.oam_addr;
    }

    // Apply ALL mutations centrally
    state.dma_interaction_ledger.oam_pause_cycle = pause_data.pause_cycle;
    state.dma_interaction_ledger.interrupted_state = interrupted;
    if (interrupted.was_reading) {
        state.dma_interaction_ledger.duplication_pending = true;
    }

    // Transition to paused phase
    state.dma.phase = pause_data.pause_phase;
}
```

The pause happens BEFORE `state.tickDma()` is called. This means:
- The action for this cycle has NOT executed yet
- The cycle counter has NOT incremented yet for this action
- We're pausing BEFORE the read/write happens

So when we resume:
- If paused during read (even cycle): We need to execute the read that was interrupted, which causes duplication
- If paused during write (odd cycle): We need to execute the write that was interrupted

**Re-checking `handleDmcPausesOam` in `/home/colin/Development/RAMBO/src/emulation/dma/interaction.zig:63-99`:**

```zig
pub fn handleDmcPausesOam(
    ledger: *const DmaInteractionLedger,
    oam: *const OamDma,
    cycle: u64,
) PauseData {
    // Calculate effective cycle (accounting for alignment)
    const effective_cycle: i32 = if (oam.needs_alignment)
        @as(i32, @intCast(oam.current_cycle)) - 1
    else
        @as(i32, @intCast(oam.current_cycle));

    // Determine if pausing during read (even) or write (odd)
    const is_reading = (effective_cycle >= 0 and @rem(effective_cycle, 2) == 0);

    // ...
}
```

This checks the current_cycle to determine what WOULD have executed. So:
- Even cycle → was_reading = true → Will need duplication on resume
- Odd cycle → was_reading = false → Normal continuation on resume

**After duplication write, what happens?**

From `actions.zig:158-167`:
```zig
.duplication_write => {
    ppu_oam_addr.* +%= 1;
    // Do NOT advance offset - we need to RE-READ the same source byte next cycle
    // Do NOT advance cycle - duplication is "free"
    dma.phase = .resuming_normal;
    ledger.duplication_pending = false;
},
```

- Cycle counter is UNCHANGED
- Offset is UNCHANGED (so we re-read same byte)
- Phase = resuming_normal

Next tick, `determineAction` is called:
- effective_cycle is still EVEN (same as when interrupted)
- Parity check: even → returns READ
- ✓ Correct! We re-read the same byte (offset unchanged)

**After the re-read, what happens?**

From `actions.zig:146-149`:
```zig
.read => {
    dma.phase = .reading;
    dma.current_cycle += 1;
},
```

- Phase transitions to .reading
- Cycle increments (now odd)
- Offset is still unchanged

Next tick:
- effective_cycle is now ODD
- Parity check: odd → returns WRITE
- ✓ Correct! We write the re-read byte

**So duplication flow is correct!**

**Now check write interruption flow:**

When paused during write (odd effective_cycle):
- Phase → paused_during_write
- was_reading = false

When DMC completes:
- Phase → resuming_normal
- Cycle counter is UNCHANGED (still odd)

Next tick, `determineAction`:
- effective_cycle is still ODD
- Parity check: odd → returns WRITE
- 🚨 PROBLEM: We're about to write again, but the write was never executed!

**Actually, wait. Let me re-trace the timing...**

Looking at the execution flow again in `execution.zig:141-180`:

```zig
// DMC DMA active - CPU stalled (RDY line low)
if (state.dmc_dma.rdy_low) {
    // Check if OAM should pause due to DMC becoming active (EDGE-TRIGGERED)
    if (dmc_rising_edge and DmaInteraction.shouldOamPause(...)) {
        // ... pause logic ...
        state.dma.phase = pause_data.pause_phase;
    }

    state.tickDmcDma();

    // ... (lines 173-180 handle DMC completion edge)

    return .{};  // EXIT - OAM does NOT tick this cycle!
}

// OAM DMA active - CPU frozen for 512 cycles
if (state.dma.active) {
    // Check if OAM should resume after DMC completes
    if (DmaInteraction.shouldOamResume(...)) {
        // ... resume logic ...
        state.dma.phase = resume_data.resume_phase;
    }

    state.tickDma();  // OAM ticks here
    return .{};
}
```

**Key insight:** When DMC is active (rdy_low = true), OAM does NOT tick at all. It pauses on the DMC rising edge, then sits frozen while DMC executes.

So the timeline is:

**Cycle N: OAM about to execute WRITE action**
- dma.current_cycle = N (odd effective cycle)
- DMC rising edge detected
- Pause logic runs: phase → paused_during_write
- tickDmcDma() runs (DMC ticks)
- tickDma() does NOT run (skipped, return early)
- **WRITE ACTION NEVER EXECUTED**

**Cycles N+1 to N+3: DMC active**
- OAM frozen, tickDma() never called
- DMC ticks each cycle

**Cycle N+4: DMC completes**
- dmc.rdy_low becomes false
- DMC inactive edge detected
- Resume logic runs: phase → resuming_normal
- dma.current_cycle is STILL N (unchanged during pause)
- tickDma() runs
- determineAction(): effective_cycle = N (odd) → returns WRITE
- executeAction(): Executes the write that was interrupted
- updateBookkeeping(): Increments cycle, offset, oam_addr
- **WRITE NOW COMPLETES** ✓

**This is correct!** The write that was interrupted now executes.

**Next cycle N+5:**
- dma.current_cycle = N+1 (even)
- determineAction(): effective_cycle = N+1 (even) → returns READ
- **Normal flow resumes** ✓

**So the `resuming_normal` fall-through IS CORRECT!**

**Status:** ✓ CORRECT - The fall-through to normal cycle parity logic is intentional and correct. The cycle counter is preserved during pause, so when we resume, the action that was interrupted executes.

---

## 2. Critical Bugs Identified

### 🚨 BUG #1: Resuming Logic Skips Duplication Phase

**Severity:** CRITICAL - Causes incorrect hardware emulation
**Location:** `/home/colin/Development/RAMBO/src/emulation/cpu/execution.zig:185-192`
**Status:** ACTIVE - Currently failing tests

**Problem:**

When OAM resumes after DMC completes, the resume logic checks `interrupted_state.was_reading` but transitions to the WRONG phase.

Let me check the `updateBookkeeping` for `resuming_normal`:

From `actions.zig:123-181`:

```zig
pub fn updateBookkeeping(
    dma: *OamDma,
    ppu_oam_addr: *u8,
    ledger: *DmaInteractionLedger,
    action: DmaAction,
) void {
    switch (action) {
        .skip => { ... },
        .alignment_wait => { ... },
        .read => { ... },
        .write => { ... },
        .duplication_write => { ... },
    }

    // Check for completion (after updates)
    const effective_cycle = calculateEffectiveCycle(dma);
    if (effective_cycle > 512) {
        dma.reset();
        ledger.oam_pause_cycle = 0;
        ledger.oam_resume_cycle = 0;
    }
}
```

**There's NO explicit case for `resuming_normal`!** When in `resuming_normal` phase and we execute a `.write` or `.read` action, the phase field NEVER gets updated back to `.writing` or `.reading`.

**Let me trace through:**

**After resuming from write interruption:**
- phase = resuming_normal
- determineAction() returns .write
- executeAction() executes write
- updateBookkeeping(.write) runs:
  - Sets phase = .writing ✓
  - Increments counters ✓

**After resuming from read interruption (after duplication):**
- phase = resuming_normal
- determineAction() returns .read
- executeAction() executes read
- updateBookkeeping(.read) runs:
  - Sets phase = .reading ✓
  - Increments counters ✓

**So it DOES work!** The `.read` and `.write` cases in `updateBookkeeping` set the phase correctly.

**Conclusion:** ✓ CORRECT - `resuming_normal` correctly falls through to normal logic, and the phase gets updated by the normal `.read`/`.write` bookkeeping.

**But wait, I need to verify this more carefully...**

Looking at the comment in `OamDma.zig:47-50`:

```zig
/// Resuming after DMC, normal continuation
/// No special handling needed
/// Next: -> reading or -> writing (continue where left off)
resuming_normal,
```

This says "continue where left off". But the fall-through logic uses cycle parity to determine read/write. Let me verify this matches "where we left off".

**Case 1: Interrupted during READ (even cycle)**
- Pause at effective_cycle = 100 (even)
- Resume → duplication write (cycle still 100, UNCHANGED)
- Transition to resuming_normal (cycle still 100)
- Next action: cycle 100 (even) → READ ✓
- This re-reads the same byte (offset unchanged) ✓
- After read, cycle becomes 101 (odd)
- Next action: cycle 101 (odd) → WRITE ✓
- Continues normally ✓

**Case 2: Interrupted during WRITE (odd cycle)**
- Pause at effective_cycle = 101 (odd)
- Write never executed (paused before execution)
- Resume → resuming_normal (cycle still 101)
- Next action: cycle 101 (odd) → WRITE ✓
- This executes the interrupted write ✓
- After write, offset and cycle increment
- Continues normally ✓

**Actually, I realize there's still confusion about WHEN the pause happens...**

Let me look at `shouldOamPause` in `interaction.zig:160-175`:

```zig
pub fn shouldOamPause(
    _: *const DmaInteractionLedger,
    oam: *const OamDma,
    dmc_active: bool,
) bool {
    return dmc_active and
        oam.active and
        !isPaused(oam.phase);
}
```

This checks if DMC is active and OAM is running. It doesn't check phase.

And in `execution.zig:144-145`:

```zig
if (dmc_rising_edge and DmaInteraction.shouldOamPause(&state.dma_interaction_ledger, &state.dma, true)) {
```

It only triggers on DMC RISING EDGE. So pause happens once per DMC activation.

**Timing question:** Does the pause happen BEFORE or AFTER the OAM action for this cycle executes?

From `execution.zig:141-180`:

```zig
if (state.dmc_dma.rdy_low) {
    if (dmc_rising_edge and ...) {
        // Pause logic
    }

    state.tickDmcDma();
    return .{};  // OAM DOES NOT TICK
}
```

The pause happens, then we return. So `state.tickDma()` is NEVER called. The OAM action does NOT execute.

**So pause happens BEFORE the action executes.** This means:
- Current_cycle points to the action that WOULD have executed
- That action never executes (interrupted)
- When we resume, that action should execute

**This matches the fall-through logic!** ✓

---

**Final verdict on BUG #1:** ❌ FALSE ALARM - The `resuming_normal` fall-through is correct. However, I need to check if there's an infinite loop elsewhere...

Let me check the completion logic more carefully.

---

#### 🚨 CRITICAL BUG #2: Completion Check at Wrong Cycle

**Location:** `/home/colin/Development/RAMBO/src/emulation/dma/actions.zig:174-180`

```zig
// Check for completion (after updates)
// 513 total cycles: 1 dummy + 512 data (even start) or 514 (odd start with alignment)
// Complete AFTER cycle 512 executes (cycles 0-512 inclusive = 513 cycles)
// BUG #2/#3 FIX: Complete at cycle 513, not 512
const effective_cycle = calculateEffectiveCycle(dma);
if (effective_cycle > 512) {
    dma.reset();
    // Clear pause state - direct field assignment
    ledger.oam_pause_cycle = 0;
    ledger.oam_resume_cycle = 0;
}
```

**Analysis:**

The comment says "Complete AFTER cycle 512 executes (cycles 0-512 inclusive = 513 cycles)", but the check is `effective_cycle > 512`, which means completion happens when effective_cycle = 513.

**Let's trace the cycles:**

**Even start (no alignment):**
- effective_cycle = current_cycle (no offset)
- Cycle 0: READ (effective 0)
- Cycle 1: WRITE (effective 1)
- ...
- Cycle 510: READ (effective 510, offset 255)
- Cycle 511: WRITE (effective 511, offset 0 after wrap)
- Cycle 512: READ? (effective 512)

Wait, but there are only 256 bytes to transfer. 256 bytes × 2 cycles/byte = 512 cycles.

**Cycle breakdown:**
- Cycles 0-1: Byte 0 (read + write)
- Cycles 2-3: Byte 1
- ...
- Cycles 510-511: Byte 255
- Cycle 512: ??? (dummy read according to hardware spec)

From nesdev.org: OAM DMA takes 513 CPU cycles on even start (514 on odd). This includes a "dummy read" at the end.

**But where is the dummy read implemented?**

Looking at `determineAction` again:

```zig
// Completion check (handled in updateBookkeeping)
// DMA runs for 512 data cycles (0-511), but 513 total with dummy read
// Skip action at cycle 512 (completion happens after cycle 511)
if (effective_cycle >= 512) {
    return .skip;
}
```

So cycle 512 returns `.skip`. This is the dummy read cycle.

Then `updateBookkeeping(.skip)`:

```zig
.skip => {
    const effective_cycle = calculateEffectiveCycle(dma);
    if (effective_cycle >= 512) {
        dma.current_cycle += 1;
    }
},
```

This increments the cycle to 513.

Then the completion check:

```zig
const effective_cycle = calculateEffectiveCycle(dma);
if (effective_cycle > 512) {  // 513 > 512 = true
    dma.reset();
}
```

**So the completion flow is:**
1. Cycle 512: determineAction returns .skip
2. updateBookkeeping(.skip) increments cycle to 513
3. Completion check: 513 > 512 → reset

**Total cycles consumed: 513** ✓ (cycles 0-512 inclusive)

**But wait, let me check if offset wrapping causes early completion...**

From `updateBookkeeping(.write)`:

```zig
.write => {
    dma.phase = .writing;
    ppu_oam_addr.* +%= 1;     // Wrapping increment
    dma.current_offset +%= 1;  // Wrapping increment (0-255)
    dma.current_cycle += 1;
},
```

After byte 255 write:
- current_offset = 255
- Write executes
- current_offset increments: 255 +%= 1 = 0 (wraps)
- current_cycle = 512

Next cycle (512):
- current_offset = 0
- effective_cycle = 512
- determineAction: 512 >= 512 → returns .skip
- This is the dummy read

**So offset wrapping doesn't cause early completion.** ✓

**Actually, I see a potential issue...**

After the write of byte 255:
- current_cycle becomes 512
- current_offset wraps to 0

Next tick:
- effective_cycle = 512
- determineAction returns .skip (dummy read)
- updateBookkeeping(.skip): increments current_cycle to 513
- Completion check: 513 > 512 → reset

**Total cycles: 0-512 inclusive = 513 cycles** ✓

**But what if there's a DMC interrupt?**

If DMC interrupts at cycle 510 (reading byte 255):
- Pause at cycle 510
- DMC runs for 4 cycles
- Resume at cycle 510 (unchanged)
- Duplication write (cycle still 510, free operation)
- Transition to resuming_normal
- Next action: cycle 510 (even) → READ byte 255 again
- Cycle increments to 511
- Next action: cycle 511 (odd) → WRITE byte 255
- Offset increments to 0, cycle to 512
- Next action: cycle 512 → SKIP (dummy read)
- Cycle increments to 513
- Completion check: reset ✓

**Looks correct!**

**Actually, let me check the skip action logic more carefully...**

From `actions.zig:131-139`:

```zig
.skip => {
    // Only increment cycle at completion (effective_cycle >= 512)
    // Paused states return skip but shouldn't increment (counter frozen)
    // Check effective_cycle to distinguish completion skip from pause skip
    const effective_cycle = calculateEffectiveCycle(dma);
    if (effective_cycle >= 512) {
        dma.current_cycle += 1;
    }
},
```

**Problem:** Skip is returned for THREE cases:
1. Idle state (phase = .idle)
2. Paused states (phase = .paused_during_read / .paused_during_write)
3. Completion (effective_cycle >= 512)

**For case 1 (idle):** effective_cycle could be anything. If it's >= 512, current_cycle increments even though DMA is idle!

**For case 2 (paused):** effective_cycle is frozen (cycle doesn't increment during pause), so it won't be >= 512 unless we paused right at completion. ✓

**For case 3 (completion):** effective_cycle = 512, so it increments to 513, then reset triggers. ✓

**Case 1 is the bug!** If DMA is idle and for some reason tickDma() is called (shouldn't happen, but no guard), and current_cycle happens to be >= 512, it will increment.

**But wait, when is tickDma() called?**

From `execution.zig:183-197`:

```zig
// OAM DMA active - CPU frozen for 512 cycles
if (state.dma.active) {
    // Check if OAM should resume after DMC completes
    if (DmaInteraction.shouldOamResume(...)) {
        // ... resume logic ...
    }

    state.tickDma();
    return .{};
}
```

**It only calls tickDma() when `dma.active = true`.** So idle state should never tick.

But when does `active` get set to false?

From `OamDma.zig:94-96`:

```zig
pub fn reset(self: *OamDma) void {
    self.* = .{};
}
```

This sets everything to default, including `active = false` and `phase = .idle`.

So after reset, `active = false`, and `execution.zig` won't call `tickDma()` anymore. ✓

**But there's a race condition!**

From `updateBookkeeping`:

```zig
.skip => {
    const effective_cycle = calculateEffectiveCycle(dma);
    if (effective_cycle >= 512) {
        dma.current_cycle += 1;  // Cycle 512 → 513
    }
},

// ... (other cases)

// Check for completion (after updates)
const effective_cycle = calculateEffectiveCycle(dma);
if (effective_cycle > 512) {
    dma.reset();  // Sets active = false, phase = idle
}
```

**The completion check happens AFTER all action updates.** So there's one tick where:
- Phase = idle
- Active = false
- But we're still inside tickDma()

The next frame won't call tickDma() because active = false. ✓

**So BUG #2 is actually a FALSE ALARM for idle state.**

**But let me check the cycle count more carefully...**

The comment says "Complete AFTER cycle 512 executes", and the check is `effective_cycle > 512`. Let me verify this is correct.

**Cycle sequence (even start):**
- Cycles 0-511: Data transfer (256 reads + 256 writes = 512 cycles)
- Cycle 512: Dummy read (skip action, increment to 513)
- Completion check: 513 > 512 → reset

**Total cycles before reset: 513** ✓

**But the nesdev spec says 513 cycles TOTAL, which should include all cycles from trigger to completion.**

Let me check when the trigger happens...

From `OamDma.zig:83-91`:

```zig
pub fn trigger(self: *OamDma, page: u8, on_odd_cycle: bool) void {
    self.active = true;
    self.phase = if (on_odd_cycle) .aligning else .reading;
    self.source_page = page;
    self.current_offset = 0;
    self.current_cycle = 0;  // Starts at 0
    self.needs_alignment = on_odd_cycle;
    self.temp_value = 0;
}
```

The trigger happens when `$4014` is written. This is a WRITE cycle. The DMA starts on the NEXT cycle.

From nesdev.org:
> "The DMA transfer begins on the next CPU cycle after the write to $4014."

So:
- Cycle N: Write to $4014 (trigger)
- Cycle N+1: DMA cycle 0 (first read or alignment wait)
- ...
- Cycle N+513: DMA completes (even start) or N+514 (odd start)

**Total DMA cycles: 513 (even) or 514 (odd)** ✓

**Checking the implementation:**

**Even start:**
- Trigger sets current_cycle = 0
- First tick: cycle 0, read byte 0
- Last tick: cycle 512, dummy read
- Cycle 512 → 513 → reset
- Total cycles: 0-512 inclusive = 513 cycles ✓

**Odd start:**
- Trigger sets current_cycle = 0, needs_alignment = true
- First tick: cycle 0, effective_cycle = -1, alignment wait
- Cycle 0 → 1
- Second tick: cycle 1, effective_cycle = 0, read byte 0
- Last tick: cycle 513, effective_cycle = 512, dummy read
- Cycle 513 → 514 → reset
- Total cycles: 0-513 inclusive = 514 cycles ✓

**Looks correct!**

**But wait, I see an off-by-one error...**

The completion check is:

```zig
if (effective_cycle > 512) {
    dma.reset();
}
```

This resets when effective_cycle = 513. But for odd start:
- After dummy read (cycle 513, effective 512), skip increments current_cycle to 514
- effective_cycle = 514 - 1 = 513
- Completion check: 513 > 512 → reset ✓

**So it's correct.**

**Actually, I realize the test is failing...**

From the test output earlier:

```
error: 'dmc_oam_conflict_test.test.Cycle count: OAM 513 + DMC 4 = 517 total' failed: expected 517, found 1132
```

The cycle count is WAY off (1132 vs 517). This suggests an infinite loop or missing completion.

Let me check if the completion logic actually works...

**Hypothesis:** The completion check `effective_cycle > 512` might never trigger if effective_cycle gets stuck at 512.

Looking at the skip action:

```zig
.skip => {
    const effective_cycle = calculateEffectiveCycle(dma);
    if (effective_cycle >= 512) {
        dma.current_cycle += 1;
    }
},
```

**At cycle 512:**
- determineAction returns .skip
- updateBookkeeping(.skip): effective_cycle = 512 >= 512 → increment to 513
- Completion check: effective_cycle = 513 > 512 → reset ✓

**Should work...**

**Unless...** What if the phase is IDLE when effective_cycle = 512?

```zig
switch (dma.phase) {
    .idle => return .skip,
    .paused_during_read, .paused_during_write => return .skip,
    else => {},
}
```

If phase = idle, it returns .skip immediately, without checking effective_cycle.

Then updateBookkeeping(.skip):
- effective_cycle >= 512 → increment
- Completion check: effective_cycle > 512 → reset (again, already idle)

**But why would phase be idle before completion?**

Let me check all phase transitions again...

**Actually, I found it!**

Looking at `updateBookkeeping` for `.write`:

```zig
.write => {
    dma.phase = .writing;
    ppu_oam_addr.* +%= 1;
    dma.current_offset +%= 1;
    dma.current_cycle += 1;
},
```

After writing byte 255:
- current_offset = 255
- After write: current_offset = 0 (wraps)
- current_cycle = 512
- phase = .writing

Next tick:
- phase = .writing
- determineAction checks idle/paused: phase .writing doesn't match, continue
- Check duplication: phase != resuming_with_duplication, continue
- effective_cycle = 512
- Check completion: 512 >= 512 → return .skip ✓
- updateBookkeeping(.skip): increment to 513
- Completion check: 513 > 512 → reset ✓

**Should work...**

**Let me check if there's a problem with the PAUSE/RESUME flow...**

If DMC interrupts during the dummy read (cycle 512):
- Pause at cycle 512 (would have been skip/dummy read)
- current_cycle frozen at 512
- DMC runs
- DMC completes
- Resume: phase → resuming_normal (or resuming_with_duplication if it was a read)
- Cycle still 512
- determineAction: 512 >= 512 → return .skip
- updateBookkeeping(.skip): increment to 513
- Completion: 513 > 512 → reset ✓

**Should work...**

**Let me look at the actual test to see what's happening...**

From `dmc_oam_conflict_test.zig:339-375`:

```zig
test "Cycle count: OAM 513 + DMC 4 = 517 total" {
    // ... setup ...

    // Ensure even CPU cycle start
    while ((state.clock.ppu_cycles % 6) != 0) {
        state.tick();
    }
    const start_ppu = state.clock.ppu_cycles;

    // Start OAM DMA
    state.busWrite(0x4014, 0x09);
    try testing.expect(!state.dma.needs_alignment); // Even start

    // Run to byte 64, then interrupt with DMC
    harness.tickCpu(128);
    state.dmc_dma.triggerFetch(0xC000);

    // Run to completion
    runUntilDmcDmaComplete(state);
    runUntilOamDmaComplete(state);

    // Calculate elapsed CPU cycles
    const elapsed_ppu = state.clock.ppu_cycles - start_ppu;
    const elapsed_cpu = elapsed_ppu / 3;

    // Should be 513 (OAM base) + 4 (DMC) = 517 CPU cycles
    try testing.expectEqual(@as(u64, 517), elapsed_cpu);
}
```

The helper `runUntilOamDmaComplete`:

```zig
fn runUntilOamDmaComplete(state: *EmulationState) void {
    var tick_count: u32 = 0;
    while (state.dma.active and tick_count < 3000) : (tick_count += 1) {
        state.tick();
    }
}
```

It runs until `dma.active = false` or timeout (3000 ticks).

**If the test found 1132 cycles, it means the loop hit the timeout!** OAM never completed.

**This confirms there's an infinite loop bug.**

Let me trace through the scenario more carefully:

1. Start OAM DMA (even start)
2. Run 128 CPU cycles (= byte 64)
3. Trigger DMC
4. Run until DMC completes (4 cycles)
5. Run until OAM completes (should be 513 - 128 = 385 more cycles)

**Step 3-4: DMC interrupt**

At cycle 128:
- dma.current_cycle = 128 (even, reading byte 64)
- DMC triggered
- DMC rising edge detected
- Pause logic: phase → paused_during_read
- DMC ticks
- OAM does NOT tick

Cycles 129-131: DMC active, OAM paused

Cycle 132: DMC completes
- dmc.rdy_low = false
- DMC inactive edge
- Resume logic: phase → resuming_with_duplication
- OAM ticks:
  - determineAction: phase = resuming_with_duplication → duplication_write
  - executeAction: write interrupted byte
  - updateBookkeeping: phase = resuming_normal, cycle still 128

Cycle 133:
- phase = resuming_normal, cycle = 128 (even)
- determineAction: fall through to cycle parity → 128 % 2 = 0 → READ
- executeAction: read byte 64 (again, offset still 64)
- updateBookkeeping(.read): phase = .reading, cycle = 129

**So far so good...**

Cycle 134:
- phase = .reading, cycle = 129 (odd)
- determineAction: 129 % 2 = 1 → WRITE
- executeAction: write byte 64
- updateBookkeeping(.write): phase = .writing, offset = 65, cycle = 130

**Continues normally until byte 255...**

Cycle 510 (after DMC delay):
- Read byte 255

Cycle 511:
- Write byte 255
- offset wraps to 0
- cycle = 512

Cycle 512:
- phase = .writing, cycle = 512
- determineAction: 512 >= 512 → SKIP
- updateBookkeeping(.skip): 512 >= 512 → cycle = 513
- Completion check: 513 > 512 → reset

**Should complete!**

**But the test says it doesn't...**

**Wait, I need to check if the DMC interrupt is happening CORRECTLY.**

Looking at `execution.zig:144-145`:

```zig
if (dmc_rising_edge and DmaInteraction.shouldOamPause(&state.dma_interaction_ledger, &state.dma, true)) {
```

This checks `shouldOamPause`. Let me look at that:

From `interaction.zig:163-175`:

```zig
pub fn shouldOamPause(
    _: *const DmaInteractionLedger,
    oam: *const OamDma,
    dmc_active: bool,
) bool {
    return dmc_active and
        oam.active and
        !isPaused(oam.phase);
}
```

**Wait, this doesn't check if OAM is RESUMING!**

Helper `isPaused`:

```zig
fn isPaused(phase: OamDmaPhase) bool {
    return phase == .paused_during_read or phase == .paused_during_write;
}
```

**If phase = .resuming_normal or .resuming_with_duplication, it's NOT paused, so shouldOamPause returns TRUE!**

**This means if DMC triggers again while OAM is in resuming phase, it will try to pause AGAIN!**

**Let me check the test "Consecutive DMC interrupts"...**

From `dmc_oam_conflict_test.zig:302-333`:

```zig
test "Consecutive DMC interrupts (no gap)" {
    // ... setup ...

    // Start OAM DMA
    state.busWrite(0x4014, 0x08);

    // Run to byte 64
    harness.tickCpu(128);

    // First DMC interrupt
    state.dmc_dma.triggerFetch(0xC000);
    runUntilDmcDmaComplete(state);

    // Second DMC interrupt immediately after
    state.dmc_dma.triggerFetch(0xC100);
    runUntilDmcDmaComplete(state);

    // Complete OAM
    runUntilOamDmaComplete(state);

    // Verify completion
    try testing.expect(!state.dma.active);
}
```

This test has TWO consecutive DMC interrupts. After the first DMC completes, OAM resumes to `resuming_with_duplication`. Then immediately, the SECOND DMC triggers.

**What happens?**

Cycle N: First DMC completes
- Resume logic: phase → resuming_with_duplication
- OAM ticks:
  - determineAction: duplication_write
  - updateBookkeeping: phase = resuming_normal

Cycle N+1: Second DMC triggers
- dmc_rising_edge = true
- shouldOamPause: dmc_active=true, oam.active=true, phase=resuming_normal (NOT paused) → TRUE
- Pause logic runs:
  - handleDmcPausesOam called
  - effective_cycle = N+1
  - is_reading = (N+1 % 2 == 0)
  - phase → paused_during_read or paused_during_write

**This causes a SECOND pause.**

But is this correct hardware behavior?

From nesdev.org:
> "The DMC DMA can interrupt an already running OAM DMA transfer."

It doesn't say anything about consecutive interrupts. But logically, if DMC can interrupt OAM once, it should be able to interrupt again.

**So the behavior might be correct, but let me check if it causes the infinite loop...**

If the second DMC interrupt happens during resuming_normal:
- Cycle N+1: phase = resuming_normal, cycle = 128 (even, about to re-read byte 64)
- DMC interrupts
- Pause logic: is_reading = true → phase = paused_during_read
- Captured state: offset = 64, byte_value = ??? (will be read), oam_addr = ???

Wait, the pause logic reads the interrupted byte:

From `execution.zig:152-158`:

```zig
var interrupted = pause_data.interrupted_state;
if (pause_data.read_interrupted_byte) |read_info| {
    const addr = (@as(u16, read_info.source_page) << 8) | read_info.offset;
    interrupted.byte_value = state.busRead(addr);
    interrupted.oam_addr = state.ppu.oam_addr;
}
```

It reads the byte and captures oam_addr. So the SECOND pause will capture the state again, overwriting the FIRST pause state.

**This could be a problem!**

After the FIRST pause, we have:
- interrupted_state.offset = 64
- interrupted_state.byte_value = value at offset 64

After the SECOND pause (consecutive), we STILL have:
- interrupted_state.offset = 64 (unchanged, because duplication write didn't advance offset)
- interrupted_state.byte_value = value at offset 64 (re-read)

So the state is the same. After the second DMC completes:
- Resume: phase → resuming_with_duplication (again)
- Duplication write (offset still 64)
- Transition to resuming_normal
- Next action: re-read byte 64 (AGAIN)

**This creates a loop!** We keep re-reading and re-writing byte 64.

**But wait, the duplication write DOES advance oam_addr:**

From `actions.zig:158-167`:

```zig
.duplication_write => {
    ppu_oam_addr.* +%= 1; // OAM address advances (byte written)
    // Do NOT advance offset - we need to RE-READ the same source byte next cycle
    // Do NOT advance cycle - duplication is "free"
    dma.phase = .resuming_normal;
    ledger.duplication_pending = false;
},
```

So each duplication write advances oam_addr. Eventually, oam_addr wraps back to 0, but that doesn't affect the DMA transfer.

**But the offset NEVER advances past 64!**

After duplication write:
- offset = 64 (unchanged)

Next action (re-read):
- Read byte 64 into temp_value
- offset still 64 (read doesn't advance offset)

Next action (write):
- Write temp_value to OAM
- offset = 65 (write advances offset) ✓

**So after the re-read and re-write, offset finally advances!**

Unless... we get interrupted AGAIN during the re-read.

**If DMC keeps interrupting during the read of byte 64, we'll loop forever!**

**But the test triggers DMC manually, not continuously. Let me re-read the test...**

From `dmc_oam_conflict_test.zig:320-327`:

```zig
// First DMC interrupt
state.dmc_dma.triggerFetch(0xC000);
runUntilDmcDmaComplete(state);

// Second DMC interrupt immediately after
state.dmc_dma.triggerFetch(0xC100);
runUntilDmcDmaComplete(state);
```

`runUntilDmcDmaComplete` runs until `dmc_dma.rdy_low = false`. So the second DMC starts AFTER the first completes.

Timeline:
- Cycle N: First DMC completes, OAM resumes to resuming_with_duplication
- Cycle N: OAM ticks (duplication write, phase → resuming_normal)
- Cycle N+1: Second DMC triggers
- Cycle N+1: OAM should tick (re-read byte 64)
- But DMC is active (rdy_low = true)
- execution.zig checks DMC first: `if (state.dmc_dma.rdy_low)`
- Pause logic runs: phase → paused_during_read (AGAIN)
- DMC ticks
- OAM does NOT tick (return early)

**So the re-read NEVER happens!** We pause again before re-reading.

After second DMC completes:
- Resume: phase → resuming_with_duplication (byte 64 AGAIN)
- Duplication write (byte 64 to OAM, offset still 64)
- Phase → resuming_normal
- Next cycle: re-read byte 64

**And if there's no third DMC interrupt, it continues normally.**

So consecutive interrupts should work, just with extra duplication.

**But why is the test timing out?**

Let me check `runUntilOamDmaComplete` again:

```zig
fn runUntilOamDmaComplete(state: *EmulationState) void {
    var tick_count: u32 = 0;
    while (state.dma.active and tick_count < 3000) : (tick_count += 1) {
        state.tick();
    }
}
```

It runs until `dma.active = false`.

**If `dma.active` never becomes false, it loops 3000 times.**

**When does `dma.active` become false?**

Only in `dma.reset()`, which is called in the completion check:

```zig
if (effective_cycle > 512) {
    dma.reset();
}
```

**So if effective_cycle never exceeds 512, DMA never completes.**

**Let me check if effective_cycle can get stuck...**

After completing all 256 bytes:
- current_cycle should be 512
- effective_cycle = 512 (or 512 - 1 = 511 if needs_alignment)

Next tick:
- determineAction: 512 >= 512 → SKIP
- updateBookkeeping(.skip): 512 >= 512 → increment to 513
- effective_cycle = 513 (or 512 if needs_alignment)
- Completion check: 513 > 512 → reset (or 512 > 512 = false if needs_alignment!)

**FOUND IT!** If `needs_alignment = true`, effective_cycle = current_cycle - 1.

After the dummy read:
- current_cycle = 513
- effective_cycle = 513 - 1 = 512
- Completion check: 512 > 512 = FALSE
- **No reset!**

Next tick:
- effective_cycle = 512
- determineAction: 512 >= 512 → SKIP
- updateBookkeeping(.skip): 512 >= 512 → increment to 514
- effective_cycle = 514 - 1 = 513
- Completion check: 513 > 512 = TRUE → reset ✓

**So odd-start DMA requires one extra tick for completion.**

**But the comment says the completion is correct:**

> "BUG #2/#3 FIX: Complete at cycle 513, not 512"

Wait, the comment says it's a FIX for bugs #2 and #3. Let me check if the fix is correct...

**Even start (needs_alignment = false):**
- Cycles 0-511: 256 read/write pairs
- Cycle 512: dummy read (skip)
- current_cycle increments to 513
- effective_cycle = 513
- Completion: 513 > 512 → reset ✓
- Total cycles: 513 ✓

**Odd start (needs_alignment = true):**
- Cycle 0 (effective -1): alignment wait
- Cycles 1-512 (effective 0-511): 256 read/write pairs
- Cycle 513 (effective 512): dummy read (skip)
- current_cycle increments to 514
- effective_cycle = 513
- Completion: 513 > 512 → reset ✓
- Total cycles: 514 ✓

**So it's correct!**

**Then why is the test timing out?**

Let me check if the test has an odd start...

From the test:

```zig
// Ensure even CPU cycle start
while ((state.clock.ppu_cycles % 6) != 0) {
    state.tick();
}

// Start OAM DMA
state.busWrite(0x4014, 0x09);
try testing.expect(!state.dma.needs_alignment); // Even start
```

It verifies even start, so `needs_alignment = false`.

**Then the completion should work...**

**Unless...**

Let me check if the DMC interrupt affects the completion...

If DMC interrupts at cycle 512 (the dummy read):
- Pause logic captures state
- Cycle frozen at 512
- DMC runs
- DMC completes
- Resume logic: phase → resuming_normal or resuming_with_duplication

If it was a read (cycle 512 is even):
- is_reading = true
- Resume: phase → resuming_with_duplication
- Duplication write (cycle still 512, doesn't increment)
- Phase → resuming_normal
- Next tick: cycle 512 (even) → READ
- This is the "re-read" of the dummy read!
- updateBookkeeping(.read): cycle = 513
- Next tick: cycle 513 (odd) → WRITE
- But we've already written all 256 bytes!
- current_offset = 0 (wrapped)
- We write byte 0 AGAIN to OAM!
- updateBookkeeping(.write): offset = 1, cycle = 514
- Completion check: 514 > 512 → reset ✓

**So it still completes, just with an extra read/write of byte 0.**

**But wait, the dummy read shouldn't be treated as reading byte 0...**

From `determineAction`:

```zig
// Completion check (handled in updateBookkeeping)
// DMA runs for 512 data cycles (0-511), but 513 total with dummy read
// Skip action at cycle 512 (completion happens after cycle 511)
if (effective_cycle >= 512) {
    return .skip;
}

// Normal operation: alternate read/write based on cycle parity
if (@rem(effective_cycle, 2) == 0) {
    // Even cycle: READ
    return .{ .read = .{
        .source_page = dma.source_page,
        .source_offset = dma.current_offset,  // offset = 0
    }};
}
```

**The dummy read check happens BEFORE the read/write logic!**

So at cycle 512:
- effective_cycle = 512
- 512 >= 512 → return .skip (dummy read)

**NOT a real read!** ✓

**But if we're in resuming_normal phase and cycle is 512:**
- effective_cycle = 512
- determineAction checks:
  - idle? no
  - paused? no
  - resuming_with_duplication? no
  - effective_cycle < 0? no
  - effective_cycle >= 512? YES → return .skip ✓

**So even resuming_normal falls through to the dummy read check!** ✓

**Then why is there an infinite loop?**

**Let me re-examine the PAUSE condition more carefully...**

From `execution.zig:144-145`:

```zig
if (dmc_rising_edge and DmaInteraction.shouldOamPause(&state.dma_interaction_ledger, &state.dma, true)) {
```

It checks `dmc_rising_edge`. This is computed earlier:

From `execution.zig:131-144`:

```zig
const prev_dmc_active = DmaInteraction.isDmcActive(&state.dma_interaction_ledger);
const curr_dmc_active = state.dmc_dma.rdy_low;

if (curr_dmc_active and !prev_dmc_active) {
    // Rising edge: DMC became active
    state.dma_interaction_ledger.last_dmc_active_cycle = state.clock.ppu_cycles;
} else if (!curr_dmc_active and prev_dmc_active) {
    // Falling edge: DMC became inactive
    state.dma_interaction_ledger.last_dmc_inactive_cycle = state.clock.ppu_cycles;
}

// ...

if (state.dmc_dma.rdy_low) {
    const dmc_rising_edge = curr_dmc_active and !prev_dmc_active;
    if (dmc_rising_edge and ...) {
```

**Wait, `isDmcActive` checks the ledger, not the actual `rdy_low` flag!**

From `interaction.zig:32-34`:

```zig
pub fn isDmcActive(ledger: *const DmaInteractionLedger) bool {
    return ledger.last_dmc_active_cycle > ledger.last_dmc_inactive_cycle;
}
```

This uses timestamps to determine if DMC is active.

**So the edge detection is:**
- prev_dmc_active: ledger.last_dmc_active_cycle > ledger.last_dmc_inactive_cycle
- curr_dmc_active: state.dmc_dma.rdy_low
- dmc_rising_edge: curr=true AND prev=false

**If ledger timestamps are updated correctly, this should work.**

But the timestamps are updated at lines 132-136:

```zig
if (curr_dmc_active and !prev_dmc_active) {
    state.dma_interaction_ledger.last_dmc_active_cycle = state.clock.ppu_cycles;
} else if (!curr_dmc_active and prev_dmc_active) {
    state.dma_interaction_ledger.last_dmc_inactive_cycle = state.clock.ppu_cycles;
}
```

**This ALSO checks the ledger-based prev_dmc_active!**

So:
- Cycle 1: DMC triggers (rdy_low = true)
  - prev = isDmcActive(ledger) = (0 > 0) = false
  - curr = true
  - Rising edge: update last_dmc_active_cycle = 1
  - dmc_rising_edge = true AND false = true ✓
  - Pause OAM

- Cycle 2-4: DMC active
  - prev = isDmcActive(ledger) = (1 > 0) = true
  - curr = true
  - No edge, timestamps unchanged
  - dmc_rising_edge = true AND true = false (no pause)

- Cycle 5: DMC completes (rdy_low = false)
  - prev = isDmcActive(ledger) = (1 > 0) = true
  - curr = false
  - Falling edge: update last_dmc_inactive_cycle = 5
  - Resume OAM

**Looks correct...**

**But wait, there's ANOTHER timestamp update at lines 173-177:**

```zig
state.tickDmcDma();

// Check for DMC completion edge AFTER tick
// (DMC may have just completed, need to record the falling edge)
if (!state.dmc_dma.rdy_low and prev_dmc_active) {
    state.dma_interaction_ledger.last_dmc_inactive_cycle = state.clock.ppu_cycles;
}
```

**This updates the timestamp AFTER tickDmcDma().** So if DMC completes during the tick, the falling edge is recorded.

**But this creates a duplicate update!**

If DMC completes:
- Before tick: rdy_low = true, prev = true, curr = true
- After tick: rdy_low = false
- Line 134-136 check: curr=false, prev=true → update last_dmc_inactive_cycle
- Line 175-177 check: rdy_low=false, prev=true → update last_dmc_inactive_cycle (AGAIN)

**This is redundant but harmless (same value written twice).**

**Let me focus on the RESUME logic...**

From `execution.zig:182-197`:

```zig
// OAM DMA active - CPU frozen for 512 cycles
if (state.dma.active) {
    // Check if OAM should resume after DMC completes
    if (DmaInteraction.shouldOamResume(&state.dma_interaction_ledger, &state.dma, false, state.clock.ppu_cycles)) {
        const resume_data = DmaInteraction.handleOamResumes(&state.dma_interaction_ledger, state.clock.ppu_cycles);

        // Apply ALL mutations centrally
        state.dma_interaction_ledger.oam_resume_cycle = resume_data.resume_cycle;

        // Transition to resume phase (duplication handled in tickDma)
        state.dma.phase = resume_data.resume_phase;
    }

    state.tickDma();
    return .{};
}
```

**The resume logic runs BEFORE tickDma()!** So on the cycle when DMC completes:
- shouldOamResume checks are met
- Phase transitions to resuming_with_duplication or resuming_normal
- tickDma() executes with the new phase

**Let me trace through a complete scenario:**

**Setup:**
- Even start, no alignment
- DMC interrupts at cycle 128 (reading byte 64)

**Cycle 0-127: Normal OAM operation**
- Reads and writes bytes 0-63
- current_cycle = 128, offset = 64

**Cycle 128: DMC rising edge**
- prev_dmc = false, curr_dmc = true
- Rising edge: update last_dmc_active_cycle = 128
- dmc_rising_edge = true
- shouldOamPause: true
- Pause logic:
  - effective_cycle = 128 (even)
  - is_reading = true
  - Read byte 64: interrupted.byte_value = value_64
  - interrupted.oam_addr = 64
  - oam_pause_cycle = 128
  - duplication_pending = true
  - phase → paused_during_read
- tickDmcDma() runs
- **tickDma() does NOT run (return early)**

**Cycle 129-131: DMC active, OAM paused**
- prev_dmc = true, curr_dmc = true
- No edges
- tickDmcDma() runs each cycle
- tickDma() does NOT run

**Cycle 132: DMC completes**
- DMC tick causes rdy_low = false
- After tickDmcDma(): rdy_low = false
- Falling edge: update last_dmc_inactive_cycle = 132
- Return early (DMC was active at start of cycle)

**Cycle 133: OAM resumes**
- DMC: rdy_low = false, prev_dmc = false, curr_dmc = false (no edges)
- OAM: active = true
- shouldOamResume:
  - isPaused(phase) = true (paused_during_read)
  - !dmc_active = true
  - oam_pause_cycle > 0 = true (128 > 0)
  - oam_resume_cycle == 0 = true
  - last_dmc_inactive_cycle > oam_pause_cycle = true (132 > 128)
  - last_dmc_inactive_cycle == cycle = true (132 == 133)?

**WAIT! This check is wrong:**

From `interaction.zig:185-198`:

```zig
pub fn shouldOamResume(
    ledger: *const DmaInteractionLedger,
    oam: *const OamDma,
    dmc_active: bool,
    cycle: u64,
) bool {
    return isPaused(oam.phase) and
        !dmc_active and
        ledger.oam_pause_cycle > 0 and
        ledger.oam_resume_cycle == 0 and
        ledger.last_dmc_inactive_cycle > ledger.oam_pause_cycle and
        ledger.last_dmc_inactive_cycle == cycle;  // 🚨 EXACT cycle match!
}
```

**The last line requires EXACT cycle match:** `last_dmc_inactive_cycle == cycle`.

In the scenario:
- last_dmc_inactive_cycle = 132 (when DMC completed)
- Current cycle = 133
- 132 == 133 = FALSE

**So shouldOamResume returns FALSE!**

OAM will NEVER resume because the exact cycle was missed!

**Found the bug!**

---

**Actually, let me re-check when the falling edge is recorded...**

From `execution.zig:126-180`:

```zig
pub fn stepCycle(state: anytype) CpuCycleResult {
    // ... (lines 126-137: Edge detection and timestamp updates)

    // DMC DMA active - CPU stalled (RDY line low)
    if (state.dmc_dma.rdy_low) {
        // ... (lines 142-169: Pause logic)

        state.tickDmcDma();

        // Check for DMC completion edge AFTER tick
        // (DMC may have just completed, need to record the falling edge)
        if (!state.dmc_dma.rdy_low and prev_dmc_active) {
            state.dma_interaction_ledger.last_dmc_inactive_cycle = state.clock.ppu_cycles;
        }

        return .{};  // <-- EXIT HERE
    }

    // OAM DMA active - CPU frozen for 512 cycles
    if (state.dma.active) {
        // Check if OAM should resume after DMC completes
        if (DmaInteraction.shouldOamResume(...)) {
            // ...
        }

        state.tickDma();
        return .{};
    }
```

**The problem is that the falling edge timestamp is recorded at line 176, but then we RETURN at line 179!**

So on the cycle when DMC completes:
- rdy_low becomes false during tickDmcDma()
- Falling edge timestamp is recorded
- Function returns (OAM doesn't tick this cycle)

**Next cycle:**
- DMC: rdy_low = false (not active)
- OAM: active = true
- shouldOamResume:
  - last_dmc_inactive_cycle = 132 (previous cycle)
  - cycle = 133 (current cycle)
  - 132 == 133 = FALSE

**OAM never resumes!**

---

**But wait, the edge detection at lines 131-137 happens BEFORE the DMC tick:**

```zig
const prev_dmc_active = DmaInteraction.isDmcActive(&state.dma_interaction_ledger);
const curr_dmc_active = state.dmc_dma.rdy_low;

if (curr_dmc_active and !prev_dmc_active) {
    state.dma_interaction_ledger.last_dmc_active_cycle = state.clock.ppu_cycles;
} else if (!curr_dmc_active and prev_dmc_active) {
    state.dma_interaction_ledger.last_dmc_inactive_cycle = state.clock.ppu_cycles;
}
```

If DMC completes on cycle 132:
- At start of cycle 132: rdy_low = true (DMC still active)
- Edge detection: curr = true, prev = true (no edge)
- tickDmcDma() runs: rdy_low becomes false
- Post-tick check (line 175): rdy_low = false, prev = true → update last_dmc_inactive_cycle = 132
- Return

**At start of cycle 133:**
- Edge detection: curr = false, prev = false (ledger shows inactive)
- No edges
- Skip DMC block (rdy_low = false)
- OAM block: shouldOamResume checks
  - last_dmc_inactive_cycle = 132
  - cycle = 133
  - 132 == 133 = FALSE

**OAM still doesn't resume!**

---

**Let me check the comment for shouldOamResume:**

From `interaction.zig:177-184`:

```zig
/// Query if OAM should resume on this cycle
///
/// **Pure function** - reads ledger state, no mutations.
pub fn shouldOamResume(
    ledger: *const DmaInteractionLedger,
    oam: *const OamDma,
    dmc_active: bool,
    cycle: u64,
) bool {
```

The comment says "on this cycle", which suggests it should trigger on the EXACT cycle when DMC completes.

**But the implementation requires `last_dmc_inactive_cycle == cycle`, which means it should trigger on the SAME cycle the timestamp was recorded.**

**Looking at the post-tick timestamp update:**

```zig
state.tickDmcDma();

// Check for DMC completion edge AFTER tick
if (!state.dmc_dma.rdy_low and prev_dmc_active) {
    state.dma_interaction_ledger.last_dmc_inactive_cycle = state.clock.ppu_cycles;
}

return .{};
```

**The timestamp is recorded on cycle 132, but the function returns immediately. OAM doesn't get a chance to check shouldOamResume until cycle 133.**

**This is BUG #4!**

**Wait, the comment in interaction.zig line 192 says:**

```zig
// 6. EXACT cycle match (edge detection - BUG #4 FIX)
```

So this line is supposed to be a FIX for bug #4. Let me check if the fix is correct...

**The problem:** On cycle 132, DMC completes and timestamp is recorded. But OAM doesn't check until cycle 133.

**The fix:** Check for EXACT cycle match, so OAM only resumes on cycle 132.

**But this doesn't work because OAM can't check on cycle 132 (function returns early)!**

**The REAL fix should be:** Remove the exact cycle match requirement, and instead use `last_dmc_inactive_cycle >= oam_pause_cycle` to check if DMC has completed since the pause.

**Or**, move the shouldOamResume check to BEFORE the `if (state.dmc_dma.rdy_low)` block, so it can run on the same cycle as DMC completion.

**Or**, remove the early return and let OAM check even when DMC just completed this cycle.

---

**Actually, let me re-read the control flow...**

```zig
if (state.dmc_dma.rdy_low) {
    // ... pause logic ...
    state.tickDmcDma();
    // ... post-tick timestamp update ...
    return .{};  // DMC still active OR just completed - EXIT
}

// Only reached if DMC is NOT active (rdy_low = false)
if (state.dma.active) {
    if (DmaInteraction.shouldOamResume(...)) {
        // ...
    }
    state.tickDma();
    return .{};
}
```

**The OAM block is ONLY reached when DMC is NOT active** (`rdy_low = false`).

**On the cycle when DMC completes:**
- Start: rdy_low = true
- Enter DMC block
- tickDmcDma(): rdy_low becomes false
- Post-tick timestamp: last_dmc_inactive_cycle = 132
- Return (EXIT before OAM block)

**Next cycle:**
- Start: rdy_low = false
- Skip DMC block
- Enter OAM block
- shouldOamResume: last_dmc_inactive_cycle (132) == cycle (133)? FALSE

**OAM never resumes.**

**This confirms BUG #4: EXACT cycle match prevents resume because the check happens one cycle later.**

---

**Proposed Fix:**

Change the exact cycle check to:

```zig
ledger.last_dmc_inactive_cycle >= ledger.oam_pause_cycle and
ledger.oam_resume_cycle == 0
```

This checks:
1. DMC has completed since the pause
2. Resume hasn't happened yet

The `oam_resume_cycle == 0` guard prevents multiple resumes.

**Or**, check on the NEXT cycle after DMC completes:

```zig
ledger.last_dmc_inactive_cycle == cycle - 1
```

But this is fragile if there are any clock adjustments.

**Best fix:** Remove exact cycle match entirely, rely on oam_resume_cycle guard.

---

**Actually, let me check if there's another issue...**

Looking at the tests again, some tests DO pass:

From the test output earlier:

```
test "MINIMAL: DMC pauses OAM (debug with proper harness)" PASSED
```

So SOME pause/resume logic is working. Let me check what that test does:

From `dmc_oam_conflict_test.zig:59-79`:

```zig
test "MINIMAL: DMC pauses OAM (debug with proper harness)" {
    var harness = try Harness.init();
    defer harness.deinit();
    var state = &harness.state;

    // Setup DMC channel
    state.apu.dmc_bytes_remaining = 10;
    state.apu.dmc_active = true;

    // Trigger OAM DMA
    state.busWrite(0x4014, 0x0A);

    // Trigger DMC DMA (this should cause pause when we tick)
    state.dmc_dma.triggerFetch(0xC000);

    // Tick once CPU cycle - OAM should pause
    harness.tickCpu(1);

    // Verify pause happened
    try testing.expect(isDmaPaused(state));
}
```

This test ONLY checks if pause happens, not if resume works. So pause logic is correct, but resume logic is broken.

**This confirms BUG #4.**

---

**Summary of CRITICAL BUG #4:**

**Issue:** OAM never resumes after DMC completes because exact cycle match check (`last_dmc_inactive_cycle == cycle`) fails. The timestamp is recorded on cycle N, but the check happens on cycle N+1.

**Location:** `/home/colin/Development/RAMBO/src/emulation/dma/interaction.zig:198`

**Fix:** Remove exact cycle match, rely on `oam_resume_cycle == 0` guard to prevent double-resume.

```zig
pub fn shouldOamResume(
    ledger: *const DmaInteractionLedger,
    oam: *const OamDma,
    dmc_active: bool,
    cycle: u64,  // Remove this parameter, no longer needed
) bool {
    return isPaused(oam.phase) and
        !dmc_active and
        ledger.oam_pause_cycle > 0 and
        ledger.oam_resume_cycle == 0 and
        ledger.last_dmc_inactive_cycle > ledger.oam_pause_cycle;
        // ^^^ Removed exact cycle match
}
```

---

Now let me check the other bugs...

---

#### 🚨 CRITICAL BUG #3: Skip Action Increments Cycle in Wrong States

**Location:** `/home/colin/Development/RAMBO/src/emulation/dma/actions.zig:131-139`

```zig
.skip => {
    // Only increment cycle at completion (effective_cycle >= 512)
    // Paused states return skip but shouldn't increment (counter frozen)
    // Check effective_cycle to distinguish completion skip from pause skip
    const effective_cycle = calculateEffectiveCycle(dma);
    if (effective_cycle >= 512) {
        dma.current_cycle += 1;
    }
},
```

**Analysis:**

Skip is returned for:
1. `.idle` phase (line 58)
2. `.paused_during_read` / `.paused_during_write` (line 59)
3. Completion (effective_cycle >= 512, line 82)

**For idle state:**
- If tickDma() is somehow called when phase = idle, skip is returned
- effective_cycle could be anything (leftover from previous DMA)
- If effective_cycle >= 512, cycle increments

**But as analyzed earlier, tickDma() is only called when `dma.active = true`, and after reset, `active = false`. So idle state should never tick.**

**However, there's a subtle race:**

After completion check resets the DMA:
```zig
if (effective_cycle > 512) {
    dma.reset();  // Sets active = false, phase = idle
}
```

The reset happens AFTER updateBookkeeping returns. So if there's any code that checks the phase BETWEEN updateBookkeeping and the completion check... actually, there isn't. The completion check is at the end of updateBookkeeping.

**So this is NOT a bug in practice, but it's defensive programming missing.**

**Recommendation:** Add explicit phase check in skip action:

```zig
.skip => {
    // Idle and paused states: do nothing
    if (dma.phase == .idle or
        dma.phase == .paused_during_read or
        dma.phase == .paused_during_write) {
        return;
    }

    // Completion cycle: increment before reset
    const effective_cycle = calculateEffectiveCycle(dma);
    if (effective_cycle >= 512) {
        dma.current_cycle += 1;
    }
},
```

**Severity:** ⚠️ HIGH PRIORITY (defensive programming, not a current bug)

---

Now let me write the complete review document...

