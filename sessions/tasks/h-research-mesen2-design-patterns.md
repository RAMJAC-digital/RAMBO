---
name: h-research-mesen2-design-patterns
branch: none
status: pending
created: 2025-11-02
---

# Research Mesen2 Design Patterns and Architecture

## Problem/Goal
Investigate Mesen2's design patterns, architecture, and implementation approaches to identify opportunities for improving RAMBO's codebase. Focus on PPU/NMI/OAM-related patterns that could make hardware accuracy fixes easier to implement. Compare Mesen2's approaches against RAMBO's current architecture to find best practices and refactoring opportunities.

## Success Criteria
- [ ] **Mesen2 architecture documented** - Document Mesen2's overall architecture, focusing on PPU/NMI/OAM/DMA implementation patterns
- [ ] **RAMBO vs Mesen2 comparison** - Side-by-side comparison of key design patterns (State/Logic separation, timing models, DMA handling)
- [ ] **PPU/NMI/OAM pattern analysis** - Detailed analysis of Mesen2's PPU/NMI/OAM timing patterns that could ease RAMBO's accuracy fixes
- [ ] **Best practices identified** - Document Mesen2 best practices applicable to cycle-accurate emulation
- [ ] **Refactoring opportunities cataloged** - List specific areas where RAMBO could adopt Mesen2 patterns (with priority/effort estimates)
- [ ] **Follow-up task recommendations** - Propose concrete implementation/refactor tasks based on findings

## Context Manifest

### Hardware Research Context (RAMBO's Foundation)

**CRITICAL: Hardware Documentation is Ground Truth**

RAMBO's architecture is fundamentally built on NES hardware specifications from nesdev.org. All design patterns must preserve hardware accuracy. The comparative research with Mesen2 should focus on **HOW** to achieve accuracy, not **WHAT** the accuracy requirements are (those are already documented).

**Primary Hardware References:**
- https://www.nesdev.org/wiki/PPU_frame_timing (VBlank/NMI timing)
- https://www.nesdev.org/wiki/PPU_sprite_evaluation (Sprite evaluation cycles)
- https://www.nesdev.org/wiki/PPU_rendering (Complete rendering pipeline)
- https://www.nesdev.org/wiki/DMA (OAM/DMC DMA interaction)
- https://www.nesdev.org/wiki/CPU (6502 cycle timing)

**Hardware Accuracy Constraints:**
- Cycle-accurate execution (PPU cycle granularity)
- Sub-cycle execution order: CPU reads/writes → PPU flag updates
- Progressive sprite evaluation (dots 65-256)
- DMC DMA priority over OAM DMA
- NMI edge detection (not level-triggered)
- Open bus behavior (last bus value decay)

---

### RAMBO Current Architecture - Complete System Overview

**Version:** 0.2.0-alpha
**Test Status:** 1023/1041 passing (98.3%), 12 failing, 6 skipped
**Language:** Zig 0.15.1
**Primary Documentation:** `/home/colin/Development/RAMBO/CLAUDE.md`

#### 1. Core Architecture Patterns

**State/Logic Separation Pattern (RAMBO's Foundation)**

RAMBO uses a **hybrid State/Logic separation** pattern throughout the codebase. This is the most important architectural pattern to understand when comparing with Mesen2.

**State Modules (`State.zig`):**
- Pure data structures (structs, enums, constants)
- Zero business logic except convenience delegation methods
- Fully serializable for save states
- Optional non-owning pointers only
- Example: `src/cpu/State.zig`, `src/ppu/State.zig`, `src/apu/State.zig`

```zig
// Pattern: State.zig - Pure data with convenience delegation
pub const CpuState = struct {
    // Pure data fields
    a: u8, x: u8, y: u8, sp: u8, pc: u16,
    p: StatusRegister,
    instruction_cycle: u8,
    opcode: u8,

    // Convenience delegation (calls Logic, doesn't implement logic)
    pub inline fn tick(self: *CpuState, bus: *BusState) void {
        Logic.tick(self, bus);  // Delegates to Logic.zig
    }
};
```

**Logic Modules (`Logic.zig`):**
- Pure functions operating on State pointers
- NO hidden state - all mutations via explicit parameters
- All side effects explicit
- Deterministic, testable in isolation
- Example: `src/cpu/Logic.zig`, `src/ppu/Logic.zig`, `src/apu/Logic.zig`

```zig
// Pattern: Logic.zig - Pure functions
pub fn tick(cpu: *CpuState, bus: *BusState) void {
    // Pure function - all state passed explicitly
    // No global variables, no hidden mutations
    const opcode = bus.read(cpu.pc);
    cpu.pc +%= 1;
    // ... pure execution logic
}
```

**Why This Matters for Research:**
- Mesen2 may use different organization (classes with methods vs. separate State/Logic)
- Compare: How does Mesen2 organize PPU state vs. PPU logic?
- Consider: Does Mesen2's pattern make edge cases easier/harder to handle?
- Evaluate: Serialization complexity (save states)
- Note: Pure functions enable isolated unit testing

**Files to Examine:**
- RAMBO: `src/cpu/State.zig` (lines 1-200), `src/cpu/Logic.zig` (lines 1-100)
- RAMBO: `src/ppu/State.zig` (lines 1-150), `src/ppu/Logic.zig` (lines 1-100)
- Mesen2: `/home/colin/Development/Mesen2/Core/NES/NesCpu.h` (lines 19-90)
- Mesen2: `/home/colin/Development/Mesen2/Core/NES/NesPpu.h` (lines 33-103)

---

#### 2. VBlank/NMI Timing Pattern (Pure Data Ledgers)

**CURRENT STATUS:** 10 AccuracyCoin tests failing (VBlank/NMI timing bugs)
**CRITICAL FOCUS AREA:** This is where RAMBO needs improvement

**RAMBO's VBlank Pattern: Timestamp-Based Ledger**

RAMBO uses a **pure data ledger** pattern for VBlank timing:

**File:** `src/emulation/VBlankLedger.zig` (75 lines total)
```zig
pub const VBlankLedger = struct {
    // Pure timestamps (no business logic)
    last_set_cycle: u64 = 0,
    last_clear_cycle: u64 = 0,
    last_read_cycle: u64 = 0,
    last_race_cycle: u64 = 0,

    // Query methods (no mutations)
    pub inline fn isActive(self: VBlankLedger) bool {
        return self.last_set_cycle > self.last_clear_cycle;
    }

    pub inline fn isFlagVisible(self: VBlankLedger) bool {
        if (!self.isActive()) return false;
        if (self.last_read_cycle >= self.last_set_cycle) return false;
        return true;
    }

    // ONLY mutation method
    pub fn reset(self: *VBlankLedger) void {
        self.* = .{};
    }
};
```

**All VBlank mutations happen in EmulationState:**
- `src/emulation/State.zig:setVBlankFlag()` - Direct field assignment
- `src/emulation/State.zig:clearVBlankFlag()` - Direct field assignment
- `src/emulation/State.zig:applyPpuCycleResult()` - PPU flag updates AFTER CPU execution

**Critical Sub-Cycle Execution Order (LOCKED BEHAVIOR):**

**File:** `src/emulation/State.zig:tick()` (lines 617-699)
```zig
pub fn tick(self: *EmulationState) void {
    // 1. PPU rendering (pixel output)
    var ppu_result = self.stepPpuCycle(scanline, dot);

    // 2. APU processing (BEFORE CPU for IRQ state)
    if (step.apu_tick) {
        const apu_result = self.stepApuCycle();
    }

    // 3. CPU memory operations (reads/writes including $2002)
    if (step.cpu_tick) {
        self.cpu.irq_line = ...;
        _ = self.stepCpuCycle();  // ← CPU executes FIRST
    }

    // 4. PPU flag updates (VBlank set, sprite eval, etc.)
    self.applyPpuCycleResult(ppu_result);  // ← VBlank flag set AFTER CPU
}
```

**Hardware Race Condition (scanline 241, dot 1):**
- CPU reads $2002 → sees VBlank bit = 0 (flag not set yet)
- PPU sets VBlank flag → flag becomes 1
- Result: CPU missed VBlank (same-cycle race)
- Implementation verified per: https://www.nesdev.org/wiki/PPU_frame_timing

**RESEARCH QUESTION FOR MESEN2:**
- How does Mesen2 handle VBlank/NMI timing?
- Does Mesen2 use a similar ledger pattern or different approach?
- How does Mesen2 implement sub-cycle execution order?
- What patterns make edge case handling easier?

**Files to Compare:**
- RAMBO: `src/emulation/VBlankLedger.zig` (75 lines)
- RAMBO: `src/emulation/State.zig` (lines 617-727)
- Mesen2: `/home/colin/Development/Mesen2/Core/NES/NesPpu.cpp` (lines 1249-1267 - BeginVBlank, TriggerNmi)
- Mesen2: Search for "NmiFlag", "VerticalBlank", "$2002 read" patterns

---

#### 3. OAM/DMA Implementation (DMC/OAM Interaction)

**CURRENT STATUS:** AccuracyCoin OAM/NMI tests failing
**CRITICAL FOCUS AREA:** DMA timing and interaction patterns

**RAMBO's DMA Pattern: Functional Edge Detection**

RAMBO uses **functional pattern** (no state machines) for DMA:

**OAM DMA State:**
**File:** `src/emulation/state/peripherals/OamDma.zig` (48 lines)
```zig
pub const OamDma = struct {
    active: bool = false,
    source_page: u8 = 0,
    current_offset: u8 = 0,
    current_cycle: u16 = 0,
    needs_alignment: bool = false,
    temp_value: u8 = 0,

    pub fn trigger(self: *OamDma, page: u8, on_odd_cycle: bool) void {
        self.active = true;
        self.source_page = page;
        self.current_offset = 0;
        self.current_cycle = 0;
        self.needs_alignment = on_odd_cycle;
        self.temp_value = 0;
    }
};
```

**DMC DMA State:**
**File:** `src/emulation/state/peripherals/DmcDma.zig` (42 lines)
```zig
pub const DmcDma = struct {
    rdy_low: bool = false,
    transfer_complete: bool = false,
    stall_cycles_remaining: u8 = 0,
    sample_address: u16 = 0,
    sample_byte: u8 = 0,
    last_read_address: u16 = 0,

    pub fn triggerFetch(self: *DmcDma, address: u16) void {
        self.rdy_low = true;
        self.stall_cycles_remaining = 4; // 3 idle + 1 fetch
        self.sample_address = address;
    }
};
```

**DMA Interaction Ledger:**
**File:** `src/emulation/DmaInteractionLedger.zig` (70 lines)
```zig
pub const DmaInteractionLedger = struct {
    // Timestamps following VBlankLedger pattern
    last_dmc_active_cycle: u64 = 0,
    last_dmc_inactive_cycle: u64 = 0,
    oam_pause_cycle: u64 = 0,
    oam_resume_cycle: u64 = 0,
    needs_alignment_after_dmc: bool = false,

    pub fn reset(self: *DmaInteractionLedger) void {
        self.* = .{};
    }
};
```

**DMA Logic (Functional Pattern):**
**File:** `src/emulation/dma/logic.zig` (lines 1-100)
```zig
pub fn tickOamDma(state: anytype) void {
    // Functional check: Is DMC stalling OAM?
    const dmc_is_stalling_oam = state.dmc_dma.rdy_low and
        (state.dmc_dma.stall_cycles_remaining == 4 or  // Halt cycle
         state.dmc_dma.stall_cycles_remaining == 1);   // Read cycle

    if (dmc_is_stalling_oam) {
        return;  // OAM pauses during DMC halt and read cycles
    }

    // Post-DMC alignment cycle check
    if (ledger.needs_alignment_after_dmc) {
        ledger.needs_alignment_after_dmc = false;
        return; // Pure wait cycle
    }

    // Read/write cycle determination
    const is_read_cycle = @rem(effective_cycle, 2) == 0;
    if (is_read_cycle) {
        // READ
        dma.temp_value = state.busRead(addr);
    } else {
        // WRITE
        state.ppu.oam[state.ppu.oam_addr] = dma.temp_value;
        state.ppu.oam_addr +%= 1;
        dma.current_offset +%= 1;
    }
}
```

**Hardware Behavior (per nesdev.org/wiki/DMA):**
- DMC has absolute priority over OAM
- OAM pauses ONLY during DMC halt (cycle 1) and read (cycle 4)
- OAM continues during DMC dummy (cycle 2) and alignment (cycle 3) - time-sharing
- After DMC completes, OAM needs one extra alignment cycle

**RESEARCH QUESTION FOR MESEN2:**
- How does Mesen2 handle DMC/OAM DMA interaction?
- State machine vs. functional approach?
- How does Mesen2 track DMA conflicts/pausing?
- Pattern for byte duplication edge cases?

**Files to Compare:**
- RAMBO: `src/emulation/dma/logic.zig` (lines 1-150)
- RAMBO: `src/emulation/state/peripherals/` (OamDma.zig, DmcDma.zig)
- Mesen2: Search for "SpriteDMA", "DMC", "RunDMATransfer" in NesCpu.cpp
- Mesen2: Look for DMA handling in CPU execution loop

---

#### 4. PPU Implementation

**Current PPU State Structure:**

**File:** `src/ppu/State.zig` (lines 1-500+)

**Key State Components:**
- Registers: `PpuCtrl`, `PpuMask`, `PpuStatus` (packed structs)
- VRAM: `vram[2048]u8` (nametables)
- OAM: `oam[256]u8` (sprite memory)
- Secondary OAM: `secondary_oam[32]u8` (sprite evaluation buffer)
- Palette: `palette_ram[32]u8`
- Internal: `v`, `t`, `x`, `w` (scroll registers)
- Frame buffer: `frame_buffer[256 * 240]u32` (RGBA output)

**PPU Logic Organization:**

**File:** `src/ppu/Logic.zig` (facade delegating to specialized modules)

**Sub-modules:**
- `src/ppu/logic/background.zig` - Background tile fetching/rendering
- `src/ppu/logic/sprites.zig` - Sprite evaluation and rendering
- `src/ppu/logic/memory.zig` - VRAM access
- `src/ppu/logic/scrolling.zig` - Scroll register manipulation
- `src/ppu/logic/registers.zig` - CPU register I/O

**Sprite Evaluation (Progressive Pattern):**

**File:** `src/ppu/logic/sprites.zig` (lines 200-400)
```zig
// Hardware-accurate progressive sprite evaluation
// Dots 1-64: Secondary OAM clear (8 cycles per entry, 2 dots per cycle)
// Dots 65-256: Sprite evaluation (examines all 64 OAM entries)
// Dots 257-320: Sprite fetch cycles for next scanline
```

**Implementation Approach:**
- Dot-by-dot evaluation (not instant)
- Odd cycles: Read from OAM
- Even cycles: Write to secondary OAM
- Sprite overflow flag has hardware bug (documented)

**RESEARCH QUESTION FOR MESEN2:**
- How does Mesen2 organize PPU state vs. logic?
- PPU module structure and file organization?
- Sprite evaluation pattern (progressive vs. other)?
- How does Mesen2 handle PPU timing edge cases?

**Files to Compare:**
- RAMBO: `src/ppu/State.zig` (lines 1-200)
- RAMBO: `src/ppu/logic/sprites.zig` (lines 1-300)
- Mesen2: `/home/colin/Development/Mesen2/Core/NES/NesPpu.h` (lines 1-155)
- Mesen2: `/home/colin/Development/Mesen2/Core/NES/NesPpu.cpp` (lines 959-1100 - ProcessSpriteEvaluation)

---

#### 5. Comptime Generics (Zero-Cost Polymorphism)

**Pattern:** All polymorphism uses comptime duck typing - zero runtime overhead

**Example: Cartridge System**

**File:** `src/cartridge/Cartridge.zig`
```zig
pub fn Cartridge(comptime MapperType: type) type {
    return struct {
        mapper: MapperType,
        prg_rom: []const u8,
        chr_rom: []u8,

        // Direct delegation - no VTable, fully inlined
        pub fn cpuRead(self: *const Self, address: u16) u8 {
            return self.mapper.cpuRead(self, address);
        }
    };
}

// Usage - compile-time type instantiation
const NromCart = Cartridge(Mapper0);  // Zero runtime overhead
```

**Type-Erased Registry (when needed):**

**File:** `src/cartridge/mappers/registry.zig`
```zig
pub const AnyCartridge = union(enum) {
    nrom: Cartridge(Mapper0),
    mmc1: Cartridge(Mapper1),
    mmc3: Cartridge(Mapper4),
    // ... more mappers

    pub inline fn cpuRead(self: *const AnyCartridge, address: u16) u8 {
        return switch (self.*) {
            inline else => |*cart| cart.cpuRead(address),
        };
    }
};
```

**RESEARCH QUESTION FOR MESEN2:**
- Does Mesen2 use virtual functions (C++ polymorphism)?
- Runtime overhead vs. compile-time optimization?
- How does mapper polymorphism work?
- Tradeoffs: Flexibility vs. Performance?

**Files to Compare:**
- RAMBO: `src/cartridge/Cartridge.zig`
- RAMBO: `src/cartridge/mappers/registry.zig`
- Mesen2: `/home/colin/Development/Mesen2/Core/NES/BaseMapper.h`
- Mesen2: `/home/colin/Development/Mesen2/Core/NES/BaseMapper.cpp`

---

#### 6. Thread Architecture

**Pattern:** 3-thread mailbox with RT-safe emulation

**Threads:**
1. **Main Thread** - Coordinator (minimal work, libxev event loop)
2. **Emulation Thread** - Cycle-accurate CPU/PPU/APU (RT-safe, zero heap allocations)
3. **Render Thread** - Backend-agnostic rendering (60 FPS, comptime backend selection)

**Rendering Backends (Comptime Polymorphism):**
- **VulkanBackend** - Wayland + Vulkan rendering (default)
- **MovyBackend** - Terminal rendering (optional, requires `-Dwith_movy=true`)

**Communication: Lock-Free Mailboxes**

**Files:**
- `src/mailboxes/FrameMailbox.zig` - Emulation → Render (triple-buffer atomic swap)
- `src/mailboxes/ControllerInputMailbox.zig` - Main → Emulation
- `src/mailboxes/DebugCommandMailbox.zig` - Main → Emulation
- `src/mailboxes/DebugEventMailbox.zig` - Emulation → Main
- `src/mailboxes/SpscRingBuffer.zig` - Generic SPSC ring buffer

**RT-Safety Guarantees:**
- Zero heap allocations in emulation hot path
- No blocking I/O operations
- No mutex waits (atomic operations only)
- Deterministic execution time

**RESEARCH QUESTION FOR MESEN2:**
- What is Mesen2's threading model?
- Single-threaded vs. multi-threaded?
- How does Mesen2 handle rendering/emulation coordination?
- RT-safety considerations?

**Files to Compare:**
- RAMBO: `src/threads/EmulationThread.zig`
- RAMBO: `src/threads/RenderThread.zig`
- Mesen2: Look for threading in NesConsole.cpp, main execution loop

---

#### 7. Test Infrastructure and Coverage

**Current Test Status:** 1023/1041 (98.3%), 12 failing, 6 skipped
**Last Verified:** 2025-10-20
**Full Details:** `docs/STATUS.md`

**Test Categories:**

| Component | Tests | Status | Files |
|-----------|-------|--------|-------|
| CPU | ~280 | ✅ All passing | `tests/cpu/` |
| PPU | ~93 | ✅ All passing | `tests/ppu/` |
| APU | 135 | ✅ All passing | `tests/apu/` |
| Integration | 94 | ⚠️ 11 failing (VBlank/NMI) | `tests/integration/` |
| Mailboxes | 57 | ✅ All passing | `tests/mailboxes/` |
| Input | 40 | ✅ All passing | `tests/input/` |
| Threading | 14 | ⚠️ 5 skipped | `tests/threading/` |

**Failing Tests (CRITICAL FOCUS):**

**AccuracyCoin Tests (10 failures - VBlank/NMI timing):**
- `all_nop_instructions_test` - FAIL (err=1)
- `unofficial_instructions_test` - FAIL (err=10)
- `nmi_control_test` - FAIL (err=7)
- `vblank_end_test` - FAIL (err=1)
- `nmi_disabled_vblank_test` - FAIL (err=1)
- `vblank_beginning_test` - FAIL (err=1)
- `nmi_vblank_end_test` - FAIL (err=1)
- `nmi_suppression_test` - FAIL (err=1)
- `nmi_timing_test` - FAIL (err=1)
- `cpu_ppu_integration_test` - VBlank race condition

**Test Files for Reference:**
- `tests/integration/accuracy/nmi_timing_test.zig` - Example AccuracyCoin test
- `tests/integration/oam_dma_test.zig` - OAM DMA integration tests
- `tests/integration/dmc_oam_conflict_test.zig` - DMC/OAM conflict tests
- `tests/emulation/state/vblank_ledger_test.zig` - VBlank ledger unit tests

**Test Documentation:**
- `docs/testing/dmc-oam-dma-test-strategy.md` - Comprehensive DMA test strategy (264 lines)
- `docs/testing/accuracycoin-cpu-requirements.md` - AccuracyCoin test requirements
- `docs/STATUS.md` - Single source of truth for test status

**RESEARCH QUESTION FOR MESEN2:**
- What is Mesen2's test coverage approach?
- Unit tests vs. integration tests?
- How does Mesen2 verify hardware accuracy?
- Test ROM usage (blargg's tests, etc.)?

---

### Current Issues - Known Bugs to Address

**File:** `docs/CURRENT-ISSUES.md` (482 lines, last updated 2025-10-15)

**Priority 0 - Critical:**
- TMNT series: Grey screen (game-specific compatibility issue)
- Paperboy: Grey screen (similar to TMNT)

**Priority 1 - High (VBlank/NMI Focus):**
- 10 AccuracyCoin VBlank/NMI tests failing
- SMB1: Sprite palette bug (left side green instead of yellow/orange)
- SMB3: Checkered floor disappears after few frames
- Kirby's Adventure: Dialog box doesn't render

**Recent Major Fixes (Context for Research):**

**✅ NMI Line Management (2025-10-15)** - Fixed critical bug preventing commercial ROMs from receiving interrupts
- Commit: 1985d74
- Impact: Castlevania, Mega Man, Kid Icarus now working
- Pattern: NMI line reflects VBlank flag state directly

**✅ Progressive Sprite Evaluation (2025-10-15)** - Hardware-accurate cycle-by-cycle sprite evaluation
- Commits: 8484b40, 79a806f
- Impact: SMB1 title screen animates correctly (+3 tests)
- Pattern: Dot-by-dot evaluation matching hardware

**✅ RAM Initialization (2025-10-14)** - Pseudo-random RAM at power-on
- Commit: 069fb76
- Impact: Commercial ROMs take correct boot paths (+54 tests)
- Pattern: Deterministic LCG for reproducible behavior

**Investigation Notes:**
- Phase 2 focus: Mid-frame register changes (PPUCTRL/PPUMASK timing)
- Hardware documentation: https://www.nesdev.org/wiki/PPU_frame_timing
- Known limitations: CPU timing deviation (Absolute,X/Y no page cross +1 cycle)

---

### Mesen2 Codebase Structure - Investigation Targets

**Location:** `/home/colin/Development/Mesen2`
**Language:** C++
**Build System:** CMake/Visual Studio
**Status:** Multi-system emulator (NES, SNES, GB, GBA, etc.)

#### Directory Structure

```
Mesen2/
├── Core/                          # Emulation cores
│   ├── NES/                       # NES emulation (PRIMARY FOCUS)
│   │   ├── NesCpu.h/cpp          # CPU implementation
│   │   ├── NesPpu.h/cpp          # PPU implementation (template class)
│   │   ├── BaseNesPpu.h/cpp      # PPU base class
│   │   ├── NesTypes.h            # Type definitions
│   │   ├── NesConsole.h/cpp      # Console coordination
│   │   ├── APU/                  # Audio processing
│   │   ├── Mappers/              # Cartridge mappers (extensive)
│   │   ├── Input/                # Controller input
│   │   └── Debugger/             # Debugging tools
│   ├── Shared/                    # Shared utilities
│   ├── SNES/, Gameboy/, etc.     # Other systems
│   └── Debugger/                  # Cross-system debugger
├── UI/                            # User interface (not relevant)
├── Utilities/                     # Helper libraries
└── [platform dirs]                # Linux, Windows, MacOS

```

#### NES Core Files (Primary Investigation Targets)

**CPU Implementation:**
- `/home/colin/Development/Mesen2/Core/NES/NesCpu.h` (857 lines)
- `/home/colin/Development/Mesen2/Core/NES/NesCpu.cpp` (~24KB)
- Pattern: Class-based, methods for opcodes
- Note: `_state` member (NesCpuState), method-based execution

**PPU Implementation:**
- `/home/colin/Development/Mesen2/Core/NES/NesPpu.h` (155 lines - template class)
- `/home/colin/Development/Mesen2/Core/NES/NesPpu.cpp` (56KB - large implementation)
- `/home/colin/Development/Mesen2/Core/NES/BaseNesPpu.h/cpp` (base class)
- Pattern: Template class `NesPpu<T>`, inheritance hierarchy
- Key methods: `Exec()`, `ProcessSpriteEvaluation()`, `BeginVBlank()`, `TriggerNmi()`

**Type Definitions:**
- `/home/colin/Development/Mesen2/Core/NES/NesTypes.h` (472 lines)
- State structs: `NesCpuState`, `NesPpuState`, `ApuState`, `CartridgeState`
- Flags: `PPUStatusFlags`, `PpuControlFlags`, `PpuMaskFlags`
- Note: State separate from implementation (similar to RAMBO pattern?)

**Console Coordination:**
- `/home/colin/Development/Mesen2/Core/NES/NesConsole.h/cpp`
- Orchestrates CPU/PPU/APU interaction
- May contain DMA handling coordination

#### Key Investigation Areas

**1. VBlank/NMI Timing:**

**Located in NesPpu.cpp:**
```
Line 1249: BeginVBlank()
Line 1254: TriggerNmi()
Line 545: Comment about multiple NMIs via $2000 bit 7
Line 591: Comment about reading $2002 one PPU clock before
```

**Search Terms:**
- "BeginVBlank", "TriggerNmi", "VerticalBlank"
- "$2002", "PPUSTATUS", "_statusFlags.VerticalBlank"
- "NmiFlag", "SetNmiFlag", "_needNmi"

**2. Sprite Evaluation:**

**Located in NesPpu.cpp:**
```
Line 959: ProcessSpriteEvaluationStart()
Line 979: ProcessSpriteEvaluationEnd()
Line 1004: ProcessSpriteEvaluation()
Line 886: Comment about sprite evaluation not on pre-render line
```

**Search Terms:**
- "ProcessSpriteEvaluation", "secondary OAM"
- "_spriteRam", "_secondarySpriteRam"
- "sprite evaluation", "OAM copy"

**3. OAM/DMC DMA:**

**Located in NesCpu.cpp (likely):**
```
NesPpu.cpp Line 504-505: SpriteDMA register case
    _console->GetCpu()->RunDMATransfer(value);
```

**Search Terms in NesCpu:**
- "RunDMATransfer", "SpriteDMA"
- "DMC DMA", "_spriteDmaTransfer", "_dmcDmaRunning"
- "ProcessPendingDma"

**Methods to Examine:**
- `NesCpu::StartCpuCycle()` - DMA handling per cycle?
- `NesCpu::ProcessPendingDma()` - DMA conflict resolution?
- `NesCpu::ProcessDmaRead()` - DMC read handling?

**4. State Management:**

**NesTypes.h Patterns:**
- Separate state structs (like RAMBO)
- State serialization (Mesen2 has save states)
- Compare: Struct-based state vs. class members

**5. Timing Model:**

**PPU Execution:**
```cpp
template<class T> void NesPpu<T>::Run(uint64_t runTo) {
    do {
        Exec();  // Single PPU cycle
        _masterClock += _masterClockDivider;
    } while(_masterClock + _masterClockDivider <= runTo);
}
```

**CPU Execution:**
- Look for master clock synchronization
- CPU/PPU cycle ratio handling (1:3 with nuances)

---

### Comparison Framework - Research Methodology

#### Phase 1: File Organization Comparison

**Task:** Compare how RAMBO and Mesen2 organize code

**RAMBO Pattern:**
- State.zig (pure data) + Logic.zig (pure functions)
- Logic modules in subdirectories (cpu/opcodes/, ppu/logic/)
- Separate files: VBlankLedger.zig, DmaInteractionLedger.zig

**Mesen2 Pattern:**
- Class-based (NesCpu, NesPpu<T>)
- State structs in NesTypes.h
- Methods on classes vs. free functions

**Questions:**
1. Does Mesen2 mix state and logic in classes?
2. How testable are Mesen2's components in isolation?
3. Serialization complexity comparison?
4. Code navigation: methods vs. modules?

#### Phase 2: VBlank/NMI Pattern Comparison

**RAMBO's Approach:**
- Pure timestamp ledger (VBlankLedger)
- External state management (EmulationState)
- Sub-cycle execution order in tick()

**Mesen2's Approach (TO INVESTIGATE):**
- BeginVBlank() / TriggerNmi() methods
- _statusFlags.VerticalBlank flag management
- _needNmi, _prevNeedNmi tracking
- Sub-cycle ordering?

**Questions:**
1. How does Mesen2 handle $2002 read at scanline 241 dot 1?
2. Pattern for NMI edge detection?
3. Race condition handling?
4. Multiple NMI prevention?

#### Phase 3: DMA Pattern Comparison

**RAMBO's Approach:**
- Functional edge detection (no state machine)
- Time-sharing during DMC cycles 2-3
- DmaInteractionLedger timestamps

**Mesen2's Approach (TO INVESTIGATE):**
- RunDMATransfer() implementation
- ProcessPendingDma() coordination
- _spriteDmaTransfer, _dmcDmaRunning flags
- Conflict resolution pattern?

**Questions:**
1. State machine vs. functional approach?
2. How does Mesen2 pause OAM during DMC?
3. Byte duplication edge case handling?
4. Alignment cycle tracking?

#### Phase 4: Sprite Evaluation Comparison

**RAMBO's Approach:**
- Progressive evaluation (dots 65-256)
- Odd cycles: read, even cycles: write
- State in PpuState (secondary_oam, sprite_eval_n)

**Mesen2's Approach (TO INVESTIGATE):**
- ProcessSpriteEvaluation() cycle-by-cycle?
- _secondarySpriteRam management
- OAM wrapping edge cases
- Sprite overflow bug implementation

**Questions:**
1. Progressive vs. instant evaluation?
2. Cycle-accurate or simplified?
3. Edge case handling patterns?
4. Secondary OAM corruption bugs?

#### Phase 5: Testing Strategy Comparison

**RAMBO's Approach:**
- Unit tests (pure functions)
- Integration tests (full system)
- AccuracyCoin ROM tests
- Test harness (Harness.zig)

**Mesen2's Approach (TO INVESTIGATE):**
- Look for test/ directory
- Test ROM usage?
- Hardware verification approach?
- Debug/diagnostic tools?

**Questions:**
1. What is Mesen2's test coverage?
2. How does Mesen2 verify accuracy?
3. Test infrastructure patterns?
4. Regression prevention?

---

### Investigation Roadmap - Systematic Exploration

**Goal:** Identify patterns that could address RAMBO's 12 failing tests

#### Step 1: VBlank/NMI Investigation (PRIORITY 1)

**Focus:** Address 10 failing AccuracyCoin tests

**Files to Read:**
1. `Mesen2/Core/NES/NesPpu.cpp` - Lines 1249-1267 (BeginVBlank, TriggerNmi)
2. `Mesen2/Core/NES/NesPpu.cpp` - Line 545 (Multiple NMI comment)
3. `Mesen2/Core/NES/NesPpu.cpp` - Line 591 ($2002 read timing comment)
4. `Mesen2/Core/NES/NesCpu.cpp` - Search for "NmiFlag", "SetNmiFlag"
5. `Mesen2/Core/NES/NesTypes.h` - NesCpuState, NesPpuState structures

**Questions to Answer:**
- How does Mesen2 prevent multiple NMI triggers?
- $2002 read at VBlank set timing handling?
- NMI edge detection vs. level triggering?
- Sub-cycle execution order (CPU reads before PPU flag updates)?
- VBlank flag clear timing (after read, timing boundaries)?

**Expected Findings:**
- Pattern for NMI edge detection
- $2002 race condition handling
- Flag state management approach
- Potential improvements for RAMBO's VBlankLedger

#### Step 2: DMA Interaction Investigation (PRIORITY 1)

**Focus:** Address OAM/DMC DMA failures

**Files to Read:**
1. `Mesen2/Core/NES/NesCpu.cpp` - Search "RunDMATransfer"
2. `Mesen2/Core/NES/NesCpu.cpp` - Search "ProcessPendingDma"
3. `Mesen2/Core/NES/NesCpu.cpp` - Search "_spriteDmaTransfer", "_dmcDmaRunning"
4. `Mesen2/Core/NES/NesCpu.h` - Lines 39-44 (DMA flags)
5. `Mesen2/Core/NES/NesPpu.cpp` - Lines 504-505 (SpriteDMA register)

**Questions to Answer:**
- How does Mesen2 coordinate DMC/OAM DMA conflicts?
- Pause/resume mechanism for OAM during DMC?
- Byte duplication handling?
- Alignment cycle tracking?
- Time-sharing pattern (OAM continues during DMC dummy cycles)?

**Expected Findings:**
- DMA coordination pattern
- Conflict resolution strategy
- State tracking approach
- Potential improvements for RAMBO's DMA logic

#### Step 3: PPU Organization Investigation (PRIORITY 2)

**Focus:** Learn PPU modularity patterns

**Files to Read:**
1. `Mesen2/Core/NES/NesPpu.h` - Template class structure
2. `Mesen2/Core/NES/BaseNesPpu.h/cpp` - Base class pattern
3. `Mesen2/Core/NES/NesPpu.cpp` - Lines 959-1100 (ProcessSpriteEvaluation)
4. `Mesen2/Core/NES/NesTypes.h` - PPU state structures
5. Compare against RAMBO's `src/ppu/logic/` modules

**Questions to Answer:**
- How does template pattern benefit PPU implementation?
- State vs. logic separation in class hierarchy?
- Sprite evaluation modularity?
- Register I/O handling patterns?
- Mid-frame register change handling?

**Expected Findings:**
- Class organization tradeoffs
- Modularity patterns
- Edge case handling approaches
- Potential refactoring opportunities for RAMBO

#### Step 4: State Management Investigation (PRIORITY 2)

**Focus:** Compare state management approaches

**Files to Read:**
1. `Mesen2/Core/NES/NesTypes.h` - All state structs (472 lines)
2. Compare against RAMBO's State.zig files
3. Look for serialization code (save state implementation)
4. Examine state mutation patterns

**Questions to Answer:**
- Pure data structs vs. class members?
- State serialization complexity?
- State visibility (public/private)?
- Mutation control (who can modify what)?
- Testing implications?

**Expected Findings:**
- State management patterns
- Encapsulation tradeoffs
- Serialization approaches
- Potential improvements for RAMBO's State pattern

#### Step 5: Testing/Verification Investigation (PRIORITY 3)

**Focus:** Learn verification strategies

**Files to Search:**
1. Look for test/ or tests/ directory
2. Search for test ROM references (blargg, etc.)
3. Examine debug/diagnostic tools
4. Look for accuracy verification approaches

**Questions to Answer:**
- Does Mesen2 have unit tests?
- Test ROM usage patterns?
- How is hardware accuracy verified?
- Regression prevention strategies?
- Debug tool patterns?

**Expected Findings:**
- Testing infrastructure patterns
- Verification methodologies
- Debug tool capabilities
- Potential test improvements for RAMBO

---

### Comparison Metrics - Evaluation Criteria

**For Each Pattern Investigated, Evaluate:**

#### 1. Hardware Accuracy
- ✅ **Criterion:** Does the pattern make cycle-accurate implementation easier?
- 📊 **Measure:** Edge case handling complexity
- 🎯 **Goal:** Reduce likelihood of timing bugs

#### 2. Testability
- ✅ **Criterion:** Can components be tested in isolation?
- 📊 **Measure:** Unit test coverage potential
- 🎯 **Goal:** Fast, deterministic tests

#### 3. Readability
- ✅ **Criterion:** Is the code obvious and easy to follow?
- 📊 **Measure:** Time to understand critical paths
- 🎯 **Goal:** Maintainability (RAMBO principle: readability > cleverness)

#### 4. Modularity
- ✅ **Criterion:** Are concerns properly separated?
- 📊 **Measure:** Code coupling and cohesion
- 🎯 **Goal:** Changes don't cascade across modules

#### 5. Performance
- ✅ **Criterion:** Runtime overhead of pattern
- 📊 **Measure:** Instruction count, cache locality
- 🎯 **Goal:** 60 FPS emulation on modest hardware

#### 6. Debug-ability
- ✅ **Criterion:** How easy is it to diagnose bugs?
- 📊 **Measure:** State inspection, logging points
- 🎯 **Goal:** Rapid bug identification

---

### Expected Deliverables - Research Output

**After completing research, produce:**

#### 1. Architecture Comparison Document
- Side-by-side comparison of RAMBO vs. Mesen2 patterns
- Tradeoffs for each approach
- Visual diagrams (if helpful)

#### 2. VBlank/NMI Pattern Analysis
- Detailed explanation of Mesen2's approach
- Comparison with RAMBO's VBlankLedger
- Recommendations for RAMBO improvements
- Specific fixes for failing tests

#### 3. DMA Pattern Analysis
- Detailed explanation of Mesen2's DMA coordination
- Comparison with RAMBO's functional approach
- Recommendations for OAM/DMC conflict handling
- Edge case patterns to adopt

#### 4. PPU Modularity Report
- Mesen2's PPU organization strengths/weaknesses
- RAMBO's logic/ subdirectory assessment
- Refactoring opportunities
- Mid-frame register change handling insights

#### 5. Refactoring Recommendations
- **Priority 1:** Fixes for 12 failing tests
- **Priority 2:** Architectural improvements
- **Priority 3:** Long-term refactoring opportunities
- Each recommendation with effort estimate

#### 6. Follow-Up Task List
- Concrete implementation tasks based on findings
- Prioritized by impact on test failures
- Effort estimates (small/medium/large)
- Dependencies between tasks

---

### Key Files Reference - Quick Navigation

**RAMBO Critical Files:**
```
src/emulation/State.zig                  # Main tick() loop, sub-cycle ordering
src/emulation/VBlankLedger.zig           # Pure timestamp ledger (75 lines)
src/emulation/DmaInteractionLedger.zig   # DMA timestamp ledger (70 lines)
src/emulation/dma/logic.zig              # OAM/DMC DMA logic (functional)
src/ppu/State.zig                        # PPU state structure
src/ppu/Logic.zig                        # PPU logic facade
src/ppu/logic/sprites.zig                # Sprite evaluation
src/cpu/State.zig                        # CPU state structure
src/cpu/Logic.zig                        # CPU execution logic
docs/STATUS.md                           # Single source of truth for test status
docs/CURRENT-ISSUES.md                   # Known bugs and issues
docs/testing/dmc-oam-dma-test-strategy.md # DMA test documentation
```

**Mesen2 Investigation Targets:**
```
Core/NES/NesCpu.h                        # CPU class definition (857 lines)
Core/NES/NesCpu.cpp                      # CPU implementation (~24KB)
Core/NES/NesPpu.h                        # PPU template class (155 lines)
Core/NES/NesPpu.cpp                      # PPU implementation (56KB)
Core/NES/NesTypes.h                      # State structures (472 lines)
Core/NES/BaseNesPpu.h/cpp                # PPU base class
Core/NES/NesConsole.h/cpp                # System coordination

Key Line References:
  NesPpu.cpp:1249  - BeginVBlank()
  NesPpu.cpp:1254  - TriggerNmi()
  NesPpu.cpp:959   - ProcessSpriteEvaluationStart()
  NesPpu.cpp:1004  - ProcessSpriteEvaluation()
  NesPpu.cpp:504   - SpriteDMA register handling
```

---

### Research Notes - Things to Watch For

#### Patterns That Could Address RAMBO Issues

**VBlank/NMI (10 failing tests):**
- ⚠️ Look for: NMI edge detection mechanism
- ⚠️ Look for: $2002 read timing handling
- ⚠️ Look for: Multiple NMI prevention
- ⚠️ Look for: VBlank flag clear timing
- ⚠️ Look for: Race condition at scanline 241 dot 1

**OAM/DMC DMA (failing tests):**
- ⚠️ Look for: DMC priority handling
- ⚠️ Look for: OAM pause/resume mechanism
- ⚠️ Look for: Byte duplication edge cases
- ⚠️ Look for: Alignment cycle tracking
- ⚠️ Look for: Time-sharing pattern

**PPU Mid-Frame Changes (SMB3, Kirby issues):**
- ⚠️ Look for: PPUCTRL mid-scanline handling
- ⚠️ Look for: PPUMASK 3-4 dot delay
- ⚠️ Look for: Fine X scroll edge cases
- ⚠️ Look for: Register update propagation

#### Anti-Patterns to Avoid

**Don't Blindly Copy:**
- ❌ C++ patterns don't translate directly to Zig
- ❌ Performance tradeoffs may differ
- ❌ Mesen2 handles multiple systems (different constraints)

**Maintain RAMBO Principles:**
- ✅ Hardware accuracy first
- ✅ Readability over cleverness
- ✅ Testability (pure functions)
- ✅ RT-safety (zero heap allocations in hot path)
- ✅ Zig idioms (comptime, no hidden control flow)

---

### Success Criteria - How to Know Research is Complete

**Minimum Requirements:**

1. ✅ **VBlank/NMI pattern fully documented** from Mesen2
2. ✅ **DMA pattern fully documented** from Mesen2
3. ✅ **Concrete recommendations** for fixing 12 failing tests
4. ✅ **Comparison document** with tradeoffs analyzed
5. ✅ **Follow-up tasks** prioritized and scoped

**Bonus (if time permits):**

6. ⭐ **PPU modularity insights** for long-term refactoring
7. ⭐ **State management patterns** evaluation
8. ⭐ **Testing strategy** comparison
9. ⭐ **Performance analysis** (if measurable differences found)

**Research Complete When:**
- Clear understanding of why Mesen2's patterns work
- Specific actionable improvements for RAMBO identified
- Confidence that proposed changes will fix failing tests
- Documentation sufficient for implementation phase

---

**END OF CONTEXT MANIFEST**

## User Notes
<!-- Any specific notes or requirements from the developer -->

## Work Log
<!-- Updated as work progresses -->
- [YYYY-MM-DD] Started task, initial research
