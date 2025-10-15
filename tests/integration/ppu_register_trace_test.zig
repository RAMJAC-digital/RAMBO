//! PPU Register Write Tracing Test
//!
//! Tracks exact cycles when games write to PPUCTRL ($2000) and PPUMASK ($2001)
//! to understand initialization sequences and identify why rendering doesn't enable.

const std = @import("std");
const testing = std.testing;
const RAMBO = @import("RAMBO");
const Config = RAMBO.Config.Config;
const EmulationState = RAMBO.EmulationState.EmulationState;
const CartridgeLoader = RAMBO.CartridgeLoader;

const FRAME_PIXELS = 256 * 240;

test "Castlevania: Trace PPUCTRL/PPUMASK writes" {
    const allocator = testing.allocator;
    const rom_path = "tests/data/Castlevania/Castlevania (USA) (Rev 1).nes";

    const cart = CartridgeLoader.loadAnyCartridgeFile(allocator, rom_path) catch |err| {
        if (err == error.FileNotFound) return error.SkipZigTest;
        return err;
    };

    var config = Config.init(allocator);
    defer config.deinit();

    var state = EmulationState.init(&config);
    defer state.deinit();

    state.loadCartridge(cart);
    state.power_on();

    var framebuffer = [_]u32{0} ** FRAME_PIXELS;

    std.debug.print("\n=== Castlevania PPU Register Write Trace ===\n", .{});
    std.debug.print("Warmup completes at CPU cycle 29,658\n", .{});
    std.debug.print("Tracking writes to $2000 (PPUCTRL) and $2001 (PPUMASK)...\n\n", .{});

    var last_ppuctrl: u8 = 0;
    var last_ppumask: u8 = 0;
    var ppuctrl_write_count: usize = 0;
    var ppumask_write_count: usize = 0;

    // Run for 60 frames (1 second)
    var frame: usize = 0;
    while (frame < 60) : (frame += 1) {
        state.framebuffer = &framebuffer;
        _ = state.emulateFrame();

        const ppuctrl: u8 = @bitCast(state.ppu.ctrl);
        const ppumask: u8 = @bitCast(state.ppu.mask);

        // Detect PPUCTRL write
        if (ppuctrl != last_ppuctrl) {
            ppuctrl_write_count += 1;
            std.debug.print("[Frame {d}, Cycle {d}] PPUCTRL: ${X:0>2} -> ${X:0>2} (warmup={})\n", .{
                frame,
                state.clock.cpuCycles(),
                last_ppuctrl,
                ppuctrl,
                state.ppu.warmup_complete,
            });
            last_ppuctrl = ppuctrl;
        }

        // Detect PPUMASK write
        if (ppumask != last_ppumask) {
            ppumask_write_count += 1;
            std.debug.print("[Frame {d}, Cycle {d}] PPUMASK: ${X:0>2} -> ${X:0>2} (warmup={})\n", .{
                frame,
                state.clock.cpuCycles(),
                last_ppumask,
                ppumask,
                state.ppu.warmup_complete,
            });
            last_ppumask = ppumask;

            // Check if rendering enabled
            const show_bg = (ppumask >> 3) & 1;
            const show_sprites = (ppumask >> 4) & 1;
            if (show_bg != 0 or show_sprites != 0) {
                std.debug.print("  ✅ RENDERING ENABLED at frame {d}!\n", .{frame});
                return; // Success!
            }
        }

        // Report warmup completion
        if (frame == 0 and state.ppu.warmup_complete) {
            std.debug.print("[Frame 0] Warmup completed at cycle {d}\n", .{state.clock.cpuCycles()});
        }
    }

    std.debug.print("\n=== Summary ===\n", .{});
    std.debug.print("PPUCTRL writes: {d}\n", .{ppuctrl_write_count});
    std.debug.print("PPUMASK writes: {d}\n", .{ppumask_write_count});
    std.debug.print("Final PPUCTRL: ${X:0>2}\n", .{last_ppuctrl});
    std.debug.print("Final PPUMASK: ${X:0>2}\n", .{last_ppumask});
    std.debug.print("Warmup complete: {}\n", .{state.ppu.warmup_complete});

    // Check if there's a buffered write
    if (state.ppu.warmup_ppumask_buffer) |buffered| {
        std.debug.print("⚠️  BUFFERED PPUMASK: ${X:0>2} (never applied!)\n", .{buffered});
    }

    std.debug.print("\n❌ Rendering never enabled - game failed to write to PPUMASK\n", .{});
}

test "Super Mario Bros: Trace PPUCTRL/PPUMASK writes (baseline)" {
    const allocator = testing.allocator;
    const rom_path = "tests/data/Mario/Super Mario Bros. (World).nes";

    const cart = CartridgeLoader.loadAnyCartridgeFile(allocator, rom_path) catch |err| {
        if (err == error.FileNotFound) return error.SkipZigTest;
        return err;
    };

    var config = Config.init(allocator);
    defer config.deinit();

    var state = EmulationState.init(&config);
    defer state.deinit();

    state.loadCartridge(cart);
    state.power_on();

    var framebuffer = [_]u32{0} ** FRAME_PIXELS;

    std.debug.print("\n=== Super Mario Bros PPU Register Write Trace (WORKING BASELINE) ===\n", .{});

    var last_ppuctrl: u8 = 0;
    var last_ppumask: u8 = 0;
    var first_ppumask_write: ?usize = null;

    // Run for 60 frames
    var frame: usize = 0;
    while (frame < 60) : (frame += 1) {
        state.framebuffer = &framebuffer;
        _ = state.emulateFrame();

        const ppuctrl: u8 = @bitCast(state.ppu.ctrl);
        const ppumask: u8 = @bitCast(state.ppu.mask);

        // Detect PPUCTRL write
        if (ppuctrl != last_ppuctrl) {
            std.debug.print("[Frame {d}, Cycle {d}] PPUCTRL: ${X:0>2} -> ${X:0>2}\n", .{
                frame,
                state.clock.cpuCycles(),
                last_ppuctrl,
                ppuctrl,
            });
            last_ppuctrl = ppuctrl;
        }

        // Detect PPUMASK write
        if (ppumask != last_ppumask) {
            if (first_ppumask_write == null) {
                first_ppumask_write = frame;
            }
            std.debug.print("[Frame {d}, Cycle {d}] PPUMASK: ${X:0>2} -> ${X:0>2}\n", .{
                frame,
                state.clock.cpuCycles(),
                last_ppumask,
                ppumask,
            });
            last_ppumask = ppumask;

            // Check if rendering enabled
            const show_bg = (ppumask >> 3) & 1;
            const show_sprites = (ppumask >> 4) & 1;
            if (show_bg != 0 or show_sprites != 0) {
                std.debug.print("  ✅ RENDERING ENABLED at frame {d}!\n\n", .{frame});
                return; // Success!
            }
        }
    }

    std.debug.print("\n❌ Super Mario Bros failed to enable rendering (unexpected!)\n", .{});
    return error.TestUnexpectedResult;
}
