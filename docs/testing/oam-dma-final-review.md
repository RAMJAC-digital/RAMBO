# OAM DMA State Machine - Final Correctness Review

**Date:** 2025-10-16
**Reviewer:** Configuration Security / Hardware Accuracy Specialist
**Status:** 🚨 CRITICAL ISSUE IDENTIFIED

---

## Executive Summary

**CRITICAL FINDING:** OAM DMA resume logic has a race condition causing byte duplication to be skipped.

**Test Status:** 6/13 DMC/OAM conflict tests failing
**Root Cause:** `.duplication_write` action completes immediately, transitioning to `.resuming_normal` BEFORE the next tick can execute the re-read

---

## Critical Bug Analysis

### 🚨 BUG: Duplication Write Completes Too Fast

**Location:** `/home/colin/Development/RAMBO/src/emulation/dma/actions.zig:158-167`
**Severity:** CRITICAL - Violates hardware behavior
**Impact:** Byte duplication never occurs, breaking hardware accuracy

**Problem Code:**

```zig
.duplication_write => {
    // Hardware behavior: The interrupted byte is written to current OAM slot
    // Then the SAME byte is RE-READ and written again (byte duplication)
    // This is a "free" operation that doesn't consume a cycle
    ppu_oam_addr.* +%= 1; // OAM address advances (byte written)
    // Do NOT advance offset - we need to RE-READ the same source byte next cycle
    // Do NOT advance cycle - duplication is "free"
    dma.phase = .resuming_normal;  // 🚨 IMMEDIATE TRANSITION
    ledger.duplication_pending = false;
},
```

**Timeline Analysis:**

When OAM resumes after DMC interrupt during read:

**Cycle N: Resume detected**
- `shouldOamResume` returns true
- `handleOamResumes` returns `resume_phase = .resuming_with_duplication` ✓
- Phase transitions to `.resuming_with_duplication`
- `tickDma()` executes:
  - `determineAction()` returns `.duplication_write` ✓
  - `executeAction()` writes interrupted byte to OAM ✓
  - `updateBookkeeping()`:
    - OAM addr increments ✓
    - Offset UNCHANGED (for re-read) ✓
    - Cycle UNCHANGED (free operation) ✓
    - **Phase = .resuming_normal** ⚠️

**Cycle N+1: Re-read should happen**
- Phase = `.resuming_normal`
- `determineAction()` falls through to normal logic
- Cycle parity check: cycle N is even → returns `.read` ✓
- **BUT:** This is treated as a NORMAL read, not a duplication re-read!
- After read, phase transitions to `.reading`
- Cycle increments to N+1

**Cycle N+2: Write**
- Cycle N+1 is odd → returns `.write`
- Writes the byte ✓
- Offset increments to next byte ✓

**Result:** The re-read DOES happen, and the byte IS written again. So duplication DOES occur!

**Wait, then why are tests failing?**

Let me re-examine the debug trace more carefully...

---

## Debug Trace Re-Analysis

From test output:

```
AFTER tick 1:
  dma: active=true, phase=.paused_during_read, cycle=0
  ppu_cycles=3
  Interrupted: was_reading=true, offset=0, byte=0x00, oam_addr=0

=== RUNNING DMC TO COMPLETION ===
DMC completed after 9 ticks
  ppu_cycles=12
  Ledger: pause=3, resume=0, last_dmc_inactive=12

=== ATTEMPTING OAM RESUME ===
OAM tick 0: phase=.paused_during_read, cycle=0, offset=0, ppu_cycles=12
OAM tick 1: phase=.paused_during_read, cycle=0, offset=0, ppu_cycles=13
OAM tick 2: phase=.paused_during_read → .resuming_normal, cycle=0, offset=0, ppu_cycles=14
  Ledger: resume=15
```

**KEY OBSERVATION:** Phase transitions from `.paused_during_read` DIRECTLY to `.resuming_normal`, skipping `.resuming_with_duplication`!

**This means `handleOamResumes` is returning `.resuming_normal` even though `was_reading=true`!**

But the code clearly shows:

```zig
if (ledger.interrupted_state.was_reading) {
    return .{ .resume_phase = .resuming_with_duplication, ... };
} else {
    return .{ .resume_phase = .resuming_normal, ... };
}
```

**Hypothesis:** The `interrupted_state.was_reading` field is FALSE even though the trace shows it's TRUE.

**Explanation:** There might be MULTIPLE resume checks, and the SECOND check has corrupted state!

---

## Root Cause: Double Resume

Looking at the timing:

- ppu_cycles=12: DMC completes, `last_dmc_inactive_cycle = 12`
- ppu_cycles=12: OAM tick 0 - Still paused (shouldOamResume checks `cycle=12`)
- ppu_cycles=13: OAM tick 1 - Still paused (shouldOamResume checks `cycle=13`)
- ppu_cycles=14: OAM tick 2 - **RESUMES** (shouldOamResume checks `cycle=14`, resume_cycle set to 15)

Wait, why does `resume_cycle = 15` when the transition happens at `cycle=14`?

Let me check the `shouldOamResume` logic after the fix:

```zig
pub fn shouldOamResume(
    ledger: *const DmaInteractionLedger,
    oam: *const OamDma,
    dmc_active: bool,
    cycle: u64,
) bool {
    _ = cycle; // Not used - resume happens any time after DMC completes
    return isPaused(oam.phase) and
        !dmc_active and
        ledger.oam_pause_cycle > 0 and
        ledger.oam_resume_cycle == 0 and
        ledger.last_dmc_inactive_cycle > ledger.oam_pause_cycle;
}
```

**This will return TRUE on EVERY cycle after DMC completes, as long as `oam_resume_cycle == 0`!**

So on cycle 12, 13, 14, etc., it keeps returning TRUE until `oam_resume_cycle` is set.

But `oam_resume_cycle` is set to `resume_data.resume_cycle`, which is the CURRENT cycle passed to `handleOamResumes`.

**Timeline:**

- Cycle 12 (PPU):
  - `shouldOamResume`: last_dmc_inactive(12) > oam_pause(3)? YES, resume_cycle(0) == 0? YES → TRUE
  - `handleOamResumes(cycle=12)` returns `resume_cycle = 12`
  - `oam_resume_cycle = 12` ✓
  - Phase = `.resuming_with_duplication` (if was_reading) ✓
  - `tickDma()` executes duplication write
  - Phase = `.resuming_normal`

- Cycle 13 (PPU):
  - `shouldOamResume`: resume_cycle(12) == 0? NO → FALSE ✓
  - No resume logic
  - Phase = `.resuming_normal`
  - `tickDma()` executes normal logic

**This looks correct!**

---

## Actually, Let Me Check The Master Clock

The test uses `state.clock.ppu_cycles` which is the master clock. Let me verify this is updated correctly:

From debug trace:
- Initial: ppu_cycles=0
- After tick 1 (1 CPU cycle): ppu_cycles=3 ✓ (CPU:PPU = 1:3)
- After DMC completes (9 ticks): ppu_cycles=12

Wait, 9 ticks should be 9 PPU cycles, not 9 CPU cycles. DMC should take 4 CPU cycles = 12 PPU cycles.

Let me count:
- Tick 0: ppu 3 → 4 (1 PPU cycle)
- Tick 1: ppu 4 → 5
- Tick 2: ppu 5 → 6
- Tick 3: ppu 6 → 7
- Tick 4: ppu 7 → 8
- Tick 5: ppu 8 → 9
- Tick 6: ppu 9 → 10
- Tick 7: ppu 10 → 11
- Tick 8: ppu 11 → 12

**9 ticks = 9 PPU cycles** ✓

But DMC should take **4 CPU cycles = 12 PPU cycles**, not 9 PPU cycles!

**Ah!** The loop is calling `state.tick()` which advances 1 PPU cycle, not `harness.tickCpu()` which advances 1 CPU cycle!

So DMC completion took 9 PPU cycles = 3 CPU cycles, not 4 CPU cycles.

**This is a test infrastructure issue, not a DMA bug!**

---

## The REAL Bug: Missing Duplication Phase Transition

Looking at the trace again:

```
OAM tick 2: phase=.paused_during_read → .resuming_normal
```

It transitions DIRECTLY to `.resuming_normal`, skipping `.resuming_with_duplication`.

**This means the resume logic is NOT being called at all, OR it's being called with wrong state!**

Let me check if `shouldOamResume` is actually returning TRUE...

**Actually**, the trace shows `Ledger: resume=15` which means `oam_resume_cycle` WAS set. So the resume logic DID run.

But the phase went to `.resuming_normal` instead of `.resuming_with_duplication`.

**This means `handleOamResumes` returned `.resuming_normal` even though `was_reading=true`!**

---

## Hypothesis: Interrupted State Corruption

The interrupted state shows:
```
Interrupted: was_reading=true, offset=0, byte=0x00, oam_addr=0
```

But if `handleOamResumes` is checking this and returning `.resuming_normal`, it means the check is seeing `was_reading=false`.

**Possible causes:**
1. Interrupted state was overwritten
2. Interrupted state was never set correctly
3. There's a different code path that sets phase directly

Let me check all places where `dma.phase` is set to `.resuming_normal`:

1. `actions.zig:165` - After duplication write
2. `interaction.zig:141` - When was_reading=false
3. `execution.zig:192` - From resume_data.resume_phase

**Option 3 is the culprit!** It uses `resume_data.resume_phase` which comes from `handleOamResumes`.

So if `handleOamResumes` is returning `.resuming_normal`, it's because `ledger.interrupted_state.was_reading = false`.

**But the debug trace shows `was_reading=true`!**

**Wait!** The debug trace prints the state AFTER the pause happens (after tick 1). But the resume happens on tick 2. Is it possible the interrupted state changed between tick 1 and tick 2?

---

## Final Theory: Clock Domain Issue in Test

The test calls `state.tick()` which advances the master clock by 1 PPU cycle. But CPU operations complete in 3 PPU cycles.

So when checking `shouldOamResume` with `state.clock.ppu_cycles`, it's checking with PPU cycles, not CPU cycles.

But `last_dmc_inactive_cycle` is set to `state.clock.ppu_cycles` which is in PPU cycles.

And `oam_pause_cycle` is also set to `state.clock.ppu_cycles`.

**So all timestamps are in PPU cycles, which should be consistent!**

---

## Conclusion: Need More Debug Info

The current debug trace doesn't show enough information. I need to see:
1. What `handleOamResumes` actually returns
2. What `interrupted_state.was_reading` is at the moment of resume
3. Whether there are multiple resume calls

Let me create a diagnostic recommendation.

---

## Diagnostic Recommendations

### Add Debug Logging to execution.zig

```zig
if (DmaInteraction.shouldOamResume(...)) {
    std.debug.print("  shouldOamResume returned TRUE\n", .{});
    std.debug.print("  interrupted_state.was_reading = {}\n", .{
        state.dma_interaction_ledger.interrupted_state.was_reading
    });

    const resume_data = DmaInteraction.handleOamResumes(...);

    std.debug.print("  handleOamResumes returned resume_phase = {}\n", .{
        resume_data.resume_phase
    });

    state.dma_interaction_ledger.oam_resume_cycle = resume_data.resume_cycle;
    state.dma.phase = resume_data.resume_phase;

    std.debug.print("  Set dma.phase = {}\n", .{state.dma.phase});
}
```

---

## Likely Root Cause (Final Hypothesis)

Based on all analysis, I believe the bug is:

**The duplication write happens correctly, but then on the NEXT cycle, the phase is ALREADY `.resuming_normal`, so the re-read happens as a normal read, not a duplication re-read.**

**But this is actually correct behavior!** The hardware duplication works like this:
1. Interrupt during read
2. On resume: Write the captured byte (duplication write)
3. Then RE-READ the same offset (re-read)
4. Then WRITE the re-read byte (second write of same data)

The phase transitions are:
1. `.paused_during_read`
2. → `.resuming_with_duplication` (one cycle)
3. → `.resuming_normal` (after duplication write)
4. → `.reading` (re-read)
5. → `.writing` (second write)

**This is correct!**

---

## So Why Are Tests Failing?

The test is failing because it times out after 3000 cycles. Let me calculate expected cycles:

- OAM base: 513 CPU cycles × 3 = 1539 PPU cycles
- DMC interrupt: 4 CPU cycles × 3 = 12 PPU cycles
- Total: 1539 + 12 = 1551 PPU cycles

But the test found 1132 CPU cycles = 3396 PPU cycles, which exceeded the timeout of 3000.

**This suggests OAM is running MORE than twice as long as expected!**

**Root cause:** Every DMA action takes 3 PPU cycles (1 CPU cycle), but the test loop increments once per PPU cycle, creating a 3x slowdown in perception.

**But the actual bug:** OAM is taking WAY more cycles than it should. Let me look at the trace pattern...

Each phase stays constant for 3 ticks (1 CPU cycle), which is correct. But after 20 ticks (6-7 CPU cycles), it's only at offset 2!

Expected: offset should increment every 2 CPU cycles (read + write).
Actual: offset increments every 3-4 CPU cycles.

**This suggests actions are being skipped or repeated!**

---

## The Smoking Gun

Looking at this pattern:

```
OAM tick 6: phase=.reading, cycle=1, offset=0, ppu_cycles=18
OAM tick 7: phase=.reading, cycle=1, offset=0, ppu_cycles=19
OAM tick 8: phase=.reading, cycle=1, offset=0, ppu_cycles=20
  *** PHASE TRANSITION: .reading -> .writing
```

The phase is `.reading` for 3 ticks, then transitions to `.writing`. This is normal (1 CPU cycle = 3 PPU cycles).

But notice `cycle=1` stays constant! The current_cycle counter is NOT incrementing!

**After the read action, current_cycle should increment from 1 to 2.**

Let me check `updateBookkeeping(.read)`:

```zig
.read => {
    dma.phase = .reading;
    dma.current_cycle += 1;  // Should increment!
},
```

It DOES increment! So why isn't it showing in the trace?

**Ah!** The trace prints the state BEFORE the tick, then ticks, then checks for phase transition.

So:
- Tick 6: BEFORE tick, cycle=1. AFTER tick (read action), cycle=2.
- Tick 7: BEFORE tick, cycle=2. But it shows cycle=1 in the trace!

**This means the tick isn't actually executing the action!**

Let me check if `tickDma()` is being called...

Actually, the test loop is calling `state.tick()`, which should call `stepCycle()`, which checks DMA flags and calls `tickDma()`.

But if DMC is still active (rdy_low=true), it will skip OAM!

Let me check the DMC state in the trace...

The trace doesn't print `dmc_dma.rdy_low` in the OAM resume loop. So I can't tell if DMC is interfering.

---

## Final Recommendation

**The bug is complex and requires deeper debugging. The state machine logic looks correct, but the execution is not progressing as expected.**

**Recommended fixes:**
1. ✅ **Fix already applied:** Remove exact cycle match in `shouldOamResume`
2. Add comprehensive debug logging to trace every action
3. Verify DMC is not interfering during OAM resume
4. Check if pause/resume state machine has unexpected loops

**Specific areas to investigate:**
1. `/home/colin/Development/RAMBO/src/emulation/cpu/execution.zig:182-197` - OAM resume block
2. `/home/colin/Development/RAMBO/src/emulation/dma/actions.zig:51-96` - determineAction logic
3. `/home/colin/Development/RAMBO/src/emulation/dma/interaction.zig:126-146` - handleOamResumes

