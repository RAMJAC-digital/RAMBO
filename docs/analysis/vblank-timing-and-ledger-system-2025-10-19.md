# PPU VBlank Timing and Ledger System - Comprehensive Analysis

**Date:** 2025-10-19
**Project:** RAMBO NES Emulator
**Focus:** Complete VBlank lifecycle with cycle-accurate timing

---

## Executive Summary

The RAMBO emulator uses a **VBlankLedger** data structure to track VBlank timing events with cycle-level precision (master clock granularity). This decouples the hardware-visible VBlank flag from CPU interrupt detection, enabling correct handling of race conditions where a $2002 read occurs on the same cycle VBlank is set. The system is purely functional: the ledger is pure data, and all mutations are coordinated through EmulationState.

---

## 1. VBlank Signal Generation (PPU Level)

### 1.1 When PPU Generates Signals

**File:** `src/ppu/Logic.zig` (lines 387-417)

The PPU tick function generates two critical signals at specific scanline/dot coordinates:

```zig
// Signal VBlank start (scanline 241 dot 1)
if (scanline == 241 and dot == 1) {
    flags.nmi_signal = true;  // Signal edge-triggered NMI
}

// Clear sprite flags and signal VBlank end (scanline 261 dot 1)
if (scanline == 261 and dot == 1) {
    state.status.sprite_0_hit = false;
    state.status.sprite_overflow = false;
    state.internal.resetToggle();
    flags.vblank_clear = true;  // Signal end of VBlank span
}
```

**Key Timing:**
- **VBlank SET:** Scanline 241, dot 1 (PPU cycle 82,181 from frame start)
- **VBlank CLEAR:** Scanline 261, dot 1 (PPU cycle 89,001 from frame start)
- These are raw PPU events, not dependent on CPU state

### 1.2 Signal Processing in EmulationState

**File:** `src/emulation/State.zig` (lines 641-667)

Signals from PPU.tick() are processed in `applyPpuCycleResult()`:

```zig
fn applyPpuCycleResult(self: *EmulationState, result: PpuCycleResult) void {
    if (result.nmi_signal) {
        // VBlank flag set at scanline 241 dot 1
        self.vblank_ledger.last_set_cycle = self.clock.ppu_cycles;
        // DO NOT clear last_race_cycle here - preserve race state
    }

    if (result.vblank_clear) {
        // VBlank span ends at scanline 261 dot 1
        self.vblank_ledger.last_clear_cycle = self.clock.ppu_cycles;
        self.vblank_ledger.last_race_cycle = 0;  // Clear race state
    }
}
```

**Critical Point:** The ledger records timestamps when signals occur, but doesn't directly set/clear the "VBlank flag". The flag is computed on-demand through query functions.

---

## 2. VBlankLedger Data Structure

### 2.1 Definition and Fields

**File:** `src/emulation/VBlankLedger.zig` (lines 10-62)

```zig
pub const VBlankLedger = struct {
    /// Master clock cycle when VBlank was last SET (scanline 241, dot 1)
    last_set_cycle: u64 = 0,

    /// Master clock cycle when VBlank was last CLEARED by timing (scanline 261, dot 1)
    last_clear_cycle: u64 = 0,

    /// Master clock cycle of the last read from PPUSTATUS ($2002)
    last_read_cycle: u64 = 0,

    /// Master clock cycle of a $2002 read that raced with VBlank set
    /// When this equals last_set_cycle, NMI is suppressed for this VBlank span
    last_race_cycle: u64 = 0,

    // ... (methods defined below)
};
```

**Field Meanings:**

| Field | Purpose | When Updated | Notes |
|-------|---------|--------------|-------|
| `last_set_cycle` | Records when VBlank was set | Scanline 241, dot 1 | Master clock timestamp |
| `last_clear_cycle` | Records when VBlank ended by timing | Scanline 261, dot 1 | Independent of reads |
| `last_read_cycle` | Records every $2002 read | During busRead() of $2002 | Updated AFTER read returns value |
| `last_race_cycle` | Records if read occurred on set cycle | Same cycle as set | Enables NMI suppression detection |

### 2.2 State Invariants

The ledger maintains these invariants:

1. **Active VBlank:** `isActive()` returns true when `last_set_cycle > last_clear_cycle`
   - Indicates we're between set (241.1) and clear (261.1)

2. **Flag Visibility:** `isFlagVisible()` returns true when:
   - VBlank is active (set > clear)
   - AND no $2002 read has occurred since set (`last_read_cycle < last_set_cycle`)
   - This is the READABLE flag state

3. **Race Suppression:** `hasRaceSuppression()` returns true when:
   - `last_race_cycle == last_set_cycle`
   - Indicates a read occurred on the exact cycle VBlank was set

---

## 3. VBlank Flag Query Methods

### 3.1 isActive()

**Purpose:** Determine if VBlank span is currently active

```zig
pub inline fn isActive(self: VBlankLedger) bool {
    return self.last_set_cycle > self.last_clear_cycle;
}
```

**Usage:** Core logic for determining if VBlank timing window is open
- Returns true from scanline 241.1 through 261.0 (inclusive)
- Returns false at 261.1 and beyond

### 3.2 isFlagVisible()

**Purpose:** Determine what the $2002 bit 7 read should return

```zig
pub inline fn isFlagVisible(self: VBlankLedger) bool {
    // 1. VBlank span not active?
    if (!self.isActive()) return false;

    // 2. Has any $2002 read occurred since VBlank set?
    // This includes race reads - they clear the flag just like normal reads
    if (self.last_read_cycle >= self.last_set_cycle) return false;

    // 3. Flag is set and hasn't been read yet
    return true;
}
```

**Critical Behavior:**
- Flag can be set at 241.1, but if ANY read occurs at 241.1, the flag clears immediately
- The `>=` comparison covers:
  - Read after set: `last_read_cycle` (e.g., 241.5) >= `last_set_cycle` (241.1) → true
  - Race read: `last_read_cycle` (241.1) >= `last_set_cycle` (241.1) → true (equality case)

### 3.3 hasRaceSuppression()

**Purpose:** Determine if NMI should be suppressed for this VBlank

```zig
pub inline fn hasRaceSuppression(self: VBlankLedger) bool {
    return self.last_race_cycle == self.last_set_cycle;
}
```

**Key Distinction:**
- Race condition does NOT prevent flag clearing
- Race condition ONLY affects NMI generation
- Flag clears identically for race and normal reads
- NMI suppression is a separate concern

---

## 4. $2002 (PPUSTATUS) Read Path

### 4.1 PPU Register Read

**File:** `src/ppu/logic/registers.zig` (lines 60-107)

```zig
pub fn readRegister(
    state: *PpuState,
    cart: ?*AnyCartridge,
    address: u16,
    vblank_ledger: VBlankLedger,
) PpuReadResult {
    const reg = address & 0x0007;

    switch (reg) {
        0x0002 => {  // $2002 PPUSTATUS
            // 1. Query ledger for current VBlank visibility
            const vblank_active = vblank_ledger.isFlagVisible();

            // 2. Build status byte (bit 7 = VBlank, bit 6 = Sprite 0 Hit, bit 5 = Overflow)
            const value = buildStatusByte(
                state.status.sprite_overflow,
                state.status.sprite_0_hit,
                vblank_active,
                state.open_bus.value,
            );

            // 3. Signal that a $2002 read occurred
            result.read_2002 = true;

            // 4. Clear write toggle
            state.internal.resetToggle();

            // 5. Update open bus
            state.open_bus.write(value);

            result.value = value;
        },
        // ... other registers
    }
    return result;
}
```

**Side Effects of $2002 Read:**
1. Returns VBlank flag status (computed from ledger)
2. Signals `read_2002 = true` to orchestrator
3. Clears write toggle (local PPU state)
4. Updates open bus value

### 4.2 Race Detection in busRead()

**File:** `src/emulation/State.zig` (lines 268-364)

When CPU reads a PPU register via busRead():

```zig
pub inline fn busRead(self: *EmulationState, address: u16) u8 {
    // ... (other address routing) ...

    0x2000...0x3FFF => blk: {
        // Check if this is a $2002 read (PPUSTATUS) for race condition handling
        const is_status_read = (address & 0x0007) == 0x0002;

        // CRITICAL: Detect race BEFORE computing flag visibility
        if (is_status_read) {
            const now = self.clock.ppu_cycles;
            const last_set = self.vblank_ledger.last_set_cycle;
            const last_clear = self.vblank_ledger.last_clear_cycle;
            
            if (last_set > last_clear and now == last_set) {
                // Race condition: Read $2002 on EXACT same cycle as VBlank set
                self.vblank_ledger.last_race_cycle = last_set;
            }
        }

        const result = PpuLogic.readRegister(
            &self.ppu,
            cart_ptr,
            address,
            self.vblank_ledger,
        );
        ppu_read_result = result;
        break :blk result.value;
    },

    // ... (rest of routing) ...
};

// After read completes, update ledger with read timestamp
if (ppu_read_result) |result| {
    if (result.read_2002) {
        const now = self.clock.ppu_cycles;
        self.vblank_ledger.last_read_cycle = now;
    }
}
```

**Sequence for $2002 Read:**

```
Cycle N:
  1. Check if race condition (now == last_set_cycle AND VBlank active)
  2. If race: set last_race_cycle = last_set_cycle
  3. Call PpuLogic.readRegister() which calls isFlagVisible()
  4. Build status byte with computed flag value
  5. Return to busRead
  6. Update last_read_cycle = now (AFTER flag is already built from old value!)
```

**Critical Insight:** The read timestamp is recorded AFTER the flag is computed, which is correct because:
- The PPU register read function gets the ledger by value (immutable copy)
- It computes the flag based on old state
- Then busRead() updates the timestamp
- Next read in a later cycle will see updated timestamp

---

## 5. NMI Generation and Edge Detection

### 5.1 NMI Line Management

**File:** `src/emulation/cpu/execution.zig` (lines 93-109)

At the start of each CPU cycle (which happens every 3 PPU cycles):

```zig
// NMI line reflects VBlank flag state (when NMI enabled in PPUCTRL)
// Hardware: NMI line stays asserted as long as:
// 1. VBlank is active (last_set > last_clear)
// 2. NMI is enabled in PPUCTRL
// 3. Not in race condition suppression

const vblank_flag_visible = state.vblank_ledger.isFlagVisible();
const nmi_line_should_assert = vblank_flag_visible and state.ppu.ctrl.nmi_enable;

state.cpu.nmi_line = nmi_line_should_assert;
```

**Key Points:**
- NMI line is updated every CPU cycle
- It's a LEVEL signal, not an edge signal
- It goes HIGH when both conditions met:
  1. VBlank flag is readable
  2. NMI enable is set in PPUCTRL

### 5.2 Edge Detection in CPU

**File:** `src/cpu/Logic.zig` (NMI edge detection during checkInterrupts)

The CPU has a separate edge detector:

```zig
// Check if NMI has asserted (falling edge would be 0→1)
// The CPU latches NMI interrupts on 0→1 edge
```

The edge detector:
- Monitors the NMI line
- Triggers on HIGH→HIGH transition that wasn't previously latched
- Latches as `pending_interrupt = .nmi`
- Once latched, won't fire again until VBlank ends and flag is re-cleared

### 5.3 Race Condition Suppression

**Handling:** Race suppression is checked via `hasRaceSuppression()`

The flow is:
1. $2002 read occurs at scanline 241.1
2. Race detector sets `last_race_cycle = last_set_cycle`
3. Flag is still readable immediately after read (same cycle)
4. But NMI generation logic would check: "Did a race occur?" via `hasRaceSuppression()`
5. If yes, suppress the NMI (currently not fully implemented in shown code)

---

## 6. Complete VBlank Lifecycle Example

### Timeline for SMB Normal Frame

```
Time     | Event                          | Ledger State
---------|--------------------------------|------------------
241.1    | PPU: VBlank set                | last_set = 241.1
         |                                | last_clear = 0
         |                                | isActive() = true
         |                                | isFlagVisible() = true
---------|--------------------------------|------------------
241.5    | CPU reads $2002                | 
         | Flag returned = 1              |
         | (based on ledger at time of    |
         |  read, before update)          | last_read = 241.5
         |                                | isFlagVisible() = false
---------|--------------------------------|------------------
245.0    | CPU reads $2002 again          | 
         | Flag returned = 0              |
         | (flag already cleared by       | last_read = 245.0
         |  previous read)                |
---------|--------------------------------|------------------
261.1    | PPU: VBlank clear              | last_clear = 261.1
         |                                | isActive() = false
         |                                | isFlagVisible() = false
---------|--------------------------------|------------------
261.2+   | Frame 2 visible lines          | (Ledger inactive)
```

### Timeline for Race Condition

```
Time     | Event                          | Ledger State
---------|--------------------------------|------------------
241.1    | PPU: VBlank set                | last_set = 241.1
         |                                | last_clear = 0
---------|--------------------------------|------------------
241.1    | CPU reads $2002 (same cycle!)  | 
         | Flag returned = 1              |
         | Race detected!                 | last_race = 241.1
         |                                | last_read = 241.1
         |                                | isFlagVisible() = false
         |                                | hasRaceSuppression() = true
---------|--------------------------------|------------------
261.1    | PPU: VBlank clear              | last_clear = 261.1
         |                                | last_race = 0 (cleared)
```

---

## 7. Race Condition Details

### 7.1 What is the Race Condition?

**Definition:** A $2002 read occurs on the exact same master clock cycle that VBlank is set.

**Timing Window:**
- VBlank is set at scanline 241.1 (specific master clock cycle)
- CPU read of $2002 can occur within 1 cycle before or after
- If read is at scanline 241.1, it's a race

### 7.2 Hardware Behavior (Per nesdev.org)

From nesdev.org/wiki/PPU_frame_timing:

> "Reading on the same PPU clock or one later reads it as set, clears it, and suppresses the NMI for that frame."

**What this means:**
1. Read on same cycle: Flag reads as SET, gets cleared, NMI suppressed
2. Read one cycle later: Flag reads as SET, gets cleared, NMI suppressed
3. Read two+ cycles later: Flag reads as SET, gets cleared, NMI fires normally

### 7.3 Detection in RAMBO

**File:** `src/emulation/State.zig` (lines 290-297)

```zig
if (is_status_read) {
    const now = self.clock.ppu_cycles;
    const last_set = self.vblank_ledger.last_set_cycle;
    const last_clear = self.vblank_ledger.last_clear_cycle;
    
    if (last_set > last_clear and now == last_set) {
        // Race condition: Read $2002 on EXACT same cycle as VBlank set
        self.vblank_ledger.last_race_cycle = last_set;
    }
}
```

**Current Limitation:**
- Detects exact-cycle race condition (now == last_set)
- Does NOT detect "one cycle later" case
- The "one cycle later" case still needs NMI suppression

**Why This Works:**
- Flag is cleared by ANY read after set (via isFlagVisible())
- NMI suppression needs to know if it was a race
- Race detection marks the ledger, allowing NMI logic to check

### 7.4 Key Distinction

**Flag Clearing vs NMI Suppression:**

```
Flag Clearing:
- ALL reads clear the flag immediately
- Both race and normal reads clear it
- isFlagVisible() handles this uniformly

NMI Suppression:
- ONLY race reads suppress NMI
- Detected via hasRaceSuppression()
- Flag clears the same way either way
```

---

## 8. Code Paths Where $2002 Reads Don't Update Ledger

**Question:** Are there code paths where $2002 reads don't update the ledger?

**Answer:** In the normal emulation path, ALL $2002 reads go through:
1. `EmulationState.busRead()` - which checks for race and records read cycle
2. `PpuLogic.readRegister()` - which signals `read_2002 = true`
3. Back to `busRead()` - which updates `last_read_cycle`

**However**, there's a potential gap:
- Debugger reads via `peekMemory()` do NOT trigger side effects
- They specifically bypass the update path
- This is correct because they should be non-intrusive

```zig
pub inline fn peekMemory(self: *const EmulationState, address: u16) u8 {
    return BusInspection.peekMemory(self, address);
}
```

---

## 9. Detailed Timing Events

### 9.1 Master Clock Cycle Numbers

For standard NTSC frame (262 scanlines × 341 dots):

```
Frame Start (scanline 0, dot 0):  Master clock cycle 0
Scanline 241, dot 1:              Master clock cycle 82,181
Scanline 261, dot 1:              Master clock cycle 89,001
Frame End (scanline 261, dot 340):Master clock cycle 89,341
Frame 2 Start:                    Master clock cycle 89,342
```

**Calculation for scanline S, dot D:**
```
cycle = (S * 341) + D
```

### 9.2 CPU Cycle Mapping

CPU cycles occur every 3 PPU cycles:

```
CPU Cycle 0:  PPU cycles 0, 1, 2 (CPU executes at PPU 0)
CPU Cycle 1:  PPU cycles 3, 4, 5 (CPU executes at PPU 3)
...
```

So VBlank set at PPU cycle 82,181 affects CPU cycles starting at 27,394.

---

## 10. Synchronization Points

### 10.1 Event Ordering Within a Cycle

**File:** `src/emulation/State.zig` tick() method (lines 588-639)

Order matters when multiple things happen:

```zig
// 1. PPU first (may signal VBlank)
const ppu_result = self.stepPpuCycle(scanline, dot);
self.applyPpuCycleResult(ppu_result);

// 2. APU second (generates IRQ)
if (step.apu_tick) {
    const apu_result = self.stepApuCycle();
}

// 3. CPU third (can see PPU/APU state)
if (step.cpu_tick) {
    // CPU sees updated vblank_ledger from PPU
    // CPU reads updated IRQ line from APU
    _ = self.stepCpuCycle();
}
```

**Why This Order:**
- PPU sets VBlank first
- CPU can read it immediately via $2002
- NMI line reflects current state

---

## 11. Test Coverage

### 11.1 VBlank Ledger Tests

**File:** `tests/emulation/state/vblank_ledger_test.zig`

Key test cases:
- Flag set at scanline 241.1
- Flag cleared at scanline 261.1
- First read clears flag
- Subsequent reads see cleared flag
- Race condition - read on same cycle as set
- SMB polling pattern (multiple reads)

### 11.2 PPUSTATUS Polling Tests

**File:** `tests/ppu/ppustatus_polling_test.zig`

- Reading $2002 clears VBlank immediately
- Tight loop can detect VBlank
- Race condition at exact VBlank set point

---

## 12. Summary of Key Findings

### 12.1 Clean Separation of Concerns

| Component | Responsibility |
|-----------|-----------------|
| VBlankLedger | Pure data: timestamps of set/clear/read/race events |
| PPU.tick() | Generates signals at specific scanline/dot coordinates |
| EmulationState | Coordinates signals with ledger and CPU |
| PpuLogic.readRegister() | Computes flag visibility from ledger state |
| CpuExecution | Drives NMI line based on flag visibility |

### 12.2 VBlank Lifecycle

1. **Set:** Scanline 241.1 - ledger.last_set_cycle = now
2. **Query:** Any time - isFlagVisible() computes current state
3. **Read:** CPU reads $2002
   - Race detection checks if now == last_set_cycle
   - Flag computed from old ledger state
   - Timestamp recorded after read returns
4. **Clear:** Scanline 261.1 - ledger.last_clear_cycle = now

### 12.3 Race Condition Handling

- **Detection:** Exact-cycle reads flagged via last_race_cycle
- **Flag Behavior:** All reads clear flag identically
- **NMI Impact:** Race suppresses NMI (separate from flag clearing)
- **Current Limitation:** "One cycle later" race cases not fully handled

### 12.4 Correctness Properties

✓ Flag visibility is purely determined by ledger timestamps
✓ All $2002 reads go through central coordinated path
✓ Race detection happens BEFORE flag is computed
✓ Timing events (set/clear) are decoupled from CPU cycles
✓ Debugger inspection doesn't trigger side effects

---

## Appendix: File Summary

| File | Purpose |
|------|---------|
| `src/emulation/VBlankLedger.zig` | Core data structure (10-62 lines) |
| `src/ppu/logic/registers.zig` | $2002 read path and flag construction |
| `src/ppu/Logic.zig` | PPU tick and signal generation |
| `src/emulation/State.zig` | Emulation orchestration and race detection |
| `src/emulation/cpu/execution.zig` | NMI line management |
| `tests/emulation/state/vblank_ledger_test.zig` | Core VBlank tests |
| `tests/ppu/ppustatus_polling_test.zig` | PPUSTATUS behavior tests |
| `docs/specs/vblank-flag-behavior-spec.md` | Hardware specification |

