//! PPU Register I/O Operations
//!
//! Handles reading and writing PPU registers ($2000-$2007).
//! Implements register mirroring, open bus behavior, and side effects.

const std = @import("std");
const PpuState = @import("../State.zig").PpuState;
const PpuCtrl = @import("../State.zig").PpuCtrl;
const PpuMask = @import("../State.zig").PpuMask;
const AnyCartridge = @import("../../cartridge/mappers/registry.zig").AnyCartridge;
const memory = @import("memory.zig");

// DEBUG: $2002 read diagnostics
const DEBUG_PPUSTATUS = false;

/// Read from PPU register (via CPU memory bus)
/// Handles register mirroring and open bus behavior
pub fn readRegister(state: *PpuState, cart: ?*AnyCartridge, address: u16) u8 {
    // Registers are mirrored every 8 bytes through $3FFF
    const reg = address & 0x0007;

    return switch (reg) {
        0x0000 => blk: {
            // $2000 PPUCTRL - Write-only, return open bus
            break :blk state.open_bus.read();
        },
        0x0001 => blk: {
            // $2001 PPUMASK - Write-only, return open bus
            break :blk state.open_bus.read();
        },
        0x0002 => blk: {
            // $2002 PPUSTATUS - Read-only
            const value = state.status.toByte(state.open_bus.value);

            // Debug disabled for performance

            // Side effects:
            // 1. Clear VBlank flag
            state.status.vblank = false;

            // 2. Reset write toggle
            state.internal.resetToggle();

            // 3. Update open bus with status (top 3 bits)
            state.open_bus.write(value);

            break :blk value;
        },
        0x0003 => blk: {
            // $2003 OAMADDR - Write-only, return open bus
            break :blk state.open_bus.read();
        },
        0x0004 => blk: {
            // $2004 OAMDATA - Read/write
            const value = state.oam[state.oam_addr];

            // Attribute bytes have bits 2-4 as open bus
            const is_attribute_byte = (state.oam_addr & 0x03) == 0x02;
            const result = if (is_attribute_byte)
                (value & 0xE3) | (state.open_bus.value & 0x1C)
            else
                value;

            // Update open bus
            state.open_bus.write(result);

            break :blk result;
        },
        0x0005 => blk: {
            // $2005 PPUSCROLL - Write-only, return open bus
            break :blk state.open_bus.read();
        },
        0x0006 => blk: {
            // $2006 PPUADDR - Write-only, return open bus
            break :blk state.open_bus.read();
        },
        0x0007 => blk: {
            // $2007 PPUDATA - Buffered read from VRAM
            const addr = state.internal.v;
            const buffered_value = state.internal.read_buffer;

            // Update buffer with current VRAM value
            state.internal.read_buffer = memory.readVram(state, cart, addr);

            // Increment VRAM address after read
            state.internal.v +%= state.ctrl.vramIncrementAmount();

            // Palette reads are NOT buffered (return current, not buffered)
            // All other reads return the buffered value
            const value = if (addr >= 0x3F00) state.internal.read_buffer else buffered_value;

            // Update open bus
            state.open_bus.write(value);

            break :blk value;
        },
        else => unreachable,
    };
}

/// Write to PPU register (via CPU memory bus)
/// Handles register mirroring and open bus updates
pub fn writeRegister(state: *PpuState, cart: ?*AnyCartridge, address: u16, value: u8) void {
    // Registers are mirrored every 8 bytes through $3FFF
    const reg = address & 0x0007;

    // All writes update the open bus
    state.open_bus.write(value);

    switch (reg) {
        0x0000 => {
            // $2000 PPUCTRL
            // Ignored during warm-up period (first ~29,658 CPU cycles)
            if (!state.warmup_complete) return;

            state.ctrl = PpuCtrl.fromByte(value);

            // Update t register bits 10-11 (nametable select)
            state.internal.t = (state.internal.t & 0xF3FF) |
                (@as(u16, value & 0x03) << 10);
        },
        0x0001 => {
            // $2001 PPUMASK
            // Ignored during warm-up period (first ~29,658 CPU cycles)
            if (!state.warmup_complete) {
                if (DEBUG_PPUSTATUS) {
                    std.debug.print("[PPUMASK] Write 0x{X:0>2} IGNORED (warmup not complete)\n", .{value});
                }
                return;
            }

            if (DEBUG_PPUSTATUS) {
                std.debug.print("[PPUMASK] Write 0x{X:0>2}, show_bg={}, show_sprites={}\n", .{ value, (value & 0x08) != 0, (value & 0x10) != 0 });
            }
            state.mask = PpuMask.fromByte(value);
        },
        0x0002 => {
            // $2002 PPUSTATUS - Read-only, write has no effect
        },
        0x0003 => {
            // $2003 OAMADDR
            state.oam_addr = value;
        },
        0x0004 => {
            // $2004 OAMDATA
            state.oam[state.oam_addr] = value;
            state.oam_addr +%= 1; // Wraps at 256
        },
        0x0005 => {
            // $2005 PPUSCROLL
            // Ignored during warm-up period (first ~29,658 CPU cycles)
            if (!state.warmup_complete) return;

            if (!state.internal.w) {
                // First write: X scroll
                state.internal.t = (state.internal.t & 0xFFE0) |
                    (@as(u16, value) >> 3);
                state.internal.x = @truncate(value & 0x07);
                state.internal.w = true;
            } else {
                // Second write: Y scroll
                state.internal.t = (state.internal.t & 0x8FFF) |
                    ((@as(u16, value) & 0x07) << 12);
                state.internal.t = (state.internal.t & 0xFC1F) |
                    ((@as(u16, value) & 0xF8) << 2);
                state.internal.w = false;
            }
        },
        0x0006 => {
            // $2006 PPUADDR
            // Ignored during warm-up period (first ~29,658 CPU cycles)
            if (!state.warmup_complete) return;

            if (!state.internal.w) {
                // First write: High byte
                state.internal.t = (state.internal.t & 0x80FF) |
                    ((@as(u16, value) & 0x3F) << 8);
                state.internal.w = true;
            } else {
                // Second write: Low byte
                state.internal.t = (state.internal.t & 0xFF00) |
                    @as(u16, value);
                state.internal.v = state.internal.t;
                state.internal.w = false;
            }
        },
        0x0007 => {
            // $2007 PPUDATA - Write to VRAM
            const addr = state.internal.v;

            // Write to VRAM
            memory.writeVram(state, cart, addr, value);

            // Increment VRAM address after write
            state.internal.v +%= state.ctrl.vramIncrementAmount();
        },
        else => unreachable, // reg is masked to 0-7
    }
}
