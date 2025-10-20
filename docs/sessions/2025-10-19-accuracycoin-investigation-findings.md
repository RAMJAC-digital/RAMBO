# AccuracyCoin Test Investigation Findings
**Date:** 2025-10-19
**Investigator:** Claude (session continuation)
**Status:** COMPLETE - Root cause identified

## Executive Summary

All AccuracyCoin accuracy tests in `tests/integration/accuracy/` are **BROKEN** and do not reflect ROM behavior. Tests use a "direct jump" approach that bypasses critical ROM initialization, causing them to hang in VBlank polling loops or BRK interrupt loops.

### Key Findings

1. **Tests timeout and fail** - Result is 0x80 (RUNNING), not expected values
2. **Comments are incorrect** - Tests claim to pass but actually timeout after 1M cycles
3. **Direct jump approach doesn't work** - Bypasses ROM's RunTest initialization
4. **VBlank polling hangs** - Tests wait for VBlank that never arrives
5. **BRK loop traps** - Uninitialized IRQ handlers cause infinite interrupt loops

## Investigation Process

### Phase 1: Understanding ROM Boot Behavior

Created `diagnose_accuracycoin_results.zig` to observe ROM behavior.

**Boot from reset (1M cycles):**
- PC ends at 0xFF09 (ROM main loop area)
- All result addresses contain 0x00 (initialization values)
- NMI vector points to $0700 (RAM)
- IRQ vector points to $0600 (RAM)
- ROM does NOT auto-run tests - requires menu navigation or function calls

### Phase 2: Testing Direct Jump Approach

Jumped directly to TEST_DummyWrites entry point (0xA318):

**Execution trace:**
```
Cycles 0-200k:   PC loops in 0xF92F-0xF934 range
Cycle 186419:    Jump to IRQ vector at 0x0600
Cycle 186419+:   Stuck in BRK loop with stack overflow
```

**Code at 0xF92F (disassembled):**
```asm
F92F:  LDA $2002    ; AD 02 20 - Read PPUSTATUS
F932:  BPL -5       ; 10 FB    - Branch if VBlank not set (bit 7 = 0)
F934:  RTS          ; 60       - Return when VBlank detected
```

**Analysis:** Test waits for VBlank flag in $2002 bit 7, but VBlank never occurs.

**Stack analysis (SP=0xF9):**
```
[0x01FA] = 0x3A  \
[0x01FB] = 0xF9  / Return address: 0xF93A (little-endian)
```

Test expects to RTS to 0xF93B after VBlank occurs.

### Phase 3: IRQ Vector Investigation

**Execution after ~186k cycles:**
- PC jumps from $F900 range to $0600 (IRQ vector)
- Opcode at $0602 is 0x00 (BRK)
- Stack cycles: SP=0xFD → 0x00 → 0xFD (wraps around page)
- Classic BRK loop: BRK → push 3 bytes → jump to IRQ → BRK → repeat

**Root cause:** IRQ handler in RAM at $0600-$0602 is uninitialized (contains 0x00 bytes).

## AccuracyCoin ROM Structure (from ASM analysis)

### RunTest Function (line 15328 in AccuracyCoin.asm)

The ROM's official test execution flow:

```asm
RunTest:
    JSR DisableNMI              ; Turn off NMI during tests
    LDX <menuCursorYPos         ; X = which test to run
    ; ... setup code ...

    ; Clear RAM page 5 ($0500-$05FF)
    LDA #0
    LDY #0
:   STA $0500,Y
    INY
    BNE :-

    ; Construct "JSR [Test], RTS" in RAM at $001A
    LDA <suiteExecPointerList,X ; Get test entry point
    STA <JSRFromRAM+1           ; Store address in JSR instruction
    LDA <suiteExecPointerList+1,X
    STA <JSRFromRAM+2

    JSR WaitForVBlank           ; Synchronize to frame boundary
    JSR JSRFromRAM              ; Execute test (returns via RTS with result in A)

    ; A register now holds test result
    STA [TestResultPointer],Y   ; Store result in result array
```

### Test Result Encoding

From ASM lines 1503-1512:

```asm
TEST_Pass:
    LDA #01        ; Result = 0x01 = PASS
    RTS

TEST_Fail:
    LDA <ErrorCode ; Load error code
    ASL A          ; ErrorCode << 2
    ORA #02        ; | 0x02 = FAIL with error code
    RTS
```

**Result codes:**
- `0x00` = Uninitialized / not set (NOT pass!)
- `0x01` = PASS
- `0x02+` = FAIL (value encodes which subtest failed)
- `0x80` = RUNNING (custom marker used by our tests)

### Critical Initialization Missing

When jumping directly to test entry points, we bypass:

1. **NMI disable** - Tests expect NMI off during execution
2. **RAM page 5 clear** - Tests use $0500-$05FF for scratch space
3. **VBlank synchronization** - Tests expect to start at frame boundary
4. **JSR wrapper** - Tests expect to RTS with result in A register
5. **IRQ handler setup** - Tests may rely on proper IRQ vector initialization

## Current Test Implementation Problems

### Example: dummy_write_cycles_test.zig

**Current approach (lines 43-59):**
```zig
// Set PC to TEST_DummyWrites entry point
h.state.cpu.pc = 0xA318;
h.state.cpu.state = .fetch_opcode;
h.state.cpu.instruction_cycle = 0;
h.state.cpu.sp = 0xFD;

// Initialize zero-page variables
h.state.bus.ram[0x10] = 0x00; // ErrorCode
h.state.bus.ram[0x50] = 0x00; // Scratch
h.state.bus.ram[0xF0] = 0x00; // PPUCTRL_COPY
h.state.bus.ram[0xF1] = 0x00; // PPUMASK_COPY

// Initialize result address to 0x80 (RUNNING)
h.state.bus.ram[0x0407] = 0x80;
```

**Problems:**
- ❌ NMI not disabled
- ❌ RAM page 5 not cleared
- ❌ No VBlank synchronization
- ❌ IRQ handler not initialized
- ❌ No JSR wrapper for RTS
- ❌ Test hangs in VBlank polling loop

**Actual result:** Test times out after 1M cycles with result=0x80 (RUNNING)

**Expected result:** Comment claims 0x00 (PASS) but test never completes

### Excessive Logging

Lines 62-127 contain extensive diagnostic logging:
- PPU open bus pre-check (lines 62-79)
- ErrorCode change tracking (lines 92-97)
- Stack pointer corruption detection (lines 100-105)
- Failure diagnosis dump (lines 118-127)

This clutters test output and obscures actual test failures.

## ROM Screenshot Evidence

User provided ROM screenshots showing AccuracyCoin running on actual hardware.

**Expected results (from ROM screenshots):**
- Dummy Writes: PASS
- VBlank Beginning: FAIL 1
- VBlank End: FAIL 1
- NMI Control: FAIL 7
- NMI Timing: FAIL 1

**Current test expectations (from comments):**
- Match screenshots: ✅ (comments updated 2025-10-19)
- Tests expect current FAIL values to detect regressions

**Actual test behavior:**
- All tests TIMEOUT with result=0x80 (RUNNING)
- Tests don't match ROM behavior at all
- Comments claim tests pass but they actually fail

## Recommended Fixes

### Option 1: Emulate RunTest Initialization (RECOMMENDED)

Replicate what AccuracyCoin's RunTest function does:

```zig
// 1. Disable NMI
h.state.cpu.p.interrupt_disable = true;
// OR: h.state.busWrite(0x2000, 0x00); // PPUCTRL = 0 (NMI off)

// 2. Clear RAM page 5
for (0x0500..0x0600) |addr| {
    h.state.bus.ram[addr & 0x07FF] = 0x00;
}

// 3. Initialize IRQ handler in RAM (simple RTI)
h.state.bus.ram[0x0600] = 0x40; // RTI opcode

// 4. Wait for VBlank
h.seekToScanlineDot(241, 1); // VBlank start

// 5. Set PC to test entry point
h.state.cpu.pc = 0xA318; // TEST_DummyWrites
h.state.cpu.state = .fetch_opcode;
h.state.cpu.instruction_cycle = 0;
h.state.cpu.sp = 0xFD;

// 6. Run test with proper cycle budget
const max_cycles = 10_000_000; // Some tests need full frames
while (cycles < max_cycles) {
    h.state.tick();
    const result = h.state.bus.ram[0x0407];
    if (result != 0x80) break; // Test completed
}
```

### Option 2: Use ROM's RunTest Function

Boot ROM and call RunTest directly:

```zig
// 1. Boot ROM from reset
h.state.reset();
h.state.ppu.warmup_complete = true;

// 2. Run until ROM initialized
for (0..100_000) |_| h.state.tick();

// 3. Set up test selection
h.state.bus.ram[0x0C] = test_id; // menuCursorYPos

// 4. Call RunTest
h.state.cpu.pc = 0xXXXX; // Address of RunTest function
// ... push return address ...
h.state.cpu.state = .fetch_opcode;

// 5. Run until test completes
// ... check result address ...
```

**Problem:** Requires finding RunTest address and understanding its calling convention.

### Option 3: Boot Full ROM and Navigate Menu

Most realistic but slowest:

```zig
// 1. Boot ROM
h.state.reset();
h.state.ppu.warmup_complete = true;

// 2. Simulate controller inputs to navigate menu
// ... press A to select test ...

// 3. Run until test completes
// ... monitor result address ...
```

**Problem:** Requires understanding menu navigation and timing.

## Immediate Action Items

### 1. Fix dummy_write_cycles_test.zig

- ✅ Remove excessive logging (lines 62-79, 92-105, 118-127)
- ✅ Implement proper initialization (Option 1)
- ✅ Increase max_cycles to 10M (tests need full frames)
- ✅ Update expected results to match ROM screenshots
- ✅ Verify test actually runs and completes

### 2. Fix Other Accuracy Tests

Apply same fixes to:
- vblank_beginning_test.zig
- vblank_end_test.zig
- nmi_control_test.zig
- nmi_timing_test.zig
- nmi_suppression_test.zig

### 3. Remove Misleading Comments

Update all comments claiming tests pass when they actually timeout.

### 4. Verify Against ROM Screenshots

Run fixed tests and compare results to user-provided ROM screenshots:
- Tests should return actual FAIL values, not timeout
- Results should match hardware behavior
- Tests should complete in reasonable time (<10M cycles)

### 5. Update Session Documentation

Document:
- Why tests were broken
- How they were fixed
- What initialization is required
- Expected test results from ROM screenshots

## Technical Details

### VBlank Timing Issue

Tests hang waiting for VBlank because:

1. PPU warmup is bypassed: `h.state.ppu.warmup_complete = true`
2. PPU timing may not progress correctly
3. VBlank flag ($2002 bit 7) never gets set
4. Test stuck in polling loop: `LDA $2002; BPL -5`

**Fix:** Either implement proper VBlank timing or seek to VBlank start before test.

### BRK Loop Trap

After ~186k cycles, execution jumps to IRQ vector ($0600-$0602):

1. IRQ vector contains 0x00 (BRK) due to uninitialized RAM
2. BRK executes → pushes 3 bytes → jumps to IRQ vector
3. Infinite loop: BRK → IRQ → BRK → ...
4. Stack wraps around page: SP cycles 0xFD → 0x00 → 0xFD

**Fix:** Initialize IRQ handler in RAM at $0600 with RTI (0x40) opcode.

### Stack Behavior

Normal execution:
- SP starts at 0xFD (after reset)
- JSR pushes 2 bytes: SP becomes 0xFB
- RTS pops 2 bytes: SP becomes 0xFD

BRK loop:
- BRK pushes 3 bytes: SP = 0xFD → 0xFA
- RTI pops 3 bytes: SP = 0xFA → 0xFD
- But with BRK loop (no RTI), stack wraps: 0xFD → 0xFA → 0xF7 → ... → 0x00 → 0xFD

## Conclusion

All AccuracyCoin accuracy tests are fundamentally broken due to bypassing ROM initialization. The "direct jump" approach cannot work without replicating the setup that RunTest performs.

**Recommended approach:** Option 1 (Emulate RunTest initialization) - provides balance of accuracy and simplicity.

**Success criteria:**
- ✅ Tests complete without timeout
- ✅ Results match ROM screenshot values
- ✅ No excessive logging
- ✅ Tests serve as regression detection

**Next steps:**
1. Implement Option 1 initialization in all accuracy tests
2. Remove excessive diagnostic logging
3. Verify results match ROM screenshots
4. Update CLAUDE.md with findings
5. Proceed to fixing actual VBlank/NMI bugs (after test suite verified)
