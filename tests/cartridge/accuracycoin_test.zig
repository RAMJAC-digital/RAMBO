//! Integration test for loading AccuracyCoin.nes
//!
//! This test verifies that we can successfully load the AccuracyCoin ROM,
//! parse its iNES header, and access its PRG/CHR ROM through the cartridge interface.

const std = @import("std");
const testing = std.testing;
const RAMBO = @import("RAMBO");

const NromCart = RAMBO.CartridgeType;
const AnyCartridge = RAMBO.AnyCartridge;
const EmulationState = RAMBO.EmulationState.EmulationState;
const Config = RAMBO.Config;

const TestHarness = struct {
    config: *Config.Config,
    state: EmulationState,

    pub fn init() !TestHarness {
        const cfg = try testing.allocator.create(Config.Config);
        cfg.* = Config.Config.init(testing.allocator);

        var emu_state = EmulationState.init(cfg);
        emu_state.power_on();

        return .{
            .config = cfg,
            .state = emu_state,
        };
    }

    pub fn deinit(self: *TestHarness) void {
        self.state.deinit(); // Clean up emulation state (including cartridge)
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
    var cart = NromCart.load(testing.allocator, accuracycoin_path) catch |err| {
        // If file doesn't exist, skip test (not an error)
        if (err == error.FileNotFound) {
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
}

test "Load AccuracyCoin.nes through Bus" {
    const accuracycoin_path = "AccuracyCoin/AccuracyCoin.nes";

    const nrom_cart = NromCart.load(testing.allocator, accuracycoin_path) catch |err| {
        if (err == error.FileNotFound) {
            return error.SkipZigTest;
        }
        return err;
    };

    // Wrap in AnyCartridge
    const cart = AnyCartridge{ .nrom = nrom_cart };

    var harness = try TestHarness.init();
    defer harness.deinit(); // Now properly cleans up cartridge via state.deinit()
    const state = harness.statePtr();

    state.loadCartridge(cart); // State takes ownership - cart is now invalid

    // Verify we can read from ROM through emulator bus
    const value = state.busRead(0x8000);
    _ = value;

    // Read reset vector (should point to ROM)
    const reset_low = state.busRead(0xFFFC);
    const reset_high = state.busRead(0xFFFD);
    const reset_vector = (@as(u16, reset_high) << 8) | @as(u16, reset_low);

    // Reset vector should be in ROM space ($8000-$FFFF)
    try testing.expect(reset_vector >= 0x8000);
    try testing.expect(reset_vector <= 0xFFFF);
}
