# VBlankLedger Single Source of Truth Migration Plan

**Date:** 2025-10-10
**Priority:** P0 (Critical - fixes Super Mario Bros and prevents future VBlank bugs)
**Goal:** Eliminate `PpuStatus.vblank` duplication, make VBlankLedger the ONLY source of VBlank flag state

## Executive Summary

**Problem:** VBlank flag exists in TWO places:
1. `PpuStatus.vblank` - Direct boolean field (BUGGY - clears immediately)
2. `VBlankLedger` timestamps - Derived state (CORRECT - handles race conditions)

**Solution:** Move readable flag logic INTO VBlankLedger, remove `PpuStatus.vblank` field entirely.

**Risk Assessment:** 🟡 MEDIUM
- Changes core PPU state structure
- Touches 4 source files + unknown number of tests
- BUT: VBlankLedger already handles all timing correctly
- Migration is mostly mechanical (replace field with function call)

## Pre-Flight Questions

### Q1: What about test compatibility?

**Answer Needed:** We have test helpers in `EmulationState`:
- `testSetVBlank()` - Currently sets BOTH `ppu.status.vblank` AND ledger
- `testClearVBlank()` - Currently clears BOTH

**Question:** Should we:
- A) Keep helpers, update to only use ledger (tests unchanged)
- B) Remove helpers, force tests to use ledger directly (more invasive)
- C) Deprecate helpers with warnings, migrate tests gradually

**Recommendation:** Option A (keep helpers, update implementation)

### Q2: What about PpuStatus.toByte()?

**Current signature:**
```zig
pub fn toByte(self: PpuStatus, data_bus: u8) u8
```

**After migration:**
```zig
// PpuStatus no longer has vblank field
// Need to pass it as parameter

pub fn toByte(self: PpuStatus, vblank_flag: bool, data_bus: u8) u8
```

**Question:** Is this breaking change acceptable?

**Answer Needed:** How many call sites exist? Can we make it backward-compatible?

### Q3: Should we migrate in stages or all at once?

**Option A: Single atomic migration**
- Change VBlankLedger API
- Remove PpuStatus.vblank
- Update all call sites
- Fix tests
- Single commit

**Option B: Phased migration**
- Phase 1: Add new VBlankLedger.isReadableFlagSet() (vblank field still exists)
- Phase 2: Update all readers to use function
- Phase 3: Remove PpuStatus.vblank field
- Multiple commits

**Question:** Which approach?

**Recommendation:** Option B (phased) - easier to find regressions

## Detailed Design

### Phase 1: Add Query Function to VBlankLedger

**File:** `src/emulation/state/VBlankLedger.zig`

**Add new function:**
```zig
/// Query if readable VBlank flag should be set
/// This is the hardware-visible flag (bit 7 of $2002)
///
/// Hardware behavior:
/// - Flag sets at scanline 241 dot 1
/// - Flag clears at scanline 261 dot 1 OR when $2002 read
/// - EXCEPTION: If $2002 read on EXACT cycle flag set, flag STAYS set (NMI suppressed)
///
/// This decouples readable flag from internal NMI edge state
pub fn isReadableFlagSet(self: *const VBlankLedger, current_cycle: u64) bool {
    // VBlank flag is NOT active if span hasn't started yet
    if (!self.span_active) return false;

    // Race condition: If $2002 read on exact cycle VBlank set,
    // flag STAYS set (but NMI is suppressed - handled by shouldNmiEdge)
    if (self.last_status_read_cycle == self.last_set_cycle) {
        // Reading on exact set cycle preserves the flag
        return true;
    }

    // Normal case: Check if flag was cleared by read
    // If last_clear_cycle > last_set_cycle, flag was cleared
    if (self.last_clear_cycle > self.last_set_cycle) {
        return false;  // Cleared by $2002 read or scanline 261.1
    }

    // Flag is active (set and not yet cleared)
    return true;
}
```

**Add tests:**
```zig
test "VBlankLedger: isReadableFlagSet returns true after VBlank set" {
    var ledger = VBlankLedger{};

    ledger.recordVBlankSet(100, false);

    try testing.expect(ledger.isReadableFlagSet(110));
}

test "VBlankLedger: isReadableFlagSet returns false after $2002 read" {
    var ledger = VBlankLedger{};

    ledger.recordVBlankSet(100, false);
    ledger.recordStatusRead(110);  // Read at cycle 110

    try testing.expect(!ledger.isReadableFlagSet(120));  // Flag cleared
}

test "VBlankLedger: isReadableFlagSet stays true if read on exact set cycle" {
    var ledger = VBlankLedger{};

    const set_cycle = 100;
    ledger.recordVBlankSet(set_cycle, false);
    ledger.recordStatusRead(set_cycle);  // Read on SAME cycle

    // CRITICAL: Flag should STAY set (race condition behavior)
    try testing.expect(ledger.isReadableFlagSet(set_cycle + 1));
}

test "VBlankLedger: isReadableFlagSet returns false after VBlank span end" {
    var ledger = VBlankLedger{};

    ledger.recordVBlankSet(100, false);
    ledger.recordVBlankSpanEnd(200);  // Scanline 261.1

    try testing.expect(!ledger.isReadableFlagSet(210));
}

test "VBlankLedger: isReadableFlagSet preserves flag on exact-cycle read (NMI still suppressed)" {
    var ledger = VBlankLedger{};

    const set_cycle = 100;
    ledger.recordVBlankSet(set_cycle, true);  // NMI enabled
    ledger.recordStatusRead(set_cycle);  // Read on exact cycle

    // Flag stays set
    try testing.expect(ledger.isReadableFlagSet(set_cycle + 1));

    // But NMI is suppressed (existing shouldNmiEdge handles this)
    try testing.expect(!ledger.shouldNmiEdge(set_cycle + 1, true));
}
```

**Verification:** Run tests to ensure new function works correctly
```bash
zig build test
```

### Phase 2: Update $2002 Read to Use Ledger

**File:** `src/ppu/logic/registers.zig`

**Current implementation:**
```zig
0x0002 => blk: {
    // $2002 PPUSTATUS - Read-only
    const value = state.status.toByte(state.open_bus.value);  // ← Uses state.status.vblank
    const vblank_before = state.status.vblank;

    // Side effects:
    state.status.vblank = false;  // ← REMOVE THIS
    state.internal.resetToggle();
    state.open_bus.write(value);

    break :blk value;
}
```

**Problem:** This function doesn't have access to VBlankLedger OR current cycle!

**Solution:** Change function signature to accept ledger and cycle:

```zig
/// Read from PPU register (via CPU memory bus)
/// Handles register mirroring and open bus behavior
pub fn readRegister(
    state: *PpuState,
    cart: ?*AnyCartridge,
    address: u16,
    vblank_ledger: *VBlankLedger,  // NEW: Access to ledger
    current_cycle: u64,            // NEW: Current PPU cycle
) u8 {
    const reg = address & 0x0007;

    return switch (reg) {
        0x0002 => blk: {
            // $2002 PPUSTATUS - Read-only

            // Query VBlank flag from ledger (single source of truth)
            const vblank_flag = vblank_ledger.isReadableFlagSet(current_cycle);

            // Build status byte with ledger-derived VBlank bit
            const status_byte: u8 = @bitCast(PpuStatus{
                .open_bus = 0,  // Overwritten below
                .sprite_overflow = state.status.sprite_overflow,
                .sprite_0_hit = state.status.sprite_0_hit,
                .vblank = vblank_flag,  // ← From ledger, not state
            });

            // Apply open bus to lower 5 bits
            const value = (status_byte & 0xE0) | (state.open_bus.value & 0x1F);

            if (DEBUG_PPUSTATUS) {
                std.debug.print("[$2002 READ] value=0x{X:0>2}, VBlank={}, sprite_0_hit={}, sprite_overflow={}\n",
                    .{value, vblank_flag, state.status.sprite_0_hit, state.status.sprite_overflow});
            }

            // Side effects:
            // 1. Record $2002 read in ledger (this updates last_status_read_cycle)
            vblank_ledger.recordStatusRead(current_cycle);

            // 2. Reset write toggle
            state.internal.resetToggle();

            // 3. Update open bus
            state.open_bus.write(value);

            break :blk value;
        },
        // ... other registers unchanged ...
    };
}
```

**Update all call sites:**

1. `src/emulation/State.zig` - busRead function
```zig
pub fn busRead(self: *EmulationState, address: u16) u8 {
    // ... existing code ...

    if (address >= 0x2000 and address <= 0x3FFF) {
        // PPU registers (mirrored every 8 bytes)
        return PpuLogic.readRegister(
            &self.ppu,
            cart_ptr,
            address,
            &self.vblank_ledger,    // NEW
            self.clock.ppu_cycles,  // NEW
        );
    }

    // ... rest unchanged ...
}
```

2. Any other direct calls to `readRegister()` (search codebase)

**Verification Steps:**
```bash
# Find all call sites
rg "readRegister\(" --type zig

# After updating, verify compilation
zig build

# Run PPU register tests
zig build test --summary all 2>&1 | grep -E "ppu.*test|register.*test"
```

### Phase 3: Update PPU Tick to Only Update Ledger

**File:** `src/emulation/Ppu.zig`

**Current implementation (lines 160-186):**
```zig
// Set VBlank flag at start of VBlank period
if (scanline == 241 and dot == 1) {
    state.status.vblank = true;  // ← REMOVE THIS
    flags.nmi_signal = true;
}

// Clear VBlank and other flags at pre-render scanline
if (scanline == 261 and dot == 1) {
    state.status.vblank = false;  // ← REMOVE THIS
    state.status.sprite_0_hit = false;
    state.status.sprite_overflow = false;
    flags.vblank_clear = true;
}
```

**New implementation:**
```zig
// VBlank start (scanline 241 dot 1)
// NOTE: VBlank flag is now managed by VBlankLedger, not state.status.vblank
// The ledger is updated in EmulationState.applyPpuCycleResult()
if (scanline == 241 and dot == 1) {
    flags.nmi_signal = true;  // Signal to update ledger

    if (DEBUG_VBLANK) {
        std.debug.print("[VBlank] SET SIGNAL at scanline={}, dot={}, nmi_enable={}\n",
            .{ scanline, dot, state.ctrl.nmi_enable });
    }
}

// VBlank end (scanline 261 dot 1)
if (scanline == 261 and dot == 1) {
    // Clear sprite flags (these are NOT managed by ledger)
    state.status.sprite_0_hit = false;
    state.status.sprite_overflow = false;

    // Signal VBlank span end (ledger will be updated in applyPpuCycleResult)
    flags.vblank_clear = true;

    if (DEBUG_VBLANK) {
        std.debug.print("[VBlank] CLEAR SIGNAL at scanline={}, dot={}\n", .{ scanline, dot });
    }
}
```

**Verification:** VBlank flag mutations now happen ONLY in VBlankLedger

### Phase 4: Remove PpuStatus.vblank Field

**File:** `src/ppu/State.zig`

**Current definition:**
```zig
pub const PpuStatus = packed struct(u8) {
    open_bus: u5 = 0,
    sprite_overflow: bool = false,
    sprite_0_hit: bool = false,
    vblank: bool = false,  // ← REMOVE THIS

    pub fn toByte(self: PpuStatus, data_bus: u8) u8 {
        // ...
    }
};
```

**New definition:**
```zig
pub const PpuStatus = packed struct(u8) {
    open_bus: u5 = 0,
    sprite_overflow: bool = false,
    sprite_0_hit: bool = false,
    _reserved: bool = false,  // Bit 7 - not stored here anymore

    /// Convert to byte representation for $2002 reads
    /// VBlank flag must be provided separately (queried from VBlankLedger)
    pub fn toByte(self: PpuStatus, vblank_flag: bool, data_bus: u8) u8 {
        var result: u8 = @bitCast(self);

        // Set VBlank bit (bit 7) from parameter
        if (vblank_flag) {
            result |= 0x80;
        } else {
            result &= 0x7F;
        }

        // Replace open bus bits (0-4) with data bus latch
        result = (result & 0xE0) | (data_bus & 0x1F);

        return result;
    }
};
```

**Alternative (cleaner):** Use separate function entirely
```zig
pub const PpuStatus = packed struct(u8) {
    open_bus: u5 = 0,
    sprite_overflow: bool = false,
    sprite_0_hit: bool = false,
    _reserved: bool = false,  // Bit 7 placeholder
};

/// Build PPUSTATUS byte for $2002 read
/// Combines sprite flags from PpuStatus with VBlank flag from VBlankLedger
pub fn buildStatusByte(
    sprite_overflow: bool,
    sprite_0_hit: bool,
    vblank_flag: bool,
    data_bus: u8
) u8 {
    var result: u8 = 0;

    // Bit 7: VBlank flag (from VBlankLedger)
    if (vblank_flag) result |= 0x80;

    // Bit 6: Sprite 0 hit
    if (sprite_0_hit) result |= 0x40;

    // Bit 5: Sprite overflow
    if (sprite_overflow) result |= 0x20;

    // Bits 0-4: Open bus (data bus latch)
    result |= (data_bus & 0x1F);

    return result;
}
```

Then update $2002 read:
```zig
0x0002 => blk: {
    const vblank_flag = vblank_ledger.isReadableFlagSet(current_cycle);
    const value = PpuLogic.buildStatusByte(
        state.status.sprite_overflow,
        state.status.sprite_0_hit,
        vblank_flag,
        state.open_bus.value,
    );

    // Side effects...
    vblank_ledger.recordStatusRead(current_cycle);
    state.internal.resetToggle();
    state.open_bus.write(value);

    break :blk value;
}
```

**Question:** Which approach for PpuStatus refactor?
- A) Modify toByte() signature (add vblank_flag parameter)
- B) Create new buildStatusByte() function (cleaner separation)

**Recommendation:** Option B (cleaner, easier to understand)

### Phase 5: Update Test Helpers

**File:** `src/emulation/State.zig`

**Current helpers:**
```zig
pub fn testSetVBlank(self: *EmulationState) void {
    self.ppu.status.vblank = true;  // ← Field no longer exists
    const nmi_enabled = self.ppu.ctrl.nmi_enable;
    self.vblank_ledger.recordVBlankSet(self.clock.ppu_cycles, nmi_enabled);
}

pub fn testClearVBlank(self: *EmulationState) void {
    self.ppu.status.vblank = false;  // ← Field no longer exists
    self.vblank_ledger.recordVBlankSpanEnd(self.clock.ppu_cycles);
}
```

**New implementation:**
```zig
/// TEST HELPER: Simulate VBlank flag set
/// Only updates VBlankLedger (readable flag is derived from ledger)
pub fn testSetVBlank(self: *EmulationState) void {
    const nmi_enabled = self.ppu.ctrl.nmi_enable;
    self.vblank_ledger.recordVBlankSet(self.clock.ppu_cycles, nmi_enabled);
}

/// TEST HELPER: Simulate VBlank flag clear
/// Only updates VBlankLedger
pub fn testClearVBlank(self: *EmulationState) void {
    self.vblank_ledger.recordVBlankSpanEnd(self.clock.ppu_cycles);
}
```

**Verification:** Test helpers now only touch ledger (no field access)

## Migration Checklist

### Pre-Migration

- [ ] Answer Q1: Test helper strategy (A/B/C)
- [ ] Answer Q2: PpuStatus.toByte refactor approach (A/B)
- [ ] Answer Q3: Phased vs atomic migration
- [ ] Create feature branch: `fix/vblank-ledger-single-source`
- [ ] Run baseline tests: `zig build test > baseline.txt 2>&1`
- [ ] Count current passing tests (should be 959/971)

### Phase 1: Add Query Function

- [ ] Add `isReadableFlagSet()` to VBlankLedger
- [ ] Add 5 test cases for new function
- [ ] Run tests: `zig build test`
- [ ] Verify no regressions (959/971 still passing)
- [ ] Commit: `feat(vblank): Add isReadableFlagSet query function`

### Phase 2: Update $2002 Read

- [ ] Add parameters to `readRegister()` signature
- [ ] Update `readRegister()` implementation to use ledger
- [ ] Find all call sites: `rg "readRegister\(" --type zig`
- [ ] Update `EmulationState.busRead()`
- [ ] Update any other call sites
- [ ] Run tests: `zig build test`
- [ ] Check for regressions
- [ ] Commit: `refactor(ppu): Use VBlankLedger for $2002 reads`

### Phase 3: Update PPU Tick

- [ ] Remove `state.status.vblank = true` from line 166
- [ ] Remove `state.status.vblank = false` from line 182
- [ ] Add debug logging for clarity
- [ ] Run tests: `zig build test`
- [ ] Check for regressions
- [ ] Commit: `refactor(ppu): Remove direct VBlank flag mutations`

### Phase 4: Remove PpuStatus.vblank Field

- [ ] Decide on refactor approach (modify toByte vs new function)
- [ ] Update `PpuStatus` struct definition
- [ ] Update `toByte()` OR create `buildStatusByte()`
- [ ] Fix compilation errors
- [ ] Run tests: `zig build test`
- [ ] Expect test failures (tests directly access field)
- [ ] Commit: `refactor(ppu): Remove PpuStatus.vblank field`

### Phase 5: Fix Tests

- [ ] Update test helpers in `EmulationState`
- [ ] Find tests accessing `status.vblank`: `rg "status\.vblank" tests/`
- [ ] Update each test to use ledger or helpers
- [ ] Run tests incrementally
- [ ] Fix any remaining failures
- [ ] Commit: `test: Update tests for VBlankLedger single source`

### Verification

- [ ] Run full test suite: `zig build test`
- [ ] Verify 959/971 tests pass (or better!)
- [ ] Test Super Mario Bros: `zig-out/bin/RAMBO "tests/data/Mario/Super Mario Bros. (World).nes"`
- [ ] Verify SMB gets past blank screen
- [ ] Verify AccuracyCoin still passes (939/939)
- [ ] Run other commercial ROMs for smoke test

### Final Steps

- [ ] Remove debug logging added during migration
- [ ] Update CLAUDE.md with resolution
- [ ] Merge feature branch to main
- [ ] Document in KNOWN-ISSUES.md as RESOLVED

## Rollback Plan

If migration fails or causes major regressions:

1. **Immediate rollback:**
   ```bash
   git checkout main
   git branch -D fix/vblank-ledger-single-source
   ```

2. **Partial rollback (keep Phase 1):**
   - Keep `isReadableFlagSet()` function
   - Revert phases 2-5
   - Use new function alongside existing field temporarily

3. **Diagnose and retry:**
   - Identify which phase introduced regression
   - Fix that phase in isolation
   - Retry migration with fix

## Success Criteria

- ✅ All 959+ tests passing
- ✅ Super Mario Bros displays title screen (not blank)
- ✅ AccuracyCoin still 939/939
- ✅ No `status.vblank` field access in src/ (except comments)
- ✅ All VBlank flag queries go through VBlankLedger
- ✅ Race condition bug is fixed

## Questions Before Proceeding

1. **Q1 (Test Helpers):** Keep helpers and update implementation? Or remove helpers?
2. **Q2 (PpuStatus.toByte):** Modify signature or create new function?
3. **Q3 (Migration Strategy):** Phased (5 commits) or atomic (1 commit)?

**Please answer these questions before I proceed with implementation.**

---

**Estimated Time:** 2-4 hours (phased approach)
**Risk Level:** 🟡 MEDIUM (well-understood change, good test coverage)
**Confidence:** 🟢 HIGH (VBlankLedger already handles all edge cases correctly)
