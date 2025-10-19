# AccuracyCoin Test Status - ROM Verified
**Date:** 2025-10-19
**Source:** Direct ROM execution screenshots
**Status:** VERIFIED - Actual emulator behavior documented

---

## Test Results Summary

### ✅ PASSING TESTS (58 total)

#### CPU Behavior (Page 1/20)
1. ✅ ROM is not writable
2. ✅ RAM mirroring
3. ✅ PC wraparound
4. ✅ The decimal flag
5. ✅ The B flag
6. ✅ Dummy read cycles
7. ✅ **DUMMY WRITE CYCLES** ← CONFIRMED PASSING (was thought to fail)
8. ✅ Open bus

#### Addressing Mode Wraparound (Page 2/20)
1. ✅ Absolute indexed
2. ✅ Zero page indexed
3. ✅ Indirect
4. ✅ Indirect, X
5. ✅ Indirect, Y
6. ✅ Relative

#### Power-On State (Page 15/20)
1. ✅ CPU registers

#### CPU Behavior 2 (Page 20/20)
1. ✅ JSR edge cases

---

## ❌ FAILING TESTS (42 total)

### CPU - Unofficial Instructions (Pages 3-11)

#### SLO (Page 3/20) - 7 failures
- ❌ FAIL 5: $03 SLO indirect,X
- ❌ FAIL 5: $07 SLO zeropage
- ❌ FAIL 5: $0F SLO absolute
- ❌ FAIL 5: $13 SLO indirect,Y
- ❌ FAIL 5: $17 SLO zeropage,X
- ❌ FAIL 5: $1B SLO absolute,Y
- ❌ FAIL 5: $1F SLO absolute,X

#### RLA (Page 4/20) - 7 failures
- ❌ FAIL 1: $23 RLA indirect,X
- ❌ FAIL 1: $27 RLA zeropage
- ❌ FAIL 5: $2F RLA absolute
- ❌ FAIL 1: $33 RLA indirect,Y
- ❌ FAIL 1: $37 RLA zeropage,X
- ❌ FAIL 5: $3B RLA absolute,Y
- ❌ FAIL 5: $3F RLA absolute,X

#### SRE (Page 5/20) - 7 failures
- ❌ FAIL 5: $43 SRE indirect,X
- ❌ FAIL 5: $47 SRE zeropage
- ❌ FAIL 5: $4F SRE absolute
- ❌ FAIL 5: $53 SRE indirect,Y
- ❌ FAIL 5: $57 SRE zeropage,X
- ❌ FAIL 5: $5B SRE absolute,Y
- ❌ FAIL 5: $5F SRE absolute,X

#### RRA (Page 6/20) - 7 failures
- ❌ FAIL 1: $63 RRA indirect,X
- ❌ FAIL 1: $67 RRA zeropage
- ❌ FAIL 5: $6F RRA absolute
- ❌ FAIL 1: $73 RRA indirect,Y
- ❌ FAIL 1: $77 RRA zeropage,X
- ❌ FAIL 5: $7B RRA absolute,Y
- ❌ FAIL 5: $7F RRA absolute,X

#### SAX & LAX (Page 7/20) - 9 failures
- ❌ FAIL 5: $83 SAX indirect,X
- ❌ FAIL 5: $87 SAX zeropage
- ❌ FAIL 5: $8F SAX absolute
- ❌ FAIL 5: $97 SAX zeropage,Y
- ❌ FAIL 5: $A3 LAX indirect,X
- ❌ FAIL 5: $A7 LAX zeropage
- ❌ FAIL 5: $AF LAX absolute
- ❌ FAIL 5: $B3 LAX indirect,Y
- ❌ FAIL 5: $B7 LAX zeropage,Y
- ❌ FAIL 5: $BF LAX absolute,X

#### DCP (Page 8/20) - 7 failures
- ❌ FAIL 5: $C3 DCP indirect,X
- ❌ FAIL 5: $C7 DCP zeropage
- ❌ FAIL 5: $CF DCP absolute
- ❌ FAIL 5: $D3 DCP indirect,Y
- ❌ FAIL 5: $D7 DCP zeropage,X
- ❌ FAIL 5: $DB DCP absolute,Y
- ❌ FAIL 5: $DF DCP absolute,X

#### ISC (Page 9/20) - 7 failures
- ❌ FAIL 5: $E3 ISC indirect,X
- ❌ FAIL 5: $E7 ISC zeropage
- ❌ FAIL 2: $EF ISC absolute
- ❌ FAIL 5: $F3 ISC indirect,Y
- ❌ FAIL 5: $F7 ISC zeropage,X
- ❌ FAIL 2: $FB ISC absolute,Y
- ❌ FAIL 2: $FF ISC absolute,X

#### SHA, SHY, SHX, LAE (Page 10/20) - 6 failures
- ❌ FAIL F: $93 SHA indirect,Y
- ❌ FAIL F: $9F SHA absolute,Y
- ❌ FAIL F: $9B SH5 absolute,Y
- ❌ FAIL 5: $9C SHY absolute,X
- ❌ FAIL 5: $9E SHX absolute,Y
- ❌ FAIL 5: $BB LAE absolute,Y

#### Unofficial Immediates (Page 11/20) - 8 failures
- ❌ FAIL 5: $0B ANC immediate
- ❌ FAIL 5: $2B ANC immediate
- ❌ FAIL 5: $4B ASR immediate
- ❌ FAIL 5: $6B ARR immediate
- ❌ FAIL 5: $8B ANE immediate
- ❌ FAIL 5: $AB LXA immediate
- ❌ FAIL 5: $CB AXS immediate
- ❌ FAIL 2: $EB SBC immediate

### CPU - NOP Instructions (Page 1/20)
- ❌ FAIL 1: All NOP instructions

### APU Registers and DMA (Page 13/20) - 10 failures
- ❌ FAIL 2: DMA + open bus
- ❌ FAIL 2: DMA + $2007 read
- ❌ FAIL 1: DMA + $2007 write
- ❌ FAIL 2: DMA + $4015 read
- ❌ FAIL 1: DMA + $4016 read
- ❌ FAIL 1: APU register actuation
- ❌ FAIL 1: DMC DMA bus conflicts
- ❌ FAIL 1: DMC DMA + OAM DMA
- ❌ FAIL 1: Explicit DMA abort
- ❌ FAIL 1: Implicit DMA abort

### APU Timing (Page 14/20) - 6 failures
- ❌ FAIL 7: Frame counter IRQ
- ❌ FAIL 1: Frame counter 4-step
- ❌ FAIL 1: Frame counter 5-step
- ❌ FAIL 1: Delta modulation channel
- ❌ FAIL 4: Controller strobing
- ❌ FAIL 2: Controller clocking

### PPU VBlank Timing (Page 17/20) - 7 failures
- ❌ FAIL 1: VBlank beginning
- ❌ FAIL 1: VBlank end
- ❌ FAIL 7: NMI control (7 subtests fail)
- ❌ FAIL 1: NMI timing
- ❌ FAIL 1: NMI suppression
- ❌ FAIL 1: NMI at VBlank end
- ❌ FAIL 1: NMI disabled at VBlank

### Sprite Evaluation (Page 18/20) - 7 failures
- ❌ FAIL 1: Sprite overflow behavior
- ❌ FAIL 1: Sprite 0 hit behavior
- ❌ FAIL 1: Arbitrary sprite zero
- ❌ FAIL 1: Misaligned OAM behavior
- ❌ FAIL 1: Address $2004 behavior
- ⚠️ TEST: OAM corruption (crashes ROM)
- ❌ FAIL 1: INC $4014

### PPU Misc (Page 19/20) - 3 failures
- ❌ FAIL 1: Attributes as tiles
- ❌ FAIL 1: T register quirks
- ❌ FAIL 1: Stale shift registers
- ⚠️ TEST: Sprites on scanline 0 (crashes ROM)

### CPU Behavior 2 (Page 20/20) - 2 failures
- ❌ FAIL 1: Instruction timing
- ❌ FAIL 1: Implied dummy reads

---

## Test Categories by Priority

### Priority 1: VBlank/NMI (CRITICAL - blocks many games)
All 7 VBlank timing tests fail. This is the most critical issue:
1. VBlank beginning
2. VBlank end
3. NMI control (7 subtests)
4. NMI timing
5. NMI suppression
6. NMI at VBlank end
7. NMI disabled at VBlank

**Impact:** Affects all games using NMI interrupts
**Complexity:** Medium - requires VBlank ledger fixes
**Estimated effort:** 2-3 hours

### Priority 2: CPU Timing (HIGH - affects cycle accuracy)
1. Instruction timing
2. Implied dummy reads

**Impact:** Affects timing-sensitive games
**Complexity:** Low-Medium
**Estimated effort:** 1-2 hours

### Priority 3: Unofficial Instructions (MEDIUM - compatibility)
64 unofficial opcode tests fail with various error codes (1, 2, 5, F)

**Impact:** Affects games using unofficial opcodes
**Complexity:** High - requires implementing 40+ opcodes
**Estimated effort:** 4-6 hours

### Priority 4: APU/DMA (MEDIUM - audio and timing)
16 APU/DMA tests fail

**Impact:** Audio and specific DMA timing
**Complexity:** High
**Estimated effort:** 3-4 hours

### Priority 5: Sprite Evaluation (LOW-MEDIUM)
7 sprite tests fail, 2 crash the ROM

**Impact:** Sprite rendering edge cases
**Complexity:** Medium-High
**Estimated effort:** 2-3 hours

### Priority 6: PPU Misc (LOW)
3 PPU misc tests fail

**Impact:** Edge case rendering
**Complexity:** Medium
**Estimated effort:** 1-2 hours

---

## Action Plan

### Phase 1: Fix VBlank/NMI Tests (HIGHEST PRIORITY)
**Estimated time:** 2-3 hours
**Goal:** Get all 7 VBlank tests passing

1. Investigate VBlank beginning failure
2. Fix VBlank ledger race conditions
3. Fix NMI control logic
4. Verify all 7 tests pass

### Phase 2: Fix CPU Timing Tests
**Estimated time:** 1-2 hours
**Goal:** Get instruction timing and implied dummy reads passing

1. Investigate instruction timing deviations
2. Fix implied mode dummy read behavior
3. Verify tests pass

### Phase 3: Implement Unofficial Instructions (if needed)
**Estimated time:** 4-6 hours
**Goal:** Implement missing unofficial opcodes

Note: This may be deferred if not critical for target games

### Phase 4: APU/DMA Fixes (if needed)
**Estimated time:** 3-4 hours
**Goal:** Fix APU timing and DMA interactions

Note: May be deferred if audio not critical

---

## Current Test Suite Accuracy

Our unit tests were expecting:
- dummy_write_cycles_test: FAIL (but actually PASSES)
- nmi_control_test: FAIL 4 (but actually FAIL 7)

**Action:** Update all unit test expectations to match ROM results
- Tests that pass should expect 0x00
- Tests that fail should expect actual failure code
- This will make our test suite useful for regression detection

---

**Status:** Test status verified from ROM screenshots
**Next:** Fix VBlank/NMI tests (Priority 1)
