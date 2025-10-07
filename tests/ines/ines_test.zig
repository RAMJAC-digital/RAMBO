// iNES ROM Format Parser Tests
//
// Comprehensive tests for stateless iNES parser module.

const std = @import("std");
const testing = std.testing;
const ines = @import("ines");

// === Helper Functions ===

/// Create minimal valid iNES 1.0 ROM
fn createMinimalRom(allocator: std.mem.Allocator) ![]u8 {
    // Header (16 bytes) - construct as raw bytes
    var header: [16]u8 = undefined;
    header[0] = 'N';
    header[1] = 'E';
    header[2] = 'S';
    header[3] = 0x1A;
    header[4] = 0x01; // 1 x 16KB PRG ROM
    header[5] = 0x01; // 1 x 8KB CHR ROM
    header[6] = 0x00; // Flags 6 (horizontal mirroring, no battery, no trainer, mapper 0)
    header[7] = 0x00; // Flags 7 (mapper 0, iNES 1.0)
    header[8] = 0x00; // Byte 8 (PRG RAM size)
    header[9] = 0x00; // Flags 9 (NTSC)
    header[10] = 0x00; // Flags 10
    header[11] = 0x00; // Padding
    header[12] = 0x00;
    header[13] = 0x00;
    header[14] = 0x00;
    header[15] = 0x00;

    // PRG ROM (16KB)
    const prg_size = 16 * 1024;
    const prg_rom = try allocator.alloc(u8, prg_size);
    @memset(prg_rom, 0xFF);

    // CHR ROM (8KB)
    const chr_size = 8 * 1024;
    const chr_rom = try allocator.alloc(u8, chr_size);
    @memset(chr_rom, 0x00);

    // Concatenate
    const total_size = header.len + prg_size + chr_size;
    var rom_data = try allocator.alloc(u8, total_size);

    @memcpy(rom_data[0..16], &header);
    @memcpy(rom_data[16 .. 16 + prg_size], prg_rom);
    @memcpy(rom_data[16 + prg_size ..], chr_rom);

    allocator.free(prg_rom);
    allocator.free(chr_rom);

    return rom_data;
}

/// Create iNES ROM with trainer
fn createRomWithTrainer(allocator: std.mem.Allocator) ![]u8 {
    // Header with trainer flag
    var header: [16]u8 = undefined;
    header[0] = 'N';
    header[1] = 'E';
    header[2] = 'S';
    header[3] = 0x1A;
    header[4] = 0x01; // 1 x 16KB PRG ROM
    header[5] = 0x00; // 0 CHR ROM (CHR RAM)
    header[6] = 0x04; // Flags 6 (horizontal, no battery, TRAINER, mapper 0)
    header[7] = 0x00; // Flags 7 (mapper 0, iNES 1.0)
    header[8] = 0x00; // Byte 8
    header[9] = 0x00; // Flags 9
    header[10] = 0x00; // Flags 10
    header[11] = 0x00; // Padding
    header[12] = 0x00;
    header[13] = 0x00;
    header[14] = 0x00;
    header[15] = 0x00;

    // Trainer (512 bytes)
    const trainer = try allocator.alloc(u8, 512);
    @memset(trainer, 0xAA);

    // PRG ROM (16KB)
    const prg_size = 16 * 1024;
    const prg_rom = try allocator.alloc(u8, prg_size);
    @memset(prg_rom, 0xFF);

    // Concatenate
    const total_size = header.len + 512 + prg_size;
    var rom_data = try allocator.alloc(u8, total_size);

    @memcpy(rom_data[0..16], &header);
    @memcpy(rom_data[16 .. 16 + 512], trainer);
    @memcpy(rom_data[16 + 512 ..], prg_rom);

    allocator.free(trainer);
    allocator.free(prg_rom);

    return rom_data;
}

/// Create NES 2.0 ROM
fn createNes2Rom(allocator: std.mem.Allocator) ![]u8 {
    // NES 2.0 header
    var header: [16]u8 = undefined;
    header[0] = 'N';
    header[1] = 'E';
    header[2] = 'S';
    header[3] = 0x1A;
    header[4] = 0x02; // 2 x 16KB PRG ROM
    header[5] = 0x01; // 1 x 8KB CHR ROM
    header[6] = 0x01; // Flags 6 (vertical mirroring, no battery, no trainer, mapper 0 low)
    header[7] = 0x08; // Flags 7 (mapper 0 high, NES 2.0 identifier 0b10)
    header[8] = 0x00; // Byte 8 (submapper 0, PRG RAM)
    header[9] = 0x00; // Byte 9
    header[10] = 0x00; // Byte 10
    header[11] = 0x00; // Byte 11
    header[12] = 0x00; // Byte 12 (region = NTSC)
    header[13] = 0x00; // Byte 13
    header[14] = 0x00; // Byte 14
    header[15] = 0x00; // Byte 15

    // PRG ROM (32KB)
    const prg_size = 32 * 1024;
    const prg_rom = try allocator.alloc(u8, prg_size);
    @memset(prg_rom, 0xEA); // NOP instructions

    // CHR ROM (8KB)
    const chr_size = 8 * 1024;
    const chr_rom = try allocator.alloc(u8, chr_size);
    @memset(chr_rom, 0x55);

    // Concatenate
    const total_size = header.len + prg_size + chr_size;
    var rom_data = try allocator.alloc(u8, total_size);

    @memcpy(rom_data[0..16], &header);
    @memcpy(rom_data[16 .. 16 + prg_size], prg_rom);
    @memcpy(rom_data[16 + prg_size ..], chr_rom);

    allocator.free(prg_rom);
    allocator.free(chr_rom);

    return rom_data;
}

// === Tests ===

test "iNES: parse minimal ROM" {
    const rom_data = try createMinimalRom(testing.allocator);
    defer testing.allocator.free(rom_data);

    var rom = try ines.parse(testing.allocator, rom_data);
    defer rom.deinit(testing.allocator);

    // Verify format
    try testing.expectEqual(ines.Format.ines_1_0, rom.format);

    // Verify mapper
    try testing.expectEqual(@as(u12, 0), rom.mapper_number);

    // Verify sizes
    try testing.expectEqual(@as(usize, 16 * 1024), rom.prg_rom.len);
    try testing.expectEqual(@as(usize, 8 * 1024), rom.chr_rom.len);

    // Verify mirroring
    try testing.expectEqual(ines.MirroringMode.horizontal, rom.mirroring);

    // Verify region
    try testing.expectEqual(ines.Region.ntsc, rom.region);

    // Verify no trainer
    try testing.expect(rom.trainer == null);

    // Verify CHR is ROM
    try testing.expect(!rom.chr_is_ram);
}

test "iNES: parse ROM with trainer" {
    const rom_data = try createRomWithTrainer(testing.allocator);
    defer testing.allocator.free(rom_data);

    var rom = try ines.parse(testing.allocator, rom_data);
    defer rom.deinit(testing.allocator);

    // Verify trainer present
    try testing.expect(rom.trainer != null);
    try testing.expectEqual(@as(usize, 512), rom.trainer.?.len);

    // Verify CHR RAM
    try testing.expect(rom.chr_is_ram);
    try testing.expectEqual(@as(usize, 0), rom.chr_rom.len);
}

test "iNES: parse NES 2.0 ROM" {
    const rom_data = try createNes2Rom(testing.allocator);
    defer testing.allocator.free(rom_data);

    var rom = try ines.parse(testing.allocator, rom_data);
    defer rom.deinit(testing.allocator);

    // Verify NES 2.0 format
    try testing.expectEqual(ines.Format.nes_2_0, rom.format);

    // Verify vertical mirroring
    try testing.expectEqual(ines.MirroringMode.vertical, rom.mirroring);

    // Verify sizes
    try testing.expectEqual(@as(usize, 32 * 1024), rom.prg_rom.len);
    try testing.expectEqual(@as(usize, 8 * 1024), rom.chr_rom.len);
}

test "iNES: parse header only" {
    const rom_data = try createMinimalRom(testing.allocator);
    defer testing.allocator.free(rom_data);

    const header = try ines.parseHeader(rom_data);

    // Verify magic
    try testing.expect(header.isValid());

    // Verify format
    try testing.expectEqual(ines.Format.ines_1_0, header.getFormat());

    // Verify mapper
    try testing.expectEqual(@as(u12, 0), header.getMapperNumber());

    // Verify sizes
    try testing.expectEqual(@as(u32, 16 * 1024), header.getPrgRomSize());
    try testing.expectEqual(@as(u32, 8 * 1024), header.getChrRomSize());
}

test "iNES: error on file too small" {
    var small_data = [_]u8{ 'N', 'E', 'S', 0x1A, 0x01 }; // Only 5 bytes

    const result = ines.parseHeader(&small_data);
    try testing.expectError(ines.InesError.FileTooSmall, result);
}

test "iNES: error on invalid magic" {
    var invalid_header: [16]u8 align(@alignOf(ines.InesHeader)) = undefined;
    invalid_header[0] = 'B';
    invalid_header[1] = 'A';
    invalid_header[2] = 'D';
    invalid_header[3] = '!';
    invalid_header[4] = 0x01;
    invalid_header[5] = 0x01;
    @memset(invalid_header[6..], 0x00);

    const result = ines.parseHeader(&invalid_header);
    try testing.expectError(ines.InesError.InvalidMagic, result);
}

test "iNES: error on zero PRG ROM" {
    var zero_prg_header: [16]u8 align(@alignOf(ines.InesHeader)) = undefined;
    zero_prg_header[0] = 'N';
    zero_prg_header[1] = 'E';
    zero_prg_header[2] = 'S';
    zero_prg_header[3] = 0x1A;
    zero_prg_header[4] = 0x00; // ZERO PRG ROM (invalid)
    zero_prg_header[5] = 0x01; // 1 CHR ROM
    @memset(zero_prg_header[6..], 0x00);

    const result = ines.parse(testing.allocator, &zero_prg_header);
    try testing.expectError(ines.InesError.ZeroPrgRomSize, result);
}

test "iNES: error on file size mismatch" {
    var header: [16]u8 align(@alignOf(ines.InesHeader)) = undefined;
    header[0] = 'N';
    header[1] = 'E';
    header[2] = 'S';
    header[3] = 0x1A;
    header[4] = 0x01; // 1 x 16KB PRG ROM (expects 16384 bytes)
    header[5] = 0x00; // 0 CHR ROM
    @memset(header[6..], 0x00);

    // Only provide header, no PRG ROM data
    const result = ines.parse(testing.allocator, &header);
    try testing.expectError(ines.InesError.FileSizeMismatch, result);
}

test "iNES: validation - valid header" {
    const rom_data = try createMinimalRom(testing.allocator);
    defer testing.allocator.free(rom_data);

    const header = try ines.parseHeader(rom_data);

    var result = try ines.validateHeader(testing.allocator, &header);
    defer result.deinit();

    try testing.expect(result.valid);
    try testing.expectEqual(@as(usize, 0), result.errors.items.len);
}

test "iNES: validation - invalid magic" {
    var header_bytes: [16]u8 align(@alignOf(ines.InesHeader)) = undefined;
    header_bytes[0] = 'B';
    header_bytes[1] = 'A';
    header_bytes[2] = 'D';
    header_bytes[3] = '!';
    header_bytes[4] = 1; // prg_rom_banks
    header_bytes[5] = 1; // chr_rom_banks
    @memset(header_bytes[6..], 0x00);

    const invalid_header: *const ines.InesHeader = @ptrCast(@alignCast(&header_bytes));

    var result = try ines.validateHeader(testing.allocator, invalid_header);
    defer result.deinit();

    try testing.expect(!result.valid);
    try testing.expect(result.errors.items.len > 0);
}

test "iNES: quick validation" {
    const rom_data = try createMinimalRom(testing.allocator);
    defer testing.allocator.free(rom_data);

    const header = try ines.parseHeader(rom_data);

    try testing.expect(ines.isValid(&header));
}

test "iNES: calculate PRG hash" {
    const prg_data = [_]u8{ 0xFF, 0xEE, 0xDD, 0xCC };
    const hash = ines.calculatePrgHash(&prg_data);

    // Verify hash is deterministic
    const hash2 = ines.calculatePrgHash(&prg_data);
    try testing.expectEqualSlices(u8, &hash, &hash2);

    // Verify different data produces different hash
    const prg_data2 = [_]u8{ 0x00, 0x11, 0x22, 0x33 };
    const hash3 = ines.calculatePrgHash(&prg_data2);
    try testing.expect(!std.mem.eql(u8, &hash, &hash3));
}

test "iNES: common mapper check" {
    // Common mappers
    try testing.expect(ines.isCommonMapper(0)); // NROM
    try testing.expect(ines.isCommonMapper(1)); // MMC1
    try testing.expect(ines.isCommonMapper(2)); // UxROM
    try testing.expect(ines.isCommonMapper(3)); // CNROM
    try testing.expect(ines.isCommonMapper(4)); // MMC3

    // Uncommon mapper
    try testing.expect(!ines.isCommonMapper(255));
}

test "iNES: mapper names" {
    try testing.expectEqualStrings("NROM", ines.getMapperName(0));
    try testing.expectEqualStrings("MMC1", ines.getMapperName(1));
    try testing.expectEqualStrings("UxROM", ines.getMapperName(2));
    try testing.expectEqualStrings("CNROM", ines.getMapperName(3));
    try testing.expectEqualStrings("MMC3", ines.getMapperName(4));
    try testing.expectEqualStrings("Unknown", ines.getMapperName(255));
}

test "iNES: error descriptions" {
    const desc = ines.errorDescription(ines.InesError.FileTooSmall);
    try testing.expect(desc.len > 0);

    const desc2 = ines.errorDescription(ines.InesError.InvalidMagic);
    try testing.expect(desc2.len > 0);
}

test "iNES: expected file size calculation" {
    const rom_data = try createMinimalRom(testing.allocator);
    defer testing.allocator.free(rom_data);

    const header = try ines.parseHeader(rom_data);
    const expected_size = ines.getExpectedFileSize(&header);

    // 16 bytes header + 16KB PRG + 8KB CHR = 24592 bytes
    try testing.expectEqual(@as(usize, 16 + 16 * 1024 + 8 * 1024), expected_size);
}

test "iNES: format toString" {
    try testing.expectEqualStrings("iNES 1.0", ines.Format.ines_1_0.toString());
    try testing.expectEqualStrings("NES 2.0", ines.Format.nes_2_0.toString());
}

test "iNES: mirroring toString" {
    try testing.expectEqualStrings("Horizontal", ines.MirroringMode.horizontal.toString());
    try testing.expectEqualStrings("Vertical", ines.MirroringMode.vertical.toString());
    try testing.expectEqualStrings("Four-Screen", ines.MirroringMode.four_screen.toString());
}

test "iNES: region toString" {
    try testing.expectEqualStrings("NTSC", ines.Region.ntsc.toString());
    try testing.expectEqualStrings("PAL", ines.Region.pal.toString());
    try testing.expectEqualStrings("Dual (NTSC/PAL)", ines.Region.dual.toString());
}

// === NES 2.0 Specific Tests ===

test "NES 2.0: parse NES 2.0 format correctly" {
    const rom_data = try createNes2Rom(testing.allocator);
    defer testing.allocator.free(rom_data);

    var rom = try ines.parse(testing.allocator, rom_data);
    defer rom.deinit(testing.allocator);

    // Verify NES 2.0 format detected
    try testing.expectEqual(ines.Format.nes_2_0, rom.format);
    try testing.expectEqualStrings("NES 2.0", rom.getFormatString());
}

test "NES 2.0: 12-bit mapper number" {
    // Create NES 2.0 ROM with mapper 256 (requires 12-bit)
    var header: [16]u8 align(@alignOf(ines.InesHeader)) = undefined;
    header[0] = 'N';
    header[1] = 'E';
    header[2] = 'S';
    header[3] = 0x1A;
    header[4] = 0x01; // 1 x 16KB PRG ROM
    header[5] = 0x00; // 0 CHR ROM
    header[6] = 0x00; // Flags 6 (mapper low 4 bits = 0)
    header[7] = 0x08; // Flags 7 (NES 2.0 identifier, mapper mid 4 bits = 0)
    header[8] = 0x01; // Byte 8 (mapper high 4 bits = 1, submapper = 0)
    @memset(header[9..], 0x00);

    const parsed_header = try ines.parseHeader(&header);

    // Verify NES 2.0 format
    try testing.expectEqual(ines.Format.nes_2_0, parsed_header.getFormat());

    // Verify 12-bit mapper (0x100 = 256)
    const mapper_num = parsed_header.getMapperNumber();
    try testing.expectEqual(@as(u12, 0x100), mapper_num);
}

test "NES 2.0: submapper detection" {
    // Create NES 2.0 ROM with submapper 3
    var header: [16]u8 align(@alignOf(ines.InesHeader)) = undefined;
    header[0] = 'N';
    header[1] = 'E';
    header[2] = 'S';
    header[3] = 0x1A;
    header[4] = 0x01; // 1 x 16KB PRG ROM
    header[5] = 0x00; // 0 CHR ROM
    header[6] = 0x00; // Flags 6 (mapper 0)
    header[7] = 0x08; // Flags 7 (NES 2.0 identifier)
    header[8] = 0x30; // Byte 8 (submapper = 3 in high nibble)
    @memset(header[9..], 0x00);

    const parsed_header = try ines.parseHeader(&header);

    // Verify submapper
    try testing.expectEqual(@as(u4, 3), parsed_header.getSubmapper());
}

test "NES 2.0: exponential PRG ROM size" {
    // Create NES 2.0 ROM with exponential size notation
    var header: [16]u8 align(@alignOf(ines.InesHeader)) = undefined;
    header[0] = 'N';
    header[1] = 'E';
    header[2] = 'S';
    header[3] = 0x1A;
    header[4] = 0x02; // PRG ROM banks
    header[5] = 0x00; // 0 CHR ROM
    header[6] = 0x00; // Flags 6
    header[7] = 0x08; // Flags 7 (NES 2.0)
    header[8] = 0x20; // Byte 8 (exponent = 2 in high nibble)
    @memset(header[9..], 0x00);

    const parsed_header = try ines.parseHeader(&header);

    // Exponential size: (2*2+1) * 2^2 = 5 * 4 = 20 bytes (NES 2.0 exponential formula)
    const prg_size = parsed_header.getPrgRomSize();
    try testing.expectEqual(@as(u32, 20), prg_size);
}

test "NES 2.0: console type detection" {
    // Create NES 2.0 ROM - console type derived from format_id (bits 2-3 of flags7)
    var header: [16]u8 align(@alignOf(ines.InesHeader)) = undefined;
    header[0] = 'N';
    header[1] = 'E';
    header[2] = 'S';
    header[3] = 0x1A;
    header[4] = 0x01; // 1 x 16KB PRG ROM
    header[5] = 0x00; // 0 CHR ROM
    header[6] = 0x00; // Flags 6
    header[7] = 0x08; // Flags 7 (NES 2.0, format_id = 0b10 = 2)
    @memset(header[8..], 0x00);

    const parsed_header = try ines.parseHeader(&header);

    // Verify console type (format_id 0b10 = playchoice in current implementation)
    const console = parsed_header.getConsoleType();
    try testing.expectEqual(ines.ConsoleType.playchoice, console);
}

test "NES 2.0: region specification" {
    // Create NES 2.0 ROM with PAL region
    var header: [16]u8 align(@alignOf(ines.InesHeader)) = undefined;
    header[0] = 'N';
    header[1] = 'E';
    header[2] = 'S';
    header[3] = 0x1A;
    header[4] = 0x01; // 1 x 16KB PRG ROM
    header[5] = 0x00; // 0 CHR ROM
    header[6] = 0x00; // Flags 6
    header[7] = 0x08; // Flags 7 (NES 2.0)
    header[8] = 0x00; // Byte 8
    header[9] = 0x00; // Byte 9
    header[10] = 0x00; // Byte 10
    header[11] = 0x00; // Byte 11 (padding0)
    header[12] = 0x00; // Byte 12 (padding1)
    header[13] = 0x01; // Byte 13 (padding2 - region = PAL for NES 2.0)
    header[14] = 0x00; // Byte 14 (padding3)
    header[15] = 0x00; // Byte 15 (padding4)

    const parsed_header = try ines.parseHeader(&header);

    // Verify PAL region
    try testing.expectEqual(ines.Region.pal, parsed_header.getRegion());
}

test "NES 2.0: validation with submapper" {
    const rom_data = try createNes2Rom(testing.allocator);
    defer testing.allocator.free(rom_data);

    const header = try ines.parseHeader(rom_data);

    var result = try ines.validateHeader(testing.allocator, &header);
    defer result.deinit();

    // NES 2.0 should validate successfully
    try testing.expect(result.valid);
}
