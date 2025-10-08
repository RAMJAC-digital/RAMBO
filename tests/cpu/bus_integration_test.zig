//! Bus Integration Test
//!
//! Verifies that bus read/write operations work correctly with CPU execution.
//! This test isolates whether the issue is with bus routing or CPU execution.

const std = @import("std");
const testing = std.testing;
const RAMBO = @import("RAMBO");

const Harness = RAMBO.TestHarness.Harness;

// ============================================================================
// Test Infrastructure
// ============================================================================

const BusTestHarness = struct {
    harness: Harness,

    fn init() !BusTestHarness {
        return .{
            .harness = try Harness.init(),
        };
    }

    fn deinit(self: *BusTestHarness) void {
        self.harness.deinit();
    }
};

// ============================================================================
// Bus Read/Write Verification Tests
// ============================================================================

test "Bus: Direct RAM write and read" {
    var h = try BusTestHarness.init();
    defer h.deinit();

    // Test direct bus operations on various RAM addresses
    const test_cases = [_]struct { addr: u16, value: u8 }{
        .{ .addr = 0x0000, .value = 0x11 },
        .{ .addr = 0x0100, .value = 0x22 },
        .{ .addr = 0x0200, .value = 0x33 },
        .{ .addr = 0x0201, .value = 0x42 }, // Used in page crossing test
        .{ .addr = 0x0301, .value = 0x55 },
        .{ .addr = 0x0401, .value = 0x66 },
        .{ .addr = 0x0502, .value = 0x99 },
        .{ .addr = 0x0601, .value = 0xAA },
        .{ .addr = 0x0700, .value = 0xEE },
        .{ .addr = 0x0701, .value = 0xFF },
    };

    std.debug.print("\n=== Bus Read/Write Verification ===\n", .{});

    for (test_cases) |tc| {
        // Write value
        h.harness.state.busWrite(tc.addr, tc.value);

        // Read it back
        const read_value = h.harness.state.busRead(tc.addr);

        std.debug.print("Address ${X:0>4}: wrote ${X:0>2}, read ${X:0>2} ", .{
            tc.addr,
            tc.value,
            read_value,
        });

        if (read_value == tc.value) {
            std.debug.print("✓\n", .{});
        } else {
            std.debug.print("✗ FAILED\n", .{});
        }

        try testing.expectEqual(tc.value, read_value);
    }

    std.debug.print("\n", .{});
}

test "Bus: CPU reads from RAM correctly" {
    var h = try BusTestHarness.init();
    defer h.deinit();

    std.debug.print("\n=== CPU RAM Read Test ===\n", .{});

    // Place LDA immediate instruction: LDA #$42
    h.harness.state.bus.ram[0x0000] = 0xA9; // LDA immediate
    h.harness.state.bus.ram[0x0001] = 0x42; // Value to load

    // Set PC and execute
    h.harness.state.cpu.pc = 0x0000;
    const initial_pc = h.harness.state.cpu.pc;

    std.debug.print("Initial PC: ${X:0>4}\n", .{initial_pc});
    std.debug.print("Initial A:  ${X:0>2}\n", .{h.harness.state.cpu.a});
    std.debug.print("Instruction bytes: ${X:0>2} ${X:0>2}\n", .{
        h.harness.state.bus.ram[0],
        h.harness.state.bus.ram[1],
    });

    // Execute instruction (LDA #$42 takes 2 CPU cycles = 6 PPU cycles)
    // CPU runs at 1/3 PPU speed, so we need to tick 6 times minimum
    var ppu_cycles: u32 = 0;
    var instruction_started = false;
    while (ppu_cycles < 20) : (ppu_cycles += 1) {
        h.harness.state.tick();
        const cpu_cycle = h.harness.state.clock.cpuCycles();
        std.debug.print("PPU cycle {}: CPU cycle {}, PC=${X:0>4}, A=${X:0>2}, CPU state={}\n", .{
            ppu_cycles + 1,
            cpu_cycle,
            h.harness.state.cpu.pc,
            h.harness.state.cpu.a,
            h.harness.state.cpu.state,
        });

        // Track when instruction starts (PC changes)
        if (h.harness.state.cpu.pc != initial_pc) {
            instruction_started = true;
        }

        // Stop when instruction completes (back to fetch_opcode after starting)
        if (instruction_started and h.harness.state.cpu.state == .fetch_opcode) {
            break;
        }
    }

    std.debug.print("Final PC: ${X:0>4}\n", .{h.harness.state.cpu.pc});
    std.debug.print("Final A:  ${X:0>2}\n", .{h.harness.state.cpu.a});

    try testing.expectEqual(@as(u8, 0x42), h.harness.state.cpu.a);
    try testing.expect(h.harness.state.cpu.pc != initial_pc);
}

test "Bus: CPU reads from absolute address" {
    var h = try BusTestHarness.init();
    defer h.deinit();

    std.debug.print("\n=== CPU Absolute Read Test ===\n", .{});

    // Place LDA absolute instruction: LDA $0201
    h.harness.state.bus.ram[0x0000] = 0xAD; // LDA absolute
    h.harness.state.bus.ram[0x0001] = 0x01; // Low byte of address
    h.harness.state.bus.ram[0x0002] = 0x02; // High byte of address

    // Put test value at target address
    h.harness.state.busWrite(0x0201, 0x42);

    std.debug.print("Target address $0201 contains: ${X:0>2}\n", .{
        h.harness.state.busRead(0x0201),
    });

    // Set PC and execute
    h.harness.state.cpu.pc = 0x0000;
    const initial_pc = h.harness.state.cpu.pc;

    std.debug.print("Initial PC: ${X:0>4}\n", .{initial_pc});
    std.debug.print("Instruction: LDA $0201\n", .{});

    // Execute instruction (LDA absolute takes 4 CPU cycles = 12 PPU cycles)
    var ppu_cycles: u32 = 0;
    var instruction_started = false;
    while (ppu_cycles < 20) : (ppu_cycles += 1) {
        h.harness.state.tick();
        const cpu_cycle = h.harness.state.clock.cpuCycles();
        std.debug.print("PPU cycle {}: CPU cycle {}, PC=${X:0>4}, A=${X:0>2}, state={}\n", .{
            ppu_cycles + 1,
            cpu_cycle,
            h.harness.state.cpu.pc,
            h.harness.state.cpu.a,
            h.harness.state.cpu.state,
        });

        if (h.harness.state.cpu.pc != initial_pc) {
            instruction_started = true;
        }

        if (instruction_started and h.harness.state.cpu.state == .fetch_opcode) {
            break;
        }
    }

    std.debug.print("Final PC: ${X:0>4}\n", .{h.harness.state.cpu.pc});
    std.debug.print("Final A:  ${X:0>2}\n", .{h.harness.state.cpu.a});

    try testing.expectEqual(@as(u8, 0x42), h.harness.state.cpu.a);
}

test "Bus: CPU indexed addressing works" {
    var h = try BusTestHarness.init();
    defer h.deinit();

    std.debug.print("\n=== CPU Indexed Read Test ===\n", .{});

    // Place LDA absolute,X instruction: LDA $0200,X
    h.harness.state.bus.ram[0x0000] = 0xBD; // LDA absolute,X
    h.harness.state.bus.ram[0x0001] = 0x00; // Low byte
    h.harness.state.bus.ram[0x0002] = 0x02; // High byte

    // Set X register
    h.harness.state.cpu.x = 0x01;

    // Put test value at target address ($0200 + $01 = $0201)
    h.harness.state.busWrite(0x0201, 0x99);

    std.debug.print("X register: ${X:0>2}\n", .{h.harness.state.cpu.x});
    std.debug.print("Target address $0201 contains: ${X:0>2}\n", .{
        h.harness.state.busRead(0x0201),
    });

    // Set PC and execute
    h.harness.state.cpu.pc = 0x0000;
    const initial_pc = h.harness.state.cpu.pc;

    std.debug.print("Instruction: LDA $0200,X\n", .{});

    // Execute instruction (LDA absolute,X takes 4 CPU cycles = 12 PPU cycles)
    var ppu_cycles: u32 = 0;
    var instruction_started = false;
    while (ppu_cycles < 20) : (ppu_cycles += 1) {
        h.harness.state.tick();
        const cpu_cycle = h.harness.state.clock.cpuCycles();
        std.debug.print("PPU cycle {}: CPU cycle {}, PC=${X:0>4}, A=${X:0>2}, state={}\n", .{
            ppu_cycles + 1,
            cpu_cycle,
            h.harness.state.cpu.pc,
            h.harness.state.cpu.a,
            h.harness.state.cpu.state,
        });

        if (h.harness.state.cpu.pc != initial_pc) {
            instruction_started = true;
        }

        if (instruction_started and h.harness.state.cpu.state == .fetch_opcode) {
            break;
        }
    }

    std.debug.print("Final A: ${X:0>2} (expected: $99)\n", .{h.harness.state.cpu.a});

    try testing.expectEqual(@as(u8, 0x99), h.harness.state.cpu.a);
}
