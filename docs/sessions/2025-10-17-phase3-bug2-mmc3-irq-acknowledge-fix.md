# Bug #2: MMC3 IRQ Acknowledge Fix — 2025-10-17

## Summary

**Fixed MMC3 IRQ acknowledge bug** where $E001 (IRQ enable) incorrectly cleared the pending flag.

**Impact:** Ensures IRQ pending flag persists correctly between enable/disable cycles per nesdev.org specification.

**Result:** Zero regressions (1043/1049 tests, same as before), hardware-accurate IRQ behavior.

---

## Problem

### Root Cause

`src/cartridge/mappers/Mapper4.zig:146` incorrectly cleared `irq_pending` when writing to $E001 (IRQ enable):

```zig
// WRONG:
} else {
    // $E001-$FFFF: IRQ enable
    // Per nesdev.org: Writing to $E001 acknowledges any pending IRQ
    self.irq_enabled = true;
    self.irq_pending = false;  // ← INCORRECT!
}
```

**Hardware Specification (per nesdev.org):**
> **$E000 (even)** - IRQ Disable
> "Writing any value to this register will disable MMC3 interrupts AND acknowledge any pending interrupts."
>
> **$E001 (odd)** - IRQ Enable
> "Writing any value to this register will enable MMC3 interrupts. The MMC3 will continue to clock the IRQ counter regardless of the setting here."

### Why This Was Wrong

**Per nesdev.org specification:**
- **$E000 (disable)**: Disables IRQ **AND** acknowledges pending interrupts
- **$E001 (enable)**: Enables IRQ but does **NOT** acknowledge pending interrupts

**Incorrect behavior:**
```
Game writes $E001 to enable IRQs
→ Our code cleared irq_pending flag
→ Any IRQ that fired before enabling would be lost
→ Violates hardware specification
```

**Correct behavior:**
```
IRQ fires → irq_pending = true
Game writes $E001 (enable)
→ irq_pending STAYS true (not cleared)
→ CPU will still see the pending IRQ
→ Game must write $E000 (disable) to acknowledge
```

### Impact on Games

Most MMC3 games use this pattern in their IRQ handlers:

```assembly
; IRQ handler
IRQ_Handler:
    PHA                     ; Save A
    LDA #$00
    STA $E000               ; Disable IRQ + acknowledge (clears pending)
    ; ... handle split-screen effect ...
    STA $E001               ; Re-enable IRQ for next frame
    PLA
    RTI
```

Our bug meant that the re-enable at the end would incorrectly clear any new IRQ that fired during the handler, potentially causing IRQ storms or missed IRQs.

---

## Solution

### Changes Made

**1. Fixed $E001 handler** (`src/cartridge/mappers/Mapper4.zig:143-146`):

```zig
// OLD (BUGGY):
} else {
    // $E001-$FFFF: IRQ enable
    // Per nesdev.org: Writing to $E001 acknowledges any pending IRQ
    self.irq_enabled = true;
    self.irq_pending = false;  // ← REMOVED THIS LINE
}

// NEW (CORRECT):
} else {
    // $E001-$FFFF: IRQ enable
    // Per nesdev.org: Enables IRQ generation without acknowledging pending IRQ
    // Only $E000 (disable) acknowledges pending IRQs
    self.irq_enabled = true;
}
```

**2. Updated test expectations** (`src/cartridge/mappers/Mapper4.zig:617-666`):

Changed test from verifying that $E001 **clears** pending to verifying it **does NOT** clear pending:

```zig
test "Mapper4: IRQ enable does NOT clear pending flag" {
    // Per nesdev.org: $E001 (IRQ enable) only enables IRQ generation.
    // It does NOT acknowledge pending IRQs - only $E000 (disable) acknowledges.
    // Reference: https://www.nesdev.org/wiki/MMC3

    // ... test setup that triggers IRQ ...

    // Verify IRQ fired and pending flag is set
    try testing.expectEqual(true, mapper.irq_pending);

    // Write to $E001 (IRQ enable) - should NOT clear pending flag
    mapper.irq_enabled = false; // Reset for test
    mapper.cpuWrite(mock_cart, 0xE001, 0x00);

    // Verify: IRQ pending flag remains set (NOT cleared by $E001)
    try testing.expectEqual(true, mapper.irq_pending);  // Still pending!
    try testing.expectEqual(true, mapper.irq_enabled);

    // Write to $E000 (IRQ disable) - SHOULD clear pending flag
    mapper.cpuWrite(mock_cart, 0xE000, 0x00);

    // Verify: $E000 acknowledges the IRQ
    try testing.expectEqual(false, mapper.irq_pending); // Now cleared!
    try testing.expectEqual(false, mapper.irq_enabled);
}
```

**3. Verified $E000 still acknowledges correctly** (lines 122-125):

```zig
// $E000-$FFFE: IRQ disable
self.irq_enabled = false;
self.irq_pending = false;  // Still correctly acknowledges
```

---

## Testing

### Test Results

**Before:** 1043/1049 tests passing (after Bug #1)
**After:** 1043/1049 tests passing (no change)

**Mapper4 unit tests:** 14/14 passing ✅

**No regressions** - all existing tests still pass.

### Verification

```bash
$ zig test src/cartridge/mappers/Mapper4.zig
All 14 tests passed.

$ zig build test
Build Summary: 166/168 steps succeeded; 1 failed; 1043/1049 tests passed; 5 skipped; 1 failed
```

**Only failing test:** `smb3_status_bar_test` (integration test - was already failing before Bug #1)

---

## Expected Impact

### Hardware Accuracy

**After this fix:**
- ✅ $E000 (disable) acknowledges IRQs per spec
- ✅ $E001 (enable) does NOT acknowledge IRQs per spec
- ✅ IRQ pending flag persists correctly between enable/disable cycles
- ✅ Games can re-enable IRQs without losing pending state

### Technical Impact

- IRQ handlers can safely disable → re-enable without clearing pending flags
- IRQ pending state is only cleared by explicit $E000 write (disable + acknowledge)
- Matches actual MMC3 hardware behavior
- Prevents potential IRQ storms or missed IRQs in edge cases

---

## Files Modified

1. `src/cartridge/mappers/Mapper4.zig` — Fixed $E001 handler, updated test

**Total:** 1 file, 1 line removed, 15 lines changed (test update)

---

## Code Quality

- ✅ **No dead code** - Only removed incorrect line
- ✅ **Follows patterns** - Matches existing register handler structure
- ✅ **Well documented** - Comments explain hardware behavior and reference nesdev.org
- ✅ **Zero regressions** - All existing tests pass
- ✅ **Test coverage** - Updated test verifies correct behavior

---

## Hardware Reference

**nesdev.org MMC3 specification:**

> **$E000-$FFFE (even addresses) - IRQ Disable**
> "Writing any value to this register will disable MMC3 interrupts AND acknowledge any pending interrupts."
>
> **$E001-$FFFF (odd addresses) - IRQ Enable**
> "Writing any value to this register will enable MMC3 interrupts. The MMC3 will continue to clock the IRQ counter regardless of the setting here."

Key insight: Only $E000 acknowledges interrupts. $E001 only enables, it does not acknowledge.

---

## Next Steps

**Bug #3:** Input system keysym migration (P0)
- Migrate from layout-dependent keycodes to layout-independent keysyms
- Add keysym field to XdgInputEventMailbox
- Extract keysym in WaylandLogic
- Update KeyboardMapper to use keysyms
- Add --input-diagnostics flag for debugging

---

**Milestone:** Bug #2 (MMC3 IRQ Acknowledge) — ✅ COMPLETE
**Date:** 2025-10-17
**Tests:** 1043/1049 passing (no change)
**Regressions:** 0
