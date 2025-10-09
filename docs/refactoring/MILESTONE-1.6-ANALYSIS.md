# Milestone 1.6: State.zig Decomposition - Comprehensive Analysis

**Date:** 2025-10-09
**Analyst:** Claude (Explanatory Mode)
**Target:** `src/emulation/State.zig` (1,123 lines → target <800 lines)

---

## Executive Summary

State.zig has been successfully reduced from **2,225 → 1,123 lines** (49.5% reduction) across Milestones 1.1-1.5. Remaining work focuses on extracting well-isolated subsystems with **minimal risk**.

**Key Finding:** 60% of remaining code (676 lines) can be safely extracted with ZERO API changes:
- **DMA logic** (100 lines) - Perfect isolation, clear boundaries
- **Emulation helpers** (49 lines) - Convenience wrappers
- **Debugger integration** (30 lines) - Clean interface
- **Microstep boilerplate** (152 lines) - Pure delegation
- **Tests** (286 lines) - Relocate to dedicated test file
- **Bus inspection** (60 lines) - Debugger-only utility

**Recommendation:** Execute **Phase 1 (Safe Decomposition)** for Milestone 1.6, achieving **State.zig: 1,123 → 447 lines (-60.2%)**. Defer invasive refactoring to later milestones.

---

## Current State Analysis

### File Structure (1,123 lines)

| Section | Lines | % of Total | Extractable? |
|---------|-------|------------|--------------|
| **Imports & Exports** | 52 | 4.6% | ❌ Must stay |
| **EmulationState struct** | 58 | 5.2% | ❌ Must stay |
| **Core lifecycle** | 81 | 7.2% | ⚠️ Partially |
| **Bus interface** | 125 | 11.1% | ⚠️ Partially |
| **Main tick() loop** | 38 | 3.4% | ❌ Must stay |
| **Component coordination** | 73 | 6.5% | ⚠️ Complex |
| **DMA logic** | 100 | 8.9% | ✅ Extract |
| **Helper functions** | 24 | 2.1% | ✅ Extract |
| **Microstep wrappers** | 152 | 13.5% | ✅ Remove |
| **Emulation wrappers** | 49 | 4.4% | ✅ Extract |
| **Tests** | 286 | 25.5% | ✅ Relocate |
| **Other** | 85 | 7.6% | - |
| **TOTAL** | 1,123 | 100% | - |

### Function Inventory (67 functions)

#### 1. Core Lifecycle (6 functions, ~81 lines)
```zig
pub fn init(config: *const Config.Config) EmulationState
pub fn deinit(self: *EmulationState) void
pub fn loadCartridge(self: *EmulationState, cart: AnyCartridge) void
pub fn unloadCartridge(self: *EmulationState) void
pub fn reset(self: *EmulationState) void
pub fn syncDerivedSignals(self: *EmulationState) void
```
**Status:** KEEP - Fundamental to EmulationState contract

#### 2. Bus Interface (6 functions, ~125 lines)

**Public API (must stay):**
```zig
pub inline fn busRead(self: *EmulationState, address: u16) u8        // Line 209
pub inline fn busWrite(self: *EmulationState, address: u16, value: u8) // Line 251
pub inline fn busRead16(self: *EmulationState, address: u16) u16     // Line 264
pub inline fn busRead16Bug(self: *EmulationState, address: u16) u16  // Line 270
pub inline fn peekMemory(self: *const EmulationState, address: u16) u8 // Line 284, 60 lines
```

**Private helpers:**
```zig
fn cartPtr(self: *EmulationState) ?*AnyCartridge // Line 216
```

**Analysis:**
- `busRead/Write/Read16/Read16Bug`: **MUST STAY** - Core public API, heavily inlined
- `peekMemory()`: **CAN EXTRACT** - Only used by debugger, 60 lines, no inlining needed
- `cartPtr()`: **KEEP** - Tiny helper, 5 lines

#### 3. Debugger Integration (3 functions, ~30 lines)
```zig
pub fn debuggerShouldHalt(self: *const EmulationState) bool              // Line 224
pub fn debuggerIsPaused(self: *const EmulationState) bool               // Line 232
fn debuggerCheckMemoryAccess(self: *EmulationState, ...) void           // Line 237
```
**Status:** **EXTRACTABLE** to `debug/integration.zig`
**Risk:** LOW - Clean interface, called from busRead/busWrite only

#### 4. Main RT Loop (1 function, ~38 lines)
```zig
pub fn tick(self: *EmulationState) void // Line 352, CRITICAL RT LOOP
```
**Status:** **MUST STAY** - Core of cycle-accurate emulation

#### 5. Component Coordination (5 functions, ~73 lines)
```zig
fn applyPpuCycleResult(self: *EmulationState, result: PpuCycleResult) void // Line 392
fn stepPpuCycle(self: *EmulationState) PpuCycleResult                     // Line 413
fn stepCpuCycle(self: *EmulationState) CpuCycleResult                     // Line 448 (wrapper)
fn stepApuCycle(self: *EmulationState) ApuCycleResult                     // Line 464
pub fn pollMapperIrq(self: *EmulationState) bool                          // Line 452
```
**Status:** **KEEP FOR NOW** - Tightly coupled to tick() loop
**Risk:** HIGH if extracted - Complex dependencies, performance-critical

#### 6. DMA Logic (2 functions, ~100 lines)
```zig
pub fn tickDma(self: *EmulationState) void      // Line 680, 38 lines
pub fn tickDmcDma(self: *EmulationState) void   // Line 730, 50 lines
```
**Status:** **EXTRACTABLE** to `dma/logic.zig`
**Risk:** LOW - Perfect isolation, clear boundaries
**Dependencies:** BusState, PpuState, ApuLogic (all via EmulationState)

**Key Insight:** These are called ONLY from `stepCpuCycle()` in execution.zig, NOT from main tick loop!

#### 7. Helper Functions (4 functions, ~24 lines)
```zig
fn refreshPpuNmiLevel(self: *EmulationState) void        // Line 660, 5 lines
pub fn tickCpu(self: *EmulationState) void               // Line 460, 2 lines (test helper)
pub fn tickCpuWithClock(self: *EmulationState) void      // Line 654, 4 lines (test helper)
fn executeCpuCycle(self: *EmulationState) void           // Line 647, 2 lines (wrapper)
```
**Status:** MIXED
- `refreshPpuNmiLevel()`: **KEEP** - Called from busWrite(), applyPpuCycleResult()
- `tickCpu/tickCpuWithClock()`: **EXTRACT** to test utilities
- `executeCpuCycle()`: **KEEP** - Wrapper to execution.zig

#### 8. Emulation Wrappers (2 functions, ~49 lines)
```zig
pub fn emulateFrame(self: *EmulationState) u64          // Line 784, 36 lines
pub fn emulateCpuCycles(self: *EmulationState, cpu_cycles: u64) u64 // Line 823, 10 lines
```
**Status:** **EXTRACTABLE** to `helpers.zig` or `convenience.zig`
**Risk:** LOW - Convenience wrappers for tests/utilities

#### 9. Microstep Wrappers (38 functions, ~152 lines)
```zig
pub fn fetchOperandLow(self: *EmulationState) bool {
    return CpuMicrosteps.fetchOperandLow(self);
}
// ... 37 more identical wrappers
```
**Status:** **REMOVE BOILERPLATE** - Pure delegation
**Risk:** LOW - Have execution.zig import CpuMicrosteps directly

**Why they exist:** execution.zig needs to call microsteps on EmulationState. Current design uses indirection.

**Better design:**
```zig
// In execution.zig
const CpuMicrosteps = @import("cpu/microsteps.zig");

// Direct call
CpuMicrosteps.fetchOperandLow(state);
```

#### 10. Tests (11 tests, ~286 lines)
**Status:** **RELOCATE** to `tests/emulation/state_test.zig`
**Risk:** ZERO - Standard Zig pattern

---

## Extraction Strategy

### Phase 1: Safe Decomposition (Milestone 1.6)
**Goal:** Extract well-isolated subsystems with ZERO API changes
**Target Reduction:** 676 lines (60.2%)
**Result:** State.zig: 1,123 → 447 lines

#### 1.6.1: Extract DMA Logic → `dma/logic.zig` (100 lines)

**Files Created:**
- `src/emulation/dma/logic.zig` (new)

**Functions Extracted:**
```zig
pub fn tickOam(state: *EmulationState) void {
    // Previously tickDma()
    // 38 lines of OAM DMA transfer logic
}

pub fn tickDmc(state: *EmulationState) void {
    // Previously tickDmcDma()
    // 50 lines of DMC DMA stall logic
}
```

**State.zig Changes:**
```zig
const DmaLogic = @import("dma/logic.zig");

// In stepCpuCycle wrapper (execution.zig already does this):
if (state.dma.active) {
    DmaLogic.tickOam(state);  // Was: state.tickDma()
    return .{};
}

if (state.dmc_dma.rdy_low) {
    DmaLogic.tickDmc(state);  // Was: state.tickDmcDma()
    return .{};
}
```

**Risk:** **LOW**
- Clear boundaries, no complex dependencies
- Already called from isolated location (execution.zig stepCycle)
- Zero changes to public API

#### 1.6.2: Extract Bus Inspection → `bus/inspection.zig` (60 lines)

**Files Created:**
- `src/emulation/bus/inspection.zig` (new)

**Functions Extracted:**
```zig
pub fn peekMemory(state: *const EmulationState, address: u16) u8 {
    // 60 lines of switch logic for debugger inspection
}
```

**State.zig Changes:**
```zig
const BusInspection = @import("bus/inspection.zig");

pub inline fn peekMemory(self: *const EmulationState, address: u16) u8 {
    return BusInspection.peekMemory(self, address);
}
```

**Risk:** **LOW**
- Only used by debugger, not performance-critical
- Can remain inlined wrapper if needed
- Zero API changes

#### 1.6.3: Extract Debugger Integration → `debug/integration.zig` (30 lines)

**Files Created:**
- `src/emulation/debug/integration.zig` (new)

**Functions Extracted:**
```zig
pub fn shouldHalt(state: *const EmulationState) bool { ... }
pub fn isPaused(state: *const EmulationState) bool { ... }
pub fn checkMemoryAccess(state: *EmulationState, address: u16, value: u8, is_write: bool) void { ... }
```

**State.zig Changes:**
```zig
const DebugIntegration = @import("debug/integration.zig");

pub fn debuggerShouldHalt(self: *const EmulationState) bool {
    return DebugIntegration.shouldHalt(self);
}
// Similar for other functions
```

**Risk:** **LOW**
- Clear interface boundary
- Called from busRead/busWrite and tick()
- No complex dependencies

#### 1.6.4: Extract Emulation Helpers → `helpers.zig` (49 lines)

**Files Created:**
- `src/emulation/helpers.zig` (new)

**Functions Extracted:**
```zig
pub fn emulateFrame(state: *EmulationState) u64 { ... }
pub fn emulateCpuCycles(state: *EmulationState, cpu_cycles: u64) u64 { ... }
pub fn tickCpuWithClock(state: *EmulationState) void { ... }  // Test helper
```

**State.zig Changes:**
```zig
const Helpers = @import("helpers.zig");

pub fn emulateFrame(self: *EmulationState) u64 {
    return Helpers.emulateFrame(self);
}
// Similar for other functions
```

**Risk:** **LOW**
- Convenience wrappers, not core functionality
- Primarily used in tests
- Zero logic changes

#### 1.6.5: Eliminate Microstep Boilerplate (152 lines)

**Current Design:**
```zig
// In State.zig (38 functions × 4 lines = 152 lines)
pub fn fetchOperandLow(self: *EmulationState) bool {
    return CpuMicrosteps.fetchOperandLow(self);
}
// ... 37 more
```

**New Design:**
```zig
// In execution.zig - Direct import
const CpuMicrosteps = @import("cpu/microsteps.zig");

// Direct calls
if (CpuMicrosteps.fetchOperandLow(state)) { ... }
```

**State.zig Changes:**
- **Delete all 38 wrapper functions** (lines 490-641)
- Update execution.zig to import CpuMicrosteps directly

**Risk:** **LOW**
- Pure boilerplate removal
- No logic changes
- Better architecture (less indirection)

#### 1.6.6: Relocate Tests → `tests/emulation/state_test.zig` (286 lines)

**Files Created:**
- `tests/emulation/state_test.zig` (new)

**State.zig Changes:**
- **Delete all test functions** (lines 838-1124)
- Move to dedicated test file

**Risk:** **ZERO**
- Standard Zig pattern
- Improves test discoverability
- No changes to test logic

---

### Phase 1 Summary

**Extractions:**
| Module | Lines | Risk | Benefit |
|--------|-------|------|---------|
| dma/logic.zig | 100 | LOW | Clean DMA isolation |
| bus/inspection.zig | 60 | LOW | Debugger separation |
| debug/integration.zig | 30 | LOW | Clean interface |
| helpers.zig | 49 | LOW | Convenience consolidation |
| **Removals:** | | | |
| Microstep boilerplate | 152 | LOW | Architecture improvement |
| Tests relocation | 286 | ZERO | Standard pattern |
| **TOTAL REDUCTION** | **676** | **LOW** | **60.2% reduction** |

**Result:** State.zig: **1,123 → 447 lines**

**Files Created:** 4 new modules + 1 test file
**API Changes:** ZERO (all wrappers maintained)
**Risk Level:** LOW (well-isolated, clear boundaries)

---

### Phase 2: Refactoring & Cleanup (Later Milestone)
**Goal:** Clean up remaining code, minimal API changes
**Target Reduction:** ~100 lines
**Result:** State.zig: 447 → ~350 lines

#### Candidates:

1. **Component Coordination** (73 lines)
   - Extract stepPpuCycle(), stepApuCycle(), applyPpuCycleResult()
   - Module: `coordination.zig`
   - Risk: **MEDIUM-HIGH** - Tightly coupled to tick() loop
   - Benefit: Cleaner tick() function

2. **Lifecycle Consolidation** (20 lines)
   - Merge reset() logic with component modules
   - Risk: **MEDIUM** - Touches initialization
   - Benefit: Distributed ownership

**Defer to Milestone 1.7+** - Focus on safe extractions first

---

### Phase 3: Advanced Refactoring (Future Work)
**Goal:** Structural improvements, potential API changes
**Risk:** HIGH - defer until Phase 1/2 complete

#### Candidates:

1. **Component State Extraction**
   - Move cpu/ppu/apu state to dedicated files
   - Risk: **HIGH** - Major architectural change
   - Benefit: True component isolation

2. **Bus Routing Optimization**
   - Comptime dispatch instead of runtime switch
   - Risk: **HIGH** - Performance implications
   - Benefit: Potential speed improvements

**Status:** DEFERRED - Requires careful benchmarking

---

## What Must Stay in State.zig

### Core RT Loop (CRITICAL - DO NOT TOUCH)
```zig
pub fn tick(self: *EmulationState) void {
    // Main cycle-accurate emulation loop
    // Lines: 352-390 (38 lines)
}
```
**Why:** This is the heart of cycle-accurate emulation. Any extraction would add indirection to the hottest code path.

### EmulationState Struct Definition
```zig
pub const EmulationState = struct {
    clock: MasterClock,
    cpu: CpuState,
    ppu: PpuState,
    apu: ApuState,
    // ... (58 lines)
}
```
**Why:** Single source of truth for entire emulation state. Direct ownership is core to architecture.

### Core Lifecycle
```zig
pub fn init(config: *const Config.Config) EmulationState { ... }
pub fn deinit(self: *EmulationState) void { ... }
pub fn reset(self: *EmulationState) void { ... }
```
**Why:** Fundamental to EmulationState contract. External code depends on these.

### Bus Interface (Public API)
```zig
pub inline fn busRead(self: *EmulationState, address: u16) u8 { ... }
pub inline fn busWrite(self: *EmulationState, address: u16, value: u8) { ... }
pub inline fn busRead16(self: *EmulationState, address: u16) u16 { ... }
pub inline fn busRead16Bug(self: *EmulationState, address: u16) u16 { ... }
```
**Why:** Performance-critical hot path. Inlining is essential. Cannot extract without performance regression.

### Component Coordination (For Now)
```zig
fn stepPpuCycle(self: *EmulationState) PpuCycleResult { ... }
fn stepApuCycle(self: *EmulationState) ApuCycleResult { ... }
fn applyPpuCycleResult(self: *EmulationState, result: PpuCycleResult) void { ... }
```
**Why:** Tightly coupled to tick() loop. Extraction is possible but complex. Defer to Phase 2.

---

## Dependency Analysis

### DMA Logic Dependencies
```
tickDma() requires:
  - self.dma (OamDma state)
  - self.busRead() (CPU RAM access)
  - self.ppu.oam (PPU OAM array)

tickDmcDma() requires:
  - self.dmc_dma (DmcDma state)
  - self.busRead() (sample fetch)
  - ApuLogic.loadSampleByte() (APU interface)
  - self.config.cpu.variant (DPCM bug detection)
```
**Coupling:** LOW - All accessed via EmulationState pointer
**Isolation:** EXCELLENT - Called only from execution.zig stepCycle()

### Bus Inspection Dependencies
```
peekMemory() requires:
  - self.bus.ram
  - self.ppu.* (all PPU state)
  - self.apu.* (APU state)
  - self.controller.* (controller state)
  - self.cart (cartridge)
```
**Coupling:** MEDIUM - Reads entire emulation state
**Isolation:** EXCELLENT - Only used by debugger, no side effects

### Debugger Integration Dependencies
```
debuggerShouldHalt() requires:
  - self.debugger (Debugger state)

debuggerCheckMemoryAccess() requires:
  - self.debugger (Debugger state)
  - self (for breakpoint evaluation)
```
**Coupling:** LOW - Clean interface
**Isolation:** EXCELLENT - Called from well-defined locations

### Emulation Helpers Dependencies
```
emulateFrame() requires:
  - self.tick() (main loop)
  - self.frame_complete (flag)
  - self.clock (cycle counting)

emulateCpuCycles() requires:
  - self.tick() (main loop)
  - self.clock (cycle counting)
```
**Coupling:** HIGH - Wraps tick() loop
**Isolation:** GOOD - Convenience wrappers, no complex logic

---

## Risk Assessment

### LOW RISK Extractions (Phase 1)
✅ **DMA Logic** - Perfect isolation, clear call sites
✅ **Bus Inspection** - Debugger-only, no side effects
✅ **Debugger Integration** - Clean interface boundary
✅ **Emulation Helpers** - Convenience wrappers
✅ **Microstep Boilerplate** - Pure delegation removal
✅ **Test Relocation** - Standard Zig pattern

### MEDIUM RISK Extractions (Phase 2)
⚠️ **Component Coordination** - Tightly coupled to tick() loop
⚠️ **Lifecycle Consolidation** - Touches initialization

### HIGH RISK Refactoring (Phase 3+)
🔴 **Component State Extraction** - Major architectural change
🔴 **Bus Routing Optimization** - Performance implications
🔴 **Main tick() Decomposition** - Would harm performance

---

## Easy Wins

### 1. Test Relocation (286 lines, ZERO risk)
**Action:** Move tests to `tests/emulation/state_test.zig`
**Time:** 5 minutes
**Benefit:** Standard Zig pattern, cleaner State.zig

### 2. DMA Logic Extraction (100 lines, LOW risk)
**Action:** Extract to `dma/logic.zig`
**Time:** 20 minutes
**Benefit:** Clean DMA isolation, improved modularity

### 3. Microstep Boilerplate Removal (152 lines, LOW risk)
**Action:** Have execution.zig import CpuMicrosteps directly
**Time:** 15 minutes
**Benefit:** Less indirection, cleaner architecture

**Total Easy Wins:** 538 lines (47.9% reduction) in ~40 minutes

---

## Recommendations

### For Milestone 1.6 (Execute Immediately)
1. ✅ **Execute Phase 1 (Safe Decomposition)** - All 6 extractions
2. ✅ **Target:** State.zig: 1,123 → 447 lines (-60.2%)
3. ✅ **Risk Level:** LOW - Well-isolated, clear boundaries
4. ✅ **API Changes:** ZERO - All wrappers maintained
5. ✅ **Time Estimate:** 2-3 hours

### For Milestone 1.7 (Future)
1. ⚠️ **Evaluate Phase 2** - Component coordination extraction
2. ⚠️ **Risk Assessment:** Test performance impact carefully
3. ⚠️ **Time Estimate:** 3-4 hours

### For Later (Defer)
1. 🔴 **Phase 3** - Structural refactoring
2. 🔴 **Requires:** Comprehensive benchmarking suite
3. 🔴 **Risk:** HIGH - Major architectural changes

---

## Success Criteria

### Milestone 1.6 Complete When:
- ✅ State.zig reduced to <500 lines (target: 447 lines)
- ✅ All tests passing (939/950 baseline maintained)
- ✅ Build succeeds without warnings
- ✅ Zero API changes (existing code works unchanged)
- ✅ 4 new modules created (dma/logic, bus/inspection, debug/integration, helpers)
- ✅ 1 test file created (state_test.zig)
- ✅ Documentation updated (PHASE-1-PROGRESS.md)

---

## Implementation Order

**Recommended sequence for Milestone 1.6:**

1. **Test Relocation** (5 min) - Get easy win first, validate test infrastructure
2. **Microstep Boilerplate** (15 min) - Clean up before new extractions
3. **DMA Logic** (20 min) - Largest extraction, clear boundaries
4. **Bus Inspection** (15 min) - Debugger separation
5. **Debugger Integration** (15 min) - Clean interface
6. **Emulation Helpers** (10 min) - Final extraction
7. **Validation** (30 min) - Build, test, document

**Total Time:** ~2 hours

---

## Appendix: Line Count Breakdown

```
State.zig: 1,123 lines total

KEEP (447 lines after Phase 1):
  - Imports/Exports: 52 lines
  - EmulationState struct: 58 lines
  - Core lifecycle (init/deinit/reset/etc): 81 lines
  - Bus interface (busRead/Write/Read16): 65 lines (keeping wrappers to peekMemory)
  - Main tick() loop: 38 lines
  - Component coordination: 73 lines
  - Helper functions: 24 lines
  - Private helpers (cartPtr, etc): 10 lines
  - Other (comments, spacing): 46 lines

EXTRACT (676 lines):
  - DMA logic: 100 lines → dma/logic.zig
  - Bus inspection: 60 lines → bus/inspection.zig
  - Debugger integration: 30 lines → debug/integration.zig
  - Emulation helpers: 49 lines → helpers.zig
  - Microstep boilerplate: 152 lines → REMOVE (execution.zig imports directly)
  - Tests: 286 lines → tests/emulation/state_test.zig
```

**Final Result:** State.zig: **1,123 → 447 lines (-60.2%)**

---

**Status:** READY TO EXECUTE
**Next Step:** Begin Phase 1 implementation starting with test relocation
