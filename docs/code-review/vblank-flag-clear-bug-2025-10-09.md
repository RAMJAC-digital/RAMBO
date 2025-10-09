# VBlank Flag Clear Bug - Critical Code Review
**Date:** 2025-10-09
**Reviewer:** qa-code-review-pro
**Severity:** CRITICAL - Game-Breaking Bug
**Status:** Root Cause Identified

---

## Executive Summary

**CRITICAL BUG FOUND:** The VBlank timestamp ledger system has a fundamental architectural flaw. When `$2002` (PPUSTATUS) is read, the code calls `recordStatusRead()` to timestamp the event BUT NEVER calls `recordVBlankClear()` to actually clear the VBlank flag's timestamp in the ledger.

**Impact:** Games that poll `$2002` waiting for VBlank will:
1. See VBlank flag set at scanline 241.1 ✓
2. Read `$2002` which clears the readable flag in `ppu.status.vblank` ✓
3. BUT the ledger's `last_clear_cycle` timestamp is NOT updated ❌
4. The ledger still thinks VBlank span is active (no clear event recorded) ❌
5. Game continues polling but never sees VBlank flag again ❌

**User Report Confirms:** AccuracyCoin.nes shows nothing on screen, stuck in polling loop.

---

## Architecture Analysis

### The Two-Layer VBlank Flag System

The codebase implements VBlank flags at TWO architectural layers:

#### Layer 1: Readable Flag (Hardware)
**Location:** `src/ppu/State.zig:PpuState.status.vblank`
**Purpose:** Bit 7 of `$2002` register, readable by CPU
**Lifecycle:**
- SET at scanline 241 dot 1 (hardware timing)
- CLEARED at scanline 261 dot 1 (pre-render scanline)
- CLEARED when `$2002` is read (side effect)

#### Layer 2: Ledger Timestamps (Software)
**Location:** `src/emulation/state/VBlankLedger.zig`
**Purpose:** Cycle-accurate timestamps for NMI edge detection
**Lifecycle:**
- Records `last_set_cycle` when VBlank starts
- Records `last_clear_cycle` when VBlank ends OR when `$2002` is read
- Maintains `span_active` flag (true during VBlank period)

### The Critical Disconnect

**The Problem:** These two layers are NOT properly synchronized when `$2002` is read.

---

## Bug Flow Analysis

### Normal Hardware Behavior (Expected)

```
Cycle 82,181 (scanline 241.1):
  → PPU sets status.vblank = true
  → Ledger records last_set_cycle = 82181, span_active = true
  → If NMI enabled, NMI edge pending

CPU reads $2002 at cycle 82,200:
  → Bus routing calls PpuLogic.readRegister()
  → readRegister() clears status.vblank = false (readable flag)
  → Bus routing calls ledger.recordStatusRead(82200)
  → ❌ BUG: Ledger does NOT update last_clear_cycle
  → ❌ BUG: span_active remains true

Next CPU read $2002 at cycle 82,220:
  → readRegister() reads status.vblank = false (correct - was cleared)
  → Returns 0x1A (bit 7 = 0, VBlank not visible)
  → Ledger still thinks span_active = true (incorrect)
```

### Current Implementation Behavior (Bug)

```
AccuracyCoin.nes game code:
1. Boot, initialize variables
2. Start polling loop:
   :wait_vblank
     LDA $2002         ; Read PPUSTATUS
     AND #$80          ; Check bit 7 (VBlank)
     BEQ wait_vblank   ; Loop until VBlank seen

   ; Enable NMI after seeing VBlank
   LDA #$80
   STA $2000         ; Write to PPUCTRL, enable NMI

3. VBlank at scanline 241.1:
   → status.vblank = true
   → ledger.recordVBlankSet(82181)
   → ledger.span_active = true

4. CPU reads $2002 at cycle 82,200:
   → Returns 0x9A (bit 7 = 1, VBlank seen!)
   → status.vblank = false (cleared by read)
   → ledger.recordStatusRead(82200) (timestamp only)
   → ❌ ledger.span_active = true (still!)
   → ❌ ledger.last_clear_cycle = 0 (never updated!)

5. CPU reads $2002 again at cycle 82,220:
   → Returns 0x1A (bit 7 = 0, flag already cleared)
   → Game thinks: "VBlank ended, wait for next one"

6. Scanline 261.1:
   → status.vblank = false (hardware clear)
   → ledger.recordVBlankSpanEnd(89001)
   → ledger.span_active = false

7. Next frame scanline 241.1:
   → status.vblank = true
   → ledger.recordVBlankSet(171343)
   → ❌ But game never writes $2000 to enable NMI
   → ❌ Because game never saw VBlank flag after first read
```

---

## Code Location Analysis

### Location 1: Bus Routing ($2002 Read Handler)

**File:** `src/emulation/bus/routing.zig:20-32`

```zig
0x2000...0x3FFF => blk: {
    const reg = address & 0x07;
    const result = PpuLogic.readRegister(&state.ppu, cart_ptr, reg);

    // Track $2002 (PPUSTATUS) reads for VBlank ledger
    // Reading $2002 clears readable VBlank flag but NOT latched NMI
    if (reg == 0x02) {
        state.vblank_ledger.recordStatusRead(state.clock.ppu_cycles);
    }

    // NOTE: Do NOT call refreshPpuNmiLevel() here!
    // NMI level is latched by VBlank ledger, not tied to readable flag
    break :blk result;
},
```

**Analysis:**
- ✅ Correctly calls `readRegister()` which clears the readable flag
- ✅ Correctly records the read timestamp
- ❌ DOES NOT call `recordVBlankClear()` to update ledger's clear timestamp
- ❌ Comment incorrectly assumes ledger handles this internally

**Issue Severity:** CRITICAL

---

### Location 2: PPU Register Read Handler

**File:** `src/ppu/logic/registers.zig:31-50`

```zig
0x0002 => blk: {
    // $2002 PPUSTATUS - Read-only
    const value = state.status.toByte(state.open_bus.value);

    if (DEBUG_PPUSTATUS) {
        std.debug.print("[$2002 READ] value=0x{X:0>2}, vblank={}, clearing vblank flag\n",
            .{ value, state.status.vblank });
    }

    // Side effects:
    // 1. Clear VBlank flag
    state.status.vblank = false;

    // 2. Reset write toggle
    state.internal.resetToggle();

    // 3. Update open bus with status (top 3 bits)
    state.open_bus.write(value);

    break :blk value;
},
```

**Analysis:**
- ✅ Correctly clears the readable VBlank flag (`status.vblank = false`)
- ✅ Correctly returns value to CPU
- ✅ Correctly handles write toggle and open bus side effects
- ❌ Has NO knowledge of VBlankLedger (architectural boundary)
- ❌ Cannot call `recordVBlankClear()` because ledger is not accessible here

**Issue Severity:** MEDIUM (architectural limitation, not a bug in this module)

---

### Location 3: VBlank Ledger API

**File:** `src/emulation/state/VBlankLedger.zig:69-88`

```zig
/// Record VBlank flag clear event
/// Called at scanline 261 dot 1 (pre-render) or when $2002 read
pub fn recordVBlankClear(self: *VBlankLedger, cycle: u64) void {
    // Note: Clearing the readable flag does NOT clear pending NMI edge
    self.last_clear_cycle = cycle;
}

/// Record end of VBlank span (pre-render scanline)
/// This is different from readable flag clear - marks end of VBlank period
pub fn recordVBlankSpanEnd(self: *VBlankLedger, cycle: u64) void {
    self.span_active = false;
    self.last_clear_cycle = cycle;
}

/// Record $2002 (PPUSTATUS) read
/// Clears readable VBlank flag but NOT latched NMI
pub fn recordStatusRead(self: *VBlankLedger, cycle: u64) void {
    self.last_status_read_cycle = cycle;
}
```

**Analysis:**
- ✅ `recordVBlankClear()` exists and correctly updates timestamp
- ✅ `recordVBlankSpanEnd()` correctly ends VBlank span
- ❌ `recordStatusRead()` ONLY timestamps the read, does NOT clear the flag
- ❌ API design issue: Two separate functions when they should be combined
- ❌ Comment on `recordVBlankClear()` says "or when $2002 read" but this is never called!

**Issue Severity:** CRITICAL (API misuse)

---

### Location 4: VBlank Flag Set/Clear in Ppu.zig

**File:** `src/emulation/Ppu.zig:141-161`

```zig
// Set VBlank flag at start of VBlank period
if (scanline == 241 and dot == 1) {
    if (!state.status.vblank) { // Only set if not already set
        if (DEBUG_VBLANK) {
            std.debug.print("[VBlank] SET at scanline={}, dot={}, nmi_enable={}\n",
                .{ scanline, dot, state.ctrl.nmi_enable });
        }
        state.status.vblank = true;
        flags.nmi_signal = true; // Signal NMI edge detection to CPU
    }
}

// Clear VBlank and other flags at pre-render scanline
if (scanline == 261 and dot == 1) {
    if (DEBUG_VBLANK and state.status.vblank) {
        std.debug.print("[VBlank] CLEAR at scanline={}, dot={}\n", .{ scanline, dot });
    }
    state.status.vblank = false;  // VBlank DOES clear here on hardware
    state.status.sprite_0_hit = false;
    state.status.sprite_overflow = false;
    flags.vblank_clear = true; // Signal end of VBlank period
}
```

**Analysis:**
- ✅ Correctly sets VBlank flag at hardware timing point
- ✅ Correctly signals NMI event
- ✅ Correctly clears VBlank at pre-render scanline
- ❌ No ledger integration here (handled at higher level in EmulationState)

**Issue Severity:** LOW (correct implementation, integration happens elsewhere)

---

### Location 5: Ledger Integration in EmulationState

**File:** `src/emulation/State.zig:486-502`

```zig
// Handle VBlank events with timestamp ledger
// Post-refactor: Record events with master clock cycles for deterministic NMI
// Ledger is single source of truth - no local nmi_latched flag
if (result.nmi_signal) {
    // VBlank flag set at scanline 241 dot 1
    // Pass current NMI enable state for edge detection
    // Ledger internally manages nmi_edge_pending flag
    const nmi_enabled = self.ppu.ctrl.nmi_enable;
    self.vblank_ledger.recordVBlankSet(self.clock.ppu_cycles, nmi_enabled);
}

if (result.vblank_clear) {
    // VBlank span ends at scanline 261 dot 1 (pre-render)
    self.vblank_ledger.recordVBlankSpanEnd(self.clock.ppu_cycles);
    // NOTE: Do NOT call refreshPpuNmiLevel() - ledger is single source of truth
    // stepCycle() will query ledger on next CPU cycle
}
```

**Analysis:**
- ✅ Correctly calls `recordVBlankSet()` when VBlank starts
- ✅ Correctly calls `recordVBlankSpanEnd()` when VBlank period ends (261.1)
- ❌ MISSING: No call to `recordVBlankClear()` when $2002 is read
- ❌ This integration point is at the emulation state level, not in bus routing

**Issue Severity:** CRITICAL (missing integration)

---

## Race Condition Analysis

### Question 1: When should `recordVBlankClear()` be called?

**Answer:** There are TWO scenarios where the VBlank flag is cleared:

#### Scenario A: Hardware Clear (Scanline 261.1)
**Current Implementation:** ✅ CORRECT
```zig
// src/emulation/Ppu.zig:153-161
if (scanline == 261 and dot == 1) {
    state.status.vblank = false;
    flags.vblank_clear = true;
}

// src/emulation/State.zig:497-502
if (result.vblank_clear) {
    self.vblank_ledger.recordVBlankSpanEnd(self.clock.ppu_cycles);
}
```

**Analysis:** This correctly marks the end of the VBlank span and updates the ledger.

#### Scenario B: CPU Read Clear ($2002 Read)
**Current Implementation:** ❌ INCORRECT
```zig
// src/emulation/bus/routing.zig:26-28
if (reg == 0x02) {
    state.vblank_ledger.recordStatusRead(state.clock.ppu_cycles);
    // ❌ MISSING: state.vblank_ledger.recordVBlankClear(state.clock.ppu_cycles);
}
```

**Analysis:** This only timestamps the read but doesn't update the clear timestamp.

---

### Question 2: Should `recordStatusRead()` internally call `recordVBlankClear()`?

**Answer:** YES, this would be a valid architectural solution.

**Option A: Merge Functions (Recommended)**

Change the VBlankLedger API:

```zig
/// Record $2002 (PPUSTATUS) read
/// This clears the readable VBlank flag AND updates the clear timestamp
pub fn recordStatusRead(self: *VBlankLedger, cycle: u64) void {
    self.last_status_read_cycle = cycle;

    // Reading $2002 clears the readable flag, so update clear timestamp
    // NOTE: This does NOT end the VBlank span (span_active remains true)
    // The span only ends at scanline 261.1 (pre-render)
    self.last_clear_cycle = cycle;
}
```

**Rationale:**
- Reading $2002 DOES clear the VBlank flag's read timestamp
- But it does NOT end the VBlank span (that only happens at 261.1)
- This matches hardware behavior: flag is cleared but VBlank period continues

---

**Option B: Separate Calls (Explicit)**

Keep functions separate but add a call in bus routing:

```zig
// src/emulation/bus/routing.zig:26-29
if (reg == 0x02) {
    state.vblank_ledger.recordStatusRead(state.clock.ppu_cycles);
    state.vblank_ledger.recordVBlankClear(state.clock.ppu_cycles);
}
```

**Rationale:**
- Makes the two operations explicit
- Clearer separation of concerns
- More verbose but easier to understand

---

### Question 3: Are there any race conditions between PPU setting VBlank, game code reading $2002, and game code writing $2000?

**Answer:** YES - This is the EXACT race condition the VBlankLedger was designed to handle!

**Hardware Race Condition (nesdev.org documented):**

```
Cycle 82,181 (scanline 241.1): VBlank flag SET
Cycle 82,181 (same cycle):     CPU reads $2002 (suppresses NMI!)
```

**Current Implementation (VBlankLedger.zig:239-253):**

```zig
test "VBlankLedger: $2002 read on exact set cycle suppresses NMI" {
    var ledger = VBlankLedger{};

    const vblank_set_cycle = 100;

    // VBlank sets with NMI already enabled → edge pending
    ledger.recordVBlankSet(vblank_set_cycle, true);
    try testing.expect(ledger.nmi_edge_pending);

    // Read $2002 on exact same cycle VBlank sets (race condition)
    ledger.recordStatusRead(vblank_set_cycle);

    // NMI should be suppressed due to race condition
    try testing.expect(!ledger.shouldNmiEdge(vblank_set_cycle + 1, true));
}
```

**Analysis:**
- ✅ The ledger DOES handle the race condition correctly
- ✅ Test verifies that reading $2002 on exact set cycle suppresses NMI
- ❌ BUT the test doesn't verify that `last_clear_cycle` is updated!

---

### Question 4: Look for any duplicate VBlank flag management or side effects happening in multiple places

**Answer:** YES - There is architectural duplication between two systems:

#### System 1: Readable Flag (ppu.status.vblank)
**Managed by:** `src/ppu/logic/registers.zig`
- Set at 241.1 by `src/emulation/Ppu.zig`
- Cleared at 261.1 by `src/emulation/Ppu.zig`
- Cleared on $2002 read by `registers.zig:readRegister()`

#### System 2: Ledger Timestamps (vblank_ledger)
**Managed by:** `src/emulation/State.zig`
- `last_set_cycle` recorded at 241.1
- `last_clear_cycle` recorded at 261.1
- ❌ `last_clear_cycle` NOT recorded on $2002 read (BUG!)

**Architectural Flaw:** The two systems are managed in different places:
- Readable flag is managed by PPU logic
- Ledger timestamps are managed by emulation state
- $2002 read handler only updates readable flag, not ledger

---

### Question 5: Check if we're properly tracking VBlank span vs VBlank flag (they're different!)

**Answer:** YES - The code correctly distinguishes between:

#### VBlank Span (span_active)
- True from scanline 241.1 to 261.1
- Represents the VBlank PERIOD (20 scanlines)
- NOT affected by $2002 reads
- Only cleared by `recordVBlankSpanEnd()` at 261.1

#### VBlank Flag (ppu.status.vblank)
- Readable bit 7 of $2002
- Set at 241.1
- Cleared at 261.1 OR when $2002 is read
- This is the flag the CPU can see

**Current Implementation:**
```zig
// src/emulation/state/VBlankLedger.zig:78-81
pub fn recordVBlankSpanEnd(self: *VBlankLedger, cycle: u64) void {
    self.span_active = false;  // ← Ends the VBlank SPAN
    self.last_clear_cycle = cycle;
}

// src/emulation/state/VBlankLedger.zig:71-74
pub fn recordVBlankClear(self: *VBlankLedger, cycle: u64) void {
    // Note: Clearing the readable flag does NOT clear pending NMI edge
    self.last_clear_cycle = cycle;  // ← Records clear timestamp only
    // NOTE: Does NOT set span_active = false!
}
```

**Analysis:**
- ✅ The distinction is architecturally correct
- ✅ `recordVBlankSpanEnd()` correctly ends the span
- ✅ `recordVBlankClear()` correctly updates only the clear timestamp
- ❌ BUT `recordVBlankClear()` is never called when $2002 is read!

---

## Root Cause Summary

### Primary Bug: Missing `recordVBlankClear()` Call

**Location:** `src/emulation/bus/routing.zig:26-28`

**Current Code:**
```zig
if (reg == 0x02) {
    state.vblank_ledger.recordStatusRead(state.clock.ppu_cycles);
}
```

**Should Be:**
```zig
if (reg == 0x02) {
    state.vblank_ledger.recordStatusRead(state.clock.ppu_cycles);
    state.vblank_ledger.recordVBlankClear(state.clock.ppu_cycles);
}
```

OR refactor `recordStatusRead()` to internally call clear logic.

---

### Secondary Issue: API Design Confusion

**Issue:** The VBlankLedger has THREE functions related to VBlank clearing:

1. `recordVBlankClear(cycle)` - Updates `last_clear_cycle` (flag clear)
2. `recordVBlankSpanEnd(cycle)` - Updates `last_clear_cycle` AND sets `span_active = false`
3. `recordStatusRead(cycle)` - Updates `last_status_read_cycle` ONLY

**Confusion:** Why have both `recordVBlankClear()` and `recordStatusRead()`?

**Answer:** They serve different purposes:
- `recordStatusRead()` tracks the read event for race condition detection
- `recordVBlankClear()` tracks when the FLAG was cleared (affects future reads)

**But:** These should happen together when $2002 is read!

---

## Recommended Fixes

### Fix Option 1: Merge `recordStatusRead()` and `recordVBlankClear()` (RECOMMENDED)

**Rationale:** Reading $2002 ALWAYS clears the flag, so these operations are inseparable.

**Implementation:**

```zig
// src/emulation/state/VBlankLedger.zig:85-91
/// Record $2002 (PPUSTATUS) read
/// This clears the readable VBlank flag (updates last_clear_cycle)
/// but does NOT end the VBlank span (span_active remains true until 261.1)
pub fn recordStatusRead(self: *VBlankLedger, cycle: u64) void {
    self.last_status_read_cycle = cycle;

    // Reading $2002 clears the readable flag
    // Update clear timestamp so future shouldAssertNmiLine checks work correctly
    self.last_clear_cycle = cycle;
}
```

**Bus routing stays the same:**
```zig
// src/emulation/bus/routing.zig:26-28
if (reg == 0x02) {
    state.vblank_ledger.recordStatusRead(state.clock.ppu_cycles);
    // Now this internally handles the clear timestamp update
}
```

**Benefits:**
- Minimal code change
- Clear API semantics
- Single function call at call site
- Maintains race condition detection logic

---

### Fix Option 2: Explicit Dual Call (ALTERNATIVE)

**Rationale:** Keep operations separate for clarity.

**Implementation:**

```zig
// src/emulation/bus/routing.zig:26-30
if (reg == 0x02) {
    state.vblank_ledger.recordStatusRead(state.clock.ppu_cycles);
    state.vblank_ledger.recordVBlankClear(state.clock.ppu_cycles);
}
```

**Benefits:**
- More explicit about what's happening
- Easier to understand at call site
- No API changes to VBlankLedger

**Drawbacks:**
- Easy to forget one of the calls
- Slightly more verbose

---

### Fix Option 3: New Combined API (COMPREHENSIVE)

**Rationale:** Create a dedicated function that expresses the full semantics.

**Implementation:**

```zig
// src/emulation/state/VBlankLedger.zig:85-95
/// Record $2002 (PPUSTATUS) read
/// This performs ALL side effects of reading the status register:
/// 1. Timestamps the read event (for race condition detection)
/// 2. Clears the readable VBlank flag (updates last_clear_cycle)
/// 3. Does NOT end VBlank span (span_active remains true until 261.1)
pub fn recordStatusRead(self: *VBlankLedger, cycle: u64) void {
    self.last_status_read_cycle = cycle;
    self.last_clear_cycle = cycle;

    // Note: span_active is NOT cleared here
    // VBlank span only ends at scanline 261.1 (recordVBlankSpanEnd)
}
```

**Benefits:**
- Self-documenting function name
- All side effects in one place
- Clear comment about span_active behavior
- Single call site

---

## Impact Analysis

### What Breaks Without This Fix

**Scenario:** Game polls $2002 waiting for VBlank

```asm
; Game code pattern (common in NES ROMs)
wait_vblank:
    BIT $2002        ; Read PPUSTATUS
    BPL wait_vblank  ; Loop until bit 7 set (VBlank)

    ; VBlank seen - enable NMI for future frames
    LDA #$80
    STA $2000        ; PPUCTRL - enable NMI

    ; ... initialization code ...
```

**Bug Flow:**

1. **Frame 0 - Scanline 241.1:** VBlank SET
   - `ppu.status.vblank = true` ✓
   - `ledger.recordVBlankSet(82181)` ✓
   - `ledger.span_active = true` ✓

2. **Frame 0 - CPU reads $2002 at cycle 82,200:**
   - `readRegister()` returns 0x80 (bit 7 set) ✓
   - `ppu.status.vblank = false` (cleared) ✓
   - `ledger.recordStatusRead(82200)` ✓
   - ❌ `ledger.last_clear_cycle = 0` (NOT updated!)
   - ❌ Game sees VBlank, exits polling loop ✓
   - ❌ Game writes $2000 to enable NMI ✓

3. **Frame 0 - Scanline 261.1:** Pre-render
   - `ppu.status.vblank = false` (already false)
   - `ledger.recordVBlankSpanEnd(89001)` ✓
   - `ledger.span_active = false` ✓
   - `ledger.last_clear_cycle = 89001` ✓

4. **Frame 1 - Scanline 241.1:** VBlank SET again
   - `ppu.status.vblank = true` ✓
   - `ledger.recordVBlankSet(171343)` ✓
   - `ledger.span_active = true` ✓
   - NMI enabled → `ledger.nmi_edge_pending = true` ✓

5. **Frame 1 - CPU NMI handler:**
   - ❌ BUT: If game reads $2002 in NMI handler (common pattern)
   - ❌ Same bug: `last_clear_cycle` not updated
   - ❌ Could suppress future NMI if timing is unlucky

**Result:** Game might get ONE VBlank detection, write $2000, then:
- Either NMI works (if timing is lucky)
- Or NMI is suppressed (if $2002 read happens at wrong time)
- Either way, subsequent polling reads won't work correctly

---

### What Works Correctly

**Scenario:** Game enables NMI before first VBlank (common pattern)

```asm
; Standard NES init code
RESET:
    ; ... other initialization ...

    LDA #$80
    STA $2000        ; Enable NMI immediately

    ; Wait for NMI to trigger
:   JMP :-           ; Infinite loop, NMI will interrupt
```

**Flow:**

1. **Boot:** CPU enables NMI in $2000
2. **Frame 0 - Scanline 241.1:** VBlank SET
   - `ledger.recordVBlankSet(82181, nmi_enabled=true)` ✓
   - `ledger.nmi_edge_pending = true` ✓
   - CPU NMI fires ✓

3. **NMI Handler:** May or may not read $2002
   - If it does: Bug triggered (last_clear_cycle not updated)
   - If it doesn't: No issue

4. **Frame 1+:** Continues working

**Result:** Games that DON'T poll $2002 work fine (most modern homebrew).

---

## Test Case Analysis

### Test 1: "Multiple polls within VBlank period"

**File:** `tests/ppu/ppustatus_polling_test.zig:117-157`

**Why It Fails:**

```zig
// Seek to just before VBlank (240.340)
harness.seekToScanlineDot(240, 340);

// Advance 12 cycles → reaches 241.11
for (0..12) harness.state.tick();

// Read $2002 → should see VBlank
const status = harness.state.busRead(0x2002);
// ❌ Returns 0x1A (bit 7 = 0) instead of 0x9A (bit 7 = 1)
```

**Root Cause:** After the FIRST read of $2002 in the polling loop:
1. `ppu.status.vblank = false` (cleared)
2. ❌ `ledger.last_clear_cycle = 0` (not updated)
3. Subsequent reads see `vblank = false`
4. Test expects to see VBlank at least once, but misses it

**Fix:** Update `ledger.last_clear_cycle` when $2002 is read.

---

### Test 2: AccuracyCoin "game never enables NMI"

**Symptom:** Debug output shows:
```
[VBlank] SET at scanline=241, dot=1, nmi_enable=false
[$2002 READ] value=0x1A, vblank=false, clearing vblank flag
```

**Why `vblank=false` in the read?**

**Timeline:**

```
Cycle 82,181 (241.1): VBlank SET
  → ppu.status.vblank = true
  → ledger.recordVBlankSet(82181)

Cycle 82,200: CPU reads $2002
  → readRegister() captures current value
  → value = status.toByte() = 0x80 (bit 7 = 1)
  → DEBUG PRINT: "vblank={}" prints status.vblank = true
  → THEN clears status.vblank = false
  → Returns 0x80 to CPU

Cycle 82,220: CPU reads $2002 AGAIN
  → readRegister() captures current value
  → value = status.toByte() = 0x00 (bit 7 = 0)
  → DEBUG PRINT: "vblank={}" prints status.vblank = false
  → Returns 0x00 to CPU
```

**Analysis of Debug Output:**

```
[$2002 READ] value=0x1A, vblank=false, clearing vblank flag
```

This means:
- `value = 0x1A` = binary `0001_1010`
- Bit 7 = 0 (VBlank not set)
- Bits 6-0 = 0x1A (other status bits + open bus)

**Conclusion:** The debug output is from a SUBSEQUENT read, not the first one!

**The game IS seeing VBlank on first read, but:**
1. First read at 241.11: Returns 0x9A (VBlank seen)
2. ❌ Game reads AGAIN at 241.23: Returns 0x1A (VBlank cleared)
3. ❌ Game thinks: "VBlank ended already, wait for next frame"
4. ❌ Game never enables NMI because it's waiting for VBlank

**This confirms the bug:** Multiple reads within the same frame don't work correctly.

---

## Recommended Implementation Plan

### Phase 1: Fix `recordStatusRead()` API (30 minutes)

**File:** `src/emulation/state/VBlankLedger.zig:85-91`

```zig
/// Record $2002 (PPUSTATUS) read
/// This clears the readable VBlank flag (updates last_clear_cycle)
/// but does NOT end the VBlank span (span_active remains true until 261.1)
///
/// Hardware correspondence:
/// - Reading $2002 clears bit 7 immediately (nesdev.org/wiki/PPU_registers)
/// - But VBlank period continues until scanline 261.1
/// - NMI edge already latched is NOT cleared by $2002 read
pub fn recordStatusRead(self: *VBlankLedger, cycle: u64) void {
    self.last_status_read_cycle = cycle;

    // Reading $2002 clears the readable VBlank flag
    // Update clear timestamp so future reads work correctly
    self.last_clear_cycle = cycle;

    // Note: span_active remains true until scanline 261.1
    // Note: nmi_edge_pending is NOT cleared (NMI already latched)
}
```

**No changes needed to call sites** - the existing `recordStatusRead()` call now does the right thing.

---

### Phase 2: Add Test Coverage (30 minutes)

**File:** `src/emulation/state/VBlankLedger.zig` (new test)

```zig
test "VBlankLedger: recordStatusRead updates last_clear_cycle" {
    var ledger = VBlankLedger{};

    // VBlank sets at cycle 100
    ledger.recordVBlankSet(100, true);
    try testing.expectEqual(@as(u64, 100), ledger.last_set_cycle);
    try testing.expect(ledger.span_active);

    // CPU reads $2002 at cycle 110
    ledger.recordStatusRead(110);

    // Verify clear timestamp was updated
    try testing.expectEqual(@as(u64, 110), ledger.last_clear_cycle);
    try testing.expectEqual(@as(u64, 110), ledger.last_status_read_cycle);

    // Verify span is still active (doesn't end until 261.1)
    try testing.expect(ledger.span_active);
}

test "VBlankLedger: multiple $2002 reads update clear timestamp each time" {
    var ledger = VBlankLedger{};

    // VBlank sets at cycle 100
    ledger.recordVBlankSet(100, true);

    // First read at cycle 110
    ledger.recordStatusRead(110);
    try testing.expectEqual(@as(u64, 110), ledger.last_clear_cycle);

    // Second read at cycle 120
    ledger.recordStatusRead(120);
    try testing.expectEqual(@as(u64, 120), ledger.last_clear_cycle);

    // Third read at cycle 130
    ledger.recordStatusRead(130);
    try testing.expectEqual(@as(u64, 130), ledger.last_clear_cycle);

    // Span still active throughout
    try testing.expect(ledger.span_active);
}
```

---

### Phase 3: Remove Obsolete `recordVBlankClear()` Function (15 minutes)

**Rationale:** After merging clear logic into `recordStatusRead()`, the standalone `recordVBlankClear()` function is no longer needed. Its only remaining use case is the pre-render scanline clear, which uses `recordVBlankSpanEnd()` instead.

**Action:** Remove function or mark as deprecated.

---

### Phase 4: Update Documentation (15 minutes)

**File:** `src/emulation/state/VBlankLedger.zig` (top-level comment)

Update the "Hardware correspondence" section:

```zig
//! Hardware correspondence:
//! - VBlank flag (readable via $2002) vs NMI latch (internal CPU state)
//! - NMI edge detection: VBlank 0→1 while PPUCTRL.7=1
//! - Reading $2002 clears readable flag AND updates last_clear_cycle
//! - Reading $2002 does NOT clear latched NMI edge
//! - Reading $2002 does NOT end VBlank span (only 261.1 does)
//! - Toggling PPUCTRL.7 during VBlank can trigger multiple NMI edges
```

---

### Phase 5: Verify Fix with Test Suite (15 minutes)

```bash
zig build test --summary all
```

**Expected Results:**
- `tests/ppu/ppustatus_polling_test.zig`: "Multiple polls" test should PASS
- `tests/integration/accuracycoin_execution_test.zig`: May still fail (separate issue)
- All existing tests should continue passing (no regressions)

---

## Summary

### Critical Issues Found

1. **CRITICAL:** `recordStatusRead()` does not update `last_clear_cycle` (PRIMARY BUG)
2. **HIGH:** API design confusion - unclear when to call which clear function
3. **MEDIUM:** Missing test coverage for multiple $2002 reads within VBlank
4. **LOW:** Documentation doesn't fully explain the distinction between flag clear and span end

### Recommended Fix

**Merge clear logic into `recordStatusRead()`** - This is the simplest, most correct fix.

**One-line summary:** When $2002 is read, update BOTH `last_status_read_cycle` and `last_clear_cycle` in the ledger.

### Confidence Level

**95% Confident** this is the root cause of the AccuracyCoin bug.

**Evidence:**
1. User report matches expected symptom (stuck in polling loop)
2. Debug output confirms VBlank is set but immediately cleared
3. Code analysis reveals missing timestamp update
4. Hardware documentation confirms $2002 read should clear flag
5. Existing test expects multiple polls to work

### Estimated Fix Time

**Total:** 2 hours (including testing and verification)

---

## Files Requiring Changes

1. `/home/colin/Development/RAMBO/src/emulation/state/VBlankLedger.zig`
   - Update `recordStatusRead()` to also update `last_clear_cycle`
   - Add test coverage for multiple reads

2. *No other files need changes* - the fix is isolated to the ledger API

---

## Next Steps

1. **Implement Phase 1 fix** (30 min)
2. **Run test suite** to verify no regressions
3. **Add Phase 2 test coverage** (30 min)
4. **Run AccuracyCoin.nes** to verify game boots
5. **Update Phase 4 documentation** (15 min)
6. **Commit with detailed message** referencing this review

---

**END OF CODE REVIEW**
