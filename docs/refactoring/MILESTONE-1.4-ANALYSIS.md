# Milestone 1.4: Extract CPU Execution - Detailed Analysis

**Date:** 2025-10-09
**Status:** Research Phase
**Risk Level:** 🔴 HIGH (Core execution logic, 559 lines)

---

## Executive Summary

**Target Function:** `executeCpuCycle()` (lines 669-1228, 559 lines)
**Location:** `/home/colin/Development/RAMBO/src/emulation/State.zig`
**Complexity:** VERY HIGH - State machine with complex control flow
**Side Effects:** EXTENSIVE - Multiple subsystems with ordering dependencies

### Key Challenges

1. **Monster Function:** 559 lines of complex state machine logic
2. **Side Effects:** busRead/busWrite with debugger hooks, PPU sync, open bus updates
3. **Control Flow:** Multiple nested switches with early returns
4. **State Dependencies:** CPU state, DMA state, debugger state, PPU warmup
5. **Memory Ownership:** All access through `self: *EmulationState` pointer
6. **Timing Critical:** Exact cycle ordering required for hardware accuracy

---

## Function Call Graph

```
stepCpuCycle() [447-472] (25 lines) - Entry point
├── ppu.warmup_complete check/set
├── cpu.halted check
├── debuggerShouldHalt() check
├── dmc_dma.rdy_low check
│   └── tickDmcDma() [1309-1358]
├── dma.active check
│   └── tickDma() [1259-1307]
├── executeCpuCycle() [669-1228] (559 lines) ⚠️ TARGET
│   ├── PPU warmup check/set (duplicated from stepCpuCycle)
│   ├── cpu.halted check (duplicated from stepCpuCycle)
│   ├── debuggerShouldHalt() check (duplicated from stepCpuCycle)
│   ├── .interrupt_sequence state handler [709-757]
│   │   ├── busRead(pc) - dummy read
│   │   ├── pushPch() - CpuMicrosteps wrapper
│   │   ├── pushPcl() - CpuMicrosteps wrapper
│   │   ├── pushStatusInterrupt() - CpuMicrosteps wrapper
│   │   ├── busRead(0xFFFA-0xFFFD) - vector fetch
│   │   └── pc update
│   ├── .fetch_opcode state handler [760-786]
│   │   ├── busRead(pc) - opcode fetch
│   │   ├── CpuModule.dispatch.DISPATCH_TABLE lookup
│   │   └── State transition logic
│   ├── .fetch_operand_low state handler [789-1136] (347 lines!)
│   │   ├── Control flow opcodes (JSR/RTS/RTI/BRK/PHA/PLA/PHP/PLP) [801-867]
│   │   │   └── 38 CpuMicrosteps wrapper calls
│   │   ├── Addressing mode microsteps [868-1032]
│   │   │   ├── .zero_page [869-883]
│   │   │   ├── .zero_page_x [885-901]
│   │   │   ├── .zero_page_y [903-907]
│   │   │   ├── .absolute [908-924]
│   │   │   ├── .absolute_x [926-947]
│   │   │   ├── .absolute_y [949-969]
│   │   │   ├── .indexed_indirect [971-992]
│   │   │   ├── .indirect_indexed [994-1016]
│   │   │   ├── .relative [1018-1023]
│   │   │   └── .indirect [1024-1029]
│   │   ├── instruction_cycle increment [1034]
│   │   ├── Early completion check [1036-1041]
│   │   ├── Addressing done check [1046-1110]
│   │   └── Fallthrough logic for indexed modes [1115-1135]
│   └── .execute state handler [1139-1227] (88 lines)
│       ├── Operand extraction [1143-1177]
│       │   └── Multiple busRead calls based on addressing mode
│       ├── PC increment for immediate mode [1180-1182]
│       ├── effective_address setup [1185-1193]
│       ├── CpuLogic.toCoreState() [1196]
│       ├── entry.operation() call (PURE FUNCTION) [1199]
│       └── Result application [1202-1223]
│           ├── Register updates (a, x, y, sp, pc, flags)
│           ├── busWrite() for memory writes
│           ├── busWrite() for stack pushes
│           └── cpu.halted flag
└── pollMapperIrq() [474-479]
```

---

## Side Effects Analysis

### 1. Bus Operations (CRITICAL - Must Maintain Exact Ordering)

**busRead() side effects (via BusRouting module):**
- Updates `self.bus.open_bus` with read value
- Triggers debugger memory access tracking
- PPU register reads ($2002/$2004/$2007) have state side effects
- APU register reads ($4015) clear IRQ flags
- Controller reads ($4016/$4017) advance shift registers
- Cartridge mapper reads may trigger IRQ state changes

**busWrite() side effects (via BusRouting module):**
- Updates `self.bus.open_bus` with written value
- Triggers debugger memory access tracking
- PPU register writes ($2000-$2007) modify PPU state
- APU register writes ($4000-$4017) modify APU state
- Controller writes ($4016) trigger strobe state changes
- OAM DMA write ($4014) triggers DMA state
- Cartridge mapper writes modify mapper state

### 2. CPU State Mutations

**Direct CPU state modifications:**
```zig
self.cpu.opcode = ...              // [762] fetch_opcode
self.cpu.data_bus = ...            // [762, 1211, 1217] bus value tracking
self.cpu.pc += 1                   // [763] PC increment
self.cpu.address_mode = ...        // [766] addressing mode
self.cpu.state = ...               // [751, 780, 1038, 1113, 1225] state machine transitions
self.cpu.instruction_cycle = ...   // [752, 781, 1034, 1039, 1226] cycle tracking
self.cpu.page_crossed = ...        // [46, 59, 133, 325] via CpuMicrosteps
self.cpu.pending_interrupt = ...   // [744] interrupt handling
self.cpu.halted = ...              // [1221] JAM/KIL opcodes
self.cpu.a/x/y/sp/pc/p = ...       // [1202-1207] register updates from opcode execution
```

**Via CpuMicrosteps (38 functions):**
- All `fetchXxx()` functions modify cpu.operand_low/high/pc
- All `pushXxx()` functions modify cpu.sp and call busWrite
- All `pullXxx()` functions modify cpu.sp and read via busRead
- All `calcXxx()` functions modify cpu.effective_address/page_crossed/temp_value
- RMW functions modify cpu.temp_value
- Branch functions modify cpu.pc/page_crossed

### 3. PPU State Mutations

**Direct PPU modifications:**
```zig
self.ppu.warmup_complete = true    // [677] after 29,658 CPU cycles
```

**Indirect via busRead/busWrite to $2000-$2007:**
- PPU register reads/writes trigger various PPU state changes
- These happen inside busRead/busWrite via PpuLogic routing

### 4. Debugger State

**Debugger interactions:**
```zig
self.debuggerShouldHalt()          // [685] checks breakpoints/watchpoints
self.debug_break_occurred = true   // [701] signals breakpoint hit
```

**Via busRead/busWrite:**
```zig
self.debuggerCheckMemoryAccess()   // Called in busRead/busWrite wrappers
```

### 5. DMA State (via stepCpuCycle, not executeCpuCycle)

**OAM DMA:**
- Triggered by write to $4014 (happens in busWrite)
- `self.dma.active` flag checked in stepCpuCycle
- `tickDma()` reads/writes memory during DMA

**DMC DMA:**
- Triggered by APU DMC sample fetch
- `self.dmc_dma.rdy_low` flag checked in stepCpuCycle
- `tickDmcDma()` reads memory and loads into APU

### 6. APU State (Indirect)

**Via stepApuCycle (not in CPU execution):**
- Frame counter IRQ
- DMC sample fetch triggering

**Via busWrite to $4000-$4017:**
- APU register writes modify channel states

### 7. Cartridge/Mapper State

**Via pollMapperIrq():**
```zig
self.cart.tickIrq()                // [476] mapper IRQ counter tick
```

**Via busRead/busWrite:**
- Mapper register reads/writes modify mapper state
- Some mappers track A12 transitions for IRQ (MMC3)

---

## Memory Ownership Analysis

### Current Ownership Pattern

**All access flows through `self: *EmulationState`:**

```
EmulationState
├── cpu: CpuState              (owned)
├── ppu: PpuState              (owned)
├── apu: ApuState              (owned)
├── bus: BusState              (owned)
│   └── ram: [2048]u8          (owned array)
├── dma: OamDma                (owned)
├── dmc_dma: DmcDma            (owned)
├── cart: ?AnyCartridge        (owned optional)
├── debugger: ?Debugger        (owned optional)
├── controllers: [2]ControllerState (owned array)
└── clock: MasterClock         (owned)
```

**NO memory references are grabbed or passed:**
- All mutations happen through `self.*` field access
- All function calls pass `self: *EmulationState` pointer
- No pointers to subcomponents are extracted and passed around
- CpuMicrosteps functions use `state: anytype` and access `state.cpu.*` directly

### Ownership Guarantees

✅ **Single Ownership:** EmulationState owns all components
✅ **No Aliasing:** No pointers to subcomponents passed to other functions
✅ **Lifetime Safety:** All lifetimes tied to EmulationState lifetime
✅ **RT-Safe:** No heap allocations during execution

---

## Control Flow Complexity

### State Machine Structure

```
CPU State Machine (self.cpu.state):
├── .fetch_opcode        → fetch next instruction opcode
├── .fetch_operand_low   → addressing mode microsteps (1-8 cycles)
├── .execute             → opcode execution (1 cycle)
└── .interrupt_sequence  → hardware interrupt handling (7 cycles)
```

### Conditional Branches

**executeCpuCycle has:**
- 3 early returns (halted, debugger, warmup check) [681-687]
- 1 interrupt sequence handler (48 lines) [709-757]
- 1 fetch opcode handler (26 lines) [760-786]
- 1 addressing handler (347 lines!) [789-1136]
  - 66 different control flow paths (8 addressing modes × 2 RMW variants + 8 control flow opcodes)
  - Multiple early return points
  - Fallthrough logic for indexed modes
- 1 execute handler (88 lines) [1139-1227]

### Cyclomatic Complexity

**Estimated McCabe Complexity:** ~120+ (EXTREMELY HIGH)
- Normal functions: 1-10 (simple)
- Complex functions: 10-20 (needs refactoring)
- **This function: 120+ (UNMAINTAINABLE)**

---

## Critical Timing Dependencies

### 1. busRead/busWrite Ordering

**MUST preserve exact order:**
```zig
// Example: Absolute,X addressing with page cross (5 cycles)
Cycle 1: opcode fetch [762]            busRead(pc)
Cycle 2: fetchAbsLow [920]             busRead(pc)
Cycle 3: fetchAbsHigh [921]            busRead(pc)
Cycle 4: calcAbsoluteX [943]           busRead(dummy_addr)  ← CRITICAL: dummy read
Cycle 5: fixHighByte [944]             busRead(real_addr)   ← CRITICAL: real read
Cycle 6: execute [1168]                busRead(addr)        ← Wait, this is WRONG!
```

**NOTE:** There's a +1 cycle deviation for indexed reads mentioned in CLAUDE.md line 89-95:
> Hardware: 4 cycles (dummy read IS the actual read)
> Implementation: 5 cycles (separate addressing + execute states)

### 2. PPU Synchronization

**PPU ticks 3 times per CPU cycle:**
- Must maintain exact cycle count for PPU timing
- PPU register accesses during specific PPU cycles have special behavior

### 3. Interrupt Polling

**Checked at specific points:**
- Start of fetch_opcode state [690-705]
- NOT checked during mid-instruction
- NMI edge detection vs IRQ level detection

### 4. DMA Hijacking

**CPU frozen during DMA:**
- Checked in stepCpuCycle before executeCpuCycle [465-468, 460-463]
- Must not execute CPU operations during DMA

---

## Extraction Strategy Options

### Option A: Extract as Pure Logic Module (PREFERRED)

**Create:** `src/emulation/cpu/execution.zig`

**Structure:**
```zig
// Pure function - all side effects through state parameter
pub fn executeCycle(state: anytype) void {
    // Move entire executeCpuCycle body here
    // Keep using state.busRead/busWrite (side effects explicit)
    // Keep using CpuMicrosteps wrappers
}
```

**Pros:**
- Minimal changes - just move code
- Maintains exact semantics
- Side effects remain explicit through state parameter
- No ownership issues (still uses `anytype` duck typing)

**Cons:**
- Still a 559-line monster function
- Doesn't improve complexity
- Just moves the problem

### Option B: Decompose into Handler Functions

**Create:** `src/emulation/cpu/execution.zig`

**Structure:**
```zig
pub fn executeCycle(state: anytype) void {
    // Top-level dispatcher
    switch (state.cpu.state) {
        .interrupt_sequence => handleInterruptSequence(state),
        .fetch_opcode => handleFetchOpcode(state),
        .fetch_operand_low => handleAddressing(state),
        .execute => handleExecute(state),
    }
}

fn handleInterruptSequence(state: anytype) void { ... }
fn handleFetchOpcode(state: anytype) void { ... }
fn handleAddressing(state: anytype) void { ... }
fn handleExecute(state: anytype) void { ... }
```

**Pros:**
- Better modularity (4 functions instead of 1)
- Easier to understand each phase
- Clear separation of concerns

**Cons:**
- More refactoring work
- More places for errors
- handleAddressing still ~350 lines

### Option C: Further Decomposition by Addressing Mode

**Create:** `src/emulation/cpu/execution.zig` + `src/emulation/cpu/addressing.zig`

**Structure:**
```zig
// execution.zig
pub fn executeCycle(state: anytype) void {
    switch (state.cpu.state) {
        .interrupt_sequence => handleInterruptSequence(state),
        .fetch_opcode => handleFetchOpcode(state),
        .fetch_operand_low => Addressing.handleCycle(state),
        .execute => handleExecute(state),
    }
}

// addressing.zig
pub fn handleCycle(state: anytype) void {
    const entry = CpuModule.dispatch.DISPATCH_TABLE[state.cpu.opcode];

    if (isControlFlow(state.cpu.opcode)) {
        handleControlFlowAddressing(state);
    } else {
        handleStandardAddressing(state);
    }
}

fn handleControlFlowAddressing(state: anytype) void {
    switch (state.cpu.opcode) {
        0x20 => handleJsrAddressing(state),
        0x60 => handleRtsAddressing(state),
        ...
    }
}

fn handleStandardAddressing(state: anytype) void {
    const entry = CpuModule.dispatch.DISPATCH_TABLE[state.cpu.opcode];
    switch (entry.info.mode) {
        .zero_page => handleZeroPageAddressing(state, entry),
        .absolute_x => handleAbsoluteXAddressing(state, entry),
        ...
    }
}
```

**Pros:**
- Maximum modularity
- Each function <100 lines
- Clear separation of concerns
- Easier testing

**Cons:**
- MOST refactoring work
- HIGHEST risk of introducing bugs
- More files to track
- May fragment control flow understanding

---

## Recommended Approach

### Phase 1: Extract with Minimal Changes (SAFE)

**Goal:** Get executeCpuCycle out of State.zig without decomposing

1. Create `src/emulation/cpu/execution.zig`
2. Move executeCpuCycle → executeCycle (one function, 559 lines)
3. Update State.zig to call CpuExecution.executeCycle(self)
4. Run tests → verify 940/950 baseline
5. Commit

**Estimated Time:** 30 minutes
**Risk:** LOW (minimal changes)
**Benefit:** -559 lines from State.zig

### Phase 2: Decompose Handler Functions (MEDIUM RISK)

**Goal:** Split into 4 handler functions

1. Extract handleInterruptSequence (48 lines)
2. Extract handleFetchOpcode (26 lines)
3. Extract handleAddressing (347 lines) - still big!
4. Extract handleExecute (88 lines)
5. Update executeCycle to dispatch
6. Run tests → verify 940/950 baseline
7. Commit

**Estimated Time:** 2 hours
**Risk:** MEDIUM (control flow changes)
**Benefit:** Better modularity

### Phase 3: Decompose Addressing (HIGH RISK - FUTURE)

**Goal:** Split handleAddressing into per-mode functions

**Defer to Phase 2 of refactoring plan**
- Too risky for Phase 1
- Requires careful analysis of each addressing mode
- Many edge cases and timing dependencies

---

## Side Effect Isolation Strategy

### Current State

✅ **All side effects flow through state parameter:**
- `state.busRead()` → BusRouting → debugger hooks → PPU/APU/cartridge
- `state.busWrite()` → BusRouting → debugger hooks → PPU/APU/cartridge
- `state.cpu.*` mutations → direct field access
- `state.ppu.*` mutations → direct field access

✅ **No memory references grabbed:**
- No `const cpu_ptr = &state.cpu;` and passing around
- All access via `state.cpu.*` field syntax

✅ **No aliasing:**
- Single ownership through EmulationState
- No multiple pointers to same data

### Extraction Requirements

**MUST maintain:**
1. All busRead/busWrite calls in exact order
2. All state mutations in exact order
3. No grabbing of subcomponent pointers
4. All access through state parameter
5. Use `pub fn` (NOT inline) for proper isolation

**MUST NOT:**
1. Inline any functions with side effects
2. Reorder any busRead/busWrite calls
3. Create pointers to state.cpu/ppu/bus fields
4. Pass subcomponent references to other functions

---

## Testing Strategy

### Baseline Validation

**Current Baseline:** 940/950 tests passing

**Critical Tests:**
1. `ppustatus_polling_test` - PPU timing (currently 8/10 passing)
2. `emulation.State test` - Frame timing (currently 180/181 passing)
3. `accuracycoin_execution_test` - Integration (currently 5/7 passing)
4. CPU instruction tests - All passing
5. Addressing mode tests - All passing

### Validation Steps

**After each change:**
1. `zig build test` → must show 940/950
2. Check specific test failures match known issues
3. Test with Bomberman ROM: `timeout 5 zig-out/bin/RAMBO "tests/data/Bomberman/..."`
4. No new failures allowed

---

## Questions and Concerns

### 1. Duplication in executeCpuCycle

**Issue:** Lines 673-687 duplicate checks from stepCpuCycle:
```zig
// stepCpuCycle [447-472]
if (!self.ppu.warmup_complete and self.clock.cpuCycles() >= 29658) { ... }
if (self.cpu.halted) { return .{}; }
if (self.debuggerShouldHalt()) { return .{}; }

// executeCpuCycle [669-687] - DUPLICATED
if (!self.ppu.warmup_complete and self.clock.cpuCycles() >= 29658) { ... }
if (self.cpu.halted) { return; }
if (self.debuggerShouldHalt()) { return; }
```

**Question:** Should we remove duplication and rely on stepCpuCycle checks?

**Analysis:**
- stepCpuCycle is the only caller of executeCpuCycle in production
- Tests might call executeCpuCycle directly? Need to check.
- If tests don't call it directly, can remove duplication

**Recommendation:** Keep duplication for Phase 1 (safety), remove in Phase 2

### 2. +1 Cycle Deviation

**Issue:** Indexed reads have timing deviation (CLAUDE.md:89-95)

**Question:** Is this related to the fallthrough logic at lines 1115-1135?

**Analysis:**
```zig
const should_fallthrough = !dispatch_entry.is_rmw and
    (self.cpu.address_mode == .absolute_x or
        self.cpu.address_mode == .absolute_y or
        self.cpu.address_mode == .indirect_indexed);
```

This makes indexed modes execute in same cycle as final addressing.

**Recommendation:** Document this as known timing deviation, don't change

### 3. Control Flow Opcodes Special Handling

**Issue:** Control flow opcodes (JSR/RTS/RTI/BRK/PHA/PLA/PHP/PLP) have custom sequences

**Question:** Why are they handled in addressing state instead of having separate state?

**Analysis:**
- They reuse the .fetch_operand_low state for their microstep sequences
- This overloads the state machine meaning
- Could be cleaner with separate states (.jsr_sequence, .rts_sequence, etc.)

**Recommendation:** Keep current design for Phase 1, consider redesign in Phase 2

### 4. Operand Extraction Complexity

**Issue:** Lines 1143-1177 have complex operand extraction logic with busRead calls

**Question:** Could this be simplified or extracted to a function?

**Analysis:**
- Operand extraction has different logic per addressing mode
- Some modes read from memory (busRead), others use temp_value
- Write-only instructions (STA/STX/STY) skip the read
- This is a good candidate for extraction

**Recommendation:** Extract to `getOperand(state, entry) u8` function in Phase 2

### 5. Result Application Pattern

**Issue:** Lines 1202-1223 apply opcode result with optional fields

**Question:** Is this the best pattern for applying deltas?

**Analysis:**
```zig
const result = entry.operation(core_state, operand);
if (result.a) |new_a| self.cpu.a = new_a;
if (result.x) |new_x| self.cpu.x = new_x;
// ...
```

This is clean and explicit. No changes needed.

**Recommendation:** Keep current pattern

---

## Risk Assessment

### High Risk Areas

1. **Interrupt sequence handler** [709-757]
   - Complex cycle-based logic
   - Multiple busRead calls
   - Vector address selection
   - State machine transitions

2. **Addressing mode dispatcher** [789-1136]
   - 347 lines of nested switches
   - 66 different code paths
   - RMW vs non-RMW logic
   - Page crossing handling
   - Fallthrough logic

3. **Operand extraction** [1143-1177]
   - Multiple busRead calls
   - Write-only instruction special case
   - Indexed mode temp_value usage

### Medium Risk Areas

1. **Fetch opcode handler** [760-786]
   - Dispatch table lookup
   - State machine transition
   - Control flow detection

2. **Execute handler** [1139-1227]
   - Operand extraction
   - Pure function call
   - Result application

### Low Risk Areas

1. **Early return checks** [673-687]
   - Simple boolean checks
   - No side effects

---

## Potential Issues

### 1. State Machine Fragmentation

**Risk:** Extracting to separate module may make state machine harder to understand

**Mitigation:** Keep all handlers in same file (execution.zig), clear comments

### 2. Timing Regression

**Risk:** Any reordering of operations could break cycle accuracy

**Mitigation:**
- No reordering in Phase 1
- Extensive testing after each change
- Compare before/after with instruction traces

### 3. Debugger Integration

**Risk:** Debugger hooks in busRead/busWrite must maintain exact timing

**Mitigation:**
- Don't change busRead/busWrite calls
- Keep debuggerShouldHalt() in same positions

### 4. Test Coverage Gaps

**Risk:** Tests may not catch subtle timing issues

**Mitigation:**
- Run AccuracyCoin ROM (currently passing)
- Test with commercial ROMs (Bomberman, etc.)
- Manual verification of critical behaviors

---

## Final Recommendation

### Approach for Milestone 1.4

**Use Option A (Extract as Pure Logic Module) for Phase 1:**

1. Create `src/emulation/cpu/execution.zig`
2. Move executeCpuCycle → executeCycle (one function)
3. Add comprehensive documentation at top
4. State.zig wrapper: `fn executeCpuCycle(self: *EmulationState) void { CpuExecution.executeCycle(self); }`
5. Run tests → verify 940/950
6. Commit

**Result:**
- State.zig: 1,702 → 1,143 lines (-559 lines, -32.8%)
- New file: cpu/execution.zig (559 lines)
- Risk: LOW
- Time: 30 minutes

**Defer to Future:**
- Handler decomposition (Phase 2)
- Addressing mode splitting (Phase 2)
- State machine redesign (Phase 3?)

---

## Documentation Updates Needed

1. Update `PHASE-1-PROGRESS.md` with Milestone 1.4 start entry
2. Update architecture docs with cpu/execution.zig module
3. Add cross-references between execution.zig and microsteps.zig
4. Document known timing deviation in execution.zig header
5. Update `PHASE-1-DEVELOPMENT-GUIDE.md` with extraction notes

---

## Next Steps

**After review and approval:**

1. Create cpu/execution.zig with comprehensive header comment
2. Move executeCpuCycle function body
3. Update State.zig import and wrapper
4. Run full test suite
5. Test with Bomberman ROM
6. Update documentation
7. Git commit with detailed message

**Questions for user:**
1. Should we remove the duplicated checks (lines 673-687)?
2. Is the +1 cycle deviation acceptable for Phase 1?
3. Should we extract stepCpuCycle too, or just executeCpuCycle?
4. Any specific test cases to run beyond standard suite?
