# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**RAMBO** is a cycle-accurate NES emulator written in Zig 0.15.1, targeting the comprehensive AccuracyCoin test suite (128 tests covering CPU, PPU, APU, and timing accuracy).

**Current Status (2025-10-08):**
- **Phase 0:** ✅ **COMPLETE** - 100% CPU implementation with cycle-accurate timing
- **CPU Opcodes:** 100% complete (256/256 opcodes, all addressing modes) ✅
- **CPU Interrupts:** ❌ **NOT IMPLEMENTED** - NMI/IRQ/BRK sequences missing (**P0 BLOCKER**)
- **Architecture:** State/Logic separation complete, comptime generics implemented ✅
- **Thread Architecture:** Mailbox pattern + timer-driven emulation complete ✅
- **PPU Background:** 100% complete (registers, VRAM, rendering pipeline) ✅
- **PPU Sprites:** 100% complete (73/73 tests passing) ✅
- **PPU Accuracy:** ✅ **VERIFIED HARDWARE-ACCURATE** (comprehensive audit + warm-up period)
- **PPU Warm-up Period:** ✅ **IMPLEMENTED** (29,658 cycles, power-on vs RESET distinction)
- **Debugger:** 100% complete with callback system (62/62 tests) ✅
- **Controller I/O:** ✅ **100% COMPLETE & WIRED** ($4016/$4017 + mailbox → emulation)
- **Input System:** ✅ **WIRED TO EMULATION** (ButtonState, KeyboardMapper, thread-safe mailbox)
- **Bus:** 100% complete (all I/O registers implemented) ✅
- **Cartridge:** Mapper 0 (NROM) complete with full IRQ infrastructure ✅
- **Mapper System:** ✅ **FOUNDATION COMPLETE** - AnyCartridge union, IRQ support, A12 tracking
- **Video Display:** ✅ **COMPLETE** - Wayland window + Vulkan rendering at 60 FPS
- **Tests:** 920/927 passing (99.2%, 5 commercial ROM tests fail - NMI blocker, 2 threading tests)
- **AccuracyCoin:** ✅ **ALL TESTS PASSING** ($00 $00 $00 $00 status - full CPU/PPU validation)

**CRITICAL BLOCKER:** 🔴 **NMI INTERRUPT HANDLING NOT IMPLEMENTED**
- NMI/IRQ/BRK states defined in enum but **NEVER implemented** in stepCpuCycle()
- PPU VBlank sets NMI flag correctly ✅
- CPU edge detection works correctly ✅
- **But interrupt sequence never executes** ❌
- **Impact:** ALL commercial games hang in infinite loops waiting for NMI

**Current Phase:** CPU Interrupt Implementation (P0 SHOWSTOPPER)
**Next Phase:** Commercial ROM Validation → Mapper Expansion
**Critical Path:** ❌ **BLOCKED ON NMI IMPLEMENTATION** (est. 4-6 hours)

**Key Requirement:** Hardware-accurate 6502 emulation with cycle-level precision for AccuracyCoin compatibility.

---

## Recent Critical Fixes (2025-10-07)

### ✅ PPU Warm-Up Period (FIXED)

**Problem:** Commercial games (Mario 1, Burger Time) showed blank screens while test ROMs worked correctly.

**Root Cause:** Missing NES hardware warm-up period implementation. The PPU ignores writes to registers $2000/$2001/$2005/$2006 for the first 29,658 CPU cycles (~0.5 seconds) after power-on.

**Solution:**
- Implemented `warmup_complete` flag in PpuState
- Emulation tracks CPU cycle count and sets flag after warm-up
- PPU register writes gated during warm-up period
- Distinguished power-on (needs warm-up) from RESET (skips warm-up)

**Files Modified:**
- `src/ppu/State.zig` - Added warmup_complete flag
- `src/ppu/Logic.zig` - Gated register writes, RESET handling
- `src/emulation/State.zig` - Cycle tracking and flag setting
- `src/emulation/Ppu.zig` - Diagnostic logging

**Documentation:** `docs/implementation/PPU-WARMUP-PERIOD-FIX.md`

**Impact:** Commercial games now initialize correctly and prepare for rendering.

### ✅ Controller Input Wiring (FIXED)

**Problem:** Games stuck at title screens, waiting for START button press that never arrived.

**Root Cause:** ControllerInputMailbox was implemented but never connected to emulation thread. Keyboard input reached the mailbox but was never polled by the emulation.

**Solution:**
- EmulationThread now polls controller_input mailbox every frame
- Converts ButtonState to u8 and updates ControllerState
- Properly synchronizes input at 60 Hz with emulation timing

**Files Modified:**
- `src/threads/EmulationThread.zig` - Added mailbox polling in timerCallback

**Documentation:** `docs/implementation/CONTROLLER-INPUT-FIX-2025-10-07.md`

**Impact:** Games should now respond to controller input. This was the FINAL missing piece for playability!

**Test Status:** 896/900 tests passing (3 timing-sensitive threading tests, no functional regressions)

### 🔴 CRITICAL FINDING: NMI Interrupts Not Implemented (2025-10-08)

**Discovery:** After extensive debugging (20+ diagnostic traces), discovered that **NMI/IRQ/BRK interrupt handling is completely missing** from the CPU emulation.

**Root Cause:** Interrupt states (`.interrupt_dummy`, `.interrupt_push_pch`, `.interrupt_push_pcl`, `.interrupt_push_p`, `.interrupt_fetch_vector_low`, `.interrupt_fetch_vector_high`) are **defined in ExecutionState enum but have ZERO implementation** in `stepCpuCycle()`.

**Investigation Path:**
1. ✅ PPU VBlank sets correctly at scanline 241, dot 1
2. ✅ `flags.assert_nmi` set based on `nmi_enable`
3. ✅ `cpu.nmi_line` asserted in EmulationState
4. ✅ CPU edge detection triggers
5. ✅ `pending_interrupt = .nmi` set
6. ✅ `startInterruptSequence()` called
7. ❌ **CPU enters `.interrupt_dummy` state and gets STUCK FOREVER**

**Impact:**
- ✅ Test ROMs work (AccuracyCoin doesn't rely on precise NMI timing)
- ❌ ALL commercial games hang in infinite loops waiting for NMI
- ❌ Games stuck at PC addresses in initialization code
- ❌ PPUMASK never progresses past initialization values ($00, $06, $08)

**Required Implementation:** 7-cycle interrupt sequence
1. Cycle 1: Dummy read at current PC
2. Cycle 2: Push PCH to stack
3. Cycle 3: Push PCL to stack
4. Cycle 4: Push P register (with B flag handling for BRK)
5. Cycle 5: Fetch vector low byte ($FFFA=NMI, $FFFE=IRQ/BRK, $FFFC=RESET)
6. Cycle 6: Fetch vector high byte
7. Cycle 7: Jump to handler (PC = vector)

**Files Modified During Investigation:**
- `tests/helpers/FramebufferValidator.zig` - Created (252 lines)
- `tests/integration/commercial_rom_test.zig` - Created (356 lines)
- `build.zig` - Registered new tests

**Documentation:**
- `docs/sessions/2025-10-08-nmi-interrupt-investigation/CRITICAL-FINDING-NMI-NOT-IMPLEMENTED.md`
- `docs/sessions/2025-10-08-nmi-interrupt-investigation/SESSION-SUMMARY.md`

**Estimated Fix Time:** 4-6 hours implementation + 2-3 hours validation = **8-11 hours total**

---

## Quick Start

### Build Commands

```bash
# Build executable
zig build

# Run all tests (unit + integration)
zig build test      # 896/900 tests passing (99.6%, 3 threading tests timing-sensitive)

# Run specific test categories
zig build test-unit               # Unit tests only (fast)
zig build test-integration        # Integration tests (CPU instructions, PPU, etc.)
zig build test-trace              # Cycle-by-cycle execution traces
zig build test-rmw-debug          # RMW instruction debugging

# Run executable (READY FOR TESTING!)
zig build run
# Load Mario 1 or Burger Time
# Press ENTER (START) to advance from title screen
# Arrow keys = D-pad, Z = B, X = A
```

### Test Status by Category

- **Total:** 896 / 900 tests passing (99.6%, 3 timing-sensitive threading tests, 1 skipped)
- **CPU suites:** ~280 tests (264 in tests/cpu/ + 16 embedded) covering all 256 opcodes and microstep timing
- **PPU suites:** ~90 tests (79 in tests/ppu/ + 11 embedded) - background rendering, sprite evaluation/rendering, edge cases
- **APU suites:** 135 tests (frame counter, DMC, envelopes, sweeps, length counter, IRQ edge cases)
- **Debugger:** ~66 tests (62 in tests/ + 4 embedded) - breakpoints, watchpoints, callback wiring
- **Controller:** 14 tests (strobe protocol, shift register, button sequence, open bus)
- **Input System:** 40 tests (19 ButtonState + 21 KeyboardMapper, unified type, RT-safe) ✨ **AUDITED & OPTIMIZED**
- **Mailboxes:** 57 tests (all mailbox types, thread-safety, atomic updates, ring buffers)
- **Bus & Memory:** ~20 tests (17 in tests/bus/ + 3 embedded) - open bus, mirroring, mapper routing
- **Cartridge:** ~48 tests (13 in tests/ + 35 embedded) - NROM, iNES parsing, PRG RAM, registry
- **Snapshot:** ~23 tests (9 in tests/ + 14 embedded) - metadata, serialization, checksum, load/save
- **Integration:** 94 tests (CPU⇆PPU, AccuracyCoin traces, OAM DMA, controller I/O, benchmarks)
- **Threading:** 14 tests (EmulationThread, RenderThread coordination, frame timing) - 3 timing-sensitive
- **Config:** ~30 tests (15 in tests/ + 15 embedded) - parser, validation, defaults
- **Comptime:** 8 compile-time validation suites for mappers and opcode tables
- **AccuracyCoin:** ✅ **PASSING** - Full CPU/PPU validation (status bytes: $00 $00 $00 $00)

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

### Bus (`src/emulation/State.zig`)

**Status:** ✅ 100% Complete - All I/O Registers Implemented

**Architecture Note:** BusState is integrated into `EmulationState` rather than a separate module, as bus operations are tightly coupled with emulation coordination.

**Features:**
- ✅ RAM mirroring (2KB → $0000-$1FFF)
- ✅ Open bus tracking with decay timer
- ✅ ROM write protection
- ✅ PPU register routing ($2000-$2007)
- ✅ Controller I/O routing ($4016/$4017)
- ✅ Cartridge integration ($4020-$FFFF)
- ✅ Special methods: `read16()`, `read16Bug()` (JMP indirect page wrap bug)

**Tests:** ~20 tests (17 in tests/bus/ + 3 embedded)

**Implementation:**
- `BusState` struct in `src/emulation/State.zig:47-56`
- Bus logic methods in `EmulationState` for CPU/PPU bus access
- Integrated with cartridge mapper routing

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

**Tests:** 135/135 passing (100%)

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

**Status:** ✅ Mapper System Foundation COMPLETE - Ready for Expansion

**Implementation:**
- ✅ **AnyCartridge Tagged Union** - Zero-cost polymorphism with inline dispatch
- ✅ **Duck-Typed Mapper Interface** - Compile-time verification, no VTables
- ✅ **IRQ Infrastructure** - Full MMC3 IRQ support (A12 edge detection, IRQ polling)
- ✅ **State Isolation** - All mapper state in mapper structs, side effects in EmulationState.tick()
- iNES ROM format parser with validation
- Generic `Cartridge(MapperType)` type factory (comptime generics)
- Single-threaded RT-safe access

**Mapper Coverage:**
- ✅ Mapper 0 (NROM) - ~5% of NES library
- ⬜ Mapper 1 (MMC1) - +28% coverage (planned)
- ⬜ Mapper 2 (UxROM) - +11% coverage (planned)
- ⬜ Mapper 3 (CNROM) - +6% coverage (planned)
- ⬜ Mapper 4 (MMC3) - +25% coverage (planned)
- **Target:** 75% game coverage with mappers 0-4

**IRQ Features (Ready for MMC3):**
- PPU A12 edge detection in `EmulationState.tickPpu()`
- Mapper IRQ polling every CPU cycle
- IRQ acknowledgment via mapper method calls
- Full state isolation (no global IRQ state)

**Tests:** 47/47 passing (100%)
- 2 NROM loader/validation tests
- 45 mapper registry tests (AnyCartridge dispatch, IRQ interface)

**Files:**
```
src/cartridge/
├── Cartridge.zig           # Generic Cartridge(MapperType) type factory
├── ines.zig                # iNES format parser
├── loader.zig              # File loading (sync)
└── mappers/
    ├── registry.zig        # AnyCartridge union + mapper registry (370 lines)
    └── Mapper0.zig         # NROM - duck-typed interface with IRQ stubs
```

**Architecture Highlights:**
- **Tagged Union Dispatch:** `inline else` for zero-overhead polymorphism
- **Duck Typing:** Each mapper implements required methods, compiler verifies at compile-time
- **Extensibility:** Add new mappers as union variants (no VTable changes needed)
- **Documentation:** `docs/implementation/MAPPER-SYSTEM-SUMMARY.md`

---

### Debugger (`src/debugger/`)

**Status:** ✅ 100% Complete - Production Ready with Bidirectional Mailboxes

**Features:**
- ✅ Breakpoints (execute, memory access with conditions)
- ✅ Watchpoints (read, write, change with address ranges)
- ✅ Step execution (instruction, scanline, frame, step over/out)
- ✅ User callbacks (onBeforeInstruction, onMemoryAccess)
- ✅ RT-safe (zero heap allocations in hot path)
- ✅ Async/libxev compatible
- ✅ History buffer (snapshot-based time-travel debugging)
- ✅ **Bidirectional mailboxes (2025-10-08)** - Lock-free thread communication

**Bidirectional Communication:**
- `DebugCommandMailbox` (Main → Emulation) - 64-command ring buffer
- `DebugEventMailbox` (Emulation → Main) - 32-event ring buffer
- CPU snapshots included with debug events
- --inspect flag for automatic state display
- RT-safe: All `std.debug.print` removed from emulation thread

**Tests:** 62/62 passing (100%)

**Files:**
```
src/debugger/
└── Debugger.zig                      # External wrapper pattern - zero EmulationState modifications

src/mailboxes/
├── DebugCommandMailbox.zig           # Main → Emulation commands (179 lines)
└── DebugEventMailbox.zig             # Emulation → Main events (179 lines)
```

**Documentation:**
- `docs/implementation/BIDIRECTIONAL-DEBUG-MAILBOXES-2025-10-08.md` - Complete mailbox implementation
- `docs/api-reference/debugger-api.md` - Full API guide (updated 2025-10-08)
- `docs/archive/DEBUGGER-STATUS.md` - Complete implementation status (archived)
- `docs/archive/DEBUGGER-API-AUDIT.md` - API audit (archived)

---

### Input System (`src/input/`)

**Status:** ✅ 50% Complete - Keyboard Input WIRED & AUDITED, Ready for Testing!

**Goal:** Unified input architecture supporting both keyboard and TAS playback through single ControllerInputMailbox interface.

**Completed:**
- ✅ **ButtonState** - NES controller state (8 buttons packed into 1 byte)
  - Unified type (single definition across codebase)
  - Packed struct matching hardware button order (A, B, Select, Start, Up, Down, Left, Right)
  - Byte conversion methods (toByte/fromByte)
  - D-pad sanitization (opposing directions cleared)
  - 21 unit tests passing (100% coverage, external tests only)
- ✅ **KeyboardMapper** - Wayland keyboard events → ButtonState
  - Complete implementation (95 lines, optimized)
  - Default mapping: Arrow keys (D-pad), Z (B), X (A), RShift (Select), Enter (Start)
  - Automatic sanitization on key press
  - 20 unit tests passing (external tests only, 100% coverage)
- ✅ **Main thread integration** - Keyboard input wired to emulation
  - KeyboardMapper integrated with XdgInputEventMailbox
  - ButtonState posted to ControllerInputMailbox every frame (60Hz)
  - Pure message passing - no shared references
  - RT-safe - no heap allocations or blocking I/O

**Planned:**
- ⬜ **TASPlayer** - Frame-by-frame button playback from file
- ⬜ **InputMode** - Enum for keyboard/TAS/disabled modes
- ⬜ **Integration tests** - End-to-end keyboard input verification

**Architecture:**
```
Keyboard Events → KeyboardMapper → ButtonState → ControllerInputMailbox → Emulation
TAS File → TASPlayer → ButtonState → ControllerInputMailbox → Emulation
```

**Tests:** 41/63 passing (21 ButtonState + 20 KeyboardMapper + 0 Integration)

**Files:**
```
src/input/
├── ButtonState.zig      # ✅ Complete (80 lines, audited)
├── KeyboardMapper.zig   # ✅ Complete (95 lines, audited)
├── TASPlayer.zig        # TODO
└── InputMode.zig        # TODO

src/mailboxes/
└── ControllerInputMailbox.zig  # ✅ Uses unified ButtonState

tests/input/
├── button_state_test.zig      # ✅ 21 tests passing
├── keyboard_mapper_test.zig   # ✅ 20 tests passing
└── tas_player_test.zig        # TODO

tests/integration/
└── input_integration_test.zig # 22 tests scaffolded
```

**Documentation:**
- `docs/implementation/INPUT-SYSTEM-DESIGN.md` - Complete architecture specification (510 lines)
- `docs/implementation/INPUT-SYSTEM-TEST-COVERAGE.md` - Comprehensive test coverage report (391 lines)
- `docs/implementation/INPUT-SYSTEM-AUDIT-2025-10-07.md` - Full audit report (485 lines)
- `docs/implementation/INPUT-SYSTEM-AUDIT-FIXES-2025-10-07.md` - Fix completion report (440 lines)

**Timeline:** ~3 hours remaining (6 hours total, 3 hours completed)
**Critical Milestone:** Keyboard input wired - games SHOULD be playable NOW! 🎮

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

### ~~PRG RAM Not Implemented~~ ✅ FIXED (2025-10-07)

**Issue:** PRG RAM ($6000-$7FFF) writes went to wrong address - blocked AccuracyCoin test validation

- **Root Cause:** `effective_address` not calculated for absolute addressing mode
- **Impact:** All absolute writes (STA $6000) went to address 0x0000
- **Fix:** Added effective_address calculation in execute state (lines 1475-1483)
- **Status:** ✅ **FIXED** - PRG RAM writes working correctly
- **Tests Added:** 3 PRG RAM integration tests (write, read, AccuracyCoin simulation)

**Documented in:** `/tmp/SPURIOUS_READ_FIX_COMPLETE.md`

### Spurious Read in Write-Only Instructions ✅ FIXED (2025-10-07)

**Issue:** STA/STX/STY absolute performed unnecessary read before writing

- **Root Cause:** Operand extraction called `busRead()` for ALL absolute instructions
- **Impact:** Read triggered side effects on memory-mapped I/O (PPUDATA incremented v register)
- **Hardware:** Real 6502 doesn't read before writing for write-only instructions
- **Fix:** Skip `busRead()` for opcodes 0x8D (STA), 0x8E (STX), 0x8C (STY)
- **Status:** ✅ **FIXED** - AccuracyCoin rendering correctly
- **Tests Added:** 4 PPU register absolute mode tests (PPUCTRL, PPUMASK, PPUADDR, PPUDATA)

**Documented in:** `/tmp/SPURIOUS_READ_FIX_COMPLETE.md`, `docs/implementation/PPU-HARDWARE-ACCURACY-AUDIT.md`

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

### Mapper System Foundation - ✅ COMPLETE (2025-10-06)

**Status:** Foundation complete, ready for mapper expansion

**Completed:**
- ✅ **AnyCartridge Tagged Union** - Zero-cost polymorphism with `inline else` dispatch
- ✅ **Duck-Typed Mapper Interface** - Compile-time verification, no VTables
- ✅ **IRQ Infrastructure** - A12 edge detection, IRQ polling, acknowledgment
- ✅ **State Isolation** - All mapper state in structs, side effects in tick()
- ✅ **Test Coverage** - 45 new mapper registry tests, all passing
- ✅ **AccuracyCoin Validation** - Full test suite passing ($00 $00 $00 $00)

**Documentation:** `docs/implementation/MAPPER-SYSTEM-SUMMARY.md`

### Next Phase Options

**Option A: Mapper Expansion (14-19 days)**
- Implement Mappers 1-4 (MMC1, UxROM, CNROM, MMC3)
- Achieve 75% NES game coverage (1,954 games)
- Full MMC3 IRQ implementation (A12 counter, scanline detection)
- Bank switching, CHR banking, PRG RAM management

**Option B: Phase 8 - Video Display (20-28 hours)**
- Wayland window + Vulkan rendering
- Visual output for testing and debugging
- Controller input integration
- Path to playable games

**Recommendation:** Video subsystem for immediate visual feedback and debugging capabilities

### Phase 8: Video Display (Wayland + Vulkan) - ✅ COMPLETE

**Objective:** Implement Wayland window and Vulkan rendering backend to display PPU frame output.

**Status: ✅ FULLY IMPLEMENTED**
- ✅ FrameMailbox double-buffered (480 KB, RGBA format ready)
- ✅ WaylandEventMailbox for input events
- ✅ zig-wayland dependency configured in build.zig.zon
- ✅ Wayland window integration (WaylandLogic.zig - 196 lines)
- ✅ Vulkan rendering backend (VulkanLogic.zig - 1857 lines)
- ✅ RenderThread fully functional with 60 FPS rendering
- ✅ XDG shell protocol integration
- ✅ Texture upload from FrameMailbox working

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

1. **Debug Game Rendering Issue**
   - Investigate why games keep PPUMASK=$00 (rendering disabled)
   - Check if games are waiting for specific input sequences
   - Verify NMI timing and VBlank behavior with commercial ROMs
   - Test with multiple Mapper 0 games (Mario, Burger Time, Donkey Kong)

2. **Fix Timing-Sensitive Threading Tests**
   - Review 3 failing threading tests for race conditions
   - Adjust timing tolerances for CI/test environments
   - Consider mocking timer for deterministic testing

3. **Documentation Cleanup**
   - Archive completed phase documentation (Phases 0-8)
   - Consolidate duplicate docs (8 video → 1, 20 audits → 1)
   - Create QUICK-START.md for new users
   - Update test count documentation across all files

### Next Phase Options

4. **Option A: Mapper Expansion** (High Value, 14-19 days)
   - Implement MMC1 (Mapper 1) - adds 28% game coverage
   - Implement UxROM (Mapper 2) - adds 11% coverage
   - Implement CNROM (Mapper 3) - adds 6% coverage
   - Implement MMC3 (Mapper 4) - adds 25% coverage
   - **Result:** 75% of NES library playable

5. **Option B: APU Audio Output** (Medium Value, 10-14 days)
   - Complete APU Milestone 7 (Integration & Refinement)
   - Implement waveform generation for all channels
   - Add audio output backend (SDL2 or miniaudio)
   - Mix channels and apply filters
   - **Result:** Games playable with sound

6. **Option C: Hardware Accuracy Refinement** (Lower Effort, 3-5 days)
   - Fix timing edge cases discovered during game testing
   - Implement missing PPU behaviors (emphasis bits, etc.)
   - Add more comprehensive hardware test ROM suite
   - **Result:** Higher compatibility with demanding games

---

**Last Updated:** 2025-10-08
**Current Phase:** Hardware Accuracy Refinement & Game Testing
**Status:** All core components complete + bidirectional debug mailboxes implemented
**Tests:** 896/900 passing (99.6%, 3 timing-sensitive threading tests, 1 skipped)

**Recent Updates:**
- 2025-10-08: Bidirectional debug mailboxes (DebugCommandMailbox, DebugEventMailbox, --inspect flag)
- 2025-10-07: PPU warm-up period fix, Controller input wiring, NMI investigation
