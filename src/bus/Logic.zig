//! Bus Logic - Memory bus routing operations
//!
//! Implements NES memory bus read/write operations with handler dispatch.
//! Follows State/Logic separation pattern established by CPU/PPU/APU/DMA/Controller modules.

const BusState = @import("State.zig").State;

/// Read from NES memory bus
/// Routes to appropriate handler and updates open bus
///
/// Parameters:
///   - bus: Bus state (RAM, open bus, handlers)
///   - state: Emulation state (for handler access to subsystems)
///   - address: 16-bit CPU address
///
/// Returns: Byte value from bus
pub inline fn read(bus: *BusState, state: anytype, address: u16) u8 {
    // Capture last read address for DMC corruption (NTSC 2A03 bug)
    state.dma.dmc.last_read_address = address;

    // Dispatch to handlers (parameter-based pattern)
    const value = switch (address) {
        0x0000...0x1FFF => bus.handlers.ram.read(state, address),
        0x2000...0x3FFF => bus.handlers.ppu.read(state, address),
        0x4000...0x4013 => bus.handlers.apu.read(state, address),
        0x4014 => bus.handlers.oam_dma.read(state, address),
        0x4015 => bus.handlers.apu.read(state, address), // Special: does NOT update open bus
        0x4016, 0x4017 => bus.handlers.controller.read(state, address),
        0x4020...0xFFFF => bus.handlers.cartridge.read(state, address),
        else => bus.handlers.open_bus.read(state, address),
    };

    // Hardware: All reads update open bus (except $4015)
    if (address != 0x4015) {
        bus.open_bus.set(value);
    } else {
        bus.open_bus.setInternal(value);
    }

    // Notify debugger about memory access (if attached)
    if (state.debugger) |_| {
        const DebugIntegration = @import("../emulation/debug/integration.zig");
        DebugIntegration.checkMemoryAccess(state, address, value, false);
    }

    return value;
}

/// Write to NES memory bus
/// Routes to appropriate handler and updates open bus
///
/// Parameters:
///   - bus: Bus state (RAM, open bus, handlers)
///   - state: Emulation state (for handler access to subsystems)
///   - address: 16-bit CPU address
///   - value: Byte value to write
pub inline fn write(bus: *BusState, state: anytype, address: u16, value: u8) void {
    // Hardware: All writes update open bus
    bus.open_bus.set(value);

    // Dispatch to handlers (parameter-based pattern)
    switch (address) {
        0x0000...0x1FFF => bus.handlers.ram.write(state, address, value),
        0x2000...0x3FFF => bus.handlers.ppu.write(state, address, value),
        0x4000...0x4013 => bus.handlers.apu.write(state, address, value),
        0x4014 => bus.handlers.oam_dma.write(state, address, value),
        0x4015 => bus.handlers.apu.write(state, address, value),
        0x4016, 0x4017 => bus.handlers.controller.write(state, address, value),
        0x4020...0xFFFF => {
            bus.handlers.cartridge.write(state, address, value);

            // Sync PPU mirroring after cartridge write
            // Some mappers can change mirroring dynamically
            if (state.cart) |*cart| {
                state.ppu.mirroring = cart.getMirroring();
            }
        },
        else => {}, // Unmapped - write ignored
    }

    // Notify debugger about memory access (if attached)
    if (state.debugger) |_| {
        const DebugIntegration = @import("../emulation/debug/integration.zig");
        DebugIntegration.checkMemoryAccess(state, address, value, true);
    }
}

/// Read 16-bit value (little-endian)
/// Used for reading interrupt vectors and 16-bit operands
///
/// Parameters:
///   - bus: Bus state
///   - state: Emulation state
///   - address: 16-bit CPU address
///
/// Returns: 16-bit value (little-endian)
pub inline fn read16(bus: *BusState, state: anytype, address: u16) u16 {
    const low = read(bus, state, address);
    const high = read(bus, state, address +% 1);
    return (@as(u16, high) << 8) | @as(u16, low);
}

/// Dummy read - hardware-accurate 6502 bus access where value is not used
/// The 6502 performs reads during addressing calculations but discards the value
///
/// Parameters:
///   - bus: Bus state
///   - state: Emulation state
///   - address: 16-bit CPU address
pub inline fn dummyRead(bus: *BusState, state: anytype, address: u16) void {
    _ = read(bus, state, address);
}
