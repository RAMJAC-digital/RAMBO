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

/// Set OAM corruption flags when rendering is disabled mid-scanline
/// Reference: Mesen2 NesPpu.cpp SetOamCorruptionFlags(), AccuracyCoin lines 12320-12349
///
/// Hardware behavior: When rendering is disabled during sprite evaluation cycles,
/// certain OAM rows become "flagged" for corruption. When rendering is later re-enabled,
/// these flagged rows will have OAM row 0 copied over them.
///
/// Cycle ranges:
/// - Cycles 1-64: Secondary OAM clearing - flag row = cycle >> 1
/// - Cycles 65-256: Sprite evaluation - flag based on secondary_oam_addr (rounded to multiple of 4)
/// - Cycles 256-320: Sprite fetching - flag based on sprite fetch pattern
fn setOamCorruptionFlags(state: *PpuState, dot: u16) void {
    if (dot >= 1 and dot < 64) {
        // Secondary OAM clear phase
        // Hardware increments secondary OAM address every 2 cycles
        const row = dot >> 1; // Divide by 2
        if (row < 32) {
            state.oam_corruption_flags[row] = true;
        }
    } else if (dot >= 256 and dot < 320) {
        // Sprite tile fetching phase
        // 8 sprites × 8 cycles each = 64 cycles total
        const base = (dot - 256) >> 3; // Which sprite (0-7)
        const offset = @min(3, (dot - 256) & 0x07); // Which byte (0-3)
        const row = base * 4 + offset;
        if (row < 32) {
            state.oam_corruption_flags[row] = true;
        }
    } else if (dot >= 65 and dot <= 256) {
        // Sprite evaluation phase
        // Use secondary_oam_addr, but round up to nearest multiple of 4
        // Per AccuracyCoin line 12333: "ceilinged to the nearest multiple of 4"
        const addr = state.sprite_state.secondary_oam_addr;
        const row = (addr + 3) & ~@as(u8, 3); // Round up to multiple of 4
        if (row < 32) {
            state.oam_corruption_flags[row] = true;
        }
    }
}

/// Process OAM corruption by copying OAM row 0 to all flagged rows
/// Reference: Mesen2 NesPpu.cpp ProcessOamCorruption(), AccuracyCoin lines 12310-12318
///
/// Hardware behavior: For each flagged OAM row, copy the 8 bytes from OAM row 0
/// over that row, then clear the flag. Row 0 itself is never corrupted (no effect).
pub fn processOamCorruption(state: *PpuState) void {
    for (0..32) |i| {
        if (state.oam_corruption_flags[i]) {
            // Copy OAM row 0 to this row (skip if this IS row 0)
            if (i > 0) {
                const row_base = i * 8;
                for (0..8) |j| {
                    state.oam[row_base + j] = state.oam[j];
                }
            }
            // Clear the corruption flag
            state.oam_corruption_flags[i] = false;
        }
    }
}

/// Update PPU state at cycle end (deferred state transitions)
/// Reference: Mesen2 NesPpu.cpp UpdateState() lines 1421-1456
///
/// Hardware behavior: Rendering enable/disable has 1-cycle delay. Register writes
/// set pending flag, actual state transition happens at cycle end. This creates
/// the 2-3 cycle delay for OAM corruption to occur after $2001 write.
///
/// Called at end of every PPU cycle if pending_state_update flag is set.
pub fn updatePpuState(state: *PpuState, scanline: i16, dot: u16) void {
    if (!state.pending_state_update) {
        return;
    }

    state.pending_state_update = false;

    // Rendering enabled flag is set with 1-cycle delay (Mesen2 NesPpu.cpp:1425-1426)
    const current_rendering = state.mask.renderingEnabled();
    if (state.prev_rendering_enabled != current_rendering) {
        state.prev_rendering_enabled = current_rendering;

        // Only process during visible/pre-render scanlines
        if (scanline < 240) {
            if (state.prev_rendering_enabled) {
                // Rendering was just enabled - execute pending corruption NOW
                processOamCorruption(state);
            } else {
                // Rendering was just disabled - set corruption flags for LATER
                setOamCorruptionFlags(state, dot);
            }
        }
    }
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

            // Determine VBlank status from the ledger's flag state
            // The flag is managed by VBlankLedger (set at dot 1, cleared by $2002 reads)
            const vblank_active = vblank_ledger.isFlagSet();

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
            state.open_bus.setAll(value, state.frame_count);

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
            if (is_attribute_byte) {
                const sanitized = value & 0xE3;
                result.value = state.open_bus.applyMasked(0x1C, sanitized, state.frame_count);
            } else {
                state.open_bus.setAll(value, state.frame_count);
                result.value = value;
            }
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

                const sanitized = palette_value & 0x3F;
                result.value = state.open_bus.applyMasked(0xC0, sanitized, state.frame_count);
            } else {
                // Normal buffered read: return old buffer, update buffer with new value
                state.internal.read_buffer = memory.readVram(state, cart, addr);

                // Increment VRAM address after read
                state.internal.v +%= state.ctrl.vramIncrementAmount();

                state.open_bus.setAll(buffered_value, state.frame_count);
                result.value = buffered_value;
            }
        },
        else => unreachable,
    }
    return result;
}

/// Write to PPU register (via CPU memory bus)
/// Handles register mirroring and open bus updates
pub fn writeRegister(state: *PpuState, cart: ?*AnyCartridge, address: u16, value: u8) void {
    // Registers are mirrored every 8 bytes through $3FFF
    const reg = address & 0x0007;

    // All writes update the open bus
            state.open_bus.setAll(value, state.frame_count);

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

            // OAM Corruption: Defer state update until cycle end (Mesen2 pattern)
            // Reference: Mesen2 NesPpu.cpp UpdateState() lines 1421-1456
            // Set pending flag - actual corruption logic runs at cycle end
            state.pending_state_update = true;

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
