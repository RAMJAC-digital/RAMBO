//! PPU Register I/O Operations
//!
//! Handles reading and writing PPU registers ($2000-$2007).
//! Implements register mirroring, open bus behavior, and side effects.

const std = @import("std");
const PpuState = @import("../State.zig").PpuState;
const PpuCtrl = @import("../State.zig").PpuCtrl;
const PpuMask = @import("../State.zig").PpuMask;
const AnyCartridge = @import("../../cartridge/mappers/registry.zig").AnyCartridge;
const VBlankLedger = @import("../../emulation/VBlankLedger.zig").VBlankLedger;
const memory = @import("memory.zig");

/// The result of a PPU register read, containing the value and any side-effect signals.
pub const PpuReadResult = struct {
    value: u8,
    read_2002: bool = false, // True if $2002 was read, signaling a side-effect.
};

/// Build PPUSTATUS byte for $2002 read
/// Combines sprite flags from PpuStatus with VBlank flag from VBlankLedger
///
/// Hardware behavior (nesdev.org/wiki/PPU_registers):
/// - Bits 7-5: Status flags (VBlank, Sprite0Hit, SpriteOverflow)
/// - Bits 4-0: Open bus (data bus latch from last access)
///
/// VBlank flag (bit 7) is provided separately because it's managed by
/// VBlankLedger, not PpuStatus struct, to handle race conditions correctly.
///
/// Returns: Byte value to return when reading $2002
pub fn buildStatusByte(
    sprite_overflow: bool,
    sprite_0_hit: bool,
    vblank_flag: bool,
    data_bus_latch: u8,
) u8 {
    var result: u8 = 0;

    // Bit 7: VBlank flag (from VBlankLedger, not PpuStatus)
    if (vblank_flag) result |= 0x80;

    // Bit 6: Sprite 0 hit
    if (sprite_0_hit) result |= 0x40;

    // Bit 5: Sprite overflow
    if (sprite_overflow) result |= 0x20;

    // Bits 0-4: Open bus (data bus latch from previous access)
    result |= (data_bus_latch & 0x1F);

    return result;
}

/// Read from PPU register (via CPU memory bus)
/// Handles register mirroring and open bus behavior
///
/// VBlank Refactor (Phase 4): This function is now pure regarding the VBlankLedger.
/// It accepts the ledger by value, computes the VBlank status, and returns a
/// `PpuReadResult` to signal a $2002 read to the orchestrator (EmulationState).
///
/// Race Condition Fix: Added scanline/dot parameters for read-time VBlank masking.
/// Per Mesen2 and nesdev.org, reading $2002 during scanline 241, dots 0-2 returns
/// VBlank bit = 0 even if flag is set internally.
pub fn readRegister(
    state: *PpuState,
    cart: ?*AnyCartridge,
    address: u16,
    vblank_ledger: VBlankLedger,
    scanline: i16,
    dot: u16,
) PpuReadResult {
    _ = scanline; // Race window prevention handled in State.zig
    _ = dot; // Race window prevention handled in State.zig
    // Registers are mirrored every 8 bytes through $3FFF
    const reg = address & 0x0007;

    var result = PpuReadResult{.value = 0};

    switch (reg) {
        0x0000 => {
            // $2000 PPUCTRL - Write-only, return open bus
            result.value = state.open_bus.read();
        },
        0x0001 => {
            // $2001 PPUMASK - Write-only, return open bus
            result.value = state.open_bus.read();
        },
        0x0002 => {
            // $2002 PPUSTATUS - Read-only

            // Determine VBlank status from the ledger's timestamps.
            // A VBlank is active if it was set more recently than it was cleared by timing
            // AND more recently than it was cleared by a previous read.
            const vblank_active = vblank_ledger.isFlagVisible();

            // Build status byte using the computed flag.
            const value = buildStatusByte(
                state.status.sprite_overflow,
                state.status.sprite_0_hit,
                vblank_active,
                state.open_bus.value,
            );

            // CRITICAL: NO race window masking in hardware reads!
            // Hardware behavior per nesdev.org/wiki/PPU_frame_timing:
            // "Reading on the same PPU clock or one later reads it as set,
            //  clears it, and suppresses the NMI for that frame."
            //
            // Mesen2 NesPpu.cpp ReadRam (line 332-348):
            // - Reads actual flag value (no masking)
            // - Calls UpdateStatusFlag() to clear it
            // - Race window masking ONLY in PeekRam (debugger), not ReadRam!
            //
            // Race window behavior:
            // - Dot 0: Prevents flag from being set (handled in State.zig)
            // - Dot 1-2: Returns actual flag (1 if set), clears it, suppresses NMI
            //
            // Previous bug: We were masking to 0 (copied from Mesen2 PeekRam by mistake)
            // This caused subsequent reads to see flag as already cleared.
            //
            // Reference: nesdev.org/wiki/PPU_frame_timing, Mesen2 NesPpu.cpp:332-348

            // Side effects handled locally or signaled upwards:
            // 1. Signal that a $2002 read occurred. EmulationState will update the ledger.
            result.read_2002 = true;

            // 2. Reset write toggle (local PPU state).
            state.internal.resetToggle();

            // 3. Update open bus with the final status byte (after masking).
            state.open_bus.write(value);

            result.value = value;
        },
        0x0003 => {
            // $2003 OAMADDR - Write-only, return open bus
            result.value = state.open_bus.read();
        },
        0x0004 => {
            // $2004 OAMDATA - Read/write
            const value = state.oam[state.oam_addr];

            // Attribute bytes have bits 2-4 as open bus
            const is_attribute_byte = (state.oam_addr & 0x03) == 0x02;
            const oam_result = if (is_attribute_byte)
                (value & 0xE3) | (state.open_bus.value & 0x1C)
            else
                value;

            // Update open bus
            state.open_bus.write(oam_result);

            result.value = oam_result;
        },
        0x0005 => {
            // $2005 PPUSCROLL - Write-only, return open bus
            result.value = state.open_bus.read();
        },
        0x0006 => {
            // $2006 PPUADDR - Write-only, return open bus
            result.value = state.open_bus.read();
        },
        0x0007 => {
            // $2007 PPUDATA - Buffered read from VRAM
            const addr = state.internal.v;
            const buffered_value = state.internal.read_buffer;

            // Palette reads are NOT buffered (return immediately)
            // BUT the buffer is filled with the underlying nametable address
            // Hardware quirk: $3F00-$3FFF reads fill buffer from $2F00-$2FFF (nametable mirror)
            if (addr >= 0x3F00) {
                // Read palette value directly (unbuffered)
                const palette_value = memory.readVram(state, cart, addr);

                // Fill buffer with underlying nametable ($3Fxx - $1000 = $2Fxx)
                const nametable_addr = addr & 0x2FFF; // Map $3F00-$3FFF to $2F00-$2FFF
                state.internal.read_buffer = memory.readVram(state, cart, nametable_addr);

                // Increment VRAM address after read
                state.internal.v +%= state.ctrl.vramIncrementAmount();

                // Update open bus
                state.open_bus.write(palette_value);

                result.value = palette_value;
            } else {
                // Normal buffered read: return old buffer, update buffer with new value
                state.internal.read_buffer = memory.readVram(state, cart, addr);

                // Increment VRAM address after read
                state.internal.v +%= state.ctrl.vramIncrementAmount();

                // Update open bus
                state.open_bus.write(buffered_value);

                result.value = buffered_value;
            }
        },
        else => unreachable,
    }
    return result;
}

/// Write to PPU register (via CPU memory bus)
/// Handles register mirroring and open bus updates
pub fn writeRegister(state: *PpuState, cart: ?*AnyCartridge, address: u16, value: u8, scanline: i16, master_cycles: u64) void {
    // Registers are mirrored every 8 bytes through $3FFF
    const reg = address & 0x0007;

    // All writes update the open bus
    state.open_bus.write(value);

    switch (reg) {
        0x0000 => {
            // $2000 PPUCTRL
            // Ignored during warm-up period (first ~29,658 CPU cycles)
            if (!state.warmup_complete) {
                return;
            }

            state.ctrl = PpuCtrl.fromByte(value);

            // Update t register bits 10-11 (nametable select)
            state.internal.t = (state.internal.t & 0xF3FF) |
                (@as(u16, value & 0x03) << 10);
        },
        0x0001 => {
            // $2001 PPUMASK
            // Buffered during warm-up period (first ~29,658 CPU cycles)
            if (!state.warmup_complete) {
                state.warmup_ppumask_buffer = value;
                return;
            }

            // OAM Corruption: Detect rendering enable/disable during visible/pre-render scanlines
            // Reference: AccuracyCoin OAM corruption test, nesdev.org wiki
            const was_rendering = state.mask.renderingEnabled();
            const new_mask = PpuMask.fromByte(value);
            const is_rendering = new_mask.renderingEnabled();

            // Rendering disabled mid-scanline - record corruption seed
            if (was_rendering and !is_rendering) {
                if (scanline >= -1 and scanline <= 239) {
                    state.oam_corruption_pending = true;
                    state.oam_corruption_seed = state.sprite_state.secondary_oam_addr;
                }
            }

            // Rendering enabled - schedule corruption if pending
            if (!was_rendering and is_rendering) {
                if (state.oam_corruption_pending and scanline >= -1 and scanline <= 239) {
                    // Compute trigger cycle based on phase (CPU/PPU alignment)
                    // Phase 0/3: 2 PPU cycles delay, Phase 1/2: 3 PPU cycles delay
                    const phase = master_cycles % 3;
                    const delay: u64 = if (phase == 0 or phase == 3) @as(u64, 2) else @as(u64, 3);
                    state.oam_corruption_trigger_cycle = master_cycles + delay;
                }
            }

            state.mask = new_mask;
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

// ============================================================================
// Tests
// ============================================================================

test {
    std.testing.refAllDeclsRecursive(@This());
}

const testing = std.testing;

test "buildStatusByte: all flags false, zero open bus" {
    const result = buildStatusByte(false, false, false, 0x00);
    try testing.expectEqual(@as(u8, 0x00), result);
}

test "buildStatusByte: VBlank flag set" {
    const result = buildStatusByte(false, false, true, 0x00);
    try testing.expectEqual(@as(u8, 0x80), result);
}

test "buildStatusByte: Sprite 0 hit set" {
    const result = buildStatusByte(false, true, false, 0x00);
    try testing.expectEqual(@as(u8, 0x40), result);
}

test "buildStatusByte: Sprite overflow set" {
    const result = buildStatusByte(true, false, false, 0x00);
    try testing.expectEqual(@as(u8, 0x20), result);
}

test "buildStatusByte: All status flags set" {
    const result = buildStatusByte(true, true, true, 0x00);
    try testing.expectEqual(@as(u8, 0xE0), result);
}

test "buildStatusByte: Open bus bits preserved" {
    const result = buildStatusByte(false, false, false, 0x1F);
    try testing.expectEqual(@as(u8, 0x1F), result);
}

test "buildStatusByte: Status flags and open bus combined" {
    const result = buildStatusByte(true, true, true, 0x15);
    try testing.expectEqual(@as(u8, 0xF5), result); // 0xE0 | 0x15
}

test "buildStatusByte: Open bus upper bits ignored" {
    const result = buildStatusByte(false, false, false, 0xFF);
    try testing.expectEqual(@as(u8, 0x1F), result); // Only lower 5 bits
}
