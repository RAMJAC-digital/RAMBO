---
name: h-refactor-emulator-cleanup
branch: feature/h-refactor-emulator-cleanup
status: in-progress
created: 2025-11-06
---

# Emulator Codebase Cleanup & Simplification

## ⚠️ CRITICAL OBJECTIVE - READ THIS FIRST EVERY SESSION ⚠️

**PRIMARY GOAL: REFACTOR, CLEAN UP, IMPROVE READABILITY**

**WHAT THIS TASK IS:**
- Methodical line-by-line review of every file
- Remove wrappers, shims, indirection
- Improve naming, structure, readability
- Delete misleading comments
- Fix architectural problems
- Document findings as you go

**WHAT THIS TASK IS NOT:**
- Making tests pass (tests are broken by design, fix them later)
- Quick fixes to get builds working
- Worrying about compilation errors in test infrastructure
- Planning and proposing - DO THE WORK
- Surface-level audits - READ EVERY LINE

**WORK APPROACH:**
1. Fix imports in moved files to get basic compilation
2. Line-by-line review of files (read every function, every comment)
3. Document what's good, what's bad, what's confusing WITH LINE NUMBERS
4. Make informed refactoring decisions based on review
5. Update this file continuously with progress

**IF YOU FIND YOURSELF:**
- Proposing investigation plans → STOP, start doing the investigation
- Trying to make tests pass → STOP, ignore test failures
- Making quick fixes without understanding → STOP, read and document first
- Planning instead of reviewing → STOP, start the line-by-line review

**STAY FOCUSED. DO THE METHODICAL WORK. DOCUMENT EVERYTHING.**

---

## Problem/Goal

The NES emulator codebase is fundamentally compromised - documentation, comments, and code patterns are actively misleading developers:

**Systemic Problems (ENTIRE CODEBASE):**
- **Toxic documentation:** README.md, ARCHITECTURE.md, CLAUDE.md, docs/* contain outdated findings and incorrect patterns
- **Misleading comments:** Comments reference removed APIs, outdated assumptions, wrong mental models
- **Wrapper hell:** Functions wrapping other fields (cpuCycle/apuCycle) creating timing confusion
- **Ghost APIs:** "Compatibility" references to non-existent features in critical timing code
- **Poor code hygiene:** Deeply nested if statements, confusing data flow, multi-purpose functions
- **Brittle tests:** Hard-coded assumptions, unfocused test cases, anti-pattern helpers
- **Unexplored areas:** PPU, NMI, DMA systems assumed to have same problems (or worse)

**This is not incremental cleanup - this is a complete rebuild with discipline.**

**Goal:** Tear down and rebuild the entire emulator with clear standards: self-documenting code, direct data flow, single-purpose functions, zero misleading documentation.

## Success Criteria

### Documentation & Comments (IN PROGRESS)
- [x] **CPU Execution comments** reduced from 779→563 lines (-216 lines, 27% reduction)
- [x] **Hardware citations preserved** - All nesdev.org and Mesen2 references kept
- [x] **Removed verbose docs** - Deleted "what the code does" comments that duplicated code
- [x] **dummyRead() helper** - Clarified hardware-accurate bus access pattern (7 instances)
- [ ] **All** documentation deleted or completely rewritten from scratch (README.md, ARCHITECTURE.md, CLAUDE.md, docs/*)
- [ ] Default: Delete ALL comments unless they explain non-obvious hardware behavior
- [ ] Zero "compatibility" references, zero references to removed APIs

### Code Architecture Refactoring (IN PROGRESS)
- [x] **PPU owns VBlank state** - Moved VBlankLedger → ppu/VBlank.zig (type renamed)
- [x] **PPU owns framebuffer** - Removed from EmulationState, added to PpuState
- [x] **PPU nmi_line output** - PPU computes internally from vblank_flag + ctrl.nmi_enable
- [ ] **CPU:** Timing, instruction execution, interrupt handling - zero wrappers, zero nested conditionals
- [ ] **PPU:** Rendering pipeline, register I/O, timing - direct data flow, no confusing returns
- [ ] **DMA:** OAM DMA, DMC DMA - timing logic is obviously correct on inspection
- [ ] **Clock Coordination:** ONE clear representation of cycles (no cpuCycle vs apuCycle confusion)

### Function-Level Standards (PARTIALLY DONE)
- [x] **Microsteps.zig** - Pure functions, single responsibility, 10% comment ratio (template quality)
- [x] **dummyRead() clarity** - Explicit intent for hardware-accurate bus accesses
- [ ] Every function does ONE thing with a clear, descriptive name
- [ ] No deeply nested conditionals - extract to named helper functions
- [ ] Critical paths (tick functions, interrupt handling) readable in 30 seconds

### Module Separation (IN PROGRESS)
- [ ] EmulationState.tick() no longer extracts PPU/CPU/APU internals
- [ ] Each subsystem (CPU, PPU, APU, DMA) manages its own state
- [ ] No backwards coupling - modules don't reach into other modules' internals
- [ ] Bus handlers follow zero-size stateless pattern (verified 98.1% pass rate)

### Test Infrastructure (DEFERRED)
- [ ] Test helpers encode ZERO brittle assumptions
- [ ] Every test has singular, focused purpose
- [ ] Test pass rate ≥98% (currently 98.1%, maintained)
- [ ] Tests verify behavior, not implementation details

### Meta-Criteria (The Real Test)
- [ ] A new developer can read ANY subsystem and understand it without docs
- [ ] Debugging doesn't require fighting through indirection layers
- [ ] No "but actually..." caveats when explaining how something works
- [ ] We can confidently say "this is correct" about every critical timing path
- [ ] The codebase doesn't lie to developers

## Context Manifest

### How the Emulator Currently Works: Complete System Map

This emulator is a **712-line monolithic tick loop** (`src/emulation/State.zig:tick()`) orchestrating 7 major subsystems through wrapper functions and timing confusion. The architecture evolved organically through multiple refactoring attempts, leaving layers of abstraction debt.

#### Core Architecture - The Tick Loop Pattern

**Master Entry Point:** `EmulationState.tick()` @ `src/emulation/State.zig:456-706`

Every emulation frame executes ~89,342 PPU cycles (NTSC) through this single function:

1. **Clock Advancement** (lines 461-466)
   - `self.clock.advance()` - Increments master_cycles by 1 (monotonic counter)
   - `nextTimingStep()` - Computes CPU/APU tick flags from master_cycles % 3
   - Returns TimingStep struct with cpu_tick boolean

2. **Component Execution Order** (lines 485-634) - HARDWARE-CRITICAL
   - APU ticks FIRST (if cpu_tick) - Updates IRQ flags BEFORE CPU sees them
   - CPU executes SECOND (via `CpuExecution.stepCycle()`) - Can read $2002, set prevention flags
   - VBlank timestamps applied THIRD (via `applyVBlankTimestamps()`) - Respects CPU prevention
   - Interrupt sampling FOURTH (via `CpuLogic.checkInterrupts()`) - Sees finalized VBlank state
   - PPU state applied LAST (via `applyPpuRenderingState()`) - Reflects CPU register writes

This ordering is LOCKED per nesdev.org hardware specification (lines 334-364 in CLAUDE.md). CPU operations execute BEFORE PPU flag updates within the same PPU cycle.

#### The Wrapper Hell Problem

**Identified Wrappers Obscuring Timing:**

1. **`isApuTick()` in MasterClock.zig** - Literally just returns `isCpuTick()`
   - Lines 234, 237: `try testing.expect(clock.isApuTick() == clock.isCpuTick());`
   - APU tick IS CPU tick, no separate timing - this wrapper adds zero value
   - Should be eliminated, use `isCpuTick()` directly

2. **`cpuCycles()` in MasterClock.zig:94** - Divides master_cycles by 3
   - Not inherently bad, but used inconsistently with raw master_cycles
   - Creates confusion: "Are we measuring CPU cycles or master cycles?"
   - Used in 18 files (see grep results)

3. **`tickCpuWithClock()` in helpers.zig:18** - Advances clock 3 times then ticks CPU
   - Helper for tests, but creates timing model confusion
   - Tests don't advance clock naturally, they call wrappers
   - Obscures the fact that tick() handles all advancement

**The Ghost API Problem:**
- Line 670-677: Removed `applyNmiLine()` function with comment about "bypassing VBlankLedger"
- References to removed functions still exist in comments throughout codebase
- Old mental models persist in documentation even after code changes

#### Subsystem 1: CPU Execution State Machine

**Files:**
- `src/cpu/State.zig` - CPU registers, flags, execution state (87 lines of pure data)
- `src/cpu/Logic.zig` - Pure functions (87 lines)
- `src/emulation/cpu/execution.zig` - Execution loop (779 lines) - **NEEDS SIMPLIFICATION**
- `src/emulation/cpu/microsteps.zig` - Per-instruction microstep logic

**State Machine (4 states in CpuState.state enum):**
1. `.interrupt_sequence` - 7-cycle hardware interrupt (NMI/IRQ/RESET)
2. `.fetch_opcode` - Fetch next instruction byte
3. `.fetch_operand_low` - Addressing mode microsteps (1-8 cycles depending on mode)
4. `.execute` - Execute instruction (1 cycle)

**Critical Path:** `CpuExecution.stepCycle()` @ execution.zig:77-150
- Checks DMA halts (OAM DMA, DMC DMA)
- Checks debugger breakpoints/watchpoints
- Handles PPU warmup completion (29,658 CPU cycles)
- Calls `executeCycle()` for actual state machine dispatch
- Updates mapper IRQ counters

**Known Issues:**
- execution.zig is 779 lines - needs decomposition into focused modules
- Deep nesting in addressing mode logic (lines 200-600)
- Mixed concerns: DMA checks, debugger, warmup, execution all in one function
- Comments reference "+1 cycle deviation" (lines 33-38) - timing quirk not fully addressed

**Interrupt Handling - Second-to-Last Cycle Rule:**
- `CpuLogic.checkInterrupts()` @ Logic.zig:59-76
- **Edge detection:** NMI on falling edge, IRQ on level
- Sampled at END of cycle N, checked at START of cycle N+1
- Uses `nmi_pending_prev`/`irq_pending_prev` for delayed checking
- **NMI priority:** `if (irq_pending_prev and pending_interrupt != .nmi)` (State.zig:521)
- This pattern is CORRECT per Mesen2 (lines 406-450 in CLAUDE.md)

#### Subsystem 2: PPU Rendering Pipeline

**Files:**
- `src/ppu/State.zig` - PPU registers, VRAM, OAM, shift registers (large struct)
- `src/ppu/Logic.zig` - PPU operations facade (506 lines)
- `src/ppu/logic/background.zig` - Tile fetching
- `src/ppu/logic/sprites.zig` - Sprite evaluation and rendering
- `src/ppu/logic/memory.zig` - VRAM access
- `src/ppu/logic/scrolling.zig` - Scroll register manipulation
- `src/ppu/logic/registers.zig` - CPU register I/O

**PPU Timing Model:**
- 341 dots per scanline, 262 scanlines per frame
- Owned by PpuState: `cycle: u16, scanline: i16, frame_count: u64`
- Advanced via `PpuLogic.advanceClock()` @ Logic.zig:54-76
- Handles odd frame skip internally (cycle 339→340 on odd frames)

**Critical PPU Path:** `PpuLogic.advanceClock()` @ Logic.zig:54-76
- Increments cycle (0-340)
- Scanline wrap at cycle > 340
- Frame wrap at scanline > 260 → -1 (pre-render)
- Odd frame skip: scanline == -1, cycle == 339, rendering_enabled, odd frame → skip to 340

**PPU Rendering State Application:** `EmulationState.applyPpuRenderingState()` @ State.zig:806-814
- Sets `rendering_enabled` from PPUMASK bits 3-4
- Sets `frame_complete` flag when result.frame_complete is true
- Applied AFTER CPU execution (reflects register writes from same cycle)

**Known Issues:**
- PPU Logic.zig is 506 lines with heavy delegation to sub-modules
- Not inherently bad, but documentation doesn't explain the delegation pattern clearly
- Comments reference "greyscale mode" and other features without nesdev.org citations

#### Subsystem 3: NMI/VBlank Coordination - The Most Complex Subsystem

**Files:**
- `src/emulation/VBlankLedger.zig` - Pure data ledger (81 lines) - **CORRECT PATTERN**
- `src/emulation/bus/handlers/PpuHandler.zig` - $2000-$3FFF handler (250+ lines)
- `src/emulation/State.zig` - VBlank timestamp application (lines 776-804)

**VBlank Ledger Pattern (Pure Data):**
```zig
pub const VBlankLedger = struct {
    vblank_flag: bool = false,           // Readable bit 7 of $2002
    vblank_span_active: bool = false,    // Hardware timing window (scanline 241 → pre-render)
    last_set_cycle: u64 = 0,             // Debugging timestamp
    last_clear_cycle: u64 = 0,           // Debugging timestamp
    last_read_cycle: u64 = 0,            // Debugging timestamp
    prevent_vbl_set_cycle: u64 = 0,      // Race prevention timestamp

    // ONLY mutation method
    pub fn reset(self: *VBlankLedger) void { self.* = .{}; }
};
```

**Critical Insight:** VBlankLedger has NO business logic - just timestamps. All mutations happen in EmulationState. This is the CORRECT pattern (documented in ARCHITECTURE.md:432-603).

**VBlank Timestamp Application:** `EmulationState.applyVBlankTimestamps()` @ State.zig:776-804
- Called AFTER CPU execution (allows CPU to set prevention flag via $2002 reads)
- Checks for VBlank set at scanline 241, dot 1
- Checks for VBlank clear at scanline -1, dot 1 (pre-render)
- Respects `prevent_vbl_set_cycle` flag (race condition handling)
- Sets `vblank_flag` and `vblank_span_active` directly
- Updates `cpu.nmi_line` based on VBlank state + PPUCTRL.7

**PpuHandler - $2002 Read Side Effects:** @ PpuHandler.zig:59-107
- Race detection: If scanline == 241, dot == 0, sets `prevent_vbl_set_cycle = master_cycles + 1`
- Always clears `vblank_flag` (line 98)
- Always clears `cpu.nmi_line` (line 102)
- Records `last_read_cycle` timestamp (line 93)

**PpuHandler - $2000 Write Side Effects:** @ PpuHandler.zig:115-151
- PPUCTRL bit 7 controls NMI enable
- 0→1 transition while VBlank active: Sets `cpu.nmi_line = true`
- 1→0 transition: Clears `cpu.nmi_line = false`
- Updates happen IMMEDIATELY (same cycle as write)

**The Hardware Behavior (LOCKED):**
Within a single PPU cycle, operations execute in this order:
1. CPU read operations (can read $2002, set prevention flag)
2. CPU write operations (can write $2000, change NMI enable)
3. PPU events (VBlank flag set, sprite evaluation)
4. End of cycle

This is why CPU execution happens BEFORE `applyVBlankTimestamps()` in tick() (line 485).

**Known Issues:**
- PpuHandler is 250+ lines with complex timing logic
- Comments reference Mesen2 line numbers that may drift
- VBlank prevention logic is correct but hard to follow (3 different cycle checks)
- Documentation in CLAUDE.md is extensive (lines 332-506) but verbose

#### Subsystem 4: APU Channels and Frame Counter

**Files:**
- `src/apu/State.zig` - APU channel states, frame counter
- `src/apu/Logic.zig` - APU operations
- `src/apu/Dmc.zig` - DMC channel (separate from APU struct)
- `src/apu/Envelope.zig` - Generic envelope component
- `src/apu/Sweep.zig` - Generic sweep component
- `src/apu/logic/registers.zig` - APU register I/O

**APU Execution:** `EmulationState.stepApuCycle()` @ State.zig:571-598
- Ticks frame counter (4-step or 5-step mode)
- Ticks 5 channels (Pulse1, Pulse2, Triangle, Noise, DMC)
- Updates `apu.frame_irq_flag` and `apu.dmc_irq_flag`
- APU ticks BEFORE CPU in tick() so CPU sees updated IRQ flags same cycle

**Frame IRQ Timing:**
- Frame counter clocks at specific CPU cycle counts
- Mode 0 (4-step): IRQ on step 3
- Mode 1 (5-step): No IRQ
- IRQ flag cleared by writing to $4017 or reading $4015

**Known Issues:**
- APU Logic is relatively clean (135 tests passing)
- DMC DMA interaction is complex (see subsystem 6)

#### Subsystem 5: DMA Systems (OAM DMA, DMC DMA)

**Files:**
- `src/emulation/state/peripherals/OamDma.zig` - OAM DMA state machine
- `src/emulation/state/peripherals/DmcDma.zig` - DMC DMA state machine
- `src/emulation/dma/logic.zig` - DMA tick logic (functional pattern)
- `src/emulation/DmaInteractionLedger.zig` - Timestamp ledger for conflict tracking

**OAM DMA ($4014 write):**
- Copies 256 bytes from $XX00-$XXFF to PPU OAM
- 512 CPU cycles (1 read, 1 write per byte)
- Needs alignment cycle if triggered on odd CPU cycle
- Ticked via `DmaLogic.tickOamDma()` @ dma/logic.zig:21-97

**DMC DMA (automatic sample fetch):**
- Triggered by APU DMC channel when sample buffer empty
- 4-cycle sequence: halt, dummy, alignment, read
- Stalls CPU (RDY line low)
- Ticked via `DmaLogic.tickDmcDma()` @ dma/logic.zig:99-160

**Time-Sharing Behavior (CRITICAL, VERIFIED CORRECT):**
When DMC interrupts OAM:
- OAM continues during DMC halt (cycle 4), dummy (cycle 3), alignment (cycle 2)
- OAM pauses ONLY during DMC read (cycle 1)
- After DMC completes, OAM needs 1 extra alignment cycle
- Net overhead: ~2 cycles total

This is implemented functionally at logic.zig:41-42:
```zig
const dmc_is_stalling_oam = state.dmc_dma.rdy_low and
    state.dmc_dma.stall_cycles_remaining == 1;  // Only DMC read cycle
```

**Known Issues:**
- DMA logic is correct but comments are verbose (lines 24-40 explain hardware repeatedly)
- DmaInteractionLedger follows VBlank pattern (pure data) but is barely used
- Functional pattern works but deeply nested conditionals in tickOamDma (lines 44-96)

#### Subsystem 6: Bus Handler Architecture

**Files (7 handlers):**
- `src/emulation/bus/handlers/RamHandler.zig` - $0000-$1FFF (2KB RAM, 4x mirrored)
- `src/emulation/bus/handlers/PpuHandler.zig` - $2000-$3FFF (8 PPU regs, mirrored)
- `src/emulation/bus/handlers/ApuHandler.zig` - $4000-$4015 (APU channels)
- `src/emulation/bus/handlers/OamDmaHandler.zig` - $4014 (OAM DMA trigger)
- `src/emulation/bus/handlers/ControllerHandler.zig` - $4016-$4017 (controllers + APU frame counter)
- `src/emulation/bus/handlers/CartridgeHandler.zig` - $4020-$FFFF (mapper delegation)
- `src/emulation/bus/handlers/OpenBusHandler.zig` - Unmapped (returns last bus value)

**Handler Pattern (Zero-Size Stateless):**
```zig
pub const HandlerName = struct {
    // NO fields - completely stateless!

    pub fn read(_: *const HandlerName, state: anytype, address: u16) u8 { }
    pub fn write(_: *HandlerName, state: anytype, address: u16, value: u8) void { }
    pub fn peek(_: *const HandlerName, state: anytype, address: u16) u8 { }
};
```

**Bus Routing:** `EmulationState.busRead()` @ State.zig:232-268
- Switch on address ranges
- Delegates to handler.read(self, address)
- Captures open bus value (line 265: `self.bus.open_bus = value`)
- Exception: $4015 doesn't update open bus

**Known Issues:**
- Pattern is CORRECT (recent 2025-11-04 refactor, 98.1% pass rate)
- Documentation in CLAUDE.md is verbose (lines 189-312)
- Handler code has good comments but some redundancy
- Zero-size guarantee tested but not enforced at compile time

#### Subsystem 7: Clock Coordination and Timing

**Files:**
- `src/emulation/MasterClock.zig` - Master clock (358 lines with tests)
- `src/emulation/state/Timing.zig` - TimingStep struct and helpers
- `src/ppu/timing.zig` - PPU timing constants

**MasterClock Fields:**
```zig
pub const MasterClock = struct {
    master_cycles: u64 = 0,           // Monotonic counter (ALWAYS +1)
    speed_multiplier: f64 = 1.0,      // Emulation speed control
    initial_phase: u2 = 0,            // CPU/PPU phase offset (0, 1, or 2)
};
```

**Timing Model:**
- 1 CPU cycle = 3 master cycles (NES hardware ratio)
- Master clock advances monotonically (no skipping)
- PPU clock advances via PpuLogic.advanceClock() (handles odd frame skip)
- APU ticks same as CPU (every 3 master cycles)

**Critical Functions:**
- `advance()` - Increments master_cycles by 1 (ALWAYS)
- `isCpuTick()` - Returns true if (master_cycles % 3) == 0
- `cpuCycles()` - Returns master_cycles / 3

**The isApuTick() Problem:**
MasterClock.zig defines `isApuTick()` but it's NEVER IMPLEMENTED in the file! The grep results show it's only used in TESTS (lines 234, 237) to assert `isApuTick() == isCpuTick()`. This function doesn't exist but is referenced, creating confusion.

**Phase Independence:**
- Hardware has random phase at power-on (0, 1, or 2)
- Phase determines which PPU dots the CPU ticks at scanline 241
- VBlank prevention logic uses `isCpuTick()` instead of hardcoded dots (phase-independent)

**Known Issues:**
- MasterClock.zig is 358 lines but 200+ lines are tests
- Comments repeat hardware ratios multiple times (lines 4-23)
- cpuCycles() wrapper creates "CPU cycles vs master cycles" confusion
- isApuTick() ghost reference in tests

### Documentation Inventory: The Toxic Asset Problem

**112 Markdown Files Total** across the codebase.

**Top-Level Documentation (NEEDS COMPLETE REWRITE):**
- `README.md` - 528 lines mixing current status, old fixes, architecture overview
  - Lines 9-97: "Recent Fixes" section references 2025-11-04, 2025-11-03, 2025-11-02, 2025-10-15
  - Outdated as soon as written - contains snapshots instead of current state
  - Lines 232-270: Architecture section duplicates ARCHITECTURE.md
  - Lines 360-408: Component structure duplicates CLAUDE.md

- `CLAUDE.md` - 782 lines of development guidance
  - Lines 332-506: Critical Hardware Behaviors section (175 lines)
  - Extensive documentation of VBlank/NMI timing with nesdev.org citations
  - Lines 137-312: Bus Handler Architecture (176 lines) - just added 2025-11-04
  - Mixes reference documentation with implementation details
  - "Do not modify" warnings scattered throughout
  - Comments reference specific line numbers (e.g., "State.zig:651-774") that drift

- `ARCHITECTURE.md` - 940 lines of pattern reference
  - Lines 432-603: VBlank Pattern (Pure Data Ledgers) - 172 lines
  - Lines 699-777: DMA Interaction Model - 79 lines
  - Duplicates content from CLAUDE.md
  - Some sections reference removed functions/patterns

**Sessions Directory:**
- `sessions/tasks/h-fix-oam-nmi-accuracy.md` - Previous refactoring task
- `sessions/tasks/h-refactor-ppu-shift-register-rewrite.md` - PPU refactoring
- Multiple task files with outdated status, completed work marked as pending

**The Problem:**
Documentation was written DURING investigations, captures historical reasoning rather than current truth. Every fix adds a "Recent Fixes" section without removing old ones. Comments in code reference documentation line numbers. Documentation references code line numbers. Both drift over time.

**Ghost APIs in Documentation:**
- Line 670-677 in State.zig comments reference removed `applyNmiLine()` function
- Comments throughout explain WHY something was removed, not what's current
- "LOCKED BEHAVIOR" warnings prevent refactoring even when better patterns exist

### Test Infrastructure: Brittleness Patterns

**Test Organization:** `build/tests.zig` - Metadata table for all tests
- 15 test areas (cpu, ppu, apu, integration, etc.)
- 1162/1184 tests passing (98.1% pass rate)
- Tests span 97 files (from Glob results)

**Helper Functions:** `src/emulation/helpers.zig` - 108 lines
- `tickCpuWithClock()` - Advances clock 3 times then ticks CPU
- `emulateFrame()` - Runs until frame_complete flag (max 110,000 cycles safety check)
- `emulateCpuCycles()` - Runs N CPU cycles

**Test Helper Assumptions:**
1. Tests call `tickCpuWithClock()` instead of natural `tick()` progression
2. Helper has hardcoded 110,000 cycle limit (lines 65-76 with safety check)
3. Helper checks `debuggerShouldHalt()` - embeds debugger assumption in test infrastructure
4. No test helper exists for "tick N master cycles" - tests work in CPU cycle units

**Example Brittle Pattern (from emulateFrame):**
```zig
// Safety: Prevent infinite loop if something goes wrong
const max_cycles: u64 = 110_000;
const current_cycles = state.clock.master_cycles;
const elapsed = if (current_cycles >= start_cycle)
    current_cycles - start_cycle
else
    0;  // Underflow protection for threading tests
if (elapsed > max_cycles) {
    if (comptime std.debug.runtime_safety) {
        unreachable; // Debug mode only
    }
    break; // Release mode: exit gracefully
}
```

This is defending against undefined behavior in the test harness, not testing hardware accuracy.

**Configuration Dependencies:**
- Tests create `Config.Config.init(testing.allocator)`
- Config has ROM paths, debug flags, speed multipliers
- Test behavior changes based on config state
- No standard "test config" helper - each test builds its own

**Threading Tests (5 skipped):**
Per CLAUDE.md:681-683, threading tests are "timing-sensitive" and "Not a functional problem - mailboxes work correctly in production." This is the test infrastructure admitting defeat.

### Critical Code Paths Requiring Simplification

**Path 1: EmulationState.tick() - 250+ lines (456-706)**
Issues:
- Mixes timing decisions, component coordination, VBlank logic, debugger checks
- Inline comments exceed code (60+ lines of comments explaining sub-cycle execution)
- Multiple early returns for debugger halts
- VBlank timestamp application as separate function but PPU state application inlined

Simplification approach:
- Extract "timing coordinator" that just determines what ticks
- Extract "component executor" that dispatches to subsystems
- Extract "event applier" that handles VBlank/PPU state
- Reduce to ~50 lines of clear orchestration

**Path 2: CpuExecution.stepCycle() - 779 lines total file**
Issues:
- Deep nesting in addressing mode logic
- State machine dispatcher mixes DMA checks, warmup, execution
- Comments reference timing deviations without solutions
- Microsteps scattered across multiple functions

Simplification approach:
- State machine should be table-driven, not nested if/else
- DMA checks belong in DMA subsystem, not CPU execution
- Addressing modes should be pure functions, not stateful microsteps

**Path 3: PpuHandler.read/write - 250+ lines**
Issues:
- VBlank race detection, NMI line management, register I/O all mixed
- Comments repeat hardware citations multiple times
- Complex flag tracking (prevent_vbl_set_cycle logic)

Simplification approach:
- Separate "register I/O" from "timing effects"
- VBlank prevention is ONE check, not scattered across 50 lines
- NMI line updates should be explicit state transitions, not embedded in handler

### Areas Assumed to Have Same Problems (Not Investigated Yet)

Based on the patterns found in CPU/PPU/NMI:

**PPU Rendering Logic:** `src/ppu/logic/*.zig` modules
- Likely has deep nesting in sprite evaluation
- Background tile fetching probably has timing confusion
- Scroll register manipulation probably has wrapper functions

**APU Channel Logic:** `src/apu/logic/*.zig` modules
- Frame counter logic probably has nested conditionals
- DMC timing probably has comments about "compatibility"
- Envelope/sweep components might have over-abstraction

**Cartridge Mappers:** `src/cartridge/mappers/*.zig`
- Mapper implementations probably have inconsistent patterns
- IRQ timing probably has timing confusion
- CHR banking probably has confusing indirection

### Refactoring Priorities by Impact

**Priority 1 (Must Fix - Core Confusion):**
1. Eliminate `isApuTick()` ghost reference - Replace with `isCpuTick()` everywhere
2. Standardize timing model - Master cycles OR CPU cycles, not both interchangeably
3. Simplify EmulationState.tick() - Extract coordinator/executor/applier pattern
4. Consolidate VBlank logic - One function sets, one function clears, no scattered updates

**Priority 2 (High Value - Code Hygiene):**
5. Flatten CpuExecution nesting - Table-driven state machine
6. Decompose PpuHandler - Separate register I/O from timing effects
7. Simplify DMA logic - Remove verbose comments, extract timing checks
8. Standardize test helpers - One clear way to advance emulation in tests

**Priority 3 (Documentation Rebuild):**
9. Delete ALL documentation markdown files
10. Rewrite from working code - Document what IS, not what WAS
11. Remove line number references - Code and docs drift independently
12. Eliminate "LOCKED BEHAVIOR" warnings - Code should be self-documenting

**Priority 4 (Future Cleanup - Not Blocking):**
13. PPU rendering simplification
14. APU channel cleanup
15. Mapper pattern standardization
16. Test infrastructure redesign

### File Locations for Critical Paths

**Timing & Coordination:**
- `src/emulation/State.zig` (712 lines) - Main tick loop, bus routing, initialization
- `src/emulation/MasterClock.zig` (358 lines) - Master clock and timing
- `src/emulation/state/Timing.zig` - TimingStep struct
- `src/emulation/helpers.zig` (108 lines) - Test helpers

**CPU Execution:**
- `src/cpu/State.zig` (87 lines) - CPU registers and state
- `src/cpu/Logic.zig` (87 lines) - CPU pure functions
- `src/emulation/cpu/execution.zig` (779 lines) - Execution state machine
- `src/emulation/cpu/microsteps.zig` - Addressing mode microsteps

**PPU & VBlank:**
- `src/ppu/State.zig` - PPU state
- `src/ppu/Logic.zig` (506 lines) - PPU operations facade
- `src/emulation/VBlankLedger.zig` (81 lines) - VBlank timestamp ledger
- `src/emulation/bus/handlers/PpuHandler.zig` (250+ lines) - PPU register handler

**DMA Systems:**
- `src/emulation/state/peripherals/OamDma.zig` - OAM DMA state
- `src/emulation/state/peripherals/DmcDma.zig` - DMC DMA state
- `src/emulation/dma/logic.zig` (160+ lines) - DMA tick functions
- `src/emulation/DmaInteractionLedger.zig` - DMA conflict tracking

**APU:**
- `src/apu/State.zig` - APU state
- `src/apu/Logic.zig` - APU operations
- `src/apu/Dmc.zig` - DMC channel
- `src/apu/logic/registers.zig` - APU register I/O

**Bus Handlers (7 files):**
- `src/emulation/bus/handlers/RamHandler.zig`
- `src/emulation/bus/handlers/PpuHandler.zig` (MOST COMPLEX)
- `src/emulation/bus/handlers/ApuHandler.zig`
- `src/emulation/bus/handlers/OamDmaHandler.zig`
- `src/emulation/bus/handlers/ControllerHandler.zig`
- `src/emulation/bus/handlers/CartridgeHandler.zig`
- `src/emulation/bus/handlers/OpenBusHandler.zig`

**Test Infrastructure:**
- `build/tests.zig` (100+ lines) - Test metadata table
- `src/emulation/helpers.zig` - Emulation test helpers
- `tests/**/` - 97 test files across 15 areas

**Documentation (112 files total):**
- `README.md` (528 lines)
- `CLAUDE.md` (782 lines)
- `ARCHITECTURE.md` (940 lines)
- `sessions/` - Task tracking and session notes

### What Needs Complete Rewrite vs Cleanup

**Complete Rewrite:**
1. `src/emulation/State.zig:tick()` - 250+ line monolith → 50 line coordinator
2. `src/emulation/cpu/execution.zig` - 779 lines with deep nesting → table-driven state machine
3. All documentation (README, CLAUDE, ARCHITECTURE) - Delete and rebuild from code

**Cleanup (Good Bones, Bad Presentation):**
4. `src/emulation/VBlankLedger.zig` - Pattern is CORRECT, just remove verbose comments
5. `src/emulation/dma/logic.zig` - Logic is CORRECT, flatten nested conditionals
6. `src/emulation/bus/handlers/*.zig` - Pattern is CORRECT, reduce comment redundancy
7. `src/emulation/MasterClock.zig` - Remove wrapper cruft (isApuTick), simplify

**Keep As-Is (Already Clean):**
8. `src/cpu/State.zig` - 87 lines of pure data
9. `src/cpu/Logic.zig` - 87 lines of pure functions
10. Handler pattern architecture - Zero-size stateless is ideal

### Success Criteria Validation

Can we meet the stated success criteria?

**"A new developer can read ANY subsystem and understand it without docs"**
- Current: NO - tick() is 250+ lines with inline comments as crutches
- After refactor: YES - Extract coordinator pattern, 50 line orchestration

**"Debugging doesn't require fighting through indirection layers"**
- Current: NO - cpuCycle() wraps master_cycles, isApuTick() doesn't exist, helpers wrap tick()
- After refactor: YES - One timing model (master cycles), direct function calls

**"No 'but actually...' caveats when explaining how something works"**
- Current: NO - "VBlank flag vs span", "CPU cycles vs master cycles", "isApuTick is really isCpuTick"
- After refactor: YES - VBlank flag IS the flag, master cycles IS the timing, APU ticks ARE CPU ticks

**"The codebase doesn't lie to developers"**
- Current: NO - Comments reference removed functions, docs reference old line numbers, ghost APIs exist
- After refactor: YES - Code is source of truth, comments only for hardware citations

**"Critical paths readable in 30 seconds"**
- Current: NO - tick() takes 5+ minutes to understand, execution.zig requires investigation
- After refactor: YES - Coordinator dispatches to clear subsystems, state machine is table-driven

## User Notes
<!-- Any specific notes or requirements from the developer -->

## Work Log

### 2025-11-06

#### Task Creation & Context Gathering
- Created comprehensive task for complete emulator codebase cleanup
- Context-gathering agent mapped entire system (712-line tick loop, 7 subsystems, 112 docs)
- Identified systemic problems: wrapper hell (isApuTick ghost function), toxic documentation, timing confusion

#### Investigation Phase: Architectural Issues Identified
- **God Object Problem**: EmulationState does EVERYTHING - CPU, PPU, APU, DMA coordination mixed into single object
- **Separation of Concerns Violation**: tick() extracts `ppu.scanline/cycle` then passes to `stepPpuCycle()` - backwards coupling
- **Pointless Wrappers**: `nextTimingStep()` just wraps `isCpuTick()` in struct, adds zero value
- **Method Misplacement**: `stepPpuCycle()`, `stepApuCycle()` are EmulationState methods but should be in respective modules
- **Test Helper Pollution**: `tickCpuWithClock()`, `emulateFrame()`, `emulateCpuCycles()` in production State struct

#### Fundamental Architecture Questions Surfaced
- Why does tick() care about PPU internals (scanline/dot)?
- Should stepPpuCycle() even need coordinates - shouldn't PPU know where it is?
- Module structure: State.zig as coordinator vs implementation - currently both
- Comments explain WHAT (obvious from code) not WHY (design decisions)

#### Session Outcome
- Realized surface-level audit insufficient - need deep architectural rethinking
- Session ended with recognition that problems run deeper than comments/wrappers
- Need big-picture redesign of subsystem boundaries and responsibility allocation

---

### 2025-11-06 (Session 2 - Cleanup & Review Foundation)

#### Critical Objective Section Added
- Added prominent ⚠️ CRITICAL OBJECTIVE section at top of task file (lines 10-42)
- Explicitly lists what this task IS: methodical review, cleanup, refactoring
- Explicitly lists what this task IS NOT: making tests pass, quick fixes, planning
- Provides work approach checklist and warning signs to watch for

#### Complete Subsystem Reviews Completed
- Line-by-line review of cpu/Execution.zig (779 lines) with detailed findings
- Line-by-line review of cpu/Microsteps.zig (383 lines) - identified as GOOD CODE template
- Research of 4 questionable patterns: PPU warmup duplication, DMA coordination coupling, opcode duplication, completion check mirrors
- Critical architectural issue surfaced: EmulationState extracting PPU internals (backwards coupling)

#### Line-by-Line Review: cpu/Execution.zig (779 lines)

**File Structure:**
- Lines 0-52: Module-level documentation (52 lines)
- Lines 54-61: Imports and constants
- Lines 76-162: `stepCycle()` function (87 lines)
- Lines 174-779: `executeCycle()` function (605 lines!)

**Comment Problems:**

1. **Excessive top-level docs** (lines 0-52):
   - 52 lines of doc comments describing WHAT code does
   - Should describe WHY and hardware citations only
   - Most content is obvious from reading function signatures

2. **External references that drift** (lines 30-37):
   - "Documented in CLAUDE.md:89-95" - will drift as CLAUDE.md changes
   - "Mitigated by fallthrough logic (lines 1115-1135 in original)" - references OLD line numbers
   - Should explain timing deviation HERE, not point elsewhere

3. **Function comment lies** (line 75):
   - Says "Returns: CpuCycleResult with mapper_irq flag"
   - Actual signature: `pub fn stepCycle(state: anytype) void`
   - Comment is WRONG

4. **Comments point elsewhere** (lines 92-94):
   - "NMI line is now updated in State.zig tick()"
   - Doesn't help reader understand THIS function
   - Creates indirection - have to go read other file

5. **Verbose explanatory blocks** (lines 178-194):
   - 17 lines explaining interrupt restoration
   - Good content but could be 5 lines with nesdev.org citation

**Code Structure Problems:**

1. **stepCycle() is really two functions** (lines 76-162):
   - Lines 77-105: PPU warmup + debugger + CPU halted checks
   - Lines 107-162: DMA coordination
   - Should be split - these are separate concerns

2. **PPU functionality in CPU module** (lines 80-90):
   - Checks `state.ppu.warmup_complete`
   - Sets `state.ppu.mask`
   - Line 87: Inline import `@import("../ppu/State.zig").PpuMask` - ugly
   - WHY is CPU execution handling PPU warmup?

3. **DMA coordination mixed with CPU execution** (lines 107-162):
   - 55 lines of DMA edge detection and coordination
   - Lines 117-118: `was_paused` calculation via timestamp comparison - confusing
   - This feels like DMA module responsibility, not CPU

4. **God function: executeCycle()** (lines 174-779):
   - 605 lines in single function
   - Handles 4 different CPU states
   - 348 lines just for addressing mode microsteps (lines 318-666)

5. **Deeply nested switches** (lines 318-666):
   - Pattern: switch opcode → switch cycle → call microstep
   - Lines 331-397: Control flow opcodes (66 lines of nested switches)
   - Lines 399-562: Regular addressing modes (163 lines of nested switches)
   - This is TABLE data expressed as CODE

6. **DRY violations - hardcoded opcode lists**:
   - Lines 301-307: Control flow opcodes listed
   - Lines 324-327: SAME list again
   - Lines 333-396: Opcodes dispatched individually (JSR, RTS, RTI, BRK, etc.)
   - Lines 578-586: SAME opcodes checked AGAIN for completion
   - If we add a control flow opcode, must update 4+ places

7. **Completion check duplicates structure** (lines 576-640):
   - 64 lines checking "is addressing done?"
   - Mirrors the dispatch structure from lines 331-562
   - Hardcoded magic numbers (>= 3, >= 4, >= 5)
   - Should be derivable from dispatch table, not separate code

8. **Fallthrough workaround** (lines 645-666):
   - Lines 651-654: Hardcoded check for specific addressing modes
   - This is the "mitigation" mentioned in line 35
   - Unclear WHY this works - just that it does

9. **Operand extraction switch** (lines 672-709):
   - ANOTHER switch on addressing mode
   - Lines 684-696: Special case for STA/STX/STY - hardcoded opcodes
   - Could this be table-driven?

**Dead Code:**
- Lines 58-59: `CycleResults` imported but never used
- Line 60: Comment "DMA interaction logic is now inline" - this is a note, not docs

**Naming Issues:**
- `stepCycle` vs `executeCycle` - unclear distinction (both sound like "run CPU")
- `complete` (lines 238, 331, 566) - generic, what IS complete?
- `addressing_done` (line 576) - boolean but logic spans 64 lines
- `should_fallthrough` (line 651) - doesn't explain WHY

**Architectural Coupling:**
1. CPU execution knows about PPU warmup (lines 80-90)
2. CPU execution does DMA coordination (lines 107-162)
3. Inline PPU imports (line 87)

**What's Good:**
- Clear state machine (4 states, well-defined transitions)
- Microsteps module separation is clean
- Hardware citations present (nesdev.org, Mesen2)
- Interrupt handling structure is logical (lines 234-287)
- Operand extraction handles edge cases (lines 684-696)

**Key Findings:**
1. executeCycle() should be table-driven, not 605 lines of nested switches
2. PPU warmup doesn't belong in CPU execution
3. DMA coordination doesn't belong in CPU execution
4. Opcode lists appear 4+ times - needs centralization
5. Comments mostly describe WHAT (obvious), not WHY (valuable)
6. External documentation references will drift

#### Line-by-Line Review: cpu/Microsteps.zig (383 lines)

**File Structure:**
- Lines 1-5: Module-level documentation (5 lines) - concise, good
- Lines 7-383: 30 microstep functions (pure, atomic operations)

**Overall Assessment: THIS IS GOOD CODE**

This file is a stark contrast to Execution.zig. Clean, focused, atomic functions.

**What's Excellent:**
1. **Single responsibility**: Each function does ONE thing
2. **Clear naming**: Function names describe exactly what they do
3. **Consistent pattern**: All functions take `state: anytype`, return `bool`
4. **Pure operations**: No hidden side effects, everything through `state` parameter
5. **Minimal comments**: Only where hardware behavior isn't obvious
6. **Good hardware citations**: Lines 197-200 explain B flag behavior with nesdev.org reference
7. **Appropriate length**: Longest function is 35 lines (branchFetchOffset), most are 5-10 lines

**Comment Quality (Mostly Good):**

1. **Lines 1-5**: Module doc is concise and accurate
   - "These atomic functions perform hardware-perfect CPU operations"
   - Explains return value meaning
   - No fluff

2. **Lines 48-51**: Good critical comment explaining dummy read behavior
   - "CRITICAL: Dummy read at wrong address (base_high | result_low)"
   - This is non-obvious hardware behavior - comment is valuable

3. **Lines 67-80**: Good multi-line comment in fixHighByte()
   - Explains difference between reads and RMW
   - Explains what temp_value contains in different scenarios
   - Actually helpful

4. **Lines 140-146**: Excellent critical comment in addYCheckPage()
   - "CRITICAL: When page NOT crossed, the dummy read IS the actual read"
   - Explains non-intuitive hardware behavior
   - This is what comments SHOULD do

5. **Lines 193-200**: Excellent hardware citation for pushStatusInterrupt()
   - Links to nesdev.org with specific anchor
   - Explains B flag behavior clearly
   - Shows bit patterns (0b01 vs 0b11)

**Minor Issues:**

1. **Line 30, 37, 92**: Comment "// Dummy read" is obvious from discarding the return value
   - The `_ =` pattern makes this clear without comment
   - Could delete these

2. **Lines 67-69**: Comment could be more concise
   - Current: "Fix high byte after page crossing / For reads: Do REAL read when page crossed / For RMW: This is always a dummy read"
   - Better: "Fix high byte after page crossing (real read for loads, dummy for RMW)"

3. **Line 105**: Complex type casting that might benefit from brief comment
   - `@as(u16, @as(u8, @truncate(state.cpu.temp_address)) +% 1)`
   - This wraps within zero page - comment would help

4. **Line 353**: Complex dummy address calculation in branchFixPch()
   - Formula is cryptic: `(state.cpu.pc & 0x00FF) | ((state.cpu.pc -% ...) & 0xFF00)`
   - A one-line comment explaining WHY would help

**Code Quality (Excellent):**

1. **Consistent casting pattern**: Uses `@as(u16, ...)` consistently for type safety
2. **Wrapping arithmetic**: Uses `+%` and `-%` where appropriate (zero page wrapping, etc.)
3. **No magic numbers** (except hardware constants like 0x0100 for stack, 0xFFFE for vectors)
4. **Clear variable names**: `base`, `offset`, `dummy_addr`, `stack_addr` - all obvious
5. **Hardware-accurate**: Functions implement exact 6502 microstep behavior

**Comparison to Execution.zig:**

| Aspect | Microsteps.zig | Execution.zig |
|--------|---------------|---------------|
| Lines per function | 5-35 (avg ~13) | 87, 605 (massive) |
| Comment ratio | ~10% | ~40% |
| Comment quality | Hardware behavior | Mostly "what" not "why" |
| Single responsibility | Yes | No (god functions) |
| Naming clarity | Excellent | Mixed |
| Code duplication | None | Opcode lists 4+ times |

**Why This Works:**

1. Each function is a "building block" used by Execution.zig
2. Functions are composable - easy to test in isolation
3. No conditional logic - just direct operations
4. Hardware behavior is encoded in the SEQUENCE of calls, not in the functions themselves
5. Clear contract: `bool` return indicates early completion

**What Could Be Better:**

1. **Line 241**: `@TypeOf(state.cpu.p).fromByte(status)` - could extract to local var for clarity
2. **Lines 283-292**: rmwRead() switch could use comments on each case (what mode)
3. **Lines 313-323**: Branch condition switch is hardcoded opcodes (same issue as Execution.zig)
   - But at least it's isolated to ONE function
   - Could still be table-driven

**Dead Code:**
- None detected

**Naming Issues:**
- None - names are clear and descriptive

**Architectural Issues:**
- None - clean separation of concerns

**Key Findings:**
1. This is how code SHOULD look - clean, focused, well-named
2. Comments explain hardware behavior, not obvious code
3. Functions are composable building blocks
4. Length is appropriate (5-35 lines per function)
5. No duplication or god functions
6. This file should be the TEMPLATE for refactoring Execution.zig

**Recommendation:**
- Keep this file mostly as-is
- Minor comment cleanup (remove "// Dummy read" redundancy)
- Add brief comments to complex calculations (lines 105, 353)
- Consider table-driven branch conditions (lines 313-323)
- Otherwise, this is GOOD CODE - don't overengineer it

#### Research: Questionable Patterns Investigation

**Context:** During line-by-line review of cpu/Execution.zig, identified 4 patterns that warranted deeper investigation to understand architectural decisions.

**Pattern 1: PPU Warmup in CPU Execution**

**Finding:** PPU warmup is managed in FOUR places:
1. `cpu/Execution.zig:82` - Sets `warmup_complete = true` AND applies buffer
2. `emulation/State.zig:256` - Sets `warmup_complete = true`
3. `emulation/bus/handlers/PpuHandler.zig:273` - Sets `warmup_complete = true`
4. `ppu/Logic.zig:38` - Sets `warmup_complete = true`

**Analysis:**
- PPU register handler (`ppu/logic/registers.zig:318`) BUFFERS PPUMASK writes during warmup
- CPU execution (`cpu/Execution.zig:80-90`) checks cycle count, sets `warmup_complete`, AND applies buffer
- This is DUPLICATION - both PPU and CPU know about warmup

**Root cause:**
- Warmup completion is time-based (29,658 CPU cycles)
- CPU execution checks cycle count → sets flag → applies buffer
- But PPU registers also check the flag and buffer writes
- The buffer application in CPU execution seems redundant

**Question:** Why doesn't PPU module apply its own buffer when warmup completes?
- Answer: Because warmup completion is detected in CPU execution based on CPU cycle count
- PPU doesn't know CPU cycle count without coordination

**Architectural issue:**
- Warmup is PPU hardware behavior
- But completion depends on CPU cycle count
- This creates coupling: CPU must know about PPU warmup
- Better: PPU tracks its own warmup via cycle count passed to it

**Pattern 2: DMA Coordination in CPU Execution**

**Finding:** DMA coordination logic split between:
1. `cpu/Execution.zig:107-162` - Edge detection, pause/resume timestamps (55 lines)
2. `emulation/dma/logic.zig` - Actual DMA tick functions

**Analysis:**
- CPU execution does DMC edge detection (`dmc_was_active` vs `dmc_is_active`)
- Updates `dma_interaction_ledger` timestamps
- Detects OAM pause/resume based on timestamps
- Then delegates to `tickDma()` and `tickDmcDma()`

**Why is this in CPU execution?**
- DMA affects CPU execution (RDY line stalls CPU)
- Edge detection determines when to update timestamps
- But the actual DMA logic is already in dma/logic.zig

**Architectural issue:**
- DMA coordination could be in DMA module
- CPU just needs to check "am I stalled?" not "detect edges and manage timestamps"
- Edge detection could be internal to DMA module
- CPU just calls `dma.shouldStallCpu()` → bool

**Pattern 3: Opcode Duplication**

**Finding:** Control flow opcodes hardcoded in 4+ places in Execution.zig:
1. Lines 301-307: Check if addressing needed
2. Lines 324-327: Check if control flow
3. Lines 333-396: Dispatch individual opcodes
4. Lines 578-586: Check if addressing complete

**Analysis:**
- JSR, RTS, RTI, BRK, PHA, PLA, PHP, PLP listed multiple times
- If we add a control flow opcode, must update all locations
- This is brittle

**Why this exists:**
- Control flow opcodes have custom microstep sequences
- They're marked as `.implied` or `.absolute` in dispatch table
- But they need addressing cycles despite this
- Execution.zig needs special handling

**Better approach:**
- Add `is_control_flow` flag to dispatch table entry
- Check once: `if (entry.is_control_flow) ...`
- Opcode list exists in ONE place (dispatch table)
- No duplication

**Pattern 4: Addressing Completion Check Duplication**

**Finding:** Lines 576-640 check "is addressing done?" for each mode
- Mirrors dispatch structure from lines 331-562
- Hardcoded thresholds (>= 3, >= 4, >= 5)

**Analysis:**
- Dispatch: switch mode → switch cycle → call microstep
- Completion: switch mode → check cycle >= threshold
- The threshold COULD be derived from dispatch table
- Add `addressing_cycles` field to dispatch table entry

**Better approach:**
```zig
const addressing_done = state.cpu.instruction_cycle >= entry.addressing_cycles;
```
- One check, no duplication
- Thresholds defined in dispatch table
- Change in one place applies everywhere

**Key Recommendations:**

1. **PPU warmup:** Move completion check to PPU module, pass CPU cycle count as parameter
2. **DMA coordination:** Move edge detection to DMA module, CPU just checks `shouldStallCpu()`
3. **Opcode duplication:** Add `is_control_flow` flag to dispatch table
4. **Completion check:** Add `addressing_cycles` to dispatch table, derive threshold

**All of these point to the same solution: Make dispatch table richer, reduce hardcoded logic**

#### Session Outcome & Critical Discovery

**Work Completed:**
1. Added CRITICAL OBJECTIVE section to prevent future session drift
2. Fixed all broken imports in moved files (cpu/Execution.zig, emulation/helpers.zig)
3. Build compiles successfully
4. Completed line-by-line review of cpu/Execution.zig (779 lines) - documented findings with line numbers
5. Completed line-by-line review of cpu/Microsteps.zig (383 lines) - identified as GOOD CODE template
6. Researched 4 questionable patterns (PPU warmup, DMA coordination, opcode duplication, completion checks)

**CRITICAL ARCHITECTURAL ISSUE IDENTIFIED BY USER:**

During review, user pointed out fundamental problem that demonstrates systemic coupling:

```zig
// src/emulation/State.zig (line ~806-814) - applyPpuRenderingState()
pub fn applyPpuRenderingState(...) void {
    const scanline = state.ppu.scanline;  // ← EmulationState extracting PPU internals
    const dot = state.ppu.cycle;          // ← This is backwards coupling
    ...
}
```

**The Problem:** EmulationState is extracting PPU state (scanline, cycle) to make decisions about PPU behavior. This violates proper module boundaries.

**Why This Matters:**
- PPU should know where IT is, not external coordinator
- God object pattern: EmulationState doing EVERYTHING
- Explains wrapper hell and indirection problems throughout codebase
- Similar pattern likely exists for CPU, APU, DMA (all managed by EmulationState)

**What This Reveals:**
- The refactoring needs aren't just comment cleanup
- Fundamental architectural boundary violations need fixing
- EmulationState has too many responsibilities
- Module separation is broken at the root level

**Next Steps Identified:**
1. Continue documentation of ALL subsystems to identify similar patterns
2. Map out proper module boundaries (what SHOULD own what)
3. Design clean separation of concerns
4. Refactor with discipline

---

---

### 2025-11-06 (Session 3 - Comment Cleanup & VBlank Migration Start)

#### Part 1: CPU Execution Comment Cleanup (COMPLETED)
**Massive comment reduction:** cpu/Execution.zig reduced from 779 → 563 lines (-216 lines)

**Changes:**
- Removed 42 lines of verbose module-level documentation
- Deleted function docs that contradicted code (wrong return type claims)
- Removed 26+ line blocks explaining interrupt state restoration → replaced with 3-line hardware citation
- Deleted 55+ lines of DMA coordination verbose comments
- Removed 244+ lines of addressing mode switch comments (redundant explaining obvious)
- Consolidated inline comments throughout for clarity
- Added dummyRead() helper (State.zig:307-311) to clarify hardware-accurate bus accesses
- Replaced all `_ = state.busRead()` patterns with explicit `state.dummyRead()` calls (7 instances)

**Result:**
- Code-to-comment ratio improved dramatically
- All hardware citations preserved (nesdev.org, Mesen2)
- Critical timing comments retained (second-to-last cycle rule, interrupt hijack)
- Build compiles successfully

#### Part 2: VBlank Subsystem Refactoring (INCOMPLETE - STOPPED)

**Architectural Problem Identified:**
EmulationState violates module boundaries - extracts PPU internals (scanline/cycle/nmi_enable) to manage VBlank. PPU should own and manage its own state.

**Work Attempted:**
1. Moved VBlankLedger.zig → ppu/VBlank.zig (git mv preserves history)
2. Renamed type VBlankLedger → VBlank
3. Started adding vblank and nmi_line fields to PpuState
4. Started refactoring PPU Logic.tick() signature

**Critical Issues Encountered:**
- **Half-assing pattern:** Left broken references mid-refactoring without completing
- **Build broken:** State.zig:618 calls old Logic.tick() signature
- **Incomplete:** VBlank migration only 8/28 items done, deferred with "context compaction"
- **Not cleaned:** Comments still describe old behavior, accumulating technical debt

**Why Work Stopped:**
User feedback: This approach violates task principles - "don't propose, DO the work" and "complete each refactoring fully before stopping." Partial refactoring creates cascading breaks and misleading code.

**Session Outcome:**
- Session 3 demonstrated exactly what task CRITICAL OBJECTIVE warns against
- Comment cleanup was successful and complete
- VBlank refactoring should NOT have been started if not finishing
- Lesson: One atomic unit at a time (complete or revert)

---

### 2025-11-07 (Session 4 - VBlank Ownership Migration - INCOMPLETE)

#### VBlank Ownership Migration: Critical Architectural Refactor

**Work Completed:**
1. ✅ Moved VBlankLedger.zig → ppu/VBlank.zig (via git mv, preserves history)
2. ✅ Renamed type: VBlankLedger → VBlank
3. ✅ Added vblank field to PpuState (PPU owns VBlank state)
4. ✅ Added nmi_line output signal to PpuState (PPU computes NMI line internally)
5. ✅ Added framebuffer ownership to PpuState (moved from EmulationState)
6. ✅ Fixed framebuffer access in wasm.zig and EmulationThread.zig (state.ppu.framebuffer)
7. ✅ Deleted stepPpuCycle() from EmulationState (no more extracting PPU internals)
8. ✅ Updated EmulationState.tick() to call ppu.tick() directly
9. ✅ Moved VBlank set/clear logic into ppu/Logic.tick() (scanline 241, -1)
10. ✅ PPU computes nmi_line internally (vblank_flag AND ctrl.nmi_enable)
11. ✅ Wired ppu.nmi_line → cpu.nmi_line in EmulationState.tick()
12. ✅ Deleted vblank_ledger field and applyVBlankTimestamps() from EmulationState
13. ✅ Updated PpuHandler to access state.ppu.vblank instead of state.vblank_ledger
14. ✅ Removed rendering_enabled caching from EmulationState

**Import Path Updates (5 files):**
- ✅ emulation/State.zig - Changed VBlankLedger → VBlank import
- ✅ ppu/Logic.zig - Fixed import path
- ✅ bus/handlers/PpuHandler.zig - Updated VBlank import
- ✅ snapshot/state.zig - Fixed VBlank references
- ✅ ppu/logic/registers.zig - Updated VBlank references

**Build Status:** ✅ Successful compilation

#### Critical Discoveries: Additional Coupling Requiring Deeper Refactor

**EmulationState still caches PPU state:**
- `frame_complete` field duplicates ppu.frame_complete
- `odd_frame` field duplicates ppu.odd_frame
- These should be read from PPU, not cached in emulator

**Wrapper layers creating unnecessary complexity:**
- `PpuCycleResult` struct just wraps flags - delete and use direct reads
- `TickFlags` struct - PPU returning events instead of managing state directly
- `applyPpuRenderingState()` function orchestrating PPU internals from outside

**PPU Logic.tick() signature still problematic:**
- Currently receives `scanline, dot` parameters that PPU already knows
- EmulationState extracts ppu.scanline/ppu.cycle then passes them back
- Should receive only `master_cycles` and manage timing internally

**advanceClock() design flaw:**
- Takes `rendering_enabled` as parameter instead of reading state.mask internally
- PPU should read its own mask register, not have it passed in

**A12 rising edge notification delegated to emulator:**
- PPU computes A12 state but emulator notifies cartridge
- PPU should handle A12 notification directly via cartridge reference

#### Session Issues: Poor Execution Pattern

**User Feedback Summary:**
Session marked by significant frustration with:
- **Hedging and incomplete investigation** - Not fully exploring coupling before proposing solutions
- **Poor todo ordering** - Listed work in wrong dependency order (delete before add)
- **Reactive approach** - Fixing one thing at a time without understanding full dependency graph
- **Inconsistency** - Multiple rounds of "corrected" todos without actually executing
- **God object persistence** - Continuing to centralize ownership in EmulationState

**Specific Complaints:**
1. "Why are there two steps? What the fuck? You need to actually be an effective developer."
2. "framebuffer? Does that belong in the emulator? WHAT THE FUCK? Why do you insist the emulator contain everything?"
3. "This session has been marked by inconsistency, hedging, pedantic behavior bordering on incompetence/malice"

**Root Problem Identified:**
EmulationState god object pattern - coordinator reaches into subsystems, extracts state, orchestrates behavior from outside instead of letting subsystems manage themselves.

**Example of backwards coupling:**
```zig
// WRONG (current)
const scanline = self.ppu.scanline;  // Extract from PPU
const dot = self.ppu.cycle;          // Extract from PPU
PpuLogic.tick(&self.ppu, scanline, dot, ...);  // Pass back!

// CORRECT (needed)
PpuLogic.tick(&self.ppu, master_cycles, cart);  // PPU manages itself
```

#### Next Steps Required for Complete Decoupling

**Remaining wrapper elimination:**
1. Delete `frame_complete` and `odd_frame` from EmulationState
2. Read `state.ppu.frame_complete` directly in helpers
3. Delete `PpuCycleResult` struct entirely
4. Make `PpuLogic.tick()` return void instead of TickFlags
5. Remove `scanline, dot` parameters from tick() - PPU manages timing
6. Remove `rendering_enabled` parameter from advanceClock() - read mask internally
7. PPU handles A12 notification to cartridge directly
8. Delete `applyPpuRenderingState()` - PPU manages state internally

**Core architectural fix:**
EmulationState.tick() should wire signals between subsystems, NOT orchestrate their internals.

---

### 2025-11-07 (Session 6 - Phase 6 Completion & Bug Fixes)

#### Phase 6: Complete PPU Decoupling - COMPLETED

**Work Completed:**
1. ✅ Deleted cached PPU state fields from EmulationState (frame_complete, odd_frame, rendering_enabled)
2. ✅ Removed all PPU wrapper structures (PpuCycleResult deleted from CycleResults.zig)
3. ✅ Removed TickFlags struct from ppu/Logic.zig
4. ✅ Deleted applyPpuRenderingState() orchestration function
5. ✅ Cleaned up snapshot serialization (removed odd_frame, rendering_enabled from writeEmulationStateFlags/readEmulationStateFlags)
6. ✅ Simplified EmulationState.tick() to pure signal wiring (3 lines for PPU)
7. ✅ Fixed all import references to removed types

**Architecture Result:**
```zig
// EmulationState.tick() - Final PPU section (3 lines)
PpuLogic.advanceClock(&self.ppu);
PpuLogic.tick(&self.ppu, self.clock.master_cycles, cart_ptr);
self.cpu.nmi_line = self.ppu.nmi_line;  // Wire signal
```

**Phase 6 Outcome:**
- Zero wrapper layers between EmulationState and PPU
- PPU fully self-contained (owns vblank, nmi_line, framebuffer, frame_complete)
- Clean signal-based architecture established
- EmulationState.tick() reduced from 250+ lines to ~8 lines for PPU (96% reduction)

#### Critical Bug Fixes During Refactoring

**Bug Fix 1: Snapshot Serialization Mismatch**
- **Problem:** Snapshot code tried to read `state.odd_frame` and `state.rendering_enabled` fields that didn't exist in EmulationState
- **Root Cause:** Snapshot serialization functions not updated after field deletions
- **Fix:** Removed odd_frame and rendering_enabled from `writeEmulationStateFlags()` and `readEmulationStateFlags()`
- **Impact:** Prevented compilation failure when snapshot code tried to access deleted fields

**Bug Fix 2: PpuCycleResult Import Dead Code**
- **Problem:** EmulationState.zig imported PpuCycleResult type that was no longer used after refactoring
- **Root Cause:** Import statement left behind after deleting applyPpuRenderingState() function that used the type
- **Fix:** Removed `const PpuCycleResult = CycleResults.PpuCycleResult;` import from State.zig
- **Impact:** Cleaned up dead imports that would fail after PpuCycleResult struct deletion

**Bug Fix 3: Empty Snapshot Serialization Functions**
- **Problem:** User caught "hedging" pattern - empty functions with comment "keeping function for future extensibility"
- **Root Cause:** After removing all fields from serialization, left empty functions instead of deleting them
- **Fix:** Initially attempted to keep empty functions, user corrected to delete functions entirely from Snapshot.zig call sites
- **Impact:** Prevented accumulation of dead code with justification comments
- **Lesson:** Don't leave empty functions "for future use" - delete them and restore if actually needed later

**Compilation Status:**
- ✅ zig build successful
- ✅ All imports resolved
- ✅ No dead code warnings
- ✅ Snapshot code compiles without accessing deleted fields

#### Testing Status
- Test compilation not performed (focus on structural refactoring)
- Browser emulator functionality not verified this session
- Integration testing deferred to next phase

#### Session Outcome
Phase 6 (Complete PPU Decoupling) is COMPLETE. All wrapper layers eliminated, PPU is fully self-contained black box. The three bug fixes were caught and resolved during implementation:
1. Snapshot serialization updated to match current EmulationState struct
2. Dead imports removed from State.zig
3. Empty functions deleted instead of leaving "future extensibility" stubs

**Next Phase:** Phase 7 - CPU Subsystem Refactoring (table-driven execution, same decoupling pattern as PPU)

---

## Discovered During Implementation

### Date: 2025-11-07 / Sessions 3-4 Context Refinement

During this session's comment cleanup and VBlank refactoring work, several critical discoveries emerged about the codebase's actual behavior versus its documented architecture. These discoveries reveal systemic patterns that affect how the emulator operates and must be understood before further refactoring.

#### Discovery 1: "God Object" Pattern - EmulationState Owns Everything and Extracts Internal State

**What was discovered:**
When refactoring code (particularly during VBlank subsystem work in earlier sessions), breaking changes were left incomplete. For example:
- Files were moved but callers weren't updated
- Function signatures were changed but all call sites weren't fixed
- Comments weren't cleaned as changes were made - they accumulated describing old behavior
- Work was deferred with assumptions it would be "caught later"

**Why this matters:**
- Build breaks compound quickly with cascading undefined method calls
- Half-done refactoring leaves misleading comments that contradict current code
- Next developer has to figure out which comments are old and which are current
- Creates "technical debt anchors" - bad patterns that prevent further improvement

**Evidence:**
State.zig:618 from Session 3 showed a broken `Logic.tick()` call with old signature. Similar pattern appeared with broken imports, missing helper functions (like `tickCpu()` that doesn't exist but is called in helpers.zig).

**Impact on refactoring approach:**
- **DO NOT defer work** - Complete each refactoring fully before stopping
- **Clean comments as you go** - Don't leave stale documentation that contradicts code
- **Verify build after each change** - Catch cascading failures immediately
- **One atomic unit at a time** - Move file, fix all imports, clean all comments, test - in one pass

#### Discovery 2: Comment Cleanup Scope Vastly Underestimated

**What was discovered:**
Initial scope was 46 lines of Execution.zig comments. Actual scope: **216+ lines** (779 → 563).

This represents the "tip of the iceberg" problem - when surfacing one problematic area (module docs at line 1-53), the pattern extends throughout the entire file:
- Lines 63-75: Verbose function docs lying about return type
- Lines 78-90: PPU warmup comment block (13 lines)
- Lines 93-95: Redirect comments pointing elsewhere
- Lines 107-123: DMC completion handling comments (verbose)
- Lines 125-139: DMC edge detection comments
- Lines 141-158: DMA coordination comments
- Lines 164-177: Execution cycle comment blocks
- Lines 178-203: MASSIVE interrupt state restoration comments

**Why this matters:**
- Surface-level spot checks miss the pattern - must read ENTIRE files
- Each subsystem (CPU, PPU, APU, DMA) likely has same verbose comment disease
- Estimated cleanup work was approximately 3x-4x underestimated in initial assessment
- "Everywhere" problem - not isolated to one module

**Actual vs. Estimated:**
- Estimated: ~50 lines of deletions
- Actual: ~216 lines deleted from single file
- Projected for entire codebase: Similar pattern across 10+ core modules

**Impact on task planning:**
- Documentation cleanup will take longer than anticipated
- Need full-file audit approach, not spot-check methodology
- "Read every line" instruction in task README is critical for accurate work

#### Discovery 3: Critical Timing Comments Preserve Hardware Accuracy

**What was discovered:**
During aggressive comment cleanup, some verbose-looking comments actually document non-obvious hardware behavior:
- "Dummy read" pattern comments appeared redundant but served purpose in context
- Verbose "RESTORE INTERRUPT STATE" block documented subtle second-to-last-cycle rule
- Comments linking to nesdev.org citations were initially marked for deletion but needed preservation

**The pattern:**
- Comments that say "CRITICAL:" or link to hardware documentation → KEEP
- Comments that explain non-obvious code flow → KEEP
- Comments that restate obvious code logic → DELETE
- Comments that redirect to other files → DELETE

**Why this matters:**
- Can't delete comments blindly based on line count
- Must distinguish between "verbose explaining obvious" vs "essential explaining non-obvious"
- Hardware emulation requires these citations - future developers need them
- Mesen2 references and nesdev.org links are valuable documentation anchors

**Approach correction:**
- Identify hardware behavior indicators: "CRITICAL", "Hardware:", "[citation]"
- Preserve all comments explaining hardware behavior
- Aggressively delete comments explaining obvious code flow
- Don't reduce comments further than 10-15% without reviewing hardware accuracy

#### Discovery 4: dummyRead() Helper Pattern Clarifies Intent

**What was discovered:**
The pattern `_ = state.busRead()` appears ~7+ times in code but its purpose was unclear:
- Is this a performance optimization (ignored result)?
- Is this a hardware quirk that needs documentation?
- Is this accidental dead code?

**Solution implemented:**
Created explicit `dummyRead()` helper that makes intent obvious:
```zig
pub inline fn dummyRead(self: *const EmulationState, address: u16) void {
    _ = self.busRead(address);  // Hardware-accurate 6502 bus access where value is not used
}
```

Replaced all 7 instances with explicit `state.dummyRead()` calls.

**Why this matters:**
- Code intent is now obvious - this is intentional hardware behavior, not dead code
- Can grep for "dummyRead" to find all locations where dummy bus accesses happen
- New developers understand this is cycle-accurate hardware emulation requirement
- Creates single point of documentation for this pattern

**Pattern recognition:**
- Discarded return values deserve named helpers when they represent intent
- `_ = busRead()` is harder to search for and understand than `dummyRead()`
- Similar patterns exist elsewhere (dummy writes, dummy fetches) - same approach applies

#### Discovery 5: Execution.zig vs Microsteps.zig Reveals Code Quality Gradient

**What was discovered:**
Two files in same module show dramatically different code quality:

**Execution.zig (579 lines, ~40% comments):**
- Deep nesting in addressing mode logic
- God functions (605-line executeCycle)
- Opcode lists hardcoded in 4+ places
- Verbose explaining-the-obvious comments
- Multiple concerns mixed (DMA, warmup, execution)

**Microsteps.zig (383 lines, ~10% comments):**
- Pure functions with single responsibility
- Clear naming (fetchLow, fetchHigh, fixHighByte, etc.)
- Hardware behavior documented with nesdev.org citations
- Comments explain non-obvious behavior only
- Perfect separation of concerns

**Why this matters:**
- These files work together but follow OPPOSITE code quality standards
- Microsteps.zig IS THE TEMPLATE for how code should look
- Execution.zig shows what happens when initial design isn't maintained
- This quality gradient exists in other subsystems (PPU rendering, DMA logic)

**Refactoring implication:**
- Don't just delete bad comments from bad code
- Rewrite bad code to match Microsteps.zig pattern
- Use Microsteps.zig as TEMPLATE for every module refactor
- Low comment-to-code ratio (10%) is achievable, not exceptional

#### Discovery 6: Build System Isolation Issues During Refactoring

**What was discovered:**
When moving files (e.g., `emulation/cpu/execution.zig` → `cpu/Execution.zig`):
- Imports with outdated paths break silently until full rebuild
- Different error messages for each target (native vs wasm32-freestanding)
- Test builds may succeed while main build fails (or vice versa)
- Full-file cleanup can mask import errors until late in refactoring

**Evidence:**
- Line 88 in Execution.zig: `@import("../../ppu/State.zig")` broke when file moved to new directory
- Helpers.zig called `state.tickCpu()` which doesn't exist (method was removed)
- Build errors only surfaced after test compilation started

**Why this matters:**
- Must verify `zig build` (main) AND `zig build test-unit` after import changes
- Can't assume move is "complete" until both targets compile
- Import paths are relative to file location - moving a file requires immediate path fixes
- Partial refactoring cascades - one broken import can hide others

**Process improvement:**
- After file move: Immediately check all imports using `grep -n "@import"`
- Run `zig build` before running tests
- Keep refactoring atomic - move file, fix imports, test, commit
- Don't do multiple refactorings and hope they work together

### Updated Technical Details

**Module Structure After Session 3 Cleanup:**
- cpu/Execution.zig: 563 lines (reduced from 779, -216 lines of comments)
- cpu/Microsteps.zig: Pure function template (10% comment ratio)
- src/emulation/State.zig: Added dummyRead() helper (line 307-311)
- Build status: Compiling successfully, ready for next subsystem

**Refactoring Methodology Correction:**
The original task assumed "line-by-line review" was sufficient. Actual process needed:
1. Read entire file (not spot checks)
2. Identify all instances of pattern (not just first example)
3. Categorize comments by purpose (hardware vs obvious)
4. Complete ALL changes in single atomic commit
5. Verify both `zig build` AND `zig build test-unit`
6. Don't defer cleanup - finish one subsystem fully before starting next

**Comment Preservation Rules (Hardware Accuracy):**
- Keep: Comments with hardware citations or "CRITICAL" markers
- Keep: Comments explaining non-obvious CPU/PPU/APU behavior
- Delete: Comments explaining obvious code logic
- Delete: Comments redirecting to other documentation
- Target ratio: 10-15% comments-to-code (achievable, demonstrated in Microsteps.zig)

**Known Anti-Patterns to Watch For:**
1. **Half-assing refactoring** - Incomplete changes that break build
2. **Verbose comment disease** - Comments explaining obvious code
3. **Redirects instead of context** - "See other file" comments
4. **Undifferentiated cleanup** - Treating all comments as equal
5. **Import path assumptions** - Not fixing paths after moves immediately

#### Discovery 7: God Object Anti-Pattern - EmulationState Reaches Into and Owns Everything

**What was discovered (Session 4):**
EmulationState violates module boundaries at a fundamental architectural level:

1. **Extracts PPU internals and passes them back:**
```zig
// EmulationState.stepPpuCycle() - BACKWARDS DESIGN
const scanline = self.ppu.scanline;  // Extract from PPU
const dot = self.ppu.cycle;          // Extract from PPU
PpuLogic.tick(&self.ppu, scanline, dot, ...);  // Pass back to PPU!
```
The PPU already knows its scanline and cycle - why extract and pass back?

2. **Owns the PPU's output framebuffer:**
```zig
pub framebuffer: []u32,  // In EmulationState - should be in PpuState!
```
The framebuffer is the PPU's OUTPUT (rendered pixels). The PPU should own it.

3. **Owns VBlank ledger (now being moved but reveals pattern):**
- VBlankLedger belongs in PPU (VBlank is PPU hardware behavior)
- Was in emulation/ because "god object owns everything"

4. **Manages timing decisions that should be per-subsystem:**
- CPU execution checks PPU warmup flag
- CPU execution handles DMA coordination
- Emulator decides when to apply PPU register writes
- Each subsystem should know when IT executes

**Why this matters:**
- **Backwards coupling:** Subsystems can't function independently
- **Information extraction:** Coordinator reaches into internal state
- **Responsibility dilution:** EmulationState shouldn't know CPU/PPU/APU internals
- **Prevents clean refactoring:** Can't improve subsystems without touching god object
- **Test difficulty:** Can't test subsystems in isolation

**Hardware reality check:**
In NES hardware:
- Master clock drives all subsystems independently
- Each chip (6502, 2C02, APU) manages its own internal state
- Chips communicate through defined signals (NMI line, RDY line, etc.)
- No "coordinator" that knows everything and extracts internals

**Correct architecture:**
1. **Master clock advances** (monotonic counter)
2. **Each subsystem ticks independently:**
   - CPU.tick(master_cycles)
   - PPU.tick(master_cycles)
   - APU.tick(master_cycles)
3. **Subsystems output signals:**
   - ppu.nmi_line → cpu.nmi_line
   - ppu.framebuffer → render thread
   - cpu.rdy_line ← dma state
4. **No extraction, no god object**

**Current Impact:**
This architectural flaw requires:
- EmulationState.tick() = 250+ lines orchestrating everything
- PPU handler needs special VBlank prevention logic (because emulator manages it)
- Bus handlers have complex side effects (because emulator owns state)
- Framebuffer management scattered (emulator owns it)
- Difficult to test subsystems independently

**Refactoring Direction:**
Move toward "subsystem ownership" pattern:
- PPU owns: vblank state, nmi_line, framebuffer, rendering logic
- CPU owns: registers, instruction state, execution
- APU owns: channel states, IRQ flags
- DMA owns: transfer state, pause/resume logic
- Emulator just wires: master_cycles → subsystems → signals

#### Discovery 8: Scope Creep During Refactoring (Comment Cleanup Underestimated by 3-4x)

**What was discovered (Session 3-4):**
Initial scope estimate: Delete ~50 lines of comments
Actual scope: **216+ lines deleted** from single file (cpu/Execution.zig alone)

**The pattern:**
1. User shows ONE example (lines 1-53 module docs)
2. I identify that as needing deletion
3. I stop looking - **surface-level spot check**
4. User discovers I missed ALL the other instances of same pattern
5. Every module, every subsystem has same disease

**Actual scope per file:**
- Execution.zig: 52 line module docs → 11 lines (-41 lines)
- Plus 42+ more lines of "explain the obvious" comments
- Plus redirect comments ("see other file")
- Plus DMA verbose comments
- Plus interrupt state restoration essay
- **Total: ~200+ lines to delete from ONE file**

**Why it happens:**
Verbose comment disease is EVERYWHERE:
- Execution.zig has 779 lines, ~40% comments
- Microsteps.zig has 383 lines, ~10% comments (the template)
- Same ratio appears in every module

**If cleaning comments comprehensively:**
- ~10 core modules × 200 lines average = ~2000 lines to delete
- This alone is a full 8-10 hour refactoring task
- Current estimate was 2-3 hours

**Lesson:**
Don't spot-check. When you find a pattern, assume it's EVERYWHERE and scale estimates accordingly.

#### Discovery 9: PPU Signature Doesn't Match Hardware Model

**What was discovered (Session 4):**
```zig
// Current broken signature
pub fn tick(state: *PpuState, scanline: i16, dot: u16,
           cart: ?*AnyCartridge, framebuffer: ?[]u32) TickFlags
```

Issues:
1. **Receives scanline/dot parameters** - PPU already has these fields! Backwards.
2. **Receives framebuffer** - PPU should own its own output buffer
3. **Returns TickFlags** - Trying to pass events back instead of managing state

**Correct signature:**
```zig
pub fn tick(state: *PpuState, master_cycles: u64,
           cart: ?*AnyCartridge) TickFlags
```

**PPU should:**
- Receive master_cycles (like hardware)
- Advance scanline/dot internally
- Own framebuffer (render into own state)
- Return signals (nmi_line), not events

**Why this matters:**
If PPU signature stays wrong:
- Coordinator still extracting internals
- Can't fix god object problem
- PPU can't function independently
- Refactoring cascades forever

**Implementation note:**
PPU already has advanceClock() to handle timing internally. Just need to:
1. Call advanceClock() based on master_cycles
2. Remove scanline/dot parameters (redundant)
3. Remove framebuffer parameter (own it)
4. Compute nmi_line internally

**This blocks:**
- Clean subsystem boundaries
- Independent PPU testing
- Breaking god object pattern
- Hardware-accurate architecture

#### Discovery 10: Circular State Flow - EmulationState Caching PPU State

**What was discovered (Session 4 continuation, 2025-11-07):**

EmulationState caches PPU state then passes it back to PPU in circular pattern:

```zig
// EmulationState.tick() - CIRCULAR PATTERN
PpuLogic.advanceClock(&self.ppu, self.rendering_enabled);  // Pass cached value
const flags = PpuLogic.tick(&self.ppu, ...);               // PPU returns fresh value
self.rendering_enabled = flags.rendering_enabled;          // Update cache
```

**The circular flow:**
1. EmulationState has cached `rendering_enabled` field
2. Passes cached value to `PpuLogic.advanceClock()` as parameter
3. PPU internally computes fresh value from `state.mask.renderingEnabled()`
4. PPU returns computed value in TickFlags
5. EmulationState copies returned value back to cache
6. Repeat next cycle

**Why this is backwards:**
- PPU has authoritative state (mask register)
- PPU shouldn't receive its own state as parameter
- Caching creates stale/inconsistent data risk
- Adds indirection for zero benefit

**Same pattern with other fields:**
- `frame_complete` - PPU detects boundary, returns flag, EmulationState caches it
- `odd_frame` - EmulationState derives from `ppu.frame_count` each frame
- `rendering_was_enabled` - BOTH EmulationState AND PPU write to `ppu.rendering_was_enabled` (confused ownership)

**Correct pattern:**
```zig
// PpuLogic.advanceClock() - DIRECT READ
pub fn advanceClock(ppu: *PpuState) void {  // NO PARAMETER
    ppu.cycle += 1;
    const rendering_enabled = ppu.mask.renderingEnabled();  // Read own state
    if (ppu.scanline == -1 and ppu.cycle == 339 and (ppu.frame_count & 1) == 1 and rendering_enabled) {
        ppu.cycle = 340;  // Odd frame skip
    }
}
```

**Evidence of coupling:**
- EmulationState.zig:509 - passes `self.rendering_enabled` to advanceClock()
- EmulationState.zig:540 - copies `result.rendering_enabled` to cache
- EmulationState.zig:523-524 - writes to `ppu.rendering_was_enabled` (duplicate tracking)
- EmulationState.zig:526 - derives `odd_frame` from `ppu.frame_count` (unnecessary caching)

**Impact:**
This circular pattern prevents clean subsystem boundaries. PPU cannot be self-contained because it depends on EmulationState to tell it about its own state. Fixing VBlank ownership (Session 4) didn't address this deeper pattern.

**Required cleanup:**
1. Delete `rendering_enabled`, `frame_complete`, `odd_frame` from EmulationState
2. Remove parameter from `advanceClock()` - PPU reads own mask
3. Add `frame_complete` field to PpuState - PPU owns frame boundaries
4. Delete TickFlags wrapper - no need to return state that's already accessible
5. PPU handles A12 notification directly - no delegation through EmulationState

**This discovery reveals:** VBlank migration was incomplete - addressed symptom (VBlank ownership) but not root cause (EmulationState extracting and caching all subsystem state).

---

### 2025-11-07 (Session 5 - PPU Decoupling Complete - BLACK BOX ARCHITECTURE ACHIEVED)

#### PPU Subsystem Decoupling - Clean Signal-Based Architecture

**Work Completed:**
1. ✅ Eliminated all PPU wrapper structures (PpuCycleResult, TickFlags)
2. ✅ Deleted cached state fields from EmulationState (frame_complete, odd_frame, rendering_enabled)
3. ✅ Simplified PPU interface (advanceClock no params, tick returns void, direct A12 calls)
4. ✅ Reduced EmulationState.tick() to pure signal wiring (cpu.nmi_line = ppu.nmi_line)
5. ✅ Fixed NMI timing bug in PpuHandler.write() (level signal vs direct manipulation)
6. ✅ All compilation successful, browser emulator working
7. ✅ AccuracyCoin "NMI disabled at VBlank" test now passes (was hanging before)
8. ✅ **ZERO wrapper layers between EmulationState and PPU** - Complete black box decoupling

**Architecture Changes:**

**Before (God Object Pattern):**
```zig
// EmulationState extracts PPU internals, caches state, returns flags
const flags = PpuLogic.tick(&self.ppu, scanline, dot, cart, framebuffer);
self.frame_complete = flags.frame_complete;
self.rendering_enabled = flags.rendering_enabled;
```

**After (Clean Signal Wiring):**
```zig
// PPU manages itself, outputs signal
PpuLogic.tick(&self.ppu, self.clock.master_cycles, self.cart);
self.cpu.nmi_line = self.ppu.nmi_line;  // Wire signal
```

**Key Structural Improvements:**

1. **PpuLogic.advanceClock()** - No parameters, reads own mask register
   - Before: `advanceClock(&ppu, rendering_enabled)` - circular dependency
   - After: `advanceClock(&ppu)` - self-contained timing

2. **PpuLogic.tick()** - Returns void, computes signals internally
   - Before: Returns TickFlags with frame_complete, nmi_signal, A12_rising, etc.
   - After: Sets state.nmi_line directly, calls cart.ppuA12Rising() directly

3. **EmulationState.tick()** - Pure signal wiring (8 lines)
   - Before: 250+ lines extracting PPU internals, caching state, applying flags
   - After: Advances clock → ticks subsystems → wires signals

4. **Deleted wrappers:**
   - PpuCycleResult struct (was wrapping PPU state for return)
   - TickFlags struct (was returning events instead of managing state)
   - applyPpuRenderingState() function (was orchestrating PPU from outside)

**Bug Fixes:**

**NMI Timing Bug in PpuHandler.write():**
- **Before:** Directly manipulated `state.ppu.nmi_line` when PPUCTRL.7 changed
- **After:** Updates `state.ppu.ctrl.nmi_enable`, PPU computes nmi_line from (vblank_flag AND nmi_enable)
- **Impact:** AccuracyCoin "NMI disabled at VBlank" test now passes (was hanging)
- **Root cause:** Handler was forcing NMI line high even when VBlank not active
- **Fix:** PPU owns NMI line computation, handler only updates ctrl register

**Helper Function Updates:**
- src/emulation/helpers.zig:48, 57 - Changed `state.frame_complete` → `state.ppu.frame_complete`
- tests/emulation/state_test.zig - Updated frame_complete references
- tests/snapshot/snapshot_integration_test.zig - Updated frame_complete references

**Snapshot Serialization Updates:**
- Added frame_complete to PpuState serialization (writePpuState/readPpuState)
- Removed frame_complete from EmulationStateFlags
- Maintained backwards compatibility not required (non-working emulator)

**Deleted Fields from EmulationState:**
- `frame_complete: bool` → Moved to ppu.frame_complete
- `rendering_enabled: bool` → Deleted (PPU reads own mask)
- `odd_frame: bool` → Deleted (derive from ppu.frame_count if needed)
- `applyPpuRenderingState()` → Deleted (PPU manages own state)

**Compilation Status:**
- ✅ zig build - successful
- ✅ zig build test-unit - passing
- ✅ Browser emulator - loads and runs without crashes
- ✅ AccuracyCoin test suite - "NMI disabled at VBlank" now passes (+1 test)

**Code Quality Metrics:**
- EmulationState.tick() PPU section: 250+ lines → ~8 lines (96% reduction)
- PPU interface complexity: Multiple wrappers → Direct signal wiring
- Circular dependencies: Eliminated (PPU no longer receives own state as params)

#### Session Outcome

**Success Criteria Met:**
1. ✅ PPU owns its state (no external caching)
2. ✅ Clean subsystem boundaries (PPU doesn't extract from emulator)
3. ✅ Signal-based architecture (nmi_line wiring, not flag returning)
4. ✅ Zero wrapper indirection (direct calls, no PpuCycleResult/TickFlags)
5. ✅ Hardware-accurate NMI timing (level signal, not direct manipulation)

**Pattern Established for Other Subsystems:**
- CPU should own interrupt lines, output to emulator
- APU should own IRQ flags, output to CPU
- DMA should own RDY line, output to CPU
- Emulator just wires signals between subsystems

**This refactor eliminates the "God Object" anti-pattern for PPU subsystem and establishes the clean signal-wiring pattern for future subsystem decoupling.**

#### Discovery 11: Bus Refactoring Should Wait Until After Major Subsystems Complete

**What was discovered (Session 5 planning):**
During final work on PPU decoupling, the question came up: "Should we tackle the bus system next?"

**Critical insight realized:**
Bus refactoring (splitting handlers, cleaning up routing logic) is LESS IMPORTANT than completing the subsystem decoupling pattern for CPU, APU, and DMA.

**Why this matters:**
- Bus handlers are already working correctly (98.1% test pass rate from Nov 2025-11-04 refactor)
- Bus is infrastructure - it SERVES the subsystems
- Refactoring bus before subsystems would mean:
  - Fighting against god object patterns still present in CPU/APU/DMA
  - Potentially reworking bus handlers again after subsystem changes
  - Delaying the more impactful architectural improvements

**Correct priority order:**
1. **Complete PPU decoupling** ✅ (Session 5 - DONE)
2. **CPU subsystem decoupling** (make CPU self-contained, signal-based)
3. **APU subsystem decoupling** (APU owns IRQ flags, outputs signals)
4. **DMA subsystem decoupling** (DMA owns RDY line state)
5. **THEN bus refactoring** (once subsystems are clean, optimize their infrastructure)

**The pattern:**
- Major systems (components that do work) come FIRST
- Infrastructure (plumbing between components) comes AFTER
- Don't optimize the pipes while the machines they connect are still being redesigned

**Impact on task planning:**
This realization prevents wasted effort. Bus handlers work correctly NOW. Refactoring them before completing CPU/APU/DMA decoupling would mean potentially redoing bus work later when those subsystems change their interaction patterns.

**Lesson for future refactoring:**
When choosing what to refactor next, ask: "Is this infrastructure or implementation?" Infrastructure should wait until the things it serves are stable.

#### Discovery 12: NMI Timing Bug - Handler Computed Flag Instead of Level Signal

**What was discovered (Session 5, during PpuHandler cleanup):**
PpuHandler.write() for PPUCTRL was directly manipulating `state.ppu.nmi_line` based on PPUCTRL.7 changes:

```zig
// WRONG (Session 4 pattern)
if (ctrl_changed and new_ctrl.nmi_enable and state.ppu.vblank.vblank_flag) {
    state.ppu.nmi_line = true;  // Force NMI high
}
```

**Why this is wrong:**
- Handler was COMPUTING the NMI line state (combining vblank_flag AND nmi_enable)
- This violates the signal ownership model - PPU should compute its own outputs
- Handler should ONLY update the input (ctrl.nmi_enable), not the output (nmi_line)
- PPU's nmi_line is a LEVEL signal that should reflect: `vblank_flag AND ctrl.nmi_enable`

**Correct pattern:**
```zig
// Handler ONLY updates input register
state.ppu.ctrl.nmi_enable = new_ctrl.nmi_enable;

// PPU Logic.tick() computes output signal from state
state.nmi_line = state.vblank.vblank_flag and state.ctrl.nmi_enable;
```

**Impact:**
- Fixed AccuracyCoin "NMI disabled at VBlank" test (was hanging)
- Test writes PPUCTRL.7 = 0 during VBlank - should NOT trigger NMI
- Old code forced nmi_line=true even when nmi_enable=false
- New code correctly computes level signal from both inputs

**Why this matters:**
This reveals the CORRECT pattern for hardware register handlers:
1. **Handlers update STATE** (register bits, flags)
2. **Subsystem logic computes SIGNALS** (outputs derived from state)
3. **Coordinator wires SIGNALS** between subsystems

This is the hardware-accurate model: Registers are inputs, signals are outputs, logic derives outputs from inputs.

**Pattern applies to:**
- PPUCTRL → nmi_line (PPU computes)
- APU frame counter → frame_irq (APU computes)
- DMC channel → dmc_irq (APU computes)
- DMA state → rdy_line (DMA computes)

Handlers should NEVER compute derived signals - that's the subsystem's job.

---

### 2025-11-07 (Session 6 - Phase 6 Table-Driven CPU Refactor Complete)

#### Phase 6: Table-Driven CPU Execution - Microstep Dispatch Complete

**Work Completed:**
1. ✅ Converted all CPU instruction execution to table-driven microstep dispatch
2. ✅ Built comptime microstep table (MICROSTEP_TABLE) indexed by opcode
3. ✅ Eliminated switch-based addressing mode logic from execute loop
4. ✅ Fixed Bug #4: calcAbsoluteY discarding dummy read value
5. ✅ Discovered Bug #8: effective_address overwrite in execute phase (RMW instructions)
6. ✅ All compilation successful, AccuracyCoin passing
7. ✅ Browser emulator working with table-driven execution

**Architecture Changes:**

**Before (Switch-Based Dispatch):**
```zig
// 250+ lines of switch on addressing mode
switch (cpu.address_mode) {
    .absolute_y => {
        const base = ...;
        const dummy_addr = ...;
        // Nested logic for each mode
    },
    // ... 15 more cases
}
```

**After (Table-Driven Dispatch):**
```zig
// Single comptime-built table lookup
const sequence = MicrostepTable.MICROSTEP_TABLE[cpu.opcode];
const microstep_fn = MicrostepTable.MICROSTEP_FUNCTIONS[sequence.steps[cpu.instruction_cycle]];
const early_complete = microstep_fn(state);
```

**Key Structural Improvements:**

1. **MicrostepTable.zig** - Comptime-built dispatch table (36 microstep functions, 256 opcode entries)
   - Before: Switch statements scattered across Execution.zig
   - After: Single source of truth, built at compile time, zero runtime overhead

2. **Microsteps.zig** - Pure, single-purpose addressing functions (12 addressing microsteps)
   - Each function does ONE thing (calcAbsoluteX, fetchIndirectLow, addYCheckPage, etc.)
   - Hardware-accurate dummy reads with correct bus timing
   - Clear early completion signals (return true when addressing done)

3. **Execution.zig** - Simplified execute loop (removed 250+ lines of switch logic)
   - fetch_operand_low state: Execute microstep from table, check completion
   - No nested conditionals, no address mode branching
   - Direct microstep function calls via comptime table

**Bug Fixes:**

**Bug #4: calcAbsoluteY Discards Dummy Read Value**
- **Before:** `state.cpu.temp_value = state.bus.open_bus.get();` (line 63)
- **After:** `state.cpu.temp_value = dummy_value;` (matches calcAbsoluteX)
- **Impact:** All absolute,Y read instructions (LDA/ADC/AND/CMP/EOR/LDX/ORA/SBC $1234,Y) were loading garbage when page NOT crossed
- **Root cause:** When page is NOT crossed, the "dummy" read IS the actual value (hardware behavior)
- **Fix:** Store dummy_value instead of open_bus, let fixHighByte overwrite when page IS crossed

**Bug #8: effective_address Overwrite in Execute Phase (DISCOVERED, NOT YET FIXED)**
- **What was discovered:** RMW (Read-Modify-Write) instructions overwrite effective_address during execute phase
- **Impact:** Causes dummy write to wrong address in RMW instructions (INC/DEC/ASL/LSR/ROL/ROR/SLO/SRE/RLA/RRA/DCP/ISC)
- **Manifestation:** `ppu_dummy_write_test` failure - INC $2002 writes to wrong PPU register
- **Root cause analysis:**
  - RMW sequence: Read operand → Execute ALU operation → Write result back
  - Execute phase calls `state.busRead(effective_address)` to fetch operand
  - busRead() dispatches to PpuHandler for $2002-$3FFF
  - PpuHandler.read() performs mirroring: `const mirror_addr = 0x2000 + (address % 8)`
  - busRead() stores mirrored address in `state.cpu.effective_address` (OVERWRITES original!)
  - Write phase uses corrupted effective_address → writes to wrong register
- **Example:** INC $2002 becomes INC $2000 (reads from $2002, writes to $2000)
- **Decision:** Put on back burner to finish Phase 6 refactor, fix later
- **Proper fix:** Separate read_address vs write_address, or don't overwrite effective_address

**Investigation: Dummy Write Cycles Test Failure**
- Investigated RMW instruction flow to understand `ppu_dummy_write_test` failure
- Traced execution: Addressing → Read → Modify → Dummy Write → Real Write
- Confirmed RMW instructions use correct microstep sequences with dummy write
- Identified effective_address corruption as root cause (see Bug #8)
- Documented RMW timing: 6 cycles (2 addressing, 1 read, 1 modify, 1 dummy write, 1 real write)

**RMW Instruction Flow Analysis:**
```
Cycle 1: fetch_opcode (read opcode byte)
Cycle 2: fetch_operand_low (address low byte)
Cycle 3: fetch_operand_high (address high byte)
Cycle 4: read operand (busRead fetches value)
Cycle 5: execute (ALU modifies value)
Cycle 6: dummy write (write old value back - PPU register interaction!)
Cycle 7: real write (write new value)
```

**PPU Register Interaction:**
- Dummy write happens at cycle 6, before real write
- This affects PPU registers with read/write side effects ($2002, $2004, $2007)
- $2002 read clears VBlank flag - dummy write triggers read side effect!
- AccuracyCoin test expects INC $2002 to clear VBlank BEFORE final write
- Correct behavior requires dummy write to happen at correct address

**Compilation Status:**
- ✅ zig build - successful
- ✅ zig build test-unit - passing
- ✅ Browser emulator - loads and runs
- ✅ AccuracyCoin test suite - Phase 6 tests passing
- ⚠️  ppu_dummy_write_test - failing (Bug #8, deferred)

**Code Quality Metrics:**
- Execution.zig: Removed 250+ lines of switch-based addressing logic
- Table-driven dispatch: Zero runtime overhead (comptime-built table)
- Microstep purity: All functions are single-purpose, hardware-accurate

#### Decision: Defer Bug #8 to Finish Refactor

**Context:** During Phase 6 table-driven refactor, discovered Bug #8 (effective_address overwrite in execute phase causing RMW dummy writes to wrong address).

**Options considered:**
1. Fix Bug #8 immediately (interrupt refactor flow)
2. Defer Bug #8, complete Phase 6, fix later

**Decision:** Defer Bug #8 to back burner, prioritize completing Phase 6 refactor.

**Rationale:**
- Phase 6 refactor is 95% complete, only needs final testing
- Bug #8 is isolated to RMW instructions, doesn't block table-driven dispatch
- Fixing Bug #8 requires deeper analysis of address vs effective_address usage
- Better to complete one major refactor cleanly than half-finish two
- Can return to Bug #8 with fresh perspective after Phase 6 complete

**Impact:**
- `ppu_dummy_write_test` continues to fail (known issue, tracked)
- All other tests passing
- Table-driven execution works correctly for non-RMW instructions
- Bug #8 logged in discoveries for future remediation

**Next Steps:**
- Complete Phase 6 validation testing
- Document Bug #8 in issues tracker
- Return to Bug #8 after Phase 6 complete

---
