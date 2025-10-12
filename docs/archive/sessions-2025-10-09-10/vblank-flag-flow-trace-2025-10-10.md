# VBlank Flag Flow Trace - Complete Analysis

**Date:** 2025-10-10
**Based on:** GraphViz Documentation (`docs/dot/*`)
**Finding:** VBlank flag has TWO separate states causing race condition

## Architecture Overview (from emulation-coordination.dot)

### Two Separate VBlank States

**CRITICAL DISCOVERY:** There are TWO independent VBlank flag states in the system:

1. **PpuStatus.vblank** (Readable via $2002)
   - Location: `src/ppu/State.zig` → `PpuStatus.vblank: bool`
   - Set at: scanline 241 dot 1
   - Cleared at: scanline 261 dot 1 OR $2002 read
   - **Problem:** Clears immediately on ANY $2002 read

2. **VBlankLedger State** (Internal NMI tracking)
   - Location: `src/emulation/state/VBlankLedger.zig`
   - Fields:
     - `span_active: bool` - VBlank period active (241.1 → 261.1)
     - `nmi_edge_pending: bool` - Latched NMI edge (persists until CPU acknowledges)
   - **Correctly handles:** NMI edge detection and persistence

## Complete Flow Trace (Scanline 241 Dot 1)

### Step 1: PPU Tick (src/emulation/Ppu.zig:160-175)

**Source:** `ppu-module-structure.dot:167`
```
runtime_tick [label="tick(state, scanline, dot, cart, fb) TickFlags\n
// SIDE EFFECTS:\n
// - Sets/clears VBlank flag", fillcolor=lightcoral]
```

**Implementation:** `src/emulation/Ppu.zig:160-175`
```zig
if (scanline == 241 and dot == 1) {
    state.status.vblank = true;  // ← Sets PpuStatus.vblank
    flags.nmi_signal = true;      // ← Signals NMI event
}
```

**Result:**
- ✅ `PpuStatus.vblank = true`
- ✅ `TickFlags.nmi_signal = true`

### Step 2: VBlank Ledger Recording (src/emulation/State.zig)

**Source:** `emulation-coordination.dot:121`
```
vblank_record_set [label="recordVBlankSet(cycle, nmi_enabled)\n
// Sets span_active = true\n
// Latch NMI edge if !was_active && nmi_enabled"]
```

**Implementation:** `src/emulation/state/VBlankLedger.zig:57-71`
```zig
pub fn recordVBlankSet(self: *VBlankLedger, cycle: u64, nmi_enabled: bool) void {
    const was_active = self.span_active;
    self.span_active = true;
    self.last_set_cycle = cycle;

    // Detect NMI edge: 0→1 transition of (VBlank span AND NMI_enable)
    if (!was_active and nmi_enabled) {
        self.nmi_edge_pending = true;  // ← Correctly latches NMI edge
    }
}
```

**Result:**
- ✅ `VBlankLedger.span_active = true`
- ✅ `VBlankLedger.nmi_edge_pending = true` (if NMI enabled)
- ✅ `VBlankLedger.last_set_cycle = 82181` (current cycle)

### Step 3: CPU Reads $2002 (Next Frame)

**Source:** `ppu-module-structure.dot:249`
```
reg_read -> ppu_status [label="$2002 clears VBlank", color=blue]
```

**Source:** `ppu-timing.dot:110`
```
read_action [label="Read Side Effect:\n
status.vblank = false\n           ← UNCONDITIONAL CLEAR
internal.resetToggle()\n
NMI latch persists!"]                ← But this doesn't help!
```

**Implementation:** `src/ppu/logic/registers.zig:33-54`
```zig
0x0002 => blk: {
    // $2002 PPUSTATUS - Read-only
    const value = state.status.toByte(state.open_bus.value);

    // Side effects:
    // 1. Clear VBlank flag
    state.status.vblank = false;  // ← CLEARS IMMEDIATELY!
                                   //   Even if just set this cycle!

    // 2. Reset write toggle
    state.internal.resetToggle();

    // 3. Update open bus
    state.open_bus.write(value);

    break :blk value;
}
```

**Result:**
- ❌ `PpuStatus.vblank = false` (cleared immediately)
- ✅ `VBlankLedger.nmi_edge_pending` still true (correct)
- ❌ Visible flag is now wrong!

### Step 4: CPU Queries NMI Line

**Source:** `emulation-coordination.dot:131`
```
vblank_should_assert [label="shouldAssertNmiLine(cycle, nmi_en, vb_flag) bool\n
// Combines edge (latched) + level (active) logic\n
// Single source of truth for CPU NMI input"]
```

**Implementation:** `src/emulation/state/VBlankLedger.zig:165-174`
```zig
pub fn shouldAssertNmiLine(
    self: *const VBlankLedger,
    cycle: u64,
    nmi_enabled: bool,
    vblank_flag: bool,  // ← THIS IS PpuStatus.vblank (BROKEN!)
) bool {
    _ = vblank_flag; // Unused after edge detection

    // NMI line is asserted ONLY when edge is pending
    return self.shouldNmiEdge(cycle, nmi_enabled);
}
```

**Good News:** VBlankLedger ignores `vblank_flag` parameter!
**Bad News:** But PpuStatus.vblank is still wrong for games that poll $2002

## The Two Bugs

### Bug #1: PpuStatus.vblank Clears Too Early

**Location:** `src/ppu/logic/registers.zig:46`

**Problem:** Reading $2002 clears VBlank flag unconditionally, even if:
- VBlank was set on the same cycle (race condition)
- Game polls $2002 immediately after VBlank sets
- Flag should persist until 261.1 or explicit clear

**Hardware Spec (nesdev.org):**
> "Reading $2002 on the exact cycle VBlank sets should suppress NMI but NOT clear the flag"

**Current Implementation:** Clears flag regardless of timing

### Bug #2: Missing Race Condition Protection

**Source:** `ppu-timing.dot:106-111`
```
read_timing [label="$2002 Read\n(Any Time)"]
read_action [label="Read Side Effect:\n
status.vblank = false\n             ← Should NOT clear on same cycle
internal.resetToggle()\n
NMI latch persists!"]
```

**Expected Behavior:**
```zig
// Reading $2002 on exact cycle VBlank sets (241.1):
// - NMI is suppressed (handled by VBlankLedger)
// - VBlank flag should STAY SET (not cleared)
// - Flag only clears on LATER reads or 261.1
```

**Current Behavior:**
```zig
// Reading $2002 ANY TIME:
// - VBlank flag clears immediately (WRONG!)
// - No cycle comparison
// - No race condition protection
```

## Super Mario Bros Impact

### SMB's VBlank Polling Loop

From `ppu-timing.dot:128-140`:
```
wait_code [label="Assembly Code:\n
:vblankwait1\n
  BIT $2002\n           ← Reads $2002, clears VBlank flag
  BPL vblankwait1"]

wait_expected [label="Expected Timing:\n
Loop until scanline 241.1\n
VBlank sets, N=1, exit loop"]

wait_actual [label="CURRENT BUG:\n
Loop never exits\n
Scans only reach 0-17\n      ← This was old bug, now fixed
VBlank never arrives!"]      ← This part is NEW
```

**Updated Analysis:**
1. SMB enables NMI (PPUCTRL=$90)
2. VBlank sets at 241.1 → `status.vblank = true`
3. VBlankLedger correctly latches edge: `nmi_edge_pending = true`
4. **BUT** SMB polls $2002 (BIT instruction)
5. $2002 read clears `status.vblank = false` IMMEDIATELY
6. SMB reads $2002 again, sees VBlank=0
7. SMB thinks VBlank ended, never enters handler
8. Infinite loop

## Hardware Specification References

### nesdev.org/wiki/PPU_registers ($2002 PPUSTATUS)

> "Reading the status register will return the current state of various PPU flags and **clear the VBlank flag**. The VBlank flag is set during VBlank and **cleared by reading this register or by the start of the pre-render scanline**."

**Key Point:** Flag should persist BETWEEN the set (241.1) and first read

### nesdev.org/wiki/NMI (Race Condition)

> "If the VBlank flag is read on the **same PPU clock cycle** that it is set, the **flag will not be cleared**, but the **NMI will be suppressed**."

**Critical Behavior:**
- Read on EXACT cycle VBlank sets → Flag STAYS SET, NMI suppressed
- Read on ANY other cycle during VBlank → Flag CLEARED, NMI already fired

## GraphViz Documentation Confirms Architecture

### emulation-coordination.dot Line 119

```zig
vblank_ledger_state [label="VBlankLedger:
// ...
Decouples NMI latch from readable VBlank flag
Records events with master clock timestamps"]
```

**Confirms:** VBlankLedger and PpuStatus.vblank are SEPARATE

### ppu-module-structure.dot Line 248

```
runtime_tick -> ppu_status [label="set VBlank @ 241.1\nclear @ 261.1", color=red]
reg_read -> ppu_status [label="$2002 clears VBlank", color=blue]
```

**Confirms:** Two separate code paths modify PpuStatus.vblank:
1. PPU tick sets/clears at scanline boundaries
2. $2002 read clears immediately

## The Fix

### Required Changes

**File:** `src/ppu/State.zig`
Add field to track VBlank set timing:
```zig
pub const PpuStatus = struct {
    vblank: bool = false,
    sprite_0_hit: bool = false,
    sprite_overflow: bool = false,

    // NEW: Track when VBlank was last set
    vblank_set_cycle: ?u64 = null,  // PPU cycle when VBlank set

    // ...
};
```

**File:** `src/emulation/Ppu.zig:160-175`
Update VBlank set to record cycle:
```zig
if (scanline == 241 and dot == 1) {
    state.status.vblank = true;
    state.status.vblank_set_cycle = current_ppu_cycle;  // NEW
    flags.nmi_signal = true;
}
```

**File:** `src/ppu/logic/registers.zig:33-54`
Add race condition protection:
```zig
0x0002 => blk: {
    const value = state.status.toByte(state.open_bus.value);

    // NEW: Check if read on exact cycle VBlank was set
    const read_on_set_cycle = if (state.status.vblank_set_cycle) |set_cycle|
        (current_ppu_cycle == set_cycle)
    else
        false;

    // Side effects:
    // 1. Clear VBlank flag (UNLESS read on exact set cycle)
    if (!read_on_set_cycle) {
        state.status.vblank = false;
    }

    // 2. Reset write toggle
    state.internal.resetToggle();

    // 3. Update open bus
    state.open_bus.write(value);

    break :blk value;
}
```

**File:** `src/emulation/Ppu.zig:178-186`
Clear vblank_set_cycle at scanline 261:
```zig
if (scanline == 261 and dot == 1) {
    state.status.vblank = false;
    state.status.vblank_set_cycle = null;  // NEW: Clear tracking
    state.status.sprite_0_hit = false;
    state.status.sprite_overflow = false;
    flags.vblank_clear = true;
}
```

### Alternative: Use VBlankLedger as Single Source

**More invasive but cleaner:**

Make VBlankLedger track BOTH internal NMI state AND readable flag state:

```zig
pub const VBlankLedger = struct {
    span_active: bool = false,
    nmi_edge_pending: bool = false,

    // NEW: Track readable flag separately
    readable_flag_active: bool = false,

    // ...

    pub fn isReadableFlagSet(self: *const VBlankLedger, cycle: u64) bool {
        // VBlank flag is visible from 241.1 until:
        // - Pre-render (261.1), OR
        // - $2002 read (unless read on exact set cycle)

        if (!self.span_active) return false;

        // Check race condition: if last read was on exact set cycle, flag stays set
        if (self.last_status_read_cycle == self.last_set_cycle) {
            return true;  // Flag stays set despite read
        }

        // Otherwise, check if cleared by read
        if (self.last_status_read_cycle > self.last_set_cycle) {
            return false;  // Cleared by read
        }

        return true;  // Still active
    }
};
```

Then update `src/ppu/State.zig` to query ledger instead of maintaining separate state.

## Next Steps

1. ✅ Document flow (this document)
2. ⬜ Decide on fix approach (Option 1: Add cycle tracking, Option 2: VBlankLedger single source)
3. ⬜ Implement fix with test coverage
4. ⬜ Verify SMB initialization completes
5. ⬜ Verify no regressions in existing tests

## References

- `docs/dot/emulation-coordination.dot` - Complete system integration
- `docs/dot/ppu-module-structure.dot` - PPU architecture
- `docs/dot/ppu-timing.dot` - VBlank timing specification
- `docs/dot/AUDIT-emulation-coordination.md` - Architecture audit
- `src/emulation/state/VBlankLedger.zig` - NMI edge detection
- `src/ppu/logic/registers.zig` - $2002 PPUSTATUS read
- `src/emulation/Ppu.zig` - PPU tick orchestration

---

**Conclusion:** The architecture correctly separates NMI edge detection (VBlankLedger) from readable flag state (PpuStatus.vblank). However, the readable flag clears too aggressively, breaking games that poll $2002. The fix requires adding cycle-aware clearing logic to match hardware behavior.
