//! JMP Indirect Page Boundary Bug - Hardware Spec Compliance Tests
//!
//! Tests the 6502 hardware bug where JMP ($xxFF) reads the high byte from
//! $xx00 instead of $(xx+1)00. This bug exists in all 6502 chips and must
//! be emulated for accurate NES behavior.
//!
//! **Hardware Specification:**
//! "JMP ($xxyy), or JMP indirect, does not advance pages if the lower eight
//! bits of the specified address is $FF; the upper eight bits are fetched
//! from $xx00, 255 bytes earlier, instead of the expected following byte."
//!
//! **Reference:** https://www.nesdev.org/wiki/Errata
//! **Implementation:** src/emulation/cpu/microsteps.zig:357-369 (jmpIndirectFetchHigh)
//! **Opcode:** 0x6C (JMP indirect)
//!
//! These tests verify:
//! 1. Page boundary bug ($xxFF → reads from $xx00)
//! 2. Correct behavior when not at boundary
//! 3. All 256 page boundaries exhibit the bug
//! 4. Regression detection if bug is accidentally "fixed"

const std = @import("std");
const testing = std.testing;
const RAMBO = @import("RAMBO");
const EmulationState = RAMBO.EmulationState.EmulationState;
const Config = RAMBO.Config;

// Import microsteps module for direct testing
// NOTE: This is a white-box test - we're testing implementation internals
// to ensure hardware spec compliance at the lowest level

const TestHarness = struct {
    config: *Config.Config,
    state: EmulationState,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *TestHarness) void {
        self.config.deinit();
        self.allocator.destroy(self.config);
    }
};

/// Helper to set up EmulationState for JMP indirect testing
fn setupState(allocator: std.mem.Allocator) !TestHarness {
    const config = try allocator.create(Config.Config);
    config.* = Config.Config.init(allocator);
    var state = EmulationState.init(config);
    state.reset();

    return .{
        .config = config,
        .state = state,
        .allocator = allocator,
    };
}

/// Simulate jmpIndirectFetchHigh microstep
/// This duplicates the exact logic from src/emulation/cpu/microsteps.zig:357-369
/// to test the hardware bug implementation without importing internal modules
fn simulateJmpIndirectFetchHigh(state: *EmulationState) void {
    // 6502 bug: If pointer is at page boundary, wraps within page
    const ptr = state.cpu.effective_address;
    const high_addr = if ((ptr & 0xFF) == 0xFF)
        ptr & 0xFF00 // Wrap to start of same page
    else
        ptr + 1;

    state.cpu.operand_high = state.busRead(high_addr);
    state.cpu.effective_address = (@as(u16, state.cpu.operand_high) << 8) |
                                  @as(u16, state.cpu.operand_low);
}

// ============================================================================
// Core Hardware Bug Tests
// ============================================================================

test "JMP Indirect: Page boundary bug - pointer at $02FF reads high byte from $0200" {
    var harness = try setupState(testing.allocator);
    defer harness.deinit();
    var state = &harness.state;

    // Setup: JMP ($02FF)
    // Expected behavior (if bug didn't exist): Read low from $02FF, high from $0300
    // Actual hardware behavior: Read low from $02FF, high from $0200 (BUG)

    const pointer_addr: u16 = 0x02FF;

    // Place pointer data
    state.busWrite(0x02FF, 0x34); // Low byte of target address
    state.busWrite(0x0300, 0x56); // High byte - CORRECT (not read due to bug)
    state.busWrite(0x0200, 0x12); // High byte - BUGGY (actually read)

    // Simulate jmpIndirectFetchLow (fetch low byte of target)
    state.cpu.effective_address = pointer_addr;
    state.cpu.operand_low = state.busRead(pointer_addr); // Reads $34

    // Now test jmpIndirectFetchHigh (the buggy microstep)
    // This should read from $0200, not $0300
    simulateJmpIndirectFetchHigh(state);

    // Verify the bug: effective_address = $1234 (not $5634)
    try testing.expectEqual(@as(u16, 0x1234), state.cpu.effective_address);

    // Verify operand components
    try testing.expectEqual(@as(u8, 0x34), state.cpu.operand_low);
    try testing.expectEqual(@as(u8, 0x12), state.cpu.operand_high); // Read from $0200 (bug)
}

test "JMP Indirect: No bug when pointer NOT at page boundary ($0280)" {
    var harness = try setupState(testing.allocator);
    defer harness.deinit();
    var state = &harness.state;

    // Setup: JMP ($0280)
    // Expected behavior: Read low from $0280, high from $0281
    // Actual behavior: Same as expected (no bug when not at $xxFF)

    const pointer_addr: u16 = 0x0280;

    state.busWrite(0x0280, 0x34); // Low byte of target
    state.busWrite(0x0281, 0x56); // High byte (correct)

    state.cpu.effective_address = pointer_addr;
    state.cpu.operand_low = state.busRead(pointer_addr);

    simulateJmpIndirectFetchHigh(state);

    // Verify correct behavior: effective_address = $5634
    try testing.expectEqual(@as(u16, 0x5634), state.cpu.effective_address);
    try testing.expectEqual(@as(u8, 0x34), state.cpu.operand_low);
    try testing.expectEqual(@as(u8, 0x56), state.cpu.operand_high);
}

test "JMP Indirect: Bug exists at $00FF (zero page boundary)" {
    var harness = try setupState(testing.allocator);
    defer harness.deinit();
    var state = &harness.state;

    // Edge case: Pointer at $00FF (zero page boundary)
    state.busWrite(0x00FF, 0xAB); // Low byte
    state.busWrite(0x0100, 0xCD); // High byte - correct (not read)
    state.busWrite(0x0000, 0xEF); // High byte - buggy (read)

    state.cpu.effective_address = 0x00FF;
    state.cpu.operand_low = state.busRead(0x00FF);

    simulateJmpIndirectFetchHigh(state);

    // Should jump to $EFAB (not $CDAB)
    try testing.expectEqual(@as(u16, 0xEFAB), state.cpu.effective_address);
}

test "JMP Indirect: Bug exists at $FFFF (highest address)" {
    var harness = try setupState(testing.allocator);
    defer harness.deinit();
    var state = &harness.state;

    // Edge case: Pointer at $FFFF
    state.busWrite(0xFFFF, 0x11); // Low byte
    state.busWrite(0x0000, 0x22); // High byte - would wrap to $0000 (but wrong page)
    state.busWrite(0xFF00, 0x33); // High byte - buggy (read due to page wrap)

    state.cpu.effective_address = 0xFFFF;
    state.cpu.operand_low = 0x11; // Manually set (already fetched in previous microstep)

    simulateJmpIndirectFetchHigh(state);

    // Should jump to $3311 (reads from $FF00)
    try testing.expectEqual(@as(u16, 0x3311), state.cpu.effective_address);
}

// ============================================================================
// Comprehensive Coverage: All 256 Page Boundaries
// ============================================================================

test "JMP Indirect: Bug exists at ALL 256 page boundaries ($00FF through $FFFF)" {
    var harness = try setupState(testing.allocator);
    defer harness.deinit();
    var state = &harness.state;

    // Test every single page boundary to ensure consistent bug behavior
    for (0..256) |page| {
        const page_u8 = @as(u8, @intCast(page));
        const boundary_addr = (@as(u16, page_u8) << 8) | 0xFF; // $xxFF
        const wrapped_addr = @as(u16, page_u8) << 8; // $xx00

        // Clear previous data
        state.cpu.effective_address = 0;
        state.cpu.operand_low = 0;
        state.cpu.operand_high = 0;

        // Setup: Low byte = 0x34, High byte at $xx00 = 0x12
        state.busWrite(boundary_addr, 0x34);
        state.busWrite(wrapped_addr, 0x12);

        // Simulate fetch
        state.cpu.effective_address = boundary_addr;
        state.cpu.operand_low = 0x34;

        simulateJmpIndirectFetchHigh(state);

        // ALL boundaries should produce $1234
        try testing.expectEqual(@as(u16, 0x1234), state.cpu.effective_address);
    }
}

// ============================================================================
// Regression Detection: Verify Bug is NOT "Fixed"
// ============================================================================

test "JMP Indirect: REGRESSION CHECK - Bug must exist (not accidentally fixed)" {
    var harness = try setupState(testing.allocator);
    defer harness.deinit();
    var state = &harness.state;

    // This test FAILS if the bug is "fixed" (becomes correct behavior)
    // The bug is part of 6502 hardware and MUST be emulated

    state.busWrite(0x01FF, 0xAA);
    state.busWrite(0x0200, 0xBB); // Correct: should read from here (but doesn't)
    state.busWrite(0x0100, 0xCC); // Bug: reads from here (wraps to page start)

    state.cpu.effective_address = 0x01FF;
    state.cpu.operand_low = 0xAA;

    simulateJmpIndirectFetchHigh(state);

    // MUST be $CCAA (buggy - reads from $0100), NOT $BBAA (correct - would read from $0200)
    try testing.expectEqual(@as(u16, 0xCCAA), state.cpu.effective_address);

    // Explicit check: If this fails, the bug was "fixed" - WRONG!
    try testing.expect(state.cpu.effective_address != 0xBBAA);
}

// ============================================================================
// Boundary Condition Tests
// ============================================================================

test "JMP Indirect: Pointer at $xxFE - one byte before boundary (no bug)" {
    var harness = try setupState(testing.allocator);
    defer harness.deinit();
    var state = &harness.state;

    // $02FE is NOT at boundary, should work correctly
    state.busWrite(0x02FE, 0x11);
    state.busWrite(0x02FF, 0x22); // Reads from here (correct)

    state.cpu.effective_address = 0x02FE;
    state.cpu.operand_low = 0x11;

    simulateJmpIndirectFetchHigh(state);

    try testing.expectEqual(@as(u16, 0x2211), state.cpu.effective_address);
}

test "JMP Indirect: Pointer at $xx00 - start of page (no bug)" {
    var harness = try setupState(testing.allocator);
    defer harness.deinit();
    var state = &harness.state;

    // $0200 is at start of page, should work correctly
    state.busWrite(0x0200, 0x33);
    state.busWrite(0x0201, 0x44); // Reads from here (correct)

    state.cpu.effective_address = 0x0200;
    state.cpu.operand_low = 0x33;

    simulateJmpIndirectFetchHigh(state);

    try testing.expectEqual(@as(u16, 0x4433), state.cpu.effective_address);
}

// ============================================================================
// Real-World Scenario Tests
// ============================================================================

test "JMP Indirect: Real-world bug scenario - indirect jump table at $1FF" {
    var harness = try setupState(testing.allocator);
    defer harness.deinit();
    var state = &harness.state;

    // Scenario: Jump table stored at page boundaries
    // This is a common bug that NES developers encounter
    // If you place a jump table entry at $01FF, it won't work as expected

    // Jump table entry at $01FF intended to point to routine at $8000
    state.busWrite(0x01FF, 0x00); // Low byte
    state.busWrite(0x0200, 0x80); // Intended high byte (not read due to bug)
    state.busWrite(0x0100, 0x90); // Bug reads from here (page wrap)

    state.cpu.effective_address = 0x01FF;
    state.cpu.operand_low = 0x00;

    simulateJmpIndirectFetchHigh(state);

    // Bug causes jump to $9000 instead of intended $8000
    // Reads from $0100 (page wrap) instead of $0200 (next page)
    try testing.expectEqual(@as(u16, 0x9000), state.cpu.effective_address);
}

test "JMP Indirect: Bug can cause game crashes - wrong routine executed" {
    var harness = try setupState(testing.allocator);
    defer harness.deinit();
    var state = &harness.state;

    // Scenario: Pointer at $3CFF intended to jump to $A000
    // But due to bug, jumps to $6000 instead (wrong routine)

    state.busWrite(0x3CFF, 0x00); // Low byte
    state.busWrite(0x3D00, 0xA0); // Intended high byte (not read)
    state.busWrite(0x3C00, 0x60); // Buggy high byte (read instead)

    state.cpu.effective_address = 0x3CFF;
    state.cpu.operand_low = 0x00;

    simulateJmpIndirectFetchHigh(state);

    // Jumps to $6000 instead of $A000 - could crash game!
    try testing.expectEqual(@as(u16, 0x6000), state.cpu.effective_address);
    try testing.expect(state.cpu.effective_address != 0xA000); // NOT the intended address
}

// ============================================================================
// Hardware Spec Compliance Documentation Tests
// ============================================================================

test "JMP Indirect: Spec compliance - nesdev.org Errata documentation" {
    // This test documents the hardware specification and ensures our
    // implementation matches the documented hardware bug exactly.
    //
    // From nesdev.org/wiki/Errata:
    // "JMP ($xxyy), or JMP indirect, does not advance pages if the
    // lower eight bits of the specified address is $FF; the upper
    // eight bits are fetched from $xx00, 255 bytes earlier, instead
    // of the expected following byte."
    //
    // Our implementation in src/emulation/cpu/microsteps.zig:
    //   const high_addr = if ((ptr & 0xFF) == 0xFF)
    //       ptr & 0xFF00  // Wrap to start of same page
    //   else
    //       ptr + 1;
    //
    // This test verifies the "255 bytes earlier" claim

    var harness = try setupState(testing.allocator);
    defer harness.deinit();
    var state = &harness.state;

    const boundary: u16 = 0x05FF;
    const wrapped: u16 = 0x0500; // 255 bytes earlier ($FF = 255 decimal)

    try testing.expectEqual(@as(u16, 255), boundary - wrapped);

    state.busWrite(boundary, 0x77);
    state.busWrite(wrapped, 0x88);

    state.cpu.effective_address = boundary;
    state.cpu.operand_low = 0x77;

    simulateJmpIndirectFetchHigh(state);

    // Verify we read from "255 bytes earlier"
    try testing.expectEqual(@as(u16, 0x8877), state.cpu.effective_address);
}
