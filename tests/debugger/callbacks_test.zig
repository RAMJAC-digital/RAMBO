//! Debugger Callback System Tests
//!
//! Tests verify user-defined callbacks work correctly while maintaining:
//! - Isolation (callbacks receive const state)
//! - RT-safety (no heap allocations in callback path)
//! - Const-correctness (compile-time enforcement)
//! - Multiple callback support
//! - Proper registration/unregistration

const std = @import("std");
const testing = std.testing;
const RAMBO = @import("RAMBO");

const Debugger = RAMBO.Debugger.Debugger;
const DebugMode = RAMBO.Debugger.DebugMode;

const EmulationState = RAMBO.EmulationState.EmulationState;
const Config = RAMBO.Config.Config;

const test_fixtures = @import("test_fixtures.zig");

// ============================================================================
// Callback System Tests
// ============================================================================
// These tests verify user-defined callbacks work correctly and maintain
// isolation, RT-safety, and const-correctness guarantees.

const TestCallback = struct {
    break_count: u32 = 0,
    last_pc: u16 = 0,
    last_address: u16 = 0,

    fn onBeforeInstruction(userdata: *anyopaque, state: *const EmulationState) bool {
        const self: *TestCallback = @ptrCast(@alignCast(userdata));
        self.last_pc = state.cpu.pc;
        self.break_count += 1;
        return state.cpu.pc == 0x8100; // Break at specific PC
    }

    fn onMemoryAccess(userdata: *anyopaque, address: u16, value: u8, is_write: bool) bool {
        const self: *TestCallback = @ptrCast(@alignCast(userdata));
        self.last_address = address;
        _ = value;
        _ = is_write;
        return address == 0x2000; // Break on PPU access
    }
};

test "Callback: onBeforeInstruction called and can break" {
    var config = Config.init(testing.allocator);
    defer config.deinit();

    var debugger = Debugger.init(testing.allocator, &config);
    defer debugger.deinit();

    var state = test_fixtures.createTestState(&config);

    var callback = TestCallback{};
    try debugger.registerCallback(.{
        .onBeforeInstruction = TestCallback.onBeforeInstruction,
        .userdata = &callback,
    });

    // Callback should NOT break at 0x8000
    state.cpu.pc = 0x8000;
    const should_break1 = try debugger.shouldBreak(&state);
    try testing.expect(!should_break1);
    try testing.expectEqual(@as(u32, 1), callback.break_count);
    try testing.expectEqual(@as(u16, 0x8000), callback.last_pc);

    // Callback SHOULD break at 0x8100
    state.cpu.pc = 0x8100;
    const should_break2 = try debugger.shouldBreak(&state);
    try testing.expect(should_break2);
    try testing.expectEqual(@as(u32, 2), callback.break_count);
    try testing.expectEqual(@as(u16, 0x8100), callback.last_pc);

    // Verify break reason
    const reason = debugger.getBreakReason();
    try testing.expect(reason != null);
    try testing.expect(std.mem.eql(u8, reason.?, "User callback break"));
}

test "Callback: onMemoryAccess called and can break" {
    var config = Config.init(testing.allocator);
    defer config.deinit();

    var debugger = Debugger.init(testing.allocator, &config);
    defer debugger.deinit();

    const state = test_fixtures.createTestState(&config);

    var callback = TestCallback{};
    try debugger.registerCallback(.{
        .onMemoryAccess = TestCallback.onMemoryAccess,
        .userdata = &callback,
    });

    // Callback should NOT break at 0x0200
    const should_break1 = try debugger.checkMemoryAccess(&state, 0x0200, 0x42, false);
    try testing.expect(!should_break1);
    try testing.expectEqual(@as(u16, 0x0200), callback.last_address);

    // Callback SHOULD break at 0x2000 (PPU)
    const should_break2 = try debugger.checkMemoryAccess(&state, 0x2000, 0x80, true);
    try testing.expect(should_break2);
    try testing.expectEqual(@as(u16, 0x2000), callback.last_address);

    // Verify break reason contains "Memory callback"
    const reason = debugger.getBreakReason();
    try testing.expect(reason != null);
    try testing.expect(std.mem.indexOf(u8, reason.?, "Memory callback") != null);
}

test "Callback: Multiple callbacks supported" {
    var config = Config.init(testing.allocator);
    defer config.deinit();

    var debugger = Debugger.init(testing.allocator, &config);
    defer debugger.deinit();

    var state = test_fixtures.createTestState(&config);

    var callback1 = TestCallback{};
    var callback2 = TestCallback{};

    // Register two callbacks
    try debugger.registerCallback(.{
        .onBeforeInstruction = TestCallback.onBeforeInstruction,
        .userdata = &callback1,
    });
    try debugger.registerCallback(.{
        .onBeforeInstruction = TestCallback.onBeforeInstruction,
        .userdata = &callback2,
    });

    // Both callbacks should be called
    state.cpu.pc = 0x8000;
    _ = try debugger.shouldBreak(&state);

    try testing.expectEqual(@as(u32, 1), callback1.break_count);
    try testing.expectEqual(@as(u32, 1), callback2.break_count);
    try testing.expectEqual(@as(u16, 0x8000), callback1.last_pc);
    try testing.expectEqual(@as(u16, 0x8000), callback2.last_pc);
}

test "Callback: Unregister works correctly" {
    var config = Config.init(testing.allocator);
    defer config.deinit();

    var debugger = Debugger.init(testing.allocator, &config);
    defer debugger.deinit();

    var state = test_fixtures.createTestState(&config);

    var callback = TestCallback{};
    try debugger.registerCallback(.{
        .onBeforeInstruction = TestCallback.onBeforeInstruction,
        .userdata = &callback,
    });

    // Callback is registered
    state.cpu.pc = 0x8000;
    _ = try debugger.shouldBreak(&state);
    try testing.expectEqual(@as(u32, 1), callback.break_count);

    // Unregister callback
    const removed = debugger.unregisterCallback(&callback);
    try testing.expect(removed);

    // Callback should NOT be called anymore
    state.cpu.pc = 0x8000;
    _ = try debugger.shouldBreak(&state);
    try testing.expectEqual(@as(u32, 1), callback.break_count); // Still 1, not incremented
}

test "Callback: Clear all callbacks" {
    var config = Config.init(testing.allocator);
    defer config.deinit();

    var debugger = Debugger.init(testing.allocator, &config);
    defer debugger.deinit();

    var state = test_fixtures.createTestState(&config);

    var callback1 = TestCallback{};
    var callback2 = TestCallback{};

    try debugger.registerCallback(.{
        .onBeforeInstruction = TestCallback.onBeforeInstruction,
        .userdata = &callback1,
    });
    try debugger.registerCallback(.{
        .onBeforeInstruction = TestCallback.onBeforeInstruction,
        .userdata = &callback2,
    });

    // Clear all callbacks
    debugger.clearCallbacks();

    // No callbacks should be called
    state.cpu.pc = 0x8000;
    _ = try debugger.shouldBreak(&state);

    try testing.expectEqual(@as(u32, 0), callback1.break_count);
    try testing.expectEqual(@as(u32, 0), callback2.break_count);
}

test "Callback: RT-safety - no heap allocations in callback path" {
    var config = Config.init(testing.allocator);
    defer config.deinit();

    var debugger = Debugger.init(testing.allocator, &config);
    defer debugger.deinit();

    var state = test_fixtures.createTestState(&config);

    var callback = TestCallback{};
    try debugger.registerCallback(.{
        .onBeforeInstruction = TestCallback.onBeforeInstruction,
        .userdata = &callback,
    });

    // Capture allocation count
    const allocations_before = testing.allocator_instance.total_requested_bytes;

    // Call shouldBreak (which calls callback)
    state.cpu.pc = 0x8000;
    _ = try debugger.shouldBreak(&state);

    const allocations_after = testing.allocator_instance.total_requested_bytes;

    // ✅ Verify zero heap allocations in callback path
    try testing.expectEqual(allocations_before, allocations_after);
}

test "Callback: Const state enforcement - callback receives read-only state" {
    // This is a compile-time test - if it compiles, const is enforced
    // The callback signature requires *const EmulationState

    var config = Config.init(testing.allocator);
    defer config.deinit();

    var debugger = Debugger.init(testing.allocator, &config);
    defer debugger.deinit();

    var state = test_fixtures.createTestState(&config);

    const ReadOnlyCallback = struct {
        fn onBefore(userdata: *anyopaque, const_state: *const EmulationState) bool {
            _ = userdata;
            // ✅ Can read state
            _ = const_state.cpu.pc;
            _ = const_state.cpu.a;

            // ❌ Cannot write state (would be compile error)
            // const_state.cpu.pc = 0x9000;  // Compile error: const_state is const

            return false;
        }
    };

    var callback_data: u32 = 0;
    try debugger.registerCallback(.{
        .onBeforeInstruction = ReadOnlyCallback.onBefore,
        .userdata = &callback_data,
    });

    // If this compiles, const enforcement works
    _ = try debugger.shouldBreak(&state);
}
