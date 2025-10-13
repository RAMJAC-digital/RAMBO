# JMP Indirect Page Boundary Bug - Test Infrastructure Plan

**Status:** 📋 Planning
**Priority:** P3 (Optional Improvement)
**Estimated Effort:** 2-3 hours

## Problem Statement

The JMP indirect page boundary bug is correctly implemented in `src/emulation/cpu/microsteps.zig:357-369`, but cannot be properly tested with current RAM-based test infrastructure.

### Implementation (Verified Correct)

```zig
/// Fetch high byte of JMP indirect target (with page boundary bug)
pub fn jmpIndirectFetchHigh(state: anytype) bool {
    // 6502 bug: If pointer is at page boundary, wraps within page
    const ptr = state.cpu.effective_address;
    const high_addr = if ((ptr & 0xFF) == 0xFF)
        ptr & 0xFF00 // Wrap to start of same page
    else
        ptr + 1;

    state.cpu.operand_high = state.busRead(high_addr);
    state.cpu.effective_address = (@as(u16, state.cpu.operand_high) << 8) |
                                   @as(u16, state.cpu.operand_low);
    return false;
}
```

### Test Infrastructure Challenge

**Issue:** Test harness calls `reset()` which loads PC from ROM reset vector ($FFFC-$FFFD).
- Without cartridge loaded: Reset vector contains garbage
- RAM at $0000 not executable from CPU's perspective after reset
- Direct PC manipulation requires careful CPU state management

**Attempted Solution (Failed):**
```zig
// Place JMP in RAM
h.harness.state.bus.ram[0] = 0x6C;
h.harness.state.cpu.pc = 0x0000;
h.harness.state.cpu.state = .fetch_opcode;

// Result: PC ends up at 0xFF6C (reading from wrong memory)
```

**Root Cause:** CPU opcode fetch goes through `busRead()` which routes to cartridge ROM space, not RAM, for addresses $0000 in the context of instruction fetching.

## Solution Options

### Option 1: ROM-Based Test Harness (Recommended)

Create minimal test ROM with JMP indirect tests in ROM space.

**Pros:**
- Tests run in authentic NES environment
- ROM space naturally executable
- Can test full instruction pipeline
- Validates bus routing correctness

**Cons:**
- Requires ROM compilation tooling
- More complex test setup
- Harder to debug failures

**Implementation:**
1. Create `tests/roms/jmp_indirect_test.s` (6502 assembly)
2. Assemble to `.nes` ROM file
3. Load ROM in test harness
4. Execute and verify PC destination

### Option 2: Cartridge Mock with Execute-in-Place

Create mock cartridge that allows RAM-based code execution.

**Pros:**
- Simpler than full ROM compilation
- Keeps tests in Zig codebase
- Fast iteration cycle

**Cons:**
- Not authentic hardware environment
- Complex mock cartridge implementation
- May miss bus routing bugs

**Implementation:**
```zig
const TestCart = struct {
    ram: [256]u8,

    pub fn cpuRead(self: *TestCart, address: u16) u8 {
        // Map $8000-$80FF to RAM
        if (address >= 0x8000 and address < 0x8100) {
            return self.ram[address & 0xFF];
        }
        return 0xFF; // Open bus
    }
};
```

### Option 3: Direct Microstep Unit Test

Test the `jmpIndirectFetchHigh` function directly in isolation.

**Pros:**
- Simplest implementation
- Fast execution
- Direct validation of bug logic

**Cons:**
- White-box test (tests implementation, not behavior)
- Doesn't validate integration with CPU pipeline
- Already verified by code review

**Implementation:**
```zig
test "jmpIndirectFetchHigh: page boundary wraps within page" {
    var state = EmulationState.init(&config);

    // Setup: Pointer at $02FF
    state.cpu.effective_address = 0x02FF;
    state.busWrite(0x02FF, 0x34); // Low byte
    state.busWrite(0x0200, 0x12); // High byte (wrapped)
    state.busWrite(0x0300, 0x56); // High byte (correct, not read)

    _ = jmpIndirectFetchHigh(&state);

    // Verify effective_address = $1234 (not $5634)
    try testing.expectEqual(@as(u16, 0x1234), state.cpu.effective_address);
}
```

## Recommended Approach: Hybrid Strategy

**Phase 1: Immediate (30 min)**
- Implement Option 3 (microstep unit test)
- Documents behavior, provides regression detection
- Low risk, high value for current state

**Phase 2: Future (2-3 hours)**
- Implement Option 1 (ROM-based test)
- When ROM tooling infrastructure is ready
- Provides authentic hardware validation

**Phase 3: Enhancement (1 hour)**
- Add test for non-boundary case ($0280 → reads from $0281)
- Add test for all page boundary positions ($xxFF)
- Cross-reference with nestest or other ROM test suites

## Implementation Plan (Phase 1)

### Step 1: Create Microstep Unit Test (15 min)

**File:** `tests/cpu/microsteps/jmp_indirect_test.zig`

```zig
//! JMP Indirect Page Boundary Bug Unit Tests
//!
//! Tests the hardware bug in jmpIndirectFetchHigh where pointers
//! at page boundaries ($xxFF) wrap within the same page instead of
//! reading from the next page.
//!
//! Reference: https://www.nesdev.org/wiki/Errata
//! Implementation: src/emulation/cpu/microsteps.zig:357-369

const std = @import("std");
const testing = std.testing;
const RAMBO = @import("RAMBO");
const EmulationState = RAMBO.EmulationState.EmulationState;
const Config = RAMBO.Config;
const microsteps = @import("../../../src/emulation/cpu/microsteps.zig");

test "jmpIndirectFetchHigh: page boundary bug ($xxFF wraps to $xx00)" {
    var config = Config.Config.init(testing.allocator);
    defer config.deinit();

    var state = EmulationState.init(&config);
    state.reset();

    // JMP ($02FF) should read:
    // - Low byte from $02FF
    // - High byte from $0200 (BUG: should be $0300)

    state.cpu.effective_address = 0x02FF; // Pointer address
    state.busWrite(0x02FF, 0x34); // Low byte of target
    state.busWrite(0x0200, 0x12); // High byte (wrapped - BUG)
    state.busWrite(0x0300, 0x56); // High byte (correct - not read)

    state.cpu.operand_low = state.busRead(0x02FF); // Simulate fetch

    _ = microsteps.jmpIndirectFetchHigh(&state);

    // Verify bug: reads from $0200, not $0300
    // Result: effective_address = $1234, not $5634
    try testing.expectEqual(@as(u16, 0x1234), state.cpu.effective_address);
}

test "jmpIndirectFetchHigh: no bug when not at page boundary" {
    var config = Config.Config.init(testing.allocator);
    defer config.deinit();

    var state = EmulationState.init(&config);
    state.reset();

    // JMP ($0280) should read:
    // - Low byte from $0280
    // - High byte from $0281 (correct)

    state.cpu.effective_address = 0x0280;
    state.busWrite(0x0280, 0x34); // Low byte
    state.busWrite(0x0281, 0x56); // High byte (correct)

    state.cpu.operand_low = state.busRead(0x0280);

    _ = microsteps.jmpIndirectFetchHigh(&state);

    // Verify correct behavior: reads from $0281
    // Result: effective_address = $5634
    try testing.expectEqual(@as(u16, 0x5634), state.cpu.effective_address);
}

test "jmpIndirectFetchHigh: all page boundary positions" {
    var config = Config.Config.init(testing.allocator);
    defer config.deinit();

    // Test all 256 page boundaries ($00FF, $01FF, ..., $FFFF)
    for (0..256) |page| {
        var state = EmulationState.init(&config);
        state.reset();

        const page_u8 = @as(u8, @intCast(page));
        const boundary_addr = (@as(u16, page_u8) << 8) | 0xFF;
        const wrapped_addr = @as(u16, page_u8) << 8; // $xx00

        state.cpu.effective_address = boundary_addr;
        state.busWrite(boundary_addr, 0x34); // Low byte
        state.busWrite(wrapped_addr, 0x12);  // High byte (wrapped)

        state.cpu.operand_low = 0x34;

        _ = microsteps.jmpIndirectFetchHigh(&state);

        // All boundaries should wrap to $1234
        try testing.expectEqual(@as(u16, 0x1234), state.cpu.effective_address);
    }
}
```

### Step 2: Update page_crossing_test.zig (5 min)

Replace the placeholder comment with reference to new unit test:

```zig
// ============================================================================
// JMP Indirect Page Boundary Bug
// ============================================================================
//
// NOTE: JMP indirect page boundary bug is correctly implemented in
// src/emulation/cpu/microsteps.zig:357-369 (jmpIndirectFetchHigh).
//
// Direct microstep unit test: tests/cpu/microsteps/jmp_indirect_test.zig
// Full integration test deferred to ROM-based test infrastructure.
//
// Hardware behavior:
//   - If pointer at $xxFF, reads high byte from $xx00 (wraps within page)
//   - If pointer not at page boundary, reads normally from next byte
//
// Reference: https://www.nesdev.org/wiki/Errata
```

### Step 3: Register Test in build.zig (10 min)

Add to CPU microstep tests section:

```zig
// JMP indirect microstep tests
const jmp_indirect_microstep_tests = b.addTest(.{
    .root_module = b.createModule(.{
        .root_source_file = b.path("tests/cpu/microsteps/jmp_indirect_test.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "RAMBO", .module = mod },
        },
    }),
});
jmp_indirect_microstep_tests.root_module.addImport("xev", xev_dep.module("xev"));

const run_jmp_indirect_microstep_tests = b.addRunArtifact(jmp_indirect_microstep_tests);

// Add to test steps
test_step.dependOn(&run_jmp_indirect_microstep_tests.step);
unit_test_step.dependOn(&run_jmp_indirect_microstep_tests.step);
```

## Success Criteria

### Phase 1 (Microstep Unit Test)
- ✅ 3 unit tests passing
- ✅ Tests verify bug at page boundary ($xxFF → $xx00)
- ✅ Tests verify correct behavior not at boundary
- ✅ Tests cover all 256 page boundaries
- ✅ Code comments reference implementation and test location

### Phase 2 (ROM-Based Integration Test - Future)
- ✅ ROM compiles and loads in harness
- ✅ JMP ($xxFF) executes and jumps to correct buggy address
- ✅ JMP ($xx00-$xxFE) executes correctly
- ✅ Test validates full CPU pipeline (fetch, decode, execute)
- ✅ Test runs in under 100ms

## References

- **Implementation:** `src/emulation/cpu/microsteps.zig:357-369`
- **nesdev Errata:** https://www.nesdev.org/wiki/Errata
- **6502 Bug:** "An indirect JMP (xxFF) will fail because the MSB will be fetched from address xx00 instead of page xx+1"
- **Existing Tests:** `tests/cpu/page_crossing_test.zig` (integration test attempts)
- **Test Harness:** `src/test/Harness.zig`

## Timeline

- **Phase 1 (Immediate):** 30 minutes - Microstep unit tests
- **Phase 2 (Future):** 2-3 hours - ROM-based integration tests (requires ROM tooling)
- **Phase 3 (Enhancement):** 1 hour - Cross-reference with nestest

**Total Immediate Work:** 30 minutes
**Total Future Work:** 3-4 hours
