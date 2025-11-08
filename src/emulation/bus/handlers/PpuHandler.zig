// PpuHandler.zig
//
// Handles $2000-$3FFF (PPU registers, mirrored every 8 bytes).
// Contains critical VBlank/NMI timing logic previously in bus layer.
//
// Complexity: ⭐⭐⭐⭐⭐ (5/5) - Timing-sensitive, NMI coordination, race conditions
//
// Hardware Reference:
// - nesdev.org/wiki/PPU_registers
// - nesdev.org/wiki/NMI
// - nesdev.org/wiki/PPU_frame_timing
//
// Mesen2 Reference:
// - Core/NES/NesPpu.cpp:TriggerNmi(), UpdateStatusFlag()

const std = @import("std");
const PpuLogic = @import("../../../ppu/Logic.zig");
const PpuReadResult = PpuLogic.PpuReadResult;

/// Handler for $2000-$3FFF (PPU registers)
///
/// Register map (8 registers mirrored through $2000-$3FFF):
/// - $2000: PPUCTRL (write-only control flags)
/// - $2001: PPUMASK (write-only rendering flags)
/// - $2002: PPUSTATUS (read-only status flags)
/// - $2003: OAMADDR (write-only OAM address)
/// - $2004: OAMDATA (read/write OAM data)
/// - $2005: PPUSCROLL (write-only scroll position)
/// - $2006: PPUADDR (write-only VRAM address)
/// - $2007: PPUDATA (read/write VRAM data)
///
/// Critical timing behaviors:
/// 1. VBlank race detection (reading $2002 during scanline 241, dot 0-2)
/// 2. NMI line management (PPUCTRL bit 7 + VBlank state)
/// 3. $2002 read always clears VBlank flag and NMI line
///
/// Pattern: Completely stateless - accesses ppu/vblank/cpu/clock via state parameter
pub const PpuHandler = struct {
    // NO fields - completely stateless!
    // Accesses state.ppu (including vblank), state.cpu, state.clock through parameter

    /// Read from PPU register
    ///
    /// Most registers are write-only and return open bus.
    /// $2002 (PPUSTATUS), $2004 (OAMDATA), $2007 (PPUDATA) can be read.
    ///
    /// CRITICAL: $2002 read has complex side effects:
    /// 1. VBlank race detection (scanline 241, dot 0-2)
    /// 2. Always clears VBlank flag
    /// 3. Always clears NMI line
    /// 4. Resets write toggle
    ///
    /// Parameters:
    /// - self: Handler instance (unused - no internal state)
    /// - state: Emulation state containing ppu (with vblank), cpu, clock, cart
    /// - address: Memory address ($2000-$3FFF)
    ///
    /// Returns: Register value or open bus
    pub fn read(_: *const PpuHandler, state: anytype, address: u16) u8 {
        const reg = address & 0x07;
        const cart_ptr = if (state.cart) |*cart_ref| cart_ref else null;

        // VBlank race detection (CRITICAL TIMING)
        // If reading $2002 during race window, prevent VBlank flag from being set
        if (reg == 0x02) {
            const scanline = state.ppu.scanline;
            const dot = state.ppu.cycle;

            // Prevention window: scanline 241, dot 0 ONLY
            // Hardware Citation: nesdev.org/wiki/PPU_frame_timing
            // Mesen2 Reference: NesPpu.cpp:590-592 (prevention set ONLY at cycle 0)
            // Note: CPU reads only happen on CPU ticks, so isCpuTick() check is redundant
            if (scanline == 241 and dot == 0) {
                // Prevent VBlank set this frame
                state.ppu.vblank.prevent_vbl_set_cycle = state.clock.master_cycles + 1;
            }
        }

        // Delegate to PPU logic for register read
        const result = PpuLogic.readRegister(
            &state.ppu,
            cart_ptr,
            address,
            state.ppu.vblank,
            state.ppu.scanline,
            state.ppu.cycle,
        );

        // $2002 read side effects (CRITICAL)
        if (result.read_2002) {
            // ALWAYS record timestamp (hardware behavior)
            // Per Mesen2: UpdateStatusFlag() clears flag unconditionally
            state.ppu.vblank.last_read_cycle = state.clock.master_cycles;

            // ALWAYS clear VBlank flag (hardware behavior)
            // Per Mesen2 NesPpu.cpp:587: _statusFlags.VerticalBlank = false
            // Flag can be cleared while span is still active (span ends at pre-render)
            state.ppu.vblank.vblank_flag = false;

            // ALWAYS clear NMI line (like Mesen2)
            // Per Mesen2: Reading PPUSTATUS clears NMI immediately
            state.cpu.nmi_line = false;
        }

        return result.value;
    }

    /// Write to PPU register
    ///
    /// All registers are writable (though some like $2002 ignore writes).
    ///
    /// CRITICAL: $2000 (PPUCTRL) write updates NMI line IMMEDIATELY:
    /// - 0→1 transition while VBlank active: triggers NMI
    /// - 1→0 transition: clears NMI
    ///
    /// Parameters:
    /// - self: Handler instance (unused - no internal state)
    /// - state: Emulation state containing ppu (with vblank), cpu, cart
    /// - address: Memory address ($2000-$3FFF)
    /// - value: Byte to write
    pub fn write(_: *PpuHandler, state: anytype, address: u16, value: u8) void {
        const reg = address & 0x07;
        const cart_ptr = if (state.cart) |*cart_ref| cart_ref else null;

        // Delegate to PPU logic for register write
        PpuLogic.writeRegister(&state.ppu, cart_ptr, address, value);

        // CRITICAL: Recompute NMI line IMMEDIATELY on PPUCTRL write
        // Reference: Mesen2 NesPpu.cpp:546-550
        // Hardware: NMI line = vblank_flag AND ctrl.nmi_enable (level signal)
        // CPU edge detection handles 0→1 transitions to latch NMI
        if (reg == 0x00) {
            // Level signal: PPU outputs nmi_line = (vblank_flag AND ctrl.nmi_enable)
            // CPU latches edges - disabling NMI does NOT suppress already-latched NMI
            state.ppu.nmi_line = state.ppu.vblank.isFlagSet() and state.ppu.ctrl.nmi_enable;
        }
    }

    /// Peek PPU register (debugger support)
    ///
    /// Returns register value WITHOUT side effects.
    /// No VBlank clear, no NMI line changes, no race detection.
    ///
    /// Parameters:
    /// - self: Handler instance (unused)
    /// - state: Emulation state containing ppu
    /// - address: Memory address ($2000-$3FFF)
    ///
    /// Returns: Register value or open bus
    pub fn peek(_: *const PpuHandler, state: anytype, address: u16) u8 {
        const reg = address & 0x07;

        // Only PPUSTATUS ($2002) is readable without side effects
        if (reg == 0x02) {
            // Import buildStatusByte from PpuLogic
            const registers = @import("../../../ppu/logic/registers.zig");
            const vblank_flag = state.ppu.vblank.isFlagSet();
            return registers.buildStatusByte(
                state.ppu.status.sprite_overflow,
                state.ppu.status.sprite_0_hit,
                vblank_flag,
                state.bus.open_bus.get(),
            );
        }

        // Other registers are write-only - return open bus
        return state.bus.open_bus.get();
    }
};

// ============================================================================
// Unit Tests
// ============================================================================

const testing = std.testing;
const CpuOpenBus = @import("../../state/BusState.zig").BusState.OpenBus;
const PpuState = @import("../../../ppu/State.zig").PpuState;
const PpuStatus = @import("../../../ppu/State.zig").PpuStatus;
const AnyCartridge = @import("../../../cartridge/mappers/registry.zig").AnyCartridge;

// Test state with real PPU (handlers call real PpuLogic functions)
// PPU now owns VBlank state via ppu.vblank field
const TestState = struct {
    bus: struct {
        open_bus: CpuOpenBus = .{},
    } = .{},
    ppu: PpuState = .{},
    cpu: struct {
        nmi_line: bool = false,
    } = .{},
    clock: struct {
        master_cycles: u64 = 0,

        pub fn isCpuTick(self: *const @This()) bool {
            _ = self;
            return true; // Default: always CPU tick for testing
        }
    } = .{},
    cart: ?AnyCartridge = null,
};

test "PpuHandler: read $2002 returns status byte" {
    var state = TestState{};
    var handler = PpuHandler{};

    // Just verify read works and returns a byte
    const value = handler.read(&state, 0x2002);
    _ = value; // Actual value depends on PPU state
}

test "PpuHandler: read $2002 clears NMI line" {
    var state = TestState{};
    state.cpu.nmi_line = true;

    var handler = PpuHandler{};
    _ = handler.read(&state, 0x2002);

    // Verify NMI line was cleared
    try testing.expect(!state.cpu.nmi_line);
}

test "PpuHandler: read $2002 records timestamp" {
    var state = TestState{};
    state.clock.master_cycles = 12345;

    var handler = PpuHandler{};
    _ = handler.read(&state, 0x2002);

    // Verify timestamp was recorded
    try testing.expectEqual(@as(u64, 12345), state.ppu.vblank.last_read_cycle);
}

test "PpuHandler: read $2002 at dot 0 sets prevention" {
    var state = TestState{};
    state.ppu.scanline = 241;
    state.ppu.cycle = 0; // ONLY dot 0 prevents (per nesdev.org)
    state.clock.master_cycles = 54321;

    var handler = PpuHandler{};
    _ = handler.read(&state, 0x2002);

    // Should set prevention timestamp at dot 0 only
    // Hardware: "Reading one PPU clock before reads it as clear and never sets the flag"
    try testing.expectEqual(@as(u64, 54322), state.ppu.vblank.prevent_vbl_set_cycle);
}

test "PpuHandler: write $2000 enables NMI when VBlank active" {
    var state = TestState{};
    // Set VBlank flag
    state.ppu.vblank.vblank_flag = true;

    var handler = PpuHandler{};
    handler.write(&state, 0x2000, 0x80); // Enable NMI

    // NMI should be triggered if VBlank flag is set
    try testing.expect(state.cpu.nmi_line);
}

test "PpuHandler: write $2000 updates PPU control register" {
    var state = TestState{};
    state.ppu.warmup_complete = true; // Required for PPUCTRL writes to take effect
    var handler = PpuHandler{};

    // Write to PPUCTRL
    handler.write(&state, 0x2000, 0x80);

    // Verify write was routed to PpuLogic (NMI enable set)
    try testing.expect(state.ppu.ctrl.nmi_enable);
}

test "PpuHandler: peek doesn't have side effects" {
    var state = TestState{};
    // Set up VBlank flag
    state.ppu.vblank.vblank_flag = true;

    state.cpu.nmi_line = true;
    const original_timestamp = state.ppu.vblank.last_read_cycle;

    var handler = PpuHandler{};
    const value = handler.peek(&state, 0x2002);

    // Should return value with VBlank bit set (0x80)
    try testing.expectEqual(@as(u8, 0x80), value);

    // Should NOT clear NMI
    try testing.expect(state.cpu.nmi_line);

    // Should NOT update timestamp
    try testing.expectEqual(original_timestamp, state.ppu.vblank.last_read_cycle);
}

test "PpuHandler: register mirroring" {
    var state = TestState{};
    // Set up sprite flags (bits 5-6 of PPUSTATUS)
    state.ppu.status.sprite_overflow = true;  // Bit 5
    state.ppu.status.sprite_0_hit = false;    // Bit 6
    // VBlank bit (7) comes from ledger - don't set it
    // Expected: 0x20 (sprite_overflow=1, others=0)

    var handler = PpuHandler{};

    // $2002, $200A, $2012, etc. all read same register
    // All should return same value (0x20 = sprite overflow bit)
    const expected = @as(u8, 0x20);
    try testing.expectEqual(expected, handler.read(&state, 0x2002));
    try testing.expectEqual(expected, handler.read(&state, 0x200A));
    try testing.expectEqual(expected, handler.read(&state, 0x3FFA)); // Mirror
}

test "PpuHandler: no internal state - handler is empty" {
    // Verify handler has no fields (completely stateless)
    try testing.expectEqual(@as(usize, 0), @sizeOf(PpuHandler));
}
