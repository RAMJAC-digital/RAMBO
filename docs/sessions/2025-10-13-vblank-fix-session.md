# VBlank Fix Session 2025-10-13

## Initial State (Baseline)
- Test count: 930/966 passing (96.3%)
- Known bug: CLAUDE.md line 208 documents VBlankLedger.zig:197 uses wrong variable
- Commercial ROM tests failing: SMB, DK, BurgerTime, Bomberman (don't enable rendering)

## Changes Made

### 1. VBlankLedger.zig Line 201
**File**: `src/emulation/state/VBlankLedger.zig`
**Line**: 201
**Before**: `if (self.last_status_read_cycle >= self.last_set_cycle)`
**After**: `if (self.last_clear_cycle >= self.last_set_cycle)`
**Reason**: Bug fix - was using wrong variable for flag clear detection

### 2. Updated Embedded Test 1
**File**: `src/emulation/state/VBlankLedger.zig`
**Lines**: 391-404
**Test name changed**:
- Before: "isReadableFlagSet stays true if read on exact set cycle"
- After: "Race condition read clears flag immediately"
**Behavior changed**:
- Before: Expected flag to remain set after race condition read
- After: Expected flag to clear immediately after race condition read

### 3. Updated Embedded Test 2
**File**: `src/emulation/state/VBlankLedger.zig`
**Lines**: 420-434
**Test name changed**:
- Before: "isReadableFlagSet race condition does not affect NMI suppression"
- After: "Race condition clears flag but suppresses NMI"
**Behavior changed**:
- Before: Expected flag stays set, NMI suppressed
- After: Expected flag clears, NMI suppressed

## Justification for Changes

### NESdev.org Research
**Query**: "NES PPU VBlank flag race condition $2002 read exact cycle nesdev.org 2024"
**Source**: https://www.nesdev.org/wiki/PPU_frame_timing
**Quote**: "Reading on the same PPU clock or one later reads it as set, clears it, and suppresses the NMI for that frame."

**Interpretation**: Race condition read sees flag SET, clears it immediately, suppresses NMI

## Test Results After Changes

### Embedded VBlankLedger Tests
**Command**: `zig test src/emulation/state/VBlankLedger.zig`
**Result**: 16/16 passing

### Full Test Suite
**Command**: `zig build test --summary all`
**Output saved to**: `/tmp/test-results-after-fix.txt`

**Still failing tests**:
- `vblank_ledger_test.zig`: "Race condition - read on exact set cycle keeps flag set"
- `vblank_ledger_test.zig`: "Read at cycle 0 (race condition)"
- `bit_ppustatus_test.zig`: 2 tests
- `cpu_ppu_integration_test.zig`: 2 tests
- `ppustatus_polling_test.zig`: 2 tests
- `commercial_rom_test.zig`: SMB, DK, BurgerTime (same as baseline)

## Files Modified
1. `src/emulation/state/VBlankLedger.zig` (line 201 + 2 test updates)

## Files Not Modified (but have failing tests)
1. `tests/emulation/state/vblank_ledger_test.zig` - has tests expecting different behavior
2. `tests/integration/bit_ppustatus_test.zig`
3. `tests/integration/cpu_ppu_integration_test.zig`
4. `tests/integration/ppustatus_polling_test.zig`
5. `tests/integration/commercial_rom_test.zig`

## Current Status
- Embedded VBlankLedger tests: ✅ 16/16 passing
- Integration tests: ❌ Multiple still failing
- Commercial ROMs: ❌ Still don't enable rendering (same as baseline)

## Outstanding Questions
1. Are the failing integration tests expecting wrong behavior?
2. Is the NESdev interpretation correct?
3. Why don't commercial ROMs enable rendering?
4. Is SMB rendering issue related to VBlank bug or separate issue?

## Artifacts
- Baseline test results: `/tmp/rambo-test-baseline.txt`
- Post-fix test results: `/tmp/test-results-after-fix.txt`
- Session notes: `/tmp/vblank-fix-session-2025-10-13.md`
- Analysis: `/tmp/sat-solver-analysis.md`
- NMI edge analysis: `/tmp/nmi-edge-analysis.md`
- Methodical analysis: `/tmp/methodical-analysis.md`
