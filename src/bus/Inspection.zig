//! Bus Inspection Logic - Debugger Memory Reads Without Side Effects
//!
//! Provides read-only memory inspection for debugging purposes.
//! Unlike read(), these functions do NOT trigger hardware side effects:
//! - No PPU register read side effects ($2002 VBlank clear, $2007 buffering)
//! - No open bus value updates
//! - No controller shift register advances
//!
//! All functions are safe to call from debuggers, watchpoints, and memory viewers.

const BusState = @import("State.zig").State;

/// Peek at memory without triggering side effects (debugger-safe read)
///
/// Differences from Logic.read():
/// - No open_bus value update
/// - No PPU register read side effects
/// - No controller shift advance
/// - Always const state (read-only)
///
/// Use cases:
/// - Debugger memory viewer
/// - Watchpoint evaluation
/// - State inspection
///
/// Parameters:
///   - bus: Const bus state (read-only)
///   - state: Const emulation state (read-only)
///   - address: 16-bit CPU address to read from
///
/// Returns: Byte value at address (or open bus value if unmapped)
pub fn peek(bus: *const BusState, state: anytype, address: u16) u8 {
    return switch (address) {
        // RAM + mirrors ($0000-$1FFF)
        0x0000...0x1FFF => bus.ram[address & 0x7FF],

        // PPU registers + mirrors ($2000-$3FFF)
        // Return raw PPU state without side effects
        0x2000...0x3FFF => blk: {
            break :blk switch (address & 0x07) {
                0 => @as(u8, @bitCast(state.ppu.ctrl)), // PPUCTRL
                1 => @as(u8, @bitCast(state.ppu.mask)), // PPUMASK
                2 => @as(u8, @bitCast(state.ppu.status)), // PPUSTATUS
                3 => state.ppu.oam_addr, // OAMADDR
                4 => state.ppu.oam[state.ppu.oam_addr], // OAMDATA
                5 => bus.open_bus.get(), // PPUSCROLL (write-only)
                6 => bus.open_bus.get(), // PPUADDR (write-only)
                7 => state.ppu.internal.read_buffer, // PPUDATA (return buffer, not live read)
                else => unreachable,
            };
        },

        // APU and I/O registers ($4000-$4017)
        0x4000...0x4013 => bus.open_bus.get(),
        0x4014 => bus.open_bus.get(), // OAMDMA write-only
        0x4015 => bus.open_bus.get(),
        0x4016 => (state.controller.shift1 & 0x01) | (bus.open_bus.get() & 0xE0), // Controller 1 peek (no shift)
        0x4017 => (state.controller.shift2 & 0x01) | (bus.open_bus.get() & 0xE0), // Controller 2 peek (no shift)

        // Expansion area ($4020-$5FFF) defaults to open bus
        0x4020...0x5FFF => bus.open_bus.get(),

        // Cartridge space ($6000-$FFFF)
        0x6000...0xFFFF => blk: {
            if (state.cart) |cart| {
                break :blk cart.cpuRead(address);
            }
            // No cartridge - check test RAM
            if (bus.test_ram) |test_ram| {
                if (address >= 0x8000) {
                    break :blk test_ram[address - 0x8000];
                } else {
                    const prg_ram_offset = @as(usize, @intCast(address - 0x6000));
                    const base_offset = 16384;
                    if (test_ram.len > base_offset + prg_ram_offset) {
                        break :blk test_ram[base_offset + prg_ram_offset];
                    }
                }
            }
            // No cartridge or test RAM - open bus
            break :blk bus.open_bus.get();
        },

        // Unmapped regions - return open bus
        else => bus.open_bus.get(),
    };
    // NO open_bus update - this is the key difference from Logic.read()
}
