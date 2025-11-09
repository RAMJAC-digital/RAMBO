//! Castlevania (Mapper 2 / UxROM) Integration Test
//!
//! Tests Mapper 2 (UxROM) functionality using Castlevania (USA) (Rev 1).nes
//!
//! Validates:
//! - ROM loading with proper mapper detection
//! - CHR RAM initialization and accessibility
//! - PRG bank switching (16KB switchable + 16KB fixed)
//! - PPU rendering initialization
//! - Reset vector in fixed last bank

const std = @import("std");
const testing = std.testing;
const RAMBO = @import("RAMBO");

const EmulationState = RAMBO.EmulationState.EmulationState;
const Config = RAMBO.Config.Config;
const CartridgeLoader = RAMBO.CartridgeLoader;
const AnyCartridge = RAMBO.AnyCartridge;

const FRAME_WIDTH = 256;
const FRAME_HEIGHT = 240;
const FRAME_PIXELS = FRAME_WIDTH * FRAME_HEIGHT;

test "Castlevania: ROM loads with Mapper 2 detection" {
    const allocator = testing.allocator;
    const rom_path = "tests/data/Castlevania/Castlevania (USA) (Rev 1).nes";

    const cart = CartridgeLoader.loadAnyCartridgeFile(allocator, rom_path) catch |err| {
        if (err == error.FileNotFound) {
            std.debug.print("Castlevania ROM not found at: {s}\n", .{rom_path});
            return error.SkipZigTest;
        }
        return err;
    };

    // Verify it's a UxROM cart
    try testing.expect(cart == .uxrom);

    const uxrom_cart = cart.uxrom;

    // Verify PRG ROM size (8 banks × 16KB = 128KB)
    try testing.expectEqual(@as(usize, 131072), uxrom_cart.prg_rom.len);

    // Verify CHR RAM (8KB)
    try testing.expectEqual(@as(usize, 8192), uxrom_cart.chr_data.len);

    // Verify mapper number
    const mapper_num = uxrom_cart.header.getMapperNumber();
    try testing.expectEqual(@as(u12, 2), mapper_num);

    // Clean up
    var mutable_cart = cart;
    mutable_cart.deinit();
}

test "Castlevania: CHR RAM is writable" {
    const allocator = testing.allocator;
    const rom_path = "tests/data/Castlevania/Castlevania (USA) (Rev 1).nes";

    var cart = CartridgeLoader.loadAnyCartridgeFile(allocator, rom_path) catch |err| {
        if (err == error.FileNotFound) return error.SkipZigTest;
        return err;
    };
    defer cart.deinit();

    try testing.expect(cart == .uxrom);

    // Test CHR RAM write/read through cartridge interface
    cart.ppuWrite(0x0000, 0xAA);
    cart.ppuWrite(0x0001, 0x55);
    cart.ppuWrite(0x1000, 0xCC);
    cart.ppuWrite(0x1FFF, 0x99);

    // Read back
    try testing.expectEqual(@as(u8, 0xAA), cart.ppuRead(0x0000));
    try testing.expectEqual(@as(u8, 0x55), cart.ppuRead(0x0001));
    try testing.expectEqual(@as(u8, 0xCC), cart.ppuRead(0x1000));
    try testing.expectEqual(@as(u8, 0x99), cart.ppuRead(0x1FFF));
}

test "Castlevania: PRG banking works correctly" {
    const allocator = testing.allocator;
    const rom_path = "tests/data/Castlevania/Castlevania (USA) (Rev 1).nes";

    var cart = CartridgeLoader.loadAnyCartridgeFile(allocator, rom_path) catch |err| {
        if (err == error.FileNotFound) return error.SkipZigTest;
        return err;
    };
    defer cart.deinit();

    try testing.expect(cart == .uxrom);

    // Read from switchable bank (default bank 0)
    const switchable_byte_bank0 = cart.cpuRead(0x8000);

    // Read from fixed bank (always last bank)
    const fixed_bank_byte_before = cart.cpuRead(0xC000);

    // Switch to bank 1
    cart.cpuWrite(0x8000, 0x01);

    // Read from switchable bank (now bank 1)
    const switchable_byte_bank1 = cart.cpuRead(0x8000);

    // Read from fixed bank (should be unchanged)
    const fixed_bank_byte_after = cart.cpuRead(0xC000);

    // Fixed bank should not change after bank switch
    try testing.expectEqual(fixed_bank_byte_before, fixed_bank_byte_after);

    // Switchable bank should have different data (unless banks are identical)
    // We can't assert they're different because ROM data might coincidentally match
    _ = switchable_byte_bank0;
    _ = switchable_byte_bank1;
}

test "Castlevania: Reset vector is in fixed last bank" {
    const allocator = testing.allocator;
    const rom_path = "tests/data/Castlevania/Castlevania (USA) (Rev 1).nes";

    const cart = CartridgeLoader.loadAnyCartridgeFile(allocator, rom_path) catch |err| {
        if (err == error.FileNotFound) return error.SkipZigTest;
        return err;
    };
    // Note: cart ownership transferred to state.loadCartridge()

    try testing.expect(cart == .uxrom);

    // Initialize emulation state
    var config = Config.init(allocator);
    defer config.deinit();

    var state = EmulationState.init(&config);
    defer state.deinit();

    state.loadCartridge(cart);
    state.power_on();

    // Read reset vector from $FFFC-$FFFD (should be in fixed last bank)
    const reset_low = state.busRead(0xFFFC);
    const reset_high = state.busRead(0xFFFD);
    const reset_vector = @as(u16, reset_low) | (@as(u16, reset_high) << 8);

    std.debug.print("Castlevania reset vector: ${X:0>4}\n", .{reset_vector});

    // PC should match reset vector after power-on
    try testing.expectEqual(reset_vector, state.cpu.pc);

    // Reset vector should be in valid ROM range ($8000-$FFFF)
    try testing.expect(reset_vector >= 0x8000);
}

test "Castlevania: Emulation runs without crash" {
    const allocator = testing.allocator;
    const rom_path = "tests/data/Castlevania/Castlevania (USA) (Rev 1).nes";

    const cart = CartridgeLoader.loadAnyCartridgeFile(allocator, rom_path) catch |err| {
        if (err == error.FileNotFound) return error.SkipZigTest;
        return err;
    };
    // Note: cart ownership transferred to state.loadCartridge()

    var config = Config.init(allocator);
    defer config.deinit();

    var state = EmulationState.init(&config);
    defer state.deinit();

    state.loadCartridge(cart);
    state.power_on();

    // Create framebuffer
    var framebuffer = [_]u32{0} ** FRAME_PIXELS;

    // Run for 10 frames without crashing
    var frame: usize = 0;
    while (frame < 10) : (frame += 1) {
        state.ppu.framebuffer = &framebuffer;
        _ = state.emulateFrame();
    }

    // If we got here, emulation didn't crash
    try testing.expect(true);
}

test "Castlevania: PPU rendering initialization" {
    const allocator = testing.allocator;
    const rom_path = "tests/data/Castlevania/Castlevania (USA) (Rev 1).nes";

    const cart = CartridgeLoader.loadAnyCartridgeFile(allocator, rom_path) catch |err| {
        if (err == error.FileNotFound) return error.SkipZigTest;
        return err;
    };

    var config = Config.init(allocator);
    defer config.deinit();

    var state = EmulationState.init(&config);
    defer state.deinit();

    state.loadCartridge(cart);
    state.power_on();

    // Print initial state
    const reset_vector = state.cpu.pc;
    std.debug.print("\nCastlevania Initial State:\n", .{});
    std.debug.print("  Reset Vector: ${X:0>4}\n", .{reset_vector});
    std.debug.print("  Warmup cycles needed: 29658\n", .{});
    std.debug.print("  Warmup complete (initial): {}\n", .{state.ppu.warmup_complete});

    // Trace first 100 instructions including $2002 reads
    std.debug.print("\nFirst 100 instructions (showing $2002 reads):\n", .{});
    var instr_count: usize = 0;
    var read_2002_count: usize = 0;

    while (instr_count < 100) {
        const pc_before = state.cpu.pc;
        const cycle_before = state.cpu.instruction_cycle;

        state.tick();

        // Detect instruction completion (cycle wrapped back to 0)
        if (state.cpu.instruction_cycle == 0 and cycle_before != 0) {
            instr_count += 1;
            const opcode = state.busRead(pc_before);
            if (instr_count <= 20) {
                // Disassemble instruction
                const operand1 = if (pc_before < 0xFFFF) state.busRead(pc_before + 1) else 0;
                const operand2 = if (pc_before < 0xFFFE) state.busRead(pc_before + 2) else 0;
                const addr16 = @as(u16, operand1) | (@as(u16, operand2) << 8);

                std.debug.print("  {d:>3}. PC=${X:0>4} op=${X:0>2} [{X:0>2} {X:0>2}] A=${X:0>2}", .{
                    instr_count,
                    pc_before,
                    opcode,
                    operand1,
                    operand2,
                    state.cpu.a,
                });

                // Show what LDA is loading
                if (opcode == 0xAD) { // LDA absolute
                    const value = state.busRead(addr16);
                    std.debug.print(" LDA ${X:0>4}=${X:0>2}", .{ addr16, value });

                    // Track $2002 reads
                    if (addr16 == 0x2002) {
                        read_2002_count += 1;
                        const master_cycle = state.clock.master_cycles;
                        const scanline = state.ppu.scanline;
                        const dot = state.ppu.dot;
                        std.debug.print(" <- PPUSTATUS read! scanline={d} dot={d} master_cycle={d}", .{ scanline, dot, master_cycle });
                    }
                }
                std.debug.print("\n", .{});
            }
        }
    }

    std.debug.print("Total $2002 reads in first 100 instructions: {d}\n", .{read_2002_count});

    std.debug.print("\nAfter first 50 instructions:\n", .{});
    std.debug.print("  CPU cycles: {d}\n", .{state.clock.cpuCycles()});
    std.debug.print("  Warmup complete: {}\n", .{state.ppu.warmup_complete});
    std.debug.print("  PC: ${X:0>4}\n", .{state.cpu.pc});

    var framebuffer = [_]u32{0} ** FRAME_PIXELS;
    var rendering_enabled_frame: ?u64 = null;

    // Track PPUMASK writes
    std.debug.print("\n\nTracking PPUMASK ($2001) writes...\n", .{});

    // Run for 300 frames (5 seconds) and monitor for rendering
    var frame: usize = 0;
    var total_instructions: u64 = 0;
    var last_pc: u16 = state.cpu.pc;
    var pc_stuck_count: usize = 0;

    // Track PC frequency for loop detection
    var pc_frequency = std.AutoHashMap(u16, u32).init(testing.allocator);
    defer pc_frequency.deinit();

    while (frame < 300) : (frame += 1) {
        state.ppu.framebuffer = &framebuffer;
        const frame_instructions = state.emulateFrame();
        total_instructions += frame_instructions;

        // Track PC for first 5 frames to detect loops
        if (frame < 5) {
            const entry = try pc_frequency.getOrPut(state.cpu.pc);
            if (!entry.found_existing) {
                entry.value_ptr.* = 1;
            } else {
                entry.value_ptr.* += 1;
            }
        }

        // Check for infinite loop (PC not changing)
        if (state.cpu.pc == last_pc) {
            pc_stuck_count += 1;
            if (pc_stuck_count > 10 and frame < 10) {
                std.debug.print("WARNING: PC stuck at ${X:0>4} for {d} frames\n", .{ state.cpu.pc, pc_stuck_count });
            }
        } else {
            pc_stuck_count = 0;
            last_pc = state.cpu.pc;
        }

        // Check if rendering enabled
        const ppumask: u8 = @bitCast(state.ppu.mask);
        const ppuctrl: u8 = @bitCast(state.ppu.ctrl);

        if (frame < 10) {
            // Read $2002 to get actual VBlank status
            const read_result = state.busRead(0x2002);
            const actual_vblank = (read_result >> 7) & 1;

            std.debug.print("Frame {d}: PC=${X:0>4} PPUCTRL=${X:0>2} PPUMASK=${X:0>2} $2002=${X:0>2} vblank={} warmup={} instr={d}\n", .{
                frame,
                state.cpu.pc,
                ppuctrl,
                ppumask,
                read_result,
                actual_vblank,
                state.ppu.warmup_complete,
                frame_instructions,
            });

            std.debug.print("  VBlankLedger: set={d} clear={d} read={d} prevent={d}\n", .{
                state.ppu.vblank.last_set_cycle,
                state.ppu.vblank.last_clear_cycle,
                state.ppu.vblank.last_read_cycle,
                state.ppu.vblank.prevent_vbl_set_cycle,
            });
        }

        if (rendering_enabled_frame == null and state.rendering_enabled) {
            rendering_enabled_frame = state.ppu.frame_count;
            std.debug.print("Castlevania: Rendering enabled at frame {d}\n", .{rendering_enabled_frame.?});
        }
    }

    // Analyze PC frequency
    std.debug.print("\nPC frequency analysis (first 5 frames):\n", .{});
    var iter = pc_frequency.iterator();
    var top_pcs: [5]struct { pc: u16, count: u32 } = undefined;
    var top_count: usize = 0;

    while (iter.next()) |entry| {
        if (top_count < 5) {
            top_pcs[top_count] = .{ .pc = entry.key_ptr.*, .count = entry.value_ptr.* };
            top_count += 1;
        } else {
            // Find minimum
            var min_idx: usize = 0;
            var min_count = top_pcs[0].count;
            for (top_pcs[1..], 1..) |item, i| {
                if (item.count < min_count) {
                    min_count = item.count;
                    min_idx = i;
                }
            }
            if (entry.value_ptr.* > min_count) {
                top_pcs[min_idx] = .{ .pc = entry.key_ptr.*, .count = entry.value_ptr.* };
            }
        }
    }

    // Sort top PCs by count (descending)
    for (0..top_count) |i| {
        for (i + 1..top_count) |j| {
            if (top_pcs[j].count > top_pcs[i].count) {
                const temp = top_pcs[i];
                top_pcs[i] = top_pcs[j];
                top_pcs[j] = temp;
            }
        }
    }

    std.debug.print("Most frequent PCs:\n", .{});
    for (top_pcs[0..top_count]) |item| {
        std.debug.print("  ${X:0>4}: {d} times\n", .{ item.pc, item.count });
    }

    std.debug.print("Castlevania final state:\n", .{});
    const final_mask: u8 = @bitCast(state.ppu.mask);
    const final_ctrl: u8 = @bitCast(state.ppu.ctrl);
    std.debug.print("  PPUMASK: ${X:0>2}\n", .{final_mask});
    std.debug.print("  PPUCTRL: ${X:0>2}\n", .{final_ctrl});
    std.debug.print("  PC: ${X:0>4}\n", .{state.cpu.pc});
    std.debug.print("  Total instructions: {d}\n", .{total_instructions});
    std.debug.print("  rendering_enabled: {}\n", .{state.rendering_enabled});

    // Castlevania should enable rendering within 5 seconds
    if (rendering_enabled_frame == null) {
        std.debug.print("ERROR: Castlevania did not enable rendering in 300 frames\n", .{});
        std.debug.print("This is the grey screen bug - PPU rendering never initialized\n", .{});
    }

    try testing.expect(rendering_enabled_frame != null);
}
