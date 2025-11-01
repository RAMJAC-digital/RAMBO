//! NES memory bus routing logic
//! Handles memory-mapped I/O for CPU read/write operations
//! Implements complete NES memory map with proper mirroring and open bus behavior

const std = @import("std");
const PpuLogic = @import("../../ppu/Logic.zig");
const ApuLogic = @import("../../apu/Logic.zig");
const AnyCartridge = @import("../../cartridge/mappers/registry.zig").AnyCartridge;

/// Read from NES memory bus
/// Routes to appropriate component and updates open bus
pub inline fn busRead(state: anytype, address: u16) u8 {
    const cart_ptr = if (state.cart) |*cart_ref| cart_ref else null;
    const value = switch (address) {
        // RAM + mirrors ($0000-$1FFF)
        // 2KB RAM mirrored 4 times through $0000-$1FFF
        0x0000...0x1FFF => state.bus.ram[address & 0x7FF],

        // PPU registers + mirrors ($2000-$3FFF)
        // 8 registers mirrored through $2000-$3FFF
        0x2000...0x3FFF => blk: {
            const reg = address & 0x07;

            // VBlank Migration (Phase 2): Pass VBlankLedger
            // readRegister now handles $2002 side effects internally (recordStatusRead)
            const result = PpuLogic.readRegister(
                &state.ppu,
                cart_ptr,
                reg,
                state.vblank_ledger,
            );

            // NOTE: recordStatusRead() is now called inside readRegister() for $2002
            // No need to call it here anymore - single source of truth

            break :blk result;
        },

        // APU and I/O registers ($4000-$4017)
        0x4000...0x4013 => state.bus.open_bus, // APU channels write-only
        0x4014 => state.bus.open_bus, // OAMDMA write-only
        0x4015 => blk: {
            // APU status register (read has side effect)
            const status = ApuLogic.readStatus(&state.apu);
            // Side effect: Clear frame IRQ flag
            ApuLogic.clearFrameIrq(&state.apu);
            break :blk status;
        },
        0x4016 => state.controller.read1() | (state.bus.open_bus & 0xE0), // Controller 1 + open bus bits 5-7
        0x4017 => state.controller.read2() | (state.bus.open_bus & 0xE0), // Controller 2 + open bus bits 5-7

        // Expansion area ($4020-$5FFF) defaults to open bus
        0x4020...0x5FFF => state.bus.open_bus,

        // Cartridge space ($6000-$FFFF)
        0x6000...0xFFFF => blk: {
            if (state.cart) |*cart| {
                break :blk cart.cpuRead(address);
            }
            // No cartridge - check test RAM
            if (state.bus.test_ram) |test_ram| {
                if (address >= 0x8000) {
                    break :blk test_ram[address - 0x8000];
                } else {
                    // PRG RAM region - read from test_ram offset
                    const prg_ram_offset = @as(usize, @intCast(address - 0x6000));
                    const base_offset = 16384;
                    if (test_ram.len > base_offset + prg_ram_offset) {
                        break :blk test_ram[base_offset + prg_ram_offset];
                    }
                }
            }
            // No cartridge or test RAM - open bus
            break :blk state.bus.open_bus;
        },

        // Unmapped regions - return open bus
        else => state.bus.open_bus,
    };

    // Hardware: All reads update open bus (except $4015 which is a special case)
    // $4015 (APU Status) doesn't update open bus because the value is synthesized
    if (address != 0x4015) {
        state.bus.open_bus = value;
    }
    return value;
}

/// Write to NES memory bus
/// Routes to appropriate component and updates open bus
pub inline fn busWrite(state: anytype, address: u16, value: u8) void {
    const cart_ptr = if (state.cart) |*cart_ref| cart_ref else null;
    // Hardware: All writes update open bus
    state.bus.open_bus = value;

    switch (address) {
        // RAM + mirrors ($0000-$1FFF)
        0x0000...0x1FFF => {
            state.bus.ram[address & 0x7FF] = value;
        },

        // PPU registers + mirrors ($2000-$3FFF)
        0x2000...0x3FFF => |addr| {
            const reg = addr & 0x07;
            PpuLogic.writeRegister(&state.ppu, cart_ptr, reg, value);
            // NOTE: PPUCTRL writes ($2000) are handled by State.busWrite() which records
            // NMI enable toggles in VBlankLedger for edge detection
        },

        // APU and I/O registers ($4000-$4017)
        // Pulse 1 ($4000-$4003)
        0x4000...0x4003 => |addr| ApuLogic.writePulse1(&state.apu, @intCast(addr & 0x03), value),

        // Pulse 2 ($4004-$4007)
        0x4004...0x4007 => |addr| ApuLogic.writePulse2(&state.apu, @intCast(addr & 0x03), value),

        // Triangle ($4008-$400B)
        0x4008...0x400B => |addr| ApuLogic.writeTriangle(&state.apu, @intCast(addr & 0x03), value),

        // Noise ($400C-$400F)
        0x400C...0x400F => |addr| ApuLogic.writeNoise(&state.apu, @intCast(addr & 0x03), value),

        // DMC ($4010-$4013)
        0x4010...0x4013 => |addr| ApuLogic.writeDmc(&state.apu, @intCast(addr & 0x03), value),

        0x4014 => {
            // OAM DMA trigger
            // Check if we're on an odd CPU cycle (PPU runs at 3x CPU speed)
            const cpu_cycle = state.clock.ppu_cycles / 3;
            const on_odd_cycle = (cpu_cycle & 1) != 0;
            state.dma.trigger(value, on_odd_cycle);
        },

        // APU Control ($4015)
        0x4015 => ApuLogic.writeControl(&state.apu, value),

        0x4016 => {
            // Controller strobe (bit 0 controls latch/shift mode)
            state.controller.writeStrobe(value);
        },

        // APU Frame Counter ($4017)
        0x4017 => ApuLogic.writeFrameCounter(&state.apu, value),

        // Cartridge space ($4020-$FFFF)
        0x4020...0xFFFF => {
            if (state.cart) |*cart| {
                cart.cpuWrite(address, value);
            } else if (state.bus.test_ram) |test_ram| {
                // Allow test RAM writes to PRG ROM ($8000+) and PRG RAM ($6000-$7FFF)
                if (address >= 0x8000) {
                    test_ram[address - 0x8000] = value;
                } else if (address >= 0x6000 and address < 0x8000) {
                    // PRG RAM region - write to test_ram offset
                    // Map $6000-$7FFF to end of test_ram (after PRG ROM)
                    const prg_ram_offset = (address - 0x6000);
                    if (test_ram.len > 16384 + prg_ram_offset) {
                        test_ram[16384 + prg_ram_offset] = value;
                    }
                }
            }
            // No cartridge or test RAM - write ignored
        },

        // Unmapped regions - write ignored
        else => {},
    }
}

/// Read 16-bit value (little-endian)
/// Used for reading interrupt vectors and 16-bit operands
pub inline fn busRead16(state: anytype, address: u16) u16 {
    // Call through state.busRead() to ensure debugger checks are triggered
    const low = state.busRead(address);
    const high = state.busRead(address +% 1);
    return (@as(u16, high) << 8) | @as(u16, low);
}

/// Read 16-bit value with JMP indirect page wrap bug
/// The 6502 has a bug where JMP ($xxFF) wraps within the page
pub inline fn busRead16Bug(state: anytype, address: u16) u16 {
    const low_addr = address;
    // If low byte is $FF, wrap to $x00 instead of crossing page
    const high_addr = if ((address & 0x00FF) == 0x00FF)
        address & 0xFF00
    else
        address +% 1;

    // Call through state.busRead() to ensure debugger checks are triggered
    const low = state.busRead(low_addr);
    const high = state.busRead(high_addr);
    return (@as(u16, high) << 8) | @as(u16, low);
}
