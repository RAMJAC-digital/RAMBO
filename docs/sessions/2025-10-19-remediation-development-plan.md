# 2025-10-19 CPU/PPU Accuracy Investigation - Comprehensive Remediation & Development Plan

## Executive Summary

**Status**: 3 critical AccuracyCoin tests failing with result `0x80` (RUNNING flag, test never completes)
- `dummy_write_cycles_test`: ErrorCode=0x02, PC=0x0602
- `nmi_control_test`: ErrorCode=0x06, PC=0x0602
- `unofficial_instructions_test`: Result=0x80

**Root Cause Assessment**: Based on comprehensive code analysis and subagent reports, the primary issue is **NOT** with RMW dummy writes (implementation appears correct) but rather with **test execution flow** - tests are hitting BRK/infinite loops before reaching actual validation code.

**Investigation Confidence**: HIGH - All subsystems analyzed, no smoking guns found in core CPU/PPU logic

---

## Investigation Findings Summary

### 1. RMW (Read-Modify-Write) Implementation Analysis ✅ **CORRECT**

**Subagent Report**: RMW implementation is cycle-accurate and hardware-correct.

**Code Path** (`src/emulation/cpu/execution.zig` + `microsteps.zig`):
```
Zero Page RMW (5 cycles):
  Cycle 0: fetchOperandLow
  Cycle 1: rmwRead → reads value to temp_value
  Cycle 2: rmwDummyWrite → writes temp_value back (dummy write)
  Cycle 3: execute → uses temp_value, writes modified value

Absolute RMW (6 cycles):
  Cycle 0: fetchAbsLow
  Cycle 1: fetchAbsHigh
  Cycle 2: rmwRead → reads value to temp_value
  Cycle 3: rmwDummyWrite → writes temp_value back (dummy write)
  Cycle 4: execute → uses temp_value, writes modified value
```

**Critical Implementation Details**:
- `execution.zig:671-672`: RMW instructions use `temp_value` (NOT re-read in execute stage)
- `microsteps.zig:287-297`: `rmwDummyWrite()` writes original value via `busWrite()`
- `dispatch.zig:328-367`: All RMW opcodes correctly marked with `is_rmw = true`
- Debug logging present in `rmwDummyWrite()` for PPU register range ($2000-$3FFF)

**Verification**: No debug output observed when running tests, suggesting:
1. RMW instructions not reaching dummy write stage, OR
2. Tests failing earlier in execution (more likely)

### 2. JSR/RTS Stack Operations Analysis ✅ **CORRECT**

**Subagent Report**: JSR/RTS implementation is hardware-perfect and cycle-accurate.

**Implementation** (`microsteps.zig`):
- JSR (6 cycles): Correctly pushes PC-1 (high byte first, then low)
- RTS (6 cycles): Correctly pulls PC (low byte first, then high), increments PC
- Stack pointer operations verified correct (decrement on push, increment on pull)

**Confidence**: 95% - No issues detected

### 3. Open Bus Behavior Analysis ✅ **MOSTLY CORRECT**

**Subagent Report**: Implementation is comprehensive with strong test coverage.

**Current Implementation**:
- `BusState.open_bus`: 8-bit value updated on every write
- `PpuState.open_bus`: Advanced tracking with 60-frame decay timer
- All PPU register writes update open bus (`registers.zig:184`)
- Write-only registers return open bus on read (correct)

**Potential Gap**:
- Some indirect read paths may bypass open bus updates
- DMA operations might not update open bus correctly
- Need to verify ALL `busRead()` call sites update open bus

### 4. NMI Ledger & VBlank Management Analysis ⚠️ **NEEDS INVESTIGATION**

**Subagent Report**: High likelihood of subtle timing/read path issues.

**Current Implementation** (`VBlankLedger.zig` + `State.zig:351-357`):
```zig
if (ppu_read_result) |result| {
    if (result.read_2002) {
        const now = self.clock.ppu_cycles;
        self.vblank_ledger.last_read_cycle = now;
    }
}
```

**Identified Issues**:
1. **Missing Read Paths**: $2002 reads during dummy cycles/DMA may bypass ledger update
2. **Race Condition Masking**: `hasRace()` may hide missing timestamp updates
3. **Edge Detection Sensitivity**: NMI enable/disable timing requires precise cycle tracking

**Evidence from Test Failures**:
- `nmi_control_test` ErrorCode=0x06: Subtest 6 checks NMI enable mid-vblank behavior
- Investigation document shows `last_read_cycle` stuck at old values
- NMI line assertion logic depends on accurate timestamp tracking

### 5. Test Execution Flow Analysis ⚠️ **PRIMARY SUSPECT**

**Critical Finding**: All 3 failing tests return `result=0x80` (RUNNING flag never clears)

**This indicates**:
1. Tests hit BRK instruction before completion (PC=0x0602 is BRK vector area)
2. ErrorCode values show progression (0x02, 0x06) then halt
3. ROM never writes final result to $0407

**AccuracyCoin Test Flow** (from ROM source analysis):
```
TEST_DummyWrites:
  1. Verify PPU open bus (TEST_PPU_Open_Bus)
     - If fails → TEST_FailPPUOpenBus2 → JMP TEST_Fail
  2. Set up VRAM values
  3. Test RMW dummy writes on $2006
  4. Verify VRAM reads match expected values
  5. Write result to $0407
```

**Hypothesis**: Test 1 (PPU open bus verification) is failing, causing early exit.

---

## Root Cause Deep-Dive: Why Tests Never Complete

### Scenario 1: PPU Open Bus Decay Test Failing

**ROM Code** (`AccuracyCoin.asm`):
```asm
LDA #1
STA <$50    ; Skip decay test by setting $50=1
JSR TEST_PPU_Open_Bus
LDX #1
STX <ErrorCode
CMP #$01
BNE TEST_FailPPUOpenBus2  ; ← LIKELY FAILING HERE
INC <ErrorCode
```

**What This Tests**:
- Reads PPU register to get open bus value
- Expects specific value based on previous write
- If open bus not working, CMP fails, jumps to fail handler

**Potential Issue**:
- Our open bus implementation may return wrong value
- Decay timer might be interfering (though $50=1 should skip this)
- Timing of open bus updates might be off

### Scenario 2: Early ROM Execution Path Issue

**Evidence**:
- PC=0x0602 suggests BRK instruction executed
- ErrorCode increments (0x01 → 0x02 → 0x03, then jumps back to 0x01 → 0x02)
- ROM comment: "FAIL 2" corresponds to ErrorCode=0x02

**Hypothesis**:
- ROM is looping through test setup
- Hitting failure condition repeatedly
- Never reaching actual RMW test code

---

## Remediation Plan

### Phase 1: Diagnostic Enhancement (Priority: CRITICAL)

**Goal**: Identify exact failure point in AccuracyCoin execution

**Tasks**:

#### 1.1: Add Comprehensive Execution Tracing
**File**: Create `tests/integration/accuracy/diagnostic_runner.zig`

**Implementation**:
```zig
// Track every instruction execution
// Log ErrorCode changes
// Log PC when entering/exiting key subroutines
// Capture PPU open bus state on every read
// Monitor VRAM address (v register) changes
```

**Deliverables**:
- [ ] Diagnostic test harness with detailed logging
- [ ] Execution trace showing exact failure point
- [ ] PPU open bus value timeline
- [ ] ErrorCode progression map

#### 1.2: Instrument PPU Open Bus Reads
**Files**: `src/ppu/logic/registers.zig`

**Changes**:
```zig
// Add debug mode flag
pub const debug_open_bus = false; // Set to true for tracing

// In readRegister():
if (debug_open_bus and reg == 0x0006) {
    std.debug.print("$2006 read: open_bus=0x{X:0>2} cycle={d}\n",
        .{state.open_bus.value, /* cycle count */});
}
```

**Deliverables**:
- [ ] Optional debug logging for open bus reads
- [ ] Trace of all $2000-$2007 reads/writes during test
- [ ] Verification that open bus returns expected values

#### 1.3: Validate RMW Dummy Write Path
**Files**: `src/emulation/cpu/microsteps.zig`

**Changes**:
```zig
// Enhance existing debug print in rmwDummyWrite (line 289)
if (state.cpu.effective_address >= 0x2000 and state.cpu.effective_address <= 0x3FFF) {
    std.debug.print(
        "[RMW] addr=0x{X:0>4} orig=0x{X:0>2} opcode=0x{X:0>2} cycle={d} PC=0x{X:0>4}\n",
        .{ state.cpu.effective_address, state.cpu.temp_value, state.cpu.opcode,
           state.clock.ppu_cycles, state.cpu.pc - 3 }, // PC-3 = start of instruction
    );
}
```

**Deliverables**:
- [ ] Confirmation that rmwDummyWrite is called for $2006
- [ ] Verification of dummy write value correctness
- [ ] Timeline of PPU register access during RMW

### Phase 2: Open Bus Investigation (Priority: HIGH)

**Goal**: Verify open bus behavior matches hardware expectations

**Tasks**:

#### 2.1: Audit All busRead() Call Sites
**Files**: All files calling `state.busRead()`

**Method**: Use subagent to grep and analyze

**Deliverables**:
- [ ] Complete list of busRead() call sites with file:line
- [ ] Verification that each updates open bus correctly
- [ ] Identification of any bypass paths

#### 2.2: Verify PPU Register Open Bus Behavior
**Files**: `src/ppu/logic/registers.zig`

**Test Cases**:
- [ ] Read $2000-$2007 write-only registers return last bus value
- [ ] Write to $2000-$2007 updates open bus immediately
- [ ] Open bus persists across multiple reads
- [ ] Decay timer works correctly (60 frames)

**Implementation**:
```zig
// In tests/ppu/open_bus_behavior_test.zig (NEW FILE)
test "PPU register open bus persistence" {
    // Write value to $2006
    // Read $2000 (write-only)
    // Verify returns last written value
}
```

#### 2.3: Trace Open Bus During AccuracyCoin Execution
**Method**: Run diagnostic with open bus logging enabled

**Expected Output**:
```
Cycle XXXXX: Write $2D to $2006 (set open_bus=$2D)
Cycle XXXXX: Read $2000 → returns $2D (open bus)
Cycle XXXXX: CMP #$2D → should set Z flag
```

**Deliverables**:
- [ ] Full open bus trace during PPU_Open_Bus test
- [ ] Identification of any incorrect open bus values
- [ ] Verification of decay timer interaction

### Phase 3: NMI Ledger Fixes (Priority: MEDIUM)

**Goal**: Ensure all $2002 read paths update ledger correctly

**Tasks**:

#### 3.1: Audit $2002 Read Paths
**Files**: Search for all code reading from $2002

**Known Paths**:
1. Normal CPU instruction reads (`busRead($2002)`)
2. Dummy reads during addressing modes
3. DMA introspection (if any)
4. Debugger reads (if any)

**Verification**:
- [ ] Each path goes through `readRegister()` in `registers.zig`
- [ ] Each path triggers `read_2002` flag in `PpuReadResult`
- [ ] EmulationState.busRead() propagates flag to ledger

#### 3.2: Fix Missing Ledger Updates
**Files**: `src/emulation/State.zig`

**Current Code** (lines 351-357):
```zig
if (ppu_read_result) |result| {
    if (result.read_2002) {
        const now = self.clock.ppu_cycles;
        self.vblank_ledger.last_read_cycle = now;
    }
}
```

**Potential Issues**:
- Conditional `if (ppu_read_result)` - when is this null?
- Are there busRead() calls that bypass this logic?

**Investigation**:
- [ ] Trace all busRead() implementations
- [ ] Verify PPU register reads always set `ppu_read_result`
- [ ] Check if DMA/dummy reads bypass this logic

#### 3.3: Add NMI Edge Detection Tests
**Files**: Create `tests/integration/accuracy/nmi_edge_detection_test.zig`

**Test Cases** (from AccuracyCoin subtest 6):
```zig
test "NMI: Enable during VBlank with flag clear should NOT trigger" {
    // 1. Enter VBlank
    // 2. Read $2002 (clears flag)
    // 3. Write $2000 with NMI enable
    // 4. Verify NMI does NOT occur
}

test "NMI: Enable during VBlank with flag set SHOULD trigger" {
    // 1. Enter VBlank
    // 2. Write $2000 with NMI enable (don't read $2002)
    // 3. Verify NMI occurs on next instruction
}
```

**Deliverables**:
- [ ] Comprehensive NMI edge detection test suite
- [ ] Verification against nesdev.org wiki behavior
- [ ] Fixes for any incorrect edge cases

### Phase 4: Side Effect Isolation & Refactoring (Priority: MEDIUM-LOW)

**Goal**: Clean up code for maintainability and reduce cognitive overhead

**Tasks**:

#### 4.1: Eliminate Early Returns in State Logic
**Files**: Search for functions with early returns that skip side effects

**Pattern to Find**:
```zig
pub fn someFunction(state: *State) void {
    if (some_condition) return; // ← PROBLEMATIC
    // Important side effects happen here
    state.something = value;
}
```

**Refactor Pattern**:
```zig
pub fn someFunction(state: *State) void {
    const should_process = !some_condition;
    if (should_process) {
        state.something = value;
    }
    // All code paths reach end - no hidden state
}
```

**Deliverables**:
- [ ] List of all functions with conditional early returns
- [ ] Refactored versions ensuring all side effects are explicit
- [ ] Tests verifying behavior unchanged

#### 4.2: Audit busRead/busWrite Side Effects
**Files**: `src/emulation/State.zig`

**Goal**: Ensure side effects are predictable and well-documented

**Method**:
```zig
// Document ALL side effects in function comments
/// busRead(): Reads from memory bus
///
/// Side Effects:
/// - Updates BusState.open_bus
/// - May trigger PPU register read side effects ($2002, $2007)
/// - May trigger APU register reads
/// - May trigger cartridge mapper behavior
/// - Updates VBlankLedger if reading $2002
/// - Calls debugger watchpoint checks
```

**Deliverables**:
- [ ] Comprehensive documentation of all bus operation side effects
- [ ] Verification that side effects are isolated to bus layer
- [ ] Tests for side effect ordering

#### 4.3: Remove Legacy/Dead Code
**Method**: Search for commented code, old investigation scripts

**Candidates**:
- [ ] Old diagnostic scripts (`diagnose_*.zig` in root)
- [ ] Commented-out code blocks
- [ ] Unused helper functions
- [ ] Deprecated test utilities

**Rule**: If it's not in `build/tests.zig`, it should be removed or documented

### Phase 5: Testing & Validation (Priority: CRITICAL)

**Goal**: Ensure all fixes pass tests and don't introduce regressions

**Tasks**:

#### 5.1: Unit Test Expansion
**Files**: Add to existing test files

**Coverage Targets**:
```
RMW Instructions:
- [ ] Zero page RMW with PPU register ($2006)
- [ ] Absolute RMW with PPU register
- [ ] Indexed RMW with PPU register ($2000,X)
- [ ] Verify dummy write occurs before modified write
- [ ] Verify PPU state changes correctly

Open Bus:
- [ ] Write-only PPU registers return open bus
- [ ] Open bus persists across multiple reads
- [ ] Decay timer reduces value after 60 frames
- [ ] Bus writes update open bus immediately

NMI Ledger:
- [ ] $2002 reads update last_read_cycle
- [ ] Dummy reads update last_read_cycle
- [ ] DMA doesn't corrupt last_read_cycle
- [ ] Race condition suppression works
```

#### 5.2: Integration Test Validation
**Method**: Run full test suite after each fix

**Command**: `zig build test --summary failures`

**Acceptance Criteria**:
- [ ] All 3 accuracy tests pass (0x00 result)
- [ ] No regressions in existing tests
- [ ] AccuracyCoin execution test passes

#### 5.3: Commercial ROM Regression Testing
**ROMs to Test**:
- [ ] Castlevania
- [ ] Mega Man
- [ ] Kid Icarus
- [ ] SMB1/2/3
- [ ] Kirby's Adventure

**Verification**:
- [ ] No new crashes
- [ ] No new visual glitches
- [ ] Gameplay remains functional

---

## Implementation Strategy

### Workflow Rules

1. **Never Guess**: Run diagnostics first, fix based on evidence
2. **Test After Every Change**: `zig build test` must pass
3. **Document As You Go**: Update this plan with findings
4. **One Fix At A Time**: Isolate changes for easier debugging
5. **Git Commits At Milestones**: Commit working states frequently

### Development Phases

**Phase 1 (Days 1-2)**: Diagnostics
- Build comprehensive tracing infrastructure
- Identify exact failure points
- Document findings

**Phase 2 (Days 3-4)**: Open Bus Fixes
- Fix any open bus issues found
- Expand test coverage
- Verify AccuracyCoin PPU_Open_Bus test passes

**Phase 3 (Days 5-6)**: NMI Ledger Fixes
- Fix $2002 read path gaps
- Add edge case handling
- Verify nmi_control_test passes

**Phase 4 (Days 7-8)**: Refactoring & Cleanup
- Eliminate early returns
- Remove dead code
- Improve documentation

**Phase 5 (Days 9-10)**: Validation
- Full test suite run
- Commercial ROM testing
- Performance verification

### Success Criteria

**Primary Goal**: All 3 accuracy tests pass
```
✅ dummy_write_cycles_test: Result=0x00 (PASS)
✅ nmi_control_test: Result=0x00 (PASS)
✅ unofficial_instructions_test: Result=0x00 (PASS)
```

**Secondary Goals**:
- [ ] No test regressions (990+/995 passing)
- [ ] Commercial ROMs still work
- [ ] Code maintainability improved

---

## File Organization

### New Files To Create

```
tests/integration/accuracy/
  └── diagnostic_runner.zig          # Comprehensive execution tracer

tests/ppu/
  └── open_bus_behavior_test.zig     # PPU open bus unit tests

tests/integration/accuracy/
  └── nmi_edge_detection_test.zig    # NMI edge case tests

docs/sessions/
  └── 2025-10-19-remediation-development-plan.md  # This document
  └── 2025-10-19-diagnostic-findings.md  # Results from Phase 1
```

### Files To Modify

```
src/emulation/cpu/execution.zig      # Possible fixes for early returns
src/emulation/cpu/microsteps.zig     # Enhanced RMW debug logging
src/ppu/logic/registers.zig          # Open bus debug logging, possible fixes
src/emulation/State.zig              # NMI ledger update logic fixes
src/emulation/VBlankLedger.zig       # Possible edge case fixes
```

### Files To Remove

```
diagnose_*.zig (root directory)      # Old investigation scripts
scripts/test_smb_ram.zig             # Deprecated diagnostic (already in git status)
```

---

## Risk Assessment

### High-Risk Changes
- **NMI ledger modifications**: Could break existing VBlank tests
- **Open bus timing changes**: Could affect commercial ROM behavior
- **Early return elimination**: Could introduce subtle state bugs

**Mitigation**: Full test suite run after each change, git commits at stable points

### Medium-Risk Changes
- **Debug logging additions**: Minimal risk, easy to remove
- **Test expansion**: Could expose new bugs (actually good!)

### Low-Risk Changes
- **Code cleanup**: Removing dead code is safe
- **Documentation improvements**: Zero risk

---

## Questions For Review

Before starting implementation, verify:

1. ✅ **Investigation Completeness**: Have we analyzed all relevant subsystems?
   - Yes: CPU execution, microsteps, JSR/RTS, open bus, NMI ledger, PPU registers

2. ❓ **Root Cause Confidence**: Are we confident in the primary hypothesis?
   - Moderate: Believe PPU open bus test is failing, need diagnostics to confirm

3. ✅ **Plan Feasibility**: Is the 10-day timeline realistic?
   - Yes: Phased approach with clear milestones

4. ✅ **Test Coverage**: Do we have adequate tests for verification?
   - Yes: 3 failing tests + unit tests + commercial ROMs

5. ❓ **Missing Pieces**: Are there any unanalyzed areas?
   - DMA interaction with open bus (medium priority)
   - Debugger read paths (low priority)
   - Cartridge mapper side effects (low priority)

---

## Next Steps (Immediate)

1. **Review this plan with user** - Get approval/feedback
2. **Create diagnostic_runner.zig** - Start Phase 1
3. **Run first diagnostic** - Identify exact failure point
4. **Update this document** - Add findings to new section
5. **Proceed with fixes** - Based on diagnostic results

---

## Document History

- **2025-10-19 21:00**: Initial plan created after comprehensive investigation
- **Status**: PENDING REVIEW - Awaiting user approval to proceed

## Related Documents

- `/docs/sessions/2025-10-18-cpu-execution-bug.md` - Previous CPU investigation
- `/docs/sessions/2025-10-19-dummywrite-nmi-investigation.md` - Current investigation notes
- `/docs/CURRENT-ISSUES.md` - Overall project status
- `/CLAUDE.md` - Project architecture and patterns

---

**Plan Author**: Claude Code (AI Assistant)
**Review Required**: YES - User approval needed before implementation
**Estimated Duration**: 10 days (phased approach)
**Success Metric**: All 3 AccuracyCoin accuracy tests passing (0x00 result)
