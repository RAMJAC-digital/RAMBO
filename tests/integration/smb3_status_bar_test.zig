//! SMB3 Status Bar MMC3 IRQ Integration Test
//!
//! Tests that Super Mario Bros 3's status bar split-screen effect works correctly.
//! This requires MMC3 IRQ timing to be accurate.

const std = @import("std");
const testing = std.testing;
const math = std.math;
const RAMBO = @import("RAMBO");

const Harness = RAMBO.TestHarness.Harness;
const CartridgeLoader = RAMBO.CartridgeLoader;

test "SMB3: MMC3 IRQ fires during gameplay" {
    const allocator = testing.allocator;
    const rom_path = "tests/data/Mario/Super Mario Bros. 3 (USA) (Rev 1).nes";

    // Load SMB3 ROM
    const cart = CartridgeLoader.loadAnyCartridgeFile(allocator, rom_path) catch |err| {
        if (err == error.FileNotFound) {
            std.debug.print("SMB3 ROM not found at: {s}\n", .{rom_path});
            return error.SkipZigTest;
        }
        return err;
    };

    // Verify it's MMC3
    try testing.expect(cart == .mmc3);

    var h = try Harness.init();
    defer h.deinit();

    h.loadCartridge(cart);
    h.state.reset();

    // Run until warmup complete
    while (!h.state.ppu.warmup_complete) {
        h.state.tick();
    }

    std.debug.print("\n=== SMB3 MMC3 IRQ Test ===\n", .{});

    // Track IRQ behavior
    var irq_fired_frame: ?usize = null;
    var irq_fired_scanline: ?u16 = null;
    var irq_latch_value: ?u8 = null;
    var total_irqs: usize = 0;

    // Diagnostic: Track IRQ state
    var irq_enabled_frame: ?usize = null;
    var prev_irq_latch: ?u8 = null;

    // Run for 180 frames (3 seconds) - enough to get past title screen
    var frame: usize = 0;
    while (frame < 180) : (frame += 1) {
        const scanlines_per_frame = 262;
        const dots_per_scanline = 341;
        const ppu_cycles_per_frame = scanlines_per_frame * dots_per_scanline;

        var prev_irq_pending = false;
        var prev_irq_counter: u8 = 0;
        var prev_a12_count: u32 = 0;
        var accum_a12: u32 = 0;
        var prev_irq_enabled = false;
        var min_irq_counter: u8 = 0xFF;
        var zero_counter_events: usize = 0;
        var prev_irq_event_count: u32 = 0;
        var prev_irq_reload = false;
        var prev_scanline = h.state.ppu.scanline;

        var a12_per_scanline: [262]u32 = [_]u32{0} ** 262;

        var irq_counter_changes: [64]struct {
            frame: usize,
            scanline: u16,
            dot: u16,
            old: u8,
            new: u8,
        } = undefined;
        var irq_counter_change_count: usize = 0;

        var irq_edge_log: [32]struct {
            frame: usize,
            scanline: u16,
            dot: u16,
            counter: u8,
            latch: u8,
        } = undefined;
        var irq_edge_count: usize = 0;

        if (h.state.cart) |*c| {
            switch (c.*) {
                .mmc3 => |*mmc3_cart| {
                    prev_irq_pending = mmc3_cart.mapper.irq_pending;
                    prev_irq_counter = mmc3_cart.mapper.irq_counter;
                    prev_a12_count = mmc3_cart.mapper.debug_a12_count;
                    prev_irq_enabled = mmc3_cart.mapper.irq_enabled;
                    min_irq_counter = prev_irq_counter;
                    prev_irq_event_count = mmc3_cart.mapper.debug_irq_events;
                    prev_irq_reload = mmc3_cart.mapper.irq_reload;
                },
                else => {},
            }
        }

        var cycle: usize = 0;
        while (cycle < ppu_cycles_per_frame) : (cycle += 1) {
            h.state.tick();

            if (h.state.cart) |*c| {
                switch (c.*) {
                    .mmc3 => |*mmc3_cart| {
                        const mapper = &mmc3_cart.mapper;

                        const current_scanline = h.state.ppu.scanline;
                        if (current_scanline != prev_scanline) {
                            if (prev_scanline < a12_per_scanline.len) {
                                a12_per_scanline[prev_scanline] += accum_a12;
                            }
                            accum_a12 = 0;
                            prev_scanline = current_scanline;
                        }

                        if (mapper.debug_a12_count != prev_a12_count) {
                            const delta = if (mapper.debug_a12_count >= prev_a12_count)
                                mapper.debug_a12_count - prev_a12_count
                            else
                                (math.maxInt(u32) - prev_a12_count) + mapper.debug_a12_count + 1;
                            accum_a12 += delta;
                            prev_a12_count = mapper.debug_a12_count;
                        }

                        if (mapper.irq_counter != prev_irq_counter and irq_counter_change_count < irq_counter_changes.len) {
                            irq_counter_changes[irq_counter_change_count] = .{
                                .frame = frame,
                                .scanline = h.state.ppu.scanline,
                                .dot = h.state.ppu.dot,
                                .old = prev_irq_counter,
                                .new = mapper.irq_counter,
                            };
                            irq_counter_change_count += 1;
                            prev_irq_counter = mapper.irq_counter;
                        } else {
                            prev_irq_counter = mapper.irq_counter;
                        }

                        if (mapper.irq_counter < min_irq_counter) {
                            min_irq_counter = mapper.irq_counter;
                        }

                        if (mapper.irq_counter == 0 and mapper.irq_enabled) {
                            zero_counter_events += 1;
                            if (prev_irq_counter == 1) {
                                std.debug.print(
                                    "  >>> Counter decremented to zero at frame {} SL {} Dot {} (events={})\n",
                                    .{
                                        frame,
                                        h.state.ppu.scanline,
                                        h.state.ppu.dot,
                                        mapper.debug_irq_events,
                                    },
                                );
                            }
                        }

                        if (mapper.irq_enabled and !prev_irq_enabled) {
                            if (irq_enabled_frame == null) irq_enabled_frame = frame;
                            std.debug.print("IRQ ENABLED at frame {} (scanline {})\n", .{ frame, h.state.ppu.scanline });
                            prev_irq_enabled = true;
                        } else if (!mapper.irq_enabled and prev_irq_enabled) {
                            std.debug.print("IRQ DISABLED at frame {} (scanline {})\n", .{ frame, h.state.ppu.scanline });
                            prev_irq_enabled = false;
                        }

                        if (prev_irq_latch == null or mapper.irq_latch != prev_irq_latch.?) {
                            prev_irq_latch = mapper.irq_latch;
                            std.debug.print("IRQ LATCH set to ${X:0>2} at frame {} (scanline {})\n", .{ mapper.irq_latch, frame, h.state.ppu.scanline });
                        }

                        const curr_irq_pending = mapper.irq_pending;
                        if (!prev_irq_pending and curr_irq_pending) {
                            total_irqs += 1;

                            if (irq_fired_frame == null) {
                                irq_fired_frame = frame;
                                irq_fired_scanline = h.state.ppu.scanline;
                                irq_latch_value = mapper.irq_latch;

                                std.debug.print("FIRST IRQ: Frame={}, SL={}, Latch=${X:0>2}, Counter={}\n", .{
                                    frame,
                                    irq_fired_scanline.?,
                                    irq_latch_value.?,
                                    mapper.irq_counter,
                                });
                            }

                            if (irq_edge_count < irq_edge_log.len) {
                                irq_edge_log[irq_edge_count] = .{
                                    .frame = frame,
                                    .scanline = h.state.ppu.scanline,
                                    .dot = h.state.ppu.dot,
                                    .counter = mapper.irq_counter,
                                    .latch = mapper.irq_latch,
                                };
                                irq_edge_count += 1;
                            }
                        }

                        if (mapper.debug_irq_events != prev_irq_event_count) {
                            const delta_events = mapper.debug_irq_events - prev_irq_event_count;
                            prev_irq_event_count = mapper.debug_irq_events;
                            std.debug.print(
                                "[Frame {} SL {} Dot {}] IRQ pending events += {} (counter={}, enabled={})\n",
                                .{
                                    frame,
                                    h.state.ppu.scanline,
                                    h.state.ppu.dot,
                                    delta_events,
                                    mapper.irq_counter,
                                    mapper.irq_enabled,
                                },
                            );
                        }

                        if (mapper.irq_reload and !prev_irq_reload) {
                            std.debug.print(
                                "  >>> IRQ reload set at frame {} SL {} Dot {} (counter={}, latch=${X:0>2}, bg_pattern={}, sprite_pattern={})\n",
                                .{
                                    frame,
                                    h.state.ppu.scanline,
                                    h.state.ppu.dot,
                                    mapper.irq_counter,
                                    mapper.irq_latch,
                                    @intFromBool(h.state.ppu.ctrl.bg_pattern),
                                    @intFromBool(h.state.ppu.ctrl.sprite_pattern),
                                },
                            );
                            prev_irq_reload = true;
                        } else if (!mapper.irq_reload and prev_irq_reload) {
                            prev_irq_reload = false;
                        }

                        prev_irq_pending = curr_irq_pending;
                    },
                    else => {},
                }
            }
        }

        if (prev_scanline < a12_per_scanline.len) {
            a12_per_scanline[prev_scanline] += accum_a12;
        }

        if (frame % 30 == 0) {
            std.debug.print("Frame {}: Total IRQs so far = {}\n", .{ frame, total_irqs });
        }

        if (total_irqs == 0 and frame % 60 == 59) {
            std.debug.print("-- A12 edge counts frame {} --\n", .{frame});
            for (a12_per_scanline, 0..) |count, sl| {
                if (count != 0) {
                    std.debug.print("  SL {:3}: {} edges\n", .{ sl, count });
                }
            }
            if (irq_counter_change_count > 0) {
                std.debug.print("-- IRQ counter transitions frame {} --\n", .{frame});
                for (irq_counter_changes[0..irq_counter_change_count]) |entry| {
                    std.debug.print(
                        "  Frame {} SL {} Dot {} counter {} -> {}\n",
                        .{ entry.frame, entry.scanline, entry.dot, entry.old, entry.new },
                    );
                }
            }
            std.debug.print("Min IRQ counter observed this frame: {}\n", .{min_irq_counter});
            std.debug.print("Zero counter events (enabled) this frame: {}\n", .{zero_counter_events});
        }

        if (total_irqs == 0 and irq_edge_count > 0) {
            std.debug.print("-- IRQ pending edges frame {} --\n", .{frame});
            for (irq_edge_log[0..irq_edge_count]) |entry| {
                std.debug.print(
                    "  Frame {} SL {} Dot {} counter={} latch=${X:0>2}\n",
                    .{ entry.frame, entry.scanline, entry.dot, entry.counter, entry.latch },
                );
            }
        }
    }

    // CRITICAL: SMB3 MUST use MMC3 IRQs for status bar
    // If no IRQs fire, the implementation is broken
    if (irq_fired_frame == null) {
        return error.TestFailed;
    }

    // Verify IRQ fired in reasonable timeframe (before frame 120)
    try testing.expect(irq_fired_frame.? < 120);

    // Verify multiple IRQs fired (split-screen is continuous)
    try testing.expect(total_irqs > 10);
}
