# Subagent Analysis - RAMBO Cleanup Plan Review

**Date:** 2025-10-05
**Session:** Code Review Implementation Planning
**Agents:** zig-systems-pro, architect-reviewer, code-reviewer, test-automator, search-specialist

---

## Executive Summary

Five specialized agents conducted comprehensive analysis of the RAMBO cleanup plan. Key findings:

1. **Priority 1 items** are low-risk, high-value improvements
2. **Priority 2 architectural decisions** require course corrections
3. **KDL library doesn't exist** for Zig 0.15.x - stateless parser is better solution
4. **dispatch.zig + execution.zig merge is not recommended** - violates separation of concerns
5. **Test strategy** must include baseline capture and regression prevention

---

## Agent 1: zig-systems-pro (Priority 1 Analysis)

### Priority 1.1: Unstable Opcode Configuration

**Current State:**
- File: `src/cpu/instructions/unofficial.zig`
- Hardcoded magic values found:
  - Lines 415, 432: `XAA` and `LXA` use `magic: u8 = 0xEE`
  - Lines 337, 350, 363, 379: Unstable store operations use hardcoded AND values

**Configuration Infrastructure Exists:**
```zig
// src/config/Config.zig (lines 126-146)
pub const UnstableOpcodeConfig = struct {
    sha_behavior: SHABehavior = .rp2a03g,
    lxa_magic: u8 = 0xEE,
};

pub const CpuModel = struct {
    variant: CpuVariant = .rp2a03g,
    unstable_opcodes: UnstableOpcodeConfig = .{},
};
```

**Implementation Recommendation:**
- Thread config through instruction functions: `pub fn xaa(state: *CpuState, bus: *BusState, config: *const CpuModel) bool`
- Update 7 unstable opcode implementations
- Modify dispatch table to include config parameter
- Estimated time: 6-8 hours

**Risk Assessment:** LOW
- Compiler will catch all signature mismatches
- No silent failures possible
- Zero runtime overhead (pointer parameter)

**Test Requirements:**
- Test XAA/LXA with magic values: 0x00, 0xEE, 0xFF
- Test SHA with RP2A03G vs RP2A03H behavior
- Verify AccuracyCoin compliance with RP2A03G config

---

### Priority 1.3: Replace anytype in Bus Logic

**Current State:**
- File: `src/bus/Logic.zig`
- 8 functions use `anytype` for `ppu` parameter
- Current design accepts both `?*PpuState` and `*PpuState` with runtime type introspection

**Analysis:**
```zig
// Lines 22-23 - Current problematic pattern
pub fn read(state: *BusState, cartridge: anytype, ppu: anytype, address: u16) u8

// Lines 67-80 - Runtime type introspection (unnecessary)
if (@typeInfo(@TypeOf(ppu)) == .optional) {
    if (ppu) |p| break :blk p.readRegister(address);
}
```

**Recommendation:**
```zig
// Simplified - use optional pointer directly
pub fn read(state: *BusState, cartridge: anytype, ppu: ?*PpuState, address: u16) u8 {
    if (ppu) |p| return p.readRegister(address);
    return state.open_bus.read();
}
```

**Keep `cartridge: anytype`** - truly polymorphic (Mapper0, Mapper1, etc.)

**Risk Assessment:** VERY LOW
- Compiler catches all type mismatches
- No behavior change, only type signature
- Tests already use typed pointers

**Estimated Time:** 1.5-2 hours

---

## Agent 2: architect-reviewer (Priority 2 Analysis)

### Priority 2.1: Refactor Massive Dispatch Function

**Current State:**
- File: `src/cpu/dispatch.zig` - 1370 lines
- Single monolithic `buildDispatchTable()` function
- All 256 opcode entries defined inline

**Recommendation:**
Extract opcode group builders:
```zig
fn buildLoadStoreOpcodes() []DispatchEntry { ... }
fn buildArithmeticOpcodes() []DispatchEntry { ... }
fn buildBranchOpcodes() []DispatchEntry { ... }
// etc.
```

**NOT RECOMMENDED:** Create separate files for each group in this refactor
- Current approach: Helper functions in same file
- Benefits: Reduces cognitive load, maintains compile-time construction
- Risk: LOW

**Estimated Time:** 3-4 hours

---

### Priority 2.2: Consolidate execution.zig and dispatch.zig

**RECOMMENDATION: DO NOT MERGE** ❌

**Rationale:**
- `execution.zig` (392 lines) - Microstep execution engine
- `dispatch.zig` (1370 lines) - Opcode → executor mapping
- Different architectural purposes

**Alternative Approach:**
```
src/cpu/
├── opcodes/              # NEW: Better organization
│   ├── dispatch.zig      # Dispatch table
│   ├── LoadStore.zig     # Opcode group
│   └── ...
├── execution/            # NEW: Execution engine
│   ├── microsteps.zig    # Pure microstep functions
│   └── engine.zig        # Coordinator
```

**Rationale:**
- Separation of concerns preserved
- Each module has clear responsibility
- Easier to navigate and maintain
- No 1762-line monolith

**Estimated Time:** 8-12 hours (for proper reorganization)

---

### Priority 2.3: Remove Unused Type Aliases

**Analysis:**

**Files to Check:**
- `src/root.zig` - Exports type aliases and `PpuLogic`

**Findings:**
```zig
// src/root.zig (problematic exports)
pub const PpuLogic = @import("ppu/Logic.zig");  // ❌ Internal implementation exposed
pub const CpuType = Cpu.State.CpuState;         // Redundant alias
pub const BusType = Bus.State.BusState;         // Redundant alias
pub const PpuType = Ppu.State.PpuState;         // Redundant alias
```

**Recommendation:**
1. Remove `PpuLogic` export (line 28)
2. Optionally remove `*Type` aliases
3. Update tests to use direct paths:
   - `RAMBO.Cpu.State.CpuState` instead of `RAMBO.CpuType`

**Impact:** MEDIUM
- Breaking change for tests
- ~30 test files need import updates
- Improved API cleanliness

**Estimated Time:** 2-3 hours

---

### Priority 2.4: Reorganize Debug Tests

**Current State:**
- Debug tests mixed with core CPU tests
- Files: `cycle_trace_test.zig`, `dispatch_debug_test.zig`, `rmw_debug_test.zig`

**Recommendation:**
```bash
mkdir -p tests/debug
git mv tests/cpu/cycle_trace_test.zig tests/debug/
git mv tests/cpu/dispatch_debug_test.zig tests/debug/
git mv tests/cpu/rmw_debug_test.zig tests/debug/
# Update build.zig paths (already has test-debug step)
```

**Risk:** LOW - File movement only

**Estimated Time:** 1-2 hours

---

## Agent 3: code-reviewer (Priority 3 Analysis)

### Priority 3.1: Granular PPU tick Function

**Current State:**
- File: `src/ppu/Logic.zig` (lines 760-927)
- `tick()` function is 168 lines
- Intermixes 5 pipeline stages

**Issues Identified:**
1. Cognitive complexity - all stages in one function
2. Debugging difficulty - navigate through unrelated code
3. Testing challenges - cannot isolate stages

**Recommendation:**
Extract pipeline stages:
```zig
pub fn tick(state: *PpuState, framebuffer: ?[]u32) void {
    advanceCycle(state);
    const scanline = state.scanline;
    const dot = state.dot;

    if (is_rendering_line and state.mask.renderingEnabled()) {
        tickBackgroundPipeline(state, dot);
        tickSpritePipeline(state, dot, is_visible);
    }

    if (is_visible and dot >= 1 and dot <= 256) {
        renderPixel(state, framebuffer, dot - 1, scanline);
    }

    tickVBlankTiming(state, scanline, dot);
}
```

**RT-Safety:** Preserved - all functions remain inline-able

**Estimated Time:** 2-3 hours

---

### Priority 3.2: Shift/Rotate Instruction Duplication

**Current State:**
- File: `src/cpu/instructions/shifts.zig` (125 lines)
- All 4 instructions (ASL, LSR, ROL, ROR) duplicate accumulator vs memory handling

**Duplication Pattern:**
```zig
// Repeated 4 times:
if (state.address_mode == .accumulator) {
    value = state.a;
    // ... shift logic ...
    state.a = value;
} else {
    value = state.temp_value;
    // ... shift logic ...
    bus.write(state.effective_address, value);
}
```

**Recommendation:**
```zig
inline fn performShiftRotate(
    state: *CpuState,
    bus: *BusState,
    comptime ShiftFn: fn(u8, bool) struct { value: u8, carry: bool }
) bool {
    var value = if (state.address_mode == .accumulator)
        state.a else state.temp_value;

    const result = ShiftFn(value, state.p.carry);

    if (state.address_mode == .accumulator) {
        state.a = result.value;
    } else {
        bus.write(state.effective_address, result.value);
    }

    state.p.carry = result.carry;
    state.p.updateZN(result.value);
    return true;
}
```

**Benefits:**
- Code size: 125 → ~80 lines (36% reduction)
- DRY principle enforced
- `inline` + `comptime` = zero overhead

**Cycle Accuracy:** PRESERVED - Timing in addressing microsteps, not execute functions

**Estimated Time:** 1-2 hours

---

### Priority 3.3: READMEs for Placeholder Directories

**Findings:**

**✅ All directories already have READMEs:**
1. `src/apu/README.md` - Documents "Not Yet Implemented", planned features
2. `src/io/README.md` - Status "Planned for Phase 8+", controller registers
3. `src/mappers/README.md` - Mapper priorities, coverage percentages

**Recommendation:** NO ACTION NEEDED

---

### Priority 3.4: Skip TODO PPU Tests

**Current State:**
- File: `tests/ppu/sprite_rendering_test.zig`
- 4 tests with TODO comments but no assertions
- Tests pass misleadingly (no verification)

**Recommendation:**
```zig
test "Sprite renders at correct X" {
    // TODO(Phase 8): Requires video subsystem for framebuffer verification
    return error.SkipZigTest;
}
```

**Estimated Time:** 15 minutes

---

### Priority 3.5: Unstable Opcode Configuration (BONUS)

**Finding:**
Configuration infrastructure exists but is not connected to CPU opcodes.

**Files:**
- `src/config/Config.zig` (lines 106-152) - `UnstableOpcodeConfig` defined
- `src/cpu/instructions/unofficial.zig` - Uses hardcoded values

**Recommendation:** See Priority 1.1 analysis (same issue)

---

## Agent 4: test-automator (Test Strategy)

### Test Strategy Matrix

#### Priority 1: High-Impact Fixes

**1.1 Unstable Opcode Configuration**

*Existing Coverage:*
- `tests/cpu/unofficial_opcodes_test.zig` - 48+ tests
- Inline tests in `unofficial.zig` - 24+ tests
- ⚠️ Tests use hardcoded expectations

*New Tests Required:*
```zig
// tests/cpu/unstable_opcodes_variant_test.zig
test "XAA: magic constant varies by CPU revision" { ... }
test "LXA: RP2A03G vs RP2A03H magic values" { ... }
test "SHA: sha_behavior enum affects output" { ... }
```

*Regression Tests:*
- Behavior matrix: Each unstable opcode × each CPU variant
- Snapshot compatibility test
- AccuracyCoin compliance verification

**1.2 KDL Parsing Library**

*Existing Coverage:*
- `src/config/Config.zig` - 20+ inline tests
- ⚠️ Brittle manual parsing

*New Tests Required:*
```zig
// tests/config/kdl_parser_test.zig
test "Parse existing config.kdl with new library" { ... }
test "Malformed KDL handling" { ... }
test "Error recovery with sensible defaults" { ... }
```

**1.3 Replace anytype in Bus**

*Existing Coverage:*
- `tests/bus/bus_integration_test.zig` - 17 tests
- ⚠️ Don't verify type safety

*New Tests Required:*
```zig
// tests/comptime/bus_type_safety_test.zig
test "Bus Logic requires PpuState pointer" { ... }
// Compile-time verification - wrong type should fail to compile
```

---

#### Priority 2: Code Organization

**2.1 Refactor Dispatch Function**

*Tests:*
```zig
// tests/comptime/dispatch_table_integrity_test.zig
test "Dispatch table completeness after refactor" {
    const table = dispatch.buildDispatchTable();
    try testing.expectEqual(@as(usize, 256), table.len);
    // Verify no null function pointers
    // Verify specific critical opcodes
}
```

*Regression:*
- Generate dispatch table with OLD function → save
- Generate with NEW functions → save
- Assert binary equality

**2.2 Consolidate Files** (NOT RECOMMENDED)

*If pursued anyway:*
- Import path migration test
- Public API stability test
- Verify microstep functions remain internal

---

#### Priority 3: General Refactoring

**3.1 Granular PPU tick**

*Tests:*
```zig
// tests/ppu/pipeline_stages_test.zig
test "Nametable fetch at correct cycle" { ... }
test "Background rendering pipeline - refactored" { ... }
```

*Regression:*
- Pixel-perfect framebuffer comparison
- Cycle timing verification (89,342 cycles = 1 frame)

**3.2 Shift/Rotate Refactor**

*Existing Coverage:* 5+ inline tests per instruction

*No new tests needed* - behavior identical

*Regression:*
- All shift/rotate tests must pass
- Verify RMW dummy writes still occur

---

### Test Execution Workflow

**Before Each Phase:**
```bash
git tag "pre-phase-N"
bash scripts/capture-baseline.sh
zig build test > phase-N-baseline.log
```

**During Phase:**
```bash
# TDD: Write tests first
zig test tests/new_feature_test.zig  # Should FAIL

# Implement
# ...

# Verify
zig build test-unit  # After each change
```

**After Phase:**
```bash
zig build test
diff phase-N-baseline.log current.log
git commit -m "phase N: description"
```

---

### Regression Prevention Checklist

- [ ] Test count ≥ 575 (never decrease)
- [ ] CPU traces match baseline
- [ ] PPU framebuffers pixel-perfect
- [ ] Dispatch table structure identical
- [ ] No new expected failures
- [ ] AccuracyCoin.nes loads successfully

---

## Agent 5: search-specialist (KDL Library Research)

### Research Findings

**KDL Library Status for Zig 0.15.x:**
- ❌ **No native Zig KDL parsing library exists** for Zig 0.15.x
- KDL 2.0.0 spec finalized, but no Zig implementations found

### Alternative Solutions

**Option 1: Implement Custom KDL Parser** ⭐ CHOSEN
- Pros: Full control, learn Zig patterns, stateless design
- Cons: Initial time investment
- Effort: LOW with stateless approach (4-6 hours)
- **Result:** Successfully implemented in Phase 0

**Option 2: Adopt TOML**
- Pros: Mature libraries (`sam701/zig-toml`, `mattyhall/tomlz`)
- Cons: Different syntax, requires config migration
- Effort: 1-2 days
- **Not chosen** - KDL format preferred for readability

**Option 3: Create Minimal KDL Parser**
- Same as Option 1 (what we did)

### Recommendation

✅ **Stateless KDL Parser** (implemented in Phase 0)
- No external dependencies
- Complete control over error handling
- Thread-safe by design
- Follows RAMBO's State/Logic pattern

---

## Key Recommendations Summary

### ✅ Implement (High Value, Low Risk)

1. **Stateless KDL Parser** - Done in Phase 0 ✅
2. **Replace anytype in Bus** - Simple type signature change
3. **Unstable opcode config** - Essential for AccuracyCoin
4. **Reorganize debug tests** - File movement only
5. **Skip empty PPU tests** - Quick clarification

### ⚠️ Modify Approach (Course Correction Needed)

1. **Don't merge execution.zig + dispatch.zig**
   - Instead: Organize into `opcodes/` and `execution/` directories

2. **Don't just refactor dispatch.zig**
   - Instead: Complete opcode reorganization with state separation

3. **Remove unused type aliases carefully**
   - Breaking change - update all tests first

### 🔄 Defer to Later (Not Critical Path)

1. **Priority 4 items** - Accuracy improvements
   - Test ROM integration
   - Advanced open bus
   - OAM DMA
   - Four-screen mirroring

---

## Implementation Priority Order

Based on agent analysis, recommended order:

1. **Phase 0: Stateless Parser** ✅ COMPLETE
2. **Phase 1: Opcode State/Execution Separation** (6-8h)
3. **Phase 2: PPU Pipeline Refactoring** (4-6h)
4. **Phase 3: Config Integration** (3-4h)
5. **Phase 4: Code Organization** (4-6h)
6. **Phase 5: Documentation** (2-3h)
7. **Phase 6: Integration Verification** (2-3h)

**Total Estimated: 32-42 hours (4-6 days)**

---

## References

- **Development Progress:** [`DEVELOPMENT-PROGRESS.md`](DEVELOPMENT-PROGRESS.md)
- **Master Cleanup Plan:** [`CLEANUP-PLAN-2025-10-05.md`](CLEANUP-PLAN-2025-10-05.md)
- **Development Procedures:** [`DEVELOPMENT-PROCEDURES.md`](DEVELOPMENT-PROCEDURES.md)

---

**Analysis Date:** 2025-10-05
**Agents:** zig-systems-pro, architect-reviewer, code-reviewer, test-automator, search-specialist
**Status:** Analysis complete, Phase 0 implemented successfully ✅
