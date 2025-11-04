# Memory Handler Architecture (Revised - Parameter-Based)

**Date:** 2025-11-03
**Status:** Final design specification
**Pattern:** Mapper parameter-passing pattern (zero pointers, zero allocations)

## Core Design Principle

**Handlers work EXACTLY like Mappers:**
- Handlers are **stateless** (or have minimal internal state only)
- State passed as **parameter** to methods (like `cart` in mapper methods)
- Handlers **embedded** directly in EmulationState (not heap allocated)
- Dispatch via **switch statement** (Zig native, fast, no indirection)

## Handler Interface (Duck-Typed)

Every handler implements these methods with state as parameter:

```zig
/// Duck-typed handler interface
/// First parameter: handler instance (*const for read, * for write)
/// Second parameter: emulation state (anytype)
/// Third parameter: address (u16)

pub fn read(_: *const HandlerType, state: anytype, address: u16) u8;
pub fn write(_: *HandlerType, state: anytype, address: u16, value: u8) void;
pub fn peek(_: *const HandlerType, state: anytype, address: u16) u8;
```

## Comparison: Mapper vs Handler

**Mapper Pattern (Reference):**
```zig
// Mapper receives cart data via parameter
pub fn cpuRead(_: *const Mapper0, cart: anytype, address: u16) u8 {
    const prg_size = cart.prg_rom.len;  // Access via parameter
    return cart.prg_rom[offset];
}
```

**Handler Pattern (Our Implementation):**
```zig
// Handler receives emulation state via parameter
pub fn read(_: *const RamHandler, state: anytype, address: u16) u8 {
    const ram_addr = address & 0x7FF;   // Mirroring
    return state.bus.ram[ram_addr];      // Access via parameter
}
```

**Why This Works:**
- State is owned by EmulationState (single owner)
- Handlers don't store references (no lifetime issues)
- All access through parameter (explicit, traceable)
- Handlers are pure logic (deterministic, testable)

## EmulationState Layout (Direct Embedding)

```zig
pub const EmulationState = struct {
    // Core components (existing)
    clock: MasterClock,
    cpu: CpuState,
    ppu: PpuState,
    apu: ApuState,
    bus: BusState,
    vblank_ledger: VBlankLedger,
    cart: ?AnyCartridge,
    // ... etc

    // NEW: Handlers directly embedded (zero allocation)
    handlers: struct {
        ram: RamHandler = .{},
        ppu: PpuHandler = .{},
        apu: ApuHandler = .{},
        controller: ControllerHandler = .{},
        oam_dma: OamDmaHandler = .{},
        cartridge: CartridgeHandler = .{},
        open_bus: OpenBusHandler = .{},
    } = .{},

    // Existing methods...
    pub fn busRead(self: *EmulationState, address: u16) u8 {
        // NEW: Dispatch to handlers (pass self as state parameter)
        return switch (address) {
            0x0000...0x1FFF => self.handlers.ram.read(self, address),
            0x2000...0x3FFF => self.handlers.ppu.read(self, address),
            0x4000...0x4013 => self.handlers.apu.read(self, address),
            0x4014 => self.handlers.oam_dma.read(self, address),
            0x4015 => self.handlers.apu.readStatus(self, address),
            0x4016...0x4017 => self.handlers.controller.read(self, address),
            0x4020...0xFFFF => self.handlers.cartridge.read(self, address),
            else => self.handlers.open_bus.read(self, address),
        };
    }
};
```

## Handler Examples

### OpenBusHandler (Simplest - Has Internal State)

```zig
pub const OpenBusHandler = struct {
    value: u8 = 0,  // Internal state (not a reference!)

    pub fn read(self: *const OpenBusHandler, _: anytype, _: u16) u8 {
        return self.value;  // Return stored value
    }

    pub fn write(_: *OpenBusHandler, _: anytype, _: u16, _: u8) void {
        // Writes to unmapped regions ignored
    }

    pub fn peek(self: *const OpenBusHandler, _: anytype, _: u16) u8 {
        return self.value;
    }

    pub fn update(self: *OpenBusHandler, value: u8) void {
        self.value = value;  // Bus layer updates this
    }
};
```

### RamHandler (Stateless - Accesses via Parameter)

```zig
pub const RamHandler = struct {
    // NO fields - completely stateless!

    pub fn read(_: *const RamHandler, state: anytype, address: u16) u8 {
        const ram_addr = address & 0x7FF;  // Mirroring
        return state.bus.ram[ram_addr];     // Access via parameter
    }

    pub fn write(_: *RamHandler, state: anytype, address: u16, value: u8) void {
        const ram_addr = address & 0x7FF;
        state.bus.ram[ram_addr] = value;
    }

    pub fn peek(_: *const RamHandler, state: anytype, address: u16) u8 {
        return read(undefined, state, address);  // Same as read (no side effects)
    }
};
```

### PpuHandler (Complex Side Effects)

```zig
pub const PpuHandler = struct {
    // NO fields - all state accessed via parameter!

    pub fn read(_: *const PpuHandler, state: anytype, address: u16) u8 {
        const reg = address & 0x07;

        if (reg == 0x02) {  // PPUSTATUS
            // Build status byte
            const value = buildStatusByte(
                state.ppu.status.sprite_overflow,
                state.ppu.status.sprite_0_hit,
                state.vblank_ledger.isFlagVisible(),
                state.ppu.open_bus.value,
            );

            // Side effects (access via parameter)
            state.vblank_ledger.last_read_cycle = state.clock.master_cycles;
            state.cpu.nmi_line = false;
            state.ppu.internal.resetToggle();

            // Race detection
            const scanline = state.ppu.scanline;
            const dot = state.ppu.cycle;
            if (scanline == 241 and dot <= 2 and state.clock.isCpuTick()) {
                state.vblank_ledger.prevent_vbl_set_cycle = state.clock.master_cycles;
            }

            return value;
        }

        // Other registers...
        return PpuLogic.readRegister(&state.ppu, state.cartPtr(), reg);
    }

    pub fn write(_: *PpuHandler, state: anytype, address: u16, value: u8) void {
        const reg = address & 0x07;

        if (reg == 0x00) {  // PPUCTRL
            const old_nmi_enable = state.ppu.ctrl.nmi_enable;
            const new_nmi_enable = (value & 0x80) != 0;
            const vblank_active = state.vblank_ledger.isFlagVisible();

            // NMI line updates (access via parameter)
            if (!old_nmi_enable and new_nmi_enable and vblank_active) {
                state.cpu.nmi_line = true;
            }
            if (old_nmi_enable and !new_nmi_enable) {
                state.cpu.nmi_line = false;
            }
        }

        // Delegate to PPU logic
        PpuLogic.writeRegister(&state.ppu, state.cartPtr(), reg, value);
    }

    pub fn peek(_: *const PpuHandler, state: anytype, address: u16) u8 {
        const reg = address & 0x07;
        if (reg == 0x02) {
            // No side effects - just build status byte
            return buildStatusByte(
                state.ppu.status.sprite_overflow,
                state.ppu.status.sprite_0_hit,
                state.vblank_ledger.isFlagVisible(),
                state.ppu.open_bus.value,
            );
        }
        // ... other registers
    }
};
```

## Bus Dispatch (Switch Statement)

**Current busRead() (before):**
```zig
pub fn busRead(self: *EmulationState, address: u16) u8 {
    // Giant switch with inline logic (100+ lines)
    const value = switch (address) {
        0x0000...0x1FFF => self.bus.ram[address & 0x7FF],
        0x2000...0x3FFF => /* complex PPU logic inline */,
        // ... etc
    };
    return value;
}
```

**New busRead() (after):**
```zig
pub fn busRead(self: *EmulationState, address: u16) u8 {
    // Dispatch to handlers (logic in handler modules)
    const value = switch (address) {
        0x0000...0x1FFF => self.handlers.ram.read(self, address),
        0x2000...0x3FFF => self.handlers.ppu.read(self, address),
        0x4000...0x4013 => self.handlers.apu.read(self, address),
        0x4014 => self.handlers.oam_dma.read(self, address),
        0x4015 => self.handlers.apu.readStatus(self, address),
        0x4016...0x4017 => self.handlers.controller.read(self, address),
        0x4020...0xFFFF => self.handlers.cartridge.read(self, address),
        else => self.handlers.open_bus.read(self, address),
    };

    // Update open bus (centralized)
    if (address != 0x4015) {
        self.handlers.open_bus.update(value);
    }

    return value;
}
```

**Advantages:**
- Logic extracted to handler modules (separation of concerns)
- EmulationState.busRead() becomes simple routing
- Each handler testable in isolation
- Still switch statement (fast, Zig-native)
- Zero indirection, zero allocations

## Open Bus Management

Open bus is unique - it has internal state but is updated by the bus layer:

```zig
// After every read (except $4015)
self.handlers.open_bus.update(value);

// After every write
self.handlers.open_bus.update(value);
```

This is the ONLY handler with mutable state that's updated externally.

## Testing Strategy

**Unit Tests (Per Handler):**
```zig
test "RamHandler: mirroring" {
    var state = TestState{
        .bus = .{ .ram = [_]u8{0} ** 2048 },
    };

    var handler = RamHandler{};

    // Write to $0000
    handler.write(&handler, &state, 0x0000, 0x42);

    // Read from mirror $0800
    try testing.expectEqual(@as(u8, 0x42), handler.read(&handler, &state, 0x0800));
}
```

**Integration Tests:**
```zig
test "EmulationState: PPU handler via busRead" {
    var state = EmulationState.init(&config);

    // Read PPUSTATUS via bus
    const value = state.busRead(0x2002);

    // Verify VBlank cleared
    try testing.expect(!state.vblank_ledger.isFlagVisible());
}
```

## Performance

**Zero overhead compared to current implementation:**
- Switch statement → switch statement (same dispatch cost)
- Inline logic → handler.method() (likely inlined by compiler)
- No heap allocations (everything embedded)
- No pointer indirection (direct struct access)

**Actually faster in some cases:**
- Better code locality (handlers in separate modules)
- Better cache utilization (handlers loaded on demand)
- Compiler can optimize handler methods independently

## Migration Path

1. Create handlers (extract logic from current switch)
2. Embed handlers in EmulationState
3. Update busRead()/busWrite() to dispatch to handlers
4. Keep old code until all handlers proven
5. Remove old switch logic
6. Run full test suite

## Summary

**Key Principles:**
1. ✅ Handlers embedded (not pointers)
2. ✅ State passed as parameter (like mappers)
3. ✅ Switch dispatch (Zig-native)
4. ✅ Zero allocations (stack-based)
5. ✅ Separation of concerns (logic in handlers)
6. ✅ Testable (each handler isolated)

**This is the mapper pattern applied to memory handlers. Proven, simple, fast.**

## References

**Mapper Pattern (Proven):**
- `src/cartridge/mappers/Mapper0.zig` - Parameter-based duck typing
- `src/cartridge/Cartridge.zig` - Generic Cartridge(MapperType) factory

**Current Bus:**
- `src/emulation/bus/routing.zig` - Current switch-based dispatch
- `src/emulation/State.zig:busRead()` - Current inline logic

**Hardware:**
- nesdev.org/wiki/CPU_memory_map - NES memory layout
