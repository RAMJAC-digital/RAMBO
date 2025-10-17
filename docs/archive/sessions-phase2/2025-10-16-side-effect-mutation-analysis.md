# DMA System: Side Effect and Mutation Ordering Analysis
**Date:** 2025-10-16
**Analyst:** Code Review Agent
**Status:** Complete - Analysis Only (No Fixes Proposed)

---

## Executive Summary

This document catalogs ALL side effects and mutations in the DMA system, analyzes their ordering and scoping, identifies architectural violations, and establishes principles for correct side effect management.

**Critical Findings:**
1. Bus reads occurring in Query phase (violation)
2. "Pure" functions mutating state (documentation lies)
3. Direct field mutations bypassing encapsulation
4. Business logic embedded in data structures
5. Interleaved mutations across 3 different modules

**Impact:** Current architecture makes reasoning about state changes impossible and violates clean architecture principles established for rest of codebase.

---

## Complete Side Effect Catalog

### Definition: Side Effects
- Bus reads (`state.busRead()`) - Can trigger PPU/APU/cartridge state changes
- Bus writes (`state.busWrite()`) - Modifies memory-mapped I/O
- Any operation that affects external state beyond local variables

### Side Effects in DMA Flow

#### 1. Bus Read - Interrupted Byte Capture
**Location:** `execution.zig:156`
```zig
interrupted.byte_value = state.busRead(addr);
```
**Phase:** Query (VIOLATION - should be Execute)
**Justification:** None - this is pure architectural violation
**Frequency:** Once per pause event
**Mutates:** `bus.open_bus`, potentially PPU/APU state
**Order:** Happens DURING pause action determination

#### 2. Bus Read - OAM DMA Read Phase
**Location:** `actions.zig:108` (via `executeAction`)
```zig
state.dma.temp_value = state.busRead(addr);
```
**Phase:** Execute (CORRECT)
**Justification:** Single side effect during Execute phase
**Frequency:** 256 times per OAM DMA transfer
**Mutates:** `bus.open_bus`, `dma.temp_value`
**Order:** Happens AFTER action determined, BEFORE bookkeeping

#### 3. Bus Write - OAM Write Phase
**Location:** `actions.zig:113` (via `executeAction`)
```zig
state.ppu.oam[state.ppu.oam_addr] = state.dma.temp_value;
```
**Phase:** Execute (CORRECT)
**Justification:** Single side effect during Execute phase
**Frequency:** 256 times per OAM DMA transfer
**Mutates:** PPU OAM memory
**Order:** Happens AFTER action determined, BEFORE bookkeeping

#### 4. Bus Write - Duplication Write
**Location:** `actions.zig:118` (via `executeAction`)
```zig
state.ppu.oam[info.target_oam_addr] = info.byte_value;
```
**Phase:** Execute (CORRECT)
**Justification:** Single side effect during Execute phase
**Frequency:** Once per resume-with-duplication event
**Mutates:** PPU OAM memory
**Order:** Happens AFTER action determined, BEFORE bookkeeping

#### 5. Bus Read - DMC Sample Fetch
**Location:** `dma/logic.zig:72` (in `tickDmcDma`)
```zig
state.dmc_dma.sample_byte = state.busRead(address);
```
**Phase:** N/A (DMC has no 3-phase architecture)
**Justification:** DMC is simple enough to not need phases
**Frequency:** Once per DMC DMA cycle
**Mutates:** `bus.open_bus`, `dmc_dma.sample_byte`
**Order:** Happens during DMC tick, interleaved with OAM logic

#### 6. Bus Read - DMC Corruption Bug (NTSC)
**Location:** `dma/logic.zig:94, 99` (in `tickDmcDma`)
```zig
_ = state.busRead(last_addr);  // Repeat read for corruption
```
**Phase:** N/A
**Justification:** Hardware bug emulation
**Frequency:** 3 times per DMC DMA (idle cycles)
**Mutates:** `bus.open_bus`, potentially controller shift registers, PPU state
**Order:** Happens during DMC idle cycles

### Side Effect Summary Table

| Side Effect | File | Line | Phase | Correct? | Frequency |
|-------------|------|------|-------|----------|-----------|
| Bus read (interrupted byte) | execution.zig | 156 | Query | NO | 1/pause |
| Bus read (OAM source) | actions.zig | 108 | Execute | YES | 256/transfer |
| Bus write (OAM) | actions.zig | 113 | Execute | YES | 256/transfer |
| Bus write (duplication) | actions.zig | 118 | Execute | YES | 1/resume |
| Bus read (DMC sample) | logic.zig | 72 | N/A | N/A | 1/DMC |
| Bus read (DMC corruption) | logic.zig | 94,99 | N/A | N/A | 3/DMC |

**Violations:** 1 out of 6 side effects in wrong phase (16% violation rate)

---

## Complete Mutation Catalog

### Definition: Mutations
- Direct field assignments to any state structure
- Method calls that modify state
- Any operation that changes program state

### Mutations in Pause Event Flow

**Call Path:** `execution.zig:145-169`

```
stepCycle() → DMC rising edge detected
    ↓
DmaInteraction.shouldOamPause() [QUERY - pure ✓]
    ↓
DmaInteraction.handleDmcPausesOam() [QUERY - claims pure ✗]
    ↓ Returns PauseData
    ↓
execution.zig applies mutations:
```

#### Mutation 1: Ledger Pause Cycle
**Location:** `execution.zig:161`
```zig
state.dma_interaction_ledger.oam_pause_cycle = pause_data.pause_cycle;
```
**Scope:** DmaInteractionLedger
**Responsibility:** Timestamp recording
**Order:** 1st mutation (after query)
**Encapsulation:** Direct field access (VIOLATION)

#### Mutation 2: Ledger Interrupted State
**Location:** `execution.zig:162`
```zig
state.dma_interaction_ledger.interrupted_state = interrupted;
```
**Scope:** DmaInteractionLedger
**Responsibility:** State snapshot
**Order:** 2nd mutation
**Encapsulation:** Direct field access (VIOLATION)

#### Mutation 3: Ledger Duplication Flag
**Location:** `execution.zig:164`
```zig
state.dma_interaction_ledger.duplication_pending = true;
```
**Scope:** DmaInteractionLedger
**Responsibility:** Flag setting
**Order:** 3rd mutation (conditional)
**Encapsulation:** Direct field access (VIOLATION)

#### Mutation 4: OAM DMA Phase
**Location:** `execution.zig:168`
```zig
state.dma.phase = pause_data.pause_phase;
```
**Scope:** OamDma
**Responsibility:** State machine transition
**Order:** 4th mutation (after ledger updates)
**Encapsulation:** Direct field access (acceptable - state machine)

#### Hidden Mutation: Interrupted Byte Value
**Location:** `execution.zig:156`
```zig
interrupted.byte_value = state.busRead(addr);
```
**Scope:** Local variable (then copied to ledger)
**Responsibility:** Bus side effect + value capture
**Order:** DURING query phase (VIOLATION)
**Problem:** Should happen in Execute phase

#### Hidden Mutation: Interrupted OAM Address
**Location:** `execution.zig:157`
```zig
interrupted.oam_addr = state.ppu.oam_addr;
```
**Scope:** Local variable (then copied to ledger)
**Responsibility:** PPU state capture
**Order:** DURING query phase (VIOLATION)
**Problem:** Reading live PPU state during query

### Mutations in Resume Event Flow

**Call Path:** `execution.zig:185-193`

```
stepCycle() → OAM active path, DMC inactive
    ↓
DmaInteraction.shouldOamResume() [QUERY - pure ✓]
    ↓
DmaInteraction.handleOamResumes() [QUERY - pure ✓]
    ↓ Returns ResumeData
    ↓
execution.zig applies mutations:
```

#### Mutation 5: Ledger Resume Cycle
**Location:** `execution.zig:189`
```zig
state.dma_interaction_ledger.oam_resume_cycle = resume_data.resume_cycle;
```
**Scope:** DmaInteractionLedger
**Responsibility:** Timestamp recording
**Order:** 1st mutation (after query)
**Encapsulation:** Direct field access (VIOLATION)

#### Mutation 6: OAM DMA Phase (Resume)
**Location:** `execution.zig:192`
```zig
state.dma.phase = resume_data.resume_phase;
```
**Scope:** OamDma
**Responsibility:** State machine transition
**Order:** 2nd mutation
**Encapsulation:** Direct field access (acceptable)

### Mutations in Duplication Write

**Call Path:** `actions.zig:152-160` (in `updateBookkeeping`)

#### Mutation 7: PPU OAM Address Advance
**Location:** `actions.zig:156`
```zig
ppu_oam_addr.* +%= 1;
```
**Scope:** PPU
**Responsibility:** OAM pointer advancement
**Order:** After duplication write side effect
**Encapsulation:** Proper (passed as parameter)

#### Mutation 8: OAM DMA Phase (Duplication Complete)
**Location:** `actions.zig:159`
```zig
dma.phase = .resuming_normal;
```
**Scope:** OamDma
**Responsibility:** State machine transition
**Order:** After OAM address advance
**Encapsulation:** Proper (passed as parameter)

#### Mutation 9: Ledger Duplication Clear
**Location:** `actions.zig:160`
```zig
ledger.duplication_pending = false;
```
**Scope:** DmaInteractionLedger
**Responsibility:** Flag clearing
**Order:** After phase transition
**Encapsulation:** Direct field access (VIOLATION)

### Mutation Flow Diagram

```
┌─────────────────────────────────────────────────────────┐
│                    PAUSE EVENT FLOW                     │
└─────────────────────────────────────────────────────────┘

execution.zig:145  shouldOamPause() → true
                        ↓
execution.zig:146  handleDmcPausesOam()
                        ↓ [QUERY PHASE - should be pure]
                        │
execution.zig:156  ├──→ busRead(addr) ← SIDE EFFECT IN QUERY!
                        │
                        ├──→ interrupted.byte_value = ...
                        │
execution.zig:157  ├──→ interrupted.oam_addr = ppu.oam_addr
                        │
                        └──→ Returns PauseData
                        ↓
execution.zig:161  ledger.oam_pause_cycle = ... ← Mutation 1
                        ↓
execution.zig:162  ledger.interrupted_state = ... ← Mutation 2
                        ↓
execution.zig:164  ledger.duplication_pending = true ← Mutation 3
                        ↓
execution.zig:168  dma.phase = .paused_during_read ← Mutation 4

┌─────────────────────────────────────────────────────────┐
│                   RESUME EVENT FLOW                     │
└─────────────────────────────────────────────────────────┘

execution.zig:185  shouldOamResume() → true
                        ↓
execution.zig:186  handleOamResumes()
                        ↓ [QUERY PHASE - pure ✓]
                        │
                        └──→ Returns ResumeData
                        ↓
execution.zig:189  ledger.oam_resume_cycle = ... ← Mutation 5
                        ↓
execution.zig:192  dma.phase = .resuming_with_duplication ← Mutation 6
                        ↓
[Next tick]
logic.zig:32       determineAction() → duplication_write
                        ↓
actions.zig:118    executeAction() → OAM write ← SIDE EFFECT
                        ↓
actions.zig:156    ppu_oam_addr.* += 1 ← Mutation 7
                        ↓
actions.zig:159    dma.phase = .resuming_normal ← Mutation 8
                        ↓
actions.zig:160    ledger.duplication_pending = false ← Mutation 9
```

### Mutation Summary

| Mutation | Target | File | Line | Scope | Encapsulation |
|----------|--------|------|------|-------|---------------|
| oam_pause_cycle | Ledger | execution.zig | 161 | Pause | Direct (BAD) |
| interrupted_state | Ledger | execution.zig | 162 | Pause | Direct (BAD) |
| duplication_pending | Ledger | execution.zig | 164 | Pause | Direct (BAD) |
| dma.phase | OamDma | execution.zig | 168 | Pause | Direct (OK) |
| oam_resume_cycle | Ledger | execution.zig | 189 | Resume | Direct (BAD) |
| dma.phase | OamDma | execution.zig | 192 | Resume | Direct (OK) |
| ppu.oam_addr | PPU | actions.zig | 156 | Update | Parameter (GOOD) |
| dma.phase | OamDma | actions.zig | 159 | Update | Parameter (GOOD) |
| duplication_pending | Ledger | actions.zig | 160 | Update | Direct (BAD) |

**Total Mutations:** 9
**Direct Field Access (Bad):** 5 out of 9 (55% violation rate)
**Proper Encapsulation:** 4 out of 9 (45%)

---

## Query Phase Violation: Deep Analysis

### The Critical Violation: Bus Read in Query Phase

**Location:** `execution.zig:154-158`

```zig
// This section is AFTER handleDmcPausesOam returns (supposedly pure query)
// But we're still in "determination" phase - no Execute has happened yet!

var interrupted = pause_data.interrupted_state;
if (pause_data.read_interrupted_byte) |read_info| {
    const addr = (@as(u16, read_info.source_page) << 8) | read_info.offset;
    interrupted.byte_value = state.busRead(addr);  // ← BUS READ IN QUERY PHASE
    interrupted.oam_addr = state.ppu.oam_addr;
}

// Apply ALL mutations centrally
state.dma_interaction_ledger.oam_pause_cycle = pause_data.pause_cycle;
state.dma_interaction_ledger.interrupted_state = interrupted;
```

### Why This Is Wrong

**3-Phase Architecture:**
1. **Query Phase:** Determine what to do (PURE - no side effects, no mutations)
2. **Execute Phase:** Perform the action (SINGLE side effect only)
3. **Update Phase:** Bookkeeping mutations (state changes AFTER action)

**Current Behavior:**
- Query phase: `handleDmcPausesOam()` returns data ✓
- **Still in Query:** `busRead()` happens ✗ ← THIS IS THE PROBLEM
- Update phase: Mutations applied ✓

**Correct Behavior:**
- Query phase: Determine that pause needs byte read ✓
- **Execute phase:** Perform the bus read (single side effect) ✓
- Update phase: Apply mutations with captured byte ✓

### Why Does This Matter?

**Problem 1: Ordering Ambiguity**
- When does the bus read happen relative to other side effects?
- What if another component is also reading during this cycle?
- Which read happens first?

**Problem 2: Testing Impossible**
- Cannot test Query phase without triggering side effects
- Cannot mock bus reads during query
- Unit tests become integration tests

**Problem 3: Breaks Referential Transparency**
- Same inputs don't produce same outputs (bus state varies)
- Cannot reason about code behavior
- Debugging requires tracing through multiple layers

**Problem 4: Race Conditions**
- Bus read mutates `open_bus`
- What if PPU/APU also read during this cycle?
- Order of operations becomes critical and hidden

### Where Should This Bus Read Happen?

**Option A: Execute Phase in actions.zig**

Add a new action type:
```zig
pub const DmaAction = union(enum) {
    // ... existing actions ...

    /// Capture interrupted byte (for duplication on resume)
    capture_interrupted_byte: struct {
        source_page: u8,
        offset: u8,
    },
};
```

Then in `executeAction()`:
```zig
.capture_interrupted_byte => |info| {
    // ONLY side effect: read interrupted byte
    const addr = (@as(u16, info.source_page) << 8) | info.offset;
    state.dma.temp_value = state.busRead(addr);  // Store in temp
},
```

**Option B: Separate Execute Call**

In `execution.zig`:
```zig
// Query phase
const pause_data = DmaInteraction.handleDmcPausesOam(...);

// Execute phase (NEW)
var interrupted = pause_data.interrupted_state;
if (pause_data.read_interrupted_byte) |read_info| {
    interrupted.byte_value = executeCaptureInterruptedByte(state, read_info);
    interrupted.oam_addr = state.ppu.oam_addr;
}

// Update phase
state.dma_interaction_ledger.oam_pause_cycle = pause_data.pause_cycle;
state.dma_interaction_ledger.interrupted_state = interrupted;
// ...
```

**Option C: Defer Read Until Resume**

Don't read during pause at all. On resume:
1. Query: Determine duplication needed
2. Execute: Read source byte + write to OAM (combined action)
3. Update: Bookkeeping

Problem: Loses hardware accuracy (real hardware captures the byte at pause time)

---

## "Pure Function" Documentation Lies

### Claim vs Reality: handleDmcPausesOam

**Documentation (interaction.zig:30-31):**
```zig
/// **PURE FUNCTION** - Returns data only, NO mutations.
/// Caller must perform all state updates.
```

**Signature (interaction.zig:32-36):**
```zig
pub fn handleDmcPausesOam(
    ledger: *const DmaInteractionLedger,  // ← CONST pointer
    oam: *const OamDma,                   // ← CONST pointer
    cycle: u64,
) PauseData {
```

**Reality Check:**

Function IS pure ✓ - Takes const pointers, returns data structure, no mutations in function body.

**BUT:** The CALLER performs side effects DURING what should be Query phase ✗

### Claim vs Reality: handleOamResumes

**Documentation (interaction.zig:93-94):**
```zig
/// **PURE FUNCTION** - Returns data only, NO mutations.
/// Caller must perform all state updates.
```

**Signature (interaction.zig:95-98):**
```zig
pub fn handleOamResumes(
    ledger: *const DmaInteractionLedger,
    cycle: u64,
) ResumeData {
```

**Reality Check:**

Function IS pure ✓ - Takes const pointer, returns data, no mutations.

Caller properly separates Query from Update ✓

**This one is correct!**

### The Real Problem

The functions ARE pure, but the CALL SITE violates the phase separation by performing side effects between Query and Update.

**Root Cause:** Lack of explicit Execute phase at call site.

---

## Data Structure Business Logic Violation

### VBlankLedger (Correct Pattern)

**File:** `src/emulation/state/VBlankLedger.zig`

```zig
pub const VBlankLedger = struct {
    last_set_cycle: u64 = 0,
    last_clear_cycle: u64 = 0,
    last_read_cycle: u64 = 0,
    race_hold: bool = false,

    /// ONLY mutation method - simple reset
    pub fn reset(self: *VBlankLedger) void {
        self.* = .{};
    }

    // NO OTHER METHODS
    // ALL logic happens in EmulationState
};
```

**Characteristics:**
- Pure data structure
- Zero business logic
- Single mutation method (reset only)
- All decisions made by caller
- Timestamp-based state

### DmaInteractionLedger (Broken Pattern)

**File:** `src/emulation/DmaInteractionLedger.zig`

```zig
pub const DmaInteractionLedger = struct {
    last_dmc_active_cycle: u64 = 0,
    last_dmc_inactive_cycle: u64 = 0,
    oam_pause_cycle: u64 = 0,
    oam_resume_cycle: u64 = 0,
    interrupted_state: InterruptedState = .{},
    duplication_pending: bool = false,  // ← Business logic flag

    /// Business logic in data structure!
    pub fn recordOamPause(
        self: *DmaInteractionLedger,
        cycle: u64,
        state: InterruptedState,
    ) void {
        self.oam_pause_cycle = cycle;
        self.interrupted_state = state;

        // DECISION-MAKING in data structure!
        if (state.was_reading) {
            self.duplication_pending = true;  // ← Business logic
        }
    }

    // 5 MORE mutation methods...
};
```

**Violations:**
1. Business logic decision (`if state.was_reading`)
2. Multiple mutation methods (6 total)
3. Flag management embedded in structure
4. Encapsulation hiding mutations from caller

### Comparison Table

| Aspect | VBlankLedger | DmaInteractionLedger |
|--------|--------------|---------------------|
| Mutation methods | 1 (`reset()`) | 6 (record*, clear*) |
| Business logic | None | Yes (duplication flag) |
| Encapsulation | Open (direct access) | Closed (methods hide mutations) |
| Decision making | Caller decides | Ledger decides |
| Testability | High (pure data) | Low (hidden logic) |
| Pattern adherence | 100% | 0% |

### Why This Matters

**Problem 1: Hidden Mutations**

With methods, mutations are scattered:
```zig
// Where do mutations happen? Need to read 6 different methods!
ledger.recordOamPause(cycle, state);      // Mutates 3 fields
ledger.clearDuplication();                 // Mutates 1 field
ledger.clearPause();                       // Mutates 4 fields
```

With direct access, mutations are visible:
```zig
// All mutations clearly visible at call site
ledger.oam_pause_cycle = cycle;
ledger.interrupted_state = state;
ledger.duplication_pending = true;
```

**Problem 2: Business Logic Coupling**

Ledger makes decisions:
```zig
if (state.was_reading) {  // ← Decision in ledger
    self.duplication_pending = true;
}
```

Should be:
```zig
// Caller makes decision
if (interrupted.was_reading) {
    ledger.duplication_pending = true;
}
```

**Problem 3: Testing Complexity**

Testing methods requires mocking entire structure:
```zig
test "recordOamPause sets duplication_pending" {
    var ledger = DmaInteractionLedger{};
    const state = InterruptedState{ .was_reading = true, ... };

    // Black box - can't test intermediate state
    ledger.recordOamPause(100, state);

    // Can only assert final result
    try testing.expect(ledger.duplication_pending);
}
```

Testing direct access is trivial:
```zig
test "pause during read sets duplication flag" {
    var ledger = DmaInteractionLedger{};

    // Explicit mutation - easy to reason about
    ledger.oam_pause_cycle = 100;
    ledger.interrupted_state = .{ .was_reading = true, ... };
    ledger.duplication_pending = true;

    // Easy to verify
    try testing.expect(ledger.duplication_pending);
}
```

---

## Mutation Ordering Principles

### Principle 1: Single Source of Truth for Ordering

**BAD (Current):** Mutations scattered across 3 modules
- `execution.zig` mutates ledger (lines 161-164)
- `actions.zig` mutates ledger (line 160)
- `interaction.zig` would mutate if not const (documentation lies)

**GOOD:** All mutations in single location
```zig
// execution.zig becomes the ONLY place that mutates DMA state
pub fn handleDmaPauseEvent(state: anytype) void {
    // 1. Query
    const should_pause = DmaInteraction.shouldOamPause(...);
    if (!should_pause) return;

    const pause_data = DmaInteraction.handleDmcPausesOam(...);

    // 2. Execute
    var captured_byte: u8 = 0;
    if (pause_data.read_interrupted_byte) |read_info| {
        captured_byte = executeCaptureInterruptedByte(state, read_info);
    }

    // 3. Update (ALL mutations in one place)
    state.dma_interaction_ledger.oam_pause_cycle = pause_data.pause_cycle;
    state.dma_interaction_ledger.interrupted_state = .{
        .was_reading = pause_data.was_reading,
        .byte_value = captured_byte,
        .oam_addr = state.ppu.oam_addr,
        .offset = pause_data.offset,
    };
    if (pause_data.was_reading) {
        state.dma_interaction_ledger.duplication_pending = true;
    }
    state.dma.phase = pause_data.pause_phase;
}
```

### Principle 2: Explicit Phase Boundaries

**BAD (Current):** No clear boundary between Query and Execute
```zig
const pause_data = handleDmcPausesOam(...);  // Query
// ... side effect happens here ...           // ← WHERE IS EXECUTE?
state.dma_interaction_ledger.oam_pause_cycle = ...;  // Update
```

**GOOD:** Clear phase markers
```zig
// PHASE 1: QUERY
const action = determineAction(...);

// PHASE 2: EXECUTE
executeAction(state, action);

// PHASE 3: UPDATE
updateBookkeeping(..., action);
```

### Principle 3: Single Responsibility Per Function

**BAD:** Function that does multiple things
```zig
pub fn tickOamDma(state: anytype) void {
    // Determine action
    const cycle = state.dma.current_cycle;
    const is_read = (cycle % 2 == 0);

    // Execute action
    if (is_read) {
        state.dma.temp_value = state.busRead(...);
    } else {
        state.ppu.oam[...] = state.dma.temp_value;
    }

    // Update bookkeeping
    state.dma.current_cycle += 1;
    state.dma.phase = ...;

    // Check completion
    if (cycle >= 512) {
        state.dma.reset();
    }
}
```

**GOOD:** Separate functions with single responsibility
```zig
pub fn tickOamDma(state: anytype) void {
    const action = determineAction(&state.dma, &state.ledger);
    executeAction(state, action);
    updateBookkeeping(&state.dma, &state.ppu.oam_addr, &state.ledger, action);
}
```

### Principle 4: Mutation Visibility

**BAD:** Hidden mutations in method calls
```zig
ledger.recordOamPause(cycle, state);  // What does this mutate? Unknown!
```

**GOOD:** Visible mutations at call site
```zig
ledger.oam_pause_cycle = cycle;            // Clear mutation
ledger.interrupted_state = state;          // Clear mutation
ledger.duplication_pending = true;         // Clear mutation
```

### Principle 5: Testable Units

**BAD:** Untestable mega-function
```zig
pub fn tickOamDma(state: anytype) void {
    // 150 lines of interleaved logic
    // Cannot test individual actions
    // Cannot mock individual side effects
    // Cannot verify intermediate state
}
```

**GOOD:** Testable components
```zig
// Test query independently
test "determineAction returns read on even cycle" {
    const action = determineAction(&dma, &ledger);
    try testing.expect(action == .read);
}

// Test execute independently (with mock state)
test "executeAction performs bus read" {
    var mock_state = MockState{};
    executeAction(&mock_state, .read);
    try testing.expect(mock_state.bus_read_called);
}

// Test bookkeeping independently
test "updateBookkeeping increments cycle" {
    var dma = OamDma{};
    updateBookkeeping(&dma, &oam_addr, &ledger, .read);
    try testing.expectEqual(@as(u16, 1), dma.current_cycle);
}
```

---

## Correct Architecture Patterns

### Pattern 1: VBlankLedger (Pure Data)

**What It Does Right:**
1. Zero business logic - just timestamps
2. Single mutation method (`reset()`)
3. All decisions made by caller
4. Direct field access encouraged
5. Easy to test (pure data)

**Example Usage:**
```zig
// In EmulationState - ALL logic here
if (scanline == 241 and dot == 1) {
    // Caller makes decision
    if (state.vblank_ledger.last_set_cycle != state.clock.ppu_cycles) {
        // Caller performs mutation
        state.vblank_ledger.last_set_cycle = state.clock.ppu_cycles;
        state.vblank_ledger.race_hold = false;
    }
}

// Query ledger (pure - no mutations)
const vblank_active = (state.vblank_ledger.last_set_cycle >
                       state.vblank_ledger.last_clear_cycle);
```

### Pattern 2: 3-Phase Action Architecture (actions.zig)

**What It Does Right:**
1. Clear phase separation
2. Single responsibility per function
3. Testable components
4. Explicit side effect boundaries
5. Linear control flow

**Example Usage:**
```zig
pub fn tickOamDma(state: anytype) void {
    // PHASE 1: QUERY (pure, no mutations)
    const action = DmaActions.determineAction(&state.dma, &state.ledger);

    // PHASE 2: EXECUTE (single side effect)
    DmaActions.executeAction(state, action);

    // PHASE 3: UPDATE (state mutations)
    DmaActions.updateBookkeeping(&state.dma, &state.ppu.oam_addr,
                                  &state.ledger, action);
}
```

### Pattern 3: Pure Query Functions (shouldOamPause, shouldOamResume)

**What They Do Right:**
1. Take const pointers only
2. Return boolean decisions
3. Zero mutations
4. Zero side effects
5. Testable in isolation

**Example Usage:**
```zig
pub fn shouldOamPause(
    _: *const DmaInteractionLedger,
    oam: *const OamDma,
    dmc_active: bool,
) bool {
    return dmc_active and
           oam.active and
           !isPaused(oam.phase);
}
```

### Pattern 4: Data-Returning Action Functions

**What They Do Right:**
1. Return structured data (not void)
2. Caller applies mutations
3. No hidden state changes
4. Composable and testable

**Example:**
```zig
pub fn handleDmcPausesOam(
    ledger: *const DmaInteractionLedger,
    oam: *const OamDma,
    cycle: u64,
) PauseData {
    // Pure calculation - no mutations
    const is_reading = (effective_cycle % 2 == 0);

    // Return data structure with ALL information
    return .{
        .pause_phase = if (is_reading) .paused_during_read else .paused_during_write,
        .pause_cycle = cycle,
        .interrupted_state = .{ ... },
        .read_interrupted_byte = if (is_reading) .{ ... } else null,
    };
}
```

---

## Recommendations for Proper Mutation Ordering

### Recommendation 1: Move Bus Read to Execute Phase

**Current Problem:** Bus read in Query phase

**Solution:** Create explicit Execute phase at call site

```zig
// In execution.zig:145-169
if (dmc_rising_edge and DmaInteraction.shouldOamPause(...)) {
    // PHASE 1: QUERY
    const pause_data = DmaInteraction.handleDmcPausesOam(...);

    // PHASE 2: EXECUTE (NEW)
    var interrupted = pause_data.interrupted_state;
    if (pause_data.read_interrupted_byte) |read_info| {
        // Execute phase - single side effect
        interrupted.byte_value = executeInterruptedByteRead(state, read_info);
        interrupted.oam_addr = state.ppu.oam_addr;
    }

    // PHASE 3: UPDATE
    applyPauseMutations(state, pause_data, interrupted);
}

fn executeInterruptedByteRead(state: anytype, read_info: anytype) u8 {
    const addr = (@as(u16, read_info.source_page) << 8) | read_info.offset;
    return state.busRead(addr);
}

fn applyPauseMutations(state: anytype, pause_data: anytype, interrupted: anytype) void {
    state.dma_interaction_ledger.oam_pause_cycle = pause_data.pause_cycle;
    state.dma_interaction_ledger.interrupted_state = interrupted;
    if (interrupted.was_reading) {
        state.dma_interaction_ledger.duplication_pending = true;
    }
    state.dma.phase = pause_data.pause_phase;
}
```

### Recommendation 2: Simplify Ledger to Pure Data

**Current Problem:** 6 mutation methods + business logic

**Solution:** Remove all methods except reset(), move logic to EmulationState

```zig
pub const DmaInteractionLedger = struct {
    last_dmc_active_cycle: u64 = 0,
    last_dmc_inactive_cycle: u64 = 0,
    oam_pause_cycle: u64 = 0,
    oam_resume_cycle: u64 = 0,
    interrupted_state: InterruptedState = .{},
    duplication_pending: bool = false,

    pub const InterruptedState = struct {
        was_reading: bool = false,
        offset: u8 = 0,
        byte_value: u8 = 0,
        oam_addr: u8 = 0,
    };

    /// ONLY mutation method
    pub fn reset(self: *DmaInteractionLedger) void {
        self.* = .{};
    }

    // Query methods stay (pure, const pointers)
    pub fn isDmcActive(self: *const DmaInteractionLedger) bool {
        return self.last_dmc_active_cycle > self.last_dmc_inactive_cycle;
    }

    pub fn isOamPaused(self: *const DmaInteractionLedger) bool {
        return self.oam_pause_cycle > self.oam_resume_cycle;
    }

    // Remove: recordDmcActive, recordDmcInactive, recordOamPause,
    //         recordOamResume, clearDuplication, clearPause
    // All mutations happen in EmulationState via direct field access
};
```

### Recommendation 3: Centralize DMC Edge Detection

**Current Problem:** Edge detection scattered in execution.zig

**Solution:** Move to EmulationState method with clear mutation ordering

```zig
// In EmulationState
pub fn updateDmcEdges(self: *EmulationState) void {
    const prev_active = self.dma_interaction_ledger.isDmcActive();
    const curr_active = self.dmc_dma.rdy_low;

    // Rising edge: DMC became active
    if (curr_active and !prev_active) {
        self.dma_interaction_ledger.last_dmc_active_cycle = self.clock.ppu_cycles;
    }

    // Falling edge: DMC became inactive
    if (!curr_active and prev_active) {
        self.dma_interaction_ledger.last_dmc_inactive_cycle = self.clock.ppu_cycles;
    }
}
```

### Recommendation 4: Document Mutation Points

**Solution:** Add comments marking mutation boundaries

```zig
pub fn stepCycle(state: anytype) CpuCycleResult {
    // === QUERY PHASE: No mutations, no side effects ===

    const vblank_active = (state.vblank_ledger.last_set_cycle >
                           state.vblank_ledger.last_clear_cycle);
    const nmi_line_should_assert = vblank_active and
                                   state.ppu.ctrl.nmi_enable;

    // === MUTATION PHASE: State updates only ===

    state.cpu.nmi_line = nmi_line_should_assert;

    // === EXECUTE PHASE: Side effects only ===

    if (state.dmc_dma.rdy_low) {
        state.tickDmcDma();  // Contains bus reads
    }

    // === QUERY PHASE: Determine next action ===

    const should_pause = DmaInteraction.shouldOamPause(...);

    // ...
}
```

---

## Summary of Violations

### Severity Levels
- CRITICAL: Breaks fundamental architecture principles
- HIGH: Violates established patterns, hard to maintain
- MEDIUM: Inconsistent with codebase, needs refactoring
- LOW: Minor deviation, easy to fix

### Violation List

| ID | Severity | Violation | Location | Impact |
|----|----------|-----------|----------|--------|
| V1 | CRITICAL | Bus read in Query phase | execution.zig:156 | Breaks 3-phase pattern |
| V2 | HIGH | Direct field mutations (5x) | execution.zig, actions.zig | Breaks encapsulation |
| V3 | HIGH | Business logic in ledger | DmaInteractionLedger.zig:92-94 | Violates VBlankLedger pattern |
| V4 | HIGH | 6 mutation methods in ledger | DmaInteractionLedger.zig | Should be pure data |
| V5 | MEDIUM | Scattered DMC edge detection | execution.zig:132-137 | Hard to reason about |
| V6 | MEDIUM | Mutations in 3 different modules | All DMA files | No single source of truth |
| V7 | LOW | Misleading "pure" comments | interaction.zig:30 | Functions ARE pure, call site isn't |

---

## Principles for Correct Side Effect Management

### Principle 1: Phase Separation
**Query → Execute → Update**

- Query: Pure functions, const pointers, return data
- Execute: Single side effect only (bus read OR bus write)
- Update: State mutations after side effect complete

### Principle 2: Single Source of Truth
**All mutations for a subsystem in ONE location**

- DMA mutations: All in execution.zig (or EmulationState)
- NOT scattered across interaction.zig, actions.zig, ledger.zig

### Principle 3: Data Structures Are Dumb
**Follow VBlankLedger pattern**

- Zero business logic in data structures
- Only reset() method for mutations
- All decisions made by caller
- Direct field access encouraged

### Principle 4: Explicit > Implicit
**Make side effects and mutations visible**

```zig
// BAD: Hidden mutation
ledger.recordOamPause(cycle, state);

// GOOD: Visible mutation
ledger.oam_pause_cycle = cycle;
ledger.interrupted_state = state;
```

### Principle 5: Testability First
**Architecture enables testing**

- Pure query functions → Easy unit tests
- Single-action execute → Easy mock testing
- Separate bookkeeping → Easy state verification

---

## Files Requiring Architecture Review

### High Priority (Critical Violations)
1. `/home/colin/Development/RAMBO/src/emulation/cpu/execution.zig` (lines 140-199)
   - Move bus read to explicit Execute phase
   - Centralize all DMA mutations

2. `/home/colin/Development/RAMBO/src/emulation/DmaInteractionLedger.zig`
   - Remove 6 mutation methods
   - Remove business logic (duplication_pending decision)
   - Keep only reset() + query methods

### Medium Priority (Pattern Violations)
3. `/home/colin/Development/RAMBO/src/emulation/dma/actions.zig` (line 160)
   - Remove direct ledger mutation
   - Return action result instead

4. `/home/colin/Development/RAMBO/src/emulation/dma/interaction.zig`
   - Fix documentation (functions ARE pure, call site isn't)
   - Consider returning more data to avoid call site mutations

### Low Priority (Documentation)
5. All DMA files
   - Add phase boundary comments
   - Document mutation points
   - Clarify side effect ordering

---

## Conclusion

The DMA system has **fundamental architectural violations** that make reasoning about state changes extremely difficult:

1. **16% of side effects** happen in wrong phase (Query instead of Execute)
2. **55% of mutations** bypass encapsulation via direct field access
3. **Zero adherence** to VBlankLedger pattern (should be 100%)
4. **Mutations scattered** across 3 different modules (should be 1)

The clean 3-phase architecture in `actions.zig` is EXCELLENT, but it's undermined by violations in `execution.zig` and `DmaInteractionLedger.zig`.

**Recommendation:** Fix architecture BEFORE fixing bugs. The bugs will be easier to fix (and less likely to reoccur) with clean architecture.

**Estimated Refactoring Scope:**
- 2 hours: Simplify DmaInteractionLedger to pure data
- 2 hours: Move bus read to Execute phase
- 1 hour: Centralize mutations in execution.zig
- 1 hour: Update documentation and add phase comments
- **Total: 6 hours for clean architecture**

vs.

**Bug Fix Scope:**
- 15 minutes: Apply 4 bug fixes
- **Total: 15 minutes with architectural debt**

The architectural debt will cost far more than 6 hours in future maintenance, debugging, and onboarding new contributors.

---

**End of Analysis**
