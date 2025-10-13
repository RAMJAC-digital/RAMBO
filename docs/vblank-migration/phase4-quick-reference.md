# Phase 4 Quick Reference - Test Impact

**BASELINE:** 930/966 tests passing (96.3%)
**ZERO REGRESSION TOLERANCE:** Must maintain 930/966 after Phase 4

---

## Critical Files to Update (5 files)

1. **src/test/Harness.zig** - Remove PpuRuntime, update 4 methods
2. **src/ppu/State.zig** - Add `a12_state: bool = false`
3. **src/emulation/State.zig** - Remove `ppu_a12_state`, update 4 references
4. **src/snapshot/Snapshot.zig** - Update A12 serialization (line 250)
5. **DELETE:** `src/emulation/Ppu.zig` (after Harness updated)

---

## Test Files Affected (21 files using Harness)

### CRITICAL (Run First)
- `tests/ppu/sprite_evaluation_test.zig` (19 tickPpu calls)
- `tests/ppu/vblank_nmi_timing_test.zig` (VBlank timing)
- `tests/integration/nmi_sequence_test.zig` (NMI flow)
- `tests/integration/cpu_ppu_integration_test.zig` (CPU/PPU sync)
- `tests/snapshot/snapshot_integration_test.zig` (A12 serialization)

### HIGH Priority
- `tests/ppu/vblank_behavior_test.zig`
- `tests/ppu/seek_behavior_test.zig`
- `tests/ppu/ppustatus_polling_test.zig`
- `tests/integration/bit_ppustatus_test.zig`
- `tests/integration/vblank_wait_test.zig`
- `tests/integration/smb_vblank_reproduction_test.zig`

### MEDIUM Priority
- All other PPU tests (3 files)
- Remaining integration tests (5 files)

### LOW Priority
- `tests/cpu/page_crossing_test.zig`
- `tests/integration/rom_test_runner.zig`

---

## Phase 4a: Harness Update (Facade Removal)

### Step 1: Update Harness.zig

```zig
// DELETE line 9:
const PpuRuntime = @import("../emulation/Ppu.zig");

// UPDATE tickPpu() (lines 56-61):
pub fn tickPpu(self: *Harness) void {
    self.state.tick(); // Replaces PpuRuntime.tick() call
}

// UPDATE tickPpuCycles() (lines 63-65):
pub fn tickPpuCycles(self: *Harness, cycles: usize) void {
    for (0..cycles) |_| self.state.tick();
}

// UPDATE tickPpuWithFramebuffer() (lines 67-72):
pub fn tickPpuWithFramebuffer(self: *Harness, framebuffer: []u32) void {
    self.state.framebuffer = framebuffer;
    self.state.tick();
    self.state.framebuffer = null;
}
```

### Step 2: Verify Harness
```bash
zig build test-unit  # Quick check
```

### Step 3: Run Critical Tests
```bash
zig build test 2>&1 | grep -E "ppu/|integration/"
```

### Step 4: Full Verification
```bash
zig build test  # Must show: 930/966 passing
```

---

## Phase 4b: A12 Migration

### Step 1: Add to PpuState
```zig
// src/ppu/State.zig - Add field:
pub const PpuState = struct {
    // ... existing fields ...
    a12_state: bool = false,
};
```

### Step 2: Remove from EmulationState
```zig
// src/emulation/State.zig - DELETE line 96:
ppu_a12_state: bool = false,

// UPDATE 4 references:
// Lines 196, 226: self.ppu_a12_state = false;
//         → self.ppu.a12_state = false;
// Lines 530, 534: self.ppu_a12_state
//         → self.ppu.a12_state
```

### Step 3: Update Harness resetPpu()
```zig
// src/test/Harness.zig line 100:
self.state.ppu.a12_state = false; // Was: ppu_a12_state
```

### Step 4: Update Snapshot
```zig
// src/snapshot/Snapshot.zig line 250:
// Change deserialization to use ppu.a12_state
```

### Step 5: Verify A12 Migration
```bash
grep -r "ppu_a12_state" src/  # Should return 0 matches
zig build test  # Must show: 930/966 passing
```

---

## Phase 4c: Cleanup

### Step 1: Delete PpuRuntime Facade
```bash
rm src/emulation/Ppu.zig
```

### Step 2: Verify No References
```bash
grep -r "emulation/Ppu" src/ tests/  # Should return 0
grep -r "PpuRuntime" src/ tests/      # Should return 0
```

### Step 3: Final Verification
```bash
zig build test  # Must show: 930/966 passing
```

---

## Verification Checklist

### After Each Phase:
- [ ] `zig build` compiles cleanly
- [ ] `zig build test` shows 930/966 passing
- [ ] No new test failures (compare with baseline)
- [ ] No PpuRuntime/ppu_a12_state references remain

### Before Committing:
- [ ] All 3 phases complete
- [ ] Test count verified: 930/966
- [ ] Phase 4 documentation updated
- [ ] Git diff reviewed (no unintended changes)

---

## Rollback Commands

### If Phase 4a Fails (Harness):
```bash
git checkout src/test/Harness.zig
zig build test  # Verify: 930/966
```

### If Phase 4b Fails (A12):
```bash
git checkout src/ppu/State.zig src/emulation/State.zig \
             src/test/Harness.zig src/snapshot/Snapshot.zig
zig build test  # Verify: 930/966
```

### If Phase 4c Fails (Cleanup):
```bash
git checkout src/emulation/Ppu.zig
zig build test  # Verify: 930/966
```

---

## Emergency Contacts

**If Critical Failure:**
1. Run: `zig build test 2>&1 | grep FAILED`
2. Identify failing test
3. Check test uses Harness PPU methods
4. Debug or rollback immediately

**Known Safe Fallback:**
- Baseline: 930/966 tests passing
- Known failures: 36 tests (documented in KNOWN-ISSUES.md)
- Any deviation: INVESTIGATE or ROLLBACK

---

## Success Metrics

### Phase 4a Complete:
✅ Harness updated (no PpuRuntime)
✅ 930/966 tests passing
✅ All PPU tests pass

### Phase 4b Complete:
✅ A12 in PpuState (not EmulationState)
✅ 930/966 tests passing
✅ Snapshot tests pass

### Phase 4c Complete:
✅ PpuRuntime deleted
✅ 930/966 tests passing
✅ No facade references

---

**Document Version:** 1.0
**Last Updated:** 2025-10-13
**Status:** READY FOR IMPLEMENTATION
