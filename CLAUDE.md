# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**RAMBO** is a cycle-accurate NES emulator written in Zig 0.15.1, targeting the comprehensive AccuracyCoin test suite (128 tests covering CPU, PPU, APU, and timing accuracy).

**Current Status:** CPU 100% complete (256 opcodes), PPU 60% complete (registers, VRAM, background rendering - sprites pending), Bus 85% complete (missing controller I/O), cartridge loading functional (Mapper 0 only), passing all tests (375 tests). Video subsystem architecture designed and ready for implementation.

**Key Requirement:** Hardware-accurate 6502 emulation with cycle-level precision for AccuracyCoin compatibility.

## Build Commands

```bash
# Build executable
zig build

# Run all tests (unit + integration)
zig build test

# Run only unit tests (fast - embedded in modules)
zig build test-unit

# Run only integration tests (CPU instruction tests)
zig build test-integration

# Run debug trace tests (cycle-by-cycle execution traces)
zig build test-trace
zig build test-rmw-debug  # RMW instruction debugging

# Run executable
zig build run
```

## Architecture

### Hybrid State/Logic Pattern

All core components follow the **State/Logic separation pattern** for modularity, testability, and RT-safety:

**State Modules (`State.zig`)**:
- Pure data structures with optional non-owning pointers
- Convenience methods that delegate to Logic functions
- Zero hidden state, fully serializable
- Examples: `CpuState`, `BusState`, `PpuState`

**Logic Modules (`Logic.zig`)**:
- Pure functions operating on State pointers
- No global state, deterministic execution
- All side effects explicit through parameters
- Examples: `CpuLogic`, `BusLogic`, `PpuLogic`

**Module Re-exports (`Cpu.zig`, `Bus.zig`, `Ppu.zig`)**:
- Clean API: `pub const State = @import("State.zig");`
- Type aliases: `pub const CpuState = State.CpuState;`
- Convenience exports for common types

**Comptime Generics (Duck Typing)**:
- Zero-cost polymorphism via comptime duck typing
- No VTables, no runtime indirection
- Mapper interface: `Cartridge(MapperType)` generic type factory
- Duck-typed methods use `anytype` to break circular dependencies

### Core Components

**Bus (`src/bus/Bus.zig`)**
- Central memory/IO communication hub
- 2KB RAM with 4x mirroring ($0000-$1FFF)
- Open bus behavior tracking (data bus retention)
- ROM write protection
- Cartridge read/write routing ($4020-$FFFF)
- Special methods: `read16()`, `read16Bug()` (JMP indirect page wrap bug)

**CPU (`src/cpu/Cpu.zig`)**
- Microstep-based state machine (cycle-accurate execution)
- Each instruction broken into individual clock cycles
- 6502 register set: A, X, Y, SP, PC, P (status flags)
- NMI edge detection, IRQ level triggering
- Opcode table: All 256 opcodes defined (151 official + 105 unofficial)

**Cartridge (`src/cartridge/`)**
- iNES ROM format parser with validation
- Generic Cartridge(MapperType) with comptime duck typing (zero VTable overhead)
- Mapper 0 (NROM) fully implemented
- Single-threaded RT-safe access (no mutex needed)
- Loaded ROM: AccuracyCoin.nes (32KB PRG, 8KB CHR, Mapper 0)

### Module Structure

```
src/
├── root.zig              # Library entry point
├── main.zig              # Executable entry point
├── bus/
│   ├── Bus.zig           # Module re-exports
│   ├── State.zig         # BusState - pure data structure
│   └── Logic.zig         # Pure functions for bus operations
├── cpu/
│   ├── Cpu.zig           # Module re-exports
│   ├── State.zig         # CpuState - 6502 registers and state
│   ├── Logic.zig         # Pure functions for CPU operations
│   ├── opcodes.zig       # 256-opcode compile-time table
│   ├── execution.zig     # Microstep execution engine
│   ├── addressing.zig    # Addressing mode microsteps
│   ├── dispatch.zig      # Opcode → executor mapping
│   ├── constants.zig     # CPU constants
│   ├── helpers.zig       # Helper functions
│   └── instructions/     # Instruction implementations
│       ├── loadstore.zig # LDA/LDX/LDY, STA/STX/STY (all modes)
│       ├── arithmetic.zig # ADC, SBC (all modes)
│       ├── logical.zig   # AND, ORA, EOR (all modes)
│       ├── shifts.zig    # ASL, LSR, ROL, ROR (all modes)
│       ├── incdec.zig    # INC, DEC, INX, INY, DEX, DEY
│       ├── compare.zig   # CMP, CPX, CPY, BIT (all modes)
│       ├── branch.zig    # BCC, BCS, BEQ, BNE, BMI, BPL, BVC, BVS
│       ├── jumps.zig     # JMP, JSR, RTS, RTI, BRK
│       ├── stack.zig     # PHA, PLA, PHP, PLP
│       ├── transfer.zig  # TAX, TXA, TAY, TYA, TSX, TXS, flag ops
│       └── unofficial.zig # Unofficial opcodes (105/105 implemented)
├── ppu/
│   ├── Ppu.zig           # Module re-exports
│   ├── State.zig         # PpuState - PPU registers and state
│   ├── Logic.zig         # Pure functions for PPU operations
│   ├── palette.zig       # NES color palette (64 colors)
│   └── timing.zig        # PPU timing constants
└── cartridge/
    ├── Cartridge.zig     # Generic Cartridge(MapperType) type factory
    ├── ines.zig          # iNES format parser
    ├── loader.zig        # File loading (sync, future: libxev async)
    └── mappers/
        └── Mapper0.zig   # NROM (16KB/32KB PRG, 8KB CHR) - duck-typed interface
```

## Critical Hardware Behaviors

### 1. Read-Modify-Write (RMW) Dummy Write
**ALL RMW instructions (ASL, LSR, ROL, ROR, INC, DEC) MUST write the original value back before writing the modified value:**

```zig
// INC $10: 5 cycles
// Cycle 3: Read value from $10
// Cycle 4: Write ORIGINAL value back to $10  <-- CRITICAL!
// Cycle 5: Write INCREMENTED value to $10
```

This is visible to memory-mapped I/O and tested by AccuracyCoin "Dummy write cycles" test.

### 2. Dummy Reads on Page Crossing
When indexed addressing crosses a page boundary (e.g., `LDA $10FF,X` with X=$02), the CPU:
- Cycle 4: Performs dummy read at WRONG address (low byte wrapped, high byte not yet fixed)
- Cycle 5: Reads from correct address

**The dummy read address is `(base_high << 8) | ((base_low + index) & 0xFF)`**

### 3. Open Bus Behavior
Every bus read/write updates the data bus. Reading unmapped memory returns the last bus value. This is tracked explicitly in `Bus.OpenBus` struct.

### 4. Zero Page Wrapping
Zero page indexed addressing MUST wrap within page 0:
```zig
// LDA $FF,X with X=$02 -> reads from $01, NOT $101
address = @as(u16, (base +% index))  // Wraps at byte boundary
```

### 5. NMI Edge Detection
NMI triggers on falling edge (high → low transition), not level. IRQ is level-triggered.

## Instruction Implementation Pattern

When adding new CPU instructions:

1. **Check AccuracyCoin requirements** in `docs/05-testing/accuracycoin-cpu-requirements.md`
2. **Review hardware timing** in `docs/06-implementation-notes/design-decisions/6502-hardware-timing-quirks.md`
3. **Write tests first** in `tests/cpu/instructions_test.zig`
4. **Implement in appropriate file** under `src/cpu/instructions/`
5. **Add to dispatch table** in `src/cpu/dispatch.zig`
6. **Verify cycle count** matches hardware exactly
7. **Test dummy reads/writes** occur at correct cycles with correct addresses

### Example: LDA Immediate (2 cycles)
```zig
// Using hybrid State/Logic pattern
pub fn ldaImmediate(cpu: *CpuState, bus: *BusState) bool {
    cpu.a = bus.read(cpu.pc);
    cpu.pc +%= 1;
    cpu.p.updateZN(cpu.a);
    return true; // Instruction complete
}
```

### Example: Comptime Generic Cartridge
```zig
// Zero-cost abstraction with duck typing
const Mapper0 = @import("mappers/Mapper0.zig");
const CartType = Cartridge(Mapper0);  // Compile-time type instantiation

var cart = try CartType.loadFromData(allocator, rom_data);
defer cart.deinit();

// Direct call - no VTable, fully inlined
const value = cart.cpuRead(0x8000);
```

### Example: ASL Zero Page (5 cycles with RMW)
```zig
// Uses RMW addressing mode sequence:
// 1. Fetch opcode
// 2. Fetch ZP address
// 3. Read value from address
// 4. Dummy write (original value) <-- CRITICAL
// 5. Write modified value
```

## Known Timing Deviations

**Absolute,X/Y reads without page crossing:**
- Hardware: 4 cycles (dummy read IS the actual read)
- Current implementation: 5 cycles (separate addressing + execute states)
- Impact: Functionally correct, timing off by +1 cycle
- Priority: MEDIUM (affects cycle-accurate timing tests)

This is documented in `docs/06-implementation-notes/STATUS.md` under "Known Issues & Deviations".

## Testing Strategy

### Cycle-by-Cycle Validation
Tests verify:
- Exact cycle count matches hardware
- Correct values at each cycle
- Dummy reads/writes occur at correct addresses
- Open bus updated correctly
- Status flags set correctly

### Test Organization
- **Unit tests**: Embedded in modules (fast, run with `zig build test-unit`)
- **Integration tests**: Full instruction execution in `tests/cpu/` (run with `zig build test-integration`)
- **Trace tests**: Cycle-by-cycle execution traces for debugging (run with `zig build test-trace`)

### AccuracyCoin Integration
AccuracyCoin.nes is loaded and accessible. Full execution requires:
- ✅ All 256 opcodes implemented (151 official + 105 unofficial)
- ✅ PPU VRAM system (100% complete with ChrProvider abstraction)
- ✅ PPU Background rendering (tile fetching, shift registers, scroll)
- 🟡 Video display (designed, ready for implementation)
- ❌ Controller I/O (not implemented)
- ❌ Sprite rendering (not implemented)
- ❌ APU implementation (not started)

## Implementation Priorities

### HIGH (Critical Path to Playability)
1. ✅ **VRAM Access** - COMPLETE (ChrProvider interface, all tests passing)
2. ✅ **Background Rendering** - COMPLETE (tile fetching, shift registers, pixel output)
3. **Video Subsystem** - OpenGL backend for frame display (20-25 hours) - NEXT PRIORITY
   - See: docs/06-implementation-notes/design-decisions/video-subsystem-architecture.md
4. **Controller I/O** ($4016/$4017) - Cannot play games without input (3-4 hours)
5. **OAM DMA** ($4014) - Required for sprite rendering (2-3 hours)
6. **Sprite Rendering** - Complete graphics output (12-16 hours)
7. **MMC1 Mapper** - Adds 28% game compatibility (6-8 hours)

### MEDIUM (Enhanced Compatibility)
7. **MMC3 Mapper** - Critical for popular games, adds 25% coverage (12-16 hours)
8. **Fix absolute,X/Y timing** - Remove +1 cycle deviation (3-4 hours)
9. **Complete interrupt sequence** - 7-cycle implementation (2-3 hours)
10. **Scrolling** - Coarse and fine scroll (8 hours)

### LOW (Polish and Features)
11. **APU Implementation** - Audio processing (5-7 days)
12. **Additional mappers** (UxROM, CNROM, AxROM) - 80% game coverage
13. **Save states and debugging tools**

## Documentation

Key docs in `docs/`:
- `05-testing/accuracycoin-cpu-requirements.md` - Test suite requirements
- `06-implementation-notes/design-decisions/cpu-execution-architecture.md` - Microstep architecture
- `06-implementation-notes/design-decisions/6502-hardware-timing-quirks.md` - Hardware behaviors
- `06-implementation-notes/design-decisions/memory-bus-implementation.md` - Bus design
- `06-implementation-notes/STATUS.md` - Current implementation status

Session notes in `docs/06-implementation-notes/sessions/` document development progress.

## Important Notes

- **AccuracyCoin.nes location:** `AccuracyCoin/AccuracyCoin.nes` (not in repo, external)
- **Zig version:** 0.15.1 (check with `zig version`)
- **libxev dependency:** Integrated but not yet used (future async I/O)
- **All tests passing:** 375 tests (all passing)
- **Test coverage:** 100% for implemented features
- **CPU Implementation:** ✅ Complete - 256/256 opcodes (100%)
- **PPU Implementation:** 🟡 60% complete (registers, VRAM, background rendering complete - sprites pending)
- **Bus Implementation:** 🟡 85% complete (missing controller I/O)

## Development Workflow

### For PPU Development (Current Priority)
1. **VRAM Access**: Implement read/write methods for graphics memory
2. **PPUDATA Fix**: Complete $2007 register implementation
3. **Nametable Mirroring**: Implement horizontal/vertical mirroring
4. **Minimal Rendering**: Start with background tile rendering
5. **Test with Simple ROMs**: Use homebrew test ROMs before complex games

### For Controller Implementation
1. **Remove Cartridge Mutex**: Eliminate RT-thread blocking risk
2. **Controller Registers**: Implement $4016/$4017 with shift register
3. **OAM DMA**: Implement $4014 with 513-514 cycle suspension
4. **Test Input**: Verify controller state reading

### For Mapper Development
1. **MMC1 First**: Shift register, bank switching (28% game coverage)
2. **MMC3 Second**: Complex mapper with IRQ counter (25% additional coverage)
3. **Test Popular Games**: Super Mario Bros (MMC1), Super Mario Bros 3 (MMC3)
