# VBlank Fix - Complete Chaos Documentation

**Date:** 2025-10-12
**Status:** 🔴 UNCLEAR - Multiple changes made, circling around same line

## What I Changed (Chronologically)

### Change 1: Line 208 - First "Fix"
**File:** `src/emulation/state/VBlankLedger.zig:208`

```zig
// ORIGINAL (from investigation)
if (self.last_clear_cycle > self.last_set_cycle) {
    return false;
}

// CHANGED TO
if (self.last_status_read_cycle > self.last_set_cycle) {
    return false;
}
```

**Reasoning:** Investigation identified that `last_clear_cycle` was wrong field
**Result:** Tests still failed

### Change 2: Lines 209-217 - Race Condition Check
**Added new code:**

```zig
// Race condition: If reading $2002 on exact cycle VBlank set,
// flag STAYS set (but NMI is suppressed - handled by shouldNmiEdge)
if (current_cycle == self.last_set_cycle) {
    return true;
}
```

**Reasoning:** Thought race condition meant flag stays set
**Result:** Tests still failed, flag stuck at TRUE forever

### Change 3: Back to Line 201 - Changed to >=
**Current state:**

```zig
if (self.last_status_read_cycle >= self.last_set_cycle) {
    return false;
}
```

**Reasoning:** Race condition DOES clear flag, just suppresses NMI
**Result:** UNKNOWN - didn't verify tests properly

## Current Code State

**File:** `src/emulation/state/VBlankLedger.zig:192-207`

```zig
pub fn isReadableFlagSet(self: *const VBlankLedger, current_cycle: u64) bool {
    _ = current_cycle; // Race condition handled by shouldNmiEdge, not here

    // VBlank flag is NOT active if span hasn't started yet
    if (!self.span_active) return false;

    // Check if flag was cleared by a previous $2002 read
    // Race condition (read at exact set cycle) DOES clear the flag for future reads,
    // but suppresses NMI (handled in shouldNmiEdge)
    if (self.last_status_read_cycle >= self.last_set_cycle) {
        return false; // Cleared by $2002 read (including race condition read)
    }

    // Flag is active (set and not yet cleared by any read)
    return true;
}
```

## The Problem I Keep Making

**I keep changing the SAME comparison operator without:**
1. Writing down what the CURRENT state is
2. Running tests to verify the change
3. Understanding WHY tests fail before making next change

## What I NEED To Do

1. **STOP changing code**
2. **Document EXACTLY what tests are failing**
3. **Understand WHY they're failing**
4. **Make ONE deliberate change**
5. **Verify that specific change works**

## Current Test Status

Last known: 930/968 tests passing, 17 failed

**I DON'T KNOW:**
- Which specific tests are failing
- What they expect vs what they get
- Whether the `>=` change made things better or worse

## Next Steps (MUST DO IN ORDER)

1. ✅ Write this documentation
2. ⏳ Check git diff to see EXACTLY what changed from original
3. ⏳ Run tests and capture EXACT failure messages
4. ⏳ Pick ONE failing test to analyze
5. ⏳ Trace through the logic for that ONE test
6. ⏳ Make ONE targeted fix
7. ⏳ Verify that fix works
8. ⏳ Repeat for remaining failures

## Questions I Need To Answer

1. What was the ORIGINAL implementation before I started?
2. What is the CURRENT implementation?
3. What EXACTLY do the failing tests expect?
4. What EXACTLY is the hardware behavior per nesdev.org?
5. Does `>=` or `>` match the hardware behavior?
