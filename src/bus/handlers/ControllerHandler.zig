// ControllerHandler.zig
//
// Handles $4016-$4017 (controller ports and APU frame counter).
// $4016: Controller 1 + strobe control
// $4017: Controller 2 + APU frame counter
//
// Complexity: ⭐⭐ (2/5) - Shift registers + open bus masking
//
// Hardware Reference:
// - nesdev.org/wiki/Standard_controller
// - nesdev.org/wiki/APU_Frame_Counter

const std = @import("std");
const ApuLogic = @import("../../apu/Logic.zig");
const ControllerLogic = @import("../../controller/Logic.zig").Logic;

/// Handler for $4016-$4017 (controller ports)
///
/// $4016 functions:
/// - Read: Controller 1 serial data (bit 0) + open bus (bits 5-7)
/// - Write: Controller strobe control (bit 0)
///
/// $4017 functions:
/// - Read: Controller 2 serial data (bit 0) + open bus (bits 5-7)
/// - Write: APU frame counter mode (bits 6-7)
///
/// Open bus masking: Bits 1-4 are always 0, bits 5-7 come from open bus
///
/// Pattern: Completely stateless - accesses controller/apu via state parameter
pub const ControllerHandler = struct {
    // NO fields - completely stateless!
    // Accesses state.controller, state.apu, state.bus.open_bus through parameter

    /// Read from controller port
    ///
    /// $4016: Controller 1 serial data (bit 0) + open bus (bits 5-7)
    /// $4017: Controller 2 serial data (bit 0) + open bus (bits 5-7)
    ///
    /// Side effects:
    /// - Shifts controller shift register (if strobe is low)
    /// - Bits 0: Controller data
    /// - Bits 1-4: Always 0
    /// - Bits 5-7: Open bus
    ///
    /// Parameters:
    /// - self: Handler instance (unused - no internal state)
    /// - state: Emulation state containing controller and bus
    /// - address: Memory address ($4016 or $4017)
    ///
    /// Returns: Controller bit (0) + open bus bits (5-7)
    pub fn read(_: *const ControllerHandler, state: anytype, address: u16) u8 {
        const reg = address & 0x01; // 0=$4016, 1=$4017

        // Read controller data (bit 0 only)
        const controller_bit = if (reg == 0)
            ControllerLogic.read1(&state.controller)
        else
            ControllerLogic.read2(&state.controller);

        // Combine with open bus bits 5-7
        // Bits 1-4 are always 0 (hardware behavior)
        return controller_bit | (state.bus.open_bus.get() & 0xE0);
    }

    /// Write to controller port
    ///
    /// $4016: Controller strobe (bit 0)
    ///   - 0→1: Latch button state into shift registers
    ///   - 1: Continuously reload shift registers
    ///   - 0: Shift mode (read advances shift register)
    ///
    /// $4017: APU frame counter mode
    ///   - Bit 7: 0=4-step mode, 1=5-step mode
    ///   - Bit 6: IRQ inhibit flag
    ///
    /// Parameters:
    /// - self: Handler instance (unused - no internal state)
    /// - state: Emulation state containing controller and apu
    /// - address: Memory address ($4016 or $4017)
    /// - value: Value to write
    pub fn write(_: *ControllerHandler, state: anytype, address: u16, value: u8) void {
        const reg = address & 0x01;

        if (reg == 0) {
            // $4016: Controller strobe
            ControllerLogic.writeStrobe(&state.controller, value);
        } else {
            // $4017: APU frame counter
            ApuLogic.writeFrameCounter(&state.apu, value);
        }
    }

    /// Peek controller port (debugger support)
    ///
    /// Returns controller data without shifting registers.
    /// This allows debugger inspection without side effects.
    ///
    /// Parameters:
    /// - self: Handler instance (unused)
    /// - state: Emulation state containing controller and bus
    /// - address: Memory address ($4016 or $4017)
    ///
    /// Returns: Controller bit (0) + open bus bits (5-7)
    pub fn peek(_: *const ControllerHandler, state: anytype, address: u16) u8 {
        const reg = address & 0x01;

        // Peek current shift register state WITHOUT shifting
        // (read1/read2 would advance the shift register)
        const controller_bit = if (reg == 0)
            state.controller.shift1 & 0x01
        else
            state.controller.shift2 & 0x01;

        return controller_bit | (state.bus.open_bus.get() & 0xE0);
    }
};

// ============================================================================
// Unit Tests
// ============================================================================

const testing = std.testing;
const CpuOpenBus = @import("../State.zig").State.OpenBus;
const ApuState = @import("../../apu/State.zig").ApuState;
const ControllerState = @import("../../controller/State.zig").ControllerState;

// Test state with minimal controller/bus
const TestState = struct {
    bus: struct {
        open_bus: CpuOpenBus = .{},
    } = .{},
    controller: ControllerState = .{},
    apu: ApuState = .{},
};

test "ControllerHandler: read $4016 returns controller 1 bit" {
    var state = TestState{};
    state.controller.shift1 = 0x01; // Bit 0 set
    var handler = ControllerHandler{};

    const value = handler.read(&state, 0x4016);

    // Should return bit 0 set
    try testing.expectEqual(@as(u8, 0x01), value & 0x01);
}

test "ControllerHandler: read $4017 returns controller 2 bit" {
    var state = TestState{};
    state.controller.shift2 = 0x01; // Bit 0 set
    var handler = ControllerHandler{};

    const value = handler.read(&state, 0x4017);

    // Should return bit 0 set
    try testing.expectEqual(@as(u8, 0x01), value & 0x01);
}

test "ControllerHandler: read combines with open bus bits 5-7" {
    var state = TestState{};
    state.controller.shift1 = 0x01; // Controller bit 0
    state.bus.open_bus.set(0xE0); // Bits 5-7 set
    var handler = ControllerHandler{};

    const value = handler.read(&state, 0x4016);

    // Should return controller bit 0 + open bus bits 5-7
    try testing.expectEqual(@as(u8, 0xE1), value);
}

test "ControllerHandler: read shifts register (strobe low)" {
    var state = TestState{};
    state.controller.shift1 = 0x55; // 01010101
    state.controller.strobe = false;
    var handler = ControllerHandler{};

    // First read
    const value1 = handler.read(&state, 0x4016);
    try testing.expectEqual(@as(u8, 0x01), value1 & 0x01); // Bit 0

    // Second read (should shift)
    const value2 = handler.read(&state, 0x4016);
    try testing.expectEqual(@as(u8, 0x00), value2 & 0x01); // Bit 0 after shift
}

test "ControllerHandler: write $4016 sets strobe" {
    var state = TestState{};
    state.controller.buttons1 = 0xFF;
    var handler = ControllerHandler{};

    // Write strobe high
    handler.write(&state, 0x4016, 0x01);

    try testing.expect(state.controller.strobe);
    try testing.expectEqual(@as(u8, 0xFF), state.controller.shift1);
}

test "ControllerHandler: write $4017 sets frame counter mode" {
    var state = TestState{};
    var handler = ControllerHandler{};

    // Write 5-step mode (bit 7)
    handler.write(&state, 0x4017, 0x80);

    try testing.expect(state.apu.frame_counter_mode);
}

test "ControllerHandler: write $4017 sets IRQ inhibit" {
    var state = TestState{};
    var handler = ControllerHandler{};

    // Write IRQ inhibit (bit 6)
    handler.write(&state, 0x4017, 0x40);

    try testing.expect(state.apu.irq_inhibit);
}

test "ControllerHandler: peek doesn't shift register" {
    var state = TestState{};
    state.controller.shift1 = 0x55;
    state.controller.strobe = false;
    var handler = ControllerHandler{};

    // Peek multiple times
    const value1 = handler.peek(&state, 0x4016);
    const value2 = handler.peek(&state, 0x4016);

    // Should return same value (no shift)
    try testing.expectEqual(value1, value2);
    try testing.expectEqual(@as(u8, 0x55), state.controller.shift1); // Unchanged
}

test "ControllerHandler: peek combines with open bus" {
    var state = TestState{};
    state.controller.shift1 = 0x01;
    state.bus.open_bus.set(0xA0); // Bits 5, 7 set
    var handler = ControllerHandler{};

    const value = handler.peek(&state, 0x4016);

    try testing.expectEqual(@as(u8, 0xA1), value);
}

test "ControllerHandler: no internal state - handler is empty" {
    // Verify handler has no fields (completely stateless)
    try testing.expectEqual(@as(usize, 0), @sizeOf(ControllerHandler));
}
