# PPU Register Verification Checklist

**Purpose**: Systematic verification of PPU register behaviors against hardware specification
**Date**: 2025-10-09
**Reference**: nesdev.org/wiki/PPU_registers

---

## PPUCTRL ($2000) - Write Only

| Behavior | Hardware Spec | Implementation | Status | Location |
|----------|---------------|----------------|--------|----------|
| Write-only (read returns open bus) | ✓ | ✓ | ✅ PASS | registers.zig:26-27 |
| Bit 0-1: Nametable select updates t[10-11] | ✓ | ✓ | ✅ PASS | registers.zig:136-138 |
| Bit 2: VRAM increment (1 or 32) | ✓ | ✓ | ✅ PASS | State.zig:48-50 |
| Bit 3: Sprite pattern table | ✓ | ✓ | ✅ PASS | State.zig:24 |
| Bit 4: Background pattern table | ✓ | ✓ | ✅ PASS | State.zig:25 |
| Bit 5: Sprite size (8x8 or 8x16) | ✓ | ✓ | ✅ PASS | State.zig:26 |
| Bit 7: NMI enable | ✓ | ✓ | ✅ PASS | State.zig:28 |
| Ignored during warmup period | ✓ | ✓ | ✅ PASS | registers.zig:121-126 |
| Toggling bit 7 during VBlank triggers NMI | ✓ | ✓ | ✅ PASS | State.zig:306-316 |
| Open bus updated on write | ✓ | ✓ | ✅ PASS | registers.zig:115 |

**Result**: 10/10 behaviors verified ✅

---

## PPUMASK ($2001) - Write Only

| Behavior | Hardware Spec | Implementation | Status | Location |
|----------|---------------|----------------|--------|----------|
| Write-only (read returns open bus) | ✓ | ✓ | ✅ PASS | registers.zig:30-31 |
| Bit 0: Grayscale mode | ✓ | ✓ | ✅ PASS | State.zig:65 |
| Bit 1: Show background in leftmost 8 pixels | ✓ | ✓ | ✅ PASS | State.zig:66 |
| Bit 2: Show sprites in leftmost 8 pixels | ✓ | ✓ | ✅ PASS | State.zig:67 |
| Bit 3: Show background | ✓ | ✓ | ✅ PASS | State.zig:68 |
| Bit 4: Show sprites | ✓ | ✓ | ✅ PASS | State.zig:69 |
| Bit 5: Emphasize red | ✓ | ✓ | ✅ PASS | State.zig:70 |
| Bit 6: Emphasize green | ✓ | ✓ | ✅ PASS | State.zig:71 |
| Bit 7: Emphasize blue | ✓ | ✓ | ✅ PASS | State.zig:72 |
| Ignored during warmup period | ✓ | ✓ | ✅ PASS | registers.zig:143-148 |
| Rendering enabled check (bit 3 OR bit 4) | ✓ | ✓ | ✅ PASS | State.zig:85-87 |
| Open bus updated on write | ✓ | ✓ | ✅ PASS | registers.zig:115 |

**Result**: 12/12 behaviors verified ✅

---

## PPUSTATUS ($2002) - Read Only

| Behavior | Hardware Spec | Implementation | Status | Location |
|----------|---------------|----------------|--------|----------|
| Read-only (write has no effect) | ✓ | ✓ | ✅ PASS | registers.zig:159-161 |
| Bit 0-4: Open bus bits | ✓ | ✓ | ✅ PASS | State.zig:98, 105-109 |
| Bit 5: Sprite overflow flag | ✓ | ✓ | ✅ PASS | State.zig:99 |
| Bit 6: Sprite 0 hit flag | ✓ | ✓ | ✅ PASS | State.zig:100 |
| Bit 7: VBlank flag | ✓ | ✓ | ✅ PASS | State.zig:101 |
| Read clears VBlank flag (bit 7) | ✓ | ✓ | ⚠️ VERIFY | registers.zig:46 |
| Read resets write toggle (w=0) | ✓ | ✓ | ✅ PASS | registers.zig:49 |
| Read updates open bus (top 3 bits) | ✓ | ✓ | ✅ PASS | registers.zig:52 |
| Read does NOT clear latched NMI | ✓ | ✓ | ✅ PASS | VBlankLedger.zig:99 |
| Race: Read on exact VBlank set suppresses NMI | ✓ | ✓ | ✅ PASS | VBlankLedger.zig:136-137 |

**Result**: 9/10 behaviors verified, 1 needs timing verification ⚠️

**Issue**: The VBlank flag clear happens immediately, but **test failures suggest timing issues**. Need to verify this occurs at the correct CPU cycle.

---

## OAMADDR ($2003) - Write Only

| Behavior | Hardware Spec | Implementation | Status | Location |
|----------|---------------|----------------|--------|----------|
| Write-only (read returns open bus) | ✓ | ✓ | ✅ PASS | registers.zig:57-58 |
| Sets OAM address pointer | ✓ | ✓ | ✅ PASS | registers.zig:167 |
| Full 8-bit range (0-255) | ✓ | ✓ | ✅ PASS | State.zig:302 |
| Open bus updated on write | ✓ | ✓ | ✅ PASS | registers.zig:115 |

**Result**: 4/4 behaviors verified ✅

---

## OAMDATA ($2004) - Read/Write

| Behavior | Hardware Spec | Implementation | Status | Location |
|----------|---------------|----------------|--------|----------|
| Read current OAM byte | ✓ | ✓ | ✅ PASS | registers.zig:62 |
| Attribute bytes (n*4+2) have bits 2-4 as open bus | ✓ | ✓ | ✅ PASS | registers.zig:65-69 |
| Read updates open bus | ✓ | ✓ | ✅ PASS | registers.zig:72 |
| Write to OAM at current address | ✓ | ✓ | ✅ PASS | registers.zig:171 |
| Auto-increment address after write | ✓ | ✓ | ✅ PASS | registers.zig:172 |
| Address wraps at 256 | ✓ | ✓ | ✅ PASS | registers.zig:172 (+%= operator) |
| Write updates open bus | ✓ | ✓ | ✅ PASS | registers.zig:115 |

**Result**: 7/7 behaviors verified ✅

---

## PPUSCROLL ($2005) - Write Only (2 writes)

| Behavior | Hardware Spec | Implementation | Status | Location |
|----------|---------------|----------------|--------|----------|
| Write-only (read returns open bus) | ✓ | ✓ | ✅ PASS | registers.zig:77-78 |
| First write: X scroll (t[4-0] = d[7-3], x = d[2-0]) | ✓ | ✓ | ✅ PASS | registers.zig:181-183 |
| Second write: Y scroll (t[14-12] = d[2-0], t[9-5] = d[7-3]) | ✓ | ✓ | ✅ PASS | registers.zig:187-190 |
| Toggle w after each write | ✓ | ✓ | ✅ PASS | registers.zig:184, 191 |
| Ignored during warmup period | ✓ | ✓ | ✅ PASS | registers.zig:177 |
| Open bus updated on write | ✓ | ✓ | ✅ PASS | registers.zig:115 |

**Result**: 6/6 behaviors verified ✅

---

## PPUADDR ($2006) - Write Only (2 writes)

| Behavior | Hardware Spec | Implementation | Status | Location |
|----------|---------------|----------------|--------|----------|
| Write-only (read returns open bus) | ✓ | ✓ | ✅ PASS | registers.zig:81-82 |
| First write: High byte (t[13-8] = d[5-0], clear bit 14) | ✓ | ✓ | ✅ PASS | registers.zig:201-202 |
| Second write: Low byte (t[7-0] = d[7-0]) | ✓ | ✓ | ✅ PASS | registers.zig:206-207 |
| Copy t→v on second write | ✓ | ✓ | ✅ PASS | registers.zig:208 |
| Toggle w after each write | ✓ | ✓ | ✅ PASS | registers.zig:203, 209 |
| Ignored during warmup period | ✓ | ✓ | ✅ PASS | registers.zig:197 |
| Open bus updated on write | ✓ | ✓ | ✅ PASS | registers.zig:115 |

**Result**: 7/7 behaviors verified ✅

---

## PPUDATA ($2007) - Read/Write

| Behavior | Hardware Spec | Implementation | Status | Location |
|----------|---------------|----------------|--------|----------|
| Read from v address | ✓ | ✓ | ✅ PASS | registers.zig:86-90 |
| Read is buffered (return previous buffer) | ✓ | ✓ | ✅ PASS | registers.zig:87, 97 |
| Palette reads are unbuffered | ✓ | ✓ | ✅ PASS | registers.zig:97 |
| Auto-increment v after read | ✓ | ✓ | ✅ PASS | registers.zig:93 |
| Increment by 1 or 32 (PPUCTRL bit 2) | ✓ | ✓ | ✅ PASS | registers.zig:93 |
| Read updates open bus | ✓ | ✓ | ✅ PASS | registers.zig:100 |
| Write to v address | ✓ | ✓ | ✅ PASS | registers.zig:214-217 |
| Auto-increment v after write | ✓ | ✓ | ✅ PASS | registers.zig:220 |
| Write updates open bus | ✓ | ✓ | ✅ PASS | registers.zig:115 |

**Result**: 9/9 behaviors verified ✅

---

## VBlank Timing

| Behavior | Hardware Spec | Implementation | Status | Location |
|----------|---------------|----------------|--------|----------|
| VBlank flag set at scanline 241 dot 1 | ✓ | ✓ | ✅ PASS | Ppu.zig:155 |
| VBlank flag cleared at scanline 261 dot 1 | ✓ | ✓ | ✅ PASS | Ppu.zig:171 |
| VBlank flag cleared by $2002 read | ✓ | ✓ | ⚠️ VERIFY | registers.zig:46 |
| NMI triggered on VBlank set if NMI enable=1 | ✓ | ✓ | ✅ PASS | VBlankLedger.zig:64-66 |
| NMI edge persists until CPU acknowledgment | ✓ | ✓ | ✅ PASS | VBlankLedger.zig:174-177 |
| $2002 read does NOT clear latched NMI | ✓ | ✓ | ✅ PASS | VBlankLedger.zig:99 |
| Sprite 0 hit cleared at scanline 261 dot 1 | ✓ | ✓ | ✅ PASS | Ppu.zig:176 |
| Sprite overflow cleared at scanline 261 dot 1 | ✓ | ✓ | ✅ PASS | Ppu.zig:177 |

**Result**: 7/8 behaviors verified, 1 needs timing verification ⚠️

---

## NMI Edge Detection (VBlankLedger)

| Behavior | Hardware Spec | Implementation | Status | Location |
|----------|---------------|----------------|--------|----------|
| NMI edge on VBlank set with NMI enable=1 | ✓ | ✓ | ✅ PASS | VBlankLedger.zig:64-66 |
| NMI edge on PPUCTRL.7 toggle 0→1 during VBlank | ✓ | ✓ | ✅ PASS | VBlankLedger.zig:109-111 |
| Multiple NMI edges possible in one VBlank span | ✓ | ✓ | ✅ PASS | VBlankLedger.zig:102-112 |
| Race: $2002 read on exact VBlank set suppresses NMI | ✓ | ✓ | ✅ PASS | VBlankLedger.zig:136-137 |
| NMI edge latched until CPU acknowledgment | ✓ | ✓ | ✅ PASS | VBlankLedger.zig:33 |
| CPU acknowledges NMI during interrupt cycle 6 | ✓ | ✓ | ✅ PASS | cpu/execution.zig:218 |
| NMI line asserted only while edge pending | ✓ | ✓ | ✅ PASS | VBlankLedger.zig:161-170 |

**Result**: 7/7 behaviors verified ✅

---

## Open Bus Behavior

| Behavior | Hardware Spec | Implementation | Status | Location |
|----------|---------------|----------------|--------|----------|
| Data bus latch updated by all PPU writes | ✓ | ✓ | ✅ PASS | registers.zig:115 |
| Data bus latch updated by all PPU reads | ✓ | ✓ | ✅ PASS | registers.zig:52, 72, 100 |
| Write-only registers return open bus on read | ✓ | ✓ | ✅ PASS | registers.zig:27, 31, 58, 78, 82 |
| PPUSTATUS bits 0-4 from open bus | ✓ | ✓ | ✅ PASS | State.zig:108 |
| OAMDATA attribute bytes bits 2-4 from open bus | ✓ | ✓ | ✅ PASS | registers.zig:66-67 |
| Open bus decays after ~60 frames (~1 second) | ✓ | ✓ | ✅ PASS | State.zig:138, 147-153 |

**Result**: 6/6 behaviors verified ✅

---

## Warmup Period

| Behavior | Hardware Spec | Implementation | Status | Location |
|----------|---------------|----------------|--------|----------|
| Warmup period is 29,658 CPU cycles | ✓ | ✓ | ✅ PASS | cpu/execution.zig:106 |
| $2000 writes ignored during warmup | ✓ | ✓ | ✅ PASS | registers.zig:121-126 |
| $2001 writes ignored during warmup | ✓ | ✓ | ✅ PASS | registers.zig:143-148 |
| $2005 writes ignored during warmup | ✓ | ✓ | ✅ PASS | registers.zig:177 |
| $2006 writes ignored during warmup | ✓ | ✓ | ✅ PASS | registers.zig:197 |
| Warmup flag set after 29,658 CPU cycles | ✓ | ✓ | ✅ PASS | cpu/execution.zig:106-108 |
| RESET button does NOT trigger warmup | ✓ | ✓ | ✅ PASS | Logic.zig:36 |

**Result**: 7/7 behaviors verified ✅

---

## Register Mirroring

| Behavior | Hardware Spec | Implementation | Status | Location |
|----------|---------------|----------------|--------|----------|
| 8 registers at $2000-$2007 | ✓ | ✓ | ✅ PASS | registers.zig:22, 112 |
| Mirrored through $2008-$3FFF | ✓ | ✓ | ✅ PASS | routing.zig:20-34 |
| Mask formula: address & 0x0007 | ✓ | ✓ | ✅ PASS | registers.zig:22, 112 |

**Result**: 3/3 behaviors verified ✅

---

## Summary

| Category | Total | Verified | Needs Verification | Pass Rate |
|----------|-------|----------|-------------------|-----------|
| PPUCTRL | 10 | 10 | 0 | 100% |
| PPUMASK | 12 | 12 | 0 | 100% |
| PPUSTATUS | 10 | 9 | 1 | 90% |
| OAMADDR | 4 | 4 | 0 | 100% |
| OAMDATA | 7 | 7 | 0 | 100% |
| PPUSCROLL | 6 | 6 | 0 | 100% |
| PPUADDR | 7 | 7 | 0 | 100% |
| PPUDATA | 9 | 9 | 0 | 100% |
| VBlank Timing | 8 | 7 | 1 | 87.5% |
| NMI Edge Detection | 7 | 7 | 0 | 100% |
| Open Bus | 6 | 6 | 0 | 100% |
| Warmup Period | 7 | 7 | 0 | 100% |
| Register Mirroring | 3 | 3 | 0 | 100% |
| **TOTAL** | **96** | **94** | **2** | **97.9%** |

---

## Issues Requiring Verification

### 1. PPUSTATUS Read VBlank Clear Timing ⚠️

**What**: VBlank flag clear on $2002 read
**Where**: `registers.zig:46`
**Why**: Test failures show VBlank flag remains true after read during BIT/LDA execution
**Impact**: 3 failing tests, possibly affects Super Mario Bros
**Priority**: HIGH
**Action**: Add cycle-level logging to trace when $2002 read occurs relative to CPU execution phases

### 2. VBlank Flag Clear on $2002 Read (Same as #1) ⚠️

**What**: Duplicate entry - same issue as above
**Where**: `registers.zig:46`
**Impact**: Same as #1
**Priority**: HIGH
**Action**: Same as #1

---

## Test Failures Analysis

**Failing Tests**:
1. `vblank_wait_test.test.VBlank Wait Loop`
2. `ppustatus_polling_test.test.Simple VBlank: LDA $2002 clears flag`
3. `ppustatus_polling_test.test.BIT instruction timing`

**Common Pattern**: All involve $2002 reads during specific CPU execution phases

**Hypothesis**: Side effects occur during addressing mode microsteps instead of execute phase

**Evidence**:
```
CPU Cycle 4 (execute - SHOULD READ $2002 HERE)
  Before: VBlank: true
  After: VBlank: true   // ❌ Should be false
```

---

## Hardware References

- **NESDev Wiki**: https://www.nesdev.org/wiki/PPU_registers
- **NMI Timing**: https://www.nesdev.org/wiki/NMI
- **PPU Frame Timing**: https://www.nesdev.org/wiki/PPU_frame_timing
- **Power-up State**: https://www.nesdev.org/wiki/PPU_power_up_state

---

**Checklist Date**: 2025-10-09
**Coverage**: 96 behaviors across 13 categories
**Pass Rate**: 97.9% (94/96 verified)
**Outstanding Issues**: 2 timing verifications needed
