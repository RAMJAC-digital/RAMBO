//! Super Mario Bros VBlank Regression Test
//!
//! This test loads the actual SMB ROM and runs it for several frames.
//! SMB was working before but now shows blank screen due to VBlank flag bug.
//!
//! Expected: SMB should enable rendering (PPUMASK != 0) after initialization
//! Actual: SMB gets stuck in infinite loop waiting for VBlank that never happens

const std = @import("std");
const testing = std.testing;
const RAMBO = @import("RAMBO");

const EmulationState = RAMBO.EmulationState.EmulationState;
const Config = RAMBO.Config.Config;
const NromCart = RAMBO.CartridgeType;
const AnyCartridge = RAMBO.AnyCartridge;

test "SMB VBlank Regression: Super Mario Bros initializes rendering" {
    const allocator = testing.allocator;

    // Load Super Mario Bros ROM
    const rom_path = "tests/data/Mario/Super Mario Bros. (World).nes";
    const nrom_cart = NromCart.load(allocator, rom_path) catch |err| {
        if (err == error.FileNotFound) return error.SkipZigTest;
        return err;
    };

    const cart = AnyCartridge{ .nrom = nrom_cart };

    // Initialize emulation state
    var config = Config.init(allocator);
    defer config.deinit();

    var state = EmulationState.init(&config);
    defer state.deinit();

    state.loadCartridge(cart);

    // Power-on: Load reset vector
    const reset_vector = state.busRead16(0xFFFC);
    state.cpu.pc = reset_vector;
    state.cpu.sp = 0xFD;
    state.cpu.p.interrupt = true;

    // Run for 180 frames (3 seconds at 60 FPS)
    var frame_count: usize = 0;
    var vblank_set_count: usize = 0;
    var last_set_cycle: u64 = 0;
    var last_clear_cycle: u64 = 0;
    var late_clear_frame: ?usize = null;

    const FrameTrace = struct {
        index: usize,
        ctrl: u8,
        mask: u8,
        rendering_enabled: bool,
        nmi_enable: bool,
        nmi_pending: bool,
        vblank_set: u64,
        vblank_clear: u64,
        status_read: ?u64,
        ctrl_toggle: u64,
        read_on_set: bool,
    };

    var traces: [64]FrameTrace = undefined;
    var traces_count: usize = 0;

    var early_vblank_read_violation = false;

    while (frame_count < 180) {
        // Track VBlank cycles at start of frame
        const cycle_before_frame = state.clock.ppu_cycles;

        // Run until frame complete
        while (true) {
            state.tick();

            // Check if frame is complete
            const scanline = state.ppu.scanline;
            const dot = state.ppu.dot;
            if (scanline == 0 and dot == 0) {
                break;
            }
        }

        frame_count += 1;

        // After frame completes, check if VBlank was set during this frame
        if (state.ppu.vblank.last_set_cycle > cycle_before_frame) {
            vblank_set_count += 1;
            last_set_cycle = state.ppu.vblank.last_set_cycle;
            last_clear_cycle = state.ppu.vblank.last_clear_cycle;

            // On first 3 frames, verify VBlank is working correctly
            if (frame_count <= 3) {
                const delta = last_clear_cycle - last_set_cycle;
                const last_read = state.ppu.vblank.last_read_cycle;

                // Check if SMB read $2002 during this frame
                const read_during_frame = (last_read > cycle_before_frame);
                if (read_during_frame) {
                    const read_during_vblank = (last_read >= last_set_cycle) and (last_read < (last_set_cycle + 6820));
                    if (!read_during_vblank) {
                        early_vblank_read_violation = true;
                    }
                }

                if (last_clear_cycle <= last_set_cycle) {
                    late_clear_frame = frame_count;
                }
                if (delta > 6840) {
                    late_clear_frame = frame_count;
                }
            }
        }

        // Check if SMB has enabled rendering yet
        const rendering_enabled = (state.ppu.mask.show_bg or state.ppu.mask.show_sprites);

        if (traces_count < traces.len) {
            const ledger = state.ppu.vblank;
            const last_read_cycle = if (ledger.last_read_cycle > cycle_before_frame)
                ledger.last_read_cycle
            else
                null;

            traces[traces_count] = .{
                .index = frame_count,
                .ctrl = @as(u8, @bitCast(state.ppu.ctrl)),
                .mask = @as(u8, @bitCast(state.ppu.mask)),
                .rendering_enabled = rendering_enabled,
                .nmi_enable = state.ppu.ctrl.nmi_enable,
                .nmi_pending = ledger.nmi_edge_pending,
                .vblank_set = ledger.last_set_cycle,
                .vblank_clear = ledger.last_clear_cycle,
                .status_read = last_read_cycle,
                .ctrl_toggle = ledger.last_ctrl_toggle_cycle,
                .read_on_set = last_read_cycle != null and last_read_cycle.? == ledger.last_set_cycle,
            };
            traces_count += 1;
        }

        if (rendering_enabled) {
            // SUCCESS: SMB enabled rendering
            return; // Test passed
        }
    }

    // FAILURE: SMB never enabled rendering after 180 frames
    // Add assertions about what we observed
    const has_vblank = vblank_set_count > 0;
    const sufficient_vblank = vblank_set_count >= 170;
    const read_ok = !early_vblank_read_violation;
    const clear_ok = late_clear_frame == null;

    if (!has_vblank or !sufficient_vblank or !read_ok or !clear_ok) {
        std.debug.print("\n=== SMB VBLANK BUG REPRODUCED ===\n", .{});
        std.debug.print("SMB failed to enable rendering after {} frames\n", .{frame_count});
        std.debug.print("Conditions: has_vblank={} sufficient_vblank={} read_ok={} clear_ok={}\n", .{ has_vblank, sufficient_vblank, read_ok, clear_ok });
        std.debug.print("\nCurrent state:\n", .{});
        std.debug.print("  CPU PC: 0x{X:0>4}\n", .{state.cpu.pc});
        std.debug.print("  PPUMASK: 0x{X:0>2}\n", .{@as(u8, @bitCast(state.ppu.mask))});
        std.debug.print("  PPUCTRL: 0x{X:0>2}\n", .{@as(u8, @bitCast(state.ppu.ctrl))});
        std.debug.print("  VBlank ledger:\n", .{});
        std.debug.print("    span_active: {}\n", .{state.ppu.vblank.vblank_span_active});
        std.debug.print("    last_set_cycle: {}\n", .{state.ppu.vblank.last_set_cycle});
        std.debug.print("    last_clear_cycle: {}\n", .{state.ppu.vblank.last_clear_cycle});
        std.debug.print("    last_read_cycle: {}\n", .{state.ppu.vblank.last_read_cycle});

        std.debug.print("\nFrame trace (first {} frames):\n", .{traces_count});
        for (traces[0..traces_count]) |trace| {
            std.debug.print(
                "  #{:>3} ctrl=0x{X:0>2} mask=0x{X:0>2} render={} nmi_en={} nmi_pending={} set={} clear={} read={} ctrl_toggle={} read_on_set={}\n",
                .{
                    trace.index,
                    trace.ctrl,
                    trace.mask,
                    trace.rendering_enabled,
                    trace.nmi_enable,
                    trace.nmi_pending,
                    trace.vblank_set,
                    trace.vblank_clear,
                    trace.status_read orelse 0,
                    trace.ctrl_toggle,
                    trace.read_on_set,
                },
            );
        }

        return error.SmbStuckWaitingForVBlank;
    }

    return error.SmbStuckWaitingForVBlank;
}
