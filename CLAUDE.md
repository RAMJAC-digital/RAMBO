# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**RAMBO** is a cycle-accurate NES emulator written in Zig 0.15.1, targeting the comprehensive AccuracyCoin test suite (128 tests covering CPU, PPU, APU, and timing accuracy).

**Current Status (2025-10-06):**
- **Phase 0:** ✅ **COMPLETE** - 100% CPU implementation with cycle-accurate timing
- **CPU:** 100% complete (256/256 opcodes, all addressing modes) ✅
- **Architecture:** State/Logic separation complete, comptime generics implemented ✅
- **Thread Architecture:** Mailbox pattern + timer-driven emulation complete ✅
- **PPU Background:** 100% complete (registers, VRAM, rendering pipeline) ✅
- **PPU Sprites:** 100% complete (73/73 tests passing) ✅
- **Debugger:** 100% complete with callback system (62/62 tests) ✅
- **Controller I/O:** 100% complete ($4016/$4017, 14 tests passing) ✅
- **Bus:** 100% complete (all I/O registers implemented) ✅
- **Cartridge:** Mapper 0 (NROM) complete ✅
- **APU:** 86% complete (6/7 milestones - DMC, Envelopes, Linear Counter, Sweep, Frame IRQ, Open Bus) ⏳
- **Tests:** 729/731 passing (99.7%, 2 skipped due to missing PRG RAM)

**Current Phase:** APU Development - Milestones 5 & 6 ✅ COMPLETE (Frame IRQ Edge Cases + Open Bus)
**Next Phase:** APU Milestone 7 (AccuracyCoin Integration - requires PRG RAM) OR Video Subsystem
**Critical Path:** ✅ P1 Accuracy → ✅ Controller I/O → ✅ APU (86%) → Video → Playable Games

**Key Requirement:** Hardware-accurate 6502 emulation with cycle-level precision for AccuracyCoin compatibility.

---

## Quick Start

### Build Commands

```bash
# Build executable
zig build

# Run all tests (unit + integration)
zig build --summary all test      # 712/714 tests passing (2 skipped)

# Run specific test categories
zig build test-unit               # Unit tests only (fast)
zig build test-integration        # Integration tests (CPU instructions, PPU, etc.)
zig build test-trace              # Cycle-by-cycle execution traces
zig build test-rmw-debug          # RMW instruction debugging

# Run executable (not playable yet - needs video display)
zig build run
```

### Test Status by Category

- **Total:** 712 / 714 tests passing (99.7%, 2 skipped)
- **CPU suites:** 105 unit + integration tests covering all 256 opcodes and microstep timing
- **PPU suites:** 79 tests (background rendering, sprite evaluation, rendering, and edge cases)
- **Debugger:** 62 tests validating breakpoints, watchpoints, and callback wiring
- **Controller:** 14 tests (strobe protocol, shift register, button sequence, open bus)
- **APU:** 60 tests (DMC 25, Envelopes 20, Linear Counter 15, Sweep Units 25, plus framework tests)
- **Mailboxes:** 6 tests (ControllerInputMailbox, thread-safety, atomic updates)
- **Bus & Memory:** 17 tests (open bus, mirroring, mapper routing)
- **Cartridge:** 2 NROM loader/validation tests
- **Snapshot:** 9 tests (metadata, serialization, checksum, load/save)
- **Integration:** 21 multi-component scenarios (CPU⇆PPU, AccuracyCoin traces, OAM DMA)
- **Comptime:** 8 compile-time validation suites for mappers and opcode tables

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

**Tests:** 105/105 passing (100%)

**Files:**
```
src/cpu/
├── Cpu.zig           # Module re-exports
├── State.zig         # CpuState - 6502 registers and microstep state
├── Logic.zig         # Pure functions for CPU operations
├── execution.zig     # Microstep execution engine
├── addressing.zig    # Addressing mode microsteps
├── dispatch.zig      # Opcode → executor mapping
├── constants.zig     # CPU constants
├── helpers.zig       # Helper functions
└── opcodes/          # Pure functional opcodes (12 submodules + mod.zig)
    ├── mod.zig            # Central re-export module (226 lines)
    ├── loadstore.zig      # LDA/LDX/LDY, STA/STX/STY (6 functions)
    ├── arithmetic.zig     # ADC, SBC (2 functions)
    ├── logical.zig        # AND, ORA, EOR (3 functions)
    ├── compare.zig        # CMP, CPX, CPY, BIT (4 functions)
    ├── flags.zig          # CLC, CLD, CLI, CLV, SEC, SED, SEI (7 functions)
    ├── transfer.zig       # TAX, TXA, TAY, TYA, TSX, TXS (6 functions)
    ├── stack.zig          # PHA, PLA, PHP, PLP (4 functions)
    ├── incdec.zig         # INC, DEC, INX, INY, DEX, DEY (6 functions)
    ├── shifts.zig         # ASL, LSR, ROL, ROR variants (8 functions)
    ├── branch.zig         # BCC, BCS, BEQ, BNE, BMI, BPL, BVC, BVS (8 functions)
    ├── control.zig        # JMP, NOP (2 functions)
    └── unofficial.zig     # All 105 unofficial opcodes (20 functions)
```

---

### PPU (`src/ppu/`)

**Status:** ✅ 100% Complete - Background and Sprites Done

**Completed Features:**
- ✅ All 8 PPU registers ($2000-$2007)
- ✅ VRAM system (2KB nametable + 32B palette RAM)
- ✅ Background rendering pipeline (tile fetching, shift registers, pixel output)
- ✅ Sprite evaluation (cycles 1-256) - full algorithm
- ✅ Sprite fetching (cycles 257-320) - pattern data loading
- ✅ Sprite rendering pipeline - pixel output with priority
- ✅ Sprite 0 hit detection - accurate implementation
- ✅ NES NTSC palette (64 colors, RGB888)
- ✅ Scroll management (coarse X/Y, fine X)
- ✅ VBlank timing and NMI generation
- ✅ Horizontal/vertical mirroring

**Missing Features (Future):**
- ⬜ Emphasis bits - minor feature

**Tests:** 79/79 passing (100% - 6 background + 73 sprite)

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

**Status:** ✅ 100% Complete - All I/O Registers Implemented

**Features:**
- ✅ RAM mirroring (2KB → $0000-$1FFF)
- ✅ Open bus tracking with decay timer
- ✅ ROM write protection
- ✅ PPU register routing ($2000-$2007)
- ✅ Controller I/O routing ($4016/$4017)
- ✅ Cartridge integration ($4020-$FFFF)
- ✅ Special methods: `read16()`, `read16Bug()` (JMP indirect page wrap bug)

**Tests:** 17/17 passing (100%)

**Files:**
```
src/bus/
├── Bus.zig           # Module re-exports
├── State.zig         # BusState - RAM, open bus, non-owning component pointers
└── Logic.zig         # Pure functions for bus operations
```

---

### Controller I/O (`src/emulation/State.zig` + `src/mailboxes/`)

**Status:** ✅ 100% Complete - Hardware-Accurate NES Controller Implementation

**Implementation:**
- Cycle-accurate 4021 8-bit shift register emulation
- NES-specific clocking behavior (strobe high prevents shifting)
- Button order: A, B, Select, Start, Up, Down, Left, Right
- Shift register fills with 1s after 8 reads (hardware behavior)
- Open bus bits 5-7 preserved on reads
- Independent dual controller support

**Registers:**
- `$4016` read: Controller 1 serial data (bit 0) + open bus (bits 5-7)
- `$4016` write: Strobe control (bit 0 only, rising edge latches button state)
- `$4017` read: Controller 2 serial data (bit 0) + open bus (bits 5-7)

**Architecture:**
- `ControllerState` embedded in `EmulationState` (follows `DmaState` pattern)
- `ControllerInputMailbox` for thread-safe button state updates
- Pure functional methods: `latch()`, `read1()`, `read2()`, `writeStrobe()`

**Tests:** 20/20 passing (100% - 6 mailbox + 14 integration)

**Files:**
```
src/emulation/State.zig           # ControllerState (lines 133-218)
src/mailboxes/ControllerInputMailbox.zig  # Atomic button state mailbox
tests/integration/controller_test.zig     # 14 comprehensive tests
```

---

### APU (`src/apu/`)

**Status:** ⏳ 86% Complete - 6/7 Milestones Implemented

**Completed Milestones:**
- ✅ **Milestone 1: DMC Channel** - DMA, IRQ, sample playback state (25 tests)
- ✅ **Milestone 2: Envelopes** - Volume control for pulse/noise channels (20 tests)
- ✅ **Milestone 3: Linear Counter** - Triangle channel timing (15 tests)
- ✅ **Milestone 4: Sweep Units** - Pulse channel frequency modulation (25 tests)
- ✅ **Milestone 5: Frame IRQ Edge Cases** - IRQ flag timing refinement (11 tests)
- ✅ **Milestone 6: APU Register Open Bus** - Write-only register behavior (8 tests)

**Remaining Milestones:**
- ⬜ **Milestone 7: Integration & Refinement** - Full AccuracyCoin validation (requires PRG RAM)

**Implementation:**
- Frame counter (4-step/5-step modes) with quarter-frame (240 Hz) and half-frame (120 Hz) clocking
- Generic reusable components: `Envelope` (pulse1, pulse2, noise), `Sweep` (pulse1, pulse2)
- Channel-specific: Linear counter (triangle), DMC state machine
- Register handlers: $4000-$4017 (all APU registers)
- Pure functional architecture with State/Logic separation

**Tests:** 131/131 passing (100%)

**Files:**
```
src/apu/
├── Apu.zig           # Module re-exports
├── State.zig         # ApuState - frame counter, channels, envelopes, sweeps
├── Logic.zig         # Pure functions for APU operations
├── Dmc.zig           # DMC channel logic (140 lines)
├── Envelope.zig      # Generic envelope component (106 lines)
├── Sweep.zig         # Generic sweep component (140 lines)
└── (TODO: waveform generation for Phase 3+)

tests/apu/
├── apu_test.zig              # Frame counter tests (8 tests)
├── length_counter_test.zig   # Length counter tests (25 tests)
├── dmc_test.zig              # DMC channel tests (25 tests)
├── envelope_test.zig         # Envelope tests (20 tests)
├── linear_counter_test.zig   # Linear counter tests (15 tests)
├── sweep_test.zig            # Sweep tests (25 tests)
├── frame_irq_edge_test.zig   # Frame IRQ edge case tests (11 tests)
└── open_bus_test.zig         # APU register open bus tests (8 tests)
```

**Key Features:**
- Cycle-accurate frame counter timing (NTSC timing constants)
- Hardware-accurate sweep units (one's complement for Pulse 1, two's complement for Pulse 2)
- **Frame IRQ edge case:** IRQ flag actively RE-SET during cycles 29829-29831 (prevents software from clearing during critical window)
- **Open bus behavior:** Write-only APU registers ($4000-$4013) return open_bus, $4015 reads don't update open_bus
- DMC DMA integration with CPU cycle stealing
- Quarter-frame clocking: Envelopes + Linear Counter (240 Hz)
- Half-frame clocking: Length Counters + Sweep Units (120 Hz)

**Documentation:**
- `docs/APU-UNIFIED-IMPLEMENTATION-PLAN.md` - Complete implementation roadmap

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
- `docs/archive/DEBUGGER-STATUS.md` - Complete implementation status (archived)
- `docs/archive/DEBUGGER-API-AUDIT.md` - API audit (archived)

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

**Documented in:** `docs/code-review/archive/2025-10-05/02-cpu.md` (archived)

### PRG RAM Not Implemented (High Priority)

**Issue:** PRG RAM ($6000-$7FFF) not implemented - blocks AccuracyCoin test validation

- **Current:** Mapper0 returns open bus (0xFF) for $6000-$7FFF
- **Required:** 8KB battery-backed RAM for test ROMs and save data
- **Impact:** Cannot extract AccuracyCoin test results (writes to $6000-$6003)
- **Workaround:** Use comprehensive unit tests for APU validation (712/714 passing)
- **Priority:** HIGH (blocks AccuracyCoin validation, but not gameplay)
- **Time:** 2-3 hours to implement
- **Status:** Deferred until APU Milestones 2-7 complete

**Documented in:** `docs/PRG-RAM-GAP.md`

---

## Phase 0 Completion Summary

**Date Completed:** 2025-10-06
**Status:** ✅ **COMPLETE** - 100% CPU Implementation with Cycle-Accurate Timing

### Achievements

- **256/256 Opcodes Implemented** (151 official + 105 unofficial)
- **Cycle-Accurate Timing** for all addressing modes
- **Hardware-Accurate Behavior**:
  - Read-Modify-Write dummy write cycles
  - Dummy reads on page crossing
  - Open bus behavior
  - Zero page wrapping
  - NMI edge detection
- **Pure Functional Architecture** with State/Logic separation
- **551/551 Tests Passing** (100%)

### Final P0 Work: Timing Fix

The culminating achievement of P0 was fixing the systematic +1 cycle deviation for indexed addressing modes:

**Problem:** LDA absolute,X took 5 cycles instead of 4 (6 instead of 5 with page cross)
**Root Cause:** Architecture separated operand read (addressing) from execution, while hardware combines them
**Solution:** Conditional fallthrough for indexed modes only (absolute_x, absolute_y, indirect_indexed)
**Result:** Hardware-accurate timing with zero regressions

**Documentation:** `docs/archive/p0/P0-TIMING-FIX-COMPLETION-2025-10-06.md`
**Session History:** `docs/archive/sessions/p0/README.md`

---

## Current Development Phase

### Phase 1 (P1): Accuracy Fixes - Next

**Goal:** Fine-grained accuracy improvements for AccuracyCoin compatibility

**Tasks:**
1. **Unstable Opcode Configuration** - CPU variant-specific behavior for unofficial opcodes
2. **OAM DMA Implementation** - Cycle-accurate PPU/CPU DMA transfer ($4014)
3. **Type Safety Improvements** - Replace `anytype` with concrete types in Bus logic

**Planning:** `docs/code-review/PLAN-P1-ACCURACY-FIXES.md`

### Phase 8: Video Display (Wayland + Vulkan) - Future

**Objective:** Implement Wayland window and Vulkan rendering backend to display PPU frame output.

**Current Status:**
- ✅ FrameMailbox double-buffered (480 KB, RGBA format ready)
- ✅ WaylandEventMailbox scaffolding implemented
- ✅ zig-wayland dependency configured in build.zig.zon
- ⬜ Wayland window integration (not started)
- ⬜ Vulkan rendering backend (not started)

#### **Phase 8.1: Wayland Window** (6-8 hours)

**Tasks:**
1. Create `src/video/Window.zig` - Wayland + XDG shell protocol
2. Implement window creation and surface management
3. Handle input events (keyboard/close)
4. Post events to WaylandEventMailbox
5. Integrate with libxev event loop

**Deliverable:** Wayland window opens, responds to events

#### **Phase 8.2: Vulkan Renderer** (8-10 hours)

**Tasks:**
1. Create `src/video/VulkanRenderer.zig`
2. Initialize Vulkan instance, device, swapchain
3. Setup render pass and graphics pipeline
4. Implement texture upload from FrameMailbox
5. Handle buffer synchronization (double-buffered)

**Deliverable:** Vulkan renders frame data to window

#### **Phase 8.3: Integration** (4-6 hours)

**Tasks:**
1. Connect PPU output to FrameMailbox writes
2. Spawn video thread consuming FrameMailbox
3. Test with AccuracyCoin.nes (background + sprites)
4. Verify 60 FPS rendering stability

**Deliverable:** Full PPU output visible on screen

#### **Phase 8.4: Polish** (2-4 hours)

**Tasks:**
1. Add FPS counter overlay
2. Implement window resize with aspect ratio correction (8:7 pixel aspect)
3. Add vsync support
4. Handle window close gracefully

**Deliverable:** Production-ready video output

**Total Phase 8:** 20-28 hours

---

## Documentation Structure

### Quick Reference

**For Navigation:**
- `docs/README.md` - Documentation hub with component status and quick links
- `CLAUDE.md` (this file) - Development guide and architecture reference

**For Code Review:**
- `docs/code-review/STATUS.md` - Current status and P0 completion
- `docs/code-review/PLAN-P1-ACCURACY-FIXES.md` - Phase 1 planning
- `docs/code-review/archive/2025-10-05/README.md` - Archived code review hub
- `docs/code-review/archive/2025-10-05/01-architecture.md` - Hybrid State/Logic pattern (archived)
- `docs/code-review/archive/2025-10-05/02-cpu.md` - CPU implementation review (archived)

**For Architecture:**
- `docs/architecture/ppu-sprites.md` - Complete sprite rendering specification
- `docs/implementation/design-decisions/final-hybrid-architecture.md` - Hybrid pattern guide
- `docs/archive/code-review-2025-10-04/PHASE-3-COMPTIME-GENERICS-PLAN.md` - Comptime generics design (archived)

**For API Reference:**
- `docs/api-reference/debugger-api.md` - Debugger API guide
- `docs/api-reference/snapshot-api.md` - Snapshot API guide

**For Testing:**
- `docs/testing/accuracycoin-cpu-requirements.md` - Test ROM requirements

**For History:**
- `docs/archive/` - Archived documentation and completed phases
- `docs/archive/sessions/p0/` - Phase 0 development session notes
- `docs/archive/p0/` - Phase 0 completion documentation
- `docs/implementation/completed/` - Completed work summaries

### Key Documents by Task

**Understanding the Codebase:**
1. Read `docs/README.md` for high-level overview and current status
2. Read `docs/code-review/01-architecture.md` for hybrid State/Logic pattern
3. Review `docs/api-reference/` for component APIs

**Implementing New Features:**
1. Check `docs/README.md` for current phase and priorities
2. Review relevant architecture docs in `docs/architecture/`
3. Follow patterns in `docs/implementation/design-decisions/`

**Working with Sprites (Complete):**
1. See `docs/architecture/ppu-sprites.md` for complete specification
2. Review implementation in `src/ppu/State.zig` and `src/ppu/Logic.zig`
3. Check tests in `tests/ppu/sprite_*.zig` (73/73 passing)

---

## Development Workflow

### Phase 8 Workflow (Next)

**Video Subsystem Implementation:**
```bash
# 1. Setup zig-wayland binding (already in build.zig.zon)
zig fetch

# 2. Create video module structure
mkdir -p src/video
touch src/video/Window.zig src/video/VulkanRenderer.zig

# 3. Implement Wayland window management
# Edit src/video/Window.zig
zig build

# 4. Implement Vulkan rendering backend
# Edit src/video/VulkanRenderer.zig
zig build

# 5. Test integration
zig build run

# 6. Commit at milestones
git add src/video/
git commit -m "feat(video): Implement Wayland window management"
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
├── bus/                         # Bus-specific tests (17 tests)
│   └── bus_test.zig                   # RAM mirroring, routing, open bus
├── integration/                 # Cross-component tests (35 tests)
│   ├── cpu_ppu_integration_test.zig   # CPU-PPU coordination
│   ├── oam_dma_test.zig               # OAM DMA (14 tests)
│   └── controller_test.zig            # Controller I/O (14 tests)
├── cpu/                         # CPU tests (105 tests)
│   ├── instructions_test.zig          # Instruction execution
│   ├── unofficial_opcodes_test.zig    # Unofficial opcodes
│   └── rmw_test.zig                   # Read-modify-write
├── ppu/                         # PPU tests (79 tests)
│   ├── sprite_evaluation_test.zig     # Sprite evaluation (15 tests)
│   ├── sprite_rendering_test.zig      # Sprite rendering (23 tests)
│   ├── sprite_edge_cases_test.zig     # Sprite edge cases (35 tests)
│   └── chr_integration_test.zig       # CHR/background (6 tests)
├── debugger/                    # Debugger tests (62 tests)
│   └── debugger_test.zig              # Complete debugger coverage
├── cartridge/                   # Cartridge tests (2 tests)
│   └── accuracycoin_test.zig          # ROM loading and validation
├── snapshot/                    # Snapshot tests (9 tests)
│   └── snapshot_integration_test.zig  # State save/restore
└── comptime/                    # Comptime tests (8 tests)
    └── mapper_generics_test.zig      # Compile-time polymorphism
```

### Running Tests

```bash
# All tests (712/714 passing, 2 skipped)
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

- **Total Tests:** 712/714 (99.7%, 2 skipped)
- **Expected Failures:** 0 (2 AccuracyCoin tests skipped due to missing PRG RAM)

### Architecture Completion

- ✅ **Phase 1:** Bus State/Logic separation (commit 1ceb301)
- ✅ **Phase 2:** PPU State/Logic separation (commit 73f9279)
- ✅ **Phase A:** Backward compatibility cleanup (commit 2fba2fa)
- ✅ **Phase 3:** VTable elimination, comptime generics (commit 2dc78b8)
- ✅ **Phase 4:** Debugger system complete (commit 2e23a4a)
- ✅ **Phase 5:** Snapshot system (commit 65e0651)
- ✅ **Phase 6:** Thread architecture, mailbox pattern (commit cc6734f)
- ✅ **Phase 7:** PPU sprites complete (commit 772484b)
- 🟡 **Phase 8:** Video subsystem (Wayland + Vulkan) - Next

---

## Critical Path to Playability

**Current Progress: 87.5% Architecture Complete**

1. ✅ **CPU Emulation** (100%) - Production ready
2. ✅ **Architecture Refactoring** (100%) - State/Logic, comptime generics
3. ✅ **PPU Background** (100%) - Tile fetching, rendering
4. ✅ **PPU Sprites** (100%) - Evaluation, fetching, rendering pipeline ✨ COMPLETE
5. ✅ **Debugger** (100%) - Full debugging system
6. ✅ **Thread Architecture** (100%) - Mailbox pattern, timer-driven emulation
7. ✅ **Controller I/O** (100%) - $4016/$4017 registers, 4021 shift register ✨ COMPLETE
8. 🟡 **Video Display** (0%) - Wayland + Vulkan backend (scaffolding ready)

**Estimated Time to Playable:** 20-28 hours (2.5-3.5 days)**

---

## Next Actions

### Immediate (Current Session)

1. **Begin Phase 8: Video Subsystem Implementation**
   - Design Wayland window integration
   - Plan Vulkan rendering backend
   - Understand existing WaylandEventMailbox scaffolding

2. **Phase 8.1: Wayland Window (6-8 hours)**
   - Create `src/video/Window.zig` (Wayland + XDG shell)
   - Implement window event handling
   - Post events to WaylandEventMailbox

3. **Phase 8.2: Vulkan Backend (8-10 hours)**
   - Create `src/video/VulkanRenderer.zig`
   - Setup swapchain and render pass
   - Implement texture upload from FrameMailbox

### Next Session

4. **Phase 8.3: Integration (4-6 hours)**
   - Connect PPU rendering to FrameMailbox
   - Connect ControllerInputMailbox to keyboard input
   - Integrate video thread with main loop
   - Test with AccuracyCoin.nes graphics (background + sprites + controller)

5. **Phase 8.4: Polish (2-4 hours)**
   - Add FPS counter
   - Implement window resize handling
   - Aspect ratio correction (8:7 pixel aspect)

6. **Begin Phase 9: Controller I/O (3-4 hours)**
   - Implement $4016/$4017 registers
   - Map keyboard to NES controller
   - Test with interactive ROMs

---

**Last Updated:** 2025-10-06
**Current Phase:** APU Development (4/7 milestones complete)
**Status:** DMC, Envelopes, Linear Counter, Sweep Units complete
**Tests:** 712/714 passing (99.7%, 2 skipped due to missing PRG RAM)
