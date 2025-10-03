# Session: Hybrid Architecture Design & Planning

**Date:** 2025-10-03
**Duration:** ~4 hours (comprehensive research and planning)
**Objective:** Design async message-passing architecture, discover it breaks cycle accuracy, pivot to hybrid model

---

## Session Summary

This session involved deep architectural research and planning for RAMBO's evolution beyond the current synchronous design. The goal was to implement asynchronous message-passing between components (CPU, PPU, APU) for better parallelism and hardware modeling.

**Key Outcome:** After comprehensive research and multi-agent review, we discovered that **full async architecture breaks cycle-accurate emulation**. We pivoted to a **hybrid model** that preserves cycle accuracy while adding async I/O benefits.

---

## Research Phase

### Research Agent 1: CPU Variants
**Goal:** Understand NES CPU variants and their differences.

**Findings:**
- **RP2A03 (NTSC)**: 1.79 MHz (21.47727 MHz ÷ 12)
  - RP2A03E: Early revision
  - **RP2A03G**: Standard front-loader (AccuracyCoin target)
  - RP2A03H: Later revision
- **RP2A07 (PAL)**: 1.66 MHz (26.6017 MHz ÷ 16)
- **Key Finding**: Opcodes behave identically across RP2A03 revisions
- **Variance**: Only unstable opcodes (SHA, SHX, SHY, SHS, LXA) differ by revision

**Impact on Config:**
- Need `cpu.variant` (RP2A03E/G/H, RP2A07)
- Need `cpu.unstable_opcodes.sha_behavior`
- Need `cpu.unstable_opcodes.lxa_magic`

### Research Agent 2: CIC Lockout Chips
**Goal:** Understand CIC chips and whether they need async execution.

**Findings:**
- **CIC Architecture**: 4-bit Sharp SM590 microcontroller @ 4 MHz
- **Variants**: CIC-NES-3193 (NTSC), CIC-NES-3195/3197 (PAL)
- **Critical Finding**: Simple state machine, does NOT need async execution
- **Emulation**: Can be synchronous state machine integrated with init

**Impact on Design:**
- CIC is synchronous utility, not separate async component
- Configuration: `cic.variant`, `cic.emulation` (state_machine/bypass/disabled)

### Research Agent 3: SPSC Message Passing
**Goal:** Learn lock-free SPSC queue patterns for Zig.

**Findings:**
- Lock-free ring buffer with atomic head/tail indices
- Power-of-2 capacity for fast modulo operations
- Pre-allocated buffers (zero allocations on hot path)
- Memory ordering: Acquire/Release (with explicit fences needed)
- Zig std.atomic for thread-safe operations

**Impact on Design:**
- Patterns identified for async I/O layer
- Critical bug found: Need memory fence between buffer write and index update

### Research Agent 4: NES Board Revisions
**Goal:** Understand console variants and hardware differences.

**Findings:**
- **Console Variants**: Famicom, NES front-loader, NES top-loader, AV Famicom
- **Board Revisions**: HVC-CPU-01 to -08 (Famicom), NES-CPU-01 to -11 (NES)
- **Controller Differences**: NES vs Famicom clocking (AccuracyCoin tests this!)
- **CPU+PPU Combinations**: Specific pairings per console variant

**Impact on Config:**
- Need `controllers.type` (NES vs Famicom)
- Configuration should describe complete hardware, not just CPU/PPU

---

## Architecture Design Phase

### Initial Proposal: Full Async Message-Passing

**Design:**
- Each component (CPU, PPU, APU) runs in separate thread
- SPSC queues for inter-component communication
- Message types: memory_read, memory_write, interrupt, sync
- Main thread acts as message bus

**Goals:**
- True parallelism (CPU and PPU run simultaneously)
- Matches hardware (independent chips)
- Modern async patterns

**Deliverable:** Created `async-architecture-design.md` (67KB document)

---

## Critical Review Phase

### Review Agent 1: Architect Review

**Critical Finding #1: Memory Operations Cannot Be Async**

> "The proposed async message-passing for memory breaks cycle-accurate emulation."

**Problem:**
```zig
// Proposed (BREAKS ACCURACY):
cpu_sends_message(memory_read)  // Send request
wait_for_response()              // CPU BLOCKED!
value = get_response()           // Too late!

// Required:
value = bus.read(address)  // IMMEDIATE response
```

**Impact:** AccuracyCoin tests would fail. Cycle accuracy requires immediate memory responses.

**Critical Finding #2: Synchronization Too Coarse**

Frame-level sync (29,780 cycles) insufficient for:
- Mid-frame PPU register writes (split-screen effects)
- Sprite 0 hit timing (cycle-accurate)
- MMC3 scanline counters
- Audio/video sync

**Critical Finding #3: Bus Contention Not Modeled**

Design assumes "RAM access only by CPU" but PPU must access CPU memory for OAM DMA.

**Recommendation:** "DO NOT implement full async architecture as proposed."

### Review Agent 2: Performance Review

**Finding #1: Messages Too Large**

Message union is 40-64 bytes, causing cache misses.
- Current: 32 MB/s memory bandwidth
- Optimized (4-byte tagged indices): 2 MB/s (16× reduction)

**Finding #2: Atomic Operations Too Expensive**

Every `bus.read()`/`bus.write()` performs 3 atomic operations.
- At 1.79M ops/sec: 5.4M atomic ops/sec (excessive)
- Each atomic: ~5-10 cycles minimum
- Total overhead: ~27-54M cycles/sec

**Recommendation:** Synchronous bus for emulation core, async only for I/O.

### Review Agent 3: Code Review

**Finding #1: VTable Pattern Unsafe in Zig**

Component vtable with `@ptrCast`/`@alignCast` is undefined behavior if types don't match.

**Recommendation:** Use comptime generics (duck typing) instead:
```zig
pub fn Emulator(comptime CpuImpl: type, comptime PpuImpl: type) type {
    // Compile-time polymorphism, zero runtime cost
}
```

**Finding #2: SPSC Queue Memory Ordering Bug**

Missing memory fence between buffer write and index update.

**Fix Required:**
```zig
self.buffer[current_head] = item;
std.atomic.fence(.Release);  // Ensure write completes first
self.head.store(next_head, .Release);
```

---

## Pivot: Hybrid Architecture

### Unanimous Recommendation

All three review agents independently concluded:

> "DO NOT implement full async architecture. Adopt hybrid sync/async model."

### Hybrid Design Principles

**Keep Synchronous (Emulation Core):**
- CPU, PPU, APU, Bus: Synchronous execution
- Direct memory access (no messages)
- Single-threaded, cycle-accurate
- Matches real NES synchronous design

**Make Asynchronous (I/O Layer):**
- Input polling (controllers)
- Video output (frame submission)
- Audio output (sample buffering)
- File I/O (ROM loading, save states)
- Debug/trace logging

**Clean Separation:**
- Emulation core is pure state machine: `state_n+1 = tick(state_n)`
- I/O layer uses libxev event loop
- No blocking between layers

---

## Final Architecture Design

### Core Principles

**P1: Deterministic Emulation Core**
- Pure function: `state_n+1 = f(state_n)`
- No I/O, no allocations, no side effects
- Fully reproducible execution

**P2: Hardware-Accurate Timing**
- Each component tracks own clock
- Timing relationships match hardware (PPU = 3× CPU)
- Visual glitches accurately emulated

**P3: Clean Separation**
- Emulation core isolated from I/O
- libxev handles all async operations
- Configuration immutable during emulation

**P4: Parameterized Hardware**
- All variants (RP2A03G/H, RP2C02G, etc.) use same code
- Behavior controlled by configuration

**P5: Zero Coupling**
- Components communicate only through Bus
- CPU doesn't know about PPU implementation
- CIC is separate utility

### RT Emulation Loop

**Master Clock:**
- Advances by single PPU cycles (finest granularity)
- Derived CPU cycles (PPU ÷ 3)
- Scanline/dot calculated from PPU cycles

**Tick Function:**
```zig
pub fn tick(state: *EmulationState) void {
    state.clock.ppu_cycles += 1;

    const cpu_tick = (state.clock.ppu_cycles % 3) == 0;
    const ppu_tick = true;
    const apu_tick = cpu_tick;

    if (ppu_tick) tickPpu(&state.ppu, &state.bus, state.config);
    if (cpu_tick) tickCpu(&state.cpu, &state.bus, state.config);
    if (apu_tick) tickApu(&state.apu, state.config);
}
```

**Zero Coupling Design:**
- CPU reads/writes through `busRead()`/`busWrite()`
- Bus routes to RAM/PPU/APU/Cartridge
- No direct component-to-component calls

### libxev Integration

**Event Loop:**
- Frame timer triggers emulation (`emulateFrame()`)
- Input polling (125 Hz - faster than 60 FPS)
- Video frame submission (async)
- Audio sample buffering (async)
- File operations (async ROM loading)

**Callbacks:**
```zig
fn frameTimerCallback(...) {
    emulateFrame(&self.emu_state);  // Pure state machine
    if (self.on_frame_complete) |cb| cb(self);  // Async I/O
}
```

---

## Configuration System Expansion

### Hardware Configuration Structure

```zig
pub const HardwareConfig = struct {
    console: ConsoleVariant,
    cpu: CpuConfig,      // Variant + unstable opcodes
    ppu: PpuConfig,      // Variant + region
    apu: ApuConfig,      // Enabled + region
    cic: CicConfig,      // Variant + emulation mode
    controllers: ControllerConfig,  // NES vs Famicom
    timing: TimingConfig,  // Derived from variants
};
```

### AccuracyCoin Target Config

```kdl
console "NES-NTSC-FrontLoader"

cpu {
    variant "RP2A03G"
    unstable_opcodes {
        sha_behavior "standard"
        lxa_magic 0xEE
    }
}

ppu {
    variant "RP2C02G"
    region "NTSC"
}

cic {
    variant "CIC-NES-3193"
    enabled true
}

controllers {
    type "NES"
}
```

---

## Implementation Plan

### 11-Week Schedule

**Phase 1: Configuration System (Week 1)**
- Expand Config.zig with hardware variants
- Update rambo.kdl parser
- 20+ tests

**Phase 2: State Machine Refactor (Week 2)**
- Create EmulationState struct
- Pure state machine architecture
- 30+ tests

**Phase 3: CIC State Machine (Week 3)**
- Implement CIC as synchronous state machine
- Authentication, bypass, disabled modes
- 10+ tests

**Phase 4: PPU Foundation (Weeks 4-6)**
- PPU state machine
- Cycle-accurate rendering
- Visual glitch support
- 40+ tests

**Phase 5: libxev Integration (Week 7)**
- Emulator struct with event loop
- Async I/O layer
- Integration tests

**Phase 6: Visual Glitches (Week 8)**
- Mid-scanline effects
- VBlank timing
- Sprite 0 hit
- NMI suppression

**Phase 7: APU (Week 9)**
- Audio channels
- Frame counter
- 30+ tests

**Phase 8: AccuracyCoin Testing (Week 10)**
- Run full test suite
- Fix failures
- Performance tuning

**Phase 9: Documentation (Week 11)**
- Update all docs
- Remove legacy code
- Final cleanup

---

## Testing Strategy

### Test Targets

**Current:** 112 tests passing
**Target:** 250+ tests

**Categories:**
- Bus: 16 tests
- CPU: 70 tests
- Cartridge: 42 tests
- Configuration: 20 tests (new)
- State Machine: 30 tests (new)
- PPU: 40 tests (new)
- APU: 30 tests (new)
- Integration: 10+ tests (new)

### Acceptance Criteria

**Per Phase:**
- All existing tests pass (0 regressions)
- Phase-specific tests pass
- Code coverage >95%
- Documentation updated

**Final:**
- AccuracyCoin CPU tests pass
- AccuracyCoin PPU tests pass
- 60 FPS NTSC achieved
- <10% CPU usage
- <100 MB memory

---

## Key Insights

### Insight #1: NES is Synchronous Hardware

The NES has a shared master clock with fixed timing relationships. Modeling as async components **fights the hardware design**.

**Lesson:** Match the architecture to the hardware being emulated.

### Insight #2: Research Prevents Mistakes

The thorough research and multi-agent review **prevented a major architectural mistake**:
- Would have broken cycle accuracy
- 7-week migration would have required complete rewrite
- Caught before writing code (saved weeks of effort)

**Lesson:** Invest time in architecture review before implementation.

### Insight #3: Hybrid Model is Optimal

- **Sync core**: Maintains cycle accuracy (proven to work)
- **Async I/O**: Provides real benefits (responsive, non-blocking)
- **Best of both**: Accuracy + performance where it matters

**Lesson:** Don't force async everywhere. Use it where it provides value.

---

## Deliverables

### Documentation Created

1. **`async-architecture-design.md`** (67KB)
   - Full async architecture proposal
   - SPSC queue implementation
   - Component interfaces
   - **Status:** SUPERSEDED (but preserved for reference)

2. **`architecture-review-summary.md`** (28KB)
   - Critical review findings
   - Hybrid architecture recommendation
   - Revised implementation plan

3. **`final-hybrid-architecture.md`** (51KB)
   - Complete hybrid architecture design
   - RT emulation loop
   - libxev integration
   - 11-week implementation plan
   - **Status:** APPROVED - Ready for implementation

4. **`2025-10-03-hybrid-architecture.md`** (this document)
   - Session summary
   - Research findings
   - Design evolution
   - Key insights

### Code Changes

**None yet** - This was purely research and planning phase.

**Next Step:** Begin Phase 1 (Configuration System Expansion)

---

## Legacy Code to Remove

### Items Identified for Removal

1. **Async architecture experiments** (if any prototypes were created)
2. **Old configuration code** (will be replaced in Phase 1)
3. **Unused helper functions** (audit during Phase 2)
4. **TODO/FIXME comments** (address during implementation)
5. **Dead test code** (clean up during Phase 9)

### Removal Process

1. Run `git grep -n "TODO\|FIXME\|HACK\|XXX\|DEPRECATED"`
2. Address or remove each instance
3. Check for unused imports
4. Verify tests still pass after removal
5. Document removals in commit messages

---

## Next Steps

### Immediate Actions

1. ✅ Get user approval for hybrid architecture
2. ✅ Get final architect review sign-off
3. ✅ Create detailed Phase 1 task breakdown
4. ⬜ Begin Phase 1: Configuration System Expansion

### Phase 1 Kickoff (Week 1)

**Tasks:**
1. Expand `Config.zig` with CPU/PPU/CIC/controller variants
2. Add unstable opcode configuration (SHA, LXA behavior)
3. Update `rambo.kdl` parser
4. Write 20+ configuration tests
5. Document configuration options
6. Verify 0 regressions (all 112 tests pass)

**Deliverables:**
- Expanded configuration system
- Complete hardware variant support
- AccuracyCoin target config loadable
- Documentation updated

---

## Lessons Learned

### What Went Well

✅ **Comprehensive Research**: 4 parallel search agents gathered complete hardware info
✅ **Multi-Agent Review**: 3 specialist reviewers independently caught critical flaws
✅ **Early Detection**: Caught architectural mistake before implementation
✅ **Unanimous Conclusion**: All reviewers agreed on hybrid approach
✅ **Detailed Planning**: 11-week plan with clear milestones

### What Could Improve

⚠️ **Initial Assumption**: Assumed async was universally better (it's not for emulation core)
⚠️ **Scope Creep**: Original goal was "add PPU", expanded to full architecture overhaul
⚠️ **Time Investment**: 4+ hours of planning (but saved weeks of bad implementation)

### Key Takeaway

> "The best code is the code you don't write because you discovered it was wrong during planning."

This session exemplifies the value of careful architectural design, thorough research, and multi-perspective review before committing to implementation.

---

## Preservation Notes

This session's work is preserved for posterity in:

1. **Architecture Documents**: 3 comprehensive design docs in `docs/06-implementation-notes/design-decisions/`
2. **Session Notes**: This document in `docs/06-implementation-notes/sessions/`
3. **Research Findings**: Embedded in architecture documents
4. **Implementation Plan**: 11-week schedule with clear phases and acceptance criteria

Future developers can understand:
- Why hybrid architecture was chosen
- What alternatives were considered
- What mistakes were avoided
- How the final design was validated

---

**End of Session Notes**

**Date:** 2025-10-03
**Outcome:** Hybrid architecture approved, ready for Phase 1 implementation
**Next Session:** Configuration System Expansion (Week 1)
