//! CPU Instruction Integration Tests: Absolute mode writes to PPU registers
//!
//! These tests validate CPU instruction execution for absolute addressing mode
//! when writing to PPU registers. Requires direct CPU instruction setup.
//!
//! This validates the effective_address fix for absolute addressing mode.

const std = @import("std");
const testing = std.testing;
const RAMBO = @import("RAMBO");

const Harness = RAMBO.TestHarness.Harness;

test "Absolute mode: STA $2000 sets PPUCTRL correctly" {
    var harness = try Harness.init();
    defer harness.deinit();

    harness.state.reset();

    // Setup: STA $2000 instruction (write 0x90 to PPUCTRL)
    // LDA #$90, STA $2000
    // Note: Integration test - direct state access required for CPU instruction setup
    harness.state.bus.ram[0] = 0xA9; // LDA immediate
    harness.state.bus.ram[1] = 0x90; // Value
    harness.state.bus.ram[2] = 0x8D; // STA absolute
    harness.state.bus.ram[3] = 0x00; // Low byte of $2000
    harness.state.bus.ram[4] = 0x20; // High byte of $2000
    harness.state.cpu.pc = 0x0000;

    // Execute LDA #$90 (2 CPU cycles = 6 PPU cycles)
    var ppu_cycles: usize = 0;
    while (ppu_cycles < 6) : (ppu_cycles += 1) {
        harness.state.tick();
    }

    // Verify A register loaded
    try testing.expectEqual(@as(u8, 0x90), harness.state.cpu.a);

    // Execute STA $2000 (4 CPU cycles = 12 PPU cycles)
    ppu_cycles = 0;
    while (ppu_cycles < 12) : (ppu_cycles += 1) {
        harness.state.tick();
    }

    // Verify PPUCTRL was written correctly
    // 0x90 = 10010000 binary
    // Bit 7 (NMI): 1 = enabled
    // Bits 1-0 (nametable): 00 = $2000
    try testing.expectEqual(true, harness.state.ppu.ctrl.nmi_enable);
    try testing.expectEqual(false, harness.state.ppu.ctrl.nametable_x);
    try testing.expectEqual(false, harness.state.ppu.ctrl.nametable_y);
}

test "Absolute mode: STA $2001 sets PPUMASK correctly" {
    var harness = try Harness.init();
    defer harness.deinit();

    harness.state.reset();

    // Setup: LDA #$1E, STA $2001
    // Note: Integration test - direct state access required for CPU instruction setup
    harness.state.bus.ram[0] = 0xA9; // LDA immediate
    harness.state.bus.ram[1] = 0x1E; // 0x1E = show background + sprites
    harness.state.bus.ram[2] = 0x8D; // STA absolute
    harness.state.bus.ram[3] = 0x01; // Low byte of $2001
    harness.state.bus.ram[4] = 0x20; // High byte of $2001
    harness.state.cpu.pc = 0x0000;

    // Execute LDA + STA (18 PPU cycles total)
    var ppu_cycles: usize = 0;
    while (ppu_cycles < 18) : (ppu_cycles += 1) {
        harness.state.tick();
    }

    // Verify PPUMASK was written correctly
    // 0x1E = 00011110 binary
    try testing.expectEqual(true, harness.state.ppu.mask.show_bg);
    try testing.expectEqual(true, harness.state.ppu.mask.show_sprites);
    try testing.expectEqual(true, harness.state.ppu.mask.show_bg_left);
    try testing.expectEqual(true, harness.state.ppu.mask.show_sprites_left);
}

test "Absolute mode: Multiple PPUADDR writes set correct address" {
    var harness = try Harness.init();
    defer harness.deinit();

    harness.state.reset();

    // Setup: Write $23 then $C0 to PPUADDR to set address to $23C0
    // LDA #$23, STA $2006, LDA #$C0, STA $2006
    // Note: Integration test - direct state access required for CPU instruction setup
    harness.state.bus.ram[0] = 0xA9; // LDA #$23
    harness.state.bus.ram[1] = 0x23;
    harness.state.bus.ram[2] = 0x8D; // STA $2006
    harness.state.bus.ram[3] = 0x06;
    harness.state.bus.ram[4] = 0x20;
    harness.state.bus.ram[5] = 0xA9; // LDA #$C0
    harness.state.bus.ram[6] = 0xC0;
    harness.state.bus.ram[7] = 0x8D; // STA $2006
    harness.state.bus.ram[8] = 0x06;
    harness.state.bus.ram[9] = 0x20;
    harness.state.cpu.pc = 0x0000;

    // Execute first LDA + STA (18 PPU cycles)
    var ppu_cycles: usize = 0;
    while (ppu_cycles < 18) : (ppu_cycles += 1) {
        harness.state.tick();
    }

    // Execute second LDA + STA (18 PPU cycles)
    ppu_cycles = 0;
    while (ppu_cycles < 18) : (ppu_cycles += 1) {
        harness.state.tick();
    }

    // Verify VRAM address is $23C0
    try testing.expectEqual(@as(u16, 0x23C0), harness.state.ppu.internal.v);
}

test "Absolute mode: PPUDATA writes populate VRAM" {
    var harness = try Harness.init();
    defer harness.deinit();

    harness.state.reset();

    // Setup: Set PPUADDR to $2000, then write $AA to PPUDATA
    // Note: Integration test - direct state access required for CPU instruction setup
    harness.state.bus.ram[0] = 0xA9; // LDA #$20
    harness.state.bus.ram[1] = 0x20;
    harness.state.bus.ram[2] = 0x8D; // STA $2006 (high byte)
    harness.state.bus.ram[3] = 0x06;
    harness.state.bus.ram[4] = 0x20;
    harness.state.bus.ram[5] = 0xA9; // LDA #$00
    harness.state.bus.ram[6] = 0x00;
    harness.state.bus.ram[7] = 0x8D; // STA $2006 (low byte)
    harness.state.bus.ram[8] = 0x06;
    harness.state.bus.ram[9] = 0x20;
    harness.state.bus.ram[10] = 0xA9; // LDA #$AA
    harness.state.bus.ram[11] = 0xAA;
    harness.state.bus.ram[12] = 0x8D; // STA $2007 (PPUDATA)
    harness.state.bus.ram[13] = 0x07;
    harness.state.bus.ram[14] = 0x20;
    harness.state.cpu.pc = 0x0000;

    // Execute first LDA + STA (18 PPU cycles)
    var ppu_cycles: usize = 0;
    while (ppu_cycles < 18) : (ppu_cycles += 1) {
        harness.state.tick();
    }

    // Execute second LDA + STA (18 PPU cycles)
    ppu_cycles = 0;
    while (ppu_cycles < 18) : (ppu_cycles += 1) {
        harness.state.tick();
    }

    // Execute third LDA + STA (18 PPU cycles)
    ppu_cycles = 0;
    while (ppu_cycles < 18) : (ppu_cycles += 1) {
        harness.state.tick();
    }

    // Read VRAM directly to verify write
    const vram_value = harness.state.ppu.vram[0x0000]; // $2000 maps to VRAM $0000 with mirroring

    try testing.expectEqual(@as(u8, 0xAA), vram_value);
}
