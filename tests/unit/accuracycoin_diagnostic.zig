const std = @import("std");
const RAMBO = @import("RAMBO");
const EmulationState = RAMBO.EmulationState.EmulationState;
const Config = RAMBO.Config.Config;
const AnyCartridge = RAMBO.AnyCartridge;
const CartridgeLoader = RAMBO.CartridgeLoader;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const rom_path = "tests/data/AccuracyCoin/AccuracyCoin.nes";
    std.debug.print("Loading AccuracyCoin ROM from: {s}\n", .{rom_path});

    const cart = try CartridgeLoader.loadAnyCartridgeFile(allocator, rom_path);
    var config = Config.init(allocator);
    defer config.deinit();
   
    var state = EmulationState.init(&config);
    defer state.deinit();

    state.loadCartridge(cart);
    state.power_on();

    const max_frames = 200;
    var frame_count: usize = 0;

    std.debug.print("Running AccuracyCoin tests...\n", .{});

    while (frame_count < max_frames) : (frame_count += 1) {
        _ = state.emulateFrame();
        const page_number = state.peekMemory(0x40);
        
        if (frame_count % 20 == 0) {
            std.debug.print("Frame {}, page={}\n", .{frame_count, page_number});
        }

        if (page_number == 17 or page_number == 0x11) {
            std.debug.print("\n=== AccuracyCoin Test Results (Page {}) ===\n", .{page_number});

            const results = [_]struct { name: []const u8, addr: u16 }{
                .{ .name = "VBlank Beginning", .addr = 0x450 },
                .{ .name = "VBlank End", .addr = 0x451 },
                .{ .name = "NMI Control", .addr = 0x452 },
                .{ .name = "NMI Timing", .addr = 0x453 },
                .{ .name = "NMI Suppression", .addr = 0x454 },
                .{ .name = "NMI at VBlank End", .addr = 0x455 },
                .{ .name = "NMI Disabled at VBlank", .addr = 0x456 },
            };

            var all_passed = true;
            for (results) |result| {
                const value = state.peekMemory(result.addr);
                const passed = (value == 0xFF);
                const status = if (passed) "PASS" else "FAIL";
                std.debug.print("  {s: <30} [{s}] (value=0x{X:0>2})\n", .{ result.name, status, value });
                if (!passed) all_passed = false;
            }

            std.debug.print("\n", .{});
            if (all_passed) {
                std.debug.print("✅ All NMI/VBlank tests PASSED!\n", .{});
                return;
            } else {
                std.debug.print("❌ Some tests FAILED\n", .{});
                std.process.exit(1);
            }
        }
    }

    std.debug.print("⚠️  Timeout: Did not reach test results page after {} frames (last page={})\n", .{max_frames, state.peekMemory(0x40)});
    std.process.exit(1);
}
