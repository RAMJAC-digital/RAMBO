# Test Harness Reference Guide

**Date:** 2025-10-08
**Purpose:** Complete reference for writing integration tests with RAMBO's test harness
**Investigation:** Phase-by-phase debug CLI implementation

---

## Overview

RAMBO provides a comprehensive test harness (`TestHarness.Harness`) for integration testing. This harness:
- Creates a complete emulation environment with test allocator
- Provides direct access to all emulation state
- Supports precise timing control (scanline/dot positioning)
- Enables ROM loading for integration tests
- Follows the same patterns across all test suites

**Key Principle:** **NO SHELL SCRIPTS** - All tests use the harness API

---

## Test Harness API

### Location

```zig
const RAMBO = @import("RAMBO");
const Harness = RAMBO.TestHarness.Harness;
```

**Source:** `src/test/Harness.zig` (140 lines)
**Export:** `src/root.zig:41` - `pub const TestHarness = @import("test/Harness.zig");`

### Initialization Pattern

```zig
test "Example test" {
    // Create harness (allocates Config + EmulationState)
    var harness = try Harness.init();
    defer harness.deinit();

    // Direct state access
    harness.state.cpu.pc = 0x8000;
    harness.state.cpu.a = 0x42;

    // Execute emulation
    harness.state.tick();  // Single CPU cycle

    // Assert state
    try testing.expectEqual(@as(u16, 0x8001), harness.state.cpu.pc);
}
```

---

## Core API Methods

### State Access

```zig
// Direct EmulationState access
harness.state.cpu.*        // CpuState
harness.state.ppu.*        // PpuState
harness.state.apu.*        // ApuState
harness.state.bus.*        // BusState
harness.state.controller.* // ControllerState
harness.state.clock.*      // MasterClock
harness.state.cart         // ?*AnyCartridge

// Bus operations
harness.state.busRead(address: u16) u8
harness.state.busWrite(address: u16, value: u8) void

// Execution
harness.state.tick()                  // Single CPU cycle (3 PPU cycles)
harness.state.tickCpu()               // Single CPU cycle
harness.state.emulateFrame()          // Full frame (29,780 CPU cycles)
```

### PPU Control

```zig
// Set exact PPU timing
harness.setPpuTiming(scanline: u16, dot: u16) void

// Example: Set to VBlank start
harness.setPpuTiming(241, 1);  // Scanline 241, dot 1

// Advance PPU cycles
harness.tickPpu()                     // Single PPU cycle
harness.tickPpuCycles(cycles: usize)  // Multiple PPU cycles

// PPU register access (bypasses bus)
harness.ppuReadRegister(address: u16) u8
harness.ppuWriteRegister(address: u16, value: u8) void

// VRAM access (bypasses bus)
harness.ppuReadVram(address: u16) u8
harness.ppuWriteVram(address: u16, value: u8) void

// Reset PPU and clock
harness.resetPpu() void
```

### Timing Helpers

```zig
// Seek to exact scanline.dot position
// (Executes emulation until target reached)
harness.seekToScanlineDot(target_scanline: u16, target_dot: u16) void

// Example: Seek to NMI trigger point
harness.seekToScanlineDot(241, 1);

// Get current timing
const scanline = harness.getScanline();  // u16
const dot = harness.getDot();            // u16
const frame = harness.state.clock.frame();  // u64
const cpu_cycles = harness.state.clock.cpuCycles();  // u64
```

### Cartridge Loading

```zig
// Load generic cartridge
harness.loadCartridge(cart: AnyCartridge) void

// Load NROM cartridge (convenience wrapper)
harness.loadNromCartridge(cart: NromCart) void

// Set mirroring mode
harness.setMirroring(mode: MirroringType) void
```

---

## Common Test Patterns

### Pattern 1: CPU Instruction Test

```zig
test "CPU: LDA immediate" {
    var harness = try Harness.init();
    defer harness.deinit();

    // Place instruction in RAM
    harness.state.bus.ram[0x8000 & 0x7FF] = 0xA9;  // LDA #
    harness.state.bus.ram[0x8001 & 0x7FF] = 0x42;  // Value

    // Set PC
    harness.state.cpu.pc = 0x8000;

    // Execute instruction (2 CPU cycles)
    for (0..2) |_| {
        harness.state.tick();
    }

    // Verify A register
    try testing.expectEqual(@as(u8, 0x42), harness.state.cpu.a);
}
```

### Pattern 2: PPU Timing Test

```zig
test "PPU: VBlank NMI timing" {
    var harness = try Harness.init();
    defer harness.deinit();

    // Enable NMI
    harness.state.ppu.ctrl.nmi_enable = true;

    // Seek to scanline 240 (before VBlank)
    harness.seekToScanlineDot(240, 340);

    // Verify NMI not triggered yet
    try testing.expect(!harness.state.cpu.nmi_pending);

    // Advance to VBlank start (241, 1)
    harness.tickPpuCycles(2);  // 241.0 → 241.1

    // Verify NMI triggered
    try testing.expect(harness.state.cpu.nmi_pending);
}
```

### Pattern 3: ROM Integration Test

```zig
test "ROM: Execute from cartridge" {
    var harness = try Harness.init();
    defer harness.deinit();

    // Create test ROM
    var prg_rom = [_]u8{0} ** (16 * 1024);  // 16KB
    var chr_rom = [_]u8{0} ** (8 * 1024);   // 8KB

    // Place LDA #$42 at reset vector
    prg_rom[0x0000] = 0xA9;  // LDA #
    prg_rom[0x0001] = 0x42;  // Value

    // Set reset vector to $8000
    prg_rom[0x3FFC] = 0x00;  // Low byte
    prg_rom[0x3FFD] = 0x80;  // High byte

    // Load cartridge
    const cart = NromCart{
        .prg_rom = &prg_rom,
        .chr_rom = &chr_rom,
        .mirroring = .horizontal,
        .has_prg_ram = false,
    };
    harness.loadNromCartridge(cart);

    // Reset CPU (loads PC from reset vector)
    harness.state.reset();

    // Verify PC loaded
    try testing.expectEqual(@as(u16, 0x8000), harness.state.cpu.pc);

    // Execute LDA instruction
    for (0..2) |_| {
        harness.state.tick();
    }

    // Verify A register
    try testing.expectEqual(@as(u8, 0x42), harness.state.cpu.a);
}
```

### Pattern 4: Debugger Integration Test

```zig
test "Debugger: Breakpoint triggers during emulation" {
    var harness = try Harness.init();
    defer harness.deinit();

    // Create debugger
    var debugger = Debugger.init(testing.allocator, harness.config);
    defer debugger.deinit();

    // Set breakpoint
    try debugger.addBreakpoint(0x8100, .execute);

    // Set initial PC
    harness.state.cpu.pc = 0x8000;

    // Execute until breakpoint or max cycles
    const max_cycles = 1000;
    var cycles: usize = 0;

    while (cycles < max_cycles) : (cycles += 1) {
        // Check for breakpoint BEFORE executing instruction
        if (try debugger.shouldBreak(&harness.state)) {
            break;
        }

        // Execute one CPU cycle
        harness.state.tick();
    }

    // Verify breakpoint hit
    try testing.expectEqual(DebugMode.paused, debugger.mode);
    try testing.expectEqual(@as(u16, 0x8100), harness.state.cpu.pc);
}
```

---

## Test File Organization

### Directory Structure

```
tests/
├── debugger/                # Debugger-specific tests
│   └── debugger_test.zig    # 62 tests - breakpoints, watchpoints, callbacks
├── integration/             # Cross-component tests
│   ├── controller_test.zig  # Controller I/O tests with harness
│   ├── vblank_wait_test.zig # PPU timing tests
│   └── cpu_ppu_integration_test.zig  # CPU-PPU coordination
├── cpu/                     # CPU-specific tests
│   └── bus_integration_test.zig  # Bus routing tests
└── ppu/                     # PPU-specific tests
    └── sprite_evaluation_test.zig  # Sprite system tests
```

### Naming Conventions

- **File naming:** `{component}_{feature}_test.zig`
- **Test naming:** `test "{Component}: {specific behavior}"`
- **Helper structs:** `{Feature}TestHarness` (wraps Harness if needed)

**Examples:**
- File: `debugger_breakpoint_test.zig`
- Test: `test "Debugger: execute breakpoint triggers on PC match"`
- Struct: `DebuggerTestHarness` (if needed for complex setup)

---

## Key Testing Principles

### 1. Use Harness for All Integration Tests

**✅ CORRECT:**
```zig
test "PPU: NMI triggers on VBlank" {
    var harness = try Harness.init();
    defer harness.deinit();

    harness.seekToScanlineDot(241, 1);
    try testing.expect(harness.state.cpu.nmi_pending);
}
```

**❌ INCORRECT:**
```zig
// DON'T create shell scripts like this:
// $ zig-out/bin/RAMBO test.nes --break-at 0x8000 --cycles 1000
```

### 2. Direct State Access for Assertions

**✅ CORRECT:**
```zig
// Direct CPU state inspection
try testing.expectEqual(@as(u8, 0x42), harness.state.cpu.a);
try testing.expectEqual(@as(u16, 0x8000), harness.state.cpu.pc);
```

**❌ INCORRECT:**
```zig
// DON'T use debugger for assertions (debugger is the thing being tested)
const a_value = debugger.readMemory(&harness.state, 0x0000);  // Wrong!
```

### 3. Deterministic Timing Control

**✅ CORRECT:**
```zig
// Exact cycle control
harness.seekToScanlineDot(241, 1);  // VBlank start
try testing.expectEqual(@as(u16, 241), harness.getScanline());
```

**❌ INCORRECT:**
```zig
// DON'T use approximate timing
std.Thread.sleep(16_000_000);  // "Wait 16ms" - Non-deterministic!
```

### 4. Test Isolation

**✅ CORRECT:**
```zig
test "Test 1" {
    var harness = try Harness.init();  // Fresh state
    defer harness.deinit();
    // ... test logic
}

test "Test 2" {
    var harness = try Harness.init();  // Fresh state again
    defer harness.deinit();
    // ... test logic
}
```

**❌ INCORRECT:**
```zig
// DON'T share state across tests
var global_harness: Harness = undefined;  // WRONG - not isolated
```

---

## RT-Safety Verification Pattern

From `tests/debugger/debugger_test.zig:949-972`:

```zig
test "RT-Safety: shouldBreak() uses no heap allocation" {
    var config = Config.init(testing.allocator);
    defer config.deinit();

    var debugger = Debugger.init(testing.allocator, &config);
    defer debugger.deinit();

    var state = createTestState(&config);

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
```

**Key Technique:**
- Capture `testing.allocator_instance.total_requested_bytes` before operation
- Execute RT-critical operation
- Compare allocation count after
- Assert zero growth (no heap allocations)

---

## MasterClock Integration

### Understanding the Clock

**Single Counter:** `harness.state.clock.ppu_cycles` (u64)
- Only counter in entire emulator
- All timing derived from this value

**3:1 PPU/CPU Ratio:**
```zig
// PPU advances every cycle
harness.state.clock.advance(1);  // +1 PPU cycle

// CPU ticks every 3 PPU cycles
const is_cpu_tick = harness.state.clock.isCpuTick();  // (ppu_cycles % 3) == 0
```

**Fractional Cycles:**
```zig
// Frame has 89,342 PPU cycles
// 89,342 ÷ 3 = 29,780.67 CPU cycles (fractional!)
const cpu_cycles = harness.state.clock.cpuCycles();  // Integer division
```

**NMI "0.5 cycles" phenomenon:**
- NMI can trigger mid-CPU instruction
- PPU emits VBlank signal at exact dot (241.1)
- CPU may be in middle of 3-PPU-cycle period
- Creates fractional cycle timing relative to CPU

### Testing with MasterClock

```zig
test "MasterClock: Exact scanline.dot positioning" {
    var harness = try Harness.init();
    defer harness.deinit();

    // Set exact PPU position
    harness.setPpuTiming(100, 200);  // Scanline 100, dot 200

    // Verify timing
    try testing.expectEqual(@as(u16, 100), harness.getScanline());
    try testing.expectEqual(@as(u16, 200), harness.getDot());

    // Calculate expected PPU cycles
    const expected_ppu = (@as(u64, 100) * 341) + 200;
    try testing.expectEqual(expected_ppu, harness.state.clock.ppu_cycles);

    // Verify CPU cycles (integer division)
    const expected_cpu = expected_ppu / 3;
    try testing.expectEqual(expected_cpu, harness.state.clock.cpuCycles());
}
```

---

## Example: Complete Integration Test

From `tests/integration/controller_test.zig:17-54`:

```zig
test "Controller: strobe on bit 0 only" {
    // 1. Initialize harness
    var harness = try Harness.init();
    defer harness.deinit();

    // 2. Setup initial state
    harness.state.controller.buttons1 = 0b00000001;  // A button pressed

    // 3. Test behavior
    harness.state.busWrite(0x4016, 0x02);  // Write $02 (bit 0 = 0)
    try testing.expect(harness.state.controller.strobe == false);  // Should NOT strobe

    harness.state.busWrite(0x4016, 0x01);  // Write $01 (bit 0 = 1)
    try testing.expect(harness.state.controller.strobe == true);   // SHOULD strobe

    harness.state.busWrite(0x4016, 0xFF);  // Write $FF (bit 0 = 1)
    try testing.expect(harness.state.controller.strobe == true);   // SHOULD strobe
}
```

---

## Debugger Integration Example

**Pattern for debugger + harness:**

```zig
test "Debugger: Cycle limit works with harness" {
    var harness = try Harness.init();
    defer harness.deinit();

    var debugger = Debugger.init(testing.allocator, harness.config);
    defer debugger.deinit();

    // Setup: Place NOP loop at $8000
    harness.state.bus.ram[0x8000 & 0x7FF] = 0xEA;  // NOP
    harness.state.bus.ram[0x8001 & 0x7FF] = 0x4C;  // JMP abs
    harness.state.bus.ram[0x8002 & 0x7FF] = 0x00;  // Low byte ($8000)
    harness.state.bus.ram[0x8003 & 0x7FF] = 0x80;  // High byte

    harness.state.cpu.pc = 0x8000;

    // Execute for 100 cycles with debugger monitoring
    const max_cycles = 100;
    var cycles: usize = 0;

    while (cycles < max_cycles) : (cycles += 1) {
        // Check breakpoint before each instruction
        if (try debugger.shouldBreak(&harness.state)) {
            break;
        }

        // Execute one CPU cycle
        harness.state.tick();
    }

    // Verify cycle count
    try testing.expectEqual(@as(usize, 100), cycles);

    // Verify stats
    try testing.expectEqual(@as(u64, 100), debugger.stats.instructions_executed);
}
```

---

## Summary

**Test Harness Provides:**
- ✅ Complete emulation environment (CPU, PPU, APU, Bus, Controller)
- ✅ Precise timing control (scanline.dot positioning)
- ✅ ROM loading capabilities
- ✅ Direct state access for assertions
- ✅ Test isolation (fresh state per test)
- ✅ RT-safety verification tools

**DO:**
- ✅ Use `Harness.init()` for all integration tests
- ✅ Access state directly: `harness.state.cpu.*`
- ✅ Control timing precisely: `seekToScanlineDot()`
- ✅ Verify allocations: `testing.allocator_instance.total_requested_bytes`

**DON'T:**
- ❌ Create shell scripts to test emulator
- ❌ Use `std.Thread.sleep()` for timing
- ❌ Share harness across tests
- ❌ Access debugger methods for state inspection (debugger is being tested!)

---

**Status:** ✅ **COMPLETE** - Ready for test implementation
**Next:** Apply this knowledge to create 36 debugger integration tests
