//! Debugger Isolation Tests
//!
//! Tests verify complete isolation between debugger and runtime execution:
//! - Zero shared mutable state
//! - Side-effect isolation (memory inspection doesn't affect open bus)
//! - RT-safety verification (no heap allocations in hot paths)
//! - TAS (Tool-Assisted Speedrun) support for intentional undefined behaviors
//! - Compile-time const enforcement

const std = @import("std");
const testing = std.testing;
const RAMBO = @import("RAMBO");

const Debugger = RAMBO.Debugger.Debugger;
const DebugMode = RAMBO.Debugger.DebugMode;
const BreakpointType = RAMBO.Debugger.BreakpointType;

const EmulationState = RAMBO.EmulationState.EmulationState;
const Config = RAMBO.Config.Config;

const test_fixtures = @import("test_fixtures.zig");

// ============================================================================
// Phase 1.4: Side-Effect Isolation Tests
// ============================================================================

test "Memory Inspection: readMemory does not affect open bus" {
    var config = Config.init(testing.allocator);
    defer config.deinit();

    var debugger = Debugger.init(testing.allocator, &config);
    defer debugger.deinit();

    var state = test_fixtures.createTestState(&config);

    // Set open bus to known value
    state.bus.open_bus = 0x42;
    const original_value = state.bus.open_bus;
    // Cycle tracking removed: open_bus is now just u8

    // Read memory via debugger (should NOT affect open bus)
    _ = debugger.readMemory(&state, 0x0200);

    // ✅ Verify open bus unchanged
    try testing.expectEqual(original_value, state.bus.open_bus);
}

test "Memory Inspection: readMemoryRange does not affect open bus" {
    var config = Config.init(testing.allocator);
    defer config.deinit();

    var debugger = Debugger.init(testing.allocator, &config);
    defer debugger.deinit();

    var state = test_fixtures.createTestState(&config);

    // Set open bus to known value
    state.bus.open_bus = 0x99;
    const original_value = state.bus.open_bus;
    // Cycle tracking removed: open_bus is now just u8

    // Read memory range via debugger
    const buffer = try debugger.readMemoryRange(testing.allocator, &state, 0x0100, 16);
    defer testing.allocator.free(buffer);

    // ✅ Verify open bus unchanged after multiple reads
    try testing.expectEqual(original_value, state.bus.open_bus);
}

test "Memory Inspection: multiple reads preserve state" {
    var config = Config.init(testing.allocator);
    defer config.deinit();

    var debugger = Debugger.init(testing.allocator, &config);
    defer debugger.deinit();

    var state = test_fixtures.createTestState(&config);

    // Capture initial state
    state.bus.open_bus = 0xAA;
    const initial_value = state.bus.open_bus;

    // Perform 1000 debugger reads
    for (0..1000) |i| {
        _ = debugger.readMemory(&state, @intCast(i % 256));
    }

    // ✅ Open bus should still be unchanged
    try testing.expectEqual(initial_value, state.bus.open_bus);
}

// ============================================================================
// Phase 2.5: RT-Safety Verification Tests
// ============================================================================

test "RT-Safety: shouldBreak() uses no heap allocation" {
    var config = Config.init(testing.allocator);
    defer config.deinit();

    var debugger = Debugger.init(testing.allocator, &config);
    defer debugger.deinit();

    var state = test_fixtures.createTestState(&config);

    // Add breakpoint
    try debugger.addBreakpoint(0x8000, .execute);
    state.cpu.pc = 0x8000;

    // Track allocations before shouldBreak()
    const allocations_before = testing.allocator_instance.total_requested_bytes;

    // Trigger breakpoint (should NOT allocate)
    _ = try debugger.shouldBreak(&state);

    const allocations_after = testing.allocator_instance.total_requested_bytes;

    // ✅ Verify zero allocations in hot path
    try testing.expectEqual(allocations_before, allocations_after);
}

test "RT-Safety: checkMemoryAccess() uses no heap allocation" {
    var config = Config.init(testing.allocator);
    defer config.deinit();

    var debugger = Debugger.init(testing.allocator, &config);
    defer debugger.deinit();

    var state = test_fixtures.createTestState(&config);

    // Add memory breakpoint and watchpoint
    try debugger.addBreakpoint(0x2000, .write);
    try debugger.addWatchpoint(0x2001, 1, .write);

    // Track allocations
    const allocations_before = testing.allocator_instance.total_requested_bytes;

    // Trigger memory breakpoint (should NOT allocate)
    _ = try debugger.checkMemoryAccess(&state, 0x2000, 0x42, true);

    const allocations_after = testing.allocator_instance.total_requested_bytes;

    // ✅ Verify zero allocations
    try testing.expectEqual(allocations_before, allocations_after);
}

test "RT-Safety: break reason accessible after trigger" {
    var config = Config.init(testing.allocator);
    defer config.deinit();

    var debugger = Debugger.init(testing.allocator, &config);
    defer debugger.deinit();

    var state = test_fixtures.createTestState(&config);

    // Initially no break reason
    try testing.expect(debugger.getBreakReason() == null);

    // Add and trigger breakpoint
    try debugger.addBreakpoint(0x8000, .execute);
    state.cpu.pc = 0x8000;
    _ = try debugger.shouldBreak(&state);

    // ✅ Verify break reason is set and accessible
    const reason = debugger.getBreakReason();
    try testing.expect(reason != null);
    try testing.expect(std.mem.containsAtLeast(u8, reason.?, 1, "Breakpoint"));

    // Verify it contains address
    try testing.expect(std.mem.containsAtLeast(u8, reason.?, 1, "8000"));
}

// ============================================================================
// Phase 3: Bounded Modifications History Tests
// ============================================================================

test "Modification History: bounded to max size" {
    var config = Config.init(testing.allocator);
    defer config.deinit();

    var debugger = Debugger.init(testing.allocator, &config);
    defer debugger.deinit();

    // Set small max size for testing
    debugger.state.modifications_max_size = 10;

    var state = test_fixtures.createTestState(&config);

    // Add 20 modifications (2x max size)
    for (0..20) |i| {
        debugger.setRegisterA(&state, @intCast(i));
    }

    // ✅ Should be bounded to 10
    const mods = debugger.getModifications();
    try testing.expectEqual(@as(usize, 10), mods.len);

    // ✅ Should contain most recent 10 (values 10-19)
    try testing.expectEqual(@as(u8, 10), mods[0].register_a);
    try testing.expectEqual(@as(u8, 19), mods[9].register_a);
}

test "Modification History: circular buffer behavior" {
    var config = Config.init(testing.allocator);
    defer config.deinit();

    var debugger = Debugger.init(testing.allocator, &config);
    defer debugger.deinit();

    debugger.state.modifications_max_size = 5;

    var state = test_fixtures.createTestState(&config);

    // Add 3 modifications
    debugger.setRegisterA(&state, 0x11);
    debugger.setRegisterX(&state, 0x22);
    debugger.setRegisterY(&state, 0x33);

    try testing.expectEqual(@as(usize, 3), debugger.getModifications().len);

    // Add 5 more (total 8, should wrap to 5)
    for (0..5) |i| {
        debugger.setProgramCounter(&state, @intCast(0x8000 + i));
    }

    // ✅ Should have exactly 5 entries
    try testing.expectEqual(@as(usize, 5), debugger.getModifications().len);

    // ✅ First 3 should be removed, remaining are last 5 PC changes
    const mods = debugger.getModifications();
    try testing.expect(mods[0] == .program_counter);
    try testing.expectEqual(@as(u16, 0x8000), mods[0].program_counter);
    try testing.expectEqual(@as(u16, 0x8004), mods[4].program_counter);
}

// ============================================================================
// TAS (Tool-Assisted Speedrun) Support Tests
// ============================================================================
// These tests verify that the debugger supports TAS workflows including
// intentional undefined behaviors, corruption, and edge cases.

test "TAS Support: PC in RAM for ACE (Arbitrary Code Execution)" {
    var config = Config.init(testing.allocator);
    defer config.deinit();

    var debugger = Debugger.init(testing.allocator, &config);
    defer debugger.deinit();

    var state = test_fixtures.createTestState(&config);

    // Write crafted "code" to RAM (actually data)
    // Example: LDA #$42 (0xA9 0x42), RTS (0x60)
    debugger.writeMemory(&state, 0x0200, 0xA9); // LDA immediate
    debugger.writeMemory(&state, 0x0201, 0x42); // Value
    debugger.writeMemory(&state, 0x0202, 0x60); // RTS

    // ✅ Set PC to RAM address (ACE technique)
    debugger.setProgramCounter(&state, 0x0200);
    try testing.expectEqual(@as(u16, 0x0200), state.cpu.pc);

    // ✅ Verify modification logged
    const mods = debugger.getModifications();
    try testing.expect(mods.len >= 1);

    // CPU will now execute RAM as code (ACE exploit)
    // This is INTENTIONAL for TAS - debugger does NOT prevent this
}

test "TAS Support: ROM write intent tracking" {
    var config = Config.init(testing.allocator);
    defer config.deinit();

    var debugger = Debugger.init(testing.allocator, &config);
    defer debugger.deinit();

    var state = test_fixtures.createTestState(&config);

    // Clear modifications history
    debugger.clearHistory();

    // ✅ Write to ROM region (hardware-protected, write won't succeed)
    debugger.writeMemory(&state, 0x8000, 0xFF);
    debugger.writeMemory(&state, 0xFFFC, 0x00); // NMI vector (ROM)

    // ✅ Verify writes are LOGGED even though they don't modify ROM
    // This is intentional - debugger tracks INTENT for TAS documentation
    const mods = debugger.getModifications();
    try testing.expectEqual(@as(usize, 2), mods.len);
    try testing.expect(mods[0] == .memory_write);
    try testing.expectEqual(@as(u16, 0x8000), mods[0].memory_write.address);
    try testing.expectEqual(@as(u8, 0xFF), mods[0].memory_write.value);

    // ✅ Data bus is updated even though ROM isn't modified
    try testing.expectEqual(@as(u8, 0x00), state.bus.open_bus);
}

test "TAS Support: Stack overflow and underflow edge cases" {
    var config = Config.init(testing.allocator);
    defer config.deinit();

    var debugger = Debugger.init(testing.allocator, &config);
    defer debugger.deinit();

    var state = test_fixtures.createTestState(&config);

    // ✅ Test stack overflow (SP = 0x00)
    debugger.setStackPointer(&state, 0x00);
    try testing.expectEqual(@as(u8, 0x00), state.cpu.sp);
    // Stack now at $0100 - pushes will wrap to $01FF

    // ✅ Test stack underflow (SP = 0xFF)
    debugger.setStackPointer(&state, 0xFF);
    try testing.expectEqual(@as(u8, 0xFF), state.cpu.sp);
    // Stack now at $01FF - pops will wrap to $0100

    // ✅ Verify modifications logged
    const mods = debugger.getModifications();
    try testing.expect(mods.len >= 2);

    // This is INTENTIONAL - TAS uses stack manipulation for wrong warps
    // The emulator allows these edge cases without protection
}

test "TAS Support: Unusual status flag combinations" {
    var config = Config.init(testing.allocator);
    defer config.deinit();

    var debugger = Debugger.init(testing.allocator, &config);
    defer debugger.deinit();

    var state = test_fixtures.createTestState(&config);

    // ✅ Set decimal flag (normally ignored on NES)
    debugger.setStatusRegister(&state, 0b00001000); // D flag only
    try testing.expect(state.cpu.p.decimal);
    try testing.expect(!state.cpu.p.carry);
    try testing.expect(!state.cpu.p.zero);

    // ✅ Set all flags simultaneously (unusual but valid)
    debugger.setStatusRegister(&state, 0xFF);
    try testing.expect(state.cpu.p.carry);
    try testing.expect(state.cpu.p.zero);
    try testing.expect(state.cpu.p.interrupt);
    try testing.expect(state.cpu.p.decimal);
    try testing.expect(state.cpu.p.overflow);
    try testing.expect(state.cpu.p.negative);

    // ✅ Clear all flags (also unusual)
    debugger.setStatusRegister(&state, 0x00);
    try testing.expect(!state.cpu.p.carry);
    try testing.expect(!state.cpu.p.zero);
    try testing.expect(!state.cpu.p.interrupt);
    try testing.expect(!state.cpu.p.decimal);
    try testing.expect(!state.cpu.p.overflow);
    try testing.expect(!state.cpu.p.negative);

    // All combinations are INTENTIONAL - TAS may use unusual states
}

test "TAS Support: PC in I/O region (undefined behavior)" {
    var config = Config.init(testing.allocator);
    defer config.deinit();

    var debugger = Debugger.init(testing.allocator, &config);
    defer debugger.deinit();

    var state = test_fixtures.createTestState(&config);

    // ✅ Set PC to PPU register region (undefined behavior)
    debugger.setProgramCounter(&state, 0x2000); // PPUCTRL
    try testing.expectEqual(@as(u16, 0x2000), state.cpu.pc);

    // ✅ Set PC to APU register region
    debugger.setProgramCounter(&state, 0x4000); // APU
    try testing.expectEqual(@as(u16, 0x4000), state.cpu.pc);

    // ✅ Set PC to controller I/O region
    debugger.setProgramCounter(&state, 0x4016); // Controller 1
    try testing.expectEqual(@as(u16, 0x4016), state.cpu.pc);

    // ✅ Verify modifications logged
    const mods = debugger.getModifications();
    try testing.expect(mods.len >= 3);

    // This is INTENTIONAL - debugger does NOT prevent undefined behaviors
    // CPU will attempt to execute I/O reads as opcodes (may crash/glitch)
    // TAS users may intentionally create these states for exploits
}

// ============================================================================
// Isolation Verification Tests
// ============================================================================
// These tests verify complete isolation between debugger and runtime:
// - Zero shared mutable state
// - Debugger operations don't affect runtime
// - Runtime execution doesn't corrupt debugger state

test "Isolation: Debugger state changes don't affect runtime" {
    var config = Config.init(testing.allocator);
    defer config.deinit();

    var debugger = Debugger.init(testing.allocator, &config);
    defer debugger.deinit();

    const state = test_fixtures.createTestState(&config);

    // Capture original runtime state
    const orig_pc = state.cpu.pc;
    const orig_a = state.cpu.a;
    const orig_sp = state.cpu.sp;
    const orig_bus = state.bus.open_bus;

    // Perform debugger operations (should NOT affect runtime)
    try debugger.addBreakpoint(0x8100, .execute);
    try debugger.addWatchpoint(0x0200, 1, .write);
    debugger.state.mode = .paused;
    debugger.clearHistory();

    // ✅ Verify runtime state UNCHANGED
    try testing.expectEqual(orig_pc, state.cpu.pc);
    try testing.expectEqual(orig_a, state.cpu.a);
    try testing.expectEqual(orig_sp, state.cpu.sp);
    try testing.expectEqual(orig_bus, state.bus.open_bus);

    // Debugger and runtime are COMPLETELY ISOLATED
}

test "Isolation: Runtime execution doesn't corrupt debugger state" {
    var config = Config.init(testing.allocator);
    defer config.deinit();

    var debugger = Debugger.init(testing.allocator, &config);
    defer debugger.deinit();

    var state = test_fixtures.createTestState(&config);

    // Set up debugger state
    try debugger.addBreakpoint(0x8000, .execute);
    try debugger.addWatchpoint(0x0200, 1, .write);
    debugger.setRegisterA(&state, 0x42);
    debugger.setProgramCounter(&state, 0x8000);

    const mod_count_before = debugger.getModifications().len;

    // Simulate runtime operations (direct state manipulation)
    state.cpu.a = 0x99; // Direct write (NOT via debugger)
    state.cpu.pc = 0x8050;
    state.busWrite(0x0200, 0xFF);
    state.clock.ppu_cycles = 200 * 341; // Scanline 200

    // ✅ Verify debugger state UNCHANGED
    try testing.expectEqual(@as(usize, 1), debugger.state.breakpoint_count);
    try testing.expectEqual(@as(usize, 1), debugger.state.watchpoint_count);
    // Find and verify breakpoint address
    var found_bp_addr: u16 = 0;
    for (debugger.state.breakpoints[0..256]) |maybe_bp| {
        if (maybe_bp) |bp| {
            found_bp_addr = bp.address;
            break;
        }
    }
    try testing.expectEqual(@as(u16, 0x8000), found_bp_addr);
    // Find and verify watchpoint address
    var found_wp_addr: u16 = 0;
    for (debugger.state.watchpoints[0..256]) |maybe_wp| {
        if (maybe_wp) |wp| {
            found_wp_addr = wp.address;
            break;
        }
    }
    try testing.expectEqual(@as(u16, 0x0200), found_wp_addr);

    // ✅ Modification history UNCHANGED (runtime ops don't log to debugger)
    try testing.expectEqual(mod_count_before, debugger.getModifications().len);

    // Runtime and debugger are COMPLETELY ISOLATED
}

test "Isolation: Breakpoint state isolation from runtime" {
    var config = Config.init(testing.allocator);
    defer config.deinit();

    var debugger = Debugger.init(testing.allocator, &config);
    defer debugger.deinit();

    var state = test_fixtures.createTestState(&config);

    // Add breakpoints via debugger
    try debugger.addBreakpoint(0x8000, .execute);
    try debugger.addBreakpoint(0x8010, .write);
    try debugger.addBreakpoint(0x8020, .read);

    // Capture breakpoint count
    const bp_count = debugger.state.breakpoint_count;

    // Simulate runtime operations that MIGHT affect breakpoints (if shared)
    state.cpu.pc = 0x8000; // PC at breakpoint address
    state.busWrite(0x8010, 0xFF); // Write to breakpoint address
    _ = state.busRead(0x8020); // Read from breakpoint address

    // Execute CPU cycles
    for (0..100) |_| {
        state.tickCpu();
    }

    // ✅ Breakpoint count UNCHANGED (runtime doesn't modify breakpoints)
    try testing.expectEqual(bp_count, debugger.state.breakpoint_count);

    // ✅ Breakpoints still at correct addresses
    var found_addresses = [_]u16{ 0, 0, 0 };
    var found_count: usize = 0;
    for (debugger.state.breakpoints[0..256]) |maybe_bp| {
        if (maybe_bp) |bp| {
            found_addresses[found_count] = bp.address;
            found_count += 1;
        }
    }
    try testing.expectEqual(@as(usize, 3), found_count);
    // Check addresses (may be in any order due to fixed array slots)
    const has_8000 = (found_addresses[0] == 0x8000 or found_addresses[1] == 0x8000 or found_addresses[2] == 0x8000);
    const has_8010 = (found_addresses[0] == 0x8010 or found_addresses[1] == 0x8010 or found_addresses[2] == 0x8010);
    const has_8020 = (found_addresses[0] == 0x8020 or found_addresses[1] == 0x8020 or found_addresses[2] == 0x8020);
    try testing.expect(has_8000);
    try testing.expect(has_8010);
    try testing.expect(has_8020);

    // Breakpoint storage is ISOLATED from runtime
}

test "Isolation: Modification history isolation from runtime" {
    var config = Config.init(testing.allocator);
    defer config.deinit();

    var debugger = Debugger.init(testing.allocator, &config);
    defer debugger.deinit();

    var state = test_fixtures.createTestState(&config);

    // Log modifications via debugger
    debugger.setRegisterA(&state, 0x11);
    debugger.setRegisterX(&state, 0x22);
    debugger.setRegisterY(&state, 0x33);

    const mod_count = debugger.getModifications().len;
    try testing.expectEqual(@as(usize, 3), mod_count);

    // Simulate runtime operations (NOT via debugger)
    state.cpu.a = 0x99; // Direct write
    state.cpu.x = 0x88;
    state.cpu.y = 0x77;
    state.cpu.pc = 0x9000;
    state.cpu.sp = 0x00;
    state.busWrite(0x0300, 0xFF);
    state.clock.ppu_cycles += 89342; // Advance one frame

    // ✅ Modification history UNCHANGED (runtime ops don't auto-log)
    try testing.expectEqual(mod_count, debugger.getModifications().len);

    // ✅ Original modifications preserved
    const mods = debugger.getModifications();
    try testing.expectEqual(@as(u8, 0x11), mods[0].register_a);
    try testing.expectEqual(@as(u8, 0x22), mods[1].register_x);
    try testing.expectEqual(@as(u8, 0x33), mods[2].register_y);

    // Modification history is ISOLATED from runtime
}

test "Isolation: readMemory() const parameter enforces isolation" {
    var config = Config.init(testing.allocator);
    defer config.deinit();

    var debugger = Debugger.init(testing.allocator, &config);
    defer debugger.deinit();

    var state = test_fixtures.createTestState(&config);

    // Set known RAM value
    state.busWrite(0x0200, 0x42);

    // Set known open bus value
    state.bus.open_bus = 0x99;
    const orig_bus_value = state.bus.open_bus;
    // Cycle tracking removed: open_bus is now just u8

    // ✅ readMemory accepts CONST state (compile-time isolation guarantee)
    const const_state: *const EmulationState = &state;
    const value = debugger.readMemory(const_state, 0x0200);

    // ✅ Correct value read
    try testing.expectEqual(@as(u8, 0x42), value);

    // ✅ Open bus UNCHANGED (const parameter prevents mutation)
    try testing.expectEqual(orig_bus_value, state.bus.open_bus);

    // COMPILE-TIME ISOLATION: const parameter prevents mutation
    // If readMemory tried to modify state, it would be a compile error
}

test "Isolation: shouldBreak() doesn't mutate state" {
    var config = Config.init(testing.allocator);
    defer config.deinit();

    var debugger = Debugger.init(testing.allocator, &config);
    defer debugger.deinit();

    var state = test_fixtures.createTestState(&config);

    // Add breakpoint at current PC
    try debugger.addBreakpoint(0x8000, .execute);
    state.cpu.pc = 0x8000;

    // Capture state before shouldBreak
    const orig_a = state.cpu.a;
    const orig_pc = state.cpu.pc;
    const orig_sp = state.cpu.sp;
    const orig_bus = state.bus.open_bus;

    // ✅ shouldBreak() checks breakpoints without mutating state
    const should_break = try debugger.shouldBreak(&state);
    try testing.expect(should_break);

    // ✅ State UNCHANGED after breakpoint check
    try testing.expectEqual(orig_a, state.cpu.a);
    try testing.expectEqual(orig_pc, state.cpu.pc);
    try testing.expectEqual(orig_sp, state.cpu.sp);
    try testing.expectEqual(orig_bus, state.bus.open_bus);

    // Hook functions operate on READ-ONLY state
    // Future user-defined hooks will receive *const EmulationState
    // This provides COMPILE-TIME isolation guarantee
}
