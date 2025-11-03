# Mesen2-Validated VBlank/NMI Hardware Specification

**Date:** 2025-11-02
**Source:** Mesen2 v0.7.0+ (reference-accurate NES emulator)
**Purpose:** Ground truth specification for RAMBO VBlank/NMI implementation
**Investigation:** Task h-fix-oam-nmi-accuracy deep research phase

## Overview

This document provides the DEFINITIVE hardware behavior specification for NES VBlank flag and NMI generation, validated against Mesen2's reference-accurate implementation. All behaviors documented here have been verified in Mesen2 source code with line number citations.

**Status:** FINAL - Use as implementation ground truth

---

## 1. VBlank Flag Lifecycle (Mesen2 Lines 1339-1344, 889-891, 585-594)

### State Machine

```
Frame Start (Scanline 0)
  ↓
Visible Scanlines (0-239)
  ↓
Post-Render (240)
  ↓
VBlank Start (241:1) ← FLAG SET HERE (if not prevented)
  ↓
VBlank Period (241-260)
  ↓
Pre-Render (261:1) ← FLAG CLEARED HERE
  ↓
Back to Frame Start
```

### Timing Values

| Event | Scanline | Cycle/Dot | PPU Cycle | Mesen2 Reference |
|-------|----------|-----------|-----------|------------------|
| VBlank flag set | 241 | 1 | 82,182 | NesPpu.cpp:1339 |
| VBlank flag clear (timing) | 261 | 1 | 89,002 | NesPpu.cpp:889 |
| VBlank flag clear ($2002 read) | Any | Any | Any | NesPpu.cpp:587 |

**Calculation:** `PPU cycle = scanline * 341 + dot`

---

## 2. VBlank Flag Prevention Logic (NEW - Missing in RAMBO)

### Mesen2 Implementation (Lines 590-592, 1340-1344)

**Boolean Flag Approach:**
```cpp
// When reading $2002 at scanline 241, cycle 0
if(_scanline == _nmiScanline && _cycle == 0) {
    _preventVblFlag = true;  // Prevent flag set at NEXT cycle
}

// At scanline 241, cycle 1 (VBlank set attempt)
if(!_preventVblFlag) {
    _statusFlags.VerticalBlank = true;  // Only set if not prevented
}
_preventVblFlag = false;  // Clear (one-shot)
```

### Hardware Behavior

**Reading $2002 at scanline 241, dot 0:**
1. CPU reads $2002 → sees VBlank = 0 (not set yet)
2. PPU clears VBlank flag (already 0)
3. **PPU sets prevention for next cycle**
4. Next cycle (dot 1): PPU checks prevention → SKIPS flag set
5. Result: **VBlank flag NEVER sets this frame**
6. Result: **NMI NEVER fires this frame**

### RAMBO Timestamp Pattern (REQUIRED)

```zig
// Add to VBlankLedger
prevent_vbl_set_cycle: u64 = 0

// During $2002 read at 241:0
if (scanline == 241 and dot == 0) {
    prevent_vbl_set_cycle = current_ppu_cycles + 1;  // Prevent NEXT cycle
}

// Before setting last_set_cycle at 241:1
if (current_ppu_cycles != prevent_vbl_set_cycle) {
    last_set_cycle = current_ppu_cycles;  // Only set if not prevented
}

// Clear prevention (one-shot)
if (prevent_vbl_set_cycle != 0 and current_ppu_cycles >= prevent_vbl_set_cycle) {
    prevent_vbl_set_cycle = 0;
}
```

**Key Insight:** User guidance "MC + 1 holds the race" means read at cycle X prevents set at cycle X+1.

---

## 3. Read-Time VBlank Masking (Lines 290-292)

### Mesen2 Implementation

```cpp
if(_scanline == _nmiScanline && _cycle < 3) {
    returnValue &= 0x7F;  // Clear bit 7 (VBlank) in return value
}
```

**Applied When:** Reading $2002 at scanline 241, cycles 0-2
**Effect:** CPU sees VBlank = 0 regardless of internal flag state
**Internal State:** Flag unchanged by masking (separate from flag clearing)

### RAMBO Implementation (Already Correct)

**Location:** `src/ppu/logic/registers.zig:117-119`
```zig
const in_race_window = (scanline == 241 and dot < 3);
if (in_race_window) {
    value &= 0x7F;  // Clear bit 7
}
```

**Status:** ✅ Already implemented correctly

---

## 4. Race Window Behavior Matrix

| Scenario | Mesen2 Behavior | RAMBO Current | RAMBO Required |
|----------|-----------------|---------------|----------------|
| **Read at 241:0** | `_preventVblFlag=true` → flag NOT set | Flag SETS (bug) | Add prevention |
| **Read at 241:1** | Flag clears, NMI suppressed, returns 0 | Same | No change |
| **Read at 241:2** | Flag clears, NMI suppressed, returns 0 | Same | No change |
| **No read** | Flag sets normally, NMI fires | Same | No change |

**Critical Bug:** RAMBO sets `last_set_cycle` unconditionally (`State.zig:732`), even when read at dot 0 should prevent it.

---

## 5. NMI Generation (Lines 1249-1259, 294-315)

### Mesen2 Flow

```cpp
// 1. PPU triggers NMI when flag sets
void TriggerNmi() {
    if(_control.NmiOnVerticalBlank) {
        _console->GetCpu()->SetNmiFlag();  // Sets _state.NmiFlag = true
    }
}

// 2. CPU edge detection (end of each cycle)
if(!_prevNmiFlag && _state.NmiFlag) {
    _needNmi = true;  // Latch NMI request
}
_prevNmiFlag = _state.NmiFlag;

// 3. Interrupt check (after each instruction)
if(_prevNeedNmi) {
    IRQ();  // Actually fire NMI
}
```

### RAMBO Flow (Already Correct)

```zig
// 1. Compute NMI line state
nmi_line = vblank_visible && nmi_enable && !race_suppression

// 2. Edge detection
if (nmi_line && !nmi_prev) {
    if (!same_vblank) {  // Double-trigger prevention
        pending_interrupt = .nmi;
    }
}
```

**Status:** ✅ NMI edge detection logic correct
**Issue:** Inputs are wrong (ledger has incorrect `last_set_cycle`)

---

## 6. NMI Suppression Mechanisms

### Complete Suppression Matrix

| Mechanism | Mesen2 | RAMBO | Effect |
|-----------|--------|-------|--------|
| **Prevention** | `_preventVblFlag` | Missing | Flag never sets → No NMI |
| **Race read** | Flag clears immediately | `hasRaceSuppression()` | NMI suppressed |
| **Normal read** | Flag clears | `last_read_cycle` | No NMI (no flag) |
| **PPUCTRL.7=0** | `ClearNmiFlag()` | `!nmi_enable` | NMI line low |

### Read-Time Clearing (Lines 587-588)

```cpp
_statusFlags.VerticalBlank = false;  // Clear flag
_console->GetCpu()->ClearNmiFlag();  // Clear CPU NMI line
```

**Effect:** Any $2002 read clears BOTH VBlank flag AND NMI signal immediately.

---

## 7. CPU/PPU Sub-Cycle Execution Order

### Mesen2 Memory Operation Order

```
MemoryRead/Write:
  1. StartCpuCycle() → PPU runs (1-3 dots)
  2. Actual memory operation (read/write $2002)
  3. EndCpuCycle() → PPU runs again (1-3 dots)
  4. NMI edge detection
```

**Key:** PPU runs TWICE per CPU memory operation.

### RAMBO Execution Order (Post-2025-10-21 Fix)

```
tick():
  1. stepPpuCycle() → Generate event flags
  2. stepCpuCycle() → CPU memory operations
  3. applyPpuCycleResult() → Update ledger timestamps
```

**Key:** PPU runs once, but timestamp updates happen AFTER CPU.

**Verdict:** ✅ Both achieve correct sub-cycle ordering (CPU reads before flag timestamps update).

---

## 8. Timing Constants

### Verified Values

| Constant | Mesen2 | RAMBO | Match? |
|----------|--------|-------|--------|
| Cycles per scanline | 341 | 341 | ✅ |
| VBlank scanline (NTSC) | 241 | 241 | ✅ |
| VBlank set cycle | 1 | 1 | ✅ |
| Pre-render scanline (NTSC) | 261 | 261 | ✅ |
| Pre-render clear cycle | 1 | 1 | ✅ |

**Calculation Check:**
- Scanline 241, dot 1: `241 * 341 + 1 = 82,182` ✅

---

## 9. Implementation Checklist

### Required Changes

- [ ] **Add `prevent_vbl_set_cycle` field** to `VBlankLedger.zig`
- [ ] **Modify $2002 read logic** (`State.zig:313-325`) to set prevention at dot 0
- [ ] **Add prevention check** before setting `last_set_cycle` (`State.zig:730-733`)
- [ ] **Add prevention clear** logic (one-shot, clear after use)

### Verified Correct (No Changes)

- [x] Read-time VBlank masking (dots 0-2)
- [x] Race suppression logic (`hasRaceSuppression()`)
- [x] NMI edge detection (`checkInterrupts()`)
- [x] CPU/PPU sub-cycle ordering
- [x] Timing constants

---

## 10. Mesen2 Source Code References

### Primary Files

- **NesPpu.cpp:**
  - Lines 585-594: `UpdateStatusFlag()` - $2002 read handling and prevention
  - Lines 1339-1344: VBlank flag set with prevention check
  - Lines 889-891: Pre-render scanline flag clear
  - Lines 290-292: Read-time VBlank masking
  - Lines 1249-1259: `BeginVBlank()` and `TriggerNmi()`

- **NesCpu.cpp:**
  - Lines 294-315: `EndCpuCycle()` - NMI edge detection
  - Lines 178-180: Interrupt check after instruction
  - Lines 198-203: NMI handling in IRQ function

- **BaseNesPpu.h:**
  - Line 74: `bool _preventVblFlag = false;` - Prevention flag declaration

### Key Initialization

- **NesPpu.cpp Line 90:** `_preventVblFlag = false;` (reset)
- **NesPpu.cpp Lines 169, 176:** `_nmiScanline = 241;` (NTSC/PAL)

---

## 11. Hardware Citations

### Primary Sources

1. **nesdev.org/wiki/PPU_frame_timing**
   - "Reading one PPU clock before reads it as clear and never sets the flag or generates NMI for that frame."
   - "Reading on the same PPU clock or one later reads it as set, clears it, and suppresses the NMI for that frame."

2. **nesdev.org/wiki/NMI**
   - "This edge detector polls the status of the NMI line during φ2 of each CPU cycle"
   - "If 1 and 3 happen simultaneously, PPUSTATUS bit 7 is read as false, and vblank_flag is set to false anyway"

3. **Mesen2 Comments (embedded hardware notes)**
   - NesPpu.cpp:591: Hardware quote about race condition
   - NesCpu.cpp:299-305: Hardware timing documentation

---

## 12. Test Validation

### AccuracyCoin Expected Outcomes (After Fix)

| Test | Current | Expected | Requires |
|------|---------|----------|----------|
| VBlank Beginning | FAIL (err=1) | PASS | Prevention logic |
| NMI Control | FAIL (err=7) | PASS | Prevention logic |
| NMI Timing | FAIL (err=1) | PASS | Prevention logic |
| NMI Suppression | FAIL (err=1) | PASS | Prevention logic |
| NMI at VBlank End | FAIL (err=1) | PASS | Prevention logic |
| NMI Disabled VBlank | FAIL (err=1) | PASS | Prevention logic |

**Hypothesis:** All failures trace to missing prevention logic allowing flag to set when it shouldn't.

---

## Conclusion

**Root Cause:** RAMBO is missing VBlank flag prevention logic. When $2002 is read at scanline 241, dot 0, RAMBO:
1. ✅ Correctly masks return value (CPU sees 0)
2. ✅ Correctly records race for NMI suppression
3. ❌ **INCORRECTLY sets `last_set_cycle` at next cycle**

Mesen2 uses `_preventVblFlag` to PREVENT the flag from being set entirely. RAMBO needs equivalent timestamp-based prevention.

**Fix Complexity:** LOW - Add one field and three logic checks
**Impact:** HIGH - Should fix all 6+ failing AccuracyCoin tests
**Risk:** LOW - Changes isolated to VBlankLedger and event application

---

**Document Status:** FINAL
**Validation:** Complete against Mesen2 v0.7.0+
**Next Step:** Implement prevention logic per Section 2
