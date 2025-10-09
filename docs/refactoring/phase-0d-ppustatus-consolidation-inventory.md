# Phase 0-D: PPUSTATUS Test Consolidation Inventory

**Date:** 2025-10-09
**Purpose:** Methodical inventory of PPUSTATUS tests before consolidation
**Process:** Test-first refactoring - analyze before acting

---

## Current Test Files (3 PPUSTATUS-related)

| File | Tests | Uses Harness | Status | Action |
|------|-------|--------------|--------|--------|
| `ppustatus_polling_test.zig` | 7 | ✅ Yes | Good (2 failing - known) | **KEEP & ENHANCE** |
| `ppustatus_read_test.zig` | 8 | ✅ Yes | Good | MERGE |
| `bit_ppustatus_test.zig` | 2 | ❌ No | Integration test | MERGE |

**Total:** 17 tests across 3 files

---

## Analysis of Each File

### 1. `tests/ppu/ppustatus_polling_test.zig` (7 tests, 2 FAILING - KNOWN)

**Uses Harness:** ✅ Yes
**Status:** **KEEP as base file**

**Tests:**
1. "PPUSTATUS Polling: VBlank flag returns in bit 7"
   - Direct flag set, read $2002, verify bit 7
   - Coverage: Basic bit 7 behavior

2. "PPUSTATUS Polling: VBlank flag cleared after read"
   - Set VBlank, read $2002, verify flag cleared
   - Coverage: Read side effect

3. "PPUSTATUS Polling: Multiple polls within VBlank period" ❌ **FAILING (Known P1)**
   - Polls from 240.340 through VBlank
   - Coverage: VBlank $2002 clear bug (OUT OF SCOPE)
   - **MUST PRESERVE** - documents known issue

4. "PPUSTATUS Polling: Polling before VBlank returns 0"
   - Poll at scanline 100, verify no VBlank
   - Coverage: No VBlank during rendering

5. "PPUSTATUS Polling: VBlank clear at scanline 261.1"
   - Seek to 261.1, verify VBlank cleared
   - Coverage: VBlank clear timing

6. "PPUSTATUS Polling: Poll continuously through VBlank"
   - Continuous polling, track detections
   - Coverage: Polling pattern behavior

7. "PPUSTATUS Polling: BIT instruction timing - when does read occur?" ❌ **FAILING (Known P1)**
   - BIT $2002 execution timing validation
   - Coverage: Instruction-level timing, VBlank $2002 bug
   - **MUST PRESERVE** - documents known issue

**Unique Coverage:**
- ✅ 2 failing tests documenting VBlank $2002 bug (CRITICAL - must preserve)
- ✅ Continuous polling patterns
- ✅ BIT instruction timing validation

**Decision:** **KEEP as base file, merge others into this**

---

### 2. `tests/ppu/ppustatus_read_test.zig` (8 tests)

**Uses Harness:** ✅ Yes
**Status:** MERGE into ppustatus_polling_test.zig

**Tests:**
1. "PPUSTATUS Read: Returns VBlank flag correctly"
   - Direct flag set, read, verify bit 7 and clear
   - Coverage: DUPLICATE of ppustatus_polling #1 & #2

2. "PPUSTATUS Read: Returns correct value when VBlank clear"
   - Flag clear, read, verify bit 7 clear
   - Coverage: Similar to ppustatus_polling #4

3. "PPUSTATUS Read: VBlank at scanline 241 dot 1 via seekToScanlineDot"
   - Seek to 241.1, verify VBlank, read $2002
   - Coverage: **UNIQUE** - seekToScanlineDot validation at exact VBlank set point

4. "PPUSTATUS Read: VBlank at scanline 245 middle of VBlank"
   - Seek to 245.150, verify VBlank persists
   - Coverage: **UNIQUE** - mid-VBlank verification

5. "PPUSTATUS Read: No VBlank at scanline 100"
   - Seek to visible scanline, verify no VBlank
   - Coverage: DUPLICATE of ppustatus_polling #4

6. "PPUSTATUS Read: VBlank cleared at scanline 261 dot 1"
   - Seek to 261.1, verify cleared
   - Coverage: DUPLICATE of ppustatus_polling #5

7. "PPUSTATUS Read: Polling simulation - advance 12 ticks and read"
   - Seek 241.1, advance 12 ticks, verify still set, read
   - Coverage: **UNIQUE** - delayed read after VBlank set (simulates BIT timing)

8. "PPUSTATUS Read: Loop polling from 240.340 - exact replica"
   - Poll continuously from 240.340
   - Coverage: DUPLICATE of ppustatus_polling #3 & #6

**Unique Coverage to Preserve:**
- ✅ Test #3: seekToScanlineDot at 241.1 (exact VBlank set timing)
- ✅ Test #4: Mid-VBlank persistence check (245.150)
- ✅ Test #7: Delayed read simulation (12-tick advance)

**Decision:** **MERGE 3 unique tests into ppustatus_polling_test.zig, delete file**

---

### 3. `tests/integration/bit_ppustatus_test.zig` (2 tests)

**Uses Harness:** ❌ No (uses direct EmulationState)
**Status:** MERGE into ppustatus_polling_test.zig (convert to Harness)

**Tests:**
1. "BIT $2002: N flag reflects VBlank state before clearing"
   - Manual CPU instruction setup (BIT $2002 at 0x0000)
   - Execute 12 PPU cycles, verify N flag
   - Coverage: **UNIQUE** - CPU flag interaction with $2002 read

2. "BIT $2002 then BPL: Loop should exit when VBlank set"
   - Full BIT/BPL loop (VBlank polling pattern in assembly)
   - Verify branch behavior based on N flag
   - Coverage: **UNIQUE** - Complete VBlank wait loop pattern

**Unique Coverage to Preserve:**
- ✅ Test #1: CPU N flag set from $2002 bit 7
- ✅ Test #2: BIT/BPL VBlank wait loop (classic NES pattern)

**Issues:**
- Direct RAM manipulation (state.bus.ram[0] = 0x2C)
- Manual CPU setup (state.cpu.pc = 0x0000)
- Not using Harness pattern

**Decision:** **MERGE with Harness conversion, delete file**

**Note:** These tests validate CPU instruction interaction with PPUSTATUS, which is different from direct register reads. They should be preserved but may need to stay as integration tests if Harness doesn't support CPU instruction execution setup.

---

## Consolidation Plan

### Strategy: Enhance ppustatus_polling_test.zig

**Keep as base:** `tests/ppu/ppustatus_polling_test.zig` (7 tests, 2 failing)
- Already has critical failing tests for VBlank $2002 bug
- Already uses Harness pattern
- Good test organization

**Add from ppustatus_read_test.zig:** 3 unique tests
1. "PPUSTATUS: VBlank at exact set point 241.1"
2. "PPUSTATUS: Mid-VBlank persistence at 245.150"
3. "PPUSTATUS: Delayed read after 12-tick advance"

**Add from bit_ppustatus_test.zig:** 2 tests (with Harness conversion)
1. "PPUSTATUS BIT: CPU N flag reflects bit 7"
2. "PPUSTATUS BIT: BIT/BPL VBlank wait loop"

**Result:** 12 tests total in ppustatus_polling_test.zig (or rename to ppustatus_behavior_test.zig)

---

## Coverage Analysis

### Unique Coverage Matrix

| Test | Source File | Coverage | Preserve? | Destination |
|------|------------|----------|-----------|-------------|
| VBlank flag bit 7 | polling #1 | Basic $2002 read | ✅ Keep | Base file |
| Flag cleared after read | polling #2 | Read side effect | ✅ Keep | Base file |
| Multiple polls (FAILING) | polling #3 | VBlank $2002 bug | ✅ **CRITICAL** | Base file |
| No VBlank during rendering | polling #4 | Visible scanlines | ✅ Keep | Base file |
| VBlank clear 261.1 | polling #5 | Clear timing | ✅ Keep | Base file |
| Continuous polling | polling #6 | Polling pattern | ✅ Keep | Base file |
| BIT timing (FAILING) | polling #7 | Instruction timing | ✅ **CRITICAL** | Base file |
| **241.1 exact timing** | read #3 | **UNIQUE** | ✅ Add | Enhanced file |
| **Mid-VBlank 245.150** | read #4 | **UNIQUE** | ✅ Add | Enhanced file |
| **Delayed read** | read #7 | **UNIQUE** | ✅ Add | Enhanced file |
| **CPU N flag** | bit #1 | **UNIQUE** | ✅ Add | Enhanced file |
| **BIT/BPL loop** | bit #2 | **UNIQUE** | **?** Consider | Enhanced file |
| Basic flag check | read #1 | Duplicate | ❌ Skip | - |
| Flag clear check | read #2 | Duplicate | ❌ Skip | - |
| Visible scanline | read #5 | Duplicate | ❌ Skip | - |
| 261.1 clear | read #6 | Duplicate | ❌ Skip | - |
| 240.340 polling | read #8 | Duplicate | ❌ Skip | - |

**Duplicates to Remove:** 5 tests from ppustatus_read_test.zig
**Unique to Add:** 3 from ppustatus_read + 2 from bit_ppustatus (with caveats)

---

## BIT Instruction Tests - Special Consideration

**Issue:** The BIT instruction tests in `bit_ppustatus_test.zig` require:
- Manual CPU instruction setup (writing opcodes to RAM)
- Direct PC manipulation
- CPU instruction execution

**Harness Pattern Limitation:**
- Harness provides `seekToScanlineDot()`, `ppuReadRegister()`, `ppuWriteRegister()`
- Does NOT provide CPU instruction execution helpers

**Options:**
1. **Keep bit_ppustatus_test.zig as separate integration test**
   - Preserves CPU instruction validation
   - Maintains direct EmulationState usage for CPU setup
   - File stays in tests/integration/

2. **Convert to Harness and use harness.state.cpu directly**
   - Migrates to Harness pattern
   - Still requires direct state manipulation: `harness.state.bus.ram[0] = 0x2C`
   - Loses some test isolation benefits

3. **Skip BIT instruction tests (not recommended)**
   - Loses CPU instruction interaction coverage
   - VBlank wait loop pattern not validated

**Recommendation:** **Option 1** - Keep bit_ppustatus_test.zig separate
- These are integration tests (CPU + PPU interaction)
- Require different testing pattern than register-level tests
- Already in tests/integration/ directory (appropriate location)
- Can convert to Harness later if Harness gains CPU execution helpers

---

## Revised Consolidation Plan

### Action 1: Enhance ppustatus_polling_test.zig
Add 3 unique tests from ppustatus_read_test.zig:
1. "PPUSTATUS: VBlank at exact set point 241.1"
2. "PPUSTATUS: Mid-VBlank persistence at 245.150"
3. "PPUSTATUS: Delayed read after 12-tick advance"

**Result:** 10 tests (7 existing + 3 new)

### Action 2: Convert bit_ppustatus_test.zig to Harness
Migrate to Harness pattern while preserving CPU instruction setup:
```zig
var harness = try Harness.init();
defer harness.deinit();

// Still use direct state access for CPU instruction setup
harness.state.bus.ram[0] = 0x2C; // BIT absolute
harness.state.cpu.pc = 0x0000;
```

**Result:** Integration test stays in tests/integration/, uses Harness for consistency

### Action 3: Delete ppustatus_read_test.zig
All unique coverage moved to ppustatus_polling_test.zig

**Result:** 2 files instead of 3 (bit_ppustatus + enhanced ppustatus_polling)

---

## Expected Results

**Before:**
- 3 PPUSTATUS test files
- 17 tests total
- 2 failing (known VBlank $2002 bug)
- Mixed patterns (2 Harness, 1 direct EmulationState)

**After:**
- 2 PPUSTATUS test files
- 12 tests total (10 in ppustatus_polling + 2 in bit_ppustatus)
- 2 failing (same - preserved)
- Consistent Harness pattern
- Zero coverage loss

**Test Count Impact:**
- Remove 5 duplicate tests from ppustatus_read
- Keep all 10 unique tests (7 existing + 3 from ppustatus_read)
- Convert 2 integration tests to Harness
- Net: 17 → 12 tests (-5 duplicates)

---

## Verification Checklist

Before committing:
- [ ] Enhanced ppustatus_polling_test.zig with 3 new tests
- [ ] All new tests use Harness pattern
- [ ] Converted bit_ppustatus_test.zig to Harness
- [ ] Run full test suite - verify no regressions
- [ ] Verify 2 known failing tests still present and failing
- [ ] Check test count (~931 passing expected: 936 - 5 duplicates)
- [ ] Update build.zig (remove ppustatus_read reference)
- [ ] Document consolidation in tracking log
- [ ] No coverage loss verified

---

## Notes

**Pattern Consistency:**
- ALL tests use `Harness.init()` / `defer harness.deinit()`
- Integration tests (bit_ppustatus) allowed to access `harness.state` directly for CPU setup
- Consistent test naming: "PPUSTATUS: specific behavior"

**Known Issues Preserved:**
- 2 failing tests in ppustatus_polling_test.zig remain (VBlank $2002 bug, P1, out of scope)
- These are documentation of a real bug, must not be deleted

**File Naming:**
- Keep ppustatus_polling_test.zig name (already established)
- OR rename to ppustatus_behavior_test.zig (more descriptive)
- Recommendation: **Keep existing name** to minimize changes

---

## Methodical Process

1. ✅ Inventory complete
2. ⏳ Enhance ppustatus_polling_test.zig with 3 tests
3. ⏳ Convert bit_ppustatus_test.zig to Harness
4. ⏳ Verify tests pass
5. ⏳ Delete ppustatus_read_test.zig
6. ⏳ Update build.zig
7. ⏳ Final verification
8. ⏳ Commit with detailed message
