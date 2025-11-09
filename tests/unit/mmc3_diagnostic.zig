//! MMC3 IRQ Timing Diagnostic Tool
//!
//! This tool analyzes TMNT II's MMC3 IRQ behavior to verify the fixes for:
//! - Bug #1: IRQ enable clears pending flag
//! - Bug #2: IRQ disable clears pending flag
//! - Bug #3: A12 edge detection filter (6-8 PPU cycle delay)

const std = @import("std");
const RAMBO = @import("RAMBO");

const EmulationState = RAMBO.EmulationState.EmulationState;
const Config = RAMBO.Config.Config;
const CartridgeLoader = RAMBO.CartridgeLoader;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const rom_path = "tests/data/TMNT/Teenage Mutant Ninja Turtles II - The Arcade Game (USA).nes";

    std.debug.print("=== TMNT II MMC3 IRQ Diagnostic ===\n\n", .{});

    // Load ROM (auto-detect mapper from iNES header)
    const cart = try CartridgeLoader.loadAnyCartridgeFile(allocator, rom_path);

    // Initialize emulation (following smb_diagnostic pattern)
    var config = Config.init(allocator);
    defer config.deinit();

    var state = EmulationState.init(&config);
    defer state.deinit();

    state.loadCartridge(cart);
    state.power_on();

    std.debug.print("Running warmup period...\n", .{});
    while (!state.ppu.warmup_complete) {
        state.tick();
    }

    std.debug.print("Warmup complete. Monitoring MMC3 IRQ registers for 180 frames (3 seconds)...\n\n", .{});

    var last_irq_latch: u8 = 0;
    var last_irq_enabled: bool = false;
    var last_irq_counter: u8 = 0;
    var irq_trigger_count: usize = 0;

    // Monitor for 180 frames (3 seconds) to catch initialization
    var frame: usize = 0;
    while (frame < 180) : (frame += 1) {
        const scanlines_per_frame = 262;
        const dots_per_scanline = 341;
        const ppu_cycles_per_frame = scanlines_per_frame * dots_per_scanline;

        // Tick frame cycle-by-cycle to catch mid-frame changes
        var cycle: usize = 0;
        while (cycle < ppu_cycles_per_frame) : (cycle += 1) {
            state.tick();

            // Check mapper state every cycle during frame
            if (state.cart) |*c| {
                switch (c.*) {
                    .mmc3 => |*mmc3_cart| {
                        const mapper = &mmc3_cart.mapper;

                        // Check for IRQ register writes
                        if (mapper.irq_latch != last_irq_latch) {
                            const scanline = state.ppu.scanline;
                            const dot = state.ppu.dot;
                            std.debug.print("[Frame {} SL{} Dot{}] IRQ Latch: ${X:0>2} -> ${X:0>2}\n", .{
                                frame,
                                scanline,
                                dot,
                                last_irq_latch,
                                mapper.irq_latch,
                            });
                            last_irq_latch = mapper.irq_latch;
                        }

                        if (mapper.irq_enabled != last_irq_enabled) {
                            const scanline = state.ppu.scanline;
                            const dot = state.ppu.dot;
                            std.debug.print("[Frame {} SL{} Dot{}] IRQ Enabled: {} -> {}\n", .{
                                frame,
                                scanline,
                                dot,
                                last_irq_enabled,
                                mapper.irq_enabled,
                            });
                            last_irq_enabled = mapper.irq_enabled;
                        }

                        // Track counter changes
                        if (mapper.irq_counter != last_irq_counter) {
                            last_irq_counter = mapper.irq_counter;
                        }

                        // Count IRQ triggers
                        if (mapper.irq_pending) {
                            irq_trigger_count += 1;
                        }
                    },
                    else => {},
                }
            }
        }

        if (frame % 30 == 0) {
            std.debug.print("Frame {}: PPUMASK=${X:0>2} rendering={}\n", .{
                frame,
                @as(u8, @bitCast(state.ppu.mask)),
                state.ppu.mask.show_bg or state.ppu.mask.show_sprites,
            });
        }
    }

    std.debug.print("\n=== Summary ===\n", .{});
    std.debug.print("Total IRQ triggers: {}\n", .{irq_trigger_count});
    std.debug.print("Final IRQ latch: ${X:0>2}\n", .{last_irq_latch});
    std.debug.print("Final IRQ enabled: {}\n", .{last_irq_enabled});
    std.debug.print("Rendering enabled: {}\n", .{state.ppu.mask.show_bg or state.ppu.mask.show_sprites});
}
