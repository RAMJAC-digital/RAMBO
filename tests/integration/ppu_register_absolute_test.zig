//! Test to verify absolute mode writes to PPU registers work correctly
//! This validates the effective_address fix for absolute addressing mode

const std = @import("std");
const testing = std.testing;
const RAMBO = @import("RAMBO");

const EmulationState = RAMBO.EmulationState.EmulationState;
const Config = RAMBO.Config;

test "Absolute mode: STA $2000 sets PPUCTRL correctly" {
    var config = Config.Config.init(testing.allocator);
    defer config.deinit();

    var state = EmulationState.init(&config);
    defer state.deinit();
    state.reset();

    // Setup: STA $2000 instruction (write 0x90 to PPUCTRL)
    // LDA #$90, STA $2000
    state.bus.ram[0] = 0xA9; // LDA immediate
    state.bus.ram[1] = 0x90; // Value
    state.bus.ram[2] = 0x8D; // STA absolute
    state.bus.ram[3] = 0x00; // Low byte of $2000
    state.bus.ram[4] = 0x20; // High byte of $2000
    state.cpu.pc = 0x0000;

    // Execute LDA #$90 (2 CPU cycles = 6 PPU cycles)
    var ppu_cycles: usize = 0;
    while (ppu_cycles < 6) : (ppu_cycles += 1) {
        state.tick();
    }

    // Verify A register loaded
    try testing.expectEqual(@as(u8, 0x90), state.cpu.a);

    // Execute STA $2000 (4 CPU cycles = 12 PPU cycles)
    ppu_cycles = 0;
    while (ppu_cycles < 12) : (ppu_cycles += 1) {
        state.tick();
    }

    // Verify PPUCTRL was written correctly
    // 0x90 = 10010000 binary
    // Bit 7 (NMI): 1 = enabled
    // Bits 1-0 (nametable): 00 = $2000
    try testing.expectEqual(true, state.ppu.ctrl.nmi_enable);
    try testing.expectEqual(false, state.ppu.ctrl.nametable_x);
    try testing.expectEqual(false, state.ppu.ctrl.nametable_y);
}

test "Absolute mode: STA $2001 sets PPUMASK correctly" {
    var config = Config.Config.init(testing.allocator);
    defer config.deinit();

    var state = EmulationState.init(&config);
    defer state.deinit();
    state.reset();

    // Setup: LDA #$1E, STA $2001
    state.bus.ram[0] = 0xA9; // LDA immediate
    state.bus.ram[1] = 0x1E; // 0x1E = show background + sprites
    state.bus.ram[2] = 0x8D; // STA absolute
    state.bus.ram[3] = 0x01; // Low byte of $2001
    state.bus.ram[4] = 0x20; // High byte of $2001
    state.cpu.pc = 0x0000;

    // Execute LDA + STA (18 PPU cycles total)
    var ppu_cycles: usize = 0;
    while (ppu_cycles < 18) : (ppu_cycles += 1) {
        state.tick();
    }

    // Verify PPUMASK was written correctly
    // 0x1E = 00011110 binary
    try testing.expectEqual(true, state.ppu.mask.show_bg);
    try testing.expectEqual(true, state.ppu.mask.show_sprites);
    try testing.expectEqual(true, state.ppu.mask.show_bg_left);
    try testing.expectEqual(true, state.ppu.mask.show_sprites_left);
}

test "Absolute mode: Multiple PPUADDR writes set correct address" {
    var config = Config.Config.init(testing.allocator);
    defer config.deinit();

    var state = EmulationState.init(&config);
    defer state.deinit();
    state.reset();

    // Setup: Write $23 then $C0 to PPUADDR to set address to $23C0
    // LDA #$23, STA $2006, LDA #$C0, STA $2006
    state.bus.ram[0] = 0xA9; // LDA #$23
    state.bus.ram[1] = 0x23;
    state.bus.ram[2] = 0x8D; // STA $2006
    state.bus.ram[3] = 0x06;
    state.bus.ram[4] = 0x20;
    state.bus.ram[5] = 0xA9; // LDA #$C0
    state.bus.ram[6] = 0xC0;
    state.bus.ram[7] = 0x8D; // STA $2006
    state.bus.ram[8] = 0x06;
    state.bus.ram[9] = 0x20;
    state.cpu.pc = 0x0000;

    // Execute first LDA + STA (18 PPU cycles)
    var ppu_cycles: usize = 0;
    while (ppu_cycles < 18) : (ppu_cycles += 1) {
        state.tick();
    }

    // Execute second LDA + STA (18 PPU cycles)
    ppu_cycles = 0;
    while (ppu_cycles < 18) : (ppu_cycles += 1) {
        state.tick();
    }

    // Verify VRAM address is $23C0
    try testing.expectEqual(@as(u16, 0x23C0), state.ppu.internal.v);
}

test "Absolute mode: PPUDATA writes populate VRAM" {
    var config = Config.Config.init(testing.allocator);
    defer config.deinit();

    var state = EmulationState.init(&config);
    defer state.deinit();
    state.reset();

    // Setup: Set PPUADDR to $2000, then write $AA to PPUDATA
    state.bus.ram[0] = 0xA9; // LDA #$20
    state.bus.ram[1] = 0x20;
    state.bus.ram[2] = 0x8D; // STA $2006 (high byte)
    state.bus.ram[3] = 0x06;
    state.bus.ram[4] = 0x20;
    state.bus.ram[5] = 0xA9; // LDA #$00
    state.bus.ram[6] = 0x00;
    state.bus.ram[7] = 0x8D; // STA $2006 (low byte)
    state.bus.ram[8] = 0x06;
    state.bus.ram[9] = 0x20;
    state.bus.ram[10] = 0xA9; // LDA #$AA
    state.bus.ram[11] = 0xAA;
    state.bus.ram[12] = 0x8D; // STA $2007 (PPUDATA)
    state.bus.ram[13] = 0x07;
    state.bus.ram[14] = 0x20;
    state.cpu.pc = 0x0000;

    // Execute first LDA + STA (18 PPU cycles)
    var ppu_cycles: usize = 0;
    while (ppu_cycles < 18) : (ppu_cycles += 1) {
        state.tick();
    }

    // Execute second LDA + STA (18 PPU cycles)
    ppu_cycles = 0;
    while (ppu_cycles < 18) : (ppu_cycles += 1) {
        state.tick();
    }

    // Execute third LDA + STA (18 PPU cycles)
    ppu_cycles = 0;
    while (ppu_cycles < 18) : (ppu_cycles += 1) {
        state.tick();
    }

    // Read VRAM directly to verify write
    const vram_value = state.ppu.vram[0x0000]; // $2000 maps to VRAM $0000 with mirroring

    try testing.expectEqual(@as(u8, 0xAA), vram_value);
}
