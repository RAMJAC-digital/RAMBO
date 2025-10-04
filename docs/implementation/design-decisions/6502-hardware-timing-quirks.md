# 6502 Hardware Timing Quirks and Implementation

**Date:** 2025-10-02
**Status:** Active
**Component:** CPU Core
**Decision Type:** Critical Hardware Accuracy

## Overview

The 6502 CPU has specific hardware behaviors and "bugs" that are ESSENTIAL to emulate correctly. Games and AccuracyCoin tests rely on these exact behaviors. This document defines the hardware-accurate timing for our emulator.

## Critical Principle

**The 6502 does NOT separate "addressing" from "execution"**. Every cycle has a specific bus operation, and what looks like "addressing cycles" often performs partial execution.

## Addressing Mode Timing (Hardware Accurate)

### Immediate Mode - 2 Cycles
```
Cycle 1: Fetch opcode, PC++
Cycle 2: Fetch operand, PC++, EXECUTE
```
**Key**: Operand fetch IS the execution cycle. No separate execute step.

### Zero Page - 3 Cycles
```
Cycle 1: Fetch opcode, PC++
Cycle 2: Fetch ZP address, PC++
Cycle 3: Read from ZP address, EXECUTE
```

### Zero Page,X - 4 Cycles
```
Cycle 1: Fetch opcode, PC++
Cycle 2: Fetch ZP address, PC++
Cycle 3: Read from ZP (dummy), add X to address (wraps in page 0)
Cycle 4: Read from ZP+X, EXECUTE
```
**Key**: Cycle 3 reads from wrong address while adding index!

### Absolute - 4 Cycles
```
Cycle 1: Fetch opcode, PC++
Cycle 2: Fetch address low, PC++
Cycle 3: Fetch address high, PC++
Cycle 4: Read from address, EXECUTE
```

### Absolute,X (READ like LDA) - 4 or 5 Cycles
```
Cycle 1: Fetch opcode, PC++
Cycle 2: Fetch address low, PC++
Cycle 3: Fetch address high, PC++
Cycle 4: Read from (high << 8) | ((low + X) & 0xFF), add X to address
        - If no page cross: This read IS the correct data, EXECUTE, DONE (4 cycles)
        - If page cross: This is dummy read, wrong address
Cycle 5: (Only if page crossed) Read from correct address, EXECUTE
```

**CRITICAL HARDWARE QUIRK**: The dummy read address is `(base_high << 8) | ((base_low + index) & 0xFF)` - the high byte is NOT incremented yet!

### Absolute,X (WRITE like STA) - ALWAYS 5 Cycles
```
Cycle 1: Fetch opcode, PC++
Cycle 2: Fetch address low, PC++
Cycle 3: Fetch address high, PC++
Cycle 4: Read from (high << 8) | ((low + X) & 0xFF) - DUMMY READ ALWAYS
Cycle 5: Write to correct address
```

**Key**: Write instructions ALWAYS take the extra cycle. The dummy read happens even without page crossing.

### Absolute,X (RMW like INC) - ALWAYS 7 Cycles
```
Cycle 1: Fetch opcode, PC++
Cycle 2: Fetch address low, PC++
Cycle 3: Fetch address high, PC++
Cycle 4: Read from wrong address (dummy)
Cycle 5: Read from correct address (get original value)
Cycle 6: Write original value back (DUMMY WRITE)
Cycle 7: Write modified value
```

### (Indirect,X) - 6 Cycles
```
Cycle 1: Fetch opcode, PC++
Cycle 2: Fetch ZP pointer, PC++
Cycle 3: Read from ZP (dummy), add X to pointer
Cycle 4: Read target address low from (pointer + X) & 0xFF
Cycle 5: Read target address high from (pointer + X + 1) & 0xFF
Cycle 6: Read from target address, EXECUTE
```

**Key**: NO dummy read at target address. Indexed BEFORE indirection.

### (Indirect),Y (READ) - 5 or 6 Cycles
```
Cycle 1: Fetch opcode, PC++
Cycle 2: Fetch ZP pointer, PC++
Cycle 3: Read target address low from ZP pointer
Cycle 4: Read target address high from ZP pointer + 1
Cycle 5: Read from (high << 8) | ((low + Y) & 0xFF)
        - If no page cross: This IS the data, EXECUTE, DONE (5 cycles)
        - If page cross: Dummy read
Cycle 6: (Only if page crossed) Read from correct address, EXECUTE
```

**Key**: Indexed AFTER indirection. Has dummy read like Absolute,Y.

### (Indirect),Y (WRITE) - ALWAYS 6 Cycles
```
Cycle 1: Fetch opcode, PC++
Cycle 2: Fetch ZP pointer, PC++
Cycle 3: Read target address low from ZP pointer
Cycle 4: Read target address high from ZP pointer + 1
Cycle 5: Read from (high << 8) | ((low + Y) & 0xFF) - DUMMY READ ALWAYS
Cycle 6: Write to correct address
```

## Read-Modify-Write (RMW) Quirk

**CRITICAL**: All RMW instructions write the ORIGINAL value back to memory before writing the modified value.

```
Example: INC $10
Cycle 1: Fetch opcode
Cycle 2: Fetch address $10
Cycle 3: Read from $10 (get value, e.g. $42)
Cycle 4: Write $42 to $10 (DUMMY WRITE - write original!)
Cycle 5: Write $43 to $10 (actual increment)
```

**Why this matters**:
- Memory-mapped I/O sees TWO writes
- PPU register $2006 gets written twice
- This is how AccuracyCoin detects incorrect emulation

## Branch Timing - 2, 3, or 4 Cycles

```
Cycle 1: Fetch opcode, PC++
Cycle 2: Fetch offset, PC++
        - If branch not taken: DONE (2 cycles)
        - If branch taken: Add offset to PC
          - If no page cross: DONE (3 cycles)
          - If page cross: Continue to cycle 3
Cycle 3: Fix PC high byte (4 cycles total)
```

**Key**: Dummy read at incorrect PC during offset calculation.

## Our Current Architecture Issues

### Problem 1: Separation of Addressing and Execution

Our current design:
```zig
// Cycle 1: fetch_opcode
// Cycle 2-N: fetch_operand_low (run addressing microsteps)
// Cycle N+1: execute
```

**Issue**: This adds an extra cycle because we always run execute separately.

**Real Hardware**:
- Immediate mode: operand fetch IS execution (2 cycles, not 3)
- Absolute,X no page cross: dummy read IS the actual read (4 cycles, not 5)

### Problem 2: Page Cross Handling

Current: Addressing mode sets `page_crossed` flag, execute checks it.

**Issue**: For reads with no page cross, the dummy read cycle IS the execution. We can't add another cycle.

**Real Hardware**: Cycle 4 of LDA $nnnn,X does BOTH:
1. Read from (potentially wrong) address
2. If address was right (no page cross), that's the data - instruction complete
3. If address was wrong (page cross), discard and continue

### Problem 3: Dummy Reads Not Happening

Current: Addressing modes don't always perform the hardware-accurate dummy reads.

**Issue**: AccuracyCoin tests check for side effects from dummy reads (e.g., reading $2002 clears vblank flag).

## Required Architecture Changes

### Solution 1: Eliminate Separate Execute State for Some Modes

**Immediate Mode**:
```zig
// Cycle 1: fetch opcode
// Cycle 2: COMBINED fetch operand AND execute, return complete=true
```

**Implementation**: Immediate mode execute function does the operand fetch itself.

### Solution 2: Make Addressing Microsteps Conditionally Complete

```zig
pub fn calcAbsoluteX(cpu: *Cpu, bus: *Bus) bool {
    const base = (@as(u16, cpu.operand_high) << 8) | @as(u16, cpu.operand_low);
    cpu.effective_address = base +% cpu.x;
    cpu.page_crossed = (base & 0xFF00) != (cpu.effective_address & 0xFF00);

    // Dummy read at wrong address
    const dummy_addr = (base & 0xFF00) | (cpu.effective_address & 0x00FF);
    const dummy_value = bus.read(dummy_addr);

    // FOR READ INSTRUCTIONS: if no page cross, we just read the correct value!
    // The instruction must check cpu.page_crossed and use dummy_value if !page_crossed
    cpu.temp_value = dummy_value;

    // Return true if no page cross AND this is a read instruction
    // But we don't know the instruction type here...
}
```

**Problem**: Microsteps don't know if the instruction is read/write/RMW.

### Solution 3: Instruction-Aware Addressing

Create different microstep sequences for read vs write vs RMW:
- `absolute_x_read_steps` - can complete in 4 cycles
- `absolute_x_write_steps` - always 5 cycles
- `absolute_x_rmw_steps` - always 7 cycles

Already started this in `addressing.zig`!

## Implementation Strategy

### Phase 1: Fix Immediate Mode (DONE)
- Execute function fetches operand directly
- No addressing microsteps
- ✅ 2 cycles for LDA #$nn

### Phase 2: Fix Absolute,X Read (IN PROGRESS)
- Microstep 3 (calcAbsoluteX) performs dummy read
- If no page cross, store value in temp_value
- Execute function checks page_crossed:
  - If false: use temp_value (total 4 cycles)
  - If true: read from effective_address (total 5 cycles)

### Phase 3: Ensure Dummy Reads Update Bus
- All dummy reads must call `bus.read()`
- This ensures open bus is updated
- Side effects (like PPU register reads) occur

### Phase 4: Implement RMW Dummy Writes
- Create RMW microstep sequence:
  1. Read address calculation
  2. Read value
  3. Write original value (DUMMY)
  4. Write modified value
- Separate RMW steps for each addressing mode

### Phase 5: Branch Timing
- 2 cycles: branch not taken
- 3 cycles: branch taken, no page cross
- 4 cycles: branch taken, page cross
- Dummy read during offset calculation

## Testing Requirements

Each addressing mode must have tests for:
1. **Correct cycle count** (from AccuracyCoin)
2. **Dummy read occurs** (verify bus.read() called at dummy address)
3. **Page cross detection** (when applicable)
4. **RMW dummy write** (for INC, DEC, ASL, LSR, ROL, ROR)
5. **Open bus updates** (every read updates bus)

## References

- AccuracyCoin: `/home/colin/Development/RAMBO/AccuracyCoin/`
- Test Requirements: `/home/colin/Development/RAMBO/docs/05-testing/accuracycoin-cpu-requirements.md`
- CPU Design Doc: `/home/colin/Development/RAMBO/docs/06-implementation-notes/design-decisions/cpu-execution-architecture.md`
- NESDev Wiki: https://www.nesdev.org/wiki/CPU_timing

## Next Steps

1. ✅ Document hardware timing (this file)
2. Fix absolute,X to complete in 4 cycles (no page cross)
3. Add tests verifying dummy read addresses
4. Implement RMW dummy write cycles
5. Add comprehensive timing tests for all modes
6. Validate against AccuracyCoin tests
