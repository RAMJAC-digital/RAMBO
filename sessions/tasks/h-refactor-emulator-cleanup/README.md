---
name: h-refactor-emulator-cleanup
branch: feature/h-refactor-emulator-cleanup
status: pending
created: 2025-11-06
---

# Emulator Codebase Cleanup & Simplification

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

### Documentation Nuclear Option
- [ ] **ALL** documentation deleted or completely rewritten from scratch (README.md, ARCHITECTURE.md, CLAUDE.md, docs/*)
- [ ] Default: Delete ALL comments unless they explain non-obvious hardware behavior with nesdev.org citations
- [ ] Documentation only added AFTER code is verified correct
- [ ] Zero "compatibility" references, zero references to removed APIs
- [ ] The code IS the documentation

### Code Hygiene - Every Subsystem
- [ ] **CPU:** Timing, instruction execution, interrupt handling - zero wrappers, zero nested conditionals in critical paths
- [ ] **PPU:** Rendering pipeline, register I/O, timing - direct data flow, no confusing returns
- [ ] **APU:** Channels, frame counter, DMC - clear single-purpose functions
- [ ] **NMI/IRQ:** Interrupt coordination - explicit state machines, no magic
- [ ] **DMA:** OAM DMA, DMC DMA - timing logic is obviously correct on inspection
- [ ] **Bus Handlers:** Direct delegation, zero indirection layers
- [ ] **Clock Coordination:** ONE clear representation of cycles (no cpuCycle vs apuCycle confusion)

### Function-Level Standards
- [ ] Every function does ONE thing with a clear, descriptive name
- [ ] No deeply nested conditionals - extract to named helper functions
- [ ] Data flow is direct - no confusing function returns where mutation is clearer
- [ ] No wrapper functions that obscure what's being measured/accessed
- [ ] Critical paths (tick functions, interrupt handling) are readable in 30 seconds

### Test Infrastructure Rebuild
- [ ] Test helpers encode ZERO brittle assumptions (no hard-coded timing, no configuration dependencies)
- [ ] Every test has singular, focused purpose
- [ ] Test pass rate ≥98% with reliable, deterministic execution
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
<!-- Updated as work progresses -->
- [2025-11-06] Task created, awaiting context gathering and subtask planning

