# NES VBlank Race Condition - Implementation Guide

## Critical Timing Sequence

### What Happens at Scanline 241, Dot 1

The PPU hardware performs these operations:

```
Scanline 240, Dot 341 (last pixel of visible frame):
  - Frame rendering complete
  - Next scanline will be 241 (VBlank scanline)

Scanline 241, Dot 0:
  - Pre-VBlank state
  - If CPU reads $2002 here: sees VBlank = 0 ✓

Scanline 241, Dot 1 [CRITICAL MOMENT]:
  1. PPU sets internal VBlank flag to 1
  2. PPU asserts /NMI signal LOW (if NMI_output enabled in $2000 bit 7)
  3. [If CPU reads $2002 at this moment: race condition!]
     - Depending on sub-cycle alignment, reads either 0 or 1
     - Most likely reads 0 (missed the set)
  4. PPU may clear NMI signal if $2002 was read this cycle
     - $2002 read sets internal "clear vblank flag" signal
     - This pulls /NMI back up (active low logic)
     - CPU may not see the edge

Scanline 241, Dot 2:
  - If CPU reads $2002 now: sees VBlank = 1
  - But NMI still suppressed (too close to set event)

Scanline 241, Dot 3+:
  - If CPU reads $2002 now: sees VBlank = 1
  - NMI no longer suppressed (can fire normally)
```

---

## Implementation Checklist

### 1. VBlank Flag Setting

```zig
// In PPU Logic, when executing scanline 241 dot 1:

pub fn tick(ppu: *PpuState) void {
    // ... rendering logic ...

    if (ppu.scanline == 241 and ppu.dot == 1) {
        // CRITICAL: VBlank flag set here
        ppu.vblank_flag = true;

        // CRITICAL: NMI signal generation
        // (happens at same moment as flag set)
        if (ppu.nmi_output) {  // PPUCTRL bit 7
            // Signal CPU to enter NMI
            // This is "pulling /NMI low" in hardware
        }
    }
}
```

### 2. $2002 Read Behavior

```zig
// In PPU Logic, when CPU reads $2002:

pub fn readPpuStatus(ppu: *PpuState) u8 {
    // Step 1: Create return value with current flag states
    var status: u8 = 0;

    // Bit 7: VBlank flag (current state)
    status |= if (ppu.vblank_flag) @as(u8, 0x80) else 0;

    // Bit 6: Sprite 0 hit flag (current state)
    status |= if (ppu.sprite0_hit_flag) @as(u8, 0x40) else 0;

    // Bit 5: Sprite overflow flag (current state)
    status |= if (ppu.sprite_overflow) @as(u8, 0x20) else 0;

    // Step 2: Return the value to CPU
    // (CPU reads this from data bus)

    // Step 3: Set clear flag (happens after read)
    ppu.clear_vblank_on_read = true;
    ppu.clear_sprite0_on_read = true;

    return status;
}

// On the NEXT PPU cycle, or at appropriate timing:
// ppu.vblank_flag = false;
// ppu.sprite0_hit_flag = false;
```

### 3. The Race Condition Handling

```zig
// The critical race condition:
// What if CPU reads $2002 on the SAME cycle VBlank is being set?

// This depends on CPU-PPU alignment state!
// There's no universal answer—you must consider which alignment state

// SIMPLE IMPLEMENTATION (one alignment state):
// Assumption: Reads always see the OLD value before the new value is latched

if (ppu.scanline == 241 and ppu.dot == 1) {
    // VBlank is being set THIS CYCLE

    if (cpu_is_reading_2002_this_cycle) {
        // CPU reads BEFORE PPU latches the new flag
        // CPU sees VBlank = false (old value)
        // But clear flag is set, so next cycle VBlank = false anyway
        ppu.clear_vblank_on_read = true;
        ppu.nmi_suppressed_this_frame = true;
    } else {
        // CPU not reading this cycle
        // Set the flag normally
        ppu.vblank_flag = true;
    }
}
```

### 4. NMI Suppression Window

The NMI is suppressed when:
- A $2002 read occurs 1 cycle BEFORE VBlank is set (dot 0)
- A $2002 read occurs the SAME cycle VBlank is set (dot 1)
- A $2002 read occurs 1 cycle AFTER VBlank is set (dot 2)

```zig
// Tracking suppression:
pub const NmiSuppression = struct {
    suppressed: bool = false,
    suppression_cycle_count: u8 = 0,
};

// When $2002 is read:
if (ppu.scanline == 241 and ppu.dot >= 0 and ppu.dot <= 2) {
    ppu.nmi_suppression.suppressed = true;
    ppu.nmi_suppression.suppression_cycle_count = 3; // 3 cycle window
}

// Before each cycle:
if (ppu.nmi_suppression.suppression_cycle_count > 0) {
    ppu.nmi_suppression.suppression_cycle_count -= 1;
}

// When generating NMI:
if (ppu.vblank_flag and ppu.nmi_output and !ppu.nmi_suppression.suppressed) {
    bus.assertNmi();
}
```

### 5. Flag Clearing Timing

```zig
// The $2002 read clears the flag, but this happens AFTER returning the value

// When $2002 is read:
if (cpu.addressing_mode == MEMORY_READ and cpu.address == 0x2002) {
    // Current cycle: Return value with current flags
    // (this happens first)

    // Set a "clear on read" flag (happens second)
    ppu.clear_vblank_on_read = true;
    ppu.clear_sprite0_on_read = true;
}

// Later (next dot or specific timing):
// This clears the flags so future reads see them as false
if (ppu.clear_vblank_on_read) {
    ppu.vblank_flag = false;
    ppu.clear_vblank_on_read = false;
}
```

---

## Critical Race Conditions to Test

### Test Case 1: Read at dot 0 (before VBlank set)

```
Cycle: Read $2002 at scanline 241 dot 0
Expected: $2002 = 0x?? (bit 7 = 0)
Expected: NMI suppressed
Expected: No frame skip
```

### Test Case 2: Read at dot 1 (same cycle as VBlank set)

```
Cycle: Read $2002 at scanline 241 dot 1
Expected: $2002 = 0x?? (bit 7 = 0, due to race)
Expected: NMI suppressed for entire frame
Expected: Game will miss VBlank and stutter
```

### Test Case 3: Read at dot 2 (1 after VBlank set)

```
Cycle: Read $2002 at scanline 241 dot 2
Expected: $2002 = 0x8? (bit 7 = 1, flag was set)
Expected: Flag cleared by this read
Expected: NMI still suppressed (too close)
```

### Test Case 4: Read at dot 3+ (2+ after VBlank set)

```
Cycle: Read $2002 at scanline 241 dot 3+
Expected: $2002 = 0x8? (bit 7 = 1, flag was set)
Expected: Flag cleared by this read
Expected: NMI can fire normally
```

---

## Alignment State Complexity

The behavior described above assumes **one specific alignment state**. For completeness:

```zig
// NES can power up in one of 4 alignment states (NTSC)
pub const AlignmentState = enum {
    STATE_0,  // Most "normal" behavior
    STATE_1,  // Changes flag visibility timing
    STATE_2,  // Further timing shift
    STATE_3,  // Maximum deviation from STATE_0
};

// Current implementation should handle:
pub const ppu_alignment_state: AlignmentState = .STATE_0;

// Future work: Test with all 4 states and ensure consistent behavior
```

The alignment state affects:
- Exact sub-cycle when CPU reads occur within a PPU dot
- Whether a read on dot 1 sees flag as 0 or 1
- Exact NMI suppression timing
- Frame rate consistency

**For RAMBO:** Current tests validate one alignment state. Full compliance would require testing all 4 states, which is likely overkill unless you're building a cycle-accurate forensics tool.

---

## Validation Strategy

### Using AccuracyCoin

```bash
# Build and run AccuracyCoin
zig build run -- path/to/AccuracyCoin.nes

# Look for these test results:
# - PPUSTATUS VBlank flag timing
# - VBlank/NMI interaction
# - Flag clearing behavior

# Expected: All VBlank-related tests pass
```

### Using vbl_nmi_timing ROMs

```bash
# Test each ROM in sequence:
# 1. 01-vbl_basics.nes
# 2. 02-vbl_set_timing.nes
# 3. 03-vbl_clear_timing.nes
# 4. 04-nmi_on_vbl.nes
# 5. 05-nmi_suppression.nes
# 6. 06-nmi_edge_cases.nes
# 7. 07-timing_quirks.nes

# Each ROM exits with beep count = pass, or displays failure code

for rom in vbl_nmi_timing/*.nes; do
    echo "Testing: $rom"
    zig build run -- "$rom" --timeout 30
done
```

---

## Common Implementation Mistakes

### ❌ Mistake 1: Atomic Instruction Execution

```zig
// WRONG: Processing entire instruction at once
pub fn executeBIT_Absolute(cpu: *Cpu, bus: *Bus) void {
    let addr = cpu.read16(cpu.pc + 1);
    let value = bus.read(addr);  // <-- All happens in one function call
    // ...
}

// RIGHT: Cycle-by-cycle execution
// Cycle 1: Opcode fetch
// Cycle 2: Low byte fetch
// Cycle 3: High byte fetch
// Cycle 4: Memory read <-- This is when PPU changes matter!
```

**Why it matters:** If PPU sets VBlank during instruction execution, you must respect the exact cycle when the memory read happens.

### ❌ Mistake 2: Clearing Flag Immediately

```zig
// WRONG: Clear flag in same operation as read
pub fn readPpuStatus(ppu: *PpuState) u8 {
    let result = if (ppu.vblank_flag) 0x80 else 0;
    ppu.vblank_flag = false;  // <-- Wrong! Clears immediately
    return result;
}

// RIGHT: Set a clear flag that takes effect later
pub fn readPpuStatus(ppu: *PpuState) u8 {
    let result = if (ppu.vblank_flag) 0x80 else 0;
    ppu.clear_vblank_on_read = true;  // <-- Flag, will clear later
    return result;
}
```

**Why it matters:** The flag clearing happens AFTER the CPU reads the value. If you clear it immediately, you're violating hardware behavior.

### ❌ Mistake 3: Not Handling Sub-Cycle Alignment

```zig
// OVERSIMPLIFIED: Doesn't account for alignment state
if (ppu.scanline == 241 and ppu.dot == 1) {
    ppu.vblank_flag = true;  // <-- Always visible to CPU reads
}

// BETTER: Account for CPU-PPU phase relationship
if (ppu.scanline == 241 and ppu.dot == 1) {
    // Depending on alignment, CPU may or may not see this set
    if (alignmentState == .STATE_0) {
        // CPU read sees the old value (0)
        ppu.vblank_flag = false;  // Stays clear until next cycle
    } else {
        // Other states have different behavior
    }
}
```

---

## Testing Progression

1. **Baseline:** Can your emulator run AccuracyCoin without crashing?
2. **VBlank Detection:** Do games reliably detect VBlank using NMI?
3. **Edge Cases:** Do you pass all vbl_nmi_timing tests?
4. **Alignment States:** Do you handle all 4 NTSC alignment states?

Most game compatibility only requires tests 1-3. Test 4 is for advanced accuracy.

---

## References for Implementation

- **nesdev.org PPU frame timing:** Exact dot-by-dot timing (MOST IMPORTANT)
- **AccuracyCoin GitHub:** Look at test ROM source for validation patterns
- **vbl_nmi_timing source:** See how tests check flag state at precise cycles
- **RAMBO existing tests:** Check `tests/integration/` for current VBlank tests

---

## RAMBO-Specific Notes

Check these files in your codebase:

- `/src/ppu/State.zig` - VBlank flag state
- `/src/ppu/Logic.zig` - VBlank flag setting and clearing
- `/src/emulation/State.zig` - Master clock and scanline tracking
- `/tests/integration/` - VBlank and NMI tests

Current status (as of 2025-10-20):
- ✅ VBlank flag sets at scanline 241 dot 1
- ✅ NMI fires on VBlank flag set
- ✅ $2002 read clears flag
- ❓ Sub-cycle timing edge cases (may need refinement)
