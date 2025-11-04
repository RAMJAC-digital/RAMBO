//! Super Mario Bros 1 NMI Controller Polling Test
//!
//! SMB1 reads controller input EXCLUSIVELY in its NMI handler. This test reproduces
//! the exact SMB1 NMI handler flow based on the disassembly (SMBDIS.AMS).
//!
//! SMB1 NMI Handler Flow (from disassembly):
//! 1. NMI vector at $FFFA-$FFFB points to NonMaskableInterrupt routine
//! 2. NMI handler disables NMI, configures PPU, performs OAM DMA
//! 3. Calls ReadJoypads subroutine (ONLY controller polling in entire game!)
//! 4. ReadJoypads: strobes $4016 high, then low, reads 8 bits
//! 5. Stores button data in SavedJoypadBits ($06FC)
//!
//! If NMI doesn't fire, ReadJoypads never runs, and SMB1 NEVER sees controller input.
//!
//! Reference: https://gist.github.com/1wErt3r/4048722 (SMB1 disassembly)
//! Hardware Citation: https://www.nesdev.org/wiki/Standard_controller

const std = @import("std");
const testing = std.testing;
const RAMBO = @import("RAMBO");

const EmulationState = RAMBO.EmulationState.EmulationState;
const Config = RAMBO.Config.Config;
const NromCart = RAMBO.CartridgeType;
const AnyCartridge = RAMBO.AnyCartridge;
const ButtonState = RAMBO.ButtonState;


test "SMB1 NMI Controller Polling: NMI handler executes and reads controller" {
    const allocator = testing.allocator;

    // Load Super Mario Bros ROM
    const rom_path = "tests/data/Mario/Super Mario Bros. (World).nes";
    const nrom_cart = NromCart.load(allocator, rom_path) catch |err| {
        if (err == error.FileNotFound) return error.SkipZigTest;
        return err;
    };

    const cart = AnyCartridge{ .nrom = nrom_cart };

    // Initialize emulation state
    var config = Config.init(allocator);
    defer config.deinit();

    var state = EmulationState.init(&config);
    defer state.deinit();

    state.loadCartridge(cart);

    // Power-on: Load reset vector and initialize CPU
    const reset_vector = state.busRead16(0xFFFC);
    state.cpu.pc = reset_vector;
    state.cpu.sp = 0xFD;
    state.cpu.p.interrupt = true;

    // Skip PPU warmup period (SMB1 won't touch PPU during warmup)
    state.ppu.warmup_complete = true;

    // Prepare controller input (A button pressed)
    const button_input = ButtonState{
        .a = true,
        .b = false,
        .select = false,
        .start = false,
        .up = false,
        .down = false,
        .left = false,
        .right = false,
    };

    // Run until SMB1 initializes and reaches first NMI handler
    // SMB1 initialization takes about 2-3 frames
    var frame_count: usize = 0;
    var nmi_vector_fetched = false;
    var nmi_handler_entered = false;

    // Track when we're in VBlank for the first time with NMI enabled
    var first_vblank_with_nmi = false;
    const saved_joypad_bits_address: u16 = 0x06FC; // From SMB1 disassembly

    // Run for maximum 30 frames (SMB1 might not poll controllers during early boot)
    while (frame_count < 30) {
        // Update controller input at start of each frame (simulates mailbox poll)
        state.controller.updateButtons(button_input.toByte(), 0x00);

        // Get NMI vector address ONCE before loop
        const nmi_vector = state.busRead16(0xFFFA);

        // Run frame with NMI tracking
        while (true) {
            const pc_before_tick = state.cpu.pc;

            state.tick();

            // Simplified NMI detection: Check if PC reached NMI vector address
            // This catches the moment when the CPU jumps to the NMI handler
            if (state.cpu.pc == nmi_vector and pc_before_tick != nmi_vector) {
                nmi_vector_fetched = true;
                nmi_handler_entered = true;
            }

            // Track controller port operations (writes to $4016)
            // We can't directly intercept bus writes, so we'll check controller state changes
            // SMB1 ReadJoypads does: STA $4016 (#$01), then STA $4016 (#$00)

            // Track scanline/dot for VBlank detection
            const scanline = state.ppu.scanline;
            const dot = state.ppu.cycle;

            // Check if we're in VBlank with NMI enabled
            if (scanline == 241 and dot > 1 and state.ppu.ctrl.nmi_enable) {
                first_vblank_with_nmi = true;
            }

            // Frame complete at scanline 0, dot 0
            if (scanline == 0 and dot == 0) {
                break;
            }
        }

        frame_count += 1;

        // After frame completes, check if NMI handler was reached
        if (nmi_handler_entered) {
            // Verify that SavedJoypadBits ($06FC) was updated with controller input
            // SMB1 stores button data here after reading from $4016
            const saved_bits = state.busRead(saved_joypad_bits_address);

            std.debug.print("\n=== SMB1 NMI Controller Test Results (Frame {}) ===\n", .{frame_count});
            std.debug.print("NMI vector fetched: {}\n", .{nmi_vector_fetched});
            std.debug.print("NMI handler entered: {}\n", .{nmi_handler_entered});
            std.debug.print("SavedJoypadBits ($06FC): 0x{X:0>2}\n", .{saved_bits});
            std.debug.print("Expected button data: 0x{X:0>2} (A button = bit 0)\n", .{button_input.toByte()});

            // SUCCESS CRITERIA:
            // 1. NMI vector was fetched (NMI handler executed)
            // 2. SavedJoypadBits contains non-zero value (controller was read)

            try testing.expect(nmi_vector_fetched);

            // If we got here, NMI handler ran. Now check if controller polling worked.
            // SMB1's ReadJoypads should have stored button data in $06FC.
            // Note: SMB1 may filter/process the raw controller data, so we check for ANY non-zero value
            // indicating controller polling occurred.

            if (saved_bits != 0) {
                // SUCCESS: Controller data was read and stored
                std.debug.print("✓ SMB1 NMI handler executed and controller data stored!\n", .{});
                return; // Test PASSED
            } else {
                // FAILURE: NMI handler ran but controller data is still zero
                std.debug.print("✗ NMI handler ran but SavedJoypadBits is still 0x00\n", .{});
                std.debug.print("This indicates controller polling did not occur in NMI handler.\n", .{});
                return error.ControllerPollingDidNotOccur;
            }
        }

        // Check if we've been in VBlank with NMI enabled but NMI never fired
        if (first_vblank_with_nmi and !nmi_handler_entered and frame_count >= 10) {
            std.debug.print("\n=== SMB1 NMI TEST FAILURE ===\n", .{});
            std.debug.print("Frames run: {}\n", .{frame_count});
            std.debug.print("VBlank occurred with NMI enabled: {}\n", .{first_vblank_with_nmi});
            std.debug.print("NMI handler entered: {}\n", .{nmi_handler_entered});
            std.debug.print("\nCurrent state:\n", .{});
            std.debug.print("  CPU PC: 0x{X:0>4}\n", .{state.cpu.pc});
            std.debug.print("  CPU SP: 0x{X:0>2}\n", .{state.cpu.sp});
            std.debug.print("  PPUCTRL: 0x{X:0>2} (NMI enable: {})\n", .{ @as(u8, @bitCast(state.ppu.ctrl)), state.ppu.ctrl.nmi_enable });
            std.debug.print("  NMI line: {}\n", .{state.cpu.nmi_line});
            std.debug.print("  VBlank ledger:\n", .{});
            std.debug.print("    last_set_cycle: {}\n", .{state.vblank_ledger.last_set_cycle});
            std.debug.print("    last_clear_cycle: {}\n", .{state.vblank_ledger.last_clear_cycle});
            std.debug.print("    last_read_cycle: {}\n", .{state.vblank_ledger.last_read_cycle});
            std.debug.print("    prevent_vbl_set_cycle: {}\n", .{state.vblank_ledger.prevent_vbl_set_cycle});
            std.debug.print("    isFlagVisible(): {}\n", .{state.vblank_ledger.isFlagVisible()});

            return error.NmiDidNotFire;
        }
    }

    // If we ran 10 frames and NMI never fired, FAIL
    std.debug.print("\n=== SMB1 NMI TEST FAILURE: NMI never fired after {} frames ===\n", .{frame_count});
    std.debug.print("Expected: NMI handler to execute within first few frames\n", .{});
    std.debug.print("Actual: NMI handler never reached\n", .{});
    std.debug.print("\nThis indicates NMI timing is broken for SMB1.\n", .{});

    return error.NmiNeverFired;
}

test "SMB1 NMI Controller Polling: Minimal reproduction without ROM" {
    // This test creates a minimal scenario that reproduces SMB1's NMI controller polling
    // without requiring the actual ROM file.
    //
    // Test ROM behavior:
    // 1. Enable NMI (write 0x80 to $2000)
    // 2. Enable rendering (write 0x1E to $2001)
    // 3. Wait for VBlank (NMI fires)
    // 4. NMI handler: strobe controller ($4016 = $01, then $00), read 8 times
    // 5. Store result in zero page
    //
    // This minimal test verifies the NMI → controller read flow works.

    const allocator = testing.allocator;

    // Create minimal test ROM
    // iNES header (16 bytes) + 32KB PRG ROM
    var rom_data: [16 + 32768]u8 = undefined;

    // iNES header
    rom_data[0] = 'N';
    rom_data[1] = 'E';
    rom_data[2] = 'S';
    rom_data[3] = 0x1A;
    rom_data[4] = 2; // 2 x 16KB PRG ROM banks
    rom_data[5] = 0; // 0 CHR ROM banks
    rom_data[6] = 0x00; // Mapper 0 (NROM), horizontal mirroring
    rom_data[7] = 0x00;
    @memset(rom_data[8..16], 0);

    // PRG ROM code (starts at offset 16)
    const prg_base: usize = 16;

    // Fill with NOPs
    @memset(rom_data[prg_base..], 0xEA); // NOP

    // Reset vector points to $C000
    rom_data[rom_data.len - 4] = 0x00;
    rom_data[rom_data.len - 3] = 0xC0;

    // NMI vector points to $C100
    rom_data[rom_data.len - 6] = 0x00;
    rom_data[rom_data.len - 5] = 0xC1;

    // IRQ vector points to $FFFF (unused)
    rom_data[rom_data.len - 2] = 0xFF;
    rom_data[rom_data.len - 1] = 0xFF;

    // Reset handler at $C000 (offset = $C000 - $8000 + 16 = 0x4010)
    const reset_offset: usize = 0x4010;
    var code_pos: usize = reset_offset;

    // LDA #$80 - Enable NMI
    rom_data[code_pos] = 0xA9;
    code_pos += 1;
    rom_data[code_pos] = 0x80;
    code_pos += 1;
    // STA $2000
    rom_data[code_pos] = 0x8D;
    code_pos += 1;
    rom_data[code_pos] = 0x00;
    code_pos += 1;
    rom_data[code_pos] = 0x20;
    code_pos += 1;

    // LDA #$1E - Enable rendering
    rom_data[code_pos] = 0xA9;
    code_pos += 1;
    rom_data[code_pos] = 0x1E;
    code_pos += 1;
    // STA $2001
    rom_data[code_pos] = 0x8D;
    code_pos += 1;
    rom_data[code_pos] = 0x01;
    code_pos += 1;
    rom_data[code_pos] = 0x20;
    code_pos += 1;

    // Infinite loop (wait for NMI)
    // JMP $C00A
    rom_data[code_pos] = 0x4C;
    code_pos += 1;
    rom_data[code_pos] = 0x0A;
    code_pos += 1;
    rom_data[code_pos] = 0xC0;
    code_pos += 1;

    // NMI handler at $C100 (offset = $C100 - $8000 + 16 = 0x4110)
    const nmi_offset: usize = 0x4110;
    code_pos = nmi_offset;

    // Controller strobe sequence (like SMB1 ReadJoypads)
    // LDA #$01
    rom_data[code_pos] = 0xA9;
    code_pos += 1;
    rom_data[code_pos] = 0x01;
    code_pos += 1;
    // STA $4016 - Strobe high
    rom_data[code_pos] = 0x8D;
    code_pos += 1;
    rom_data[code_pos] = 0x16;
    code_pos += 1;
    rom_data[code_pos] = 0x40;
    code_pos += 1;

    // LDA #$00
    rom_data[code_pos] = 0xA9;
    code_pos += 1;
    rom_data[code_pos] = 0x00;
    code_pos += 1;
    // STA $4016 - Strobe low
    rom_data[code_pos] = 0x8D;
    code_pos += 1;
    rom_data[code_pos] = 0x16;
    code_pos += 1;
    rom_data[code_pos] = 0x40;
    code_pos += 1;

    // Read 8 bits from controller
    // LDX #$08
    rom_data[code_pos] = 0xA2;
    code_pos += 1;
    rom_data[code_pos] = 0x08;
    code_pos += 1;

    // Loop: LDA $4016
    const loop_start = code_pos;
    rom_data[code_pos] = 0xAD;
    code_pos += 1;
    rom_data[code_pos] = 0x16;
    code_pos += 1;
    rom_data[code_pos] = 0x40;
    code_pos += 1;

    // DEX
    rom_data[code_pos] = 0xCA;
    code_pos += 1;
    // BNE loop
    rom_data[code_pos] = 0xD0;
    code_pos += 1;
    const branch_offset: i8 = @intCast(@as(isize, @intCast(loop_start)) - @as(isize, @intCast(code_pos + 1)));
    rom_data[code_pos] = @bitCast(branch_offset);
    code_pos += 1;

    // Store accumulator in zero page (marker that we reached here)
    // STA $20
    rom_data[code_pos] = 0x85;
    code_pos += 1;
    rom_data[code_pos] = 0x20;
    code_pos += 1;

    // RTI
    rom_data[code_pos] = 0x40;
    code_pos += 1;

    // Load test ROM
    const cart = try NromCart.loadFromData(allocator, &rom_data);
    const any_cart = AnyCartridge{ .nrom = cart };

    // Initialize emulation state
    var config = Config.init(allocator);
    defer config.deinit();

    var state = EmulationState.init(&config);
    defer state.deinit();

    state.loadCartridge(any_cart);
    state.reset();

    // Skip PPU warmup
    state.ppu.warmup_complete = true;

    // Inject controller input (A button pressed)
    const button_input = ButtonState{
        .a = true,
        .b = false,
        .select = false,
        .start = false,
        .up = false,
        .down = false,
        .left = false,
        .right = false,
    };
    state.controller.updateButtons(button_input.toByte(), 0x00);

    // Run until NMI fires (maximum 2 frames)
    var nmi_fired = false;
    var marker_written = false;

    for (0..2) |_| {
        // Run one frame
        while (!(state.ppu.scanline == 0 and state.ppu.cycle == 0)) {
            state.tick();

            // Check if NMI handler wrote to $20 (our marker)
            const marker = state.busRead(0x20);
            if (marker != 0) {
                marker_written = true;
                nmi_fired = true;
                break;
            }
        }

        if (nmi_fired) break;
    }

    // Verify NMI fired and controller was read
    try testing.expect(nmi_fired);
    try testing.expect(marker_written);

    std.debug.print("\n✓ Minimal SMB1 NMI controller test PASSED\n", .{});
}
