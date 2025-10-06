# Phase 1 (P1) Development Hub - Accuracy Fixes

**Status:** 🟡 **READY TO BEGIN**
**Priority:** HIGH (Required for AccuracyCoin test suite compliance)
**Prerequisites:** ✅ Phase 0 Complete (100% CPU implementation with cycle-accurate timing)

---

## Overview

Phase 1 focuses on fine-grained accuracy improvements to achieve full compatibility with the AccuracyCoin test suite. All work maintains the established pure functional architecture with State/Logic separation.

**Goal:** Improve hardware emulation accuracy through three targeted enhancements

---

## P1 Tasks

### 1.1 Unstable Opcode Configuration ⚠️ HIGH PRIORITY

**Status:** 🔴 TODO
**Estimated Time:** 8-12 hours
**Complexity:** MEDIUM

**Problem:** Unofficial "unstable" opcodes (`XAA`, `LXA`, `SHA`, `SHX`, `SHY`, `ANE`) use hardcoded magic values that vary between CPU revisions.

**Solution:** Make behavior CPU-variant dependent via configuration
- Add `unstable_opcodes` field to `CpuModel` configuration
- Pass configuration pointer to `CpuCoreState`
- Update unofficial opcode implementations to use config values

**Implementation Plan:** See [PLAN-P1-ACCURACY-FIXES.md](./PLAN-P1-ACCURACY-FIXES.md) Section 2

**Testing Strategy:**
- Create `tests/cpu/opcodes/unstable_variants_test.zig`
- Test each opcode with multiple CPU variants (RP2A03G, RP2A03H, etc.)
- Verify variant-specific behavior matches hardware

**Dependencies:** None
**Blocking:** AccuracyCoin CPU test compliance

---

### 1.2 Cycle-Accurate OAM DMA ⚠️ HIGH PRIORITY

**Status:** 🔴 TODO
**Estimated Time:** 12-16 hours
**Complexity:** HIGH

**Problem:** OAM DMA ($4014 write) is not implemented. This is critical for sprite rendering in most games.

**Hardware Behavior:**
- Write to $4014 triggers 256-byte DMA transfer (CPU RAM → PPU OAM)
- **Stalls CPU for 513-514 cycles** (odd/even cycle alignment)
- PPU continues running during DMA
- Transfer happens one byte per cycle

**Solution:** Implement DMA coordination in main emulation loop
- Add `DmaState` to `BusState` (active, source_page, cycle_count)
- Handle $4014 write in `BusLogic.write()`
- Main loop mediates byte-by-byte transfer
- Preserve component isolation (no direct CPU→PPU access)

**Implementation Plan:** See [PLAN-P1-ACCURACY-FIXES.md](./PLAN-P1-ACCURACY-FIXES.md) Section 3

**Testing Strategy:**
- Create `tests/integration/oam_dma_test.zig`
- Verify exact cycle count (513 or 514 based on odd/even)
- Test that PPU continues during DMA
- Verify OAM data correctly transferred
- Test edge cases (DMA during VBlank, mid-instruction, etc.)

**Dependencies:** None
**Blocking:** Sprite-heavy games, AccuracyCoin PPU tests

**Historical Context:** DMA implementation discussed in:
- `docs/archive/PHASE-7A-COMPLETE-SUMMARY.md`
- `docs/archive/PHASE-4-SUMMARY.md`

---

### 1.3 Replace `anytype` in Bus Logic 🟢 LOW PRIORITY

**Status:** 🔴 TODO
**Estimated Time:** 2-4 hours
**Complexity:** LOW

**Problem:** `src/bus/Logic.zig` uses `anytype` for the `ppu` parameter, reducing type safety and IDE support.

**Solution:** Change to concrete type
```zig
// Before:
pub fn read(bus: *BusState, address: u16, ppu: anytype) u8

// After:
pub fn read(bus: *BusState, address: u16, ppu: *PpuState.PpuState) u8
```

**Implementation Plan:** See [PLAN-P1-ACCURACY-FIXES.md](./PLAN-P1-ACCURACY-FIXES.md) Section 4

**Testing Strategy:**
- Run full test suite (562/562 should still pass)
- Verify no performance regression
- Check IDE autocomplete now works for ppu parameter

**Dependencies:** None
**Blocking:** None (quality-of-life improvement)

---

## Development Workflow

### TDD Approach (Required)

1. **Write failing test first** - Document expected hardware behavior
2. **Implement minimal change** - Make test pass with smallest code change
3. **Run full suite** - Ensure zero regressions (562/562 passing)
4. **Refactor if needed** - Clean up while keeping tests green
5. **Document thoroughly** - Update relevant docs and code comments

### Testing Requirements

**Before ANY commit:**
```bash
zig build test --summary all
# Must show: 562/562 tests passed
```

**No exceptions** - Regressions are not acceptable

### Commit Strategy

Each P1 task should be a separate commit following Conventional Commits:

```bash
feat(cpu): Implement unstable opcode configuration
feat(bus): Implement cycle-accurate OAM DMA
refactor(bus): Replace anytype with concrete PpuState type
```

---

## Success Criteria

### Task 1.1 Complete When:
- [ ] All unstable opcodes use configuration values
- [ ] Tests pass for all CPU variants
- [ ] 562/562 tests still passing
- [ ] Documentation updated

### Task 1.2 Complete When:
- [ ] $4014 write triggers DMA
- [ ] CPU stalls for correct cycle count (513 or 514)
- [ ] OAM data transfers correctly
- [ ] PPU continues running during DMA
- [ ] Edge cases handled
- [ ] Integration tests passing
- [ ] 562/562 tests still passing

### Task 1.3 Complete When:
- [ ] All `anytype` replaced with `*PpuState.PpuState`
- [ ] IDE autocomplete functional
- [ ] 562/562 tests still passing
- [ ] Zero performance regression

---

## Architecture Principles (Must Maintain)

### State/Logic Separation
- State modules: Pure data structures only
- Logic modules: Pure functions operating on state pointers
- No hidden state, no global variables

### Component Isolation
- CPU cannot directly access PPU
- Bus mediates all cross-component communication
- DMA coordination happens in main emulation loop

### RT-Safety
- Zero heap allocations in hot path
- No locks in emulation core
- Deterministic execution

### Pure Functional Opcodes
- All opcode functions remain pure
- Take `CpuCoreState`, return `OpcodeResult`
- Side effects applied in execution engine only

---

## Resources

### Documentation
- **P1 Implementation Plan:** [PLAN-P1-ACCURACY-FIXES.md](./PLAN-P1-ACCURACY-FIXES.md)
- **P0 Completion:** `../archive/p0/P0-TIMING-FIX-COMPLETION-2025-10-06.md`
- **CPU Architecture:** `archive/2025-10-05/02-cpu.md`
- **Bus Architecture:** `archive/2025-10-05/04-memory-and-bus.md`

### Hardware References
- **6502 Timing:** NESdev Wiki (https://www.nesdev.org/wiki/CPU)
- **OAM DMA:** NESdev Wiki (https://www.nesdev.org/wiki/PPU_registers#OAMDMA)
- **Unstable Opcodes:** Visual 6502 project, nestest.log analysis

### Historical Context
- **DMA Discussion:** Phase 7A summary in `../archive/PHASE-7A-COMPLETE-SUMMARY.md`
- **Architecture Decisions:** Phase 3 comptime generics plan in `../archive/code-review-2025-10-04/`

---

## Estimated Timeline

| Task | Estimated Time | Complexity | Priority |
|------|---------------|------------|----------|
| 1.1 Unstable Opcodes | 8-12 hours | MEDIUM | HIGH |
| 1.2 OAM DMA | 12-16 hours | HIGH | HIGH |
| 1.3 Type Safety | 2-4 hours | LOW | LOW |
| **Total** | **22-32 hours** | **~4-5 days** | - |

**Recommended Order:**
1. Task 1.3 (Type Safety) - Quick win, improves development experience
2. Task 1.1 (Unstable Opcodes) - CPU-focused, leverages P0 architecture
3. Task 1.2 (OAM DMA) - Most complex, requires cross-component coordination

---

## Next Steps

**To Begin P1:**

1. Review this document and the detailed plan
2. Read relevant architecture docs (CPU, Bus, PPU)
3. Start with Task 1.3 (quick type safety fix)
4. Move to Task 1.1 (unstable opcodes)
5. Tackle Task 1.2 (OAM DMA) last

**Questions or Issues:**
- Refer to `STATUS.md` for current project state
- Check `archive/sessions/p0/` for P0 implementation context
- All architecture patterns established in P0 must be maintained

---

**Status:** Ready for P1 development
**Last Updated:** 2025-10-06
**Phase 0 Complete:** ✅ All prerequisites met
