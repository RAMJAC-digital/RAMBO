# Project Status - Single Source of Truth

**Last Updated:** 2025-11-02
**Test Run:** `zig build test --summary failures`

> **NOTE:** This is the ONLY authoritative source for test counts and component status.
> All other documents should reference this file, not duplicate this information.

---

## Test Results

```
Total: 1004/1026 (97.9% passing)
Failing: 16
Skipped: 6
```

---

## Failing Tests

### CPU Tests (1 failure)
- `jmp_indirect_test` - JMP indirect addressing at page boundaries
  - Error: `expected 4660, found 52`
  - Impact: CPU instruction bug

### Integration Tests (11 failures)

#### VBlank/NMI (10 failures - AccuracyCoin ROM tests)
- `all_nop_instructions_test` - FAIL (err=1)
- `unofficial_instructions_test` - FAIL (err=10)
- `nmi_control_test` - FAIL (err=7)
- `vblank_end_test` - FAIL (err=1)
- `nmi_disabled_vblank_test` - FAIL (err=1)
- `vblank_beginning_test` - FAIL (err=1)
- `nmi_vblank_end_test` - FAIL (err=1)
- `nmi_suppression_test` - FAIL (err=1)
- `nmi_timing_test` - FAIL (err=1)
- `cpu_ppu_integration_test` - VBlank race condition (expected 128, found 0)

**Context:** AccuracyCoin tests were fixed to properly initialize ROM state (2025-10-19/20).
Tests now correctly identify VBlank/NMI timing bugs in the emulator.

#### Commercial ROM Tests (1 failure)
- `commercial_rom_test` - BurgerTime rendering test

---

## Skipped Tests

- **6 tests skipped** (timing-sensitive tests, not functional failures)

---

## Component Status

### CPU (6502)
- **Status:** Feature-complete with 1 known bug
- **Tests:** ~280 total, ~279 passing
- **Known Issues:**
  - JMP indirect page boundary bug

### PPU (2C02)
- **Status:** Feature-complete with VBlank/NMI timing bugs
- **Tests:** ~90 total, ~89 passing
- **Known Issues:**
  - VBlank race condition (cpu_ppu_integration_test failing)
  - VBlank/NMI timing (10 AccuracyCoin tests failing)

### APU
- **Status:** Emulation 100% complete
- **Tests:** 135/135 passing
- **Audio output:** Not implemented (future)

### Mappers
- **Implemented:** Mapper 0 (NROM), 1 (MMC1), 2 (UxROM), 3 (CNROM), 4 (MMC3), 7 (AxROM)
- **Tests:** ~48 passing

### Other Components
- Debugger: ~66 tests passing
- Mailboxes: 57 tests passing
- Input System: 40 tests passing
- Threading: 8 passing, 6 skipped
- Config: ~30 tests passing
- iNES: 26 tests passing
- Snapshot: ~23 tests passing
- Bus & Memory: ~20 tests passing

---

## Recent Fixes

**2025-11-03:** VBlank/NMI Timing Restructuring and IRQ Masking
- Fixed execution order: CPU execution BEFORE VBlank timestamp application (allows prevention mechanism to work)
- Fixed IRQ masking during NMI: IRQ restoration preserves NMI priority (`if (irq_pending_prev and pending_interrupt != .nmi)`)
- Moved interrupt sampling to AFTER VBlank timestamps are final (ensures correct NMI line state)
- VBlank prevention now works correctly: CPU sets flag, timestamps check flag
- Test improvement: Fixed infinite interrupt loop, enabled AccuracyCoin menu access (stability milestone)
- Hardware citations: nesdev.org/wiki/PPU_frame_timing, nesdev.org/wiki/NMI
- Reference: Mesen2 NesPpu.cpp:1340-1344 (prevention flag check)
- Implementation: `src/emulation/State.zig:tick()` lines 651-774

**2025-11-02:** DMC/OAM DMA Time-Sharing
- Fixed OAM stall detection to only pause during DMC read cycle (stall==1)
- OAM now continues during DMC halt/dummy/alignment cycles (hardware-accurate time-sharing)
- Net overhead reduced from 4 cycles to ~2 cycles
- Test improvement: +2 tests passing
- All 14 DMC/OAM conflict tests now passing
- Hardware citation: nesdev.org/wiki/DMA#DMC_DMA_during_OAM_DMA
- Reference: Mesen2 NesCpu.cpp:385

## Current Focus

**Active Work:** VBlank/PPU/NMI timing bugs (TDD - failing tests identify bugs to fix)

**Next Steps:**
1. Fix VBlank race condition
2. Fix NMI timing issues
3. Address AccuracyCoin test failures

---

## How to Update This File

1. Run: `zig build test`
2. Update test counts
3. Update "Last Updated" date
4. Commit changes

**Do not duplicate this information elsewhere - link to this file instead.**
