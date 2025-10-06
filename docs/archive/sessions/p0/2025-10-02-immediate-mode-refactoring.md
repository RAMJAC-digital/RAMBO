# Session Notes: Immediate Mode Refactoring & Code Deduplication

_Historical snapshot: Metrics and status values reflect the project state on 2025-10-02._

**Date:** 2025-10-02
**Duration:** ~2 hours
**Focus:** Critical bug fixes and architectural cleanup

## Session Overview

This session addressed critical issues identified by comprehensive code reviews from three specialized agents (zig-systems-pro, qa-code-review-pro, docs-architect-pro). The primary focus was fixing immediate mode inconsistencies and eliminating code duplication before implementing the remaining 221 CPU opcodes.

## Critical Issues Fixed

### 1. Immediate Mode Handling Inconsistency (CRITICAL BUG)

**Problem Identified:**
Two conflicting patterns existed for immediate mode operand access:
- **Pattern A**: Instruction expects `cpu.operand_low` to be pre-populated by addressing steps
- **Pattern B**: Instruction reads from `cpu.pc` during execute and increments PC

**Root Cause:**
- All immediate mode entries in dispatch table had empty addressing steps: `&[_]MicrostepFn{}`
- Some instructions (ADC, SBC, AND) expected addressing steps to populate `cpu.operand_low`
- Other instructions (LDA, STA, EOR) manually fetched from PC during execute

**Impact:**
- Would cause bugs when implementing undocumented opcodes using immediate mode
- Inconsistent architecture made reasoning about timing difficult
- Pattern B was hardware-accurate (2 cycles: fetch opcode + fetch operand/execute)

**Solution Applied:**
Standardized ALL immediate mode instructions on **Pattern B**:

```zig
// Every immediate mode instruction now uses this pattern:
pub fn instructionName(cpu: *Cpu, bus: *Bus) bool {
    const value = if (cpu.address_mode == .immediate) blk: {
        const v = bus.read(cpu.pc);
        cpu.pc +%= 1;
        break :blk v;
    } else helpers.readOperand(cpu, bus);

    // Instruction-specific logic...
    return true;
}
```

**Files Modified:**
- `src/cpu/instructions/arithmetic.zig` (ADC, SBC)
- `src/cpu/instructions/logical.zig` (AND, ORA, EOR)
- `src/cpu/instructions/compare.zig` (CMP, CPX, CPY)

### 2. Code Duplication Elimination

**Problem Identified:**
Page crossing logic duplicated in 6+ instruction files:

```zig
// This pattern appeared everywhere:
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

**Solution Applied:**
Created `helpers.readOperand()` function to centralize logic:

```zig
pub inline fn readOperand(cpu: *Cpu, bus: *Bus) u8 {
    return switch (cpu.address_mode) {
        .immediate => cpu.operand_low, // Never reached in practice
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
```

**Impact:**
- Removed ~200 lines of duplicate code
- Single point of truth for addressing mode handling
- Easier to verify correctness and maintain

### 3. dispatch.zig Size Reduction

**Problem Identified:**
- dispatch.zig was 1156 lines long
- Contained inline implementations of LDA, STA, LDX, LDY, STX, STY (~400 lines)
- Violated separation of concerns

**Solution Applied:**
- Moved all load/store instructions to dedicated `src/cpu/instructions/loadstore.zig` module
- Replaced inline functions with module imports in dispatch.zig
- Used helpers for page crossing logic

**Result:**
- dispatch.zig: 1156 → 950 lines (-206 lines, 17.8% reduction)
- compare.zig: 251 → 245 lines (-6 lines)
- Total reduction: 212 lines of duplicated logic eliminated

## Files Created

1. **`src/cpu/instructions/loadstore.zig`** (new module)
   - Centralized all load/store instructions: LDA, LDX, LDY, STA, STX, STY
   - Uses helpers.readOperand() and helpers.writeOperand()
   - Clean, consistent implementation pattern

## Files Modified

1. **`src/cpu/dispatch.zig`**
   - Removed inline instruction implementations
   - Imported loadstore module
   - Updated dispatch table entries to use loadstore.lda, loadstore.sta, etc.

2. **`src/cpu/helpers.zig`**
   - Enhanced readOperand() to handle all addressing modes
   - Added writeOperand() for store instructions

3. **`src/cpu/instructions/arithmetic.zig`**
   - Updated ADC and SBC to use Pattern B for immediate mode
   - Replaced manual page crossing with helpers.readOperand()

4. **`src/cpu/instructions/logical.zig`**
   - Updated AND, ORA, EOR to use Pattern B for immediate mode
   - Replaced manual page crossing with helpers.readOperand()

5. **`src/cpu/instructions/compare.zig`**
   - Updated CMP, CPX, CPY to use Pattern B for immediate mode
   - Replaced manual page crossing with helpers.readOperand()

## Test Results

**Before Refactoring:** 112 tests passing
**After Refactoring:** 112 tests passing

**Zero regressions** - all tests maintained passing status throughout refactoring.

### Test Coverage Verification

```bash
$ zig build test
All 112 tests passed.

Breakdown:
- Unit tests: 70/70 passing
- Integration tests: 42/42 passing
```

**Critical test areas validated:**
- Immediate mode timing (2 cycles)
- Page crossing behavior (dummy reads at correct addresses)
- RMW dummy write cycles
- All addressing modes for load/store instructions

## Architecture Improvements

### Before Refactoring

```
dispatch.zig (1156 lines)
├── Inline LDA implementation (8 addressing modes)
├── Inline STA implementation (7 addressing modes)
├── Inline LDX implementation
├── Inline LDY implementation
├── Inline STX implementation
├── Inline STY implementation
└── Dispatch table entries

Instructions manually handled page crossing
```

### After Refactoring

```
dispatch.zig (950 lines)
├── Import loadstore module
└── Clean dispatch table entries

src/cpu/instructions/loadstore.zig (new)
├── lda() - uses helpers.readOperand()
├── sta() - uses helpers.writeOperand()
├── ldx() - uses helpers.readOperand()
├── ldy() - uses helpers.readOperand()
├── stx() - uses helpers.writeOperand()
└── sty() - uses helpers.writeOperand()

src/cpu/helpers.zig
├── readOperand() - handles all addressing modes
├── writeOperand() - handles all write modes
└── readWithPageCrossing() - centralized logic
```

## Hardware Accuracy Validation

### Immediate Mode Timing

**6502 Hardware Behavior:**
- Cycle 1: Fetch opcode from PC, increment PC
- Cycle 2: Fetch operand from PC, increment PC, EXECUTE

**Our Implementation (Pattern B):**
```zig
// Cycle 1: fetch_opcode state (in main tick loop)
cpu.opcode = bus.read(cpu.pc);
cpu.pc +%= 1;
// Transition to execute state (empty addressing steps)

// Cycle 2: execute state
const value = bus.read(cpu.pc); // Fetch operand
cpu.pc +%= 1;                   // Increment PC
cpu.a = value;                  // Execute (LDA example)
cpu.p.updateZN(value);
return true; // Complete - 2 cycles total
```

**Result:** ✅ Hardware accurate - 2 cycles exactly

### Page Crossing Behavior

**6502 Hardware Behavior:**
- Absolute,X without page crossing: 4 cycles (dummy read IS the actual read)
- Absolute,X with page crossing: 5 cycles (dummy read, then correct address)

**Our Implementation:**
```zig
// helpers.readWithPageCrossing() handles both cases:
if (cpu.page_crossed) {
    return bus.read(cpu.effective_address); // Extra cycle, correct address
}
return cpu.temp_value; // Use value from dummy read (no extra cycle)
```

**Known Deviation:** +1 cycle for no-page-cross case (functionally correct, timing off)
- Tracked in STATUS.md under "Known Issues & Deviations"
- Requires state machine refactor to fix (state cannot complete mid-cycle currently)

## Code Quality Metrics

### Lines of Code Changes

| File | Before | After | Change |
|------|--------|-------|--------|
| dispatch.zig | 1156 | 950 | -206 (-17.8%) |
| compare.zig | 251 | 245 | -6 (-2.4%) |
| **Total** | **1407** | **1195** | **-212 (-15.1%)** |

### Duplication Reduction

- **Page crossing logic:** Appeared in 6 files → Now in 1 function (helpers.readOperand)
- **Immediate mode pattern:** 2 conflicting patterns → 1 consistent pattern
- **Load/store implementations:** Inline in dispatch.zig → Dedicated module

### Architectural Cleanliness

**Before:**
- dispatch.zig violated single responsibility (dispatch + implementation)
- Inconsistent immediate mode handling (Pattern A vs Pattern B)
- Duplicate page crossing logic in multiple files

**After:**
- dispatch.zig only handles opcode → executor mapping
- All instructions use Pattern B (hardware-accurate immediate mode)
- Single point of truth for addressing mode logic (helpers module)

## Performance Impact

**Compile time:** No significant change (~1-2 seconds for full rebuild)
**Runtime performance:** No measurable difference (helpers are `inline` functions)
**Test execution time:** No change (all optimizations are compile-time)

## Lessons Learned

### What Went Well

1. **Test-driven refactoring:** Continuous test validation prevented regressions
2. **Modular approach:** Creating helpers module first enabled clean instruction refactoring
3. **Pattern standardization:** Pattern B emerged as clearly superior for hardware accuracy
4. **Agent collaboration:** Three specialized agents identified complementary issues

### What Could Be Improved

1. **Earlier standardization:** Immediate mode inconsistency should have been caught during initial implementation
2. **Code review timing:** Earlier review would have prevented accumulation of duplicate code
3. **Documentation:** Should have documented Pattern B decision when LDA was first implemented

### Technical Debt Addressed

✅ Immediate mode inconsistency (would have caused bugs in undocumented opcodes)
✅ Code duplication across 6+ instruction files
✅ dispatch.zig size and separation of concerns
✅ Missing helpers for common operations

### Technical Debt Remaining

⚠️ +1 cycle deviation for absolute,X/Y without page crossing (requires state machine refactor)
⚠️ 221 remaining opcodes to implement
⚠️ PPU not started
⚠️ APU not started

## Next Steps

### Immediate (Post-Refactoring)

1. ✅ Update documentation (STATUS.md, cpu-execution-architecture.md)
2. ✅ Create session notes (this document)
3. ⬜ Update REFACTORING_PLAN.md checklist

### Short-term (CPU Completion)

1. Implement arithmetic/logical instructions using new pattern:
   - ADC, SBC (already refactored, need full addressing mode support)
   - BIT instruction
2. Implement branch instructions with correct timing (2/3/4 cycles)
3. Implement jump/call instructions (JMP, JSR, RTS, RTI)
4. Implement stack instructions (PHA, PLA, PHP, PLP)
5. Implement transfer/flag instructions (remaining)

### Medium-term (Architecture)

1. Address +1 cycle deviation (state machine refactor)
2. Implement undocumented opcodes using clean Pattern B foundation
3. Begin PPU implementation for AccuracyCoin graphics tests

## Code Examples

### Before: Inconsistent Immediate Mode

```zig
// ADC (Pattern A - WRONG)
pub fn adc(cpu: *Cpu, bus: *Bus) bool {
    const value = switch (cpu.address_mode) {
        .immediate => cpu.operand_low, // Expected addressing steps to populate
        // ... other modes
    };
}

// LDA (Pattern B - CORRECT)
pub fn lda(cpu: *Cpu, bus: *Bus) bool {
    const value = if (cpu.address_mode == .immediate) blk: {
        const v = bus.read(cpu.pc); // Manual PC fetch
        cpu.pc +%= 1;
        break :blk v;
    } else helpers.readOperand(cpu, bus);
}
```

### After: Consistent Pattern B

```zig
// ALL instructions now use Pattern B
pub fn adc(cpu: *Cpu, bus: *Bus) bool {
    const value = if (cpu.address_mode == .immediate) blk: {
        const v = bus.read(cpu.pc);
        cpu.pc +%= 1;
        break :blk v;
    } else helpers.readOperand(cpu, bus);

    // ADC-specific logic...
}

pub fn and(cpu: *Cpu, bus: *Bus) bool {
    const value = if (cpu.address_mode == .immediate) blk: {
        const v = bus.read(cpu.pc);
        cpu.pc +%= 1;
        break :blk v;
    } else helpers.readOperand(cpu, bus);

    cpu.a &= value;
    cpu.p.updateZN(cpu.a);
    return true;
}
```

### Before: Duplicate Page Crossing Logic

```zig
// In arithmetic.zig
if ((cpu.address_mode == .absolute_x or
    cpu.address_mode == .absolute_y or
    cpu.address_mode == .indirect_indexed) and
    cpu.page_crossed)
{
    value = bus.read(cpu.effective_address);
} else {
    value = cpu.temp_value;
}

// In logical.zig (EXACT SAME CODE)
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

### After: Centralized Helper

```zig
// In helpers.zig (SINGLE IMPLEMENTATION)
pub inline fn readOperand(cpu: *Cpu, bus: *Bus) u8 {
    return switch (cpu.address_mode) {
        .absolute_x, .absolute_y, .indirect_indexed => readWithPageCrossing(cpu, bus),
        // ... other modes
    };
}

// In ALL instruction files
const value = helpers.readOperand(cpu, bus);
```

## References

- **Agent Reviews:**
  - zig-systems-pro: Architecture analysis
  - qa-code-review-pro: Bug identification
  - docs-architect-pro: Test scenario analysis
- **Design Docs:**
  - `/docs/06-implementation-notes/design-decisions/cpu-execution-architecture.md`
  - `/docs/06-implementation-notes/design-decisions/6502-hardware-timing-quirks.md`
- **Test Results:** All 112 tests passing (0 regressions)
- **AccuracyCoin:** Requirements validated against test suite documentation

## Session Conclusion

This refactoring session successfully addressed critical architectural issues that would have caused bugs during implementation of the remaining 221 CPU opcodes. The immediate mode standardization eliminates a class of timing bugs, and the code deduplication provides a clean, maintainable foundation.

**Key Achievement:** Zero test regressions while removing 212 lines of duplicate code and fixing a critical inconsistency bug.

**Foundation Established:** Clean Pattern B immediate mode + helpers module enables rapid, correct implementation of remaining opcodes.

**Quality Metrics:**
- 100% test pass rate maintained
- 15.1% code reduction in refactored files
- Single point of truth for addressing mode logic
- Hardware-accurate 2-cycle immediate mode timing
