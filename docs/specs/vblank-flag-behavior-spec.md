# VBlank Flag Behavior - Complete Specification

**Date:** 2025-10-12
**Purpose:** Define EXACT deterministic behavior for VBlank flag queries
**Source:** nesdev.org/wiki/PPU_frame_timing, nesdev.org/wiki/NMI

## Hardware Behavior (nesdev.org)

### Normal Case
**Timeline:**
1. Scanline 241 dot 1: VBlank flag sets
2. Some cycles later: CPU reads $2002
3. Read returns: VBlank bit = 1 (set)
4. Side effect: VBlank flag clears
5. Next $2002 read: VBlank bit = 0 (cleared)

### Race Condition Case
**Timeline:**
1. Scanline 241 dot 1: VBlank flag sets
2. **SAME CYCLE**: CPU reads $2002
3. Read returns: VBlank bit = 1 (set)
4. Side effect: VBlank flag clears
5. **Special:** NMI is SUPPRESSED (doesn't fire)
6. Next $2002 read: VBlank bit = 0 (cleared)

**Key Quote (nesdev.org/wiki/PPU_frame_timing):**
> "Reading on the same PPU clock or one later reads it as set, clears it, and suppresses the NMI for that frame."

## State Model

### State Variables
```zig
span_active: bool          // VBlank span active (241.1 to 261.1)
last_set_cycle: u64        // When VBlank was set
last_status_read_cycle: u64// When $2002 was last read
```

### Query Function: `isReadableFlagSet(current_cycle: u64) -> bool`

**Purpose:** Return what value $2002 bit 7 should have if read at `current_cycle`

**Invariants:**
1. If span not active → return FALSE
2. If any $2002 read has occurred since VBlank set → return FALSE
3. Otherwise → return TRUE

## Truth Table

| Scenario | span_active | last_set_cycle | last_status_read_cycle | Query Action | Result | Notes |
|----------|-------------|----------------|------------------------|--------------|--------|-------|
| Before VBlank | FALSE | 0 | 0 | query() | FALSE | Span not started |
| VBlank just set | TRUE | 100 | 0 | query(150) | TRUE | No reads yet |
| Normal read | TRUE | 100 | 0 | **read(150)** | **TRUE** | First read sees flag |
| After normal read | TRUE | 100 | 150 | query(151) | FALSE | Flag cleared |
| Race condition | TRUE | 100 | 0 | **read(100)** | **TRUE** | Read at exact set cycle |
| After race read | TRUE | 100 | 100 | query(101) | FALSE | Flag cleared by race read |
| Multiple reads | TRUE | 100 | 150 | query(200) | FALSE | Stays cleared |

## Implementation Logic

```zig
pub fn isReadableFlagSet(self: *const VBlankLedger, current_cycle: u64) bool {
    _ = current_cycle; // Not used in determination

    // 1. Span not active?
    if (!self.span_active) return false;

    // 2. Has any $2002 read occurred since VBlank set?
    // NOTE: Using >= because race condition read (at exact set cycle) ALSO clears
    if (self.last_status_read_cycle >= self.last_set_cycle) {
        return false;
    }

    // 3. Flag is set and no reads have occurred yet
    return true;
}
```

## Critical Insight

**The race condition does NOT prevent flag clearing!**

The race condition affects **NMI suppression**, not flag clearing:
- Normal read: Flag clears, NMI fires (if enabled)
- Race read: Flag clears, NMI SUPPRESSED

Both cases clear the flag. The difference is in `shouldNmiEdge()`, not `isReadableFlagSet()`.

## Test Scenarios

### Test 1: Normal Read
```zig
ledger.recordVBlankSet(100, false);  // Set at cycle 100
assert(ledger.isReadableFlagSet(110) == true);   // Before read
ledger.recordStatusRead(110);                     // Read at 110
assert(ledger.isReadableFlagSet(120) == false);  // After read
```

### Test 2: Race Condition Read
```zig
ledger.recordVBlankSet(100, false);  // Set at cycle 100
assert(ledger.isReadableFlagSet(100) == true);   // At exact cycle (before internal read)
ledger.recordStatusRead(100);                     // Read at exact cycle
assert(ledger.isReadableFlagSet(101) == false);  // After race read - CLEARED
```

### Test 3: Multiple Reads
```zig
ledger.recordVBlankSet(100, false);
ledger.recordStatusRead(110);    // First read
assert(ledger.isReadableFlagSet(120) == false);
ledger.recordStatusRead(130);    // Second read
assert(ledger.isReadableFlagSet(140) == false); // Still false
```

## Common Misunderstandings

### WRONG: "Race condition read doesn't clear flag"
- **Source:** Misreading nesdev.org "flag will not be cleared"
- **Context:** That quote refers to a DIFFERENT race condition scenario
- **Reality:** All $2002 reads clear the flag, including race reads

### WRONG: "Need to use current_cycle in comparison"
- **Source:** Trying to detect "reading at exact set cycle"
- **Reality:** That's already handled by the read/record sequence
- **Correct:** Only compare timestamps against each other

### CORRECT: "Race condition suppresses NMI, not clearing"
- The special behavior is in NMI generation logic
- Flag clearing works identically for all reads
- Use `>=` not `>` because read at exact cycle (equality) also clears

## References

- nesdev.org/wiki/PPU_frame_timing
- nesdev.org/wiki/NMI
- Investigation: `docs/sessions/2025-10-12-vblank-nmi-investigation.md`
