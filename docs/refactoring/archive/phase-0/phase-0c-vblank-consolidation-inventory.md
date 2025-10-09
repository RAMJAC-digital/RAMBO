# Phase 0-C: VBlank Test Consolidation Inventory

**Date:** 2025-10-09
**Purpose:** Methodical inventory of VBlank tests before consolidation
**Process:** Test-first refactoring - analyze before acting

---

## Current Test Files (7 VBlank-related)

| File | Tests | Uses Harness | Status | Action |
|------|-------|--------------|--------|--------|
| `vblank_nmi_timing_test.zig` | 6 | ✅ Yes | Good | **KEEP** |
| `ppustatus_polling_test.zig` | 7 | ✅ Yes | Good (2 failing - known) | **KEEP** |
| `vblank_minimal_test.zig` | 4 | ❌ No | Redundant | CONSOLIDATE |
| `vblank_tracking_test.zig` | 1 | ❌ No | Redundant | CONSOLIDATE |
| `vblank_persistence_test.zig` | 2 | ❌ No | Redundant | CONSOLIDATE |
| `vblank_polling_simple_test.zig` | 2 | ❌ No | Redundant | CONSOLIDATE |
| `ppustatus_read_test.zig` | 8 | ✅ Yes | Redundant | CONSOLIDATE |

**Total:** 30 tests across 7 files

---

## Files to KEEP (2 files, 13 tests)

### 1. `tests/ppu/vblank_nmi_timing_test.zig` (6 tests)
**Why Keep:** Comprehensive NMI timing validation with Harness
- "NMI timing: VBlank flag set at scanline 241 dot 1"
- "NMI timing: VBlank flag clear at scanline 261 dot 1"
- "NMI timing: VBlank survives one scanline without read"
- "NMI timing: Multiple frames preserve timing"
- "NMI timing: Exact scanline.dot validation"
- "NMI timing: Pre-render scanline behavior"

**Coverage:** NMI timing, frame boundaries, cycle-accurate validation

### 2. `tests/ppu/ppustatus_polling_test.zig` (7 tests, 2 failing - documented)
**Why Keep:** PPUSTATUS register behavior, includes failing tests for VBlank $2002 bug
- "PPUSTATUS Polling: VBlank flag returns in bit 7"
- "PPUSTATUS Polling: VBlank flag cleared after read"
- "PPUSTATUS Polling: Multiple polls within VBlank period" ❌ FAILING (known issue P1)
- "PPUSTATUS Polling: Polling before VBlank returns 0"
- "PPUSTATUS Polling: VBlank clear at scanline 261.1"
- "PPUSTATUS Polling: Poll continuously through VBlank"
- "PPUSTATUS Polling: BIT instruction timing - when does read occur?" ❌ FAILING (known issue P1)

**Coverage:** $2002 register behavior, VBlank flag clearing, polling patterns, BIT instruction timing

---

## Files to CONSOLIDATE (5 files, 17 tests)

### Group A: Basic VBlank Behavior (consolidate into new file)

#### `vblank_minimal_test.zig` (4 tests) - NO Harness
1. "VBlank Minimal: Set and check immediately"
   - Direct flag manipulation
   - Coverage: Basic flag read/write

2. "VBlank Minimal: Track through one frame"
   - Advance to 241.0, tick to 241.1, check flag
   - Coverage: VBlank set timing at 241.1

3. "VBlank Minimal: busRead($2002) returns bit 7 when VBlank set"
   - Manual clock set to 241.0, tick, read $2002
   - Coverage: $2002 bit 7 when VBlank is set, flag clears after read

4. "VBlank Minimal: Polling loop starting at 240.340"
   - Poll 100 times with 12-cycle delays
   - Coverage: VBlank detection via polling

#### `vblank_tracking_test.zig` (1 test) - NO Harness
1. "VBlank Tracking: Watch flag through 241.0 to 241.10"
   - Track flag state at each dot from 241.0 to 241.20
   - Coverage: Dot-level precision of VBlank set at 241.1

#### `vblank_persistence_test.zig` (2 tests) - NO Harness
1. "VBlank Persistence: Flag stays set for 20 scanlines"
   - Verify flag stays set from 241.1 to 261.0
   - Check every scanline through VBlank period
   - Coverage: VBlank flag persistence, clear at 261.1

2. "VBlank Persistence: Direct check without harness"
   - Run 2 frames, track set/clear transitions
   - Coverage: VBlank lifecycle across frames

#### `vblank_polling_simple_test.zig` (2 tests) - NO Harness
1. "VBlank Simple: Can detect VBlank by polling"
   - Poll for 2 frames until VBlank detected
   - Coverage: Polling detection (similar to minimal)

2. "VBlank Simple: Direct flag check"
   - Seek to 241.1, check flag, read $2002
   - Coverage: Same as minimal test #3

#### `ppustatus_read_test.zig` (8 tests) - USES Harness ✅
1. "PPUSTATUS Read: Returns VBlank flag correctly"
   - Direct flag set, read $2002, verify bit 7 and clear
   - Coverage: Basic $2002 read behavior

2. "PPUSTATUS Read: Returns correct value when VBlank clear"
   - Flag clear, read $2002, verify bit 7 clear
   - Coverage: $2002 when VBlank is not set

3. "PPUSTATUS Read: VBlank at scanline 241 dot 1 via seekToScanlineDot"
   - Harness.seekToScanlineDot(241, 1), read $2002
   - Coverage: Harness helper, VBlank at exact timing

4. "PPUSTATUS Read: VBlank at scanline 245 middle of VBlank"
   - Seek to 245.150, verify VBlank still set
   - Coverage: VBlank persistence mid-period

5. "PPUSTATUS Read: No VBlank at scanline 100"
   - Seek to visible scanline, verify no VBlank
   - Coverage: VBlank not set during rendering

6. "PPUSTATUS Read: VBlank cleared at scanline 261 dot 1"
   - Seek to 261.1, verify VBlank cleared
   - Coverage: VBlank clear timing

7. "PPUSTATUS Read: Polling simulation - advance 12 ticks and read"
   - Seek to 241.1, advance 12 ticks, read $2002
   - Coverage: Delayed read after VBlank set

8. "PPUSTATUS Read: Loop polling from 240.340 - exact replica"
   - Poll continuously from 240.340 through VBlank
   - Coverage: Continuous polling pattern

---

## Consolidation Plan

### New File: `tests/ppu/vblank_behavior_test.zig`
**Purpose:** Comprehensive VBlank flag behavior (lifecycle, timing, persistence)
**Pattern:** Use Harness for all tests
**Tests to Migrate:**

1. **"VBlank: Flag sets at scanline 241 dot 1"**
   - From: vblank_minimal #2, vblank_tracking #1
   - Coverage: Exact set timing, dot-level precision

2. **"VBlank: Flag clears at scanline 261 dot 1"**
   - From: vblank_persistence #1, ppustatus_read #6
   - Coverage: Exact clear timing

3. **"VBlank: Flag persists across scanlines without reads"**
   - From: vblank_persistence #1 & #2
   - Coverage: Flag stability through VBlank period

4. **"VBlank: Multiple frame transitions"**
   - From: vblank_persistence #2
   - Coverage: Set/clear across multiple frames

5. **"VBlank: Flag not set during visible scanlines"**
   - From: ppustatus_read #5
   - Coverage: No VBlank during rendering

### Enhanced File: `tests/ppu/ppustatus_behavior_test.zig`
**Purpose:** PPUSTATUS register ($2002) behavior
**Pattern:** Use Harness (already does)
**Tests to Migrate from ppustatus_read_test.zig:**

1. **"PPUSTATUS: Bit 7 reflects VBlank flag"**
   - From: ppustatus_read #1 & #2
   - Coverage: Bit 7 when VBlank set/clear

2. **"PPUSTATUS: Read clears VBlank flag"** ❌ KNOWN FAILING
   - From: vblank_minimal #3, vblank_polling_simple #2
   - Coverage: Side effect of $2002 read (currently broken)

3. **"PPUSTATUS: Polling from before VBlank"**
   - From: vblank_minimal #4, ppustatus_read #8
   - Coverage: Continuous polling pattern

4. **"PPUSTATUS: Delayed read after VBlank set"**
   - From: ppustatus_read #7
   - Coverage: Read after delay (BIT instruction timing)

5. **Keep existing ppustatus_polling_test.zig tests** (7 tests, 2 failing)
   - These have unique coverage for known VBlank $2002 bug

---

## Coverage Analysis

### Unique Coverage to Preserve

**From vblank_minimal_test.zig:**
- ✅ Direct flag manipulation (test #1) - low value, can skip
- ✅ VBlank set at 241.1 (test #2) - **covered by vblank_nmi_timing_test**
- ✅ $2002 read clears flag (test #3) - **covered by ppustatus_polling_test (failing)**
- ✅ Polling detection (test #4) - **covered by ppustatus_read #8**

**From vblank_tracking_test.zig:**
- ✅ Dot-level precision (test #1) - **NEW** - add to vblank_behavior_test

**From vblank_persistence_test.zig:**
- ✅ Flag persistence across scanlines (test #1) - **NEW** - add to vblank_behavior_test
- ✅ Multi-frame transitions (test #2) - **NEW** - add to vblank_behavior_test

**From vblank_polling_simple_test.zig:**
- ✅ Polling detection (test #1) - duplicate of minimal #4
- ✅ Direct flag check (test #2) - duplicate of minimal #3

**From ppustatus_read_test.zig:**
- ✅ All 8 tests - **move to ppustatus_behavior_test.zig or keep as separate**

### Verdict: Zero Coverage Loss
All unique coverage will be preserved in:
- `vblank_nmi_timing_test.zig` (keep as-is, 6 tests)
- `ppustatus_polling_test.zig` (keep as-is, 7 tests including 2 failing)
- `vblank_behavior_test.zig` (NEW, 5 tests)
- `ppustatus_behavior_test.zig` (NEW or enhance ppustatus_read, 4-8 tests)

---

## Consolidation Actions

### Step 1: Create vblank_behavior_test.zig (5 tests)
**NEW FILE** with Harness pattern, consolidating:
- vblank_minimal_test (portions)
- vblank_tracking_test (all)
- vblank_persistence_test (all)
- ppustatus_read_test (portions - timing tests)

### Step 2: Rename ppustatus_read_test.zig → ppustatus_behavior_test.zig
**OR** merge into existing ppustatus_polling_test.zig
- Consolidate all $2002 register behavior tests
- Keep 2 failing tests (known VBlank $2002 bug)

### Step 3: Delete 4 redundant files
After verification:
- ❌ `vblank_minimal_test.zig`
- ❌ `vblank_tracking_test.zig`
- ❌ `vblank_persistence_test.zig`
- ❌ `vblank_polling_simple_test.zig`

### Step 4: Update build.zig
Remove deleted test files, add new test file

---

## Expected Results

**Before:**
- 7 VBlank test files
- 30 tests total
- Mixed patterns (4 no Harness, 3 with Harness)

**After:**
- 3-4 VBlank test files (depending on ppustatus merge decision)
- 22-26 tests total (consolidated duplicates)
- Consistent Harness pattern
- Zero coverage loss
- Cleaner test organization

**Test Count Impact:**
- May reduce test count by 4-8 (duplicates removed)
- All unique coverage preserved
- Better organized by concern

---

## Verification Checklist

Before committing:
- [ ] All new tests use Harness pattern
- [ ] Run full test suite - verify no regressions
- [ ] Verify 2 known failing tests still present
- [ ] Check test count (should be ~925-929 passing)
- [ ] Update build.zig with new file references
- [ ] Document consolidation in tracking log
- [ ] No coverage loss (verify with test run)

---

## Notes

**Pattern Consistency:**
- ALL new tests use `Harness.init()` / `defer harness.deinit()`
- ALL new tests use `harness.seekToScanlineDot()` for positioning
- NO direct `EmulationState.init()` usage
- Consistent test naming: "Component: specific behavior"

**Known Issues:**
- VBlank $2002 read bug preserved in ppustatus_polling_test.zig (2 failing tests)
- Do NOT consolidate these failing tests - they are documentation

**Methodical Process:**
1. ✅ Inventory complete
2. ⏳ Create new consolidated files
3. ⏳ Verify tests pass
4. ⏳ Delete redundant files
5. ⏳ Update build.zig
6. ⏳ Commit with detailed message
