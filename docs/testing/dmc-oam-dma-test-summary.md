# DMC/OAM DMA Test Strategy - Quick Reference

**Full Document:** `docs/testing/dmc-oam-dma-test-strategy.md`
**Date:** 2025-10-15

---

## Test Suite Overview

**Total Tests:** 33+
- **Unit Tests:** 15 (simple, isolated cases)
- **Integration Tests:** 10 (complex, multi-system scenarios)
- **Timing Tests:** 8 (cycle-accurate verification)

**Expected Runtime:** < 100ms
**Testing Approach:** Test-Driven Development (write tests before implementation)

---

## Test Categories Summary

### Unit Tests (15 tests)

**DMC DMA Alone (3 tests):**
- Basic fetch completes in 4 CPU cycles ✓
- Sample byte correctly fetched ✓
- CPU stalled during fetch ✓

**OAM DMA Alone (3 tests):**
- Basic transfer (already exists in `oam_dma_test.zig`)
- Even cycle timing (already exists)
- Odd cycle timing (already exists)

**DMC Interrupts OAM (9 tests):**
- Interrupt at start (byte 0)
- Interrupt mid-transfer (byte 128)
- Interrupt at end (byte 255)
- Interrupt during read cycle
- Interrupt during write cycle
- Interrupt during alignment cycle
- Byte duplication verification
- Offset advances correctly
- Pause flag sets/clears correctly

### Integration Tests (10 tests)

**Multiple DMC Interruptions (4 tests):**
- Multiple interrupts during single OAM
- Consecutive DMC interrupts (no gap)
- Interrupt during OAM resume
- Maximum interruptions (stress test)

**Back-to-Back OAM DMAs (3 tests):**
- Sequential OAM with DMC between
- Immediate second OAM after first
- DMC interrupts both OAMs

**Edge Cases (3 tests):**
- DMC when OAM already complete
- OAM triggered while DMC active
- All bytes identical (off-by-one detection)

### Timing Tests (8 tests)

**Cycle Count (4 tests):**
- 1 DMC interrupt adds 4 cycles (513 → 517)
- 3 DMC interrupts add 12 cycles (513 → 525)
- Odd-start + DMC (514 + 4 = 518)
- DMC during alignment doesn't affect total

**CPU Stall (2 tests):**
- CPU doesn't execute during DMA
- CPU resumes after DMAs complete

**Priority (2 tests):**
- DMC always preempts OAM
- Multiple DMCs execute in order

---

## Key Test Helpers

```zig
// Fill RAM page with pattern
fn fillRamPage(state: *EmulationState, page: u8, pattern: u8) void

// Run until OAM DMA completes
fn runUntilOamDmaComplete(state: *EmulationState) void

// Run until DMC DMA completes
fn runUntilDmcDmaComplete(state: *EmulationState) void

// Verify OAM contents
fn verifyOamPattern(state: *EmulationState, expected: []const u8) !void

// Count cycles until complete
fn countPpuCyclesUntilComplete(state: *EmulationState, max_cycles: u64) u64
```

---

## Test Patterns Used

**Sequential (0x00, 0x01, 0x02, ...):**
- Detects byte skipping and offset errors

**Repeating (0xAA, 0xAA, ...):**
- Masks duplication, tests off-by-one

**Alternating (0xAA, 0x55, ...):**
- Detects byte swapping

**Arithmetic (i * 3 % 256):**
- Unique values detect any duplication

---

## Expected Outcomes

### Before Implementation
- **Pass:** 3 tests (DMC alone)
- **Fail:** 30 tests (all DMC/OAM interactions)
- **Reason:** DMC cannot interrupt OAM yet

### After Implementation
- **Pass:** 33+ tests (all)
- **Fail:** 0 tests
- **Performance:** < 100ms

---

## Hardware Behavior Reference

**DMA Priority (Highest to Lowest):**
1. DMC DMA (4 CPU cycles per fetch)
2. OAM DMA (513/514 CPU cycles)
3. CPU execution

**Conflict Behavior:**
- OAM **pauses** when DMC interrupts (does not cancel)
- OAM **resumes** after DMC completes
- Byte being read during interrupt **duplicates** on resume

**Timing:**
- Total cycles = OAM base (513 or 514) + (DMC count × 4)

---

## Quick Start Commands

```bash
# Create test file
touch tests/integration/dmc_oam_conflict_test.zig

# Run tests (expect failures before implementation)
zig build test

# Run only this test suite
zig test tests/integration/dmc_oam_conflict_test.zig \
  --deps zli,libxev,zig-wayland -I src

# Run with verbose output
zig test tests/integration/dmc_oam_conflict_test.zig \
  --deps zli,libxev,zig-wayland -I src --summary all
```

---

## Implementation Checklist

### Phase 1: Test Infrastructure (30 min)
- [ ] Create `tests/integration/dmc_oam_conflict_test.zig`
- [ ] Add to `build/tests.zig` registry
- [ ] Implement helper functions
- [ ] Verify compilation

### Phase 2: Write Tests (2.5 hours)
- [ ] 3 DMC-alone tests (baseline)
- [ ] 9 DMC-interrupts-OAM tests
- [ ] 10 integration tests
- [ ] 8 timing tests

### Phase 3: Validation (30 min)
- [ ] Run suite (document baseline failures)
- [ ] Verify no flaky tests (run 3x)
- [ ] Commit test suite
- [ ] Proceed to implementation

---

## Success Criteria

### Must Have
✅ 33+ tests compiling and running
✅ Arrange-Act-Assert pattern throughout
✅ Deterministic (no randomness)
✅ Fast (< 100ms total)
✅ Clear test names

### Should Have
✅ Comprehensive edge case coverage
✅ Cycle-accurate timing verification
✅ Helper functions reduce duplication
✅ Comments explain hardware behavior

---

## Common Failure Modes

**Timeout:**
- DMA state stuck in active
- Debug: Print state each tick

**Wrong Byte Count:**
- Offset not advancing during pause
- Debug: Print offset before/after DMC

**No Duplication:**
- Pause logic missing
- Debug: Verify paused flag

**Cycle Mismatch:**
- DMC cycles not counted
- Debug: Print elapsed_cpu at milestones

---

## Reference Files

**Existing Tests:**
- `tests/integration/oam_dma_test.zig` - 14 OAM tests
- `tests/integration/dpcm_dma_test.zig` - 3 DMC tests

**Implementation:**
- `src/emulation/dma/logic.zig` - DMA tick functions
- `src/emulation/state/peripherals/OamDma.zig` - OAM state
- `src/emulation/state/peripherals/DmcDma.zig` - DMC state

**Documentation:**
- `docs/sessions/2025-10-15-phase2e-dmc-oam-dma-plan.md` - Implementation plan
- `docs/testing/dmc-oam-dma-test-strategy.md` - Full test strategy

**Hardware Reference:**
- https://www.nesdev.org/wiki/APU_DMC
- https://www.nesdev.org/wiki/PPU_registers#OAMDMA
- https://www.nesdev.org/wiki/DMA

---

## Timeline Estimate

**Test Creation:** 3.25 hours
**Implementation:** 2-3 hours
**Debugging:** 2-3 hours
**Total:** 7-9 hours

---

## Next Steps

1. Read full strategy: `docs/testing/dmc-oam-dma-test-strategy.md`
2. Create test file: `tests/integration/dmc_oam_conflict_test.zig`
3. Write all 33+ tests (expect failures)
4. Commit test suite
5. Proceed to implementation phase
6. Run tests to verify implementation
7. Debug until all pass
8. Test with commercial ROMs

**Status:** Ready to begin test creation 🚀
