# VBlank Ledger Implementation Analysis - Comprehensive Investigation

## Executive Summary

The NMI control test failure (nmi_control_test.zig, ErrorCode=0x06) reveals a critical bug in how the VBlank ledger tracks and suppresses NMI re-triggering. The investigation shows that:

1. **Last_read_cycle remains stale** - gets set once but never updated on subsequent $2002 reads during the same VBlank span
2. **NMI suppression logic is inverted** - NMI remains asserted when it should be suppressed
3. **Race condition handling is incomplete** - the ledger clears race state too aggressively
4. **Multiple code paths don't update the ledger** - not all $2002 reads reach the ledger update code

---

## Part 1: VBlank Ledger Data Structure

**File:** `/home/colin/Development/RAMBO/src/emulation/VBlankLedger.zig`

### Fields
```zig
pub const VBlankLedger = struct {
    last_set_cycle: u64 = 0;      // PPU cycle when VBlank SET (scanline 241, dot 1)
    last_clear_cycle: u64 = 0;    // PPU cycle when VBlank CLEARED (scanline 261, dot 1)
    last_read_cycle: u64 = 0;     // PPU cycle of LAST $2002 read
    last_race_cycle: u64 = 0;     // PPU cycle marking race condition (same-cycle read+set)
```

### Key Methods

**isActive()** (line 26-28):
```zig
pub inline fn isActive(self: VBlankLedger) bool {
    return self.last_set_cycle > self.last_clear_cycle;
}
```
Returns true if VBlank is currently in the active period (between set and clear).

**isFlagVisible()** (line 32-35):
```zig
pub inline fn isFlagVisible(self: VBlankLedger) bool {
    if (!self.isActive()) return false;
    return self.hasRace() or (self.last_set_cycle > self.last_read_cycle);
}
```
**CRITICAL LOGIC:** Returns true if:
- VBlank is active AND either:
  - A race condition occurred (same-cycle read suppresses flag clearing), OR
  - No read has occurred yet (last_set > last_read means flag not cleared by read)

**hasRace()** (line 39-41):
```zig
pub inline fn hasRace(self: VBlankLedger) bool {
    return self.last_race_cycle >= self.last_set_cycle;
}
```
Returns true if a race read happened within current VBlank span.

---

## Part 2: NMI Control Flow

### NMI Line Assertion (File: `/home/colin/Development/RAMBO/src/emulation/cpu/execution.zig`, lines 93-110)

**Every CPU cycle**, the stepCycle() function checks:
```zig
const vblank_flag_visible = state.vblank_ledger.isFlagVisible();
const nmi_line_should_assert = vblank_flag_visible and
    state.ppu.ctrl.nmi_enable and
    !state.vblank_ledger.hasRace();

state.cpu.nmi_line = nmi_line_should_assert;
```

**CRITICAL BUG IDENTIFIED:** The NMI line assertion has THREE conditions:
1. VBlank flag is visible (isFlagVisible())
2. NMI enabled in PPUCTRL (nmi_enable)
3. **NOT in race condition** (!hasRace())

The third condition is WRONG. When hasRace() is true, it means:
- A race read occurred at the exact cycle VBlank was set
- The race read DID see the VBlank flag SET
- NMI should be held asserted to fire next cycle

**Current code:** Clears NMI when hasRace() is true (inverted logic!)

### NMI Enable Edge Trigger (File: `/home/colin/Development/RAMBO/src/emulation/State.zig`, lines 411-423)

**When writing to PPUCTRL ($2000):**
```zig
if (reg == 0x00) {
    const old_nmi_enable = self.ppu.ctrl.nmi_enable;
    const new_nmi_enable = (value & 0x80) != 0;
    const vblank_flag_visible = self.vblank_ledger.isFlagVisible();

    // Edge trigger: 0→1 transition while VBlank flag is visible triggers immediate NMI
    if (!old_nmi_enable and new_nmi_enable and vblank_flag_visible) {
        self.cpu.nmi_line = true;
    }
}
```

This correctly implements the edge trigger: enabling NMI (0→1) while VBlank flag is visible immediately sets NMI line.

---

## Part 3: $2002 (PPUSTATUS) Read Handling

### Read Path 1: busRead() via CPU (File: `/home/colin/Development/RAMBO/src/emulation/State.zig`, lines 268-366)

**Entry point:** `busRead(address: u16) -> u8`

**Steps:**
1. Detect if this is a $2002 read: `is_status_read = (address & 0x0007) == 0x0002` (line 286)
2. If $2002 read, check for race condition (lines 290-300):
   ```zig
   if (is_status_read) {
       const now = self.clock.ppu_cycles;
       const last_set = self.vblank_ledger.last_set_cycle;
       const last_clear = self.vblank_ledger.last_clear_cycle;
       if (last_set > last_clear and now >= last_set) {
           const delta = now - last_set;
           if (delta <= 2) {
               self.vblank_ledger.last_race_cycle = last_set;
           }
       }
   }
   ```
3. Call `PpuLogic.readRegister()` (line 302)
4. If result has `read_2002 = true`, update ledger (lines 352-356):
   ```zig
   if (ppu_read_result) |result| {
       if (result.read_2002) {
           const now = self.clock.ppu_cycles;
           self.vblank_ledger.last_read_cycle = now;  // <-- LINE 355
       }
   }
   ```

### Read Path 2: PpuLogic.readRegister() (File: `/home/colin/Development/RAMBO/src/ppu/logic/registers.zig`, lines 54-175)

**Entry point:** `readRegister(state, cart, address, vblank_ledger) -> PpuReadResult`

**For $2002 (lines 80-107):**
```zig
0x0002 => {
    // $2002 PPUSTATUS - Read-only
    const vblank_active = vblank_ledger.isFlagVisible();
    
    const value = buildStatusByte(
        state.status.sprite_overflow,
        state.status.sprite_0_hit,
        vblank_active,
        state.open_bus.value,
    );
    
    result.read_2002 = true;  // <-- Signal read occurred
    state.internal.resetToggle();
    state.open_bus.write(value);
    
    result.value = value;
}
```

Sets `result.read_2002 = true` to signal the orchestrator to update the ledger.

---

## Part 4: VBlank Set and Clear Events

### VBlank SET (File: `/home/colin/Development/RAMBO/src/emulation/State.zig`, lines 658-662)

**When:** PPU reports `nmi_signal` at scanline 241, dot 1

```zig
if (result.nmi_signal) {
    // VBlank flag set at scanline 241 dot 1.
    self.vblank_ledger.last_set_cycle = self.clock.ppu_cycles;
    self.vblank_ledger.last_race_cycle = 0;  // <-- BUG: Race state cleared!
}
```

**BUG:** Clears `last_race_cycle = 0` immediately when VBlank is set.
- This is premature - race condition lasts multiple cycles
- Should only clear race state when VBlank is cleared

### VBlank CLEAR (File: `/home/colin/Development/RAMBO/src/emulation/State.zig`, lines 664-668)

**When:** PPU reports `vblank_clear` at scanline 261, dot 1

```zig
if (result.vblank_clear) {
    // VBlank span ends at scanline 261 dot 1 (pre-render).
    self.vblank_ledger.last_clear_cycle = self.clock.ppu_cycles;
    self.vblank_ledger.last_race_cycle = 0;  // <-- Correct: clear race state on VBlank clear
}
```

---

## Part 5: Root Cause Analysis - Why Subtests 5 & 6 Fail

### Test Scenario: NMI Re-enable During VBlank

From investigation document: Subtests 5 & 6 check NMI re-enable timing.

**Game code pattern:**
```
1. Game reads $2002 (clears VBlank flag by updating last_read_cycle)
2. Game disables NMI (writes $00 to PPUCTRL bit 7)
3. Game re-enables NMI (writes $80 to PPUCTRL bit 7)
```

**Expected hardware behavior:**
- After step 1: VBlank flag should be hidden (last_read > last_set)
- After step 2: NMI line should be deasserted (disabled)
- After step 3: NMI line should stay deasserted because flag is hidden

**Actual emulator behavior:**
- `last_read_cycle` remains at initial read value (never updated on subsequent reads!)
- isFlagVisible() returns true (because last_set > last_read is still true from first read)
- NMI stays asserted even though game expects suppression

### Root Causes

**BUG #1: Race State Cleared Too Early (Line 661)**
```zig
if (result.nmi_signal) {
    self.vblank_ledger.last_set_cycle = self.clock.ppu_cycles;
    self.vblank_ledger.last_race_cycle = 0;  // <-- WRONG: Clears too soon
}
```

The race state should NOT be cleared when VBlank is set. It should only be cleared when VBlank is cleared (line 667). This causes hasRace() to return false immediately after VBlank starts, even if a race read occurred.

**BUG #2: NMI Line Assertion Logic Inverted (Line 108)**
```zig
const nmi_line_should_assert = vblank_flag_visible and
    state.ppu.ctrl.nmi_enable and
    !state.vblank_ledger.hasRace();  // <-- INVERTED LOGIC
```

This line DEASSERTS NMI when a race condition exists. But race conditions are supposed to HOLD the flag visible, not suppress it!

The logic should be:
- If race occurred: always keep NMI asserted (to fire on next cycle)
- If no race: NMI asserts normally based on isFlagVisible()

Current code does the opposite.

**BUG #3: Multiple $2002 Reads Don't Update Ledger**

From investigation: "last_read_cycle remains 528912 even after subsequent $2002 reads"

The ledger update happens here (State.zig lines 352-356):
```zig
if (ppu_read_result) |result| {
    if (result.read_2002) {
        const now = self.clock.ppu_cycles;
        self.vblank_ledger.last_read_cycle = now;
    }
}
```

This should update on EVERY $2002 read. But the investigation shows it doesn't.

**Possible paths where update is missed:**
1. CPU fetches during addressing modes might not go through this exact code path
2. Dummy reads (page crossing, RMW instructions) may not set `result.read_2002`
3. Some addressing mode fetches might read $2002 but not update the ledger

---

## Part 6: Code Path Audit - Where $2002 Reads Happen

### Path 1: Normal CPU Execution (SAFE)
- CPU calls `state.busRead(0x2002)` during instruction execution
- busRead() detects `is_status_read = true`
- Calls `PpuLogic.readRegister()`
- Returns `PpuReadResult` with `read_2002 = true`
- busRead() updates `last_read_cycle` (line 355)
- **Status:** Updates ledger correctly

### Path 2: Harness ppuReadRegister() (SAFE)
- Harness calls `self.state.busRead(address)` (Harness.zig line 124)
- Same as Path 1
- **Status:** Updates ledger correctly

### Path 3: CPU Addressing Modes - Dummy Reads (UNCERTAIN)
- Some addressing modes perform dummy reads during fetch phase
- Example: Indirect,X addressing reads wrong page then correct page
- These dummy reads might hit $2002 if address happens to be there
- **Question:** Do all dummy reads check for $2002 specifically?
- **Answer:** Yes - busRead() checks every read address (line 286)
- **Status:** Should update ledger, needs verification

### Path 4: RMW Cycle Sequence (UNCERTAIN)
- RMW instructions (ASL, INC, DEC, etc.) do: read, dummy write, final write
- Investigation document mentions RMW may double-read operands
- If double-read bypasses ledger update, $2002 reads wouldn't update
- **Status:** SUSPECT - Investigation document flags this as RMW execute path issue

---

## Part 7: Suppression Logic Timeline

### Correct Suppression Sequence (Expected)

**Cycle 1: VBlank starts (scanline 241, dot 1)**
- `last_set_cycle = C1`
- `last_clear_cycle = C0` (from previous frame)
- `isFlagVisible()` returns true (C1 > C0)

**Cycle 2: Game reads $2002**
- `last_read_cycle = C2`
- `isFlagVisible()` returns true (C1 > C2? No! C1 < C2)
  - WAIT: If read happens AFTER set, then last_set < last_read
  - So isFlagVisible() should return FALSE (flag is suppressed)

**Cycles 3+: Subsequent reads**
- Game reads $2002 again
- `last_read_cycle = C3` (should be updated!)
- `isFlagVisible()` still returns false

### Actual Behavior (Buggy)

**Cycle 1: VBlank starts**
- `last_set_cycle = C1`
- `last_race_cycle = 0` (CLEARED too early!)

**Cycle 2: Game reads $2002**
- `last_read_cycle = C2`
- `isFlagVisible()` should check: `C1 > C2 or hasRace()`
  - C1 > C2? Depends on exact timing
  - hasRace()? Returns `(0 >= C1)` = FALSE (cleared at C1)

**Cycles 3+: Subsequent reads (THE BUG)**
- Game reads $2002 again
- `last_read_cycle` = ??? (doesn't update!)
- Stays at C2 value from first read

**Why doesn't last_read_cycle update?**

Investigation shows: "last_read_cycle remains 528912 even after subsequent $2002 reads"

This suggests:
1. The second read doesn't call busRead(), OR
2. The second read calls busRead() but `result.read_2002` is false, OR
3. There's a missing code path where second reads happen

---

## Part 8: Race Condition Semantics - CRITICAL ISSUE

### Hardware Behavior (NESDev)

From CLAUDE.md: "NMI Edge Detection"
- NMI triggers on **falling edge** (high → low transition)
- If game reads $2002 on the exact cycle VBlank is SET, the read sees flag=0
- This is called a "race condition read"
- Hardware behavior: The race read prevents the flag from being visible on the PPU bus

### Current Implementation (WRONG)

**VBlankLedger.isFlagVisible():**
```zig
return self.hasRace() or (self.last_set_cycle > self.last_read_cycle);
```

Interprets race as: "make flag visible despite read"
- This is BACKWARDS
- Race should SUPPRESS the flag, not make it visible

**Correct interpretation should be:**
```zig
if (self.hasRace()) return false;  // Race suppresses flag
return self.last_set_cycle > self.last_read_cycle;
```

### Race State Clearing Bug (Line 661)

```zig
if (result.nmi_signal) {
    self.vblank_ledger.last_set_cycle = self.clock.ppu_cycles;
    self.vblank_ledger.last_race_cycle = 0;  // CLEARED IMMEDIATELY
}
```

By clearing race state immediately when VBlank is set, the code loses the "race condition occurred" information. This means:
- Subsequent reads during same VBlank can't tell if a race occurred
- hasRace() returns false for the entire VBlank period

Correct behavior: Race state should persist until VBlank CLEAR (line 667 is correct, line 661 should not clear)

---

## Part 9: Summary of Bugs

| # | Location | Bug | Impact | Severity |
|---|----------|-----|--------|----------|
| 1 | VBlankLedger line 34 | isFlagVisible() returns true when hasRace(), but race should suppress flag | NMI stays asserted when it should be suppressed | CRITICAL |
| 2 | cpu/execution.zig line 108 | !hasRace() deasserts NMI, but race should hold it | NMI is inverted during race conditions | CRITICAL |
| 3 | State.zig line 661 | Clears last_race_cycle when VBlank SET, should only clear on CLEAR | Race state lost immediately, can't be checked later | CRITICAL |
| 4 | State.zig line 355 | last_read_cycle only updated if result.read_2002 is true | Multiple $2002 reads might not update ledger | HIGH |
| 5 | cpu/execution.zig lines 290-300 | Race detection only on delta <= 2 cycles from set | May miss race conditions outside this window | MEDIUM |

---

## Part 10: Evidence from Investigation Document

From `/home/colin/Development/RAMBO/docs/sessions/2025-10-19-dummywrite-nmi-investigation.md`:

**Finding 1:** "last_read_cycle remains 528912 even after subsequent $2002 reads"
- Shows ledger is not updating on all reads
- Indicates missing code path or condition that prevents update

**Finding 2:** "nmi_line still asserted when ROM expects suppression"
- Subtests 5 & 6 fail
- Shows NMI suppression logic is inverted

**Finding 3:** "need to persist the race flag more than one cycle"
- Current code clears race state immediately
- Should persist until VBlank clears

**Finding 4:** "ensure $2002 reads that occur via indirect/dummy paths update last_read_cycle"
- Multiple code paths might not update ledger
- Needs audit of all $2002 access patterns

---

## Part 11: Reproduction Scenario

**Test:** nmi_control_test.zig, Subtests 5 & 6

**ROM Code (reconstructed):**
1. CPU polls $2002 to read VBlank flag (if set, last_read_cycle updates)
2. CPU writes $00 to $2000 (disables NMI)
3. CPU writes $80 to $2000 (enables NMI again)
4. **Expected:** NMI line should stay deasserted (flag already read and suppressed)
5. **Actual:** NMI line remains asserted (flag suppression isn't working)

**Why it fails:**
- Step 1: last_read_cycle set to cycle of first read
- Step 2: No issue, NMI just disabled
- Step 3: When re-enabling, isFlagVisible() still returns true (because last_read_cycle is stale!)
- isFlagVisible() checks: `(last_set_cycle > last_read_cycle)` or hasRace()
- last_set > last_read might still be true if subsequent reads didn't update last_read_cycle
- So flag appears visible, NMI fires again (WRONG!)

---

## Recommendations

### Fix Priority

1. **CRITICAL:** Fix hasRace() logic in isFlagVisible() (invert the condition)
2. **CRITICAL:** Fix NMI line assertion (remove !hasRace() suppression)
3. **CRITICAL:** Stop clearing last_race_cycle at VBlank SET (line 661)
4. **HIGH:** Audit and fix $2002 read path to ensure last_read_cycle always updates
5. **MEDIUM:** Review race detection window (delta <= 2 cycles)

### Proposed Changes

**File: VBlankLedger.zig, line 32-35:**
```zig
pub inline fn isFlagVisible(self: VBlankLedger) bool {
    if (!self.isActive()) return false;
    if (self.hasRace()) return false;  // RACE SUPPRESSES FLAG
    return self.last_set_cycle > self.last_read_cycle;
}
```

**File: cpu/execution.zig, line 105-108:**
```zig
const vblank_flag_visible = state.vblank_ledger.isFlagVisible();
const nmi_line_should_assert = vblank_flag_visible and
    state.ppu.ctrl.nmi_enable;  // REMOVE !hasRace() check
// Race conditions are handled by isFlagVisible() now
```

**File: State.zig, line 658-662:**
```zig
if (result.nmi_signal) {
    self.vblank_ledger.last_set_cycle = self.clock.ppu_cycles;
    // DO NOT clear last_race_cycle here!
}
```

---

