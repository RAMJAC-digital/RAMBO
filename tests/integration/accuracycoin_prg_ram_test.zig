const std = @import("std");
const testing = std.testing;
const RAMBO = @import("RAMBO");
const Cartridge = RAMBO.CartridgeType;

// ============================================================================
// AccuracyCoin PRG RAM Integration Tests
// ============================================================================
//
// Tests PRG RAM functionality with the actual AccuracyCoin.nes ROM.
// AccuracyCoin writes test results to PRG RAM for extraction.

// ============================================================================
// Test 1: AccuracyCoin ROM Has PRG RAM
// ============================================================================

test "AccuracyCoin: Cartridge has 8KB PRG RAM" {
    const accuracycoin_path = "AccuracyCoin/AccuracyCoin.nes";

    // Load cartridge from file
    var cart = Cartridge.load(testing.allocator, accuracycoin_path) catch |err| {
        if (err == error.FileNotFound) {
            return error.SkipZigTest;
        }
        return err;
    };
    defer cart.deinit();

    // Verify cartridge has PRG RAM allocated
    try testing.expect(cart.prg_ram != null);
    try testing.expectEqual(@as(usize, 8192), cart.prg_ram.?.len);
}

// ============================================================================
// Test 2: PRG RAM Read/Write via Cartridge
// ============================================================================

test "AccuracyCoin: PRG RAM read/write" {
    const accuracycoin_path = "AccuracyCoin/AccuracyCoin.nes";

    var cart = Cartridge.load(testing.allocator, accuracycoin_path) catch |err| {
        if (err == error.FileNotFound) {
            return error.SkipZigTest;
        }
        return err;
    };
    defer cart.deinit();

    // Write to PRG RAM via cartridge
    cart.cpuWrite(0x6000, 0xAA);
    cart.cpuWrite(0x7FFF, 0xBB);

    // Read back
    try testing.expectEqual(@as(u8, 0xAA), cart.cpuRead(0x6000));
    try testing.expectEqual(@as(u8, 0xBB), cart.cpuRead(0x7FFF));
}

// ============================================================================
// Test 3: PRG RAM Zero-Initialized
// ============================================================================

test "AccuracyCoin: PRG RAM starts zero" {
    const accuracycoin_path = "AccuracyCoin/AccuracyCoin.nes";

    var cart = Cartridge.load(testing.allocator, accuracycoin_path) catch |err| {
        if (err == error.FileNotFound) {
            return error.SkipZigTest;
        }
        return err;
    };
    defer cart.deinit();

    // All PRG RAM should be zero
    const ram = cart.prg_ram.?;
    for (ram) |byte| {
        try testing.expectEqual(@as(u8, 0), byte);
    }
}
