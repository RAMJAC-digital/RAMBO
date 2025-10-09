# EmulationState Architecture Audit

**File:** `/home/colin/Development/RAMBO/src/emulation/State.zig`
**Lines:** 2,225
**Functions:** 77
**Date:** 2025-10-09
**Status:** CRITICAL - File too large, needs modularization

---

## Executive Summary

### Critical Issues

1. **MASSIVE MONOLITH:** 2,225 lines in a single file - violates single responsibility principle
2. **MIXED CONCERNS:** Combines 6+ distinct responsibilities in one module
3. **200+ LINE FUNCTION:** `executeCpuCycle()` (lines 1192-1751) is 559 lines long with extreme cyclomatic complexity
4. **40+ MICROSTEP HELPERS:** Lines 832-1188 contain 35+ private helper functions that could be extracted
5. **STATE EXPLOSION:** 5 separate state machines mixed with orchestration logic
6. **PUBLIC API POLLUTION:** 17+ public functions when only ~8 are truly external API

### Impact

- **Maintainability:** CRITICAL - impossible to understand without extensive context
- **Testability:** POOR - can't test individual components in isolation
- **Risk:** HIGH - changes to CPU microsteps affect DMA, controller, and bus logic
- **Cognitive Load:** EXTREME - must understand entire emulation architecture to modify anything

### Recommendation

**IMMEDIATE ACTION REQUIRED:** Break into 8+ focused modules with clear boundaries and contracts.

---

## File Structure Analysis

### Lines 1-225: Supporting State Structures (EXTRACTABLE)

#### `PpuCycleResult` (30-36) - 7 lines
- **Purpose:** Return type for PPU cycle execution
- **Dependencies:** None
- **Risk:** ZERO - pure data structure
- **Action:** Extract to `src/emulation/CycleResults.zig`

#### `CpuCycleResult` (38-40) - 3 lines
- **Purpose:** Return type for CPU cycle execution
- **Dependencies:** None
- **Risk:** ZERO - pure data structure
- **Action:** Extract to `src/emulation/CycleResults.zig`

#### `ApuCycleResult` (42-45) - 4 lines
- **Purpose:** Return type for APU cycle execution
- **Dependencies:** None
- **Risk:** ZERO - pure data structure
- **Action:** Extract to `src/emulation/CycleResults.zig`

#### `BusState` (49-58) - 10 lines
- **Purpose:** CPU memory bus state (RAM + open bus)
- **Dependencies:** None
- **External Usage:** 3 files (snapshot/state.zig, cpu/opcodes/mod.zig, integration tests)
- **Risk:** LOW - only referenced by snapshot serialization
- **Action:** Extract to `src/emulation/BusState.zig`

#### `DmaState` (63-102) - 40 lines
- **Purpose:** OAM DMA state machine
- **Dependencies:** None
- **Methods:** 2 public (`trigger`, `reset`)
- **External Usage:** None (internal to emulation)
- **Risk:** ZERO - self-contained state machine
- **Action:** Extract to `src/emulation/dma/OamDma.zig`

#### `ControllerState` (107-189) - 83 lines
- **Purpose:** NES controller shift register emulation
- **Dependencies:** None
- **Methods:** 6 public (`latch`, `updateButtons`, `read1`, `read2`, `writeStrobe`, `reset`)
- **External Usage:** 2 test files (controller_test.zig, input_integration_test.zig)
- **Risk:** LOW - only tests directly access
- **Action:** Extract to `src/input/ControllerState.zig` (aligns with input/ module)

#### `DmcDmaState` (194-224) - 31 lines
- **Purpose:** DMC sample fetch DMA state machine
- **Dependencies:** None
- **Methods:** 2 public (`triggerFetch`, `reset`)
- **External Usage:** None (internal to emulation)
- **Risk:** ZERO - self-contained state machine
- **Action:** Extract to `src/emulation/dma/DmcDma.zig`

### Lines 233-649: EmulationState Core (KEEP - but refactor helpers)

#### `EmulationState` struct definition (233-304)
- **Purpose:** Main emulation state container
- **Fields:** 15 fields (clock, cpu, ppu, apu, bus, cart, dma, dmc_dma, controller, etc.)
- **Risk:** MEDIUM - central data structure referenced everywhere
- **Action:** KEEP structure, extract methods to Logic module

#### Lifecycle Methods (293-373)
- `init()` (293-304) - 12 lines - **PUBLIC API** ✅
- `deinit()` (308-312) - 5 lines - **PUBLIC API** ✅
- `loadCartridge()` (323-332) - 10 lines - **PUBLIC API** ✅
- `unloadCartridge()` (335-340) - 6 lines - **PUBLIC API** ✅
- `reset()` (344-368) - 25 lines - **PUBLIC API** ✅
- `syncDerivedSignals()` (371-373) - 3 lines - **PUBLIC API** (testing only)

#### Bus Routing (381-649) - 269 lines - **EXTRACT TO BusLogic.zig**

**Critical Finding:** Bus routing is inline switch logic embedded in EmulationState, but it should be a separate abstraction.

- `busRead()` (381-445) - 65 lines - **PUBLIC API** ✅
- `busWrite()` (483-565) - 83 lines - **PUBLIC API** ✅
- `busRead16()` (569-573) - 5 lines - **PUBLIC API** ✅
- `busRead16Bug()` (577-588) - 12 lines - **PUBLIC API** ✅
- `peekMemory()` (600-648) - 49 lines - **PUBLIC API** (debugger only)

**Helpers (internal):**
- `cartPtr()` (448-453) - 6 lines
- `debuggerShouldHalt()` (456-461) - 6 lines
- `debuggerIsPaused()` (464-466) - 3 lines
- `debuggerCheckMemoryAccess()` (469-479) - 11 lines

**Extraction Plan:**
1. Create `src/emulation/BusLogic.zig` with pure functions
2. Convert `busRead(state, address)` to static function pattern
3. Keep inline functions in EmulationState as delegation wrappers
4. **Risk:** MEDIUM - 40+ files call these functions

### Lines 668-821: Main Tick Loop (KEEP - but extract helpers)

#### Core Emulation Loop
- `tick()` (668-706) - 39 lines - **PUBLIC API** ✅ - KEEP
- `applyPpuCycleResult()` (708-727) - 20 lines - **EXTRACT to Logic**
- `stepPpuCycle()` (729-762) - 34 lines - **EXTRACT to Logic**
- `stepCpuCycle()` (764-789) - 26 lines - **EXTRACT to Logic**
- `stepApuCycle()` (803-821) - 19 lines - **EXTRACT to Logic**
- `pollMapperIrq()` (791-796) - 6 lines - **EXTRACT to Logic**

**Analysis:** These are orchestration functions that coordinate component state machines. Should be in `EmulationLogic.zig`.

### Lines 832-1188: CPU Microstep Helpers (357 lines - **EXTRACT**)

**CRITICAL CODE SMELL:** 35+ private helper functions (all `fn`, not `pub fn`) that implement CPU addressing mode microsteps.

**Classification:**
- **Operand Fetch:** `fetchOperandLow`, `fetchAbsLow`, `fetchAbsHigh` (lines 832-850)
- **Indexed Addressing:** `addXToZeroPage`, `addYToZeroPage`, `calcAbsoluteX`, `calcAbsoluteY`, `fixHighByte` (853-903)
- **Indirect Addressing:** `fetchZpBase`, `addXToBase`, `fetchIndirectLow`, `fetchIndirectHigh`, `fetchZpPointer`, `fetchPointerLow`, `fetchPointerHigh`, `addYCheckPage` (906-963)
- **Stack Operations:** `pullByte`, `stackDummyRead`, `pushPch`, `pushPcl`, `pushStatusBrk`, `pushStatusInterrupt`, `pullPcl`, `pullPch`, `pullPchRti`, `pullStatus`, `incrementPcAfterRts` (966-1056)
- **Control Flow:** `jsrStackDummy`, `fetchAbsHighJsr`, `fetchIrqVectorLow`, `fetchIrqVectorHigh` (1059-1085)
- **RMW Operations:** `rmwRead`, `rmwDummyWrite` (1088-1111)
- **Branch Operations:** `branchFetchOffset`, `branchAddOffset`, `branchFixPch` (1114-1164)
- **JMP Indirect:** `jmpIndirectFetchLow`, `jmpIndirectFetchHigh` (1167-1184)

**Problem:** These functions are CPU implementation details leaked into EmulationState.

**Extraction Plan:**
1. Create `src/cpu/Microsteps.zig` module
2. All functions take `*CpuState` and `*EmulationState` (for bus access)
3. Import in `EmulationState` and delegate
4. **Risk:** MEDIUM - only called from `executeCpuCycle()`

### Lines 1192-1751: executeCpuCycle() - **THE MONSTER** (559 lines)

**CRITICAL VIOLATION:** Single function is 559 lines long with nested switch statements 5+ levels deep.

**Complexity Metrics:**
- **Cyclomatic Complexity:** ~150+ (estimated from switch nesting)
- **Nesting Depth:** 5+ levels
- **Instruction Cycle Dispatch:** 256 opcode cases × 8+ addressing modes = ~500+ code paths

**Structure:**
1. Lines 1192-1229: Interrupt checking and debugger breakpoints
2. Lines 1232-1280: Hardware interrupt sequence (7 cycles)
3. Lines 1283-1309: Opcode fetch (cycle 1)
4. Lines 1312-1658: Addressing mode microsteps (MASSIVE nested switch)
5. Lines 1662-1750: Execute instruction (operand extraction + opcode call)

**Why This Is Terrible:**
- Impossible to understand without reading entire function
- Can't test individual addressing modes in isolation
- Changes to branch logic affect DMA and RMW logic
- Violates Single Responsibility Principle ~50 times

**Extraction Plan:**
1. Extract to `src/cpu/ExecutionLogic.zig`
2. Break into smaller functions:
   - `handleInterruptSequence()`
   - `handleOpcodeFetch()`
   - `handleAddressingCycle()` (switch on address_mode)
   - `handleExecuteCycle()`
3. Move microstep dispatch tables to `src/cpu/AddressingModes.zig`
4. **Risk:** HIGH - core execution path, but well-tested

### Lines 1756-1934: Convenience Wrappers + DMA (179 lines)

#### Test Helpers
- `tickCpuWithClock()` (1756-1759) - 4 lines - **PUBLIC** (test only)

#### Internal Helpers
- `refreshPpuNmiLevel()` (1762-1766) - 5 lines - **EXTRACT to Logic**

#### DMA State Machines (82 lines - **EXTRACT**)
- `tickDma()` (1782-1819) - 38 lines - **EXTRACT to dma/OamDma.zig**
- `tickDmcDma()` (1832-1881) - 50 lines - **EXTRACT to dma/DmcDma.zig**

**Analysis:** These are DMA implementation details that belong in dedicated modules.

#### Emulation Convenience Functions
- `emulateFrame()` (1886-1921) - 36 lines - **PUBLIC API** ✅
- `emulateCpuCycles()` (1925-1934) - 10 lines - **PUBLIC API** ✅

### Lines 1940-2225: Tests (286 lines)

**Good:** Comprehensive test coverage for MasterClock and EmulationState.

**Tests Cover:**
- MasterClock cycle conversion, scanline calculation, frame calculation
- EmulationState initialization, tick advancement, CPU/PPU synchronization
- VBlank timing, odd frame skip, frame toggling

**Action:** KEEP - move to separate test file later if needed

---

## Dependency Analysis

### What EmulationState Imports

```zig
std
Config (../config/Config.zig)
MasterClock (MasterClock.zig)
CpuModule (../cpu/Cpu.zig) → CpuState, CpuLogic
PpuModule (../ppu/Ppu.zig) → PpuState, PpuLogic
PpuRuntime (Ppu.zig)
ApuModule (../apu/Apu.zig) → ApuState, ApuLogic
CartridgeModule (../cartridge/Cartridge.zig)
RegistryModule (../cartridge/mappers/registry.zig) → AnyCartridge
Debugger (../debugger/Debugger.zig)
```

**Analysis:** EmulationState is a **CENTRAL HUB** that orchestrates all components. This is correct architecturally, but implementation leaks too many details.

### What Imports EmulationState

**Core Emulation:**
- `src/emulation/Ppu.zig` - PPU runtime orchestration
- `src/threads/EmulationThread.zig` - RT emulation loop
- `src/root.zig` - Public library API

**Debugging/Tools:**
- `src/debugger/Debugger.zig` - Breakpoint/watchpoint evaluation
- `src/snapshot/Snapshot.zig` - Save state serialization
- `src/snapshot/state.zig` - State serialization helpers
- `src/test/Harness.zig` - Test harness

**Tests (40+ files):**
- All integration tests
- Most CPU tests
- Most PPU tests
- APU tests
- Cartridge tests

**Critical Finding:** 40+ files import EmulationState, but most only use:
- `init()`, `deinit()`, `reset()`
- `loadCartridge()`
- `tick()`, `emulateFrame()`, `emulateCpuCycles()`
- `busRead()`, `busWrite()` (for test setup)

**Public API Usage Breakdown:**
```
init()               → 40+ files (everywhere)
deinit()             → 40+ files (everywhere)
reset()              → 35+ files
loadCartridge()      → 20+ files
tick()               → 15+ files
emulateFrame()       → 10+ files
busRead/busWrite()   → 30+ files (mostly tests)
peekMemory()         → 5+ files (debugger + tests)
emulateCpuCycles()   → 8+ files
```

**Internal Usage (should be private to emulation/):**
```
tickCpu()            → 1 file (nmi_sequence_test.zig) - TEST HELPER
tickDmcDma()         → 1 file (dpcm_dma_test.zig) - TEST HELPER
debuggerIsPaused()   → 2 files (EmulationThread, tests)
syncDerivedSignals() → 2 files (tests only)
```

---

## Code Quality Issues

### 1. Function Length Violations

**Industry Standard:** Functions should be < 50 lines for readability.

**Violations:**
- `executeCpuCycle()` - **559 lines** 🚨 (lines 1192-1751)
- `busWrite()` - 83 lines (lines 483-565)
- `busRead()` - 65 lines (lines 381-445)
- `peekMemory()` - 49 lines (lines 600-648)
- `tickDmcDma()` - 50 lines (lines 1832-1881)
- `tickDma()` - 38 lines (lines 1782-1819)
- `emulateFrame()` - 36 lines (lines 1886-1921)

**Total:** 7 functions exceed 35+ lines (9% of functions, but 46% of code)

### 2. Cyclomatic Complexity Issues

**Estimated Complexity (switch statement depth):**
- `executeCpuCycle()` - ~150+ paths (switch × switch × switch × switch × switch)
- `busRead()` - ~20 paths (address range switches)
- `busWrite()` - ~15 paths (address range switches)

**Problem:** Impossible to test all paths, high bug risk.

### 3. Single Responsibility Violations

**EmulationState is responsible for:**
1. Emulation state container (fields) ✅ Correct
2. Component lifecycle (init/deinit/reset) ✅ Correct
3. Memory bus routing (busRead/busWrite) ❌ Should be BusLogic
4. CPU microstep execution ❌ Should be CpuExecutionLogic
5. DMA state machines ❌ Should be dma/OamDma + dma/DmcDma
6. Controller emulation ❌ Should be input/ControllerState
7. PPU/CPU/APU orchestration ❌ Should be EmulationLogic
8. Debugger integration ❌ Mixed concern
9. Frame/cycle convenience wrappers ✅ Correct

**Verdict:** Violates SRP by handling 6+ distinct concerns.

### 4. Encapsulation Issues

**Public API Pollution:**
- `tickCpu()` - Should be `pub(emulation)` or `pub(test)`
- `tickDmcDma()` - Should be private (only 1 test uses it)
- `tickCpuWithClock()` - Should be `pub(test)`
- `debuggerIsPaused()` - Leaks debugger internals

**Missing Encapsulation:**
- All microstep helpers are private (`fn`), but should be in separate module
- DMA functions should be methods on DMA state machines
- Bus routing should be in separate module with clear interface

---

## Module Boundary Analysis

### Natural Module Boundaries

Based on code structure, usage patterns, and dependencies:

#### 1. **Core State** (KEEP in State.zig)
```zig
// Lines 233-304 + lifecycle methods
pub const EmulationState = struct {
    clock: MasterClock,
    cpu: CpuState,
    ppu: PpuState,
    apu: ApuState,
    bus: BusState,
    cart: ?AnyCartridge,
    dma: DmaState,
    dmc_dma: DmcDmaState,
    controller: ControllerState,
    debugger: ?Debugger,
    // ... flags and configuration

    pub fn init(...) EmulationState { ... }
    pub fn deinit(...) void { ... }
    pub fn reset(...) void { ... }
    pub fn loadCartridge(...) void { ... }
    pub fn unloadCartridge(...) void { ... }
};
```

**Lines:** ~100 (struct + lifecycle)
**Risk:** ZERO - pure data structure

#### 2. **Cycle Result Types** → `CycleResults.zig`
```zig
// Lines 30-45
pub const PpuCycleResult = struct { ... };
pub const CpuCycleResult = struct { ... };
pub const ApuCycleResult = struct { ... };
```

**Lines:** ~20
**Dependencies:** None
**Risk:** ZERO - pure data

#### 3. **Bus State** → `BusState.zig`
```zig
// Lines 49-58
pub const BusState = struct {
    ram: [2048]u8,
    open_bus: u8,
    test_ram: ?[]u8,
};
```

**Lines:** ~15
**Dependencies:** None
**External Usage:** snapshot/, tests
**Risk:** LOW - only field access

#### 4. **Bus Logic** → `BusLogic.zig`
```zig
// Lines 381-649 (bus routing logic)
pub fn busRead(state: *EmulationState, address: u16) u8 { ... }
pub fn busWrite(state: *EmulationState, address: u16, value: u8) void { ... }
pub fn busRead16(state: *EmulationState, address: u16) u16 { ... }
pub fn busRead16Bug(state: *EmulationState, address: u16) u16 { ... }
pub fn peekMemory(state: *const EmulationState, address: u16) u8 { ... }

// Internal helpers
fn cartPtr(state: *EmulationState) ?*AnyCartridge { ... }
fn debuggerCheckMemoryAccess(...) void { ... }
```

**Lines:** ~280
**Dependencies:** EmulationState, Cartridge, PPU, APU, Controller
**Risk:** MEDIUM - 40+ files call bus functions

**Migration Strategy:**
1. Create BusLogic.zig with pure functions
2. Add inline delegation wrappers to EmulationState:
   ```zig
   pub inline fn busRead(self: *EmulationState, address: u16) u8 {
       return BusLogic.busRead(self, address);
   }
   ```
3. No API changes - zero risk to external code
4. Later: Encourage direct BusLogic usage in new code

#### 5. **OAM DMA** → `dma/OamDma.zig`
```zig
// Lines 63-102 (DmaState struct)
// Lines 1782-1819 (tickDma function)

pub const OamDmaState = struct {
    active: bool,
    source_page: u8,
    current_offset: u8,
    current_cycle: u16,
    needs_alignment: bool,
    temp_value: u8,

    pub fn trigger(self: *Self, page: u8, on_odd_cycle: bool) void { ... }
    pub fn reset(self: *Self) void { ... }
    pub fn tick(self: *Self, state: *EmulationState) void { ... }
};
```

**Lines:** ~80
**Dependencies:** EmulationState (for bus access)
**Risk:** ZERO - internal to emulation

#### 6. **DMC DMA** → `dma/DmcDma.zig`
```zig
// Lines 194-224 (DmcDmaState struct)
// Lines 1832-1881 (tickDmcDma function)

pub const DmcDmaState = struct {
    rdy_low: bool,
    stall_cycles_remaining: u8,
    sample_address: u16,
    sample_byte: u8,
    last_read_address: u16,

    pub fn triggerFetch(self: *Self, address: u16) void { ... }
    pub fn reset(self: *Self) void { ... }
    pub fn tick(self: *Self, state: *EmulationState) void { ... }
};
```

**Lines:** ~80
**Dependencies:** EmulationState (for bus access), Config
**Risk:** ZERO - internal to emulation
**External Usage:** 1 test file (dpcm_dma_test.zig) - uses tickDmcDma()

**Migration Note:** Test must be updated to call `state.dmc_dma.tick(&state)` instead.

#### 7. **Controller State** → `input/ControllerState.zig`
```zig
// Lines 107-189

pub const ControllerState = struct {
    shift1: u8,
    shift2: u8,
    strobe: bool,
    buttons1: u8,
    buttons2: u8,

    pub fn latch(self: *Self) void { ... }
    pub fn updateButtons(self: *Self, buttons1: u8, buttons2: u8) void { ... }
    pub fn read1(self: *Self) u8 { ... }
    pub fn read2(self: *Self) u8 { ... }
    pub fn writeStrobe(self: *Self, value: u8) void { ... }
    pub fn reset(self: *Self) void { ... }
};
```

**Lines:** ~85
**Dependencies:** None
**External Usage:** 2 test files (controller_test.zig, input_integration_test.zig)
**Risk:** LOW - tests use public API only

**Decision:** This belongs in `src/input/` alongside keyboard mapping.

#### 8. **Emulation Logic** → `EmulationLogic.zig`
```zig
// Lines 708-821 (orchestration functions)

pub fn stepPpuCycle(state: *EmulationState) PpuCycleResult { ... }
pub fn stepCpuCycle(state: *EmulationState) CpuCycleResult { ... }
pub fn stepApuCycle(state: *EmulationState) ApuCycleResult { ... }
pub fn applyPpuCycleResult(state: *EmulationState, result: PpuCycleResult) void { ... }
pub fn pollMapperIrq(state: *EmulationState) bool { ... }
pub fn refreshPpuNmiLevel(state: *EmulationState) void { ... }
```

**Lines:** ~120
**Dependencies:** EmulationState, PpuRuntime, CpuLogic, ApuLogic
**Risk:** LOW - internal to emulation loop

**Note:** `tick()` stays in EmulationState as orchestrator, calls EmulationLogic helpers.

#### 9. **CPU Execution Logic** → `cpu/ExecutionLogic.zig`
```zig
// Lines 1192-1751 (executeCpuCycle function)
// Lines 832-1188 (microstep helpers)

pub fn executeCpuCycle(state: *EmulationState) void { ... }

// Or break into smaller functions:
pub fn handleInterruptSequence(state: *EmulationState) void { ... }
pub fn handleOpcodeFetch(state: *EmulationState) void { ... }
pub fn handleAddressingCycle(state: *EmulationState) void { ... }
pub fn handleExecuteCycle(state: *EmulationState) void { ... }

// Microsteps module
pub const Microsteps = struct {
    pub fn fetchOperandLow(cpu: *CpuState, state: *EmulationState) bool { ... }
    pub fn fetchAbsLow(cpu: *CpuState, state: *EmulationState) bool { ... }
    // ... all 35+ microstep helpers
};
```

**Lines:** ~920 (!!!)
**Dependencies:** EmulationState, CpuState, CpuLogic, dispatch table
**Risk:** HIGH - core execution path, but well-tested

**Migration Strategy:**
1. Create `cpu/ExecutionLogic.zig` with same function signature
2. Move entire `executeCpuCycle()` body unchanged
3. Update EmulationState to call `CpuExecutionLogic.executeCpuCycle(&self)`
4. Run full test suite to verify
5. THEN refactor into smaller functions

---

## Proposed File Structure

### Current (1 file)
```
src/emulation/
  ├── State.zig (2,225 lines) 🚨
  ├── MasterClock.zig
  └── Ppu.zig
```

### Proposed (11 files)
```
src/emulation/
  ├── State.zig (150 lines) - Core state container + lifecycle
  ├── Logic.zig (120 lines) - Orchestration (step functions)
  ├── BusState.zig (15 lines) - Bus state structure
  ├── BusLogic.zig (280 lines) - Bus routing logic
  ├── CycleResults.zig (20 lines) - Return types
  ├── MasterClock.zig (existing)
  ├── Ppu.zig (existing)
  └── dma/
      ├── OamDma.zig (80 lines) - OAM DMA state + logic
      └── DmcDma.zig (80 lines) - DMC DMA state + logic

src/cpu/
  ├── State.zig (existing)
  ├── Logic.zig (existing)
  ├── ExecutionLogic.zig (600 lines) - executeCpuCycle + breakdown
  ├── Microsteps.zig (320 lines) - All addressing microsteps
  └── ... (existing files)

src/input/
  ├── ControllerState.zig (85 lines) - NES controller emulation
  ├── ButtonState.zig (existing)
  └── KeyboardMapper.zig (existing)
```

**Total:** 2,225 lines → 11 focused files averaging ~200 lines each

**Benefits:**
- Each file has single responsibility
- Clear module boundaries
- Testable in isolation
- Easier to understand and modify
- Follows existing State/Logic pattern

---

## API Stability Assessment

### Core Public API (STABLE - used everywhere)

**Zero-Risk Functions (pure data/lifecycle):**
```zig
EmulationState.init() → 40+ files
EmulationState.deinit() → 40+ files
EmulationState.reset() → 35+ files
EmulationState.loadCartridge() → 20+ files
EmulationState.unloadCartridge() → 5+ files
```

**Medium-Risk Functions (can be delegation wrappers):**
```zig
EmulationState.busRead() → 30+ files
EmulationState.busWrite() → 30+ files
EmulationState.busRead16() → 10+ files
EmulationState.busRead16Bug() → 5+ files
EmulationState.peekMemory() → 5+ files
EmulationState.tick() → 15+ files
EmulationState.emulateFrame() → 10+ files
EmulationState.emulateCpuCycles() → 8+ files
```

**Strategy:** Keep inline delegation wrappers in EmulationState for backward compatibility.

### Test-Only Public API (SEMI-STABLE)

**Can be changed with test updates:**
```zig
EmulationState.tickCpu() → 1 test file
EmulationState.tickCpuWithClock() → tests only
EmulationState.tickDmcDma() → 1 test file
EmulationState.debuggerIsPaused() → 2 files
EmulationState.syncDerivedSignals() → tests only
```

**Strategy:** Mark as `pub(test)` or move to test helpers module.

### Internal Implementation (UNSTABLE)

**NOT part of public API:**
```zig
All fn (non-pub) functions → Can be moved freely
executeCpuCycle() → Internal to tick()
stepPpuCycle/stepCpuCycle/stepApuCycle() → Internal to tick()
All microstep helpers → Internal to executeCpuCycle()
DMA tick functions → Internal to step functions
```

**Strategy:** Extract without API changes - zero external impact.

---

## Refactoring Recommendations

### Phase 1: Zero-Risk Extractions (Week 1)

**Goal:** Extract pure data structures with zero API changes.

#### Step 1.1: Extract Result Types
```bash
# Create CycleResults.zig
# Lines 30-45 → src/emulation/CycleResults.zig
# Update imports in State.zig
# Run: zig build test
```

**Risk:** ZERO - pure data structures
**Files Changed:** 2 (State.zig, new CycleResults.zig)
**Test Impact:** None (type aliases)

#### Step 1.2: Extract BusState
```bash
# Create BusState.zig
# Lines 49-58 → src/emulation/BusState.zig
# Update imports in State.zig, snapshot/state.zig
# Run: zig build test
```

**Risk:** LOW - only field access
**Files Changed:** 4 (State.zig, snapshot/state.zig, cpu/opcodes/mod.zig, new BusState.zig)
**Test Impact:** None (no API changes)

#### Step 1.3: Extract DMA State Machines
```bash
# Create dma/OamDma.zig
# Lines 63-102 → struct definition
# Lines 1782-1819 → tick() method
# Keep EmulationState.dma: OamDmaState field
# Run: zig build test
```

**Risk:** ZERO - internal to emulation
**Files Changed:** 2 (State.zig, new dma/OamDma.zig)
**Test Impact:** None

```bash
# Create dma/DmcDma.zig
# Lines 194-224 → struct definition
# Lines 1832-1881 → tick() method
# Update 1 test file: dpcm_dma_test.zig
# Run: zig build test
```

**Risk:** LOW - 1 test to update
**Files Changed:** 3 (State.zig, new dma/DmcDma.zig, tests/integration/dpcm_dma_test.zig)
**Test Impact:** 1 test file (trivial change)

#### Step 1.4: Extract ControllerState
```bash
# Create input/ControllerState.zig
# Lines 107-189 → entire struct
# Update 2 test files: controller_test.zig, input_integration_test.zig
# Run: zig build test
```

**Risk:** LOW - tests only use public API
**Files Changed:** 4 (State.zig, new input/ControllerState.zig, 2 test files)
**Test Impact:** 2 test files (import changes only)

**Phase 1 Result:** 2,225 lines → 1,700 lines (24% reduction)
**Modules Created:** 5 (CycleResults, BusState, OamDma, DmcDma, ControllerState)
**Risk Level:** MINIMAL
**Time Estimate:** 2-3 days

### Phase 2: Medium-Risk Extractions (Week 2)

**Goal:** Extract logic modules with delegation wrappers for API compatibility.

#### Step 2.1: Extract BusLogic
```bash
# Create BusLogic.zig
# Lines 381-649 → pure functions
# Add inline delegation wrappers to EmulationState:
#   pub inline fn busRead(self: *Self, addr: u16) u8 {
#       return BusLogic.busRead(self, addr);
#   }
# Run: zig build test
```

**Risk:** MEDIUM - 40+ files call bus functions
**Files Changed:** 2 (State.zig, new BusLogic.zig)
**Test Impact:** None (delegation wrappers preserve API)
**Performance:** Zero overhead (inline functions)

#### Step 2.2: Extract EmulationLogic
```bash
# Create EmulationLogic.zig
# Lines 708-821 → step functions + helpers
# Update tick() to call EmulationLogic functions
# Run: zig build test
```

**Risk:** LOW - internal to tick()
**Files Changed:** 2 (State.zig, new EmulationLogic.zig)
**Test Impact:** None (tick() API unchanged)

**Phase 2 Result:** 1,700 lines → 1,300 lines (23% reduction)
**Modules Created:** 2 (BusLogic, EmulationLogic)
**Risk Level:** MODERATE
**Time Estimate:** 3-4 days

### Phase 3: High-Risk Extractions (Week 3)

**Goal:** Extract CPU execution logic (the monster function).

#### Step 3.1: Extract CPU Microsteps
```bash
# Create cpu/Microsteps.zig
# Lines 832-1188 → all microstep helpers
# Update executeCpuCycle() to call Microsteps functions
# Run: zig build test
```

**Risk:** MEDIUM - core execution path
**Files Changed:** 2 (State.zig, new cpu/Microsteps.zig)
**Test Impact:** None (internal to executeCpuCycle)
**Validation:** Run full test suite + AccuracyCoin

#### Step 3.2: Extract CPU ExecutionLogic
```bash
# Create cpu/ExecutionLogic.zig
# Lines 1192-1751 → executeCpuCycle() function
# EmulationState.executeCpuCycle() → delegation wrapper
# Run: zig build test
```

**Risk:** HIGH - 559-line monster function
**Files Changed:** 2 (State.zig, new cpu/ExecutionLogic.zig)
**Test Impact:** None (internal to stepCpuCycle)
**Validation:** Run full test suite + AccuracyCoin + manual testing

#### Step 3.3: Refactor executeCpuCycle() (OPTIONAL)
```bash
# Break executeCpuCycle into smaller functions:
#   - handleInterruptSequence()
#   - handleOpcodeFetch()
#   - handleAddressingCycle()
#   - handleExecuteCycle()
# Run: zig build test
```

**Risk:** HIGH - major refactoring
**Files Changed:** 1 (cpu/ExecutionLogic.zig)
**Test Impact:** Potential timing changes
**Validation:** Run full test suite + AccuracyCoin + regression testing

**Phase 3 Result:** 1,300 lines → 150 lines (88% reduction from original!)
**Modules Created:** 2 (cpu/Microsteps, cpu/ExecutionLogic)
**Risk Level:** HIGH
**Time Estimate:** 5-7 days

### Phase 4: Polish & Documentation (Week 4)

**Goal:** Clean up, optimize, and document new architecture.

```bash
# Update CLAUDE.md with new structure
# Add module documentation to each new file
# Update architecture docs
# Consider moving tests to separate files
# Review inline delegation wrappers - can any be removed?
# Run benchmarks to verify zero performance regression
```

**Risk:** MINIMAL
**Time Estimate:** 2-3 days

---

## Risk Assessment Summary

### Zero-Risk Changes (Safe to do immediately)
- Extract CycleResults.zig ✅
- Extract BusState.zig ✅
- Extract dma/OamDma.zig ✅

### Low-Risk Changes (Minimal testing required)
- Extract dma/DmcDma.zig (1 test update)
- Extract input/ControllerState.zig (2 test updates)
- Extract EmulationLogic.zig (internal helpers)

### Medium-Risk Changes (Comprehensive testing required)
- Extract BusLogic.zig (40+ files call it, but delegation wrappers preserve API)
- Extract cpu/Microsteps.zig (core execution path, but well-encapsulated)

### High-Risk Changes (Full regression testing required)
- Extract cpu/ExecutionLogic.zig (559-line monster, core emulation loop)
- Refactor executeCpuCycle() into smaller functions (major structural change)

**Mitigation Strategies:**
1. Make one change at a time
2. Run full test suite after each change (939/947 tests must still pass)
3. Run AccuracyCoin test after each change (must stay PASSING ✅)
4. Use git for easy rollback
5. Keep delegation wrappers for backward compatibility
6. Tag releases before and after refactoring

---

## Breaking Changes Assessment

### Public API Changes: NONE

**Strategy:** All public functions remain in EmulationState as inline delegation wrappers.

**Example:**
```zig
// Before refactoring
pub inline fn busRead(self: *EmulationState, address: u16) u8 {
    const cart_ptr = self.cartPtr();
    const value = switch (address) {
        0x0000...0x1FFF => self.bus.ram[address & 0x7FF],
        // ... 60 more lines
    };
    self.bus.open_bus = value;
    return value;
}

// After refactoring
pub inline fn busRead(self: *EmulationState, address: u16) u8 {
    return BusLogic.busRead(self, address);
}
```

**Benefits:**
- Zero API changes for external callers
- Zero performance overhead (inline expansion)
- Internal implementation can be refactored freely
- Can deprecate wrappers later if desired

### Test API Changes: MINIMAL

**Changes Required:**
1. `tickDmcDma()` - 1 test file update (dpcm_dma_test.zig)
   - Change: `state.tickDmcDma()` → `state.dmc_dma.tick(&state)`
2. ControllerState - 2 test files update (import path changes only)
3. BusState - 3 test files update (import path changes only)

**Total Impact:** 6 test files, all trivial import/call site changes

### Internal Implementation Changes: EXTENSIVE

**Functions Moved (all `fn`, not `pub fn`):**
- 35+ microstep helpers → cpu/Microsteps.zig
- executeCpuCycle() → cpu/ExecutionLogic.zig
- stepPpuCycle/stepCpuCycle/stepApuCycle → EmulationLogic.zig
- tickDma/tickDmcDma → dma modules
- Bus routing logic → BusLogic.zig

**Impact:** Zero - these are all private implementation details.

---

## Performance Considerations

### Inline Function Preservation

**Critical:** All hot-path functions must remain `inline` to avoid call overhead.

**Hot Path Functions:**
- `busRead()` - called every CPU cycle
- `busWrite()` - called every CPU cycle
- `tick()` - called 89,342 times per frame
- All microstep helpers - called multiple times per instruction

**Strategy:** Use `pub inline fn` for delegation wrappers to ensure zero overhead.

### Zero-Cost Abstraction Verification

**After refactoring, verify:**
```bash
zig build bench-release
# Compare before/after performance
# Frame time should be identical (±1%)
# Memory usage should be identical
```

**Benchmark Targets:**
- Frame emulation time: ~280μs (current)
- CPU cycle emulation: ~9ns per cycle (current)
- Memory footprint: ~100KB per EmulationState (current)

**If performance regresses:**
1. Check that inline functions are actually inlined (review assembly)
2. Move hot functions back to EmulationState
3. Consider comptime function pointers for indirection

---

## Validation Checklist

### After Each Extraction

- [ ] `zig build test` - All 939/947 tests still pass
- [ ] `zig build test-integration` - Integration tests pass
- [ ] AccuracyCoin test still passes ✅
- [ ] No new compiler warnings
- [ ] Code compiles with `zig build -Doptimize=ReleaseFast`
- [ ] Benchmarks show no regression (±1%)

### Before Merge

- [ ] All phases complete
- [ ] Documentation updated (CLAUDE.md, architecture docs)
- [ ] Git history is clean (meaningful commit messages)
- [ ] PR description explains changes and rationale
- [ ] Code review by maintainer
- [ ] Final full test suite run
- [ ] Final AccuracyCoin run
- [ ] Tag release for easy rollback

---

## Conclusion

### Current State: CRITICAL

- 2,225 lines in single file
- 77 functions with 1 monster (559 lines)
- 6+ distinct responsibilities mixed together
- Impossible to understand without extensive context

### Recommended Action: IMMEDIATE REFACTORING

**Estimated Effort:** 3-4 weeks for complete refactoring
**Risk Level:** MEDIUM (with proper validation)
**Reward:** EXTREME - maintainability, testability, cognitive load reduction

### Prioritized Phases

1. **Week 1 (Phase 1):** Zero-risk extractions - 24% reduction, minimal risk
2. **Week 2 (Phase 2):** Logic extractions - 47% reduction, moderate risk
3. **Week 3 (Phase 3):** CPU execution - 88% reduction, high risk
4. **Week 4 (Phase 4):** Polish & docs - completion

### Success Criteria

✅ All 939/947 tests still pass
✅ AccuracyCoin test still passes
✅ Zero performance regression
✅ Each file < 350 lines
✅ Each function < 100 lines
✅ Clear module boundaries
✅ Single responsibility per module
✅ Zero breaking API changes

### Final Recommendation

**PROCEED WITH REFACTORING** - The technical debt is too high to ignore. This file is a maintenance nightmare and will only get worse. Execute Phase 1 immediately (zero risk), then evaluate results before proceeding to higher-risk phases.

The existing test coverage (939/947 tests, AccuracyCoin passing) provides excellent validation for refactoring. With careful extraction and comprehensive testing, this can be done safely.

**Defer or Proceed?** PROCEED - but do it incrementally with validation at each step.

---

**Report Generated:** 2025-10-09
**Analyst:** Claude Code (Architecture Reviewer)
**Severity:** CRITICAL - Immediate Action Required
**Confidence:** HIGH - Based on comprehensive code analysis
