# RAMBO Code Review Remediation Plan

**Date Created:** 2025-10-11
**Baseline Test Status:** 949/986 tests passing (96.2%)
**Goal:** Systematically eliminate all legacy code, finalize architectural migrations, and ensure 100% consistency across the codebase

---

## Executive Summary

This plan addresses all issues identified in the comprehensive code review audit completed on 2025-10-11. The work is organized into 7 major phases, each designed to be independently testable and non-regressive. All changes will maintain or improve the current test passing rate of 949/986 tests.

**Key Findings from Audit:**
1. ✅ **CPU Module**: Excellent - only minor cleanup needed
2. ✅ **PPU Module**: Very good - final migration cleanups required
3. ✅ **Emulation Core**: Excellent - minor consolidation opportunities
4. ⚠️ **APU Module**: Needs refactoring to State/Logic separation pattern
5. ⚠️ **Cartridge System**: Dual systems exist - legacy must be removed
6. ⚠️ **Config System**: Overly complex - needs consolidation
7. ⚠️ **Documentation**: Outdated architecture docs need updating
8. ⚠️ **Testing**: Fragmented harnesses need unification

---

## Phase 1: Legacy Code Removal ✅ COMPLETE

**Status:** COMPLETED 2025-10-11 (commit c713862)
**Objective:** Remove confirmed dead code and legacy artifacts
**Risk Level:** LOW (no functionality changes)
**Actual Time:** 4 hours
**Test Results:** 914/951 tests passing (96.11% vs 96.15% baseline - no regression)

### 1.1 Remove Legacy iNES Parser

**Files to Delete:**
- `src/cartridge/ines.zig` (obsolete, replaced by `src/cartridge/ines/mod.zig`)
- `tests/ines/ines_test.zig` (tests the obsolete parser)

**Files to Update:**
```zig
// src/ppu/logic/memory.zig (line ~1)
// OLD: const Mirroring = @import("../../cartridge/ines.zig").Mirroring;
// NEW: const Mirroring = @import("../../cartridge/ines/mod.zig").Mirroring;

// src/ppu/State.zig (line ~1)
// OLD: const Mirroring = @import("../cartridge/ines.zig").Mirroring;
// NEW: const Mirroring = @import("../cartridge/ines/mod.zig").Mirroring;

// src/snapshot/state.zig (line ~1)
// OLD: const Mirroring = @import("../cartridge/ines.zig").Mirroring;
// NEW: const Mirroring = @import("../cartridge/ines/mod.zig").Mirroring;

// src/test/Harness.zig (line ~1)
// OLD: const MirroringType = @import("../cartridge/ines.zig").Mirroring;
// NEW: const MirroringType = @import("../cartridge/ines/mod.zig").Mirroring;

// src/cartridge/Cartridge.zig (line ~1)
// Update import to use new ines module
```

**Verification:**
```bash
zig build test  # Must pass 949/986 tests
grep -r "cartridge/ines.zig" src/ tests/  # Should return 0 results
```

**Questions/Risks:**
- ⚠️ Verify that `src/cartridge/ines/mod.zig` exports the same `Mirroring` type
- ⚠️ Check if any external tools depend on the old parser format

### 1.2 Remove Legacy CPU Functions

**Files to Update:**
```zig
// src/cpu/Logic.zig
// DELETE: pub fn reset(cpu: *CpuState, reset_vector: u16) void { ... }
// This function is explicitly marked as "not used in new architecture"
```

**Verification:**
```bash
grep -r "CpuLogic.reset" src/ tests/  # Should return 0 results
zig build test-unit  # CPU tests must pass
```

### 1.3 Remove Deprecated EmulationState Test Helpers

**Files to Update:**
```zig
// src/emulation/State.zig
// DELETE: pub fn syncDerivedSignals(self: *EmulationState) void { ... }
// DELETE: pub fn testSetVBlank(self: *EmulationState) void { ... }
// DELETE: pub fn testClearVBlank(self: *EmulationState) void { ... }
```

**Tests to Update:**
- Search for usages: `grep -r "testSetVBlank\|testClearVBlank\|syncDerivedSignals" tests/`
- Replace with direct VBlankLedger API calls: `state.vblank_ledger.recordVBlankSet(...)`

**Verification:**
```bash
zig build test  # Must maintain 949/986 passing
```

### 1.4 Remove Legacy PPU State Fields

**Files to Update:**
```zig
// src/ppu/State.zig
// In PpuStatus packed struct:
// DELETE: _reserved: bool = false,  // Bit 7 - was VBlank flag (now in VBlankLedger)
```

**Verification:**
```bash
zig build test-unit  # PPU tests must pass
```

---

## Phase 2: Configuration System Simplification (Medium Risk) 📋 NEXT

**Status:** READY TO START
**Objective:** Consolidate fragmented config files into single types file
**Risk Level:** MEDIUM (structural changes, parser modification)
**Estimated Time:** 3-4 hours
**Test Impact:** Should maintain test count (config tests exist)
**Prerequisites:** Phase 1 complete ✅

### 2.1 Consolidate Type Definitions

**Action:** Merge all type definitions into single file

**Files to Consolidate:**
```
src/config/types/hardware.zig  \
src/config/types/ppu.zig        } → src/config/types.zig (replace existing)
src/config/types/settings.zig  /
```

**New `src/config/types.zig` Structure:**
```zig
//! Configuration Type Definitions
//! All configuration structs in one place for clarity

// Hardware Configuration
pub const HardwareConfig = struct { ... };  // from hardware.zig
pub const CpuModel = struct { ... };        // from hardware.zig

// PPU Configuration
pub const PpuVariant = enum { ... };        // from ppu.zig

// Settings
pub const EmulationSettings = struct { ... }; // from settings.zig

// Root Config
pub const Config = struct {
    hardware: HardwareConfig,
    ppu: PpuVariant,
    settings: EmulationSettings,
};
```

**Files to Delete:**
- `src/config/types/hardware.zig`
- `src/config/types/ppu.zig`
- `src/config/types/settings.zig`
- `src/config/types.zig` (old re-export file)

**Files to Update:**
```zig
// src/config/Config.zig
// Update import: const types = @import("types.zig");
```

### 2.2 Simplify Parser

**Action:** Remove `Config.copyFrom()` method and make parser populate directly

**Files to Update:**
```zig
// src/config/Config.zig
// DELETE: pub fn copyFrom(self: *Config, other: Config) void { ... }
// DELETE: pub fn get(self: *const Config) Config { ... }
```

```zig
// src/config/parser.zig
// REFACTOR: parseKdl function signature
// OLD: pub fn parseKdl(allocator: Allocator, source: []const u8) !Config
// NEW: pub fn parseKdl(config: *Config, source: []const u8) !void

// Update function body to populate config directly instead of creating and returning
```

### 2.3 Update rambo.kdl

**Decision Point:** The config file contains `unstable_opcodes` section that is no longer in code

**Option A (RECOMMENDED):** Remove from `rambo.kdl`
```kdl
// DELETE unstable_opcodes section entirely
// Rationale: CPU behavior moved to variants.zig, config shouldn't control this
```

**Option B:** Re-add to `CpuModel` struct
```zig
// Only if user explicitly wants this level of config control
pub const CpuModel = struct {
    unstable_opcodes: struct {
        sha_behavior: enum { ... },
        lxa_magic: u8,
    },
};
```

**Verification:**
```bash
zig build test  # Config tests must pass
# Manually test: zig build run to ensure config loads correctly
```

**Questions/Risks:**
- ❓ Does the user want to keep unstable opcode configuration in the config file?
- ⚠️ Parser refactoring is most complex part - needs careful testing

---

## Phase 3: Cartridge System Cleanup (Medium-High Risk)

**Objective:** Fully migrate to new generic cartridge system, remove legacy loader
**Risk Level:** MEDIUM-HIGH (affects main.zig and test infrastructure)
**Estimated Time:** 4-5 hours
**Test Impact:** May temporarily break some integration tests, but should recover

### 3.1 Analyze Current Cartridge Usage

**Discovery Phase:**
```bash
# Find all cartridge loading patterns
grep -r "Cartridge.load\|loader.loadCartridgeFile" src/ tests/

# Find all AnyCartridge usage
grep -r "AnyCartridge" src/ tests/

# Find tests still using old system
find tests/ -name "*.zig" -exec grep -l "ines.zig" {} \;
```

### 3.2 Update main.zig

**Current Issue:** Unknown - need to inspect `main.zig` cartridge loading

**Action:** Ensure main.zig uses new system
```zig
// src/main.zig
const AnyCartridge = @import("cartridge/mappers/registry.zig").AnyCartridge;

// Loading should use:
const cart = try AnyCartridge.loadFromFile(allocator, rom_path);
```

### 3.3 Migrate Integration Tests

**Tests to Update:**
- `tests/cartridge/*.zig` - Already mostly migrated, verify all use new system
- `tests/integration/accuracycoin_execution_test.zig` - Appears to use new system
- `tests/integration/commercial_rom_test.zig` - Check if uses old patterns

**Standard Pattern:**
```zig
// In all integration tests
const AnyCartridge = @import("../../src/cartridge/mappers/registry.zig").AnyCartridge;
const cart = try AnyCartridge.loadFromFile(allocator, "path/to/rom.nes");
```

### 3.4 Evaluate loader.zig

**Decision Point:** Is `loader.zig` legacy or part of new system?

**Analysis Needed:**
- Check if `Cartridge.zig` depends on `loader.zig`
- If yes: Keep as internal helper, ensure it only uses new iNES parser
- If no: Delete and inline logic into `Cartridge.zig`

**Files to Potentially Delete:**
- `src/cartridge/loader.zig` (if logic is moved to Cartridge.zig)

### 3.5 Clean Up root.zig Exports

**Files to Update:**
```zig
// src/root.zig
// REMOVE: pub const iNES = @import("cartridge/ines/mod.zig");  // Old export
// KEEP: pub const AnyCartridge = @import("cartridge/mappers/registry.zig").AnyCartridge;
```

**Verification:**
```bash
zig build test  # Must pass integration tests
zig build run -- path/to/test/rom.nes  # Manual smoke test
```

**Questions/Risks:**
- ❓ What is the current state of main.zig cartridge loading?
- ❓ Should loader.zig be kept as internal helper or merged into Cartridge.zig?
- ⚠️ HIGH RISK: This affects ROM loading, which is critical path

---

## Phase 4: PPU Module Finalization (Low-Medium Risk)

**Objective:** Remove PPU facade layer, finalize state cleanup
**Risk Level:** LOW-MEDIUM (affects emulation coordination)
**Estimated Time:** 2-3 hours
**Test Impact:** Should maintain all tests

### 4.1 Remove Ppu.zig Facade

**Files to Delete:**
- `src/emulation/Ppu.zig` (redundant facade)

**Files to Update:**
```zig
// src/emulation/State.zig - stepPpuCycle() function

// Move TickFlags definition to:
// src/ppu/State.zig or src/ppu/types.zig (new file)
pub const TickFlags = struct {
    frame_complete: bool = false,
    rendering_enabled: bool,
    nmi_signal: bool = false,
    vblank_clear: bool = false,
};

// Update stepPpuCycle to call PpuLogic.tick() directly:
// OLD: const flags = PpuRuntime.tick(...)
// NEW: const flags = PpuLogic.tick(...)
```

### 4.2 Move ppu_a12_state to PpuState

**Rationale:** MMC3 IRQ timing is PPU address bus behavior, belongs in PPU state

**Files to Update:**
```zig
// src/ppu/State.zig
pub const PpuState = struct {
    // ... existing fields ...

    /// A12 line state for MMC3 IRQ timing
    /// Tracks rising edge of PPU address bus bit 12
    a12_state: bool = false,
};

// src/emulation/State.zig
// DELETE: ppu_a12_state: bool = false,

// Update all references to ppu_a12_state:
// OLD: self.ppu_a12_state
// NEW: self.ppu.a12_state
```

**Verification:**
```bash
zig build test  # PPU and integration tests must pass
```

---

## Phase 5: APU State/Logic Separation Refactoring (HIGH RISK)

**Objective:** Refactor APU to match CPU's pure State/Logic pattern
**Risk Level:** HIGH (major architectural change, extensive testing required)
**Estimated Time:** 12-16 hours (expanded to 4 sub-phases)
**Test Impact:** All 135 APU tests will need updates

**🔴 CRITICAL: This phase uses SUB-PHASES to reduce risk**

Each sub-phase is independently testable and can be committed separately.
If issues arise, we can pause and reassess before continuing.

---

### Sub-Phase 5A: Design and Infrastructure (2-3 hours)

**Objective:** Create type definitions and plan migration without breaking existing code

### 5A.1 Design Phase - Define Result Structs

**New Structures Needed:**
```zig
// src/apu/logic/types.zig (new file)

/// Result of DMC tick operation
pub const DmcTickResult = struct {
    trigger_dma: bool,
    timer: u16,
    output: u8,
    silence_flag: bool,
    shift_register: u8,
    bits_remaining: u8,
    sample_buffer_empty: bool,
    // ... all state changes
};

/// Result of Envelope clock operation
pub const EnvelopeClockResult = struct {
    divider: u8,
    decay_level: u8,
    start_flag: bool,
};

/// Result of Sweep clock operation
pub const SweepClockResult = struct {
    reload_flag: bool,
    divider: u8,
    target_period: u16,
    muting: bool,
};

/// Complete APU tick result (aggregates all channels)
pub const ApuTickResult = struct {
    dmc: DmcTickResult,
    pulse1_envelope: ?EnvelopeClockResult,
    pulse2_envelope: ?EnvelopeClockResult,
    noise_envelope: ?EnvelopeClockResult,
    pulse1_sweep: ?SweepClockResult,
    pulse2_sweep: ?SweepClockResult,
    frame_counter_changes: FrameCounterResult,
    trigger_dmc_dma: bool,
};
```

### 5A.2 Create Migration Plan Document

**Action:** Document the refactoring approach before starting

**New File:** `docs/apu-migration-plan.md`
**Content:**
- Current architecture analysis
- Target architecture diagram
- Step-by-step migration sequence
- Rollback procedures

**Verification:**
```bash
# Design phase complete when:
# 1. All result struct types defined
# 2. Migration plan documented
# 3. No code changes yet - this is planning only
git status  # Should show only new docs/apu-migration-plan.md
```

---

### Sub-Phase 5B: Envelope and Sweep Refactoring (3-4 hours)

**Objective:** Refactor shared components (Envelope, Sweep) to pure logic
**Risk:** MEDIUM-HIGH (affects all channels that use envelopes/sweeps)

### 5B.1 Refactor Envelope to Pure Logic

**Action:** Convert `Envelope.zig` to pure `logic/envelope.zig`

**Files to Create:**
```zig
// src/apu/logic/envelope.zig (NEW)
pub fn clock(envelope: *const Envelope, halt: bool, reload: u8) EnvelopeClockResult {
    var result = EnvelopeClockResult{
        .divider = envelope.divider,
        .decay_level = envelope.decay_level,
        .start_flag = envelope.start_flag,
    };

    if (result.start_flag) {
        result.decay_level = 15;
        result.divider = reload;
        result.start_flag = false;
    } else if (result.divider > 0) {
        result.divider -= 1;
    } else {
        result.divider = reload;
        if (result.decay_level > 0) {
            result.decay_level -= 1;
        } else if (halt) {
            result.decay_level = 15;  // Loop
        }
    }

    return result;
}
```

### 5B.2 Refactor Sweep to Pure Logic

**Action:** Convert `Sweep.zig` to pure `logic/sweep.zig`

**Files to Create:**
```zig
// src/apu/logic/sweep.zig (NEW)
pub fn clock(sweep: *const Sweep, current_period: u16, negate_mode: bool) SweepClockResult {
    var result = SweepClockResult{
        .reload_flag = sweep.reload_flag,
        .divider = sweep.divider,
        .target_period = sweep.target_period,
        .muting = sweep.muting,
    };

    // Calculate target period
    const change = current_period >> sweep.shift_count;
    result.target_period = if (negate_mode)
        current_period -% change
    else
        current_period +% change;

    // Update muting flag
    result.muting = (current_period < 8) or (result.target_period > 0x7FF);

    // Clock divider
    if (result.reload_flag) {
        result.divider = sweep.period;
        result.reload_flag = false;
    } else if (result.divider > 0) {
        result.divider -= 1;
    } else {
        result.divider = sweep.period;
        // Sweep would trigger here (returned to caller)
    }

    return result;
}
```

### 5B.3 Update Tests for Envelope and Sweep

**Action:** Update existing tests to use new pure functions

**Test Pattern:**
```zig
test "Envelope: start flag sets decay to 15" {
    const env = Envelope{ .start_flag = true, .decay_level = 5, .divider = 0 };
    const result = envelope_logic.clock(&env, false, 10);

    try testing.expectEqual(@as(u8, 15), result.decay_level);
    try testing.expect(!result.start_flag);
}
```

**Verification:**
```bash
zig build test-unit  # Envelope/Sweep tests must pass
# Don't delete old files yet - keep for comparison
```

**Files to Keep (for now):**
- `src/apu/Envelope.zig` - Keep until Sub-Phase 5D
- `src/apu/Sweep.zig` - Keep until Sub-Phase 5D

---

### Sub-Phase 5C: DMC and Channel Logic (4-5 hours)

**Objective:** Refactor DMC and create new channel logic modules
**Risk:** HIGH (DMC is complex, channels are new code)

### 5C.1 Refactor DMC to Pure Logic

**Action:** Convert `Dmc.zig` to pure `logic/dmc.zig`

**Files to Create:**
```zig
// src/apu/logic/dmc.zig (NEW)
pub fn tick(apu: *const ApuState) DmcTickResult {
    if (!apu.dmc_enabled) {
        return .{ .trigger_dma = false, .timer = apu.dmc_timer, /* ... */ };
    }

    var result = DmcTickResult{
        .trigger_dma = false,
        .timer = apu.dmc_timer,
        .output = apu.dmc_output,
        .silence_flag = apu.dmc_silence_flag,
        .shift_register = apu.dmc_shift_register,
        .bits_remaining = apu.dmc_bits_remaining,
        .sample_buffer_empty = apu.dmc_sample_buffer_empty,
    };

    // Timer countdown
    if (result.timer > 0) {
        result.timer -= 1;
    } else {
        result.timer = apu.dmc_timer_period;
        result = clockOutputUnit(result, apu);  // Helper function
    }

    return result;
}

fn clockOutputUnit(result: DmcTickResult, apu: *const ApuState) DmcTickResult {
    var new_result = result;

    if (!new_result.silence_flag) {
        const bit = new_result.shift_register & 0x01;
        new_result.shift_register >>= 1;
        new_result.bits_remaining -= 1;

        // Update output level
        if (bit == 1 and new_result.output <= 125) {
            new_result.output += 2;
        } else if (bit == 0 and new_result.output >= 2) {
            new_result.output -= 2;
        }

        // Check if sample complete
        if (new_result.bits_remaining == 0) {
            new_result.bits_remaining = 8;
            if (new_result.sample_buffer_empty) {
                new_result.silence_flag = true;
            } else {
                new_result.shift_register = apu.dmc_sample_buffer;
                new_result.sample_buffer_empty = true;
                new_result.trigger_dma = true;  // Need new sample
            }
        }
    }

    return new_result;
}
```

### 5C.2 Create Channel Logic Modules

**Action:** Create new pure logic for Pulse, Triangle, Noise channels

**Files to Create:**
```zig
// src/apu/logic/pulse.zig (NEW)
pub fn tick(apu: *const ApuState, channel_num: u1) PulseTickResult {
    // channel_num: 0=pulse1, 1=pulse2
    const sweep = if (channel_num == 0) &apu.pulse1_sweep else &apu.pulse2_sweep;
    const envelope = if (channel_num == 0) &apu.pulse1_envelope else &apu.pulse2_envelope;

    // Pure function - calculates pulse output based on current state
    // Returns: output level (0-15), timer updates, etc.
}

// src/apu/logic/triangle.zig (NEW)
pub fn tick(apu: *const ApuState) TriangleTickResult {
    // Linear counter logic, triangle sequencer
    // Pure function - no state mutation
}

// src/apu/logic/noise.zig (NEW)
pub fn tick(apu: *const ApuState) NoiseTickResult {
    // LFSR logic, envelope integration
    // Pure function - no state mutation
}
```

### 5C.3 Update Tests for DMC and Channels

**Verification:**
```bash
zig build test-unit  # DMC and channel tests must pass
# Still keeping old files for comparison
```

---

### Sub-Phase 5D: Integration and Cleanup (3-4 hours)

**Objective:** Integrate all new logic into `ApuLogic.zig`, update EmulationState, remove old files
**Risk:** MEDIUM (integration complexity, test updates)

### 5D.1 Consolidate All Logic in ApuLogic.zig

**Action:** Create unified `ApuLogic.tick()` orchestrator

**Files to Update:**
```zig
// src/apu/Logic.zig (MAJOR UPDATE)
const dmc_logic = @import("logic/dmc.zig");
const envelope_logic = @import("logic/envelope.zig");
const sweep_logic = @import("logic/sweep.zig");
const pulse_logic = @import("logic/pulse.zig");
const triangle_logic = @import("logic/triangle.zig");
const noise_logic = @import("logic/noise.zig");
const frame_counter = @import("logic/frame_counter.zig");
const registers = @import("logic/registers.zig");

/// Main APU tick function - orchestrates all channels
/// Pure function - takes const state, returns complete result struct
pub fn tick(apu: *const ApuState) ApuTickResult {
    var result = ApuTickResult{
        .dmc = dmc_logic.tick(apu),
        .frame_counter_changes = frame_counter.tick(apu),
        .pulse1 = pulse_logic.tick(apu, 0),
        .pulse2 = pulse_logic.tick(apu, 1),
        .triangle = triangle_logic.tick(apu),
        .noise = noise_logic.tick(apu),
        .pulse1_envelope = null,
        .pulse2_envelope = null,
        .noise_envelope = null,
        .pulse1_sweep = null,
        .pulse2_sweep = null,
        .trigger_dmc_dma = false,
    };

    // Quarter frame: Clock envelopes and linear counter
    if (result.frame_counter_changes.quarter_frame) {
        result.pulse1_envelope = envelope_logic.clock(&apu.pulse1_envelope, apu.pulse1_halt, apu.pulse1_envelope_reload);
        result.pulse2_envelope = envelope_logic.clock(&apu.pulse2_envelope, apu.pulse2_halt, apu.pulse2_envelope_reload);
        result.noise_envelope = envelope_logic.clock(&apu.noise_envelope, apu.noise_halt, apu.noise_envelope_reload);
    }

    // Half frame: Clock length counters and sweeps
    if (result.frame_counter_changes.half_frame) {
        result.pulse1_sweep = sweep_logic.clock(&apu.pulse1_sweep, apu.pulse1_period, false);  // Pulse 1: subtract mode
        result.pulse2_sweep = sweep_logic.clock(&apu.pulse2_sweep, apu.pulse2_period, true);   // Pulse 2: add mode
    }

    result.trigger_dmc_dma = result.dmc.trigger_dma;

    return result;
}
```

### 5D.2 Update EmulationState Integration

**Action:** Modify `stepApuCycle()` to use new pure logic

**Files to Update:**
```zig
// src/emulation/State.zig - stepApuCycle()
pub fn stepApuCycle(self: *EmulationState) void {
    // Call pure APU logic (NO state mutation in tick())
    const result = ApuLogic.tick(&self.apu);

    // Apply ALL state changes from result
    self.apu.dmc_timer = result.dmc.timer;
    self.apu.dmc_output = result.dmc.output;
    self.apu.dmc_silence_flag = result.dmc.silence_flag;
    self.apu.dmc_shift_register = result.dmc.shift_register;
    self.apu.dmc_bits_remaining = result.dmc.bits_remaining;
    self.apu.dmc_sample_buffer_empty = result.dmc.sample_buffer_empty;

    // Apply envelope updates (if quarter frame occurred)
    if (result.pulse1_envelope) |env| {
        self.apu.pulse1_envelope.divider = env.divider;
        self.apu.pulse1_envelope.decay_level = env.decay_level;
        self.apu.pulse1_envelope.start_flag = env.start_flag;
    }
    if (result.pulse2_envelope) |env| {
        self.apu.pulse2_envelope.divider = env.divider;
        self.apu.pulse2_envelope.decay_level = env.decay_level;
        self.apu.pulse2_envelope.start_flag = env.start_flag;
    }
    if (result.noise_envelope) |env| {
        self.apu.noise_envelope.divider = env.divider;
        self.apu.noise_envelope.decay_level = env.decay_level;
        self.apu.noise_envelope.start_flag = env.start_flag;
    }

    // Apply sweep updates (if half frame occurred)
    if (result.pulse1_sweep) |swp| {
        self.apu.pulse1_sweep.reload_flag = swp.reload_flag;
        self.apu.pulse1_sweep.divider = swp.divider;
        self.apu.pulse1_sweep.target_period = swp.target_period;
        self.apu.pulse1_sweep.muting = swp.muting;
    }
    if (result.pulse2_sweep) |swp| {
        self.apu.pulse2_sweep.reload_flag = swp.reload_flag;
        self.apu.pulse2_sweep.divider = swp.divider;
        self.apu.pulse2_sweep.target_period = swp.target_period;
        self.apu.pulse2_sweep.muting = swp.muting;
    }

    // Apply channel outputs
    self.apu.pulse1_output = result.pulse1.output;
    self.apu.pulse2_output = result.pulse2.output;
    self.apu.triangle_output = result.triangle.output;
    self.apu.noise_output = result.noise.output;

    // Handle DMA trigger
    if (result.trigger_dmc_dma) {
        self.triggerDmcDma();  // Existing DMA logic
    }
}
```

### 5D.3 Delete Old Implementation Files

**Action:** Remove legacy APU files after integration complete

**Files to DELETE:**
- `src/apu/Dmc.zig`
- `src/apu/Envelope.zig`
- `src/apu/Sweep.zig`

### 5D.4 Update All APU Tests

**Action:** Refactor all 135 APU tests to use new pure API

**Tests to Update:**
- `tests/apu/apu_test.zig` - All APU integration tests
- `tests/apu/frame_counter_test.zig` - Frame counter logic tests
- `tests/apu/*.zig` - Any channel-specific tests

**New Test Pattern:**
```zig
test "APU: DMC timer countdown" {
    const apu = ApuState{
        .dmc_enabled = true,
        .dmc_timer = 5,
        .dmc_timer_period = 428,
        // ... other required fields
    };

    const result = ApuLogic.tick(&apu);

    // Verify pure function output
    try testing.expectEqual(@as(u16, 4), result.dmc.timer);
    try testing.expect(!result.trigger_dmc_dma);
}

test "APU: Envelope start flag resets decay" {
    const apu = ApuState{
        .pulse1_envelope = .{ .start_flag = true, .decay_level = 5, .divider = 0 },
        .pulse1_halt = false,
        .pulse1_envelope_reload = 10,
        // ...
    };

    const result = ApuLogic.tick(&apu);

    // Note: envelope only updated on quarter frame
    // This test would need to trigger quarter frame event
}
```

**Verification:**
```bash
zig build test-unit  # All 135 APU tests must pass
zig build test       # Full suite must maintain 949/986
```

**Sub-Phase 5D Complete When:**
- ✅ All old APU files deleted
- ✅ All 135 APU tests passing
- ✅ No regressions in other tests
- ✅ EmulationState properly integrates new logic
- ✅ Git commit created: "refactor(apu): Complete State/Logic separation"

---

### Phase 5 Architecture Constraints (CRITICAL)

**RT-Safety Verification:**
```bash
# Verify NO allocations in APU logic
grep -r "allocator\|alloc\|ArrayList" src/apu/logic/
# Should return ZERO results

# Verify pure functions (const state parameters)
grep -r "pub fn.*apu.*\*ApuState" src/apu/logic/
# Should return ZERO results (all should be *const ApuState)
```

**Thread Safety Verification:**
- ✅ All APU logic functions are pure (no shared mutable state)
- ✅ Only EmulationState.stepApuCycle() mutates APU state
- ✅ Single call site from emulation loop (no race conditions)
- ✅ No locks/mutexes needed (single-threaded access guaranteed)

**Side Effect Isolation:**
- ✅ All side effects (DMA triggers, IRQ flags) returned via result struct
- ✅ EmulationState applies side effects explicitly
- ✅ No hidden state updates in APU logic

**Memory Model:**
- ✅ No heap allocations in APU logic hot path
- ✅ All result structs are stack-allocated
- ✅ Optional fields use `?Type` for selective updates

---

### Phase 5 Summary

**Total Estimated Time:** 12-16 hours across 4 sub-phases

| Sub-Phase | Time | Risk | Deliverable |
|-----------|------|------|-------------|
| 5A: Design | 2-3h | LOW | Type definitions, migration plan |
| 5B: Envelope/Sweep | 3-4h | MEDIUM-HIGH | Pure envelope/sweep logic + tests |
| 5C: DMC/Channels | 4-5h | HIGH | Pure DMC + channel logic |
| 5D: Integration | 3-4h | MEDIUM | Unified ApuLogic + test updates |

**Pause Points:**
- After 5A: Review design before code changes
- After 5B: Verify envelope/sweep refactoring works before continuing
- After 5C: Verify DMC and channels work before integration
- After 5D: Full validation before moving to Phase 6

---

## Phase 6: Emulation Core Consolidation (Low Risk)

**Objective:** Consolidate fragmented state definitions, clarify reset behavior
**Risk Level:** LOW (mostly file reorganization)
**Estimated Time:** 2-3 hours
**Test Impact:** Should maintain all tests

### 6.1 Consolidate State Definitions

**Action:** Move small state structs into EmulationState.zig

**Files to Consolidate:**
```zig
// Move these into src/emulation/State.zig as nested structs:
src/emulation/state/BusState.zig      → EmulationState.BusState
src/emulation/state/OamDma.zig        → EmulationState.OamDmaState
src/emulation/state/DmcDma.zig        → EmulationState.DmcDmaState
src/emulation/state/ControllerState.zig → EmulationState.ControllerState

// Move timing helpers:
src/emulation/state/Timing.zig → src/emulation/MasterClock.zig
```

**New Structure:**
```zig
// src/emulation/State.zig
pub const EmulationState = struct {
    // ... existing fields ...

    /// Bus state (internal definition)
    pub const BusState = struct { /* from BusState.zig */ };

    /// OAM DMA state (internal definition)
    pub const OamDmaState = struct { /* from OamDma.zig */ };

    /// DMC DMA state (internal definition)
    pub const DmcDmaState = struct { /* from DmcDma.zig */ };

    /// Controller state (internal definition)
    pub const ControllerState = struct { /* from ControllerState.zig */ };
};
```

**Files to Delete:**
- `src/emulation/state/BusState.zig`
- `src/emulation/state/OamDma.zig`
- `src/emulation/state/DmcDma.zig`
- `src/emulation/state/ControllerState.zig`
- `src/emulation/state/Timing.zig`

### 6.2 Move Test Helpers to Test Harness

**Action:** Relocate high-level test orchestration out of production code

**Files to Update:**
```zig
// src/test/Harness.zig - Add these methods:
pub fn tickCpuWithClock(harness: *TestHarness, cycles: u32) void { ... }
pub fn emulateFrame(harness: *TestHarness) void { ... }
pub fn emulateCpuCycles(harness: *TestHarness, cycles: u32) void { ... }

// src/emulation/State.zig - DELETE these methods
// src/emulation/helpers.zig - DELETE entire file if only contains test helpers
```

### 6.3 Clarify reset() vs power_on()

**Files to Update:**
```zig
// src/emulation/State.zig

/// Reset the emulator (RESET button pressed)
/// Does NOT include PPU warm-up period
pub fn reset(self: *EmulationState) void {
    self._internal_reset();
    // Reset does not set warmup_complete flag
}

/// Power-on initialization (cold start)
/// Includes PPU warm-up period where registers are ignored
pub fn power_on(self: *EmulationState) void {
    self._internal_reset();
    self.ppu.warmup_complete = false;  // Trigger warm-up
}

/// Shared reset logic
fn _internal_reset(self: *EmulationState) void {
    // Common reset logic
}
```

**Verification:**
```bash
zig build test  # Must maintain 949/986 tests
```

---

## Phase 7: Documentation Updates (Low Risk)

**Objective:** Archive obsolete docs, update architecture diagram, create central ARCHITECTURE.md
**Risk Level:** MINIMAL (documentation only)
**Estimated Time:** 3-4 hours
**Test Impact:** No test impact

### 7.1 Archive Obsolete Documentation

**Action:** Move outdated design docs to archive

**Files to Move:**
```bash
mkdir -p docs/archive/pre-refactor-2025-10

# Move obsolete documents:
mv docs/implementation/INES-MODULE-PLAN.md docs/archive/pre-refactor-2025-10/
mv docs/implementation/MAPPER-SYSTEM-PLAN.md docs/archive/pre-refactor-2025-10/
mv docs/refactoring/* docs/archive/pre-refactor-2025-10/ (if exists)

# Create archive README:
cat > docs/archive/pre-refactor-2025-10/README.md << 'EOF'
# Pre-Refactor Documentation Archive

This directory contains documentation from before the 2025-10 architectural
refactoring. These documents describe the OLD architecture and are kept for
historical reference only.

**DO NOT USE THESE DOCUMENTS** as a guide for the current codebase.
See `docs/ARCHITECTURE.md` for current system design.

Archived: 2025-10-11
EOF
```

### 7.2 Update Architecture Diagram

**Files to Update:**
```dot
// docs/dot/architecture.dot

// Key changes:
// 1. Update cartridge section to show AnyCartridge tagged union
subgraph cluster_cartridge {
    label="Cartridge System\n(Comptime Generics)";

    any_cart [label="AnyCartridge\n(Tagged Union)", shape=diamond];
    mapper0 [label="Mapper0\n(NROM)", fillcolor=lightblue];
    // Future mappers...

    any_cart -> mapper0 [label="runtime dispatch"];
}

// 2. Simplify EmulationState ownership diagram
emu_state [label="EmulationState\n(Direct Owner of All State)", shape=box3d];
emu_state -> cpu_state [label="owns"];
emu_state -> ppu_state [label="owns"];
emu_state -> apu_state [label="owns"];
emu_state -> any_cart [label="owns"];

// 3. Remove complex interconnection web
// Show that all interactions go through EmulationState.tick()

// 4. Update mailbox count (7 active, not 9)
// Already done in current version

// 5. Add source file labels
cpu_state [label="CpuState\n(src/cpu/State.zig)"];
ppu_state [label="PpuState\n(src/ppu/State.zig)"];
// ... etc
```

**Regenerate PNG:**
```bash
cd docs/dot
dot -Tpng architecture.dot -o architecture.png
```

### 7.3 Create Central ARCHITECTURE.md

**New File:** `docs/ARCHITECTURE.md`

**Content:**
```markdown
# RAMBO Architecture

**Last Updated:** 2025-10-11
**Version:** 0.2.0-alpha

## Overview

RAMBO uses a 3-thread mailbox architecture with strict real-time safety in the
emulation core. All components follow a pure State/Logic separation pattern for
deterministic execution and testability.

## Thread Model

[Embedded architecture.png diagram]

### Main Thread (Coordinator)
- Minimal work
- Routes events between Emulation and Render threads
- Handles CLI, configuration, and lifecycle

### Emulation Thread (RT-Safe)
- Cycle-accurate CPU/PPU/APU emulation
- Zero heap allocations in hot path
- Produces RGBA frames at NES native rate (~60 FPS)

### Render Thread (Wayland + Vulkan)
- Consumes frames from FrameMailbox
- Handles window management and GPU rendering
- Independent frame rate (vsync)

## Core Patterns

### State/Logic Separation

All major components split into two modules:

**State Module** (`State.zig`):
- Pure data structures
- Zero hidden state
- Fully serializable
- Optional convenience methods that delegate to Logic

**Logic Module** (`Logic.zig`):
- Pure functions
- No global state
- All side effects explicit via parameters
- Deterministic execution

Example:
```zig
// CPU State
pub const CpuState = struct {
    a: u8, x: u8, y: u8, sp: u8, pc: u16,
    // Convenience delegation
    pub fn tick(self: *CpuState, bus: *BusState) void {
        Logic.tick(self, bus);
    }
};

// CPU Logic
pub fn tick(cpu: *CpuState, bus: *BusState) void {
    // Pure function - all state passed explicitly
}
```

### Comptime Polymorphism

All polymorphism uses comptime duck typing for zero runtime overhead:

```zig
pub fn Cartridge(comptime MapperType: type) type {
    return struct {
        mapper: MapperType,

        // Direct delegation - fully inlined
        pub fn cpuRead(self: *const Self, address: u16) u8 {
            return self.mapper.cpuRead(self, address);
        }
    };
}

// Usage - zero runtime cost
const NromCart = Cartridge(Mapper0);
```

### Lock-Free Communication

7 active SPSC (Single-Producer, Single-Consumer) mailboxes:

1. **FrameMailbox**: Emulation → Render (triple-buffered RGBA frames)
2. **ControllerInputMailbox**: Main → Emulation (NES button state)
3. **DebugCommandMailbox**: Main → Emulation (breakpoints, watchpoints)
4. **DebugEventMailbox**: Emulation → Main (debug events)
5. **EmulationCommandMailbox**: Main → Emulation (pause, reset)
6. **XdgInputEventMailbox**: Render → Main (keyboard events)
7. **XdgWindowEventMailbox**: Render → Main (window events)

## Component Architecture

### Emulation State

`EmulationState` is the root coordinator, directly owning all emulation state:

```
EmulationState
├── cpu: CpuState (6502)
├── ppu: PpuState (2C02)
├── apu: ApuState (APU channels)
├── bus: BusState (2KB RAM + open bus)
├── cart: AnyCartridge (mapper dispatch)
├── clock: MasterClock (cycle counting)
├── vblank_ledger: VBlankLedger (NMI edge detection)
├── oam_dma: OamDmaState
├── dmc_dma: DmcDmaState
└── controllers: [2]ControllerState
```

### Tick Loop

Single `EmulationState.tick()` method orchestrates everything:

```zig
pub fn tick(self: *EmulationState) void {
    // Step CPU (1 CPU cycle)
    self.stepCpuCycle();

    // Step PPU (3 PPU cycles per CPU cycle for NTSC)
    self.stepPpuCycle();
    self.stepPpuCycle();
    self.stepPpuCycle();

    // Step APU (1:1 with CPU cycle)
    self.stepApuCycle();

    // Handle DMA transfers
    if (self.oam_dma.active) self.stepOamDma();
    if (self.dmc_dma.active) self.stepDmcDma();
}
```

### CPU (6502)

**Directory:** `src/cpu/`

- **State.zig**: Registers, flags, execution state
- **Logic.zig**: Pure helper functions
- **opcodes/**: 256 opcode implementations (13 modules)
- **dispatch.zig**: Opcode → executor routing table
- **decode.zig**: Opcode metadata tables

All opcodes are pure functions:
```zig
pub fn adc(cpu: *const CpuState, operand: u8) OpcodeResult { ... }
```

### PPU (2C02)

**Directory:** `src/ppu/`

- **State.zig**: Registers, VRAM, OAM, rendering state
- **Logic.zig**: Main PPU operations
- **logic/memory.zig**: VRAM/palette/OAM access
- **logic/registers.zig**: $2000-$2007 register I/O
- **logic/scrolling.zig**: Scanline/address management
- **logic/background.zig**: Background rendering
- **logic/sprites.zig**: Sprite evaluation & rendering
- **palette.zig**: 64-color NES palette
- **timing.zig**: NTSC timing constants

Key innovation: **VBlankLedger** for NMI race condition handling

### APU (Audio Processing Unit)

**Directory:** `src/apu/`

- **State.zig**: All channel state, frame counter
- **Logic.zig**: Main APU orchestration
- **logic/dmc.zig**: DMC channel
- **logic/envelope.zig**: Envelope generator (shared)
- **logic/sweep.zig**: Sweep unit (shared)
- **logic/pulse.zig**: Pulse channels 1 & 2
- **logic/triangle.zig**: Triangle channel
- **logic/noise.zig**: Noise channel
- **logic/frame_counter.zig**: Frame sequencer

All logic modules use pure functions returning result structs.

### Cartridge System

**Directory:** `src/cartridge/`

Generic `Cartridge(MapperType)` factory with `AnyCartridge` tagged union:

```zig
pub const AnyCartridge = union(MapperId) {
    nrom: Cartridge(Mapper0),
    // Future: mmc1, uxrom, cnrom, mmc3, etc.
};
```

iNES parser in `src/cartridge/ines/` (5 modules).

### Debugging System

**File:** `src/debugger/Debugger.zig`

Features:
- Breakpoints (execution address)
- Watchpoints (memory read/write)
- Single-stepping
- CPU state inspection
- Memory dumps

Communicates via `DebugCommandMailbox` and `DebugEventMailbox`.

## File Organization

```
src/
├── cpu/              # 6502 emulation
├── ppu/              # 2C02 PPU
├── apu/              # APU (audio)
├── cartridge/        # Cartridge + mappers
├── emulation/        # EmulationState (coordinator)
├── video/            # Wayland + Vulkan renderer
├── input/            # Input system
├── debugger/         # Debugging tools
├── mailboxes/        # Lock-free communication
├── snapshot/         # Save states
├── threads/          # Thread entry points
├── config/           # Configuration system
├── timing/           # Frame timing
├── benchmark/        # Performance benchmarks
├── memory/           # Memory adapters
├── test/             # Test utilities
├── root.zig          # Library root
└── main.zig          # CLI entry point
```

## Testing Strategy

**949/986 tests passing (96.2%)**

Test categories:
- **Unit Tests**: Pure logic functions (CPU opcodes, PPU logic, APU channels)
- **Integration Tests**: Component interactions (CPU-PPU, APU-DMA)
- **ROM Tests**: Full ROM execution (AccuracyCoin, commercial ROMs)
- **Hardware Tests**: Timing accuracy, edge cases, race conditions

## Build System

```bash
zig build               # Build executable
zig build test          # Run all tests (949/986 passing)
zig build test-unit     # Unit tests only
zig build test-integration  # Integration tests only
zig build run           # Run emulator
```

## References

- [Code Review](docs/code-review/OVERALL_ASSESSMENT.md)
- [Known Issues](docs/KNOWN-ISSUES.md)
- [GraphViz Diagrams](docs/dot/)
- [NESDev Wiki](https://www.nesdev.org/wiki/)
```

### 7.4 Update Code Review Documents

**Action:** Add completion status tracking to review docs

**Files to Update:**
Each `docs/code-review/*.md` file should have a header section:

```markdown
## Remediation Status

**Phase:** [Phase number from plan]
**Status:** [Not Started | In Progress | Completed | Verified]
**Completion Date:** [YYYY-MM-DD]
**Tests Passing:** [Before/After counts]
**Notes:** [Any implementation notes]
```

**Verification:**
```bash
# Ensure all diagrams regenerate correctly
cd docs/dot
for f in *.dot; do dot -Tpng "$f" -o "${f%.dot}.png" || echo "Failed: $f"; done

# Check for broken links
grep -r "docs/" docs/*.md | grep -v "archive"
```

---

## Testing Strategy

### Per-Phase Testing

After **each phase**, run this verification sequence:

```bash
# 1. Unit tests (fast feedback)
zig build test-unit

# 2. Full test suite
zig build test

# 3. Verify test count maintained or improved
# Expected: 949/986 tests passing minimum

# 4. Manual smoke test (if applicable)
zig build run -- roms/test/nestest.nes

# 5. Git diff sanity check
git diff --stat  # Review changes
git diff src/    # Inspect actual changes
```

### Regression Prevention

**Critical Invariants to Maintain:**

1. **Test Count**: Must maintain ≥949 passing tests
2. **Known Failures**: Only expected failures (12 documented in KNOWN-ISSUES.md)
3. **AccuracyCoin**: Must continue to PASS
4. **nestest**: Should continue to pass CPU tests
5. **Build Time**: Should not significantly increase
6. **Binary Size**: Should not significantly increase

### Rollback Plan

If any phase causes regressions:

```bash
# Immediate rollback
git reset --hard HEAD

# Or selective revert
git checkout HEAD -- <problematic-file>

# Document the issue
echo "Phase X caused regression: [details]" >> REMEDIATION-ISSUES.md

# Re-analyze before proceeding
```

---

## Execution Timeline

**Recommended Order:** Sequential (Phases 1→7)

| Phase | Estimated Time | Dependencies | Risk |
|-------|---------------|--------------|------|
| 1. Legacy Code Removal | 2-3 hours | None | LOW |
| 2. Config Simplification | 3-4 hours | Phase 1 | MEDIUM |
| 3. Cartridge Cleanup | 4-5 hours | Phase 1 | MEDIUM-HIGH |
| 4. PPU Finalization | 2-3 hours | Phase 1 | LOW-MEDIUM |
| 5. APU Refactoring | 8-12 hours | Phases 1, 4 | HIGH |
| 6. Emulation Consolidation | 2-3 hours | Phases 4, 5 | LOW |
| 7. Documentation | 3-4 hours | All phases | MINIMAL |

**Total Estimated Time:** 24-34 hours

**Recommended Approach:**
- Phases 1-4: Can be done in 1-2 day sprint
- Phase 5 (APU): Dedicate 2-3 days, consider sub-phases
- Phases 6-7: Final polish, 1 day

---

## Investigation Results (2025-10-11)

### ✅ Investigation 1: Unstable Opcodes Configuration

**Finding:** The `unstable_opcodes` section in `rambo.kdl` is **obsolete** and safe to remove.

**Analysis:**
- Config file contains: `sha_behavior` and `lxa_magic` settings (lines 26-36 of rambo.kdl)
- CPU implementation: `src/cpu/variants.zig` provides **comptime** variant-specific behavior
- Config struct (`src/config/types/hardware.zig`): **NO** `unstable_opcodes` field exists
- Parser (`src/config/parser.zig`): Does **NOT** parse unstable_opcodes section

**Verdict:**
- `unstable_opcodes` section in `rambo.kdl` is **dead configuration** - not parsed or used
- CPU unstable opcode behavior is correctly implemented in `src/cpu/variants.zig`:
  - `lxa_magic`: 0xEE (RP2A03G), 0xFF (RP2A03H), 0x00 (RP2A07) - comptime constants
  - `ane_magic`: Same as lxa_magic per variant
  - All behavior is **zero-cost compile-time dispatch**

**Action:** Phase 2 will remove lines 26-36 from `rambo.kdl` - no functionality loss

**Rationale:**
- CPU variant selection (RP2A03G/H/etc) already controls unstable opcode behavior
- Making this runtime-configurable would break the zero-cost comptime guarantee
- Current architecture is **superior** - hardware-accurate with no runtime overhead

---

### ✅ Investigation 2: Cartridge Loader

**Finding:** `loader.zig` is a **thin utility wrapper** that should be **kept**.

**Analysis:**
- File: `src/cartridge/loader.zig` (50 lines)
- Purpose: Simple file I/O wrapper for `Cartridge.load(path)` convenience method
- Used by: `Cartridge.zig:162` - only import of loader.zig in entire codebase
- Functionality:
  ```zig
  pub fn loadCartridgeFile(allocator, path, MapperType) !Cartridge(MapperType) {
      const file = try std.fs.cwd().openFile(path, .{});
      const data = try file.readToEndAlloc(allocator, MAX_ROM_SIZE);
      return try Cartridge(MapperType).loadFromData(allocator, data);
  }
  ```

**Verdict:**
- `loader.zig` is **NOT legacy code** - it's part of the new generic system
- Provides clean separation: `Cartridge.zig` handles ROM parsing, `loader.zig` handles file I/O
- **Keep as-is** - well-separated, single responsibility, properly integrated

**Action:** No changes needed for Phase 3. Loader stays.

**Rationale:**
- Separation of concerns: File I/O vs ROM parsing
- Future-proofing: Comment notes "Future: async libxev-based loading"
- Thread safety: File I/O isolated from RT-safe emulation logic
- Single call site: Used only by `Cartridge.load()` - proper encapsulation

---

### ✅ Investigation 3: Performance Baseline

**Status:** Benchmarks deferred - not a success criterion per user request

**Rationale:**
- Primary goals: Code quality, architecture consistency, legacy removal
- Performance monitoring: Watch for regressions, but not a blocking criterion
- Focus areas:
  - ✅ RT-safety (no allocations in emulation hot path)
  - ✅ Thread safety (no race conditions, proper mailbox usage)
  - ✅ Memory model (single call sites, side effect isolation)
  - ✅ State/Logic separation (pure functions)

**Action:** No formal benchmarks required, but maintain architectural constraints

---

## Success Criteria

### Phase Completion Criteria

Each phase is complete when:
- ✅ All planned changes implemented
- ✅ Test suite passes with ≥949/986 tests
- ✅ No new test failures introduced
- ✅ Code review document updated with completion status
- ✅ Git commit created with clear message
- ✅ Manual smoke test passes (where applicable)

### Overall Project Success

Project is complete when:
- ✅ All 7 phases completed
- ✅ All legacy code removed
- ✅ All code review issues addressed
- ✅ Documentation fully updated
- ✅ Test count maintained or improved (≥949/986)
- ✅ AccuracyCoin still passing
- ✅ No degradation in performance or binary size
- ✅ Final review of all changes completed

---

## Appendices

### Appendix A: File Deletion Checklist

**Complete list of files to delete across all phases:**

```
# Phase 1
src/cartridge/ines.zig
tests/ines/ines_test.zig
src/cpu/Logic.zig:reset()  # function only
src/emulation/State.zig:syncDerivedSignals()  # function only
src/emulation/State.zig:testSetVBlank()  # function only
src/emulation/State.zig:testClearVBlank()  # function only
src/ppu/State.zig:PpuStatus._reserved  # field only

# Phase 2
src/config/types/hardware.zig
src/config/types/ppu.zig
src/config/types/settings.zig
src/config/types.zig  # old re-export file

# Phase 3
src/cartridge/loader.zig  # potentially, needs analysis

# Phase 4
src/emulation/Ppu.zig

# Phase 5
src/apu/Dmc.zig  # moved to logic/dmc.zig
src/apu/Envelope.zig  # moved to logic/envelope.zig
src/apu/Sweep.zig  # moved to logic/sweep.zig

# Phase 6
src/emulation/state/BusState.zig
src/emulation/state/OamDma.zig
src/emulation/state/DmcDma.zig
src/emulation/state/ControllerState.zig
src/emulation/state/Timing.zig
src/emulation/helpers.zig  # potentially
```

### Appendix B: Import Update Checklist

**All imports that need updating:**

```zig
// Phase 1 - Legacy iNES imports (5 files)
src/ppu/logic/memory.zig
src/ppu/State.zig
src/snapshot/state.zig
src/test/Harness.zig
src/cartridge/Cartridge.zig

// Phase 2 - Config type imports
src/config/Config.zig
Any other files importing config types

// Phase 4 - PPU facade removal
src/emulation/State.zig (stepPpuCycle)

// Phase 5 - APU logic imports
src/emulation/State.zig (stepApuCycle)
tests/apu/*.zig (all APU tests)

// Phase 6 - State consolidation
Any files importing BusState, OamDma, DmcDma, ControllerState, Timing
```

### Appendix C: Test Impact Summary

**Expected test changes per phase:**

| Phase | Tests Modified | Tests Deleted | New Tests | Risk |
|-------|----------------|---------------|-----------|------|
| 1 | ~5-10 | ~3 (ines_test.zig) | 0 | LOW |
| 2 | ~10-15 (config tests) | 0 | 0 | MEDIUM |
| 3 | ~20-30 (integration) | 0 | 0 | MEDIUM-HIGH |
| 4 | ~10 (PPU tests) | 0 | 0 | LOW-MEDIUM |
| 5 | **~135 (all APU)** | 0 | ~10-20 | HIGH |
| 6 | ~10-20 | 0 | 0 | LOW |
| 7 | 0 | 0 | 0 | NONE |

**Total test modifications:** ~190-230 tests across all phases

---

## Conclusion

This plan provides a systematic, methodical approach to addressing all issues identified in the code review audit. Each phase is designed to be:

1. **Independent**: Can be tested and committed separately
2. **Non-regressive**: Maintains or improves test passing rate
3. **Reversible**: Can be rolled back if issues arise
4. **Verifiable**: Clear success criteria

The highest-risk work (APU refactoring) is isolated to Phase 5 and can be broken into sub-phases if needed. All other phases are low-to-medium risk with clear implementation paths.

**Recommendation:** Begin with Phases 1-4 as a cohesive sprint, pause for review, then tackle Phase 5 (APU) as a dedicated effort, followed by final polish in Phases 6-7.
