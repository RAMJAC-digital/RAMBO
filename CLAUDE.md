# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**RAMBO** is a cycle-accurate NES emulator written in Zig 0.15.1, targeting the comprehensive AccuracyCoin test suite (128 tests covering CPU, PPU, APU, and timing accuracy).

**Current Status (2025-10-04):**
- **CPU:** 100% complete (256/256 opcodes) ✅
- **Architecture:** State/Logic separation complete, comptime generics implemented ✅
- **PPU Background:** 100% complete (registers, VRAM, rendering pipeline) ✅
- **PPU Sprites:** 0% implemented (38 tests written, Phase 7 in progress) 🟡
- **Debugger:** 100% complete with callback system (62/62 tests) ✅
- **Bus:** 85% complete (missing controller I/O) 🟡
- **Cartridge:** Mapper 0 (NROM) complete ✅
- **Tests:** 486/496 passing (97.9%) - 10 expected failures (9 sprite, 1 snapshot metadata)

**Current Phase:** Phase 7A - Test Infrastructure (creating bus/integration tests)
**Next Phase:** Phase 7B - Sprite Implementation
**Critical Path:** Sprites → Video Display → Controller I/O → Playable Games

**Key Requirement:** Hardware-accurate 6502 emulation with cycle-level precision for AccuracyCoin compatibility.

---

## Quick Start

### Build Commands

```bash
# Build executable
zig build

# Run all tests (unit + integration)
zig build test                    # 486/496 tests passing

# Run specific test categories
zig build test-unit               # Unit tests only (fast)
zig build test-integration        # Integration tests (CPU instructions, PPU, etc.)
zig build test-trace              # Cycle-by-cycle execution traces
zig build test-rmw-debug          # RMW instruction debugging

# Run executable (not playable yet - needs sprites, video, controller)
zig build run
```

### Test Status by Category

```
Total: 486/496 tests passing (97.9%)

✅ CPU Tests: 283/283 (100%)
✅ PPU Background Tests: 23/23 (100%)
✅ Debugger Tests: 62/62 (100%)
✅ Bus Tests: 17/17 (100%)
✅ Cartridge Tests: 42/42 (100%)
✅ Snapshot Tests: 8/9 (89% - 1 cosmetic metadata issue)
🟡 Sprite Tests: 6/38 (16% - implementation pending)
🟡 Sprite Evaluation Tests: 6/15 (40% - 9 expected failures)
🟡 Sprite Rendering Tests: 0/23 (0% - 23 expected failures)
```

---

## Architecture Overview

### Hybrid State/Logic Pattern

**All core components use State/Logic separation for modularity, testability, and RT-safety.**

#### State Modules (`State.zig`)
- **Pure data structures** with optional non-owning pointers
- **Convenience methods** that delegate to Logic functions
- **Zero hidden state** - fully serializable for save states
- **Examples:** `CpuState`, `BusState`, `PpuState`

```zig
// Example: src/cpu/State.zig
pub const CpuState = struct {
    // Pure data - 6502 registers
    a: u8 = 0,
    x: u8 = 0,
    y: u8 = 0,
    sp: u8 = 0xFD,
    pc: u16 = 0,
    p: StatusRegister = .{},

    // Convenience delegation method
    pub inline fn tick(self: *CpuState, bus: *BusState) void {
        Logic.tick(self, bus);
    }
};
```

#### Logic Modules (`Logic.zig`)
- **Pure functions** operating on State pointers
- **No global state** - deterministic execution
- **All side effects explicit** through parameters
- **Examples:** `CpuLogic`, `BusLogic`, `PpuLogic`

```zig
// Example: src/cpu/Logic.zig
pub fn tick(cpu: *CpuState, bus: *BusState) void {
    // Pure function - all state passed explicitly
    // No hidden dependencies, fully testable
}
```

#### Module Re-exports (`Cpu.zig`, `Bus.zig`, `Ppu.zig`)
- **Clean API** with consistent patterns
- **Type aliases** for convenience
- **No backward compatibility cruft** (cleaned in Phase A)

```zig
// Example: src/cpu/Cpu.zig
pub const State = @import("State.zig");
pub const Logic = @import("Logic.zig");

// Type aliases for convenience
pub const CpuState = State.CpuState;
pub const StatusRegister = State.StatusRegister;
```

### Comptime Generics (Zero-Cost Abstraction)

**All polymorphism uses comptime duck typing - zero runtime overhead.**

```zig
// Generic cartridge type factory
pub fn Cartridge(comptime MapperType: type) type {
    return struct {
        mapper: MapperType,
        prg_rom: []const u8,
        chr_data: []u8,

        // Direct delegation - no VTable, fully inlined
        pub fn cpuRead(self: *const Self, address: u16) u8 {
            return self.mapper.cpuRead(self, address);
        }
    };
}

// Usage - compile-time type instantiation
const Mapper0 = @import("mappers/Mapper0.zig");
const NromCart = Cartridge(Mapper0);  // Zero runtime overhead
```

**Benefits:**
- ✅ No VTables, no runtime indirection
- ✅ All calls fully inlined
- ✅ Compile-time interface verification
- ✅ Type-safe duck typing

---

## Core Components

### CPU (`src/cpu/`)

**Status:** ✅ 100% Complete - Production Ready

**Implementation:**
- Microstep-based state machine (cycle-accurate execution)
- Each instruction broken into individual clock cycles
- 6502 register set: A, X, Y, SP, PC, P (status flags)
- NMI edge detection, IRQ level triggering

**Opcodes:** All 256 implemented (151 official + 105 unofficial)

**Tests:** 283/283 passing (100%)

**Files:**
```
src/cpu/
├── Cpu.zig           # Module re-exports
├── State.zig         # CpuState - 6502 registers and microstep state
├── Logic.zig         # Pure functions for CPU operations
├── opcodes.zig       # 256-opcode compile-time table
├── execution.zig     # Microstep execution engine
├── addressing.zig    # Addressing mode microsteps
├── dispatch.zig      # Opcode → executor mapping
├── constants.zig     # CPU constants
├── helpers.zig       # Helper functions
└── instructions/     # Instruction implementations (11 files)
    ├── loadstore.zig # LDA/LDX/LDY, STA/STX/STY
    ├── arithmetic.zig # ADC, SBC
    ├── logical.zig   # AND, ORA, EOR
    ├── shifts.zig    # ASL, LSR, ROL, ROR
    ├── incdec.zig    # INC, DEC, INX, INY, DEX, DEY
    ├── compare.zig   # CMP, CPX, CPY, BIT
    ├── branch.zig    # BCC, BCS, BEQ, BNE, BMI, BPL, BVC, BVS
    ├── jumps.zig     # JMP, JSR, RTS, RTI, BRK
    ├── stack.zig     # PHA, PLA, PHP, PLP
    ├── transfer.zig  # TAX, TXA, TAY, TYA, TSX, TXS, flag ops
    └── unofficial.zig # All 105 unofficial opcodes
```

---

### PPU (`src/ppu/`)

**Status:** 🟡 60% Complete - Background Done, Sprites Pending

**Completed Features:**
- ✅ All 8 PPU registers ($2000-$2007)
- ✅ VRAM system (2KB nametable + 32B palette RAM)
- ✅ Background rendering pipeline (tile fetching, shift registers, pixel output)
- ✅ NES NTSC palette (64 colors, RGB888)
- ✅ Scroll management (coarse X/Y, fine X)
- ✅ VBlank timing and NMI generation
- ✅ Horizontal/vertical mirroring

**Missing Features (Phase 7):**
- ❌ Sprite evaluation (cycles 1-256)
- ❌ Sprite fetching (cycles 257-320)
- ❌ Sprite rendering pipeline
- ❌ Sprite 0 hit detection
- ❌ OAM DMA ($4014)

**Tests:** 29/61 passing (48% - 32 sprite tests failing as expected)

**Files:**
```
src/ppu/
├── Ppu.zig           # Module re-exports
├── State.zig         # PpuState - registers, VRAM, OAM, rendering state
├── Logic.zig         # Pure functions for PPU operations
├── palette.zig       # NES color palette (64 colors)
└── timing.zig        # PPU timing constants (341 dots × 262 scanlines)
```

---

### Bus (`src/bus/`)

**Status:** ✅ 85% Complete - Missing Controller I/O

**Features:**
- ✅ RAM mirroring (2KB → $0000-$1FFF)
- ✅ Open bus tracking with decay timer
- ✅ ROM write protection
- ✅ PPU register routing ($2000-$2007)
- ✅ Cartridge integration ($4020-$FFFF)
- ✅ Special methods: `read16()`, `read16Bug()` (JMP indirect page wrap bug)
- ❌ Controller I/O ($4016/$4017) - Phase 9

**Tests:** 17/17 passing (100%)

**Files:**
```
src/bus/
├── Bus.zig           # Module re-exports
├── State.zig         # BusState - RAM, open bus, non-owning component pointers
└── Logic.zig         # Pure functions for bus operations
```

---

### Cartridge (`src/cartridge/`)

**Status:** ✅ Mapper 0 Complete - Generic Architecture Ready

**Implementation:**
- iNES ROM format parser with validation
- Generic `Cartridge(MapperType)` type factory
- Comptime duck typing (zero VTable overhead)
- Single-threaded RT-safe access

**Mapper Coverage:**
- ✅ Mapper 0 (NROM) - ~5% of NES library
- ⬜ Mapper 1 (MMC1) - +28% coverage (planned)
- ⬜ Mapper 4 (MMC3) - +25% coverage (planned)

**Tests:** 42/42 passing (100%)

**Files:**
```
src/cartridge/
├── Cartridge.zig     # Generic Cartridge(MapperType) type factory
├── ines.zig          # iNES format parser
├── loader.zig        # File loading (sync)
└── mappers/
    └── Mapper0.zig   # NROM - duck-typed interface (no VTable)
```

---

### Debugger (`src/debugger/`)

**Status:** ✅ 100% Complete - Production Ready

**Features:**
- ✅ Breakpoints (execute, memory access with conditions)
- ✅ Watchpoints (read, write, change with address ranges)
- ✅ Step execution (instruction, scanline, frame, step over/out)
- ✅ User callbacks (onBeforeInstruction, onMemoryAccess)
- ✅ RT-safe (zero heap allocations in hot path)
- ✅ Async/libxev compatible
- ✅ History buffer (snapshot-based time-travel debugging)

**Tests:** 62/62 passing (100%)

**Files:**
```
src/debugger/
└── Debugger.zig      # External wrapper pattern - zero EmulationState modifications
```

**Documentation:**
- `docs/DEBUGGER-STATUS.md` - Complete implementation status
- `docs/DEBUGGER-API-AUDIT.md` - API audit (zero issues found)

---

## Critical Hardware Behaviors

### 1. Read-Modify-Write (RMW) Dummy Write

**ALL RMW instructions (ASL, LSR, ROL, ROR, INC, DEC) MUST write the original value back before writing the modified value.**

```zig
// INC $10: 5 cycles
// Cycle 3: Read value from $10
// Cycle 4: Write ORIGINAL value back to $10  <-- CRITICAL!
// Cycle 5: Write INCREMENTED value to $10
```

This is visible to memory-mapped I/O and tested by AccuracyCoin.

### 2. Dummy Reads on Page Crossing

When indexed addressing crosses a page boundary (e.g., `LDA $10FF,X` with X=$02):
- Cycle 4: Dummy read at WRONG address (low byte wrapped, high byte not yet fixed)
- Cycle 5: Read from correct address

**The dummy read address is `(base_high << 8) | ((base_low + index) & 0xFF)`**

### 3. Open Bus Behavior

Every bus read/write updates the data bus. Reading unmapped memory returns the last bus value. This is tracked explicitly in `BusState.open_bus`.

### 4. Zero Page Wrapping

Zero page indexed addressing MUST wrap within page 0:
```zig
// LDA $FF,X with X=$02 -> reads from $01, NOT $101
address = @as(u16, (base +% index))  // Wraps at byte boundary
```

### 5. NMI Edge Detection

NMI triggers on falling edge (high → low transition), not level. IRQ is level-triggered.

---

## Known Issues & Deviations

### CPU Timing Deviation (Medium Priority)

**Issue:** Absolute,X/Y reads without page crossing have +1 cycle deviation

- **Hardware:** 4 cycles (dummy read IS the actual read)
- **Implementation:** 5 cycles (separate addressing + execute states)
- **Impact:** Functionally correct, timing off by +1 cycle
- **Priority:** MEDIUM (defer to post-playability)
- **Fix:** State machine refactor to support in-cycle execution completion

**Documented in:** `docs/code-review/02-cpu.md`

---

## Current Development Phase

### Phase 7: Sprite Implementation (In Progress)

**Revised Structure (based on QA review):**

#### **Phase 7A: Test Infrastructure** ⚠️ **CURRENT - MUST BE FIRST**
**Duration:** 28-38 hours
**Status:** In Progress

**Sub-phases:**
1. **7A.1: Bus Integration Tests** (8-12 hours, 15-20 tests)
   - RAM mirroring validation
   - PPU register mirroring
   - ROM write protection
   - Open bus behavior
   - Cartridge routing

2. **7A.2: CPU-PPU Integration Tests** (12-16 hours, 20-25 tests)
   - NMI triggering during execution
   - PPU register access timing
   - DMA suspension
   - Rendering effects on register behavior

3. **7A.3: Expanded Sprite Test Coverage** (8-10 hours, 35 tests)
   - Sprite 0 hit edge cases
   - Overflow hardware bug
   - 8×16 mode comprehensive
   - Transparency edge cases

**Deliverable:** 70-80 new tests, solid foundation for sprite work

#### **Phase 7B: Sprite Implementation** (29-42 hours - NEXT)
**Prerequisites:** Phase 7A complete

**Sub-phases:**
1. Sprite Evaluation (8-12 hours)
2. Sprite Fetching (6-8 hours)
3. Sprite Rendering (8-12 hours)
4. OAM DMA (3-4 hours)

#### **Phase 7C: Validation & Integration** (28-38 hours - FUTURE)
**Prerequisites:** Phase 7B complete

**Tasks:**
1. Regression test suite (40 tests, 16-20 hours)
2. AccuracyCoin automated testing (12 tests, 16-20 hours)
3. Visual regression testing (8-12 hours)

**Total Phase 7:** 85-118 hours, 172-182 new tests

---

## Documentation Structure

### Quick Reference

**For Implementation:**
- `CLAUDE.md` (this file) - Project overview and development guide
- `docs/DEVELOPMENT-PLAN-2025-10-04.md` - Comprehensive development plan
- `docs/PHASE-7-ACTION-PLAN.md` - Detailed Phase 7 plan with test requirements
- `docs/SPRITE-RENDERING-SPECIFICATION.md` - Complete sprite rendering spec

**For Code Review:**
- `docs/code-review/README.md` - Code review overview
- `docs/code-review/REFACTORING-ROADMAP.md` - Architecture refactoring status
- `docs/code-review/03-ppu.md` - PPU review findings

**For Testing:**
- `docs/PHASE-4-1-TEST-STATUS.md` - Sprite evaluation test status
- `docs/PHASE-4-2-TEST-STATUS.md` - Sprite rendering test status

**For Architecture:**
- `docs/code-review/01-architecture.md` - Hybrid architecture overview
- `docs/06-implementation-notes/design-decisions/video-subsystem-architecture.md` - Video system design

**For Debugging:**
- `docs/DEBUGGER-STATUS.md` - Complete debugger status
- `docs/DEBUGGER-API-AUDIT.md` - API audit results

### Key Documents by Purpose

**Starting New Work:**
1. Read `DEVELOPMENT-PLAN-2025-10-04.md` for current priorities
2. Read `PHASE-7-ACTION-PLAN.md` for detailed phase plan
3. Check `docs/code-review/REFACTORING-ROADMAP.md` for architecture patterns

**Implementing Sprites:**
1. Read `SPRITE-RENDERING-SPECIFICATION.md` for complete hardware spec
2. Check `PHASE-4-1-TEST-STATUS.md` for evaluation test status
3. Check `PHASE-4-2-TEST-STATUS.md` for rendering test status

**Understanding Architecture:**
1. Read `docs/code-review/01-architecture.md` for hybrid State/Logic pattern
2. Read `docs/code-review/REFACTORING-ROADMAP.md` for refactoring history
3. Check module source files for implementation examples

---

## Development Workflow

### Phase 7A Workflow (Current)

**Creating Bus Integration Tests:**
```bash
# 1. Create test file
touch tests/bus/bus_integration_test.zig

# 2. Implement tests following TDD pattern
# 3. Run tests
zig build test

# 4. Verify all tests compile and document expected failures
# 5. Commit at milestones (every 5-10 tests)
git add tests/bus/bus_integration_test.zig
git commit -m "test(bus): Add RAM mirroring integration tests (5 tests)"

# 6. Update documentation
# 7. Continue with next test category
```

### Phase 7B Workflow (Next)

**Sprite Implementation (Test-Driven):**
```bash
# 1. Choose sub-phase (evaluation, fetching, rendering, DMA)
# 2. Run failing tests to understand requirements
zig build test

# 3. Implement feature in src/ppu/State.zig and Logic.zig
# 4. Run tests after each change
zig build test

# 5. Commit when tests pass
git add src/ppu/State.zig src/ppu/Logic.zig
git commit -m "feat(ppu): Implement sprite evaluation (cycles 1-64)"

# 6. Continue to next sub-phase
```

### General Development Principles

1. **Test-Driven Development:** Write/review tests before implementation
2. **Frequent Commits:** Commit at milestones (every 2-4 hours of work)
3. **Update Documentation:** Keep CLAUDE.md and roadmaps current
4. **Run Full Test Suite:** `zig build test` before every commit
5. **No Regressions:** All existing tests must continue passing

---

## Testing Strategy

### Test Organization

```
tests/
├── bus/                         # Bus-specific tests
│   └── bus_integration_test.zig       # NEW - Phase 7A.1
├── integration/                 # Cross-component tests
│   └── cpu_ppu_integration_test.zig   # NEW - Phase 7A.2
├── cpu/                         # CPU tests (283 tests)
│   ├── instructions_test.zig          # Instruction execution
│   ├── unofficial_opcodes_test.zig    # Unofficial opcodes
│   └── rmw_test.zig                   # Read-modify-write
├── ppu/                         # PPU tests (61 tests)
│   ├── sprite_evaluation_test.zig     # Sprite evaluation (15 tests)
│   ├── sprite_rendering_test.zig      # Sprite rendering (23 tests)
│   ├── sprite_edge_cases_test.zig     # NEW - Phase 7A.3
│   └── chr_integration_test.zig       # CHR memory integration
├── debugger/                    # Debugger tests (62 tests)
│   └── debugger_test.zig              # Complete debugger coverage
├── cartridge/                   # Cartridge tests (42 tests)
│   └── accuracycoin_test.zig          # AccuracyCoin loading
└── snapshot/                    # Snapshot tests (9 tests)
    └── snapshot_integration_test.zig  # State save/restore
```

### Running Tests

```bash
# All tests (486/496 passing)
zig build test

# Specific categories
zig build test-unit               # Fast unit tests only
zig build test-integration        # Integration tests only
zig build test-trace              # Cycle-by-cycle traces

# Individual test files
zig test tests/cpu/instructions_test.zig --dep RAMBO -Mroot=src/root.zig
zig test tests/ppu/sprite_evaluation_test.zig --dep RAMBO -Mroot=src/root.zig
```

---

## Important Notes

### Environment

- **Zig Version:** 0.15.1 (check with `zig version`)
- **AccuracyCoin ROM:** `AccuracyCoin/AccuracyCoin.nes` (32KB PRG, 8KB CHR, Mapper 0)
- **libxev:** Integrated but not yet used (future async I/O)

### Test Status

- **Total Tests:** 486/496 (97.9%)
- **Expected Failures:** 10
  - 9 sprite tests (implementation pending in Phase 7B)
  - 1 snapshot metadata test (cosmetic issue)

### Architecture Completion

- ✅ **Phase 1:** Bus State/Logic separation (commit 1ceb301)
- ✅ **Phase 2:** PPU State/Logic separation (commit 73f9279)
- ✅ **Phase A:** Backward compatibility cleanup (commit 2fba2fa)
- ✅ **Phase 3:** VTable elimination, comptime generics (commit 2dc78b8)
- ✅ **Phase 4:** Debugger system complete (commit 2e23a4a)
- 🟡 **Phase 7A:** Test infrastructure (IN PROGRESS)

---

## Critical Path to Playability

**Current Progress: 64% Architecture Complete**

1. ✅ **CPU Emulation** (100%) - Production ready
2. ✅ **Architecture Refactoring** (100%) - State/Logic, comptime generics
3. ✅ **PPU Background** (100%) - Tile fetching, rendering
4. ✅ **Debugger** (100%) - Full debugging system
5. 🟡 **Phase 7A: Test Infrastructure** (IN PROGRESS) - Bus/integration tests
6. ⬜ **Phase 7B: Sprite Implementation** (0%) - 38 tests ready
7. ⬜ **Phase 7C: Validation** (0%) - AccuracyCoin, regression tests
8. ⬜ **Phase 8: Video Display** (0%) - OpenGL backend (architecture designed)
9. ⬜ **Phase 9: Controller I/O** (0%) - $4016/$4017 registers

**Estimated Time to Playable:** 108-147 hours (14-19 days)

---

## Next Actions

### Immediate (Current Session)

1. **Complete Phase 7A.1: Bus Integration Tests**
   - Create `tests/bus/bus_integration_test.zig`
   - Implement 15-20 bus integration tests
   - Verify all tests compile and run

2. **Begin Phase 7A.2: CPU-PPU Integration Tests**
   - Create `tests/integration/cpu_ppu_integration_test.zig`
   - Implement NMI triggering tests
   - Implement register access tests

3. **Update Documentation**
   - Update roadmap documents with Phase 7A progress
   - Commit at milestones
   - Keep CLAUDE.md current

### Next Session

4. **Complete Phase 7A.2 and 7A.3**
5. **Verify all 70-80 new tests passing**
6. **Commit Phase 7A with comprehensive documentation**
7. **Begin Phase 7B: Sprite Implementation**

---

**Last Updated:** 2025-10-04
**Current Phase:** 7A (Test Infrastructure)
**Status:** Ready for implementation
**Tests:** 486/496 passing (97.9%)
