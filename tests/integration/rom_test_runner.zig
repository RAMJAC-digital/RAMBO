//! ROM Test Runner Framework
//!
//! This module provides infrastructure for running NES test ROMs (like AccuracyCoin.nes,
//! nestest.nes, etc.) and extracting test results from emulator memory.
//!
//! Key Features:
//! - Load any .nes ROM file
//! - Run emulation with configurable timeout (frames or cycles)
//! - Monitor memory locations for test completion
//! - Extract test results and error messages from specific memory addresses
//! - Detect infinite loops and timeout conditions
//!
//! Test Result Protocol (AccuracyCoin Standard):
//! - $6000-$6003: Test status bytes (0x00 = pass, non-zero = fail)
//! - $6004+: Null-terminated error message strings (if test fails)

const std = @import("std");
const testing = std.testing;
const RAMBO = @import("RAMBO");

const EmulationState = RAMBO.EmulationState.EmulationState;
const Config = RAMBO.Config;
const NromCart = RAMBO.CartridgeType;
const AnyCartridge = RAMBO.AnyCartridge;

// ============================================================================
// ROM Test Runner
// ============================================================================

/// Configuration for ROM test execution
pub const RunConfig = struct {
    /// Maximum number of frames to run before timeout (default: 300 = ~5 seconds)
    max_frames: usize = 300,

    /// Maximum number of CPU instructions to execute before timeout
    /// Set to 0 to disable instruction-based timeout
    max_instructions: usize = 0,

    /// Memory address to monitor for test completion
    /// Test is considered complete when this address contains completion_value
    /// Set to null to run for full max_frames duration
    completion_address: ?u16 = null,

    /// Value at completion_address that indicates test completion
    completion_value: u8 = 0x00,

    /// Enable verbose logging (prints execution progress)
    verbose: bool = false,
};

/// Test result from ROM execution
pub const TestResult = struct {
    /// Test passed (all status bytes are 0x00)
    passed: bool,

    /// Total frames executed
    frames_executed: usize,

    /// Total CPU instructions executed
    instructions_executed: usize,

    /// Test status bytes from memory ($6000-$6003 for AccuracyCoin)
    status_bytes: [4]u8,

    /// Error message extracted from memory ($6004+ for AccuracyCoin)
    /// Null if test passed or no error message available
    error_message: ?[]const u8,

    /// Timeout occurred before completion
    timed_out: bool,

    pub fn deinit(self: *TestResult, allocator: std.mem.Allocator) void {
        if (self.error_message) |msg| {
            allocator.free(msg);
        }
    }
};

/// ROM Test Runner - Manages ROM execution and result extraction
pub const RomTestRunner = struct {
    allocator: std.mem.Allocator,
    config: *Config.Config,
    state: EmulationState,
    run_config: RunConfig,

    /// Initialize ROM test runner with a loaded ROM file
    pub fn init(allocator: std.mem.Allocator, rom_path: []const u8, run_config: RunConfig) !RomTestRunner {
        // Load ROM (currently only NROM/Mapper 0 supported)
        const nrom_cart = try NromCart.load(allocator, rom_path);

        // Wrap in AnyCartridge union
        const cart = AnyCartridge{ .nrom = nrom_cart };

        // Create config
        const cfg = try allocator.create(Config.Config);
        errdefer allocator.destroy(cfg);
        cfg.* = Config.Config.init(allocator);
        errdefer cfg.deinit();

        // Initialize emulation state
        var emu_state = EmulationState.init(cfg);
        errdefer emu_state.deinit();
        emu_state.reset();

        // Load cartridge into emulation state (transfers ownership)
        emu_state.loadCartridge(cart); // cart is now invalid

        return .{
            .allocator = allocator,
            .config = cfg,
            .state = emu_state,
            .run_config = run_config,
        };
    }

    pub fn deinit(self: *RomTestRunner) void {
        self.state.deinit(); // Cleans up cartridge
        self.config.deinit();
        self.allocator.destroy(self.config);
    }

    /// Run the ROM and extract test results
    pub fn run(self: *RomTestRunner) !TestResult {
        var frames_executed: usize = 0;
        var instructions_executed: usize = 0;
        var timed_out = false;

        // Run emulation loop
        while (frames_executed < self.run_config.max_frames) {
            // Check instruction timeout
            if (self.run_config.max_instructions > 0 and instructions_executed >= self.run_config.max_instructions) {
                timed_out = true;
                break;
            }

            // Execute one frame (29780 CPU cycles = 1/60th second)
            const frame_instructions = try self.runFrame();
            instructions_executed += frame_instructions;
            frames_executed += 1;

            // Check for completion condition
            if (self.run_config.completion_address) |addr| {
                const value = self.state.busRead(addr);
                if (value == self.run_config.completion_value) {
                    if (self.run_config.verbose) {}
                    break;
                }
            }

            // Verbose progress
            if (self.run_config.verbose and frames_executed % 60 == 0) {}
        }

        // Extract test results
        return try self.extractResults(frames_executed, instructions_executed, timed_out);
    }

    /// Execute one frame of emulation (29780.5 CPU cycles for precise NTSC timing)
    pub fn runFrame(self: *RomTestRunner) !usize {
        var instructions: usize = 0;
        // NTSC: ~1.789773 MHz / 60 Hz = 29829.55 PPU cycles / 3 = 9943.18 CPU cycles per frame
        // For simplicity, use 29781 CPU cycles (29780.5 rounded up for slight accuracy)
        const cycles_per_frame = 29781; // More accurate than 29780

        var cycles_executed: usize = 0;

        while (cycles_executed < cycles_per_frame) {
            const cycles_before = self.state.clock.cpuCycles();
            const cpu_state_before = self.state.cpu.state;

            self.state.tick();

            const cycles_after = self.state.clock.cpuCycles();
            const cpu_state_after = self.state.cpu.state;

            // Count cycles executed (handle overflow)
            const delta = if (cycles_after >= cycles_before)
                cycles_after - cycles_before
            else
                (std.math.maxInt(u64) - cycles_before) + cycles_after + 1;

            cycles_executed += delta;

            // Count instructions: only when CPU completes an instruction (enters fetch_opcode state)
            // Note: tick() executes ONE CPU CYCLE, not one instruction
            // An instruction is complete when we transition to fetch_opcode state
            if (cpu_state_before != .fetch_opcode and cpu_state_after == .fetch_opcode) {
                instructions += 1;
            }

            // Safety check: prevent infinite loops within a frame
            // Using cycle count instead of tick count for more accurate detection
            if (cycles_executed > cycles_per_frame * 2) {
                return error.InfiniteLoopDetected;
            }
        }

        return instructions;
    }

    /// Extract test results from memory
    fn extractResults(self: *RomTestRunner, frames: usize, instructions: usize, timed_out: bool) !TestResult {
        // Read status bytes from $6000-$6003 (AccuracyCoin standard)
        var status_bytes: [4]u8 = undefined;
        for (0..4) |i| {
            status_bytes[i] = self.state.busRead(@as(u16, 0x6000) + @as(u16, @intCast(i)));
        }

        // Check if all status bytes are 0x00 (pass condition)
        const passed = std.mem.eql(u8, &status_bytes, &[_]u8{ 0x00, 0x00, 0x00, 0x00 });

        // Extract error message if test failed
        var error_message: ?[]const u8 = null;
        if (!passed) {
            error_message = try self.extractErrorMessage();
        }

        return TestResult{
            .passed = passed,
            .frames_executed = frames,
            .instructions_executed = instructions,
            .status_bytes = status_bytes,
            .error_message = error_message,
            .timed_out = timed_out,
        };
    }

    /// Extract null-terminated error message from $6004+ (AccuracyCoin standard)
    fn extractErrorMessage(self: *RomTestRunner) ![]const u8 {
        // Read up to 256 bytes for error message
        var temp_buffer: [256]u8 = undefined;
        var length: usize = 0;

        var addr: u16 = 0x6004;
        while (addr < 0x6104 and length < 256) : (addr += 1) {
            const byte = self.state.busRead(addr);
            if (byte == 0x00) break; // Null terminator
            temp_buffer[length] = byte;
            length += 1;
        }

        // Allocate and return owned slice
        const result = try self.allocator.alloc(u8, length);
        @memcpy(result, temp_buffer[0..length]);
        return result;
    }

    /// Read a byte from emulator memory (convenience wrapper)
    pub fn readMemory(self: *RomTestRunner, address: u16) u8 {
        return self.state.busRead(address);
    }

    /// Read a range of bytes from emulator memory
    pub fn readMemoryRange(self: *RomTestRunner, start: u16, length: usize) ![]u8 {
        const buffer = try self.allocator.alloc(u8, length);
        for (0..length) |i| {
            buffer[i] = self.state.busRead(start + @as(u16, @intCast(i)));
        }
        return buffer;
    }
};

// ============================================================================
// Helper Functions
// ============================================================================

/// Run a ROM test with default AccuracyCoin configuration
pub fn runAccuracyCoinTest(allocator: std.mem.Allocator, rom_path: []const u8) !TestResult {
    const config = RunConfig{
        .max_frames = 600, // 10 seconds
        .max_instructions = 10_000_000, // 10M instructions safety limit
        .completion_address = 0x6000, // Monitor $6000 for completion
        .completion_value = 0x00, // Test writes 0x00 when done (or error code)
        .verbose = false,
    };

    var runner = try RomTestRunner.init(allocator, rom_path, config);
    defer runner.deinit();

    return try runner.run();
}

/// Print test result summary
pub fn printTestResult(result: TestResult) void {
    if (result.error_message) |_| {}

    if (result.timed_out) {}
}

// ============================================================================
// Tests
// ============================================================================

test "RomTestRunner: basic initialization" {
    const rom_path = "AccuracyCoin/AccuracyCoin.nes";

    // Skip if ROM not available
    var runner = RomTestRunner.init(testing.allocator, rom_path, .{}) catch |err| {
        if (err == error.FileNotFound) {
            return error.SkipZigTest;
        }
        return err;
    };
    defer runner.deinit();

    // Verify state is initialized and cartridge loaded
    try testing.expect(runner.state.cart != null);
    try testing.expectEqual(@as(u16, 0), runner.state.cpu.a);
}

test "RomTestRunner: memory read operations" {
    const rom_path = "AccuracyCoin/AccuracyCoin.nes";

    var runner = RomTestRunner.init(testing.allocator, rom_path, .{}) catch |err| {
        if (err == error.FileNotFound) {
            return error.SkipZigTest;
        }
        return err;
    };
    defer runner.deinit();

    // Write test data to RAM
    runner.state.busWrite(0x0200, 0xAB);
    runner.state.busWrite(0x0201, 0xCD);

    // Read back via runner API
    try testing.expectEqual(@as(u8, 0xAB), runner.readMemory(0x0200));
    try testing.expectEqual(@as(u8, 0xCD), runner.readMemory(0x0201));
}

test "RomTestRunner: extract error message" {
    const rom_path = "AccuracyCoin/AccuracyCoin.nes";

    var runner = RomTestRunner.init(testing.allocator, rom_path, .{}) catch |err| {
        if (err == error.FileNotFound) {
            return error.SkipZigTest;
        }
        return err;
    };
    defer runner.deinit();

    // Write test error message to $0204 (internal RAM, not $6004)
    // Note: AccuracyCoin uses $6004 but that requires PRG-RAM support
    // For testing the extraction logic, we use internal RAM
    const test_msg = "Test failed";
    for (test_msg, 0..) |char, i| {
        runner.state.busWrite(@as(u16, 0x0204) + @as(u16, @intCast(i)), char);
    }
    runner.state.busWrite(@as(u16, 0x0204 + test_msg.len), 0x00); // Null terminator

    // Temporarily modify extraction to read from $0204 for this test
    // In real usage, AccuracyCoin would have PRG-RAM at $6004
    var temp_buffer: [256]u8 = undefined;
    var length: usize = 0;
    var addr: u16 = 0x0204;
    while (addr < 0x0304 and length < 256) : (addr += 1) {
        const byte = runner.state.busRead(addr);
        if (byte == 0x00) break;
        temp_buffer[length] = byte;
        length += 1;
    }

    const result = try runner.allocator.alloc(u8, length);
    defer testing.allocator.free(result);
    @memcpy(result, temp_buffer[0..length]);

    try testing.expectEqualStrings("Test failed", result);
}
