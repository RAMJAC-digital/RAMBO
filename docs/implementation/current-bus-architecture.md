# Current Bus Architecture (Handler-Based)

**Date:** 2025-11-03
**Status:** Implemented and fully functional
**Reference:** `src/emulation/bus/handlers/`, `src/emulation/State.zig`

## Overview

RAMBO's bus architecture uses a **handler delegation pattern** where each address range is managed by a stateless handler. All bus routing happens via switch-based dispatch to handlers:
- `EmulationState.busRead()` - CPU reads (dispatches to handlers)
- `EmulationState.busWrite()` - CPU writes (dispatches to handlers)
- `EmulationState.peekMemory()` - Debugger-safe reads (no side effects)

**Key Characteristics:**
- **Stateless handlers** - Zero-size structs, all data accessed via state parameter
- **Modular design** - Each address range isolated in its own handler module
- **Hardware-aligned** - Handler boundaries match NES chip architecture
- **Debugger support** - All handlers provide side-effect-free `peek()` methods

## Complete Memory Map

### CPU Address Space ($0000-$FFFF)

| Range | Component | Read Behavior | Write Behavior | Side Effects |
|-------|-----------|---------------|----------------|--------------|
| $0000-$1FFF | Internal RAM | Read from 2KB RAM with mirroring (`ram[addr & 0x7FF]`) | Write to 2KB RAM with mirroring | None |
| $2000-$3FFF | PPU Registers | Delegate to `PpuLogic.readRegister()` (8 registers mirrored) | Delegate to `PpuLogic.writeRegister()` | **Complex - see below** |
| $4000-$4013 | APU Channels | Open bus (write-only registers) | Delegate to ApuLogic per channel | Channel state updates |
| $4014 | OAM DMA | Open bus (write-only) | Trigger OAM DMA transfer | DMA starts (513/514 cycles) |
| $4015 | APU Status | APU status byte, clear frame IRQ | APU channel enables | Frame IRQ cleared on read |
| $4016 | Controller 1 | Shift register output + open bus bits 5-7 | Strobe control (latch/shift mode) | Strobe triggers latch |
| $4017 | Controller 2 | Shift register output + open bus bits 5-7 | APU frame counter | Frame counter mode set |
| $4020-$5FFF | Expansion | Open bus (unmapped on stock NES) | Ignored | None |
| $6000-$7FFF | PRG RAM | Delegate to cartridge (if present), else test RAM | Delegate to cartridge (if present), else test RAM | Cartridge-dependent |
| $8000-$FFFF | PRG ROM | Delegate to cartridge (if present), else test RAM | Delegate to cartridge (mapper registers) | Mapper state updates |

### PPU Register Side Effects (Critical)

**Current Implementation:** `PpuHandler` manages all PPU register side effects.

| Register | Address | Read Side Effects | Write Side Effects |
|----------|---------|-------------------|-------------------|
| PPUCTRL | $2000 | Open bus | **NMI line update** (immediate, in PpuHandler.write()) |
| PPUMASK | $2001 | Open bus | Rendering enable/disable (delay buffer) |
| PPUSTATUS | $2002 | **VBlank flag clear**, write toggle reset | Write-only |
| OAMADDR | $2003 | Open bus | OAM address set |
| OAMDATA | $2004 | OAM byte read | OAM byte write |
| PPUSCROLL | $2005 | Open bus | Scroll position set (write toggle) |
| PPUADDR | $2006 | Open bus | VRAM address set (write toggle) |
| PPUDATA | $2007 | VRAM read (buffered) | VRAM write, address increment |

**CRITICAL: VBlank Race Detection (PpuHandler.read())**
```zig
// src/emulation/bus/handlers/PpuHandler.zig
if (reg == 0x02 and scanline == 241 and dot <= 2 and state.clock.isCpuTick()) {
    state.vblank_ledger.prevent_vbl_set_cycle = state.clock.master_cycles;
}
```
Handler detects race condition and sets prevention flag.

**CRITICAL: NMI Line Update (PpuHandler.write())**
```zig
// src/emulation/bus/handlers/PpuHandler.zig
if (reg == 0x00) {  // PPUCTRL
    const old_nmi_enable = state.ppu.ctrl.nmi_enable;
    const new_nmi_enable = (value & 0x80) != 0;
    const vblank_active = state.vblank_ledger.isFlagVisible();

    // 0→1 transition while VBlank active: trigger NMI
    if (!old_nmi_enable and new_nmi_enable and vblank_active) {
        state.cpu.nmi_line = true;
    }

    // 1→0 transition: clear NMI
    if (old_nmi_enable and !new_nmi_enable) {
        state.cpu.nmi_line = false;
    }
}
```
Handler manages NMI line directly based on PPUCTRL writes.

### Open Bus Behavior

**Current Implementation:** `EmulationState.busRead()` updates open bus AFTER handler returns value.

```zig
// src/emulation/State.zig:busRead()
const value = switch (address) {
    0x0000...0x1FFF => self.handlers.ram.read(self, address),
    // ... other handlers ...
    else => self.handlers.open_bus.read(self, address),
};

// Hardware: All reads update open bus (except $4015)
if (address != 0x4015) {
    self.bus.open_bus = value;
}

return value;
```

**Special Cases:**
- $4015 (APU Status): Does NOT update open bus (hardware quirk)
- All other reads: Update open bus with returned value
- All writes: Update open bus with written value (in busWrite)

### Handler Implementation

All handlers follow the same stateless pattern:

```zig
pub const HandlerName = struct {
    // NO fields - completely stateless!

    pub fn read(_: *const HandlerName, state: anytype, address: u16) u8 {
        // Delegate to Logic modules or access state directly
    }

    pub fn write(_: *HandlerName, state: anytype, address: u16, value: u8) void {
        // Delegate to Logic modules or mutate state directly
    }

    pub fn peek(_: *const HandlerName, state: anytype, address: u16) u8 {
        // No side effects - debugger safe
    }
};
```

**Handler Directory:** `src/emulation/bus/handlers/`
- `RamHandler.zig` - Internal RAM ($0000-$1FFF)
- `PpuHandler.zig` - PPU registers ($2000-$3FFF)
- `ApuHandler.zig` - APU channels ($4000-$4015)
- `OamDmaHandler.zig` - OAM DMA trigger ($4014)
- `ControllerHandler.zig` - Controller ports ($4016-$4017)
- `CartridgeHandler.zig` - Cartridge space ($4020-$FFFF)
- `OpenBusHandler.zig` - Unmapped regions

**Benefits:**
- **Modular:** Each address range isolated in its own file
- **Testable:** Handlers have independent unit tests
- **Debugger-safe:** `peek()` allows inspection without side effects
- **Zero overhead:** Handlers are zero-size, all calls inlined

### Test RAM Support

**Purpose:** Allow tests to run without cartridge

**Address Ranges:**
- $8000-$FFFF: test_ram[address - 0x8000] (PRG ROM area)
- $6000-$7FFF: test_ram[16384 + (address - 0x6000)] (PRG RAM area)

**Behavior:** Falls back to test RAM if no cartridge present.

## Architectural Problems

### Problem 1: Timing Logic in Bus Layer

**Current:** Bus layer knows about:
- PPU scanline/dot position (for race detection)
- CPU tick alignment (phase-dependent checks)
- VBlankLedger timestamps
- NMI line state

**Should Be:** Bus layer only routes to handlers, timing logic in handlers.

### Problem 2: Side Effects Scattered

**Current:** Side effects happen in three places:
1. `EmulationState.busRead()` - VBlank race detection
2. `EmulationState.busWrite()` - NMI line updates
3. Component logic - VBlank flag clear, APU IRQ clear, etc.

**Should Be:** All side effects owned by handlers.

### Problem 3: Tight Coupling

**Current:** Bus layer has direct access to:
- `self.ppu.scanline`, `self.ppu.cycle`
- `self.vblank_ledger`
- `self.cpu.nmi_line`
- `self.clock.isCpuTick()`

**Should Be:** Handlers hold references, bus layer has no component knowledge.

## Handler Mapping (Target Architecture)

Based on this analysis, we need these handlers:

| Handler | Address Range | Dependencies | Responsibilities |
|---------|---------------|--------------|------------------|
| RamHandler | $0000-$1FFF | []u8 ram buffer | 2KB RAM with mirroring |
| PpuHandler | $2000-$3FFF | *PpuState, *VBlankLedger, *CpuState, *MasterClock | PPU registers, VBlank race detection, NMI line updates |
| ApuChannelHandler | $4000-$4003, $4004-$4007, etc. | *ApuState | APU channel registers |
| ApuStatusHandler | $4015 | *ApuState | APU status read (clear IRQ), channel enables |
| OamDmaHandler | $4014 | *OamDma, *MasterClock | OAM DMA trigger |
| ControllerHandler | $4016-$4017 | *ControllerState, *ApuState | Controller shift registers, frame counter |
| CartridgeHandler | $4020-$FFFF | ?*AnyCartridge | Delegates to cartridge mapper |
| OpenBusHandler | (default) | *BusState | Open bus for unmapped regions |

## Migration Strategy

1. Create handlers one at a time (start with OpenBusHandler - simplest)
2. Test each handler in isolation
3. Integrate into handler table
4. Keep old bus code until ALL handlers working
5. Run test suite after each handler
6. Remove old code when all handlers proven

## References

**Current Implementation:**
- `src/emulation/bus/routing.zig` - Current routing logic
- `src/emulation/State.zig:busRead()` (lines 280-414) - Timing checks + routing
- `src/emulation/State.zig:busWrite()` (lines 445-533) - NMI line updates + routing

**Target Pattern:**
- `src/cartridge/mappers/registry.zig` - AnyCartridge tagged union pattern
- `src/cartridge/mappers/Mapper0.zig` - Duck-typed mapper interface
- `src/cartridge/Cartridge.zig` - Generic Cartridge(MapperType) pattern

**Mesen2 Reference:**
- `/home/colin/Development/Mesen2/Core/NES/NesMemoryManager.cpp` - Handler table pattern
- `/home/colin/Development/Mesen2/Core/NES/NesPpu.cpp` - PPU owns VBlank/NMI logic
