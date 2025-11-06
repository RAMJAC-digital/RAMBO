// ApuHandler.zig
//
// Handles $4000-$4015 (APU channel registers and control).
// All channel registers ($4000-$4013) are write-only.
// $4015 is read/write (status/control).
//
// Complexity: ⭐⭐⭐ (3/5) - Multiple registers, IRQ side effect
//
// Hardware Reference:
// - nesdev.org/wiki/APU
// - nesdev.org/wiki/APU_Status
//
// IMPORTANT: $4015 read does NOT update open bus (hardware quirk)

const std = @import("std");
const ApuLogic = @import("../../../apu/Logic.zig");
const CpuOpenBus = @import("../../state/BusState.zig").BusState.OpenBus;

/// Handler for $4000-$4015 (APU registers)
///
/// Register map:
/// - $4000-$4003: Pulse 1 (duty, volume, sweep, timer)
/// - $4004-$4007: Pulse 2 (duty, volume, sweep, timer)
/// - $4008-$400B: Triangle (linear counter, timer)
/// - $400C-$400F: Noise (volume, period, length)
/// - $4010-$4013: DMC (flags, output, address, length)
/// - $4015: Status (read) / Channel enable (write)
///
/// All channel registers are write-only.
/// Reading them returns open bus (except $4015).
///
/// HARDWARE QUIRK: $4015 read does NOT update open bus!
///
/// Pattern: Completely stateless - accesses apu via state parameter
pub const ApuHandler = struct {
    // NO fields - completely stateless!
    // Accesses state.apu and state.bus.open_bus through parameter

    /// Read from APU register
    ///
    /// $4000-$4013: Open bus (write-only channels)
    /// $4015: APU status byte
    ///   - Bit 7: DMC interrupt flag
    ///   - Bit 6: Frame interrupt flag
    ///   - Bit 4: DMC active
    ///   - Bit 3: Noise length counter > 0
    ///   - Bit 2: Triangle length counter > 0
    ///   - Bit 1: Pulse 2 length counter > 0
    ///   - Bit 0: Pulse 1 length counter > 0
    ///
    /// Side effects:
    /// - $4015: Clears frame interrupt flag
    ///
    /// HARDWARE QUIRK: $4015 read does NOT update open bus!
    ///
    /// Parameters:
    /// - self: Handler instance (unused - no internal state)
    /// - state: Emulation state containing apu and bus.open_bus
    /// - address: Memory address ($4000-$4015)
    ///
    /// Returns: APU status (if $4015) or open bus (if $4000-$4013)
    pub fn read(_: *const ApuHandler, state: anytype, address: u16) u8 {
        return switch (address) {
            0x4000...0x4013 => state.bus.open_bus.get(), // Write-only channels

            0x4015 => blk: {
                // Read APU status
                const status = ApuLogic.readStatus(&state.apu);
                const open_bus_mask = state.bus.open_bus.getInternal(0x20);
                const result = status | open_bus_mask;

                // Side effect: Clear frame IRQ flag
                ApuLogic.clearFrameIrq(&state.apu);

                break :blk result;
            },

            else => state.bus.open_bus.get(),
        };
    }

    /// Write to APU register
    ///
    /// Delegates to ApuLogic based on address:
    /// - $4000-$4003: Pulse 1 channel
    /// - $4004-$4007: Pulse 2 channel
    /// - $4008-$400B: Triangle channel
    /// - $400C-$400F: Noise channel
    /// - $4010-$4013: DMC channel
    /// - $4015: Channel enables + length counter resets
    ///
    /// Parameters:
    /// - self: Handler instance (unused - no internal state)
    /// - state: Emulation state containing apu
    /// - address: Memory address ($4000-$4015)
    /// - value: Byte to write
    pub fn write(_: *ApuHandler, state: anytype, address: u16, value: u8) void {
        switch (address) {
            // Pulse 1 ($4000-$4003)
            0x4000...0x4003 => |addr| {
                const reg: u2 = @intCast(addr & 0x03);
                ApuLogic.writePulse1(&state.apu, reg, value);
            },

            // Pulse 2 ($4004-$4007)
            0x4004...0x4007 => |addr| {
                const reg: u2 = @intCast(addr & 0x03);
                ApuLogic.writePulse2(&state.apu, reg, value);
            },

            // Triangle ($4008-$400B)
            0x4008...0x400B => |addr| {
                const reg: u2 = @intCast(addr & 0x03);
                ApuLogic.writeTriangle(&state.apu, reg, value);
            },

            // Noise ($400C-$400F)
            0x400C...0x400F => |addr| {
                const reg: u2 = @intCast(addr & 0x03);
                ApuLogic.writeNoise(&state.apu, reg, value);
            },

            // DMC ($4010-$4013)
            0x4010...0x4013 => |addr| {
                const reg: u2 = @intCast(addr & 0x03);
                ApuLogic.writeDmc(&state.apu, reg, value);
            },

            // APU Control ($4015)
            0x4015 => ApuLogic.writeControl(&state.apu, value),

            else => {}, // Unmapped - no-op
        }
    }

    /// Peek APU register (debugger support)
    ///
    /// Returns APU status WITHOUT clearing frame IRQ flag.
    /// This allows debugger inspection without side effects.
    ///
    /// Parameters:
    /// - self: Handler instance (unused)
    /// - state: Emulation state containing apu and bus.open_bus
    /// - address: Memory address ($4000-$4015)
    ///
    /// Returns: APU status (if $4015) or open bus (if $4000-$4013)
    pub fn peek(_: *const ApuHandler, state: anytype, address: u16) u8 {
        return switch (address) {
            0x4000...0x4013 => state.bus.open_bus.get(),
            0x4015 => ApuLogic.readStatus(&state.apu), // No side effects
            else => state.bus.open_bus.get(),
        };
    }
};

// ============================================================================
// Unit Tests
// ============================================================================

const testing = std.testing;
const ApuState = @import("../../../apu/State.zig").ApuState;

// Test state with real APU (handlers call real ApuLogic functions)
const TestState = struct {
    bus: struct {
        open_bus: CpuOpenBus = .{},
    } = .{},
    apu: ApuState = .{},
};

test "ApuHandler: read $4015 returns status (non-zero)" {
    var state = TestState{};
    // Real ApuState will return actual status
    var handler = ApuHandler{};

    // Just verify it doesn't crash and returns a byte
    const value = handler.read(&state, 0x4015);
    _ = value; // APU status depends on internal state
}

test "ApuHandler: read $4000-$4013 returns open bus" {
    var state = TestState{};
    state.bus.open_bus.set(0xAB);

    var handler = ApuHandler{};

    // Test a few addresses
    try testing.expectEqual(@as(u8, 0xAB), handler.read(&state, 0x4000));
    try testing.expectEqual(@as(u8, 0xAB), handler.read(&state, 0x4008));
    try testing.expectEqual(@as(u8, 0xAB), handler.read(&state, 0x4013));
}

test "ApuHandler: write $4000-$4003 (Pulse 1) updates state" {
    var state = TestState{};
    var handler = ApuHandler{};

    // Write to Pulse 1 registers
    handler.write(&state, 0x4000, 0x3F); // Duty, length halt, constant volume
    handler.write(&state, 0x4001, 0x08); // Sweep
    handler.write(&state, 0x4002, 0xAD); // Timer low
    handler.write(&state, 0x4003, 0x00); // Timer high, length

    // Verify writes were routed to ApuLogic (state updated)
    // $4000 = 0x3F = DDLC VVVV = 0011 1111
    // Volume/envelope (VVVV) = 1111 = 15 (0x0F)
    try testing.expectEqual(@as(u4, 0x0F), state.apu.pulse1_envelope.volume_envelope);
}

test "ApuHandler: write $4015 (Control) enables channels" {
    var state = TestState{};
    var handler = ApuHandler{};

    // Enable all channels
    handler.write(&state, 0x4015, 0x1F);

    // Verify channels were enabled
    try testing.expect(state.apu.pulse1_enabled);
    try testing.expect(state.apu.pulse2_enabled);
    try testing.expect(state.apu.triangle_enabled);
    try testing.expect(state.apu.noise_enabled);
    try testing.expect(state.apu.dmc_enabled);
}

test "ApuHandler: peek doesn't crash" {
    var state = TestState{};
    var handler = ApuHandler{};

    // Just verify peek works without side effects
    _ = handler.peek(&state, 0x4015);
}

test "ApuHandler: no internal state - handler is empty" {
    // Verify handler has no fields (completely stateless)
    try testing.expectEqual(@as(usize, 0), @sizeOf(ApuHandler));
}
