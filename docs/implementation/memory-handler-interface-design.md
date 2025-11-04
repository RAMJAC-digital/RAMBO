# MemoryHandler Interface Design

**Date:** 2025-11-03
**Status:** Design specification
**Pattern:** Based on proven Mapper duck-typing pattern

## Design Philosophy

Follow the **exact same pattern** as RAMBO's mapper system:
- Duck-typed interface (no formal interface type)
- Comptime polymorphism (zero runtime overhead)
- Explicit dependencies (handlers own their references)
- Tagged union dispatch (AnyHandler like AnyCartridge)

## Core Interface (Duck-Typed)

Every handler MUST implement these methods:

```zig
/// MemoryHandler Interface (duck-typed, no formal type)
///
/// Required methods for any memory handler:
/// - read(self: *const HandlerType, address: u16) u8
/// - write(self: *HandlerType, address: u16, value: u8) void
/// - peek(self: *const HandlerType, address: u16) u8
///
/// Pattern: Exactly like Mapper interface
/// - First parameter: handler instance (*const for reads, * for writes)
/// - Explicit parameters: No anytype magic
/// - Side effects: Owned by handler implementation
```

### Method: read()

**Signature:**
```zig
pub fn read(self: *const HandlerType, address: u16) u8
```

**Responsibilities:**
- Return byte from memory/register
- Execute ALL read side effects (VBlank clear, IRQ clear, etc.)
- Update internal handler state as needed

**Examples:**
```zig
// PpuHandler - has side effects
pub fn read(self: *const PpuHandler, address: u16) u8 {
    const reg = address & 0x07;
    if (reg == 0x02) {  // PPUSTATUS
        // Side effect: Clear VBlank flag
        self.vblank_ledger.last_read_cycle = self.clock.master_cycles;
        // Side effect: Clear NMI line
        self.cpu.nmi_line = false;
        // Return status byte
        return buildStatusByte(...);
    }
    ...
}

// RamHandler - no side effects
pub fn read(self: *const RamHandler, address: u16) u8 {
    return self.ram[address & 0x7FF];  // Just return value
}
```

### Method: write()

**Signature:**
```zig
pub fn write(self: *HandlerType, address: u16, value: u8) void
```

**Responsibilities:**
- Write byte to memory/register
- Execute ALL write side effects
- Update internal handler state

**Examples:**
```zig
// PpuHandler - has side effects
pub fn write(self: *PpuHandler, address: u16, value: u8) void {
    const reg = address & 0x07;
    if (reg == 0x00) {  // PPUCTRL
        const old_nmi_enable = self.ppu.ctrl.nmi_enable;
        const new_nmi_enable = (value & 0x80) != 0;

        // Side effect: Update NMI line immediately
        if (!old_nmi_enable and new_nmi_enable and self.vblank_ledger.isFlagVisible()) {
            self.cpu.nmi_line = true;
        }
        if (old_nmi_enable and !new_nmi_enable) {
            self.cpu.nmi_line = false;
        }
    }

    // Delegate to PPU logic
    PpuLogic.writeRegister(self.ppu, ...);
}

// RamHandler - no side effects
pub fn write(self: *RamHandler, address: u16, value: u8) void {
    self.ram[address & 0x7FF] = value;  // Just write value
}
```

### Method: peek()

**Signature:**
```zig
pub fn peek(self: *const HandlerType, address: u16) u8
```

**Responsibilities:**
- Return byte WITHOUT side effects
- Used by debugger for inspection
- MUST NOT modify any state

**Mesen2 Reference:** DebugRead() vs Read()

**Examples:**
```zig
// PpuHandler - no side effects
pub fn peek(self: *const PpuHandler, address: u16) u8 {
    const reg = address & 0x07;
    if (reg == 0x02) {  // PPUSTATUS
        // No side effects - just return current value
        return buildStatusByte(
            self.ppu.status.sprite_overflow,
            self.ppu.status.sprite_0_hit,
            self.vblank_ledger.isFlagVisible(),
            self.ppu.open_bus.value,
        );
    }
    ...
}

// RamHandler - same as read (no side effects anyway)
pub fn peek(self: *const RamHandler, address: u16) u8 {
    return self.ram[address & 0x7FF];
}
```

## Handler Dependencies Pattern

Handlers hold **references** to components they need, just like mappers hold references to cart data.

**Mapper Pattern (Reference):**
```zig
// Mapper receives cart reference via anytype parameter
pub fn cpuRead(_: *const Mapper0, cart: anytype, address: u16) u8 {
    return cart.prg_rom[offset];  // Access cart data
}
```

**Handler Pattern (Our Implementation):**
```zig
// Handler owns references in its own struct
pub const PpuHandler = struct {
    ppu: *PpuState,              // Mutable reference (writes)
    vblank_ledger: *VBlankLedger, // Mutable (update timestamps)
    cpu: *CpuState,              // Mutable (NMI line)
    clock: *const MasterClock,   // Immutable (read cycles)

    pub fn read(self: *const PpuHandler, address: u16) u8 {
        // Direct access to dependencies
        const cycle = self.clock.master_cycles;
        self.vblank_ledger.last_read_cycle = cycle;
        ...
    }
};
```

**Why Different from Mappers?**
- Mappers: Cart data passed as parameter (cart owned by Cartridge struct)
- Handlers: Components owned by EmulationState, handlers just hold references
- Both patterns: Explicit dependencies, no hidden state

## Tagged Union Dispatch (like AnyCartridge)

**NOT USED** - Handlers will use array table dispatch instead.

**Rationale:**
- Mappers: Small, fixed set (6 types in Phase 1)
- Handlers: Large set (8+ types), address-based dispatch
- Mappers: Tag determined by ROM header
- Handlers: Dispatch determined by address (array lookup faster than switch)

**Pattern from Mesen2:**
```cpp
INesMemoryHandler** _ramReadHandlers;   // Array of handler pointers
uint8_t value = _ramReadHandlers[addr]->ReadRam(addr);
```

**Our Implementation:**
```zig
const HandlerTable = struct {
    read_handlers: [0x10000]?*const AnyHandler,  // One per address

    pub fn read(self: HandlerTable, address: u16) u8 {
        const handler = self.read_handlers[address] orelse &default_handler;
        return handler.read(address);
    }
};
```

## Handler Registration Pattern

Like Mesen2's RegisterIODevice():

```zig
pub fn registerHandler(
    table: *HandlerTable,
    handler: *AnyHandler,
    start_addr: u16,
    end_addr: u16,
) void {
    var addr = start_addr;
    while (addr <= end_addr) : (addr += 1) {
        table.read_handlers[addr] = handler;
        table.write_handlers[addr] = handler;
    }
}
```

**Usage:**
```zig
var ppu_handler = PpuHandler{
    .ppu = &state.ppu,
    .vblank_ledger = &state.vblank_ledger,
    .cpu = &state.cpu,
    .clock = &state.clock,
};

// Register PPU handler for $2000-$3FFF (mirrored)
table.registerHandler(&ppu_handler, 0x2000, 0x3FFF);
```

## Comparison: Mapper vs Handler Interface

| Aspect | Mapper Pattern | Handler Pattern |
|--------|----------------|-----------------|
| **Duck Typing** | ✓ Yes (no formal interface) | ✓ Yes (same) |
| **Dispatch** | Tagged union (switch) | Array table (lookup) |
| **Dependencies** | Cart data via parameter | Component refs in struct |
| **Methods** | cpuRead, cpuWrite, reset, etc. | read, write, peek |
| **Side Effects** | In mapper methods | In handler methods |
| **Testing** | Unit test mapper directly | Unit test handler directly |

## Implementation Checklist

- [ ] Create `AnyHandler` type (wrapper for type erasure)
- [ ] Create `HandlerTable` struct (array + registration)
- [ ] Create each handler (RamHandler, PpuHandler, etc.)
- [ ] Test each handler in isolation
- [ ] Integrate into EmulationState
- [ ] Replace bus routing switch statement

## References

**Mapper Pattern (Proven):**
- `src/cartridge/Cartridge.zig` - Generic Cartridge(MapperType)
- `src/cartridge/mappers/registry.zig` - AnyCartridge tagged union
- `src/cartridge/mappers/Mapper0.zig` - Duck-typed interface example

**Mesen2 Handler Pattern (Reference):**
- `/home/colin/Development/Mesen2/Core/NES/NesMemoryManager.h` - Handler table
- `/home/colin/Development/Mesen2/Core/NES/NesMemoryManager.cpp:125-136` - Read dispatch
- `/home/colin/Development/Mesen2/Core/NES/INesMemoryHandler.h` - Handler interface

**Hardware:**
- nesdev.org/wiki/CPU_memory_map - NES CPU memory layout
