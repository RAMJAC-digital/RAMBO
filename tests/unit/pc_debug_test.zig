const std = @import("std");
const testing = std.testing;
const RAMBO = @import("RAMBO");

const EmulationState = RAMBO.EmulationState.EmulationState;
const Config = RAMBO.Config.Config;
const NromCart = RAMBO.CartridgeType;
const AnyCartridge = RAMBO.AnyCartridge;

test "Debug: Super Mario Bros PC investigation" {
    const allocator = testing.allocator;

    const rom_path = "tests/data/Mario/Super Mario Bros. (World).nes";
    const nrom_cart = NromCart.load(allocator, rom_path) catch |err| {
        if (err == error.FileNotFound) return error.SkipZigTest;
        return err;
    };
    const cart = AnyCartridge{ .nrom = nrom_cart };

    var config = Config.init(allocator);
    defer config.deinit();

    var state = EmulationState.init(&config);
    defer state.deinit();

    state.loadCartridge(cart);
    state.power_on();

    // Verify initial state
    const reset_vector = state.busRead16(0xFFFC);
    const nmi_vector = state.busRead16(0xFFFA);

    std.debug.print("\n=== Initial State ===\n", .{});
    std.debug.print("RESET vector: 0x{X:0>4}\n", .{reset_vector});
    std.debug.print("NMI vector:   0x{X:0>4}\n", .{nmi_vector});
    std.debug.print("CPU PC:       0x{X:0>4}\n", .{state.cpu.pc});
    std.debug.print("CPU state:    {}\n", .{state.cpu.state});

    try testing.expectEqual(@as(u16, 0x8000), reset_vector);
    try testing.expectEqual(@as(u16, 0x8082), nmi_vector);
    try testing.expectEqual(@as(u16, 0x8000), state.cpu.pc);

    // Run exactly 10 frames and watch PC
    var framebuffer = [_]u32{0} ** (256 * 240);
    state.ppu.framebuffer = &framebuffer;

    var frame: usize = 0;
    while (frame < 10) : (frame += 1) {
        const pc_before = state.cpu.pc;
        _ = state.emulateFrame();
        const pc_after = state.cpu.pc;

        std.debug.print("\nFrame {d}:\n", .{frame + 1});
        std.debug.print("  PC: 0x{X:0>4} -> 0x{X:0>4}\n", .{pc_before, pc_after});
        std.debug.print("  PPUCTRL: 0x{X:0>2} (NMI enable: {})\n", .{
            @as(u8, @bitCast(state.ppu.ctrl)),
            state.ppu.ctrl.nmi_enable,
        });
        std.debug.print("  PPUMASK: 0x{X:0>2}\n", .{@as(u8, @bitCast(state.ppu.mask))});

        // Check if PC went to suspicious address
        if (pc_after == 0xFFFA or pc_after == 0xFFFB or
            pc_after == 0xFFFC or pc_after == 0xFFFD or
            pc_after == 0xFFFE or pc_after == 0xFFFF) {
            std.debug.print("  ⚠️  PC at vector table address!\n", .{});
        }
    }

    std.debug.print("\n=== After 10 Frames ===\n", .{});
    std.debug.print("CPU PC:  0x{X:0>4}\n", .{state.cpu.pc});
    std.debug.print("Is PC in vector table (0xFFFA-0xFFFF)? {}\n", .{
        state.cpu.pc >= 0xFFFA and state.cpu.pc <= 0xFFFF
    });
}
