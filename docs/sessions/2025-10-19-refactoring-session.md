# 2025-10-19 Refactoring Session - Surface Bugs Through Code Clarity

## Session Goals

**Primary**: Make bugs visible through code simplification, not complex diagnostics
**Secondary**: Eliminate cognitive overhead in CPU/PPU interaction
**Tertiary**: Ensure no regressions (maintain 1040/1061 test pass rate)

---

## Baseline Status

**Test Results** (before refactoring):
- ✅ 1040/1061 tests passing (98.0%)
- ❌ 16 tests failing
- ⏭️ 5 tests skipped

**Failing Test Categories**:
1. AccuracyCoin accuracy tests (10 tests) - All return `0x80` (RUNNING, never complete)
2. MMC3 visual regression (2 tests) - Rendering issues
3. AccuracyCoin execution (1 test) - Rendering not enabled
4. Commercial ROM tests (3 tests) - Various issues

**Clean-up Completed**:
- ✅ Removed 8 throwaway `diagnose_*.zig` scripts from root
- ✅ Removed `tests/diagnose_jsr_stack.zig`
- ✅ Removed `root` binary artifact

---

## Investigation Findings

### 1. Early Returns Audit ✅

**PPU Register Writes** (`src/ppu/logic/registers.zig`):
```zig
pub fn writeRegister(state: *PpuState, ...) void {
    // Line 184: Open bus ALWAYS updated FIRST
    state.open_bus.write(value);

    switch (reg) {
        0x0000 => { // PPUCTRL
            if (!state.warmup_complete) return; // ← Early return
            // ... register update ...
        }
        0x0005 => { // PPUSCROLL
            if (!state.warmup_complete) return; // ← Early return
            // ... register update ...
        }
        0x0006 => { // PPUADDR
            if (!state.warmup_complete) return; // ← Early return
            // ... register update ...
        }
    }
}
```

**Analysis**:
- ✅ Open bus update happens BEFORE switch (line 184) - **CORRECT**
- ✅ Early returns only skip register-specific side effects - **CORRECT**
- ✅ Warmup behavior is intentional (PPU ignores writes during first 29,658 CPU cycles)
- ✅ AccuracyCoin tests set `warmup_complete = true` before execution

**Conclusion**: These early returns are **NOT the problem**. They're correct hardware behavior.

### 2. State Mutation Isolation ✅

**CPU Execution** (`src/emulation/cpu/execution.zig`, `microsteps.zig`):
- ✅ No early returns found that skip side effects
- ✅ All mutations flow through `state.*` parameter
- ✅ Bus operations are isolated to `busRead()`/`busWrite()`

**Conclusion**: State mutation is already properly isolated.

### 3. RMW Implementation Review ✅

**Dummy Write Flow** (`execution.zig:436-445`, `microsteps.zig:287-297`):
```zig
// Addressing cycles for absolute RMW:
0 => fetchAbsLow,      // Fetch address low byte
1 => fetchAbsHigh,     // Fetch address high byte
2 => rmwRead,          // Read value to temp_value
3 => rmwDummyWrite,    // Write temp_value back (DUMMY!)
// Then execute state writes modified value

// Execute stage uses cached value (execution.zig:671):
const operand = if (entry.is_rmw) state.cpu.temp_value
```

**Verification**:
- ✅ RMW instructions marked correctly in dispatch table
- ✅ Dummy write implemented (`microsteps.zig:295`)
- ✅ Execute stage uses cached `temp_value`, no re-read
- ⚠️ Debug logging present but produces NO output during tests

**Question**: Why no debug output if RMW is working?

**Hypothesis**: RMW instructions never execute because tests fail earlier (in PPU open bus verification).

---

## Refactoring Strategy

### Phase 1: Add Visibility Without Changing Behavior

**Goal**: Make execution flow visible to identify where tests fail

**Approach**: Strategic logging at decision points (NOT diagnostic tools)

#### 1.1: Add Execution Milestone Logging

**File**: `tests/integration/accuracy/dummy_write_cycles_test.zig`

**Changes**:
```zig
test "Accuracy: DUMMY WRITE CYCLES" {
    // ... existing setup ...

    // Track ErrorCode changes
    var last_error_code: u8 = 0xFF;

    while (cycles < max_cycles) : (cycles += 1) {
        h.state.tick();

        const error_code = h.state.bus.ram[0x10];
        if (error_code != last_error_code) {
            std.debug.print("Cycle {d}: ErrorCode changed 0x{X:0>2} → 0x{X:0>2}, PC=0x{X:0>4}\n",
                .{cycles, last_error_code, error_code, h.state.cpu.pc});
            last_error_code = error_code;
        }

        const result = h.state.bus.ram[0x0407];
        if (result != 0x80) {
            std.debug.print("Cycle {d}: Test complete, result=0x{X:0>2}\n", .{cycles, result});
            break;
        }
    }

    // Show final state on failure
    if (result != 0x00) {
        std.debug.print("\n=== FAILURE DIAGNOSIS ===\n", .{});
        std.debug.print("Result: 0x{X:0>2} (expected 0x00)\n", .{result});
        std.debug.print("ErrorCode: 0x{X:0>2}\n", .{h.state.bus.ram[0x10]});
        std.debug.print("PC: 0x{X:0>4}\n", .{h.state.cpu.pc});
        std.debug.print("Opcode: 0x{X:0>2}\n", .{h.state.cpu.opcode});
        std.debug.print("A: 0x{X:0>2}\n", .{h.state.cpu.a});
    }

    try testing.expectEqual(@as(u8, 0x00), result);
}
```

**Expected Output**:
```
Cycle 1234: ErrorCode changed 0xFF → 0x00, PC=0xA318
Cycle 5678: ErrorCode changed 0x00 → 0x01, PC=0xA35D
Cycle 9012: ErrorCode changed 0x01 → 0x02, PC=0xA35D
Cycle 12000: Test complete, result=0x80

=== FAILURE DIAGNOSIS ===
Result: 0x80 (expected 0x00)
ErrorCode: 0x02
PC: 0x0602
Opcode: 0x00
A: 0x0A
```

This will tell us EXACTLY where the test stops progressing.

#### 1.2: Add PPU Open Bus Validation

**File**: `tests/integration/accuracy/dummy_write_cycles_test.zig` (new section)

**Add before main test loop**:
```zig
// === Pre-Test: Verify PPU Open Bus ===
std.debug.print("\n=== PPU Open Bus Pre-Check ===\n", .{});

// Write known value to $2000 to set open bus
h.state.busWrite(0x2000, 0x42);
const read_2000 = h.state.busRead(0x2000);
std.debug.print("Write $2000=$42, Read $2000=${X:0>2} (expect $42)\n", .{read_2000});

// Write different value to $2006
h.state.busWrite(0x2006, 0x2D);
const read_2006 = h.state.busRead(0x2006);
std.debug.print("Write $2006=$2D, Read $2006=${X:0>2} (expect $2D)\n", .{read_2006});

if (read_2000 != 0x42 or read_2006 != 0x2D) {
    std.debug.print("❌ PPU open bus FAILED pre-check!\n", .{});
} else {
    std.debug.print("✅ PPU open bus working correctly\n", .{});
}
std.debug.print("=== End Pre-Check ===\n\n", .{});
```

This will immediately tell us if open bus is broken.

#### 1.3: Enable RMW Debug Logging

**File**: `src/emulation/cpu/microsteps.zig`

**Modify** (already present, just ensure it's active):
```zig
pub fn rmwDummyWrite(state: anytype) bool {
    // KEEP existing debug print (lines 289-294)
    if (state.cpu.effective_address >= 0x2000 and state.cpu.effective_address <= 0x3FFF) {
        @import("std").debug.print(
            "rmwDummyWrite addr=0x{X:0>4} value=0x{X:0>2} opcode=0x{X:0>2} cycle={d}\n",
            .{ state.cpu.effective_address, state.cpu.temp_value, state.cpu.opcode, state.clock.ppu_cycles },
        );
    }
    state.busWrite(state.cpu.effective_address, state.cpu.temp_value);
    return false;
}
```

This is ALREADY in the code but produces no output, confirming RMW never executes.

### Phase 2: Fix Based on Evidence

**DO NOT PROCEED** until Phase 1 logging reveals the actual bug location.

**Potential Scenarios** (based on logging output):

#### Scenario A: PPU Open Bus Returns Wrong Value
**Evidence**: Pre-check fails, read doesn't match write
**Fix**: Investigate `state.open_bus.read()` / `write()` implementation

#### Scenario B: Test Fails at ErrorCode=0x01
**Evidence**: ErrorCode stuck at 0x01, never increments to 0x02
**Fix**: ROM's PPU_Open_Bus test is failing, need to trace that specific subtest

#### Scenario C: RMW Never Executes
**Evidence**: No rmwDummyWrite logging even after ErrorCode=0x02
**Fix**: ROM execution path analysis - why doesn't it reach RMW code?

---

## Implementation Plan

### Step 1: Add Phase 1 Logging ✅

**Tasks**:
- [ ] Modify `dummy_write_cycles_test.zig` with ErrorCode tracking
- [ ] Add PPU open bus pre-check
- [ ] Verify RMW debug logging is active (already present)

**Verification**: Run test, observe output

### Step 2: Analyze Logging Output

**Run**: `zig test --dep RAMBO -Mroot=tests/integration/accuracy/dummy_write_cycles_test.zig -MRAMBO=src/root.zig`

**Capture**: Full output to identify failure point

### Step 3: Fix Based on Evidence

**DO NOT guess** - wait for logging to show the bug

---

## Success Criteria

### Immediate Goals
- [ ] Identify EXACT cycle where AccuracyCoin test stops progressing
- [ ] Confirm whether PPU open bus is working correctly
- [ ] Determine if RMW code is ever reached

### Ultimate Goals
- [ ] All 3 accuracy tests pass (result=0x00)
- [ ] No regressions (maintain 1040+/1061 passing)
- [ ] Code clarity improved (bugs obvious from structure)

---

## Anti-Patterns to Avoid

❌ **Don't**: Build complex diagnostic harnesses
✅ **Do**: Add targeted logging at decision points

❌ **Don't**: Refactor before understanding the bug
✅ **Do**: Make the bug visible first, then fix

❌ **Don't**: Change multiple files simultaneously
✅ **Do**: One file, one change, verify immediately

❌ **Don't**: Trust hypotheses without evidence
✅ **Do**: Prove with logging before changing code

---

## Next Actions

1. ✅ Clean up dead code (COMPLETE)
2. ✅ Run baseline tests (COMPLETE - 1040/1061)
3. ⏳ Add Phase 1 logging to `dummy_write_cycles_test.zig`
4. ⏳ Run test and capture output
5. ⏳ Analyze output to identify bug
6. ⏳ Fix based on evidence
7. ⏳ Verify all tests pass

---

## Notes

- User directive: "Refactoring first to surface problems easier"
- User concern: "Going in circles" - avoid over-planning, focus on evidence
- Logging is temporary - remove after bugs fixed
- Each fix must be verified with full test suite run

---

**Session Date**: 2025-10-19
**Status**: Phase 1 logging implementation in progress
**Baseline**: 1040/1061 tests passing
