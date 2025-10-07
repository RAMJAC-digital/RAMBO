//! VBlank Wait Loop Integration Test
//!
//! This test verifies that ROMs can successfully wait for VBlank by polling $2002.
//! This is a critical pattern used by nearly all NES ROMs during initialization.
//!
//! The test creates a minimal ROM that:
//! 1. Waits for VBlank by polling bit 7 of $2002 (PPUSTATUS)
//! 2. Writes to $2000/$2001 after VBlank detected
//! 3. Enters infinite loop
//!
//! This test catches the regression where CPU gets stuck in VBlank wait loop.

const std = @import("std");
const testing = std.testing;
const RAMBO = @import("RAMBO");

const EmulationState = RAMBO.EmulationState.EmulationState;
const Config = RAMBO.Config;
const NromCart = RAMBO.CartridgeType;
const AnyCartridge = RAMBO.AnyCartridge;

/// Create a minimal test ROM that waits for VBlank
/// ROM structure:
///   - PRG ROM: 16KB (one bank)
///   - CHR ROM: 8KB
///   - Reset vector: $8000
///   - Code at $8000: Wait for VBlank, then write to PPU registers
fn createVBlankWaitRom(allocator: std.mem.Allocator) ![]u8 {
    // iNES header (16 bytes)
    var rom = try std.ArrayList(u8).initCapacity(allocator, 16 + 16384 + 8192);
    errdefer rom.deinit(allocator);

    // iNES header
    try rom.appendSlice(allocator, &[_]u8{
        'N', 'E', 'S', 0x1A, // Magic
        1,                    // 1 x 16KB PRG ROM
        1,                    // 1 x 8KB CHR ROM
        0,                    // Mapper 0 (NROM), horizontal mirroring
        0,                    // Mapper 0 (upper bits)
        0, 0, 0, 0, 0, 0, 0, 0, // Padding
    });

    // PRG ROM (16KB)
    try rom.resize(allocator, 16 + 16384);
    @memset(rom.items[16..], 0xEA); // Fill with NOP

    // Code starts at $8000 (file offset 16)
    const code_offset = 16;
    var code = try std.ArrayList(u8).initCapacity(allocator, 256);
    defer code.deinit(allocator);

    // Wait for VBlank loop:
    // :vblankwait1
    //   BIT $2002    ; Test bit 7 of PPUSTATUS
    //   BPL vblankwait1  ; Loop while bit 7 = 0 (not in VBlank)
    try code.appendSlice(allocator, &[_]u8{
        0x2C, 0x02, 0x20, // BIT $2002
        0x10, 0xFB,       // BPL -5 (loop back to BIT)
    });

    // After VBlank detected, write to PPU control registers
    try code.appendSlice(allocator, &[_]u8{
        0xA9, 0x80,       // LDA #$80 (enable NMI)
        0x8D, 0x00, 0x20, // STA $2000 (PPUCTRL)
        0xA9, 0x1E,       // LDA #$1E (enable rendering)
        0x8D, 0x01, 0x20, // STA $2001 (PPUMASK)
    });

    // Write success marker to $6000 (for test verification)
    try code.appendSlice(allocator, &[_]u8{
        0xA9, 0x42,       // LDA #$42
        0x8D, 0x00, 0x60, // STA $6000
    });

    // Infinite loop (test passed)
    try code.appendSlice(allocator, &[_]u8{
        0x4C, 0x1C, 0x80, // JMP $801C (self-loop)
    });

    // Copy code to ROM
    @memcpy(rom.items[code_offset .. code_offset + code.items.len], code.items);

    // Reset vector at $FFFC points to $8000
    rom.items[code_offset + 0x3FFC] = 0x00; // Low byte
    rom.items[code_offset + 0x3FFD] = 0x80; // High byte

    // CHR ROM (8KB) - can be empty for this test
    try rom.resize(allocator, 16 + 16384 + 8192);
    @memset(rom.items[16 + 16384 ..], 0x00);

    return rom.toOwnedSlice(allocator);
}

test "VBlank Wait Loop: CPU successfully waits for and detects VBlank" {
    // Create test ROM
    const rom_data = try createVBlankWaitRom(testing.allocator);
    defer testing.allocator.free(rom_data);

    // Load ROM
    const cart = try NromCart.loadFromData(testing.allocator, rom_data);
    const any_cart = AnyCartridge{ .nrom = cart };

    // Initialize emulation
    var config = Config.Config.init(testing.allocator);
    defer config.deinit();

    var state = EmulationState.init(&config);
    defer state.deinit();

    state.loadCartridge(any_cart);
    state.reset();

    std.debug.print("\n[VBlank Wait Test] Starting emulation\n", .{});
    std.debug.print("  Reset vector: PC=0x{x:0>4}\n", .{state.cpu.pc});

    // DEBUG: Verify ROM code is loaded correctly
    std.debug.print("  Code at 0x8000: {x:0>2} {x:0>2} {x:0>2} {x:0>2} {x:0>2}\n", .{
        state.busRead(0x8000),
        state.busRead(0x8001),
        state.busRead(0x8002),
        state.busRead(0x8003),
        state.busRead(0x8004),
    });
    std.debug.print("  Expected:       2C 02 20 10 FB (BIT $2002, BPL -5)\n", .{});

    // Run emulation for maximum 2 frames (should complete in ~1 frame)
    const max_cycles: u64 = 89342 * 2; // 2 NTSC frames
    var cycles: u64 = 0;
    var instruction_count: usize = 0;
    const max_instructions: usize = 10000; // Safety limit

    // Track state transitions to count actual instructions (not PPU cycles)
    var last_cpu_state: @TypeOf(state.cpu.state) = state.cpu.state;
    var vblank_seen = false;

    while (cycles < max_cycles and instruction_count < max_instructions) {
        // Check for VBlank and log first BIT $2002 after VBlank
        if (!vblank_seen and state.ppu.status.vblank) {
            std.debug.print("  ✓ VBlank flag SET at scanline {d}, dot {d}, cycle {d}\n", .{
                state.ppu_timing.scanline,
                state.ppu_timing.dot,
                cycles,
            });
            vblank_seen = true;
        }

        state.tick();
        cycles += 1;

        // Count instructions by detecting TRANSITIONS to fetch_opcode
        // This avoids counting the same instruction 3 times (once per PPU cycle)
        if (state.cpu.state == .fetch_opcode and last_cpu_state != .fetch_opcode) {
            instruction_count += 1;

            // Log first few BIT instructions after VBlank
            if (vblank_seen and instruction_count >= 2740 and instruction_count <= 2750) {
                std.debug.print("  → Instruction {d}: PC=0x{x:0>4}, A=0x{x:0>2}, N={}, VBlank={}\n", .{
                    instruction_count,
                    state.cpu.pc,
                    state.cpu.a,
                    state.cpu.p.negative,
                    state.ppu.status.vblank,
                });
            }

            // Check success marker every 100 instructions
            if (instruction_count % 100 == 0) {
                const marker = state.busRead(0x6000);
                if (marker == 0x42) {
                    std.debug.print("  ✓ Success marker detected after {d} instructions\n", .{instruction_count});
                    std.debug.print("  ✓ PPU CTRL: 0x{x:0>2}\n", .{state.ppu.ctrl.toByte()});
                    std.debug.print("  ✓ PPU MASK: 0x{x:0>2}\n", .{state.ppu.mask.toByte()});

                    // Verify PPU registers were set correctly
                    try testing.expectEqual(@as(u8, 0x80), state.ppu.ctrl.toByte());
                    try testing.expectEqual(@as(u8, 0x1E), state.ppu.mask.toByte());
                    return; // Test passed!
                }
            }
        }

        last_cpu_state = state.cpu.state;
    }

    // If we get here, test failed
    std.debug.print("  ✗ FAILED: VBlank wait loop did not complete\n", .{});
    std.debug.print("  Final PC: 0x{x:0>4}\n", .{state.cpu.pc});
    std.debug.print("  Cycles: {d}\n", .{cycles});
    std.debug.print("  Instructions: {d}\n", .{instruction_count});
    std.debug.print("  PPU Status VBlank: {}\n", .{state.ppu.status.vblank});
    std.debug.print("  PPU Scanline: {d}\n", .{state.ppu_timing.scanline});
    std.debug.print("  PPU Dot: {d}\n", .{state.ppu_timing.dot});

    return error.VBlankWaitTimeout;
}
