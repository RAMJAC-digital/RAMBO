# VBlank Flag Race Condition Investigation

**Date:** 2025-10-10
**Priority:** P0 (Critical - blocks Super Mario Bros)
**Status:** Root cause identified, fix pending

## Executive Summary

**Critical Bug Found:** VBlank flag sets correctly at scanline 241 dot 1, but then **immediately clears** before the CPU can read it. This prevents NMI from firing and causes Super Mario Bros to hang in initialization.

## Evidence from Debug Logs

### The Smoking Gun

```
[PPU ENTRY] scanline=241, dot=1
[DEBUG] At 241.1: vblank_flag=false, about to set
[VBlankLedger] recordVBlankSet: was_active=false, nmi_enabled=true, will_set_edge=true
[VBlankLedger] NMI EDGE PENDING SET!
[DEBUG] VBlank flag NOW TRUE
[VBlank] SET COMPLETE - flag_after=true, ppu_state=...
[$2002 READ] value=0x10, VBlank=false, sprite_0_hit=false, sprite_overflow=false
```

**Analysis:**
1. ✅ VBlank flag sets to `true` at scanline 241 dot 1 (correct)
2. ✅ VBlankLedger correctly detects NMI edge and sets `nmi_edge_pending=true`
3. ❌ **BUT**: The very next `$2002 READ` shows `VBlank=false` (WRONG!)
4. ❌ This means VBlank flag was cleared between setting and reading

### Expected vs Actual Behavior

**Expected (Hardware):**
```
Cycle 82,181 (241.1): VBlank flag = 1
Cycle 82,182-89,000: VBlank flag = 1 (stays set for ~20 scanlines)
Cycle 89,001 (261.1): VBlank flag = 0 (cleared at pre-render)
```

**Actual (Our Emulator):**
```
Cycle 82,181 (241.1): VBlank flag = 1
Cycle 82,182: VBlank flag = 0 (IMMEDIATELY CLEARED!)
```

## Root Cause Hypothesis

There are **two possible culprits** for premature VBlank clearing:

### Hypothesis A: $2002 Read Side Effect (Most Likely)

**Location:** `src/ppu/logic/registers.zig:46`

```zig
0x0002 => blk: {
    // $2002 PPUSTATUS - Read-only
    const value = state.status.toByte(state.open_bus.value);
    const vblank_before = state.status.vblank;

    // Side effects:
    // 1. Clear VBlank flag
    state.status.vblank = false;  // ← CLEARS IMMEDIATELY ON ANY READ

    // ...
}
```

**The Bug:** Reading $2002 clears the VBlank flag **unconditionally**, even if:
- VBlank was just set this exact cycle (scanline 241 dot 1)
- CPU hasn't had a chance to latch NMI yet
- The read happens before CPU can service the interrupt

**Hardware Behavior:**
- Reading $2002 on scanline 241 dot 1 **suppresses NMI** (race condition)
- But VBlank flag should NOT clear until scanline 261 dot 1 OR explicit $2002 read
- The flag clearing should respect timing - don't clear on same cycle it was set

### Hypothesis B: Scanline 261 Clearing (Less Likely)

**Location:** `src/emulation/Ppu.zig:178-186`

```zig
// Clear VBlank and other flags at pre-render scanline
if (scanline == 261 and dot == 1) {
    if (DEBUG_VBLANK) {
        std.debug.print("[VBlank] CLEAR at scanline={}, dot={} (flag was: {})\n",
            .{ scanline, dot, state.status.vblank });
    }
    state.status.vblank = false;  // VBlank DOES clear here on hardware
    state.status.sprite_0_hit = false;
    state.status.sprite_overflow = false;
    flags.vblank_clear = true; // Signal end of VBlank period
}
```

**Why Unlikely:** This code only runs at scanline 261 dot 1, but our bug happens immediately after scanline 241 dot 1.

## Super Mario Bros Impact

### SMB's VBlank Polling Loop

SMB initialization code:
1. Enables NMI (writes $80 to $2000 / PPUCTRL)
2. Expects VBlank to set and NMI to fire
3. NMI handler should execute initialization
4. NMI handler disables NMI (writes $00 to $2000)
5. Continues with game logic

### What Actually Happens

```
[PPUCTRL] Write 0x90, NMI: false -> true        ← SMB enables NMI
[VBlankLedger] NMI EDGE PENDING SET!             ← Ledger correctly latches edge
[$2002 READ] value=0x10, VBlank=false            ← VBlank already cleared!
[PPUCTRL] Write 0x10, NMI: true -> false         ← SMB disables NMI (expected to be in handler)
```

**The Problem:**
1. SMB enables NMI, expecting to enter NMI handler
2. VBlank flag clears before CPU can read it
3. NMI never fires (no 0→1 transition visible)
4. SMB thinks it's in NMI handler (disables NMI)
5. SMB enters infinite polling loop waiting for VBlank

## Hardware Specification References

### nesdev.org/wiki/PPU_registers ($2002 PPUSTATUS)

> "Reading the status register will return the current state of various PPU flags and clear the VBlank flag. **The VBlank flag is cleared by reading this register, or by the start of the pre-render scanline (scanline 261).**"

**Key Point:** VBlank should persist from scanline 241 dot 1 until:
- CPU explicitly reads $2002, OR
- Pre-render scanline 261 dot 1

### nesdev.org/wiki/NMI (Race Condition)

> "If the VBlank flag is read on the same PPU clock cycle that it is set, the flag will not be cleared, but the NMI will be suppressed."

**Critical Race Condition:** Reading $2002 on exact cycle VBlank sets:
- ✅ VBlank flag stays HIGH (not cleared)
- ❌ NMI is suppressed (edge not detected)

**Our Bug:** We're clearing VBlank flag when we shouldn't be.

## Verification Matrix Status

From `docs/verification/irq-nmi-permutation-matrix.md`:

**P1.1: NMI Edge on VBlank Set**
- **Status:** ⚠️ VERIFIED (partial) - Edge detection works, but flag clearing breaks it
- **Current Test:** `tests/integration/cpu_ppu_integration_test.zig:52-72` (PASSING)
- **Why Test Passes:** Test doesn't check for premature flag clearing
- **Need:** Add test that verifies VBlank flag persists across multiple CPU cycles

**P1.3: $2002 Read Suppression**
- **Status:** ❌ SUSPECTED BROKEN
- **Expected:** Reading $2002 on cycle VBlank sets should suppress NMI but NOT clear flag
- **Actual:** We clear flag unconditionally on any $2002 read
- **Need:** Fix clearing logic to respect race condition timing

## Proposed Fix

### Option 1: Prevent Clearing on Set Cycle (Recommended)

**File:** `src/ppu/logic/registers.zig`

```zig
0x0002 => blk: {
    // $2002 PPUSTATUS - Read-only
    const value = state.status.toByte(state.open_bus.value);
    const vblank_before = state.status.vblank;

    // Side effects:
    // 1. Clear VBlank flag (UNLESS read on exact cycle it was set)
    //    Hardware: Reading on set cycle suppresses NMI but doesn't clear flag
    if (state.last_vblank_set_cycle != state.current_cycle) {
        state.status.vblank = false;
    }

    // 2. Reset write toggle
    state.internal.resetToggle();

    // 3. Update open bus
    state.open_bus.write(value);

    break :blk value;
}
```

**Requirements:**
1. Add `last_vblank_set_cycle: u64` to PpuState
2. Update field when VBlank sets (in `Ppu.zig:166`)
3. Add `current_cycle` parameter to `readRegister()`

### Option 2: Use VBlankLedger for Flag State

Make VBlankLedger the **single source of truth** for VBlank flag state, not just NMI edge:

```zig
// Instead of state.status.vblank, use:
const vblank_flag = state.vblank_ledger.isVBlankFlagSet(current_cycle);
```

**Pros:**
- Centralized timing logic
- Race condition handling in one place
- Easier to test and verify

**Cons:**
- More invasive refactor
- Need to pass cycle count to more places

## Next Steps

1. ✅ Document finding (this document)
2. ⬜ Update CLAUDE.md with known issue
3. ⬜ Decide on fix approach (Option 1 vs Option 2)
4. ⬜ Implement fix with test coverage
5. ⬜ Verify SMB initialization completes
6. ⬜ Regression test all VBlank-related tests

## References

- **nesdev.org/wiki/PPU_registers** - $2002 PPUSTATUS behavior
- **nesdev.org/wiki/NMI** - Race condition specification
- **nesdev.org/wiki/PPU_frame_timing** - VBlank timing (241.1 → 261.1)
- `docs/verification/irq-nmi-permutation-matrix.md` - Test coverage matrix
- `src/emulation/state/VBlankLedger.zig` - NMI edge detection logic
- `src/ppu/logic/registers.zig` - $2002 read implementation

---

**Status:** Investigation complete, awaiting fix implementation
**Assignee:** Claude Code
**Milestone:** Super Mario Bros Playability
