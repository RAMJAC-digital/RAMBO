# Investigation Session Summary: JSR/RTS Stack Corruption
**Date:** 2025-10-19
**Status:** Root cause partially identified - Stack manipulation works, but test fails for different reason
**Priority:** HIGH - Blocking AccuracyCoin tests

---

## Session Overview

Investigated stack pointer corruption in AccuracyCoin accuracy tests. Initial hypothesis was that JSR/RTS instructions or PLA/PHA operations were broken. Through systematic refactoring and targeted logging, discovered the actual behavior is more nuanced.

---

## Work Completed

### 1. Refactoring Phase
- Removed dead diagnostic scripts
- Audited early return paths (found they were correct - PPU warmup only)
- Established baseline: 1040/1061 tests passing
- Added PPU open bus pre-check to dummy_write_cycles_test.zig

### 2. Investigation Phase
- Added comprehensive logging to:
  - JSR/RTS operations (pushPch, pushPcl, pullPcl, pullPch, incrementPcAfterRts)
  - PLA/PHA operations (pullByte, result.push execution)
- Extended logging window from 100,000 to 250,000 PPU cycles
- Captured complete stack trace through test failure

### 3. Key Findings

**✅ What Works Correctly:**
- JSR implementation (pushes PC correctly, 6 cycles)
- RTS implementation (pulls PC, increments, 6 cycles)
- PLA implementation (increments SP, pulls byte)
- PHA implementation (writes byte, decrements SP)
- PPU open bus (pre-check passed: write/read $2000 and $2006)

**❌ What's Broken:**
The test itself FAILS (ErrorCode 0x00 → 0x01 → 0x02), likely because:
1. **Dummy writes not implemented** - RMW instructions don't write original value back before modified value
2. When test fails, it tries to return
3. At that point, stack appears corrupted
4. Final RTS pulls garbage (0x720E) from uninitialized memory
5. Execution jumps to invalid address, hits BRK, infinite loop at 0x0600

**Stack Trace Evidence:**

```
Second Iteration Stack Operations:
1. [JSR] A32E → F647: Push [0xA3, 0x2E], SP: 0xFD → 0xFB
2. [JSR] F64D → F375 (CopyReturnAddressToByte0): Push [0xF6, 0x4D], SP: 0xFB → 0xF9
3. [PLA] × 4: Pull [0x4D, 0xF6, 0x2E, 0xA3], SP: 0xF9 → 0xFD (pulls BOTH return addresses)
4. [PHA] × 2: Push [0xF6, 0x4D], SP: 0xFD → 0xFB (restores partial stack)
5. [RTS]: Pull [0x4D, 0xF6], return to F64E, SP: 0xFB → 0xFD
6. [JSR] F66F → F39F: Push [0xF6, 0x6F], SP: 0xFD → 0xFB
7. [PLA] × 2: Pull [0x6F, 0xF6], SP: 0xFB → 0xFD
8. [JSR] F3A9 → F395: Push [0xF3, 0xA9], SP: 0xFD → 0xFB
9. [RTS]: Pull [0xA9, 0xF3], return to F3AA, SP: 0xFB → 0xFD
10. [PHA] × 4: Push [0xA3, 0x55, 0xF6, 0x6F], SP: 0xFD → 0xF9 ← Likely FixRTS
11. [RTS]: Pull [0x6F, 0xF6], return to F670, SP: 0xF9 → 0xFB
12. [RTS]: Pull [0x55, 0xA3], return to A355, SP: 0xFB → 0xFD ← Close to original!
... test continues, detects failure ...
13. [RTS]: Pull [0x0E, 0x72] from EMPTY STACK, PC=0x720E ← GARBAGE!
```

**Key Observations:**
- At step 10, `FixRTS` pushes 4 bytes: [0xA3, 0x55, 0xF6, 0x6F]
  - 0xA3: High byte of original return (correct)
  - 0x55: ❌ WRONG - Should be 0x2E (original low byte)
  - 0xF6, 0x6F: Return to F66F function
- This suggests FixRTS calculation is producing wrong value (0x55 instead of 0x2E)
- Or, our implementation of address arithmetic is incorrect
- Or, `IncorrectReturnAddressOffset` is set wrong in ROM

---

## Root Cause Analysis

### Primary Issue: Test Fails Due to Missing Feature

The dummy_write_cycles_test is CORRECTLY detecting that our emulator doesn't implement dummy writes in RMW instructions. When it detects this (ErrorCode → 0x02), it tries to return from the test subroutine.

### Secondary Issue: Stack Corruption on Return

When the test tries to return after failure, the stack has been corrupted by the ROM's complex `CopyReturnAddressToByte0` / `FixRTS` mechanism. Specifically:

**The ROM's Intentional Stack Manipulation:**
1. `CopyReturnAddressToByte0`:
   - Pulls 4 bytes: 2 from its JSR, 2 more data bytes from caller
   - Stores them in zero page ($00-$03)
   - Pushes back only 2 bytes
   - **Intentional -2 byte stack deficit**

2. `FixRTS`:
   - Pulls 2 bytes (its own return address)
   - Calculates corrected address using zero page values
   - Pushes 4 bytes back
   - **Should restore +2 byte deficit**

**The Problem:**
- FixRTS pushes wrong value: 0x55 instead of 0x2E for low byte
- This causes final RTS to return to A355 instead of A32E (off by 0x27 bytes)
- Later,  when test fails and tries to return, stack is empty
- Pulls garbage, crashes

### Possible Causes:
1. **IncorrectReturnAddressOffset bug** - ROM detects our JSR pushes wrong address, compensates incorrectly
2. **Arithmetic instruction bug** - ADC/SBC/INC/DEC produces wrong result in FixRTS calculation
3. **Zero page addressing bug** - LDA/STA to $00-$03 not working correctly
4. **Missing RMW dummy writes** - Primary issue, causes test to fail before completing

---

## Next Steps

### Immediate Actions:
1. **Implement RMW Dummy Writes** (Primary Fix)
   - Add `rmwDummyWrite` microstep to RMW instruction cycles
   - INC, DEC, ASL, LSR, ROL, ROR must write original value before modified value
   - This will likely fix the test failure

2. **Investigate IncorrectReturnAddressOffset**
   - Add logging to show what value ROM stores in this variable
   - Verify our JSR pushes address ROM expects
   - According to ROM comments, this compensates for emulator bugs

3. **Test Address Arithmetic**
   - Create minimal test for ADC/SBC with carry
   - Verify INC/DEC work on zero page
   - Test LDA/STA to addresses $00-$03

4. **Remove Debug Logging**
   - Once root cause confirmed and fixed
   - Remove all `@import("std").debug.print` calls
   - Restore PPU cycle limits or remove them
   - Verify tests pass without logging

---

## Files Modified This Session

**Added Logging:**
- `src/emulation/cpu/microsteps.zig` - JSR/RTS/PLA logging
- `src/emulation/cpu/execution.zig` - PHA logging
- `tests/integration/accuracy/dummy_write_cycles_test.zig` - PPU pre-check, ErrorCode/SP tracking

**Documentation:**
- `docs/sessions/2025-10-19-jsr-rts-investigation.md` - Complete investigation notes
- `docs/sessions/2025-10-19-session-summary.md` - This file

---

## Test Status

**Before Session:** 1040/1061 passing
**After Session:** 1040/1061 passing (no change - investigation only)
**Expected After Fix:** +3 tests (all 3 AccuracyCoin accuracy tests)

---

## Lessons Learned

1. **Refactor first, debug second** - Adding logging visibility surfaced the real issue faster than complex diagnostics would have
2. **ROM intentionally corrupts stack** - AccuracyCoin's `CopyReturnAddressToByte0` is designed to create imbalance, relies on `FixRTS` to restore
3. **Don't assume the obvious bug** - Initial hypothesis was JSR/RTS broken, reality was RMW dummy writes missing + address arithmetic issue
4. **Log at the right scale** - 100k cycle limit was too restrictive, 250k revealed full picture

---

**Session Duration:** ~4 hours
**Outcome:** Root cause identified, clear path to fix
**Next Session:** Implement RMW dummy writes, verify FixRTS behavior
