# RAMBO NES Emulator - Implementation Status

**Last Updated:** 2025-10-03 (PPU Background Rendering Complete + Video Subsystem Design)
**Version:** 0.3.0-alpha
**Target:** Cycle-accurate NES emulation passing AccuracyCoin test suite
**Tests:** 375 passing (all)

## Project Overview

RAMBO is a hardware-accurate NES emulator written in Zig 0.15.1, designed to pass the comprehensive AccuracyCoin test suite (128 tests covering CPU, PPU, APU, and timing).

## Recent Progress

### 2025-10-03: PPU Background Rendering + Video Subsystem Architecture

**Changes:**
- ✅ Implemented complete PPU background rendering pipeline
- ✅ Added NES NTSC palette (64 colors, RGB888 format)
- ✅ Background state machine with shift registers
- ✅ Tile fetching (4-phase: nametable→attribute→pattern low→pattern high)
- ✅ Pixel generation with fine X scroll
- ✅ Scroll management (incrementScrollX/Y, copyScrollX/Y)
- ✅ Hardware-accurate timing (341 cycles/scanline, 262 scanlines/frame)
- ✅ Designed comprehensive video subsystem architecture
- ✅ QA review completed with critical fixes applied

**Impact:**
- PPU now generates pixels to framebuffer (when provided)
- Ready for video display integration
- All 375 tests passing
- Video subsystem designed with triple-buffered lock-free frame buffers
- OpenGL/Vulkan backend architecture planned

**Files Changed:**
- `src/ppu/Ppu.zig` - Added background rendering
- `src/ppu/palette.zig` - NEW: NES color palette
- `src/emulation/State.zig` - Updated PPU integration
- `docs/06-implementation-notes/design-decisions/ppu-rendering-architecture.md` - NEW
- `docs/06-implementation-notes/design-decisions/video-subsystem-architecture.md` - NEW

### 2025-10-02: Critical Refactoring - Immediate Mode Fix & Code Deduplication

**Changes:**
- ✅ Fixed critical immediate mode inconsistency bug across all instructions
- ✅ Removed 206 lines of duplicate code from dispatch.zig
- ✅ Moved all load/store instructions to dedicated loadstore module
- ✅ Standardized page crossing logic using helpers.readOperand()
- ✅ Fixed manual page crossing in EOR and CMP instructions

**Impact:**
- All immediate mode instructions now use consistent Pattern B (empty addressing steps, PC fetch in execute)
- dispatch.zig reduced from 1156 to 950 lines
- Zero test failures - all 112 tests passing
- Code duplication reduced by 212 lines
- Clean foundation for implementing 221 remaining opcodes

**Technical Details:**
- Immediate mode: 2 cycles (fetch opcode + fetch operand/execute) - hardware accurate
- All load instructions: LDA/LDX/LDY use helpers.readOperand() for non-immediate modes
- All logical instructions: AND/ORA/EOR use consistent immediate mode pattern
- All compare instructions: CMP/CPX/CPY use helpers for page crossing

### Session 2025-10-02: Cartridge/ROM Loading Implementation Complete
- **Full iNES format parser** with validation and error handling
- **Generic Cartridge type factory** with comptime duck typing (zero VTable overhead)
- **Mapper 0 (NROM)** fully implemented and tested
- **Single-threaded RT-safe access** - no mutex needed in emulation loop
- **Bus integration** complete - ROM data accessible at $8000-$FFFF
- **AccuracyCoin.nes loads successfully** - 32KB PRG ROM, 8KB CHR ROM, Mapper 0
- **Reset vector extraction** working ($8004 for AccuracyCoin)
- **Comprehensive test suite** with 40+ cartridge-specific tests

### ✅ RMW (Read-Modify-Write) Implementation (Earlier Session)
- Implemented **critical hardware quirk**: RMW dummy write cycle
- All shift/rotate instructions: ASL, LSR, ROL, ROR (accumulator + memory modes)
- All increment/decrement instructions: INC, DEC, INX, INY, DEX, DEY
- Dedicated RMW addressing mode sequences for cycle-accurate timing
- Dummy write correctly writes original value before modified value (visible to MMIO)

### 📊 Current Project Stats
- **CPU Instructions**: 256/256 opcodes complete (151 official + 105 unofficial) - 100%
- **Mappers**: 1 implemented (Mapper 0 - NROM)
- **Tests**: 112+ total (all passing)
- **Test Pass Rate**: 100%
- **ROM Loading**: ✅ Working (AccuracyCoin.nes validated)

## Architecture Status

### ✅ Major Refactoring Complete (2025-10-03)

**Phase 1-3 Refactoring: State/Logic Separation + Comptime Generics**
- ✅ **Phase 1** (Commit 1ceb301): Bus State/Logic separation with hybrid pattern
- ✅ **Phase 2** (Commit 73f9279): PPU State/Logic separation matching Bus/CPU
- ✅ **Phase A** (Commit 2fba2fa): Backward compatibility cleanup, ComponentState naming
- ✅ **Phase 3** (Commit 2dc78b8): VTable elimination, comptime generics

**Architectural Improvements:**
- Zero VTable overhead (Mapper.zig, ChrProvider.zig deleted)
- State/Logic separation for all components (CPU, Bus, PPU)
- Comptime duck typing: `Cartridge(MapperType)` generic
- RT-safe single-threaded design (mutex removed)
- Clean ComponentState naming: CpuState, BusState, PpuState

**See:** `docs/code-review/REFACTORING-ROADMAP.md` for complete details

### ✅ Completed

#### Build System & Project Structure
- **Module system**: Clean separation between library (root.zig) and executable (main.zig)
- **Test infrastructure**:
  - Unit tests embedded in modules
  - Integration tests in `tests/` directory
  - Separate test commands: `test`, `test-unit`, `test-integration`, `test-trace`
- **Dependencies**: libxev integrated for event loop (future use)
- **Documentation**: Comprehensive docs in `docs/` with session notes, design decisions, and requirements

#### Memory Bus (`src/bus/Bus.zig`)
- ✅ RAM mirroring (2KB mirrored 4x through $0000-$1FFF)
- ✅ Open bus behavior with explicit tracking
- ✅ ROM write protection
- ✅ 16-bit reads with little-endian support
- ✅ 6502 JMP indirect bug (`read16Bug`)
- ✅ 16 comprehensive unit tests, all passing
- **Test Coverage**: 100% for implemented features

#### CPU Core (`src/cpu/Cpu.zig`)
- ✅ Complete 6502 register set (A, X, Y, SP, PC, P)
- ✅ Status flags with bit-packed struct
- ✅ NMI edge detection (fixed hardware-accurate implementation)
- ✅ IRQ level-triggered interrupts
- ✅ Open bus tracking integration
- ✅ State machine foundation with cycle counting
- **Test Coverage**: Basic initialization and flags

#### Opcode Table (`src/cpu/opcodes.zig`)
- ✅ All 256 opcodes defined (151 official + 105 unofficial)
- ✅ Complete metadata: mnemonic, addressing mode, cycle count, page cross behavior
- ✅ Compile-time opcode table generation
- **Test Coverage**: Opcode properties validated

#### Execution Framework (`src/cpu/execution.zig`)
- ✅ Microstep function architecture
- ✅ Common addressing microsteps (fetch, calculate, dummy reads)
- ✅ Zero page indexed with wrapping
- ✅ Absolute indexed with page cross detection
- ✅ Indexed indirect and indirect indexed
- ✅ Dummy read implementation (hardware-accurate addresses)
- ✅ Stack operations (push/pull with proper addressing)
- **Test Coverage**: Individual microsteps tested

#### Addressing Modes (`src/cpu/addressing.zig`)
- ✅ All 13 addressing modes defined
- ✅ Microstep sequences for each mode
- ✅ Separate paths for read vs write instructions
- ✅ Page crossing detection
- **Modes Implemented**:
  - Implied/Accumulator
  - Immediate
  - Zero Page, Zero Page,X, Zero Page,Y
  - Absolute, Absolute,X, Absolute,Y
  - (Indirect,X), (Indirect),Y
  - Relative (for branches)
  - Indirect (for JMP)

#### Dispatch System (`src/cpu/dispatch.zig`)
- ✅ Compile-time dispatch table generation
- ✅ Opcode → executor mapping
- ✅ Instruction implementations:
  - NOP (implied and immediate variants)
  - LDA (all 8 addressing modes)
  - STA (all 7 addressing modes)
  - ASL, LSR, ROL, ROR (accumulator + all RMW modes)
  - INC, DEC (all RMW modes)
  - INX, INY, DEX, DEY (implied)
- **Test Coverage**: Dispatch table structure validated

#### Cartridge System (`src/cartridge/`)
- ✅ iNES format parser (`ines.zig`)
  - Full header parsing and validation
  - Mapper detection, PRG/CHR ROM size calculation
  - Mirroring mode detection
  - Battery RAM and trainer detection
- ✅ Generic Cartridge Type Factory (`Cartridge.zig`)
  - Comptime generic: `Cartridge(MapperType)`
  - Zero-cost abstraction via duck typing
  - No VTable overhead - direct dispatch
  - Type alias for convenience: `NromCart = Cartridge(Mapper0)`
- ✅ Mapper 0 (NROM) implementation (`mappers/Mapper0.zig`)
  - 16KB and 32KB PRG ROM support
  - 8KB CHR ROM/RAM support
  - Correct mirroring at $C000-$FFFF for 16KB ROMs
  - Duck-typed interface (no VTable)
- ✅ Single-threaded RT-safe access
  - No mutex needed - exclusive access from emulation loop
  - Owned ROM data with proper lifetime management
  - Future async I/O via message passing
- ✅ File loader (`loader.zig`)
  - Synchronous file loading via std.fs
  - Future: libxev async I/O integration
- ✅ Bus integration
  - Cartridge read/write routing for $4020-$FFFF
  - Open bus behavior when no cartridge loaded
- **Test Coverage**: 42 tests (iNES parsing, Mapper 0, integration, AccuracyCoin loading)

### 🚧 In Progress

#### Timing Accuracy
- ✅ Immediate mode: 2 cycles (hardware-accurate)
- ✅ Zero page: 3 cycles (hardware-accurate)
- ✅ Absolute,X reads: Functionally correct, uses dummy read value
- ⚠️ **Known Deviation**: Absolute,X no-page-cross takes 5 cycles (should be 4)
  - Hardware: Dummy read IS the actual read (4 cycles)
  - Our impl: Separate addressing + execute states (5 cycles)
  - **Impact**: Functionally correct, cycle count off by 1
  - **Fix Required**: State machine refactor to support in-cycle execution

#### Hardware Quirks
- ✅ Dummy reads occur at correct addresses
- ✅ Open bus updated on every read
- ✅ Page crossing detection accurate
- ✅ RMW dummy write: IMPLEMENTED
  - Writes original value before modified value (cycle N-1)
  - Then writes modified value (cycle N)
  - Visible to memory-mapped I/O
  - Critical for PPU register behavior

### ✅ CPU Instructions - COMPLETE (256/256)
- **ALL 256 OPCODES IMPLEMENTED** (100% complete)
  - 151 official opcodes: Complete
  - 105 unofficial opcodes: Complete
  - Hardware-accurate timing and behavior
  - RMW dummy writes implemented
  - Page crossing detection accurate
  - All addressing modes functional

### ✅ PPU VRAM System - 100% Complete

**CRITICAL CORRECTION:** Previous documentation incorrectly stated VRAM was missing. VRAM implementation is COMPLETE and fully tested.

#### ✅ VRAM Implementation (Complete):
- ✅ **readVram/writeVram** - Full $0000-$3FFF address space handling
- ✅ **CHR ROM/RAM Access** - ChrProvider interface for pattern tables ($0000-$1FFF)
- ✅ **Nametable Mirroring** - Horizontal, vertical, four-screen modes implemented
- ✅ **Palette RAM** - 32-byte palette with backdrop mirroring ($3F00-$3F1F)
- ✅ **Mirror Ranges** - Nametable ($3000-$3EFF) and palette ($3F20-$3FFF) mirrors
- ✅ **PPUDATA ($2007)** - Buffered reads with one-cycle delay (hardware-accurate)
- ✅ **Palette Unbuffering** - Palette reads bypass buffer (hardware quirk)
- ✅ **VRAM Increment** - +1 or +32 based on PPUCTRL bit 2
- ✅ **Open Bus Behavior** - Returns PPU data bus latch when no CHR provider
- ✅ **CHR ROM vs RAM** - Mapper correctly distinguishes read-only vs writable

#### Architecture:
- **Direct CHR Memory Access**
  - No abstraction overhead - PPU uses direct pointer to CHR data
  - CartridgeChrAdapter provides minimal bridge when needed
  - RT-safe: zero allocation, deterministic access
- **Proper Decoupling**
  - PPU has no knowledge of Cartridge concrete type
  - EmulationState provides CHR data pointer
  - No VTables, no indirection

#### Test Coverage:
- ✅ 6 CHR integration tests (all passing)
- ✅ 17 VRAM unit tests (all passing)
- ✅ 100% coverage of VRAM code paths

### ✅ PPU Background Rendering - COMPLETE

**Status:** Background tile rendering fully implemented with hardware-accurate timing.

#### Implemented (src/ppu/Ppu.zig):
- ✅ All 8 PPU registers ($2000-$2007) with full functionality
- ✅ Internal registers (v, t, x, w, read_buffer)
- ✅ VBlank timing (scanline 241, dot 1)
- ✅ NMI generation with edge detection
- ✅ Odd frame skip (hardware-accurate)
- ✅ Open bus behavior with decay
- ✅ OAM/palette RAM structures
- ✅ Complete VRAM system
- ✅ **Background State Machine** - Shift registers, tile latches
- ✅ **Tile Fetching** - 4-fetch pattern (nametable→attribute→pattern low→pattern high)
- ✅ **Shift Registers** - 16-bit pattern, 8-bit attribute registers
- ✅ **Pixel Generation** - Extract pixel from shift registers with fine X scroll
- ✅ **Scroll Management** - incrementScrollX/Y, copyScrollX/Y
- ✅ **Pattern Decoding** - Two-bitplane color index generation
- ✅ **Palette Lookup** - Convert palette index to RGBA8888 (src/ppu/palette.zig)
- ✅ **Hardware Timing** - 341 cycles/scanline, 262 scanlines/frame

#### NES Palette System (src/ppu/palette.zig):
- ✅ 64-color NTSC palette as RGB888 values
- ✅ RGB to RGBA conversion
- ✅ Color index masking (6-bit)
- ✅ getNesColorRgba() for lookup

#### Tests:
- ✅ 5 palette tests (all passing)
- ✅ All existing PPU tests updated for new tick() signature

#### Missing (Next Priority):
- ❌ **Video Display** - Framebuffer presentation (see video-subsystem-architecture.md)
- ❌ **Sprite Rendering** - Evaluation, fetching, priority (12-16 hours)
- ❌ **Leftmost 8-pixel Clipping** - PPUMASK bits 1-2

#### APU (Audio Processing Unit)
- Not started
- Lower priority for initial implementation

#### Additional Mappers
- ✅ **Mapper 0 (NROM)** - Complete
- ⬜ **Mapper 1 (MMC1)** - 28% of NES games
- ⬜ **Mapper 2 (UxROM)** - 10% of NES games
- ⬜ **Mapper 3 (CNROM)** - 7% of NES games
- ⬜ **Other mappers** as needed for AccuracyCoin

## Test Status

### Unit Tests: ✅ ALL PASSING (70 tests)
- Bus: 16/16 tests passing
- CPU: 3/3 tests passing
- Opcodes: 5/5 tests passing
- Execution: 6/6 tests passing
- Addressing: 5/5 tests passing
- Dispatch: 3/3 tests passing
- **iNES Parser**: 10/10 tests passing
- **Mapper 0**: 6/6 tests passing
- **Cartridge**: 8/8 tests passing
- **Loader**: 2/2 tests passing
- **Shifts/Rotates**: 4/4 tests passing
- **Inc/Dec**: 2/2 tests passing

### Integration Tests: ✅ 34/34 PASSING
- NOP implied: ✅
- NOP immediate: ✅
- LDA immediate: ✅ (all flag variants)
- LDA zero page: ✅
- LDA zero page,X: ✅ (including wrapping)
- LDA absolute: ✅
- LDA absolute,X: ✅ (with known +1 cycle deviation)
- LDA absolute,X page cross: ✅
- STA zero page: ✅
- STA absolute,X: ✅ (with known +1 cycle deviation)
- Open bus: ✅
- ASL accumulator: ✅
- ASL zero page (with RMW dummy write): ✅
- ASL absolute,X: ✅
- LSR accumulator: ✅
- LSR zero page,X: ✅
- ROL accumulator: ✅
- ROL absolute: ✅
- ROR accumulator: ✅
- INC zero page (with RMW dummy write): ✅
- INC wraps to zero: ✅
- INC absolute,X: ✅
- DEC zero page: ✅
- DEC wraps to FF: ✅
- INX, INY, DEX, DEY: ✅
- RMW dummy write verification: ✅
- **AccuracyCoin.nes loading**: ✅
- **AccuracyCoin.nes through Bus**: ✅

### AccuracyCoin Execution: ❌ NOT READY YET
- ✅ ROM loading infrastructure complete
- ✅ Can read reset vector ($8004)
- ⬜ Need complete CPU instruction set to execute
- ⬜ Need PPU implementation for graphics tests

## Known Issues & Deviations

### Timing Deviations
1. **Absolute,X/Y Read (no page cross)**
   - Hardware: 4 cycles
   - Our implementation: 5 cycles
   - Reason: Separate addressing/execute states
   - Impact: Functionally correct, timing inaccurate
   - Priority: Medium (affects cycle-accurate timing)

2. **Absolute,X/Y Write (no page cross)**
   - Hardware: 5 cycles
   - Our implementation: 6 cycles
   - Reason: Same as above
   - Impact: Functionally correct, timing inaccurate
   - Priority: Medium

### Missing Features
1. ✅ **RMW Dummy Write Cycle** (IMPLEMENTED)
   - Status: Complete with dedicated RMW addressing mode sequences
   - Cycle-accurate dummy write (writes original value)
   - All RMW instructions implemented: ASL, LSR, ROL, ROR, INC, DEC
   - 18 comprehensive RMW tests passing

2. **Branch Timing**
   - Status: Not implemented
   - Required: 2/3/4 cycle timing based on branch taken/page cross
   - Priority: HIGH

3. **Interrupt Timing**
   - Status: Structure exists, sequence not fully implemented
   - Required: 7-cycle interrupt sequence
   - Priority: MEDIUM

## Architecture Decisions

### Current Design Strengths
✅ Clean separation of concerns (execution, addressing, dispatch)
✅ Microstep architecture allows cycle-by-cycle control
✅ Hardware-accurate dummy read addresses
✅ Proper open bus tracking
✅ Compile-time opcode table generation
✅ Comprehensive test infrastructure

### Current Design Limitations
⚠️ State machine processes one state per tick (causes +1 cycle issue)
⚠️ Microsteps don't know instruction type (read/write/RMW)
⚠️ Cannot execute within addressing cycle (hardware does this)

### Proposed Solutions
1. **Hybrid Execution Model**
   - Immediate mode: Execute during "operand fetch" (DONE)
   - Indexed modes: Execute during "dummy read" for no-page-cross
   - Requires: tick() to support same-cycle state transitions

2. **Instruction-Aware Microsteps**
   - Different step sequences for read/write/RMW (DONE)
   - Microsteps can return "complete" to skip execute state
   - Requires: Refactor tick() to check completion immediately

## Next Steps (Priority Order)

### Critical Path (2-3 weeks to playable emulator)

#### Phase 1: PPU VRAM & Minimal Rendering (2-3 days)
1. ⬜ Implement VRAM read/write methods
2. ⬜ Add 2KB internal VRAM to PPU
3. ⬜ Fix PPUDATA ($2007) read/write
4. ⬜ Implement nametable mirroring
5. ⬜ Minimal background rendering

#### Phase 2: Controllers & Bus I/O (1 day)
6. ⬜ Remove cartridge mutex (RT-safety fix)
7. ⬜ Implement controller I/O ($4016/$4017)
8. ⬜ Implement OAM DMA ($4014)
9. ⬜ Add controller state to Bus

#### Phase 3: Async I/O Integration (2-3 days)
10. ⬜ Connect EmulationState to Runtime
11. ⬜ Implement frame timing loop
12. ⬜ Wire input queue to controllers
13. ⬜ Basic OpenGL rendering backend

#### Phase 4: Mapper Support (3-4 days)
14. ⬜ Implement MMC1 mapper (28% game coverage)
15. ⬜ Implement MMC3 mapper (additional 25% coverage)

#### Phase 5: Complete Graphics (2-3 days)
16. ⬜ Sprite rendering pipeline
17. ⬜ Scrolling implementation
18. ⬜ Sprite 0 hit detection

### Secondary Priorities

#### APU Implementation (5-7 days)
- ⬜ Pulse, triangle, noise channels
- ⬜ DMC channel and frame counter
- ⬜ Audio backend integration

#### Additional Features
- ⬜ Fix absolute,X/Y timing deviation
- ⬜ Complete interrupt sequence (7-cycle)
- ⬜ Additional mappers (UxROM, CNROM, AxROM)
- ⬜ Save states and debugging tools

## Documentation Status

### ✅ Complete
- Session notes (`docs/06-implementation-notes/sessions/`)
- Design decisions (`docs/06-implementation-notes/design-decisions/`)
- AccuracyCoin requirements (`docs/05-testing/accuracycoin-cpu-requirements.md`)
- Hardware timing quirks (`docs/06-implementation-notes/design-decisions/6502-hardware-timing-quirks.md`)
- CPU execution architecture (`docs/06-implementation-notes/design-decisions/cpu-execution-architecture.md`)
- Memory bus implementation (`docs/06-implementation-notes/design-decisions/memory-bus-implementation.md`)

### ⬜ To Create
- Instruction implementation guide
- Testing methodology document
- Performance optimization notes
- API reference (auto-generated from code)

## Build Commands

```bash
# Build executable
zig build

# Run all tests
zig build test

# Run only unit tests
zig build test-unit

# Run only integration tests
zig build test-integration

# Run cycle trace tests (debugging)
zig build test-trace

# Run executable
zig build run
```

## Contributing Guidelines

When implementing new instructions:

1. **Read AccuracyCoin requirements** for exact behavior
2. **Check hardware timing** in `6502-hardware-timing-quirks.md`
3. **Write tests first** (TDD approach)
4. **Implement instruction** in appropriate file (`src/cpu/instructions/*.zig`)
5. **Add to dispatch table** in `dispatch.zig`
6. **Verify cycle count** matches hardware
7. **Test dummy reads/writes** occur correctly
8. **Update this STATUS doc** with progress

## References

- AccuracyCoin: `/home/colin/Development/RAMBO/AccuracyCoin/`
- NESDev Wiki: https://www.nesdev.org/wiki/
- 6502 Reference: http://www.6502.org/
- Visual 6502: http://www.visual6502.org/
