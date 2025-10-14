# RAMBO Failing Games Investigation Plan

## Executive Summary

After fixing MMC3 CHR banking, AxROM mirroring, and iNES header parsing, we still have three categories of failing games. Analysis shows this is NOT mapper-specific - games fail across all mappers (NROM, MMC1, UxROM, CNROM, MMC3).

## Failing Games Analysis

### Category 1: Grey Screen (PPU Never Enables) - 4 Games

| Game | Mapper | PRG | CHR | Key Observation |
|------|--------|-----|-----|-----------------|
| Castlevania | 2 (UxROM) | 128KB | RAM | Executes 26M instructions, PPUCTRL=$B0 (NMI enabled), PPUMASK=$00 |
| Metroid | 1 (MMC1) | 128KB | RAM | Grey screen |
| Paperboy | 3 (CNROM) | 32KB | 32KB ROM | Grey screen |
| TMNT II Arcade | 4 (MMC3) | 256KB | 256KB ROM | Grey screen |

**Critical Finding**: TMNT II (MMC3) fails but SMB3 (MMC3) works → NOT a mapper issue

### Category 2: First Frame Freeze - 3 Games

| Game | Mapper | PRG | CHR | Key Observation |
|------|--------|-----|-----|-----------------|
| SMB1 | 0 (NROM) | 32KB | 8KB ROM | Renders first frame, then stops |
| Kid Icarus | 1 (MMC1) | 128KB | RAM | First frame freeze |
| Lemmings | 1 (MMC1) | 128KB | 128KB ROM | First frame freeze |

### Category 3: Rendering Quirks - 2+ Games

| Game | Mapper | Issue |
|------|--------|-------|
| Mega Man 2 | 1 (MMC1) | Sprites render over text, come from sky |
| Mega Man 4 | 4 (MMC3) | Flickering, background position sync issues |

## Root Cause Hypotheses

### Hypothesis 1: VBlank Ledger Race Condition (P0 Bug) - MOST LIKELY
- **Status**: Known bug in `VBlankLedger.zig:201` documented in CURRENT-ISSUES.md
- **Evidence**: Castlevania has NMI enabled but never progresses
- **Impact**: Games might be stuck waiting for VBlank flag that's incorrectly cleared
- **Priority**: CRITICAL
- **Confidence**: HIGH (documented P0 bug)

### Hypothesis 2: NMI/IRQ Timing Issues
- **Evidence**: Castlevania shows PPUCTRL=$B0 (NMI enabled), executes millions of instructions
- **Theory**: Game stuck in NMI handler waiting for PPU status that never comes
- **Investigation Needed**: Trace NMI handler execution
- **Confidence**: MEDIUM

### Hypothesis 3: PPU Warm-up Period Bug
- **Evidence**: We have `warmup_complete` flag set after 29,658 cycles
- **Theory**: Some games might be checking PPU before warm-up completes
- **Investigation Needed**: Check if failing games write to PPU before warm-up
- **Confidence**: LOW (working games also have warm-up period)

### Hypothesis 4: Mapper-Specific Reset/Initialization
- **Evidence**: Multiple mapper types fail, but not consistently
- **Theory**: Some mappers might not be resetting properly
- **Investigation Needed**: Compare working vs failing games' reset sequences
- **Confidence**: LOW (pattern doesn't support mapper-specific issue)

### Hypothesis 5: Frame Timing / V-Sync Issues
- **Evidence**: First frame freeze suggests timing-related problem
- **Theory**: Games might be waiting for frame completion that never comes
- **Investigation Needed**: Check frame counter progression
- **Confidence**: MEDIUM (explains freeze symptoms)

## Investigation Tasks (Ordered by Priority)

### Task 1: VBlank Ledger Deep Dive (CRITICAL) - START HERE
**Agent**: debugger or zig-systems-pro
**Objective**: Fix P0 VBlankLedger race condition bug
**Time Estimate**: 1-2 hours
**Steps**:
1. Review VBlankLedger.zig:201 bug details in CURRENT-ISSUES.md
2. Implement `race_condition_occurred` flag fix as described
3. Run vblank_ledger tests (currently 0/4 passing)
4. Test with Castlevania ROM after fix

**Expected Impact**: Could fix ALL grey screen games if they're hitting race condition

### Task 2: Castlevania Execution Trace (HIGH)
**Agent**: debugger
**Objective**: Understand why game executes 26M instructions without rendering
**Time Estimate**: 2-3 hours
**Steps**:
1. Add PC trace logging for first 10,000 instructions
2. Identify NMI vector from ROM ($FFFA-$FFFB)
3. Check if game enters infinite loop in NMI handler
4. Monitor PPUSTATUS reads - what is game waiting for?
5. Compare with nesdev.org Castlevania boot sequence (if available)

### Task 4: First Frame Freeze Analysis (HIGH)
**Agent**: debugger
**Objective**: Understand why games freeze after first frame
**Time Estimate**: 1-2 hours
**Steps**:
1. Run SMB1 with frame counter logging
2. Check if frame counter increments after first frame
3. Monitor VBlank flag set/clear sequence
4. Check if NMI fires on frame 2
5. Compare frame 1 vs frame 2 timing

### Task 3: PPU Warm-up Validation (MEDIUM)
**Agent**: qa-code-review-pro
**Objective**: Verify PPU warm-up period is correct
**Time Estimate**: 30 minutes
**Steps**:
1. Review PPU warm-up logic in State.zig and EmulationState
2. Check nesdev.org PPU power-up state spec
3. Verify 29,658 cycle delay matches specification
4. Check if warmup affects $2002 reads

**Note**: Low confidence this is the issue, but quick to validate

### Task 5: Mega Man Sprite Layering (MEDIUM)
**Agent**: qa-code-review-pro
**Objective**: Fix sprite priority/layering issues
**Time Estimate**: 2-3 hours
**Steps**:
1. Review PPU sprite rendering in src/ppu/logic/sprites.zig
2. Check sprite priority bit (bit 5 of attribute byte) handling
3. Verify background vs sprite layering logic
4. Check sprite 0 hit detection (might affect scrolling)
5. Test with Mega Man 2 title screen

### Task 6: Mapper Reset Sequence Comparison (LOW)
**Agent**: code-reviewer
**Objective**: Validate mapper reset sequences
**Time Estimate**: 1 hour
**Steps**:
1. Review reset() methods for all 6 mappers
2. Compare with nesdev.org reset behavior for each
3. Check PRG/CHR banking initial state
4. Verify all registers initialize to correct values

**Note**: Low priority - pattern doesn't support mapper-specific root cause

## Questions for User Before Proceeding

1. **Priority Confirmation**: Do you agree Task 1 (VBlank Ledger) should be fixed first?
   - This is a documented P0 bug that could explain grey screens
   - 4 tests currently failing, clear fix described in CURRENT-ISSUES.md

2. **Agent Selection**: For Task 1, should we use:
   - `zig-systems-pro` (implementation specialist)
   - `debugger` (debugging specialist)
   - Both in parallel (one investigates, one implements)?

3. **Investigation Depth**: For Tasks 2 & 4 (traces), should we:
   - Create minimal diagnostic tools first?
   - Use existing debugger system with breakpoints?
   - Add temporary logging to EmulationState?

4. **Mega Man Priority**: Should we:
   - Fix grey screens and freezes first, Mega Man later?
   - OR investigate all three categories in parallel?

5. **Documentation**: Should findings be:
   - Added to CURRENT-ISSUES.md as we discover them?
   - Collected in this investigation document?
   - Both?

## Success Criteria

- [ ] VBlank Ledger tests pass (4/4) - currently 0/4
- [ ] Castlevania enables rendering within 300 frames
- [ ] Metroid enables rendering
- [ ] Paperboy enables rendering
- [ ] TMNT II enables rendering
- [ ] SMB1 progresses past first frame
- [ ] Kid Icarus progresses past first frame
- [ ] Lemmings progresses past first frame
- [ ] Mega Man 2 sprites render correctly (no sky elevators)
- [ ] Mega Man 4 background scrolling fixed
- [ ] Test suite: 993/993 tests passing (100%)

## nesdev.org References

- [VBlank Flag](https://www.nesdev.org/wiki/PPU_registers#PPUSTATUS)
- [PPU Power-up State](https://www.nesdev.org/wiki/PPU_power_up_state)
- [NMI Operation](https://www.nesdev.org/wiki/NMI)
- [PPU Frame Timing](https://www.nesdev.org/wiki/PPU_frame_timing)
- [MMC1 Reset](https://www.nesdev.org/wiki/MMC1#Registers)
- [UxROM Specification](https://www.nesdev.org/wiki/UxROM)
- [CNROM Specification](https://www.nesdev.org/wiki/CNROM)

## Current Status

**Date**: 2025-10-14
**Test Results**: 987/993 passing (99.4%)
**Failing**: 6 tests (4 VBlank Ledger, 1 Castlevania, 1 threading)
**Blocking Issue**: P0 VBlank Ledger race condition bug

**Next Step**: Awaiting user approval to proceed with Task 1 (VBlank Ledger fix)
