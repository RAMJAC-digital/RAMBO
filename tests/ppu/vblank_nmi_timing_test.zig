const std = @import("std");
const testing = std.testing;
const RAMBO = @import("RAMBO");
const Harness = RAMBO.TestHarness.Harness;

// AccuracyCoin NMI Control Tests
// Based on tests/data/AccuracyCoin/AccuracyCoin.asm TEST_NMI_Control

// Test 1: NMI should NOT occur when disabled
test "NMI Control 1: NMI disabled - no interrupt" {
    var h = try Harness.init();
    defer h.deinit();

    h.state.ppu.warmup_complete = true;

    // Setup reset vector to point to infinite loop at $8000
    h.state.busWrite(0xFFFC, 0x00);
    h.state.busWrite(0xFFFD, 0x80);
    h.state.busWrite(0x8000, 0x4C); // JMP $8000
    h.state.busWrite(0x8001, 0x00);
    h.state.busWrite(0x8002, 0x80);

    // Setup NMI handler at $0700: INX; RTI
    h.state.busWrite(0x0700, 0xE8); // INX
    h.state.busWrite(0x0701, 0x40); // RTI
    h.state.busWrite(0xFFFA, 0x00); // NMI vector low
    h.state.busWrite(0xFFFB, 0x07); // NMI vector high

    // Reset to load PC from reset vector
    h.state.reset();

    // Disable NMI
    h.state.ppu.ctrl.nmi_enable = false;
    h.state.cpu.x = 0;

    // Run 1 frame (29780 cycles)
    _ = h.state.emulateFrame();

    // X should still be 0 (NMI didn't happen)
    try testing.expectEqual(@as(u8, 0), h.state.cpu.x);
}

// Test 2: NMI SHOULD occur at VBlank when enabled
test "NMI Control 2: NMI enabled before VBlank - fires at VBlank start" {
    var h = try Harness.init();
    defer h.deinit();

    h.state.ppu.warmup_complete = true;

    // Provide test ROM for vector fetch and code
    // ROM is mapped at $8000-$FFFF (32KB)
    const rom = try testing.allocator.alloc(u8, 0x8000);
    defer testing.allocator.free(rom);
    @memset(rom, 0xEA); // Fill with NOP
    h.state.bus.test_ram = rom;

    // Main loop at $8000: JMP $8000
    rom[0x0000] = 0x4C; // JMP
    rom[0x0001] = 0x00;
    rom[0x0002] = 0x80;

    // NMI handler at $C000: INX; RTI
    rom[0x4000] = 0xE8; // INX
    rom[0x4001] = 0x40; // RTI

    // NMI vector ($FFFA-$FFFB) points to $C000
    rom[0x7FFA] = 0x00; // Low byte
    rom[0x7FFB] = 0xC0; // High byte

    // Reset vector ($FFFC-$FFFD) points to $8000
    rom[0x7FFC] = 0x00; // Low byte
    rom[0x7FFD] = 0x80; // High byte

    // Reset to load PC
    h.state.reset();

    // Enable NMI
    h.state.ppu.ctrl.nmi_enable = true;
    h.state.cpu.x = 0;

    // Run 1 frame
    _ = h.state.emulateFrame();

    // X should be 1 (NMI happened once)
    try testing.expectEqual(@as(u8, 1), h.state.cpu.x);
}

// Test 3: NMI SHOULD occur when enabled during VBlank (if VBlank flag is set)
test "NMI Control 3: Enable NMI during VBlank with flag set - immediate trigger" {
    var h = try Harness.init();
    defer h.deinit();

    h.state.ppu.warmup_complete = true;

    // Provide test ROM for vector fetch and code
    const rom = try testing.allocator.alloc(u8, 0x8000);
    defer testing.allocator.free(rom);
    @memset(rom, 0xEA); // Fill with NOP
    h.state.bus.test_ram = rom;

    // Main loop at $8000: JMP $8000
    rom[0x0000] = 0x4C; // JMP
    rom[0x0001] = 0x00;
    rom[0x0002] = 0x80;

    // NMI handler at $C000: INX; RTI
    rom[0x4000] = 0xE8; // INX
    rom[0x4001] = 0x40; // RTI

    // NMI vector ($FFFA-$FFFB) points to $C000
    rom[0x7FFA] = 0x00;
    rom[0x7FFB] = 0xC0;

    // Reset vector ($FFFC-$FFFD) points to $8000
    rom[0x7FFC] = 0x00;
    rom[0x7FFD] = 0x80;

    // Reset to load PC
    h.state.reset();

    // Disable NMI initially
    h.state.ppu.ctrl.nmi_enable = false;
    h.state.cpu.x = 0;

    // Run to VBlank (scanline 241)
    while (h.state.clock.scanline() < 241) {
        h.state.tick();
    }
    // Advance a few cycles into VBlank
    var i: u32 = 0;
    while (i < 10) : (i += 1) {
        h.state.tick();
    }

    // Enable NMI while VBlank is active - should trigger immediately
    h.ppuWriteRegister(0x2000, 0x80);

    // Run cycles for NMI to process
    i = 0;
    while (i < 200) : (i += 1) {
        h.state.tick();
        if (h.state.cpu.x > 0) break;
    }

    // X should be 1 (NMI fired immediately when enabled during VBlank)
    try testing.expectEqual(@as(u8, 1), h.state.cpu.x);
}

// Comprehensive debug test
test "DEBUG: Trace NMI flow step by step" {
    var h = try Harness.init();
    defer h.deinit();

    h.state.ppu.warmup_complete = true;

    // Setup
    h.state.busWrite(0xFFFC, 0x00);
    h.state.busWrite(0xFFFD, 0x80);
    h.state.busWrite(0x8000, 0x4C); // JMP $8000
    h.state.busWrite(0x8001, 0x00);
    h.state.busWrite(0x8002, 0x80);
    h.state.busWrite(0x0700, 0xE8); // INX
    h.state.busWrite(0x0701, 0x40); // RTI
    h.state.busWrite(0xFFFA, 0x00);
    h.state.busWrite(0xFFFB, 0x07);

    h.state.reset();
    h.state.ppu.ctrl.nmi_enable = true;
    h.state.cpu.x = 0;

    std.debug.print("\n=== BEFORE VBLANK ===\n", .{});
    std.debug.print("Scanline: {}, NMI enabled: {}\n", .{h.state.clock.scanline(), h.state.ppu.ctrl.nmi_enable});
    std.debug.print("nmi_line: {}, nmi_edge_detected: {}, pending: {}\n", .{h.state.cpu.nmi_line, h.state.cpu.nmi_edge_detected, h.state.cpu.pending_interrupt});

    // Run to VBlank
    while (h.state.clock.scanline() < 241) {
        h.state.tick();
    }
    
    std.debug.print("\n=== AT VBLANK START (scanline 241) ===\n", .{});
    std.debug.print("Dot: {}, VBlank active: {}, VBlank visible: {}\n", .{
        h.state.clock.dot(),
        h.state.vblank_ledger.isActive(),
        h.state.vblank_ledger.isFlagVisible(),
    });
    std.debug.print("nmi_line: {}, nmi_edge_detected: {}, pending: {}\n", .{h.state.cpu.nmi_line, h.state.cpu.nmi_edge_detected, h.state.cpu.pending_interrupt});
    std.debug.print("last_set_cycle: {}, last_clear_cycle: {}\n", .{h.state.vblank_ledger.last_set_cycle, h.state.vblank_ledger.last_clear_cycle});

    // Run a few more cycles
    var i: u32 = 0;
    while (i < 100 and h.state.cpu.x == 0) : (i += 1) {
        h.state.tick();
        if (h.state.cpu.pending_interrupt == .nmi and i < 5) {
            std.debug.print("NMI pending at cycle {} after VBlank\n", .{i});
        }
        if (h.state.cpu.x > 0) {
            std.debug.print("X incremented to {} at cycle {}\n", .{h.state.cpu.x, i});
            break;
        }
    }

    std.debug.print("\n=== AFTER 100 CYCLES ===\n", .{});
    std.debug.print("X: {}, PC: ${X:0>4}\n", .{h.state.cpu.x, h.state.cpu.pc});
    std.debug.print("nmi_line: {}, pending: {}\n", .{h.state.cpu.nmi_line, h.state.cpu.pending_interrupt});
}
