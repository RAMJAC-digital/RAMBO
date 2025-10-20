# AccuracyCoin ROM Structure Analysis

**Date:** 2025-10-19
**Status:** Investigation in Progress

## Problem Statement

AccuracyCoin tests are not running when we boot from reset. The ROM writes initialization values (0x00) to result addresses, then gets stuck in an infinite loop at `JMP $8111`.

## Diagnostic Findings

### VBlank Beginning Test ($0450)
- Initial: 0xFF → 0x09 (RAM) → 0x00 (ROM init at cycle 242,474)
- ROM never writes 0x80 (RUNNING)
- ROM stuck at PC=0x8111 in infinite loop `JMP $8111`
- NMI enabled: true
- VBlank working: yes
- Test NEVER executes

### Dummy Write Cycles Test ($0407)
- Initial: 0xFF → 0x50 (RAM) → 0x00 (ROM init at cycle 236,123)
- ROM never writes 0x80 (RUNNING)
- Timeouts after 50M cycles
- Test "passes" only because it expects 0x00 from initialization
- Test NEVER actually executes

## Root Cause

AccuracyCoin is NOT designed to run all tests automatically from reset. It likely:
1. Boots to a menu/title screen
2. Requires user input or specific setup to select/run tests
3. OR runs tests when jumped to specific entry points

## Evidence from ROM Screenshots

User provided screenshots show tests FAILING with specific codes:
- VBlank Beginning: FAIL 1
- VBlank End: FAIL 1
- NMI Control: FAIL 7
- etc.

This proves the tests CAN run and produce results. But our approach of booting from reset doesn't trigger them.

## Previous Approach (Before My Changes)

Old tests jumped directly to entry points:
```zig
h.state.reset();
h.state.ppu.warmup_complete = true;
h.state.cpu.pc = 0xA318;  // Jump to TEST_DummyWrites
h.state.cpu.sp = 0xFD;
h.state.bus.ram[0x0407] = 0x80;  // Initialize result
```

This approach:
- ✅ Allowed tests to execute and produce results
- ❌ Skipped ROM initialization (NMI handlers, etc.)
- ❌ Caused tests to hang (my original finding)

## Hypothesis

The hanging was NOT caused by jumping to entry points. It was caused by:
1. Missing NMI handler initialization
2. Missing other ROM setup code
3. PPU warmup bypass interfering with test expectations

## Proposed Solution

**Hybrid Approach:**
1. Boot from reset vector for initialization (let ROM set up NMI handlers, etc.)
2. Run for N frames to complete warmup and setup
3. THEN jump to specific test entry point
4. Let test execute and write result to memory
5. Read result and validate

This gives us:
- ✅ Proper ROM initialization
- ✅ NMI handlers set up correctly
- ✅ Test actually executes
- ✅ Real results (not just initialization values)

## Next Steps

1. Determine how many initialization frames are needed
2. Create helper function to "boot then jump"
3. Update all accuracy tests to use this approach
4. Verify results match ROM screenshots
5. Fix any remaining issues

## Questions to Answer

1. How does AccuracyCoin work when run normally in an emulator?
2. Does it auto-run tests or require user input?
3. What memory addresses contain FINAL results vs intermediate state?
4. Are result addresses ($0407, $0450, etc.) correct?

## References

- ROM Screenshots: `/home/colin/Development/RAMBO/results/accuracy_screenshots/`
- Page 17: VBlank/NMI test results
- Page 12: CPU interrupt test results
- Page 16: PPU behavior test results
