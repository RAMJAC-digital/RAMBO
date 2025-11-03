//! Simple VBlank $2002 read test
//! Tests that $2002 reads properly clear the VBlank flag without seekToScanlineDot

const std = @import("std");
const testing = std.testing;
const RAMBO = @import("RAMBO");

const EmulationState = RAMBO.EmulationState.EmulationState;

test "Simple VBlank test: $2002 read clears flag" {
    var state = EmulationState.init(testing.allocator);
    defer state.deinit();

    // Setup simple test program that reads $2002
    // We'll manually run to VBlank without seekToScanlineDot
    var test_ram = [_]u8{0} ** 0x8000;
    test_ram[0] = 0xAD; // LDA absolute
    test_ram[1] = 0x02; // Low byte ($2002)
    test_ram[2] = 0x20; // High byte
    test_ram[3] = 0xEA; // NOP
    test_ram[4] = 0xEA; // NOP

    // Initialize reset vector at $FFFC-$FFFD to point to $8000
    test_ram[0x7FFC] = 0x00; // Low byte of $8000
    test_ram[0x7FFD] = 0x80; // High byte of $8000

    state.bus.test_ram = &test_ram;

    state.reset();
    state.ppu.warmup_complete = true;

    std.debug.print("\n=== Simple VBlank Test ===\n", .{});

    // Run emulation until we hit scanline 241 dot 1 (VBlank set)
    var found_vblank_set = false;
    var iterations: usize = 0;
    const max_iterations = 100_000; // Safety limit

    while (!found_vblank_set and iterations < max_iterations) : (iterations += 1) {
        const scanline = state.ppu.scanline;
        const dot = state.ppu.cycle;

        if (scanline == 241 and dot == 0) {
            // We're just before VBlank sets
            // At 241,0 VBlank should not yet be visible to CPU reads
            const before = state.busRead(0x2002);
            std.debug.print("At scanline 241 dot 0, PPUSTATUS=0x{X:0>2}\n", .{before});
            try testing.expect((before & 0x80) == 0);

            // Tick once - VBlank should set
            state.tick();
            // After tick, VBlank should be set; a read should see bit 7 set
            const after = state.busRead(0x2002);
            std.debug.print("After tick to 241.1, PPUSTATUS=0x{X:0>2}\n", .{after});
            try testing.expect((after & 0x80) != 0);

            found_vblank_set = true;
            break;
        }

        state.tick();
    }

    try testing.expect(found_vblank_set);

    // Now VBlank is set. Execute a few more ticks to let CPU potentially read $2002
    // LDA $2002 takes 4 CPU cycles = 12 PPU ticks
    std.debug.print("\nExecuting LDA $2002 instruction...\n", .{});

    var ticks: usize = 0;
    // VBlank was just set; ensure status reflects it at this point (non-destructive check)
    var status_before = state.busRead(0x2002);
    try testing.expect((status_before & 0x80) != 0);

    // Tick through the instruction (12 PPU ticks = 4 CPU cycles)
    while (ticks < 12) : (ticks += 1) {
        state.tick();
    }

    // After LDA $2002 executed, a subsequent read should find VBlank cleared
    var status_after = state.busRead(0x2002);
    std.debug.print("After LDA execution, PPUSTATUS=0x{X:0>2}\n", .{status_after});
    std.debug.print("CPU A register = 0x{X:0>2}\n", .{state.cpu.a});

    // After reading $2002, VBlank should be cleared
    try testing.expect((status_after & 0x80) == 0);

    // CPU A register should have captured VBlank bit (0x80 or higher)
    try testing.expect(state.cpu.a >= 0x80);
}
