//! Integration test for loading AccuracyCoin.nes
//!
//! This test verifies that we can successfully load the AccuracyCoin ROM,
//! parse its iNES header, and access its PRG/CHR ROM through the cartridge interface.

const std = @import("std");
const testing = std.testing;
const RAMBO = @import("RAMBO");

const Cartridge = RAMBO.CartridgeType;
const EmulationState = RAMBO.EmulationState.EmulationState;
const Config = RAMBO.Config;

const TestHarness = struct {
    config: *Config.Config,
    state: EmulationState,

    pub fn init() !TestHarness {
        const cfg = try testing.allocator.create(Config.Config);
        cfg.* = Config.Config.init(testing.allocator);

        var emu_state = EmulationState.init(cfg);
        emu_state.reset();

        return .{
            .config = cfg,
            .state = emu_state,
        };
    }

    pub fn deinit(self: *TestHarness) void {
        self.config.deinit();
        testing.allocator.destroy(self.config);
    }

    pub fn statePtr(self: *TestHarness) *EmulationState {
        return &self.state;
    }
};

test "Load AccuracyCoin.nes" {
    const accuracycoin_path = "AccuracyCoin/AccuracyCoin.nes";

    // Load cartridge from file
    var cart = Cartridge.load(testing.allocator, accuracycoin_path) catch |err| {
        // If file doesn't exist, skip test (not an error)
        if (err == error.FileNotFound) {
            std.debug.print("Skipping AccuracyCoin test - file not found at: {s}\n", .{accuracycoin_path});
            return error.SkipZigTest;
        }
        return err;
    };
    defer cart.deinit();

    // Verify header parsing
    try testing.expectEqual(@as(u8, 0), cart.header.getMapperNumber());
    try testing.expectEqual(@as(usize, 32768), cart.header.getPrgRomSize()); // 32KB PRG ROM
    try testing.expectEqual(@as(usize, 8192), cart.header.getChrRomSize()); // 8KB CHR ROM
    try testing.expect(!cart.header.hasBatteryRam());
    try testing.expect(!cart.header.hasTrainer());

    // Verify mirroring
    try testing.expectEqual(RAMBO.MirroringType.horizontal, cart.mirroring);

    // Verify ROM data loaded
    try testing.expectEqual(@as(usize, 32768), cart.prg_rom.len);
    try testing.expectEqual(@as(usize, 8192), cart.chr_data.len);

    // Verify we can read from PRG ROM through cartridge interface
    // Should be able to read from $8000-$FFFF
    const value_8000 = cart.cpuRead(0x8000);
    const value_ffff = cart.cpuRead(0xFFFF);

    // Values should be non-zero (actual ROM data, not uninitialized)
    // We don't check specific values as they may change with ROM updates
    _ = value_8000;
    _ = value_ffff;

    // Verify we can read from CHR ROM
    const chr_value = cart.ppuRead(0x0000);
    _ = chr_value;

    std.debug.print("AccuracyCoin.nes loaded successfully:\n", .{});
    std.debug.print("  Mapper: {d}\n", .{cart.header.getMapperNumber()});
    std.debug.print("  PRG ROM: {d} KB\n", .{cart.prg_rom.len / 1024});
    std.debug.print("  CHR ROM: {d} KB\n", .{cart.chr_data.len / 1024});
    std.debug.print("  Mirroring: {s}\n", .{@tagName(cart.mirroring)});
}

test "Load AccuracyCoin.nes through Bus" {
    const accuracycoin_path = "AccuracyCoin/AccuracyCoin.nes";

    var cart = Cartridge.load(testing.allocator, accuracycoin_path) catch |err| {
        if (err == error.FileNotFound) {
            std.debug.print("Skipping Bus integration test - file not found\n", .{});
            return error.SkipZigTest;
        }
        return err;
    };
    var harness = try TestHarness.init();
    defer harness.deinit();
    const state = harness.statePtr();

    defer {
        state.cart = null;
        cart.deinit();
    }

    state.loadCartridge(cart);

    // Verify we can read from ROM through emulator bus
    const value = state.busRead(0x8000);
    _ = value;

    // Read reset vector (should point to ROM)
    const reset_low = state.busRead(0xFFFC);
    const reset_high = state.busRead(0xFFFD);
    const reset_vector = (@as(u16, reset_high) << 8) | @as(u16, reset_low);

    std.debug.print("  Reset vector: ${X:0>4}\n", .{reset_vector});

    // Reset vector should be in ROM space ($8000-$FFFF)
    try testing.expect(reset_vector >= 0x8000);
    try testing.expect(reset_vector <= 0xFFFF);
}
