# P1 Development Plan - Accuracy Fixes
**Date:** 2025-10-06
**Status:** DRAFT - Architecture Audit Complete
**Prerequisites:** ✅ Phase 0 Complete (100% CPU implementation)

---

## Executive Summary

This document provides a **comprehensive development plan** for Phase 1 (P1) Accuracy Fixes, based on a complete audit of the RAMBO codebase as of 2025-10-06.

**CRITICAL FINDINGS:**
1. ✅ **Task 1.1 (Unstable Opcodes)** - Partially implemented but needs completion
2. ⚠️ **Task 1.2 (OAM DMA)** - 40% complete, scaffolding exists, needs execution logic
3. ❌ **Task 1.3 (Bus anytype)** - **OBSOLETE** - No separate Bus module exists

**Architecture Reality Check:**
- Bus logic is **INLINE** in `EmulationState.zig`, not in separate `Bus.zig` module
- DMA state machine is **ALREADY SCAFFOLDED** with trigger logic wired
- CPU variant system has **TWO COMPETING DESIGNS** (runtime config vs comptime generics)

---

## Table of Contents

1. [Architecture Audit Results](#architecture-audit-results)
2. [Critical Design Decisions](#critical-design-decisions)
3. [Revised Task Breakdown](#revised-task-breakdown)
4. [Implementation Roadmap](#implementation-roadmap)
5. [Testing Strategy](#testing-strategy)
6. [Development Workflow](#development-workflow)
7. [Risk Assessment](#risk-assessment)

---

## Architecture Audit Results

### Current Codebase State (2025-10-06)

#### ✅ What Exists and Works:
- **EmulationState.zig** (1626 lines)
  - Inline bus routing (no separate Bus module)
  - DmaState struct fully defined (lines 92-131)
  - $4014 write handler wired (line 290-294)
  - MasterClock with PPU cycle granularity
  - Complete microstep helpers for CPU execution

- **src/cpu/variants.zig** (239 lines)
  - Comptime type factory `Cpu(variant: CpuVariant)`
  - Variant-specific magic constants: `.lxa_magic`, `.ane_magic`
  - Comptime dispatch (zero runtime overhead)
  - Example implementations of LXA/XAA with comptime magic

- **src/cpu/opcodes/unofficial.zig** (440 lines)
  - All 20 unofficial opcode functions implemented
  - HARDCODED magic constants (line 228: `const magic: u8 = 0xEE`)
  - Pure functional API (`CpuCoreState → OpcodeResult`)

- **src/config/Config.zig** (783 lines)
  - `CpuVariant` enum: rp2a03e, rp2a03g, rp2a03h, rp2a07
  - `CpuModel` struct with variant field
  - NO `unstable_opcodes` configuration (planned in original P1 doc)

#### ❌ What's Missing:
- **Task 1**: Wiring between Config.CpuVariant and actual opcode execution
- **Task 2**: DMA microstep execution in `EmulationState.tick()`
- **Task 3**: N/A - No `anytype` in bus logic (inline architecture)

#### 🟡 Partially Implemented:
- **DMA Infrastructure (40% complete)**
  - ✅ DmaState struct
  - ✅ Trigger function with odd/even cycle detection
  - ✅ $4014 write handler
  - ❌ Microstep execution in tick() function
  - ❌ Integration tests

---

## Critical Design Decisions

### Decision 1: Unstable Opcode Configuration Strategy

**Two competing approaches identified:**

#### Option A: Runtime Config Pointer (Original P1 Plan)
```zig
// src/cpu/State.zig
pub const CpuCoreState = struct {
    a: u8, x: u8, y: u8, sp: u8, pc: u16,
    p: StatusFlags,
    effective_address: u16,
    config: *const Config.CpuModel,  // NEW: 8-byte pointer overhead
};

// src/cpu/opcodes/unofficial.zig
pub fn lxa(state: CpuCoreState, operand: u8) OpcodeResult {
    const magic = state.config.unstable_opcodes.lxa_magic;  // Runtime lookup
    // ...
}
```

**Pros:**
- Simple to implement (matches plan exactly)
- Config can change at runtime (swap CPU variants dynamically)
- Minimal code changes

**Cons:**
- 8-byte overhead per CpuCoreState copy (copied frequently!)
- Runtime memory dereference on every unstable opcode
- Pointer indirection reduces cache efficiency
- NOT RT-safe if config could be modified concurrently

#### Option B: Comptime Generics (variants.zig approach)
```zig
// src/cpu/variants.zig (ALREADY EXISTS)
pub fn Cpu(comptime variant: CpuVariant) type {
    const config = comptime getVariantConfig(variant);
    return struct {
        pub fn lxa(state: CpuCoreState, operand: u8) OpcodeResult {
            const magic = comptime config.lxa_magic;  // Compile-time constant!
            // ...
        }
    };
}

// Usage in EmulationState
const CpuG = Cpu(.rp2a03g);
const result = CpuG.lxa(core_state, operand);
```

**Pros:**
- Zero runtime overhead (magic constants are compile-time literals)
- Perfect cache behavior (no pointer dereferencing)
- RT-safe by design (immutable)
- Aligns with existing `Cartridge(MapperType)` pattern

**Cons:**
- Cannot swap CPU variant at runtime (must recompile)
- More complex dispatch architecture
- Requires comptime dispatch table generation

**RECOMMENDATION:** 🎯 **Use Option B (Comptime Generics)**

**Rationale:**
1. RAMBO already uses comptime generics for cartridges (`Cartridge(MapperType)`)
2. Zero runtime overhead is critical for RT safety
3. CPU variant never changes during emulation session
4. Aligns with Zig philosophy (prefer comptime when possible)
5. The infrastructure in `variants.zig` is already 70% complete!

---

### Decision 2: OAM DMA Execution Model

**Question:** Where should DMA microsteps execute?

**Option A: Dedicated DMA tick() section**
```zig
pub fn tick(self: *EmulationState) void {
    if (self.dma.active) {
        self.tickDma();  // Separate function
        return;  // Skip normal CPU/PPU tick
    }
    // Normal emulation...
}
```

**Option B: Inline in CPU tick section**
```zig
pub fn tickCpu(self: *EmulationState) void {
    if (self.dma.active) {
        self.executeDmaCycle();
        return;  // CPU stalled
    }
    // Normal CPU execution...
}
```

**RECOMMENDATION:** 🎯 **Option A (Dedicated DMA tick)**

**Rationale:**
1. DMA is a **bus-level operation**, not CPU-specific
2. PPU **MUST continue running** during DMA (critical for accuracy)
3. Cleaner separation of concerns
4. Matches hardware behavior (DMA controller is separate from CPU)

---

## Revised Task Breakdown

### Task 1.1: Unstable Opcode Configuration ⚠️ **REVISED**

**Status:** 🟡 40% Complete (variants.zig exists, needs integration)
**Priority:** HIGH
**Estimated Time:** 6-8 hours (reduced from 8-12)
**Complexity:** MEDIUM → LOW (infrastructure exists)

#### Implementation Plan

**Phase 1A: Update unofficial.zig to use comptime variant (3 hours)**

1. ✅ Review `src/cpu/variants.zig` (already has LXA/XAA examples)
2. Move all 20 unofficial opcode functions into `Cpu(variant)` type factory
3. Replace hardcoded magic constants with `comptime config.lxa_magic`
4. Update opcodes: `lxa`, `xaa`, `sha`, `shx`, `shy`, `tas`

**Files to Modify:**
- `src/cpu/variants.zig` - Add all unofficial opcodes
- `src/cpu/opcodes/unofficial.zig` - Mark as deprecated or remove
- `src/cpu/opcodes/mod.zig` - Update imports

**Phase 1B: Integrate with dispatch table (2 hours)**

1. Update `src/cpu/dispatch.zig` to use variant-specific opcodes
2. Generate dispatch table via comptime
3. Wire variant selection from `EmulationState.config.cpu.variant`

**Phase 1C: Testing (1-2 hours)**

1. Create `tests/cpu/opcodes/unstable_variants_test.zig`
2. Test LXA with RP2A03G (0xEE) vs RP2A03H (0xFF)
3. Verify all 562 existing tests pass

**Phase 1D: Documentation (1 hour)**

1. Update `docs/code-review/CPU.md` with variant dispatch architecture
2. Add inline code comments explaining comptime dispatch

#### Test Plan

```zig
// tests/cpu/opcodes/unstable_variants_test.zig
const CpuG = Cpu(.rp2a03g);
const CpuH = Cpu(.rp2a03h);

test "LXA: RP2A03G uses 0xEE magic" {
    const state = makeState(0xFF, 0, 0, clearFlags());
    const result = CpuG.lxa(state, 0xFF);
    // (0xFF | 0xEE) & 0xFF = 0xFF
    try expectRegister(result, "a", 0xFF);
}

test "LXA: RP2A03H uses 0xFF magic" {
    const state = makeState(0x00, 0, 0, clearFlags());
    const result = CpuH.lxa(state, 0xAA);
    // (0x00 | 0xFF) & 0xAA = 0xAA
    try expectRegister(result, "a", 0xAA);
}
```

#### Success Criteria
- [ ] All unstable opcodes use comptime variant config
- [ ] RP2A03G and RP2A03H produce different results for LXA/XAA
- [ ] Zero runtime overhead (verified via generated assembly)
- [ ] 562/562 tests passing + new variant tests
- [ ] Documentation updated

---

### Task 1.2: Cycle-Accurate OAM DMA ⚠️ **REVISED**

**Status:** 🟡 40% Complete (scaffolding exists, needs execution)
**Priority:** HIGH
**Estimated Time:** 8-10 hours (reduced from 12-16)
**Complexity:** HIGH → MEDIUM (trigger logic done)

#### Implementation Plan

**Phase 2A: Understand existing DMA infrastructure (1 hour)**

Review existing code:
- `EmulationState.DmaState` (lines 92-131 in State.zig)
- `DmaState.trigger()` function (lines 118-125)
- `$4014` write handler (lines 290-294)

**Phase 2B: Implement DMA microstep execution (4-5 hours)**

1. Create `tickDma()` function in `EmulationState`
2. Implement cycle-accurate DMA state machine:
   - **Cycle 0**: Wait cycle (if `needs_alignment`)
   - **Cycles 1-512**: Alternating read/write (256 bytes)
     - Even cycles: Read from CPU RAM (`$source_page << 8 + offset`)
     - Odd cycles: Write to PPU OAM (`self.ppu.oam[offset] = temp_value`)
   - **Final cycle**: Clear `dma.active`, resume normal execution

3. Modify `tick()` to check `dma.active` FIRST
4. Ensure PPU continues ticking during DMA

**Code Structure:**
```zig
// In EmulationState
fn tickDma(self: *EmulationState) void {
    // Alignment wait (odd CPU cycle start)
    if (self.dma.needs_alignment and self.dma.current_cycle == 0) {
        self.dma.current_cycle += 1;
        return;  // Dummy cycle
    }

    // DMA transfer: 256 bytes × 2 cycles = 512 cycles
    const cycle_in_transfer = self.dma.current_cycle -
        (if (self.dma.needs_alignment) 1 else 0);

    if (cycle_in_transfer < 512) {
        if (cycle_in_transfer % 2 == 0) {
            // Even cycle: Read from CPU RAM
            const addr = (@as(u16, self.dma.source_page) << 8) | self.dma.current_offset;
            self.dma.temp_value = self.busRead(addr);
        } else {
            // Odd cycle: Write to PPU OAM
            self.ppu.oam[self.dma.current_offset] = self.dma.temp_value;
            self.dma.current_offset +%= 1;
        }
        self.dma.current_cycle += 1;
    } else {
        // DMA complete
        self.dma.reset();
    }
}

pub fn tick(self: *EmulationState) void {
    // Check DMA first - highest priority
    if (self.dma.active) {
        self.tickDma();
        // PPU MUST still tick during DMA!
        self.tickPpu();
        return;
    }

    // Normal emulation path...
    // (existing code unchanged)
}
```

**Phase 2C: Integration Testing (2-3 hours)**

Create `tests/integration/oam_dma_test.zig`:

```zig
test "OAM DMA: transfers 256 bytes correctly" {
    var state = EmulationState.init(&config);
    state.reset();

    // Prepare source data in CPU RAM
    for (0..256) |i| {
        state.bus.ram[@as(u8, @intCast(i))] = @as(u8, @intCast(i));
    }

    // Trigger DMA from page $00
    state.busWrite(0x4014, 0x00);
    try testing.expect(state.dma.active);

    // Run DMA to completion (should be 513 or 514 cycles)
    const start_ppu_cycles = state.clock.ppu_cycles;
    while (state.dma.active) {
        state.tick();
    }
    const elapsed_cpu_cycles = (state.clock.ppu_cycles - start_ppu_cycles) / 3;

    // Verify cycle count (513 or 514)
    try testing.expect(elapsed_cpu_cycles == 513 or elapsed_cpu_cycles == 514);

    // Verify OAM data
    for (0..256) |i| {
        try testing.expectEqual(@as(u8, @intCast(i)), state.ppu.oam[i]);
    }
}

test "OAM DMA: odd cycle alignment adds 1 cycle" {
    var state = EmulationState.init(&config);
    state.reset();

    // Trigger DMA on odd CPU cycle
    state.clock.ppu_cycles = 3;  // CPU cycle 1 (odd)
    state.busWrite(0x4014, 0x00);

    const start_cycles = state.clock.ppu_cycles;
    while (state.dma.active) {
        state.tick();
    }
    const elapsed = (state.clock.ppu_cycles - start_cycles) / 3;

    try testing.expectEqual(@as(u64, 514), elapsed);  // 513 + 1 alignment
}

test "OAM DMA: PPU continues during DMA" {
    var state = EmulationState.init(&config);
    state.reset();

    state.busWrite(0x4014, 0x00);
    const start_scanline = state.ppu_timing.scanline;
    const start_dot = state.ppu_timing.dot;

    // Run DMA for 100 PPU cycles
    for (0..100) |_| {
        state.tick();
    }

    // PPU timing should have advanced
    const advanced = (state.ppu_timing.scanline != start_scanline) or
                     (state.ppu_timing.dot != start_dot);
    try testing.expect(advanced);
}
```

**Phase 2D: Edge Case Testing (1-2 hours)**

Additional test cases:
- DMA triggered during VBlank
- DMA triggered mid-instruction
- Multiple DMA triggers (second should wait)
- DMA from mirrored RAM addresses

**Phase 2E: Documentation (1 hour)**

Update documentation:
- `docs/code-review/MEMORY_AND_BUS.md` - Add DMA section
- `docs/implementation/STATUS.md` - Mark DMA as complete
- Inline code comments in `EmulationState.tickDma()`

#### Success Criteria
- [ ] $4014 write triggers DMA
- [ ] CPU stalls for 513 cycles (even start) or 514 cycles (odd start)
- [ ] All 256 bytes transferred correctly
- [ ] PPU continues ticking during DMA
- [ ] Edge cases handled
- [ ] Integration tests passing
- [ ] 562/562 base tests still passing
- [ ] Zero regressions

---

### Task 1.3: Bus Type Safety ❌ **OBSOLETE**

**Status:** ❌ NOT APPLICABLE
**Reason:** No separate `Bus.zig` module exists in current architecture

**Current Architecture:**
- Bus routing is **INLINE** in `EmulationState.zig`
- No `anytype` parameters (all types are concrete)
- `busRead()` and `busWrite()` are inline functions (lines 220-315)
- PPU pointer is obtained via `cartPtr()` helper (line 263)

**No Action Required:** Architecture is already type-safe.

---

## Implementation Roadmap

### Phase 1: Task 1.1 - Unstable Opcodes (6-8 hours)

**Day 1: Integration (4-6 hours)**
- [ ] Study `variants.zig` architecture (30 min)
- [ ] Move unofficial opcodes to `Cpu(variant)` type factory (2 hours)
- [ ] Update dispatch table generation (1 hour)
- [ ] Wire variant selection from config (1 hour)
- [ ] Initial testing (1-2 hours)

**Day 2: Testing & Polish (2 hours)**
- [ ] Create variant-specific tests (1 hour)
- [ ] Documentation update (30 min)
- [ ] Code review and cleanup (30 min)

**Milestone 1:** All unstable opcodes use comptime variant config

---

### Phase 2: Task 1.2 - OAM DMA (8-10 hours)

**Day 3: Implementation (4-5 hours)**
- [ ] Study existing DMA scaffolding (30 min)
- [ ] Implement `tickDma()` microstep function (2-3 hours)
- [ ] Integrate with `tick()` main loop (30 min)
- [ ] Initial smoke test (1 hour)

**Day 4: Testing (3-4 hours)**
- [ ] Create integration test suite (2 hours)
- [ ] Test edge cases (1 hour)
- [ ] Verify PPU continues during DMA (30 min)
- [ ] Documentation (30 min)

**Day 5: Polish (1 hour)**
- [ ] Code review (30 min)
- [ ] Final regression testing (30 min)

**Milestone 2:** OAM DMA fully functional and tested

---

### Total Estimated Time: 14-18 hours (2-3 days)

**Gantt Chart:**
```
Day 1: [====== Task 1.1: Unstable Opcodes (Day 1) ======]
Day 2: [== Task 1.1 Day 2 ==][====== Task 1.2: DMA (Day 3) ======]
Day 3: [================ Task 1.2 (Day 4-5) ================]
```

---

## Testing Strategy

### Test-Driven Development (TDD) Approach

**For EVERY feature:**

1. **Write Test First**
   - Document expected hardware behavior
   - Create minimal test case that fails
   - Commit failing test (with skip annotation if needed)

2. **Implement Minimal Solution**
   - Make test pass with smallest code change
   - No premature optimization
   - Focus on correctness first

3. **Run Full Suite**
   - `zig build test --summary all`
   - **MUST** show 562/562 + new tests passing
   - Zero regressions allowed

4. **Refactor**
   - Clean up code while tests stay green
   - Improve clarity and performance
   - Maintain architectural patterns

5. **Document**
   - Update relevant docs
   - Add inline comments
   - Update STATUS.md

### Test Coverage Requirements

**Minimum test coverage per task:**

- **Task 1.1 (Unstable Opcodes):**
  - [ ] 2+ tests per variant-dependent opcode (LXA, XAA, SHA)
  - [ ] Verify different results for RP2A03G vs RP2A03H
  - [ ] Edge cases (A=0, A=0xFF, magic constant visibility)

- **Task 1.2 (OAM DMA):**
  - [ ] Basic transfer correctness (256 bytes)
  - [ ] Even cycle start (513 cycles)
  - [ ] Odd cycle start (514 cycles)
  - [ ] PPU continues during DMA
  - [ ] Edge cases (mid-instruction, VBlank, mirrored addresses)

### Regression Prevention

**Before ANY commit:**
```bash
zig build test --summary all
# Expected output: 562/562 tests passed + new tests
```

**No exceptions.** Regressions are not acceptable.

---

## Development Workflow

### Daily Checklist

**Every coding session:**

1. ✅ Pull latest changes (if working in team)
2. ✅ Run full test suite (establish baseline)
3. ✅ Update todo list with current task
4. ✅ Write test for next feature
5. ✅ Implement feature
6. ✅ Run tests (local iteration)
7. ✅ Run full suite (verify no regressions)
8. ✅ Update documentation
9. ✅ Commit with conventional commit message
10. ✅ Update STATUS.md if milestone reached

### Commit Strategy

**Use Conventional Commits:**

```bash
feat(cpu): Add comptime variant dispatch for unstable opcodes
feat(bus): Implement cycle-accurate OAM DMA microsteps
test(cpu): Add RP2A03G vs RP2A03H variant tests
docs(cpu): Document comptime variant architecture
refactor(cpu): Extract DMA logic into dedicated function
```

**Commit Frequency:** Every 2-4 hours of work, or at natural breakpoints.

### Code Review Checkpoints

**Self-review before commit:**

- [ ] Code follows project style (pure functions, State/Logic separation)
- [ ] No heap allocations in hot path
- [ ] All side effects are explicit
- [ ] Tests cover happy path + edge cases
- [ ] Documentation is updated
- [ ] Full test suite passes

---

## Risk Assessment

### High-Risk Areas

#### Risk 1: Comptime Dispatch Complexity ⚠️ MEDIUM

**Issue:** Generating dispatch table at comptime is complex

**Mitigation:**
- Study `Cartridge(MapperType)` pattern (similar comptime generics)
- Start with simple LXA/XAA examples from variants.zig
- Incremental migration (official opcodes first, then unofficial)
- Extensive testing

**Fallback:** Revert to runtime config pointer (Option A) if comptime proves too complex

#### Risk 2: DMA Timing Accuracy ⚠️ HIGH

**Issue:** Exact cycle count is critical for hardware accuracy

**Mitigation:**
- Study NESdev Wiki timing diagrams
- Cross-reference with existing emulators (Mesen, FCEUX)
- Extensive integration tests
- Test with AccuracyCoin ROM

**Validation:** Compare cycle counts with Mesen execution traces

#### Risk 3: Regression Introduction 🟢 LOW

**Issue:** New code might break existing functionality

**Mitigation:**
- TDD approach (write tests first)
- Run full test suite before every commit
- Keep changes minimal and focused
- No premature optimization

**Validation:** 562/562 tests must pass after every change

---

## Success Metrics

### Phase 1 Complete When:

- [ ] All unstable opcodes use comptime variant config
- [ ] RP2A03G and RP2A03H produce different results
- [ ] Zero runtime overhead (assembly verified)
- [ ] New tests pass (10+ variant-specific tests)
- [ ] Documentation updated

### Phase 2 Complete When:

- [ ] $4014 triggers DMA
- [ ] Cycle count matches hardware (513/514)
- [ ] OAM data transfers correctly
- [ ] PPU continues during DMA
- [ ] Integration tests pass (8+ DMA tests)
- [ ] Edge cases handled
- [ ] Documentation updated

### P1 Complete When:

- [ ] All success criteria above met
- [ ] 562/562 base tests + 18+ new tests passing
- [ ] Zero regressions
- [ ] All documentation updated
- [ ] STATUS.md reflects P1 completion
- [ ] Code review self-passed
- [ ] Ready for AccuracyCoin testing

---

## Next Actions

### Immediate (This Session):

1. ✅ **Complete this development plan** (in progress)
2. ⬜ Review with stakeholder (user approval)
3. ⬜ Begin Task 1.1 Phase 1A (update unofficial.zig)

### Short-Term (Next Session):

4. ⬜ Complete Task 1.1 (unstable opcodes)
5. ⬜ Begin Task 1.2 (OAM DMA)

### Medium-Term (This Week):

6. ⬜ Complete Task 1.2 (OAM DMA)
7. ⬜ Update STATUS.md to mark P1 complete
8. ⬜ Prepare for AccuracyCoin test suite run

---

## Conclusion

This development plan provides a **comprehensive, reality-based roadmap** for P1 Accuracy Fixes. Key differences from the original plan:

1. **Comptime generics** for unstable opcodes (not runtime config)
2. **DMA scaffolding** already exists (40% complete)
3. **Task 1.3 obsolete** (no bus anytype to replace)
4. **Reduced timeline** from 22-32 hours to **14-18 hours**

The plan is grounded in the **actual codebase architecture** as audited on 2025-10-06, with detailed implementation steps, test strategies, and risk mitigation.

**Ready to begin execution upon user approval.**

---

**Document Status:** DRAFT - Ready for Review
**Last Updated:** 2025-10-06
**Next Review:** After each task milestone
