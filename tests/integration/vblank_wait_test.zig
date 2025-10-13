//! VBlank Wait Loop Integration Test
//!
//! Verifies that a ROM can successfully wait for VBlank by polling $2002.

const std = @import("std");
const testing = std.testing;
const RAMBO = @import("RAMBO");
const Harness = RAMBO.TestHarness.Harness;

fn createVBlankWaitRom() ![]u8 {
    const header = [_]u8{ 0x4E, 0x45, 0x53, 0x1A, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 };
    const header_size = header.len;
    const prg_size = 16384;
    const chr_size = 8192;
    const total_size = header_size + prg_size + chr_size;

    var rom_data = try std.testing.allocator.alloc(u8, total_size);
    errdefer std.testing.allocator.free(rom_data);

    @memset(rom_data, 0);
    @memcpy(rom_data[0..header_size], header[0..]);

    // PRG ROM: fill with NOPs
    const prg_start = header_size;
    @memset(rom_data[prg_start .. prg_start + prg_size], 0xEA);

    // Program code at start of PRG ROM
    const code = [_]u8{
        0x2C, 0x02, 0x20, // BIT $2002
        0x10, 0xFB,       // BPL -5
        0xA9, 0x1E,       // LDA #$1E
        0x8D, 0x01, 0x20, // STA $2001 (PPUMASK)
        0x4C, 0x0D, 0x80, // JMP $800D
    };
    @memcpy(rom_data[prg_start .. prg_start + code.len], code[0..]);

    // Reset vector at end of PRG ROM region
    const reset_vector_offset = prg_start + prg_size - 4;
    rom_data[reset_vector_offset + 0] = 0x00;
    rom_data[reset_vector_offset + 1] = 0x80;

    return rom_data;
}

test "VBlank Wait Loop: ROM successfully waits for and detects VBlank" {
    const rom_data = try createVBlankWaitRom();
    defer std.testing.allocator.free(rom_data);

    var h = try Harness.initWithRom(rom_data);
    defer h.deinit();

    // Run for 2 frames, which should be more than enough time for the
    // ROM to wait for VBlank and enable rendering.
    h.runCpuCycles(60000);

    // Check if rendering was enabled
    const mask_byte: u8 = @bitCast(h.state.ppu.mask);
    try testing.expectEqual(@as(u8, 0x1E), mask_byte);
}
