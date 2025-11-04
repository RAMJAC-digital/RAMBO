# Mesen2 vs RAMBO: VBlank/NMI Implementation Comparison

**Date:** 2025-11-02 (Investigation), 2025-11-03 (Resolution)
**Task:** h-fix-oam-nmi-accuracy
**Purpose:** Detailed comparison of VBlank/NMI timing between Mesen2 (reference emulator) and RAMBO

---

## Resolution (2025-11-03)

**Status:** FIXED - VBlank/NMI execution order restructured to match Mesen2

**Changes Implemented:**
1. ✅ CPU execution moved BEFORE VBlank timestamp application (`src/emulation/State.zig:tick()` lines 651-774)
2. ✅ Prevention mechanism now works: CPU sets `prevent_vbl_set_cycle`, then VBlank checks it before setting flag
3. ✅ Interrupt sampling moved AFTER VBlank timestamps are finalized (ensures correct NMI line state)
4. ✅ IRQ masking during NMI fixed: `if (irq_pending_prev and pending_interrupt != .nmi)`

**Result:** Execution order now matches Mesen2's pattern where prevention flag is set BEFORE VBlank set decision

**Reference:** See task file section "2025-11-03: VBlank/NMI Timing Restructuring and IRQ Masking Fix" for complete details

---

## Executive Summary (Original Investigation - 2025-11-02)

This document provides a comprehensive comparison of VBlank flag timing, NMI generation, and race condition handling between Mesen2 and RAMBO. The investigation identified **two critical timing bugs** in RAMBO that cause AccuracyCoin NMI test failures.

**Key Findings:**
1. ✅ DMA time-sharing implementation is correct (matches Mesen2 exactly)
2. 🔴 VBlank race detection window is off by one cycle (FIXED 2025-11-03)
3. 🔴 Missing read-time VBlank masking for $2002 reads (FIXED 2025-11-03)

---

## 1. VBlank Flag Set/Clear Timing

### Hardware Specification (nesdev.org)

- **VBlank set:** Scanline 241, dot 1
- **VBlank clear (timing):** Scanline -1 (pre-render), dot 1
- **VBlank clear (read):** Reading $2002 clears the flag immediately

### Mesen2 Implementation

**File:** `/home/colin/Development/Mesen2/Core/NES/NesPpu.cpp`

**VBlank Set (lines 1339-1344):**
```cpp
if(_cycle == 1 && _scanline == _nmiScanline) {
    if(!_preventVblFlag) {
        _statusFlags.VerticalBlank = true;  // Set at scanline 241, cycle 1
        BeginVBlank();                       // Triggers NMI immediately
    }
    _preventVblFlag = false;
}
```

**VBlank Clear (lines 887-892):**
```cpp
if(_scanline >= 0) {
    ((T*)this)->DrawPixel();
    ShiftTileRegisters();
    ProcessSpriteEvaluation();
} else if(_cycle < 9) {
    //Pre-render scanline logic
    if(_cycle == 1) {
        _statusFlags.VerticalBlank = false;  // Cleared at pre-render, cycle 1
        _console->GetCpu()->ClearNmiFlag();
    }
}
```

**Implementation Pattern:**
- Uses boolean flag (`_statusFlags.VerticalBlank`)
- Direct flag manipulation (set/clear)
- Immediate NMI trigger on VBlank set

### RAMBO Implementation

**File:** `src/emulation/State.zig:tick` via `applyPpuCycleResult`

**VBlank Set:**
```zig
// VBlank flag set (scanline 241, dot 1)
if (ppu_result.set_vblank) {
    self.vblank_ledger.last_set_cycle = self.clock.ppu_cycles;
}
```

**VBlank Clear:**
```zig
// VBlank flag cleared by timing (scanline 261, dot 1)
if (ppu_result.clear_vblank) {
    self.vblank_ledger.last_clear_cycle = self.clock.ppu_cycles;
}
```

**File:** `src/emulation/VBlankLedger.zig`

**Flag State Query:**
```zig
pub inline fn isFlagVisible(self: VBlankLedger) bool {
    // 1. VBlank span not active?
    if (!self.isActive()) return false;

    // 2. Has any $2002 read occurred since VBlank set?
    if (self.last_read_cycle >= self.last_set_cycle) return false;

    // 3. Flag is set and hasn't been read yet
    return true;
}
```

**Implementation Pattern:**
- Uses timestamp-based ledger (functional pattern)
- Flag state computed from timestamp comparisons
- NMI triggered when ledger indicates VBlank active

### Comparison

| Aspect | Mesen2 | RAMBO | Match? |
|--------|--------|-------|--------|
| Set timing | Scanline 241, cycle 1 | Scanline 241, dot 1 | ✅ Yes |
| Clear timing | Scanline 261, cycle 1 | Scanline 261, dot 1 | ✅ Yes |
| Representation | Boolean flag | Timestamp comparison | ⚠️ Functionally equivalent |
| Clear on $2002 read | Immediate set to false | Timestamp update | ⚠️ Functionally equivalent |

**Verdict:** Basic VBlank timing is **correct** in RAMBO. Different representation (boolean vs. timestamp) but functionally equivalent.

---

## 2. VBlank Race Condition (Critical Issue #1) 🔴

### Hardware Behavior (nesdev.org/wiki/PPU_frame_timing)

> Reading one PPU clock **before** reads it as clear and never sets the flag or generates NMI for that frame.
>
> Reading the same clock or one later reads as set, clears the flag, and suppresses NMI for that frame.

**Race Window:** Cycles 0-2 of scanline 241

### Mesen2 Implementation

**File:** `/home/colin/Development/Mesen2/Core/NES/NesPpu.cpp`

**Race Prevention (lines 585-594):**
```cpp
void NesPpu::UpdateStatusFlag()
{
    _statusFlags.VerticalBlank = false;  // Clear flag
    _console->GetCpu()->ClearNmiFlag();  // Clear CPU NMI signal

    if(_scanline == _nmiScanline && _cycle == 0) {
        //"Reading one PPU clock before reads it as clear and never sets
        // the flag or generates NMI for that frame."
        _preventVblFlag = true;  // Prevent flag set at next cycle (cycle 1)
    }
}
```

**Key Points:**
- Checks if read happens at cycle **0** (one cycle BEFORE VBlank set at cycle 1)
- Sets `_preventVblFlag = true` to prevent flag set on next cycle
- Result: VBlank flag never sets, NMI never fires

**Read-Time Masking (lines 290-292):**
```cpp
if(_scanline == _nmiScanline && _cycle < 3) {
    //Clear vertical blank flag in return value
    returnValue &= 0x7F;  // Mask bit 7 (VBlank) in return value
}
```

**Key Points:**
- Applies to reads at cycles 0, 1, or 2 of scanline 241
- Clears VBlank bit in **return value only**
- Internal flag state unchanged
- CPU sees VBlank=0 even if flag is set internally

### RAMBO Implementation

**File:** `src/emulation/State.zig:tick` (lines 617-699)

**Race Detection:**
```zig
// Step 2: Handle $2002 read (before PPU flag updates)
if (cpu_result.read_2002) {
    // Race detection: Is this read at exact VBlank set cycle?
    const is_race = (self.clock.ppu_cycles == self.vblank_ledger.last_set_cycle);

    if (is_race) {
        self.vblank_ledger.last_race_cycle = self.clock.ppu_cycles;
    }

    // Record read timestamp (clears flag)
    self.vblank_ledger.last_read_cycle = self.clock.ppu_cycles;
}

// Step 3: PPU tick (flag updates happen here)
const ppu_result = self.stepPpuCycle();
```

**File:** `src/emulation/VBlankLedger.zig` (lines 47-53)

**Race Suppression:**
```zig
pub inline fn hasRaceSuppression(self: VBlankLedger) bool {
    return self.last_race_cycle == self.last_set_cycle;
}
```

### Critical Differences 🔴

| Aspect | Mesen2 | RAMBO | Issue? |
|--------|--------|-------|--------|
| Race detection cycle | Cycle **0** (before set) | **Exact set cycle** (cycle 1) | 🔴 **OFF BY ONE** |
| Detection window | Cycles 0-2 | Exact cycle only | 🔴 **TOO NARROW** |
| Prevention method | Boolean flag prevents set | Timestamp suppresses NMI | ⚠️ Equivalent if timing correct |
| Read value masking | Returns VBlank=0 for cycles 0-2 | Returns actual flag state | 🔴 **MISSING** |

### Root Cause Analysis

**Problem 1: Race Detection One Cycle Too Late**

Mesen2 checks: `_cycle == 0` (read happens BEFORE set)
RAMBO checks: `ppu_cycles == last_set_cycle` (read happens AT set)

Hardware behavior: "Reading one PPU clock **before**" → implies detection at cycle 0, not cycle 1.

**Problem 2: No Read-Time Masking**

Mesen2 masks return value: `returnValue &= 0x7F` when `_cycle < 3`
RAMBO has no equivalent masking

Result: CPU sees VBlank=1 when hardware would return VBlank=0.

---

## 3. NMI Generation and Edge Detection

### Hardware Specification (nesdev.org/wiki/NMI)

- **Trigger:** "Start of vertical blanking (scanline 240, dot 1): Set vblank_flag in PPU to true"
- **Edge Type:** Falling edge (active-low /NMI line: high → low transition)
- **Polling:** "This edge detector polls the status of the NMI line during φ2 of each CPU cycle"
- **Race:** "If 1 and 3 happen simultaneously, PPUSTATUS bit 7 is read as false, and vblank_flag is set to false anyway"

### Mesen2 Implementation

**File:** `/home/colin/Development/Mesen2/Core/NES/NesCpu.cpp` (lines 294-315)

**NMI Edge Detection (at end of CPU cycle):**
```cpp
void NesCpu::EndCpuCycle(bool forRead)
{
    _masterClock += forRead ? (_endClockCount + 1) : (_endClockCount - 1);
    _console->GetPpu()->Run(_masterClock - _ppuOffset);

    //"This edge detector polls the status of the NMI line during φ2 of each CPU cycle"
    _prevNeedNmi = _needNmi;

    if(!_prevNmiFlag && _state.NmiFlag) {
        _needNmi = true;  // Falling edge detected
    }
    _prevNmiFlag = _state.NmiFlag;

    // IRQ (level triggered)
    _prevRunIrq = _runIrq;
    _runIrq = ((_state.IrqFlag & _irqMask) > 0 && !CheckFlag(PSFlags::Interrupt));
}
```

**NMI Triggering (from PPU):**
```cpp
void NesPpu::TriggerNmi()
{
    if(_control.NmiOnVerticalBlank) {
        _console->GetCpu()->SetNmiFlag();  // Sets NmiFlag immediately
    }
}
```

**Timing:**
- Edge detection happens at **end of CPU cycle** (φ2 phase)
- Detects `false → true` transition (`!_prevNmiFlag && _state.NmiFlag`)
- Sets `_needNmi` flag which is checked at start of next cycle

### RAMBO Implementation

**File:** `src/cpu/Logic.zig` (lines 56-81)

**NMI Edge Detection:**
```zig
pub fn checkInterrupts(state: *CpuState, vblank_set_cycle: u64) void {
    // NMI edge detection (falling edge)
    const nmi_prev = state.nmi_edge_detected;
    state.nmi_edge_detected = state.nmi_line;

    if (state.nmi_line and !nmi_prev) {
        // Double-trigger suppression
        const same_vblank = (vblank_set_cycle == state.nmi_vblank_set_cycle and
                             vblank_set_cycle != 0);

        if (!same_vblank) {
            state.pending_interrupt = .nmi;
            state.nmi_vblank_set_cycle = vblank_set_cycle;
        }
    }

    // IRQ level-triggered
    if (state.irq_line and !state.p.i) {
        state.pending_interrupt = .irq;
    }
}
```

**File:** `src/emulation/cpu/execution.zig` (lines 93-112)

**NMI Line Management:**
```zig
// NMI line reflects VBlank flag state
const vblank_flag_visible = state.vblank_ledger.isFlagVisible();
const race_suppression = state.vblank_ledger.hasRaceSuppression();
const nmi_line_should_assert = vblank_flag_visible and
    state.ppu.ctrl.nmi_enable and
    !race_suppression;

state.cpu.nmi_line = nmi_line_should_assert;
```

**Timing:**
- Called from `executeCycle()` at **start of fetch_opcode state**
- Detects `false → true` transition
- Double-trigger suppression via `nmi_vblank_set_cycle`

### Comparison

| Aspect | Mesen2 | RAMBO | Match? |
|--------|--------|-------|--------|
| Edge type | Falling (false → true) | Falling (false → true) | ✅ Same |
| Detection timing | End of cycle (φ2) | Start of fetch_opcode | ⚠️ May differ |
| Double-trigger prevention | Via `_needNmi` persistence | Via `nmi_vblank_set_cycle` | ✅ Equivalent |
| Race suppression | Via `_preventVblFlag` | Via `hasRaceSuppression()` | ⚠️ See Issue #1 |

**Potential Issue:** Mesen2 checks NMI at **end of cycle** after PPU has run, RAMBO checks at **start of instruction fetch**. Timing relative to VBlank flag set may differ.

---

## 4. CPU/PPU Sub-Cycle Execution Ordering

### Mesen2 Implementation

**File:** `/home/colin/Development/Mesen2/Core/NES/NesCpu.cpp` (lines 254-323)

**Execution Order Within Memory Operation:**
```
START OF MEMORY ACCESS
│
├─ StartCpuCycle(forRead)
│  ├─ Update master clock
│  └─ PPU->Run()  ← PPU EXECUTES (1-3 PPU cycles)
│
├─ Memory Operation (read/write $2002, etc.)
│  └─ Actual bus access
│
└─ EndCpuCycle(forRead)
   ├─ Update master clock (additional)
   ├─ PPU->Run()  ← PPU EXECUTES AGAIN (1-3 PPU cycles)
   └─ NMI Edge Detection happens HERE
```

**Key Points:**
- PPU runs **twice** per CPU memory operation (before + after)
- NMI edge detection at **end of CPU cycle**
- VBlank flag can be set during either PPU run

### RAMBO Implementation

**File:** `src/emulation/State.zig:tick` (lines 617-699)

**Execution Order:**
```zig
pub fn tick(self: *EmulationState) void {
    // Step 1: CPU execution (including memory operations)
    const cpu_result = self.stepCpuCycle();

    // Step 2: Handle $2002 read (before PPU flag updates)
    if (cpu_result.read_2002) {
        const is_race = (self.clock.ppu_cycles == self.vblank_ledger.last_set_cycle);
        if (is_race) {
            self.vblank_ledger.last_race_cycle = self.clock.ppu_cycles;
        }
        self.vblank_ledger.last_read_cycle = self.clock.ppu_cycles;
    }

    // Step 3: PPU tick (flag updates happen here)
    const ppu_result = self.stepPpuCycle();

    // Step 4: Apply PPU results (VBlank timestamps)
    self.applyPpuCycleResult(ppu_result);
}
```

**Key Points:**
- CPU executes **before** PPU within same master clock cycle
- $2002 read handling happens **before** PPU flag update
- PPU runs **once** per master clock tick

### Comparison

| Aspect | Mesen2 | RAMBO | Impact |
|--------|--------|-------|--------|
| PPU execution frequency | Twice per CPU cycle | Once per master cycle | ⚠️ May affect race timing |
| VBlank update timing | During PPU run (before/after CPU) | After CPU completes | ⚠️ Ordering difference |
| $2002 read handling | Immediate flag clear | Timestamp update before PPU | ⚠️ May affect race detection |
| NMI edge detection | At end of CPU cycle | During executeCycle | ⚠️ Timing may differ |

**Analysis:** RAMBO's single PPU execution per master cycle is simpler but may have different race condition behavior than Mesen2's dual execution model.

---

## 5. DMA Implementation (VERIFIED CORRECT ✅)

### Mesen2 Implementation

**File:** `/home/colin/Development/Mesen2/Core/NES/NesCpu.cpp` (lines 385-397)

**Time-Sharing Comment:**
```cpp
auto processCycle = [this] {
    //Sprite DMA cycles count as halt/dummy cycles for the DMC DMA
    if(_abortDmcDma) {
        _dmcDmaRunning = false;
        _abortDmcDma = false;
        _needDummyRead = false;
        _needHalt = false;
    } else if(_needHalt) {
        _needHalt = false;
    } else if(_needDummyRead) {
        _needDummyRead = false;
    }
    StartCpuCycle(true);
};
```

**DMC/OAM Interaction (lines 399-448):**
```cpp
while(_dmcDmaRunning || _spriteDmaTransfer) {
    bool getCycle = (_state.CycleCount & 0x01) == 0;

    if(_dmcDmaRunning && !_needHalt && !_needDummyRead) {
        // DMC read cycle (blocks OAM)
        processCycle();
        readValue = ProcessDmaRead(...);
        _dmcDmaRunning = false;
    } else if(_spriteDmaTransfer) {
        // OAM DMA can proceed during DMC halt/dummy cycles
        processCycle();
        if(getCycle) {
            // OAM read
            readValue = ProcessDmaRead(_spriteDmaOffset * 0x100 + spriteReadAddr, ...);
            spriteReadAddr++;
        } else {
            // OAM write
            _console->GetPpu()->WriteRam(0x2004, readValue);
            spriteWriteAddr++;
        }
    } else {
        // Alignment cycle
        processCycle();
    }
}
```

### RAMBO Implementation

**File:** `src/emulation/dma/logic.zig` (lines 24-48)

**Time-Sharing Logic:**
```zig
// Hardware time-sharing behavior per nesdev.org:
// DMC DMA cycle breakdown (stall_cycles_remaining countdown):
//   Cycle 4 (halt):      OAM continues ✓
//   Cycle 3 (dummy):     OAM continues ✓
//   Cycle 2 (alignment): OAM continues ✓
//   Cycle 1 (read):      OAM PAUSES ✗
const dmc_is_stalling_oam = state.dmc_dma.rdy_low and
    state.dmc_dma.stall_cycles_remaining == 1;

if (dmc_is_stalling_oam) return;  // OAM paused during DMC read
```

### Comparison

| Aspect | Mesen2 | RAMBO | Match? |
|--------|--------|-------|--------|
| Time-sharing | OAM advances during DMC halt/dummy | OAM advances during stall 4,3,2 | ✅ Identical |
| OAM blocking | Only during DMC read | Only during stall == 1 | ✅ Identical |
| DMC sequence | halt → dummy → alignment → read | 4 → 3 → 2 → 1 (countdown) | ✅ Equivalent |
| Post-DMC alignment | Automatic via processCycle | Explicit `needs_alignment_after_dmc` | ✅ Equivalent |

**Verdict:** DMA implementations are **functionally identical**. RAMBO's implementation is hardware-accurate.

---

## 6. Open Bus Behavior

### Mesen2 Implementation

**File:** `/home/colin/Development/Mesen2/Core/NES/OpenBusHandler.h`

**Dual Open Bus Tracking:**
```cpp
class OpenBusHandler {
private:
    uint8_t _externalOpenBus = 0;  // External bus (CPU memory bus)
    uint8_t _internalOpenBus = 0;  // Internal bus ($4015 special case)

public:
    void SetOpenBus(uint8_t value, bool setInternalOnly) {
        if(!setInternalOnly) {
            _externalOpenBus = value;
        }
        _internalOpenBus = value;
    }
};
```

**File:** `/home/colin/Development/Mesen2/Core/NES/NesPpu.cpp` (lines 221-253)

**Per-Bit Decay:**
```cpp
void NesPpu::SetOpenBus(uint8_t mask, uint8_t value)
{
    if(mask == 0xFF) {
        // Shortcut: all bits updated
        _openBus = value;
        for(int i = 0; i < 8; i++) {
            _openBusDecayStamp[i] = _frameCount;
        }
    } else {
        // Per-bit decay tracking
        for(int i = 0; i < 8; i++) {
            if(mask & 0x01) {
                // Update this bit and its timestamp
                _openBusDecayStamp[i] = _frameCount;
            } else if(_frameCount - _openBusDecayStamp[i] > 3) {
                // Decay bit to 0 after 3 frames
                openBus &= 0xFF7F;
            }
            value >>= 1;
            mask >>= 1;
        }
    }
}
```

**Decay Properties:**
- Per-bit decay tracking (each bit has independent decay timer)
- 3-frame decay duration
- Frame-based timestamp tracking

### RAMBO Implementation

**Status:** Implementation details need verification. RAMBO has open bus tracking but needs comparison with Mesen2's per-bit decay approach.

---

## 7. Fixes Required

### Fix #1: VBlank Race Detection Window 🔴

**Current Implementation (`src/emulation/State.zig`):**
```zig
const is_race = (self.clock.ppu_cycles == self.vblank_ledger.last_set_cycle);
```

**Required Fix:**
```zig
// Detect reads BEFORE VBlank set (cycle 0) or within race window (cycles 0-2)
// VBlank sets at dot 1, so race window is dots 0, 1, 2 of scanline 241
const is_race_window = (scanline == 241 and dot >= 0 and dot <= 2);
```

**Implementation Approach:**
1. Add scanline/dot fields to $2002 read result
2. Check if read occurs during race window (scanline 241, dots 0-2)
3. Set `last_race_cycle` if within window
4. Prevent VBlank flag set if read at dot 0

### Fix #2: Read-Time VBlank Masking 🔴

**Current Implementation (`src/ppu/logic/registers.zig`):**
```zig
0x0002 => {
    // $2002 PPUSTATUS
    const vblank_active = vblank_ledger.isFlagVisible();

    const value = buildStatusByte(
        state.status.sprite_overflow,
        state.status.sprite_0_hit,
        vblank_active,
        state.open_bus.value,
    );

    result.read_2002 = true;
    state.internal.resetToggle();
    state.open_bus.write(value);
    result.value = value;
}
```

**Required Fix:**
```zig
0x0002 => {
    // $2002 PPUSTATUS
    const vblank_active = vblank_ledger.isFlagVisible();

    var value = buildStatusByte(
        state.status.sprite_overflow,
        state.status.sprite_0_hit,
        vblank_active,
        state.open_bus.value,
    );

    // CRITICAL: Mask VBlank bit during race window
    // Hardware returns VBlank=0 even if flag is set internally
    // Per Mesen2 NesPpu.cpp:290-292
    const in_race_window = (state.scanline == 241 and state.dot < 3);
    if (in_race_window) {
        value &= 0x7F;  // Clear bit 7 (VBlank)
    }

    result.read_2002 = true;
    state.internal.resetToggle();
    state.open_bus.write(value);
    result.value = value;
}
```

---

## 8. Testing Plan

### AccuracyCoin NMI Tests

Run these specific tests after implementing fixes:

```bash
zig build test -- nmi
```

**Expected to pass after fixes:**
- `NMI CONTROL` - Currently FAIL (err=7)
- `NMI AT VBLANK END` - Currently FAIL (err=1)
- `NMI DISABLED AT VBLANK` - Currently FAIL (err=1)

### Regression Testing

```bash
zig build test
```

**Expected:** 1023+ tests still passing (no regressions)

### Commercial ROM Validation

Test against games known to have VBlank timing sensitivity:
- Super Mario Bros. 3 (checkered floor issue)
- Kirby's Adventure (dialog box issue)

---

## 9. References

### Mesen2 Source Files

- `/home/colin/Development/Mesen2/Core/NES/NesPpu.h` - PPU state
- `/home/colin/Development/Mesen2/Core/NES/NesPpu.cpp` - VBlank/race logic
- `/home/colin/Development/Mesen2/Core/NES/NesCpu.h` - CPU state
- `/home/colin/Development/Mesen2/Core/NES/NesCpu.cpp` - NMI edge detection, DMA
- `/home/colin/Development/Mesen2/Core/NES/OpenBusHandler.h` - Open bus tracking

### Hardware Documentation

- [nesdev.org/wiki/PPU_frame_timing](https://www.nesdev.org/wiki/PPU_frame_timing) - VBlank timing specification
- [nesdev.org/wiki/NMI](https://www.nesdev.org/wiki/NMI) - NMI behavior and race conditions
- [nesdev.org/wiki/DMA](https://www.nesdev.org/wiki/DMA) - OAM DMA and DMC DMA time-sharing
- [forums.nesdev.org/viewtopic.php?t=6186](https://forums.nesdev.org/viewtopic.php?t=6186) - CPU/PPU sub-cycle ordering
- [forums.nesdev.org/viewtopic.php?t=8216](https://forums.nesdev.org/viewtopic.php?t=8216) - VBlank race condition discussion

### RAMBO Implementation Files

- `src/emulation/State.zig` (lines 617-699) - Main emulation loop
- `src/emulation/VBlankLedger.zig` - VBlank timestamp tracking
- `src/emulation/cpu/execution.zig` - NMI line management
- `src/emulation/dma/logic.zig` - DMA time-sharing
- `src/cpu/Logic.zig` (lines 56-81) - NMI edge detection
- `src/ppu/logic/registers.zig` - PPU register reads

---

## 10. Conclusion

RAMBO's core architecture is sound and closely matches Mesen2's hardware-accurate approach. The DMA implementation is **correct and matches Mesen2 exactly**. However, two critical timing bugs have been identified:

1. **VBlank race detection window is off by one cycle** - detects at exact set cycle instead of one cycle before
2. **Missing read-time VBlank masking** - returns actual flag state instead of masking VBlank bit during race window

These bugs directly explain AccuracyCoin NMI test failures. Implementing the two fixes should resolve the failing tests while maintaining compatibility with existing passing tests.
