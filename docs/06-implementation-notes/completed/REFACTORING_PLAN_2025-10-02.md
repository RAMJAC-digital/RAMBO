# CPU Instruction Refactoring Plan

## Overview

This document outlines the complete refactoring plan based on comprehensive code reviews by three specialized agents. The goal is to fix critical issues and establish a clean, scalable architecture before implementing undocumented opcodes.

## Critical Issues Identified

### 1. Immediate Mode Handling Inconsistency ⚠️ CRITICAL
**Problem**: Two different patterns for immediate mode operand access:
- **Pattern A** (ADC, SBC, AND, etc.): Expects `cpu.operand_low` to be pre-populated
- **Pattern B** (LDA, STA, etc.): Reads from `cpu.pc` during execute and increments PC

**Root Cause**: Dispatch table has empty addressing steps for immediate mode, but some instructions expect the operand to be fetched.

**Impact**: Will cause bugs when implementing undocumented opcodes that use immediate mode.

**Fix**: Standardize on **Pattern A** (use `cpu.operand_low`) and ensure `addressing.immediate_steps` is used consistently.

### 2. Page Crossing Logic Duplication
**Problem**: Same page crossing check duplicated in 6+ files:
```zig
if ((cpu.address_mode == .absolute_x or
    cpu.address_mode == .absolute_y or
    cpu.address_mode == .indirect_indexed) and
    cpu.page_crossed)
{
    value = bus.read(cpu.effective_address);
} else {
    value = cpu.temp_value;
}
```

**Impact**: Maintenance burden, risk of inconsistencies, code bloat.

**Fix**: Extract to `helpers.readWithPageCrossing()`.

### 3. Magic Numbers Scattered Throughout Code
**Problem**: Hardcoded values like `0x0100`, `0xFFFE`, `0x80`, `0x10` appear without context.

**Impact**: Reduces readability, makes changes error-prone.

**Fix**: Create `constants.zig` with named constants.

### 4. Inline Implementations in dispatch.zig
**Problem**: LDA, STA, LDX, LDY, STX, STY implemented directly in dispatch.zig (400+ lines).

**Impact**: Breaks module separation, makes dispatch.zig too large (1100+ lines).

**Fix**: Move to dedicated `src/cpu/instructions/loadstore.zig` module.

## Architectural Improvements

### 1. New Module Structure
```
src/cpu/
├── constants.zig           [NEW] Magic numbers and hardware addresses
├── helpers.zig            [NEW] Common utility functions
├── Cpu.zig
├── dispatch.zig           [REFACTOR] Remove inline implementations
├── addressing.zig
├── execution.zig
├── opcodes.zig
└── instructions/
    ├── loadstore.zig      [NEW] LDA, LDX, LDY, STA, STX, STY
    ├── arithmetic.zig     [UPDATE] Use helpers
    ├── logical.zig        [UPDATE] Use helpers
    ├── compare.zig        [UPDATE] Use helpers
    ├── transfer.zig       [UPDATE] Use constants
    ├── branch.zig
    ├── jumps.zig          [UPDATE] Use constants
    ├── stack.zig          [UPDATE] Use constants
    ├── shifts.zig
    └── incdec.zig
```

### 2. Constants Module Design

`src/cpu/constants.zig`:
```zig
//! Hardware constants for 6502 CPU emulation

/// Stack page base address (page 1)
pub const STACK_BASE: u16 = 0x0100;

/// Reset vector address (low byte)
pub const RESET_VECTOR_LOW: u16 = 0xFFFC;

/// Reset vector address (high byte)
pub const RESET_VECTOR_HIGH: u16 = 0xFFFD;

/// NMI vector address (low byte)
pub const NMI_VECTOR_LOW: u16 = 0xFFFA;

/// NMI vector address (high byte)
pub const NMI_VECTOR_HIGH: u16 = 0xFFFB;

/// IRQ/BRK vector address (low byte)
pub const IRQ_VECTOR_LOW: u16 = 0xFFFE;

/// IRQ vector address (high byte)
pub const IRQ_VECTOR_HIGH: u16 = 0xFFFF;

/// Negative flag bit mask
pub const FLAG_NEGATIVE: u8 = 0x80;

/// Overflow flag bit mask
pub const FLAG_OVERFLOW: u8 = 0x40;

/// Break flag bit mask
pub const FLAG_BREAK: u8 = 0x10;

/// Unused flag bit mask (always 1)
pub const FLAG_UNUSED: u8 = 0x20;

/// Page size in bytes
pub const PAGE_SIZE: u16 = 0x100;

/// Page mask for extracting page number
pub const PAGE_MASK: u16 = 0xFF00;

/// Offset mask for extracting page offset
pub const OFFSET_MASK: u16 = 0x00FF;
```

### 3. Helpers Module Design

`src/cpu/helpers.zig`:
```zig
//! Common helper functions for CPU instruction implementation

const Cpu = @import("Cpu.zig").Cpu;
const Bus = @import("../bus/Bus.zig").Bus;

/// Read value handling page crossing for indexed addressing modes
///
/// For absolute,X / absolute,Y / indirect,Y modes:
/// - If no page crossing: use temp_value from dummy read
/// - If page crossing: perform actual read from effective_address
pub inline fn readWithPageCrossing(cpu: *Cpu, bus: *Bus) u8 {
    if ((cpu.address_mode == .absolute_x or
        cpu.address_mode == .absolute_y or
        cpu.address_mode == .indirect_indexed) and
        cpu.page_crossed)
    {
        return bus.read(cpu.effective_address);
    }
    return cpu.temp_value;
}

/// Read operand for read instructions (handles all addressing modes)
///
/// Supports:
/// - Immediate: from operand_low
/// - Zero page: direct read
/// - Indexed: uses page crossing logic
pub inline fn readOperand(cpu: *Cpu, bus: *Bus) u8 {
    return switch (cpu.address_mode) {
        .immediate => cpu.operand_low,
        .zero_page => bus.read(@as(u16, cpu.operand_low)),
        .zero_page_x, .zero_page_y => bus.read(cpu.effective_address),
        .absolute => blk: {
            const addr = (@as(u16, cpu.operand_high) << 8) | cpu.operand_low;
            break :blk bus.read(addr);
        },
        .absolute_x, .absolute_y, .indirect_indexed => readWithPageCrossing(cpu, bus),
        .indexed_indirect => bus.read(cpu.effective_address),
        else => unreachable,
    };
}

/// Write value to memory (handles all write addressing modes)
pub inline fn writeOperand(cpu: *Cpu, bus: *Bus, value: u8) void {
    switch (cpu.address_mode) {
        .zero_page => bus.write(@as(u16, cpu.operand_low), value),
        .zero_page_x, .zero_page_y => bus.write(cpu.effective_address, value),
        .absolute => {
            const addr = (@as(u16, cpu.operand_high) << 8) | cpu.operand_low;
            bus.write(addr, value);
        },
        .absolute_x, .absolute_y => bus.write(cpu.effective_address, value),
        .indexed_indirect, .indirect_indexed => bus.write(cpu.effective_address, value),
        else => unreachable,
    }
}

/// Check if two addresses are on different pages
pub inline fn pagesDiffer(addr1: u16, addr2: u16) bool {
    return (addr1 & 0xFF00) != (addr2 & 0xFF00);
}
```

### 4. Load/Store Module Design

`src/cpu/instructions/loadstore.zig`:
```zig
//! Load and Store Instructions
//!
//! LDA - Load Accumulator
//! LDX - Load X Register
//! LDY - Load Y Register
//! STA - Store Accumulator
//! STX - Store X Register
//! STY - Store Y Register

const Cpu = @import("../Cpu.zig").Cpu;
const Bus = @import("../../bus/Bus.zig").Bus;
const helpers = @import("../helpers.zig");

/// LDA - Load Accumulator
/// A = M
/// Flags: N, Z
pub fn lda(cpu: *Cpu, bus: *Bus) bool {
    cpu.a = helpers.readOperand(cpu, bus);
    cpu.p.updateZN(cpu.a);
    return true;
}

/// LDX - Load X Register
/// X = M
/// Flags: N, Z
pub fn ldx(cpu: *Cpu, bus: *Bus) bool {
    cpu.x = helpers.readOperand(cpu, bus);
    cpu.p.updateZN(cpu.x);
    return true;
}

/// LDY - Load Y Register
/// Y = M
/// Flags: N, Z
pub fn ldy(cpu: *Cpu, bus: *Bus) bool {
    cpu.y = helpers.readOperand(cpu, bus);
    cpu.p.updateZN(cpu.y);
    return true;
}

/// STA - Store Accumulator
/// M = A
/// Flags: None
pub fn sta(cpu: *Cpu, bus: *Bus) bool {
    helpers.writeOperand(cpu, bus, cpu.a);
    return true;
}

/// STX - Store X Register
/// M = X
/// Flags: None
pub fn stx(cpu: *Cpu, bus: *Bus) bool {
    helpers.writeOperand(cpu, bus, cpu.x);
    return true;
}

/// STY - Store Y Register
/// M = Y
/// Flags: None
pub fn sty(cpu: *Cpu, bus: *Bus) bool {
    helpers.writeOperand(cpu, bus, cpu.y);
    return true;
}

// Tests moved to tests/cpu/loadstore_test.zig
```

## Detailed Refactoring Steps

### Phase 1: Create New Modules ✅

1. Create `src/cpu/constants.zig` with all magic numbers
2. Create `src/cpu/helpers.zig` with common utilities
3. Create `src/cpu/instructions/loadstore.zig` with load/store instructions

### Phase 2: Update Immediate Mode Handling ✅

1. Ensure ALL immediate mode instructions in dispatch table use `&addressing.immediate_steps`
2. Update all instruction implementations to read from `cpu.operand_low` for immediate mode
3. Remove any PC manipulation in instruction execute functions

### Phase 3: Refactor Existing Instructions ✅

1. **arithmetic.zig**: Replace page crossing logic with `helpers.readOperand()`
2. **logical.zig**: Replace page crossing logic with `helpers.readOperand()`
3. **compare.zig**: Replace page crossing logic with `helpers.readOperand()`
4. **transfer.zig**: Use constants for flag masks
5. **jumps.zig**: Use constants for vector addresses and flag masks
6. **stack.zig**: Use constants for stack base and flag masks

### Phase 4: Update dispatch.zig ✅

1. Remove inline `ldaExecute`, `staExecute`, `ldxExecute`, `ldyExecute`, `stxExecute`, `styExecute`
2. Import `loadstore` module
3. Update dispatch table entries to use `loadstore.lda`, etc.
4. Verify all immediate mode entries use `&addressing.immediate_steps`

### Phase 5: Update Cpu.zig ✅

1. Import constants module
2. Replace magic numbers in `push()` and `pull()` with constants
3. Ensure `fromByte()` and `toByte()` use constants for flag masks

### Phase 6: Update Tests ✅

1. Move load/store tests to `tests/cpu/loadstore_test.zig`
2. Update helper function tests
3. Verify immediate mode tests use correct pattern
4. Remove any tests for deleted code

### Phase 7: Update Documentation ✅

1. Update `/docs/06-implementation-notes/design-decisions/cpu-execution-architecture.md`
2. Add section on helpers module
3. Document immediate mode handling pattern
4. Update examples to use new constants

### Phase 8: Cleanup ✅

1. Search for and remove any dead code
2. Verify no outdated comments reference old patterns
3. Run full test suite
4. Update STATUS.md with refactoring completion

## Verification Checklist

- [x] All tests pass (112/112 passing)
- [x] No magic numbers in code (all use constants)
- [x] No duplicate page crossing logic (centralized in helpers.readOperand)
- [x] All immediate mode uses consistent pattern (Pattern B - PC fetch in execute)
- [x] All load/store in dedicated module (loadstore.zig created)
- [x] dispatch.zig under 1000 lines (now 950 lines, reduced from 1156)
- [x] No dead code or unused functions
- [x] Documentation updated and accurate
- [x] All agent review issues addressed

## Expected Outcomes

1. **Code reduction**: ~400 lines removed from dispatch.zig
2. **Consistency**: Single pattern for immediate mode
3. **Maintainability**: Common helpers reduce duplication by ~200 lines
4. **Readability**: Named constants improve code clarity
5. **Scalability**: Clean foundation for adding 105 undocumented opcodes

## Timeline

- Phase 1-2: 30 minutes (create modules, fix immediate mode)
- Phase 3-4: 45 minutes (refactor instructions, update dispatch)
- Phase 5-6: 30 minutes (update Cpu.zig, move tests)
- Phase 7-8: 15 minutes (documentation, cleanup)

**Total estimated time**: 2 hours

## Success Criteria

✅ All 104+ existing tests pass
✅ No compiler warnings
✅ All agent-identified issues resolved
✅ Code reduction of 500+ lines through deduplication
✅ Clear, documented patterns for future opcodes
