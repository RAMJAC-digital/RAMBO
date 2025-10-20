// AccuracyCoin Test Integration Helpers
//
// This module provides common functionality for running AccuracyCoin tests
// via the ROM's RunTest function instead of reimplementing test logic.

const std = @import("std");
const RAMBO = @import("RAMBO");
const Harness = RAMBO.TestHarness.Harness;

pub const Suite = enum {
    cpu_behavior,
    ppu_timing,
};

pub const CpuBehaviorTest = enum(u8) {
    rom_not_writable = 0,
    ram_mirroring = 1,
    pc_wraparound = 2,
    decimal_flag = 3,
    b_flag = 4,
    dummy_read_cycles = 5,
    dummy_write_cycles = 6,
    open_bus = 7,
    unofficial_instructions = 8,
    all_nop_instructions = 9,
};

pub const PpuTimingTest = enum(u8) {
    vblank_beginning = 0,
    vblank_end = 1,
    nmi_control = 2,
    nmi_timing = 3,
    nmi_suppression = 4,
    nmi_vblank_end = 5,
    nmi_disabled_vblank = 6,
};

pub inline fn suiteIndex(comptime suite: Suite) u8 {
    return switch (suite) {
        .cpu_behavior => SUITE_CPU_BEHAVIOR_INDEX,
        .ppu_timing => SUITE_PPU_TIMING_INDEX,
    };
}

pub inline fn setupSuiteFor(h: *Harness, comptime suite: Suite) void {
    setupSuite(h, suiteIndex(suite));
}

pub inline fn setupCpuBehaviorSuite(h: *Harness) void {
    setupSuite(h, SUITE_CPU_BEHAVIOR_INDEX);
}

pub inline fn setupPpuTimingSuite(h: *Harness) void {
    setupSuite(h, SUITE_PPU_TIMING_INDEX);
}

pub const AccuracyStatus = enum {
    not_run,
    pass,
    fail,
    in_progress,
};

pub const AccuracyResult = struct {
    status: AccuracyStatus,
    error_code: u8,
};

fn statusName(status: AccuracyStatus) []const u8 {
    return switch (status) {
        .not_run => "NOT_RUN",
        .pass => "PASS",
        .fail => "FAIL",
        .in_progress => "IN_PROGRESS",
    };
}

pub fn encodeResult(status: AccuracyStatus, error_code: u8) u8 {
    const status_bits: u8 = switch (status) {
        .not_run => 0,
        .pass => 1,
        .fail => 2,
        .in_progress => 3,
    };
    return (error_code << 2) | status_bits;
}

pub fn decodeResult(raw: u8) AccuracyResult {
    const status_bits = raw & 0x03;
    const error_code = raw >> 2;
    const status = switch (status_bits) {
        0 => AccuracyStatus.not_run,
        1 => AccuracyStatus.pass,
        2 => AccuracyStatus.fail,
        3 => AccuracyStatus.in_progress,
        else => unreachable,
    };
    return .{ .status = status, .error_code = error_code };
}

pub fn reportAccuracyMismatch(
    name: []const u8,
    actual_raw: u8,
    expected_status: AccuracyStatus,
    expected_error: u8,
) void {
    const actual_decoded = decodeResult(actual_raw);
    const expected_decoded = AccuracyResult{
        .status = expected_status,
        .error_code = expected_error,
    };
    const expected_raw = encodeResult(expected_status, expected_error);
    std.debug.print(
        "{s}: expected {s} (err={}) raw=0x{X:0>2}, got {s} (err={}) raw=0x{X:0>2}\n",
        .{
            name,
            statusName(expected_decoded.status),
            expected_decoded.error_code,
            expected_raw,
            statusName(actual_decoded.status),
            actual_decoded.error_code,
            actual_raw,
        },
    );
}

pub fn bootToMainMenu(h: *Harness) void {
    // Let the ROM run its initialization until the menu is built.
    var cycles: usize = 0;
    const max_cycles: usize = 20_000_000;

    while (cycles < max_cycles and h.state.bus.ram[0x17] == 0) : (cycles += 1) {
        h.state.tick();
    }

    if (h.state.bus.ram[0x17] == 0) {
        @panic("AccuracyCoin menu did not initialize within expected cycle budget");
    }

    // Give the ROM a little extra time to finish any pending PPU work
    for (0..1_000_000) |_| h.state.tick();
}

pub inline fn runCpuBehaviorTest(h: *Harness, which: CpuBehaviorTest) u8 {
    return runTest(h, @intFromEnum(which));
}

pub inline fn runPpuTimingTest(h: *Harness, which: PpuTimingTest) u8 {
    return runTest(h, @intFromEnum(which));
}

// ROM addresses
pub const RUNTEST_ADDR = 0xF9A0;
const TABLETABLE_ADDR = 0x8200;

// Suite indices in TableTable
pub const SUITE_CPU_BEHAVIOR_INDEX = 0;
pub const SUITE_PPU_TIMING_INDEX = 16;

/// Set up a test suite by parsing its table and populating ZP arrays
pub fn setupSuite(h: *Harness, suite_index: u8) void {
    // Initialize JSRFromRAM stub at $001A (JSR opcode $20, RTS opcode $60 at $001D)
    h.state.bus.ram[0x1A] = 0x20; // JSR opcode
    h.state.bus.ram[0x1D] = 0x60; // RTS opcode

    // Read suite pointer from TableTable
    const table_offset = TABLETABLE_ADDR + (@as(u16, suite_index) * 2);
    const suite_lo = h.state.cart.?.cpuRead(table_offset);
    const suite_hi = h.state.cart.?.cpuRead(table_offset + 1);
    const suite_addr = (@as(u16, suite_hi) << 8) | suite_lo;

    // Write suite pointer to ZP $05-$06
    h.state.bus.ram[0x05] = @truncate(suite_addr & 0xFF);
    h.state.bus.ram[0x06] = @truncate((suite_addr >> 8) & 0xFF);

    // Parse suite table and populate ZP arrays
    parseSuiteTable(h, suite_addr);
}

fn parseSuiteTable(h: *Harness, suite_addr: u16) void {
    var offset: u16 = 0;

    // Skip suite name (read until $FF)
    while (h.state.cart.?.cpuRead(suite_addr + offset) != 0xFF) : (offset += 1) {}
    offset += 1; // Skip the $FF

    var test_index: u8 = 0;
    while (true) {
        const first_byte = h.state.cart.?.cpuRead(suite_addr + offset);
        if (first_byte == 0xFF) break; // End of suite

        // Skip test name
        while (h.state.cart.?.cpuRead(suite_addr + offset) != 0xFF) : (offset += 1) {}
        offset += 1; // Skip the $FF terminator

        // Read result pointer (2 bytes)
        const result_lo = h.state.cart.?.cpuRead(suite_addr + offset);
        offset += 1;
        const result_hi = h.state.cart.?.cpuRead(suite_addr + offset);
        offset += 1;

        // Read test entry point (2 bytes)
        const entry_lo = h.state.cart.?.cpuRead(suite_addr + offset);
        offset += 1;
        const entry_hi = h.state.cart.?.cpuRead(suite_addr + offset);
        offset += 1;

        // Store in ZP arrays (suitePointerList at $80, suiteExecPointerList at $A0)
        const idx_offset = @as(usize, test_index) * 2;
        h.state.bus.ram[0x80 + idx_offset] = result_lo;
        h.state.bus.ram[0x81 + idx_offset] = result_hi;
        h.state.bus.ram[0xA0 + idx_offset] = entry_lo;
        h.state.bus.ram[0xA1 + idx_offset] = entry_hi;

        test_index += 1;
    }

    // Set menuHeight
    h.state.bus.ram[0x17] = test_index;
}

/// Run a specific test from the currently loaded suite
pub fn runTest(h: *Harness, test_index: u8) u8 {
    // Clear page 4 and 5 RAM (test result storage area)
    var i: usize = 0x400;
    while (i < 0x600) : (i += 1) {
        h.state.bus.ram[i] = 0;
    }

    // Set test index and mirror menu cursor registers (matches NMI caller)
    h.state.bus.ram[0x16] = test_index; // menuCursorYPos
    h.state.bus.ram[0x15] = 0; // menuCursorXPos (menu keeps cursor left column)
    h.state.cpu.a = test_index;
    h.state.cpu.x = test_index;
    h.state.cpu.y = 0;

    // Ensure we run the menu variant of RunTest (RunningAllTests = 0)
    h.state.bus.ram[0x35] = 0;

    // Get result address before running test
    const idx_offset = @as(usize, test_index) * 2;
    const result_lo = h.state.bus.ram[0x80 + idx_offset];
    const result_hi = h.state.bus.ram[0x81 + idx_offset];
    const result_addr = (@as(u16, result_hi) << 8) | result_lo;
    const result_ram_addr = result_addr & 0x07FF;

    // Push return address onto stack (0xFFFF-1 = 0xFFFE, RTS adds 1 to get 0xFFFF)
    // Note: We must do this BEFORE setting SP, as the stack is in RAM
    h.state.bus.ram[0x01FF] = 0xFF; // High byte of return address
    h.state.bus.ram[0x01FE] = 0xFE; // Low byte of return address - 1
    h.state.cpu.sp = 0xFD; // SP points to next free slot ($01FD)

    // Set PC to RunTest and ensure CPU is in fetch state
    h.state.cpu.pc = RUNTEST_ADDR;
    h.state.cpu.state = .fetch_opcode;

    // Run until RunTest RTS to our return address
    const max_cycles = 100_000_000;
    var cycles: usize = 0;

    while (cycles < max_cycles) : (cycles += 1) {
        h.state.tick();

        // Check if we hit the return address (RunTest completed with RTS)
        if (h.state.cpu.pc == 0xFFFF) {
            break;
        }
    }

    // Read result from result address
    return h.state.bus.ram[result_ram_addr];
}
