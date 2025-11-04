# Memory Handler Taxonomy

**Date:** 2025-11-03
**Status:** ✅ IMPLEMENTED - All 7 handlers complete and functional
**Location:** `src/emulation/bus/handlers/`

## Overview

Complete list of all memory handlers for NES emulation, organized by complexity.

**Implementation Status:** All handlers implemented, unit tested, and integrated into EmulationState

---

## Handler Catalog

### 1. OpenBusHandler ✅ IMPLEMENTED

**File:** `src/emulation/bus/handlers/OpenBusHandler.zig`

**Address Range:** Default for unmapped regions

**Implementation:**
```zig
pub const OpenBusHandler = struct {
    // NO fields - completely stateless!
    // Accesses state.bus.open_bus through parameter
};
```

**Behavior:**
- **read()**: Return `state.bus.open_bus` (current value on data bus)
- **write()**: No-op (writes to unmapped regions ignored)
- **peek()**: Same as read (no side effects)

**Complexity:** ⭐ (1/5) - No side effects, just state access

**Hardware Reference:** Mesen2 OpenBusHandler.h

**Unit Tests:** `OpenBusHandler.zig` (embedded, all passing)

---

### 2. RamHandler ✅ IMPLEMENTED

**File:** `src/emulation/bus/handlers/RamHandler.zig`

**Address Range:** $0000-$1FFF (2KB RAM mirrored 4 times)

**Implementation:**
```zig
pub const RamHandler = struct {
    // NO fields - completely stateless!
    // Accesses state.bus.ram through parameter
};
```

**Behavior:**
- **read()**: `state.bus.ram[address & 0x7FF]` (4x mirroring)
- **write()**: `state.bus.ram[address & 0x7FF] = value` (4x mirroring)
- **peek()**: Same as read (no side effects)

**Complexity:** ⭐ (1/5) - Simple mirroring, no side effects

**Hardware Reference:** nesdev.org/wiki/CPU_memory_map#RAM

**Unit Tests:** `RamHandler.zig` (embedded, all passing)

---

### 3. OamDmaHandler ✅ IMPLEMENTED

**File:** `src/emulation/bus/handlers/OamDmaHandler.zig`

**Address Range:** $4014 (single address)

**Implementation:**
```zig
pub const OamDmaHandler = struct {
    // NO fields - completely stateless!
    // Accesses state.dma and state.clock through parameter
};
```

**Behavior:**
- **read()**: Return `state.bus.open_bus` (write-only register)
- **write()**: Trigger OAM DMA transfer
  - Calculate odd/even cycle: `state.clock.cpuCycles() & 1`
  - Call `state.dma.trigger(page, on_odd_cycle)`
- **peek()**: Return `state.bus.open_bus`

**Complexity:** ⭐⭐ (2/5) - Write triggers DMA, read is trivial

**Hardware Reference:** nesdev.org/wiki/PPU_OAM#DMA

**Unit Tests:** `OamDmaHandler.zig` (embedded, all passing)

---

### 4. ControllerHandler ✅ IMPLEMENTED

**File:** `src/emulation/bus/handlers/ControllerHandler.zig`

**Address Range:** $4016-$4017

**Dependencies:**
```zig
pub const ControllerHandler = struct {
    controller: *ControllerState,  // Shift registers
    apu: *ApuState,               // For $4017 frame counter
    open_bus: *u8,                // For bits 5-7 masking
};
```

**Behavior:**
- **read()**:
  - $4016: `controller.read1() | (open_bus.* & 0xE0)`
  - $4017: `controller.read2() | (open_bus.* & 0xE0)`
- **write()**:
  - $4016: `controller.writeStrobe(value)`
  - $4017: `ApuLogic.writeFrameCounter(apu, value)`
- **peek()**: Return current shift register state (no latch/shift)

**Complexity:** ⭐⭐ (2/5) - Shift registers + open bus masking

**Hardware Reference:** nesdev.org/wiki/Standard_controller

---

### 5. CartridgeHandler ✅ IMPLEMENTED

**File:** `src/emulation/bus/handlers/CartridgeHandler.zig`

**Address Range:** $4020-$FFFF (PRG RAM + PRG ROM + mapper registers)

**Dependencies:**
```zig
pub const CartridgeHandler = struct {
    cart: ?*AnyCartridge,      // Optional cartridge (may be null)
    test_ram: ?[]u8,           // Optional test RAM (for harness)
    open_bus: *u8,             // Fallback for no cartridge
};
```

**Behavior:**
- **read()**:
  - If cart: Delegate to `cart.cpuRead(address)`
  - Else if test_ram: Map $8000+ to test_ram
  - Else: Return open bus
- **write()**:
  - If cart: Delegate to `cart.cpuWrite(address, value)`
  - Else if test_ram: Allow writes (test harness)
  - Else: No-op
- **peek()**: Same as read (cart.cpuRead() has no side effects)

**Complexity:** ⭐⭐ (2/5) - Delegation, fallback logic

**Hardware Reference:** nesdev.org/wiki/CPU_memory_map#Cartridge

---

### 6. ApuHandler ✅ IMPLEMENTED

**File:** `src/emulation/bus/handlers/ApuHandler.zig`

**Address Range:** $4000-$4013, $4015, $4017 (APU registers)

**Dependencies:**
```zig
pub const ApuHandler = struct {
    apu: *ApuState,  // APU state
};
```

**Behavior:**
- **read()**:
  - $4015: APU status byte, **side effect: clear frame IRQ**
  - $4000-$4013: Open bus (write-only channels)
  - $4017: Open bus (write-only frame counter)
- **write()**:
  - Delegate to ApuLogic per register
  - $4000-$4003: Pulse 1
  - $4004-$4007: Pulse 2
  - $4008-$400B: Triangle
  - $400C-$400F: Noise
  - $4010-$4013: DMC
  - $4015: Channel enables
  - $4017: Frame counter
- **peek()**: Return status without clearing IRQ

**Complexity:** ⭐⭐⭐ (3/5) - Multiple registers, IRQ side effect

**Hardware Reference:** nesdev.org/wiki/APU

**Special:** $4015 read does NOT update open bus (hardware quirk)

---

### 7. PpuHandler ✅ IMPLEMENTED (Most Complex)

**File:** `src/emulation/bus/handlers/PpuHandler.zig`

**Address Range:** $2000-$3FFF (8 PPU registers mirrored)

**Dependencies:**
```zig
pub const PpuHandler = struct {
    ppu: *PpuState,                // PPU state (registers, VRAM, OAM)
    vblank_ledger: *VBlankLedger,  // VBlank timestamp tracking
    cpu: *CpuState,                // For NMI line updates
    clock: *const MasterClock,     // For race detection
    cart: ?*AnyCartridge,          // For CHR access
};
```

**Behavior:**

**read()** - Complex side effects:
- $2000 (PPUCTRL): Open bus
- $2001 (PPUMASK): Open bus
- $2002 (PPUSTATUS): **COMPLEX - see below**
- $2003 (OAMADDR): Open bus
- $2004 (OAMDATA): Read OAM byte
- $2005 (PPUSCROLL): Open bus
- $2006 (PPUADDR): Open bus
- $2007 (PPUDATA): Read VRAM (buffered), increment address

**$2002 PPUSTATUS Read (Critical):**
```zig
if (reg == 0x02) {
    // 1. Build status byte
    const value = buildStatusByte(
        ppu.status.sprite_overflow,
        ppu.status.sprite_0_hit,
        vblank_ledger.isFlagVisible(),
        ppu.open_bus.value,
    );

    // 2. Side effect: Clear VBlank flag
    vblank_ledger.last_read_cycle = clock.master_cycles;

    // 3. Side effect: Clear NMI line (like Mesen2)
    cpu.nmi_line = false;

    // 4. Side effect: Reset write toggle
    ppu.internal.resetToggle();

    // 5. Race detection: Prevent VBlank set if reading during race window
    const scanline = ppu.scanline;
    const dot = ppu.cycle;
    if (scanline == 241 and dot <= 2 and clock.isCpuTick()) {
        vblank_ledger.prevent_vbl_set_cycle = clock.master_cycles;
    }

    return value;
}
```

**write()** - Complex side effects:
- $2000 (PPUCTRL): **CRITICAL - NMI line update (immediate)**
  ```zig
  const old_nmi_enable = ppu.ctrl.nmi_enable;
  const new_nmi_enable = (value & 0x80) != 0;
  const vblank_active = vblank_ledger.isFlagVisible();

  // Edge trigger: 0→1 transition
  if (!old_nmi_enable and new_nmi_enable and vblank_active) {
      cpu.nmi_line = true;
  }

  // Disable: 1→0 transition
  if (old_nmi_enable and !new_nmi_enable) {
      cpu.nmi_line = false;
  }

  PpuLogic.writeRegister(ppu, cart, reg, value);
  ```
- $2001-$2007: Delegate to PpuLogic

**peek()**: Return status without side effects (debugger)

**Complexity:** ⭐⭐⭐⭐⭐ (5/5) - Timing-sensitive, NMI coordination, race conditions

**Hardware References:**
- nesdev.org/wiki/PPU_registers
- nesdev.org/wiki/NMI
- Mesen2 NesPpu.cpp:TriggerNmi(), UpdateStatusFlag()

---

## Implementation Order

**Phase 1: Simple Handlers (Prove Pattern)**
1. OpenBusHandler - Simplest, proves infrastructure works
2. RamHandler - Simple mirroring, no side effects
3. OamDmaHandler - Single register, simple trigger

**Phase 2: Medium Handlers (Build Confidence)**
4. ControllerHandler - Shift registers, open bus masking
5. CartridgeHandler - Delegation pattern, fallback logic

**Phase 3: Complex Handlers (Final Integration)**
6. ApuHandler - Multiple registers, IRQ side effect
7. PpuHandler - Most complex, timing-sensitive, NMI coordination

---

## Testing Strategy Per Handler

**Unit Tests (Each Handler):**
- Test read/write for all addresses in range
- Verify side effects (IRQ clear, NMI updates, etc.)
- Test peek() has no side effects
- Test edge cases (race conditions for PPU, mirroring for RAM)

**Integration Tests (Via Handler Table):**
- Test handler coordination (PPU → CPU NMI)
- Test open bus propagation
- Test debugger peek() vs normal read()
- Test full address space coverage

---

## Handler Summary Table

| Handler | Complexity | Address Range | Side Effects | Dependencies |
|---------|-----------|---------------|--------------|--------------|
| OpenBusHandler | ⭐ | (unmapped) | None | value |
| RamHandler | ⭐ | $0000-$1FFF | None | *ram |
| OamDmaHandler | ⭐⭐ | $4014 | Trigger DMA | *OamDma, *MasterClock |
| ControllerHandler | ⭐⭐ | $4016-$4017 | Shift registers | *ControllerState, *ApuState |
| CartridgeHandler | ⭐⭐ | $4020-$FFFF | Mapper state | ?*AnyCartridge, ?[]u8 |
| ApuHandler | ⭐⭐⭐ | $4000-$4015 | Clear IRQ | *ApuState |
| PpuHandler | ⭐⭐⭐⭐⭐ | $2000-$3FFF | VBlank clear, NMI line, race detection | *PpuState, *VBlankLedger, *CpuState, *MasterClock, ?*AnyCartridge |

---

## References

**Current Implementation:**
- `docs/implementation/current-bus-architecture.md` - Address range analysis
- `src/emulation/bus/routing.zig` - Current routing logic

**Design Patterns:**
- `docs/implementation/memory-handler-interface-design.md` - Interface specification
- `src/cartridge/mappers/Mapper0.zig` - Duck-typing reference

**Hardware:**
- nesdev.org/wiki/CPU_memory_map - NES memory layout
- nesdev.org/wiki/PPU_registers - PPU register behavior
- nesdev.org/wiki/APU - APU register behavior
