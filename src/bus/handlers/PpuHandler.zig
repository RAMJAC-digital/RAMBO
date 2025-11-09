// PpuHandler.zig
//
// Routes CPU memory accesses ($2000-$3FFF) to PPU subsystem.
// Pure delegation - all PPU hardware behavior implemented in ppu/logic/registers.zig.
//
// Complexity: ⭐ (1/5) - Pure routing, stateless handler
//
// Hardware Reference:
// - nesdev.org/wiki/PPU_registers

const std = @import("std");
const PpuLogic = @import("../../ppu/Logic.zig");
const PpuReadResult = PpuLogic.PpuReadResult;

/// Handler for $2000-$3FFF (PPU registers)
///
/// Pure routing handler - delegates all register operations to ppu/logic/registers.zig.
/// All hardware-accurate side effects (VBlank race detection, NMI line updates, etc.)
/// are implemented in the PPU subsystem.
///
/// Register map (8 registers mirrored through $2000-$3FFF):
/// - $2000: PPUCTRL - $2001: PPUMASK - $2002: PPUSTATUS
/// - $2003: OAMADDR - $2004: OAMDATA
/// - $2005: PPUSCROLL - $2006: PPUADDR - $2007: PPUDATA
///
/// Pattern: Zero-size stateless handler (follows black box architecture)
pub const PpuHandler = struct {
    // NO fields - completely stateless!

    /// Read from PPU register
    ///
    /// Pure routing - delegates to PpuLogic for all register behavior and side effects.
    /// Hardware-accurate side effects ($2002 VBlank clear, NMI line clear, etc.) are
    /// handled internally by PpuLogic.
    ///
    /// Parameters:
    /// - self: Handler instance (unused - no internal state)
    /// - state: Emulation state containing ppu, cart, clock
    /// - address: Memory address ($2000-$3FFF)
    ///
    /// Returns: Register value or open bus
    pub fn read(_: *const PpuHandler, state: anytype, address: u16) u8 {
        const cart_ptr = if (state.cart) |*cart_ref| cart_ref else null;

        // Delegate to PPU logic - PPU handles ALL side effects internally
        const result = PpuLogic.readRegister(
            &state.ppu,
            cart_ptr,
            address,
            state.clock.master_cycles,
        );

        return result.value;
    }

    /// Write to PPU register
    ///
    /// Pure routing - delegates to PpuLogic for all register behavior and side effects.
    /// Hardware-accurate side effects ($2000 NMI line updates, etc.) are handled
    /// internally by PpuLogic.
    ///
    /// Parameters:
    /// - self: Handler instance (unused - no internal state)
    /// - state: Emulation state containing ppu, cart
    /// - address: Memory address ($2000-$3FFF)
    /// - value: Byte to write
    pub fn write(_: *PpuHandler, state: anytype, address: u16, value: u8) void {
        const cart_ptr = if (state.cart) |*cart_ref| cart_ref else null;

        // Delegate to PPU logic - PPU handles ALL side effects internally
        PpuLogic.writeRegister(&state.ppu, cart_ptr, address, value);
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
            const registers = @import("../../ppu/logic/registers.zig");
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
const CpuOpenBus = @import("../State.zig").State.OpenBus;
const PpuState = @import("../../ppu/State.zig").PpuState;
const PpuStatus = @import("../../ppu/State.zig").PpuStatus;
const AnyCartridge = @import("../../cartridge/mappers/registry.zig").AnyCartridge;

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
    state.ppu.nmi_line = true; // PPU owns NMI output signal

    var handler = PpuHandler{};
    _ = handler.read(&state, 0x2002);

    // Verify PPU NMI line was cleared (handler doesn't touch cpu.nmi_line)
    try testing.expect(!state.ppu.nmi_line);
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
    state.ppu.dot = 0; // ONLY dot 0 prevents (per nesdev.org)
    state.clock.master_cycles = 54321;

    var handler = PpuHandler{};
    _ = handler.read(&state, 0x2002);

    // Should set prevention timestamp at dot 0 only
    // Hardware: "Reading one PPU clock before reads it as clear and never sets the flag"
    try testing.expectEqual(@as(u64, 54322), state.ppu.vblank.prevent_vbl_set_cycle);
}

test "PpuHandler: write $2000 enables NMI when VBlank active" {
    var state = TestState{};
    state.ppu.warmup_complete = true; // Required for PPUCTRL writes
    state.ppu.vblank.vblank_flag = true; // VBlank active

    var handler = PpuHandler{};
    handler.write(&state, 0x2000, 0x80); // Enable NMI

    // PPU should compute nmi_line = vblank_flag AND ctrl.nmi_enable = true
    try testing.expect(state.ppu.nmi_line);
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
    state.ppu.vblank.vblank_flag = true; // VBlank active
    state.ppu.nmi_line = true; // NMI asserted

    const original_timestamp = state.ppu.vblank.last_read_cycle;

    var handler = PpuHandler{};
    const value = handler.peek(&state, 0x2002);

    // Should return value with VBlank bit set (0x80)
    try testing.expectEqual(@as(u8, 0x80), value);

    // Should NOT clear PPU NMI line
    try testing.expect(state.ppu.nmi_line);

    // Should NOT update timestamp
    try testing.expectEqual(original_timestamp, state.ppu.vblank.last_read_cycle);
}

test "PpuHandler: register mirroring" {
    var state = TestState{};
    // Set up sprite flags (bits 5-6 of PPUSTATUS)
    state.ppu.status.sprite_overflow = true; // Bit 5
    state.ppu.status.sprite_0_hit = false; // Bit 6
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
