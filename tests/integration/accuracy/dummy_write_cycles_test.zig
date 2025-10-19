//! AccuracyCoin Accuracy Test: DUMMY WRITE CYCLES (FAIL 2)
//!
//! This test verifies that Read-Modify-Write (RMW) instructions perform dummy writes.
//! RMW instructions (ASL, LSR, ROL, ROR, INC, DEC) must write the original value back
//! to memory BEFORE writing the modified value. This is cycle 5 of a 6-cycle RMW instruction.
//!
//! Hardware Behavior:
//! - Cycle 4: Read value from memory
//! - Cycle 5: Write ORIGINAL value back (dummy write) ← CRITICAL
//! - Cycle 6: Write MODIFIED value
//!
//! This is visible to memory-mapped I/O (like PPU registers) and is tested by AccuracyCoin
//! using PPU $2006 writes that affect the internal VRAM address pointer.
//!
//! Result Address: $0407 (result_DummyWrites)
//! Expected: $00 = PASS
//! Current:  $00 = PASS ✅ (ROM screenshot 2025-10-19 shows PASS)

const std = @import("std");
const testing = std.testing;
const RAMBO = @import("RAMBO");
const Harness = RAMBO.TestHarness.Harness;

test "Accuracy: DUMMY WRITE CYCLES (AccuracyCoin FAIL 2)" {
    // Load AccuracyCoin ROM (complete, unmodified)
    const cart = RAMBO.CartridgeType.load(testing.allocator, "tests/data/AccuracyCoin.nes") catch |err| {
        if (err == error.FileNotFound) return error.SkipZigTest;
        return err;
    };

    var h = try Harness.init();
    defer h.deinit();

    // Load cartridge
    h.loadNromCartridge(cart);

    // Initialize emulator state
    h.state.reset();

    // Skip PPU warmup period (AccuracyCoin expects this)
    h.state.ppu.warmup_complete = true;

    // Set PC to TEST_DummyWrites entry point
    // ROM offset 0x2328 → CPU address $A318 (PRG ROM base $8000 + offset)
    h.state.cpu.pc = 0xA318;
    h.state.cpu.state = .fetch_opcode;
    h.state.cpu.instruction_cycle = 0;

    // Initialize stack pointer (AccuracyCoin expects $FD)
    h.state.cpu.sp = 0xFD;

    // Initialize zero-page variables that AccuracyCoin uses
    h.state.bus.ram[0x10] = 0x00; // ErrorCode
    h.state.bus.ram[0x50] = 0x00; // Scratch variable
    h.state.bus.ram[0xF0] = 0x00; // PPUCTRL_COPY
    h.state.bus.ram[0xF1] = 0x00; // PPUMASK_COPY

    // Initialize result address to 0x80 (RUNNING)
    h.state.bus.ram[0x0407] = 0x80;

    // === Pre-Test: Verify PPU Open Bus ===
    std.debug.print("\n=== PPU Open Bus Pre-Check ===\n", .{});

    // Write known value to $2000 to set open bus
    h.state.busWrite(0x2000, 0x42);
    const read_2000 = h.state.busRead(0x2000);
    std.debug.print("Write $2000=$42, Read $2000=0x{X:0>2} (expect 0x42)\n", .{read_2000});

    // Write different value to $2006
    h.state.busWrite(0x2006, 0x2D);
    const read_2006 = h.state.busRead(0x2006);
    std.debug.print("Write $2006=$2D, Read $2006=0x{X:0>2} (expect 0x2D)\n", .{read_2006});

    if (read_2000 != 0x42 or read_2006 != 0x2D) {
        std.debug.print("❌ PPU open bus FAILED pre-check!\n", .{});
    } else {
        std.debug.print("✅ PPU open bus working correctly\n", .{});
    }
    std.debug.print("=== End Pre-Check ===\n\n", .{});

    // Run test (max 1,000,000 cycles - test should complete much faster)
    const max_cycles: usize = 1_000_000;
    var cycles: usize = 0;

    // Track ErrorCode changes to identify failure point
    var last_error_code: u8 = 0xFF;
    var last_sp: u8 = h.state.cpu.sp;

    while (cycles < max_cycles) : (cycles += 1) {
        h.state.tick();

        // Monitor ErrorCode changes
        const error_code = h.state.bus.ram[0x10];
        if (error_code != last_error_code) {
            std.debug.print("Cycle {d}: ErrorCode 0x{X:0>2}→0x{X:0>2}, PC=0x{X:0>4}, SP=0x{X:0>2}, A=0x{X:0>2}\n", .{ cycles, last_error_code, error_code, h.state.cpu.pc, h.state.cpu.sp, h.state.cpu.a });
            last_error_code = error_code;
        }

        // Monitor stack pointer corruption
        if (h.state.cpu.sp != last_sp and h.state.cpu.state == .fetch_opcode) {
            if (@abs(@as(i16, h.state.cpu.sp) - @as(i16, last_sp)) > 10) {
                std.debug.print("Cycle {d}: ⚠️  SP jumped 0x{X:0>2}→0x{X:0>2}, PC=0x{X:0>4}\n", .{ cycles, last_sp, h.state.cpu.sp, h.state.cpu.pc });
            }
            last_sp = h.state.cpu.sp;
        }

        // Check if test completed (RTS with result written)
        const result = h.state.bus.ram[0x0407];
        if (result != 0x80) {
            std.debug.print("Cycle {d}: Test complete, result=0x{X:0>2}\n", .{ cycles, result });
            break;
        }
    }

    // === ASSERTION ===
    const result = h.state.bus.ram[0x0407];

    // Show failure diagnosis
    if (result != 0x00) {
        std.debug.print("\n=== FAILURE DIAGNOSIS ===\n", .{});
        std.debug.print("Result: 0x{X:0>2} (expected 0x00)\n", .{result});
        std.debug.print("ErrorCode: 0x{X:0>2}\n", .{h.state.bus.ram[0x10]});
        std.debug.print("PC: 0x{X:0>4}\n", .{h.state.cpu.pc});
        std.debug.print("Opcode: 0x{X:0>2}\n", .{h.state.cpu.opcode});
        std.debug.print("A: 0x{X:0>2}\n", .{h.state.cpu.a});
        std.debug.print("Cycles: {d}\n", .{cycles});
    }

    // EXPECTED: $00 = PASS (all subtests pass)
    // VERIFIED 2025-10-19: ROM screenshot shows this test PASSES
    // Test correctly detects pass status
    try testing.expectEqual(@as(u8, 0x00), result);
}
