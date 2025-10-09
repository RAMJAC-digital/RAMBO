# Config & Debugger Decomposition Plan

**Date:** 2025-10-09
**Status:** Research Complete - Ready for Implementation
**Phase:** Phase 1 Milestones 1.7 & Extension
**Prerequisite:** Milestones 1.0-1.6 Complete ✅

---

## Executive Summary

This document details the decomposition strategy for the final two major monolithic files:
- **Config.zig** (782 lines, 22 functions) - P1 MEDIUM priority
- **Debugger.zig** (1,243 lines, 42 functions) - P1 HIGH priority

Both files follow similar anti-patterns to the now-resolved State.zig:
- Mixed type definitions and implementation
- Multiple responsibilities in single file
- Low cohesion, high coupling within file

**Total Impact:** 2,025 lines decomposed → ~200 lines (facades) + organized modules

---

## Quick Status

| Metric | Config.zig | Debugger.zig | Combined |
|--------|------------|--------------|----------|
| **Current Size** | 782 lines | 1,243 lines | 2,025 lines |
| **Target Size** | ~50 lines | ~150 lines | ~200 lines |
| **Reduction** | -93.6% | -87.9% | -90.1% |
| **Functions** | 22 | 42 | 64 |
| **Types** | 13 | 11 | 24 |
| **Risk Level** | 🟢 LOW | 🟡 MEDIUM | 🟡 MEDIUM |
| **Test Impact** | 0 files | 1 file | 1 file |
| **Estimated Time** | 4-6 hours | 8-12 hours | 12-18 hours |

---

## Part 1: Config.zig Decomposition (Milestone 1.7)

### Current Structure Analysis

**File:** `src/config/Config.zig` (782 lines)

**Type Definitions (Lines 14-320, ~300 lines):**
1. `ConsoleVariant` (enum, 63 lines) - NES/Famicom variants
2. `CpuVariant` (enum, 38 lines) - RP2A03 variants
3. `CpuModel` (struct, 10 lines) - CPU configuration
4. `CicVariant` (enum, 28 lines) - Lockout chip variants
5. `CicEmulation` (enum, 20 lines) - Emulation modes
6. `CicModel` (struct, 13 lines) - CIC configuration
7. `ControllerType` (enum, 25 lines) - Controller types
8. `ControllerModel` (struct, 7 lines) - Controller configuration
9. `PpuVariant` (enum, 29 lines) - PPU chip variants
10. `VideoRegion` (enum, 13 lines) - NTSC/PAL regions
11. `AccuracyLevel` (enum, 15 lines) - Emulation accuracy
12. `VideoBackend` (enum, 15 lines) - Rendering backends
13. `PpuModel` (struct, 38 lines) - PPU configuration
14. `VideoConfig` (struct, 6 lines) - Video settings
15. `AudioConfig` (struct, 5 lines) - Audio settings
16. `InputConfig` (struct, 4 lines) - Input settings

**Main Config Struct (Lines 322-782, ~460 lines):**
- Fields: 8 configuration sections + arena + mutex
- Methods: 22 functions (init, deinit, load, save, accessors, etc.)

**Existing Module:**
- `parser.zig` (8KB, ~280 lines) - KDL parsing logic ✅

### Extraction Strategy

#### Phase 1.7.1: Extract Type Definitions (2-3 hours)

**Create:** `src/config/types/`

```
src/config/types/
├── hardware.zig           # 150 lines
│   ├── ConsoleVariant
│   ├── CpuVariant
│   ├── CpuModel
│   ├── CicVariant
│   ├── CicEmulation
│   ├── CicModel
│   ├── ControllerType
│   └── ControllerModel
├── ppu.zig                # 90 lines
│   ├── PpuVariant
│   ├── VideoRegion
│   ├── AccuracyLevel
│   ├── VideoBackend
│   └── PpuModel
└── settings.zig           # 20 lines
    ├── VideoConfig
    ├── AudioConfig
    └── InputConfig
```

**Why This Grouping?**
- `hardware.zig` - Physical console hardware configuration
- `ppu.zig` - Display/rendering configuration
- `settings.zig` - Runtime settings (non-hardware)

#### Phase 1.7.2: Extract Defaults Module (1 hour)

**Create:** `src/config/defaults.zig` (~100 lines)

```zig
//! Default configuration values for all console variants
//! Used by Config.init() and Config.applyDefaults()

const types = @import("types/hardware.zig");

/// Get default CPU model for console variant
pub fn defaultCpuModel(console: types.ConsoleVariant) types.CpuModel {
    return switch (console) {
        .nes_ntsc_frontloader => .{ .variant = .rp2a03g },
        .nes_ntsc_toploader => .{ .variant = .rp2a03g },
        .nes_pal => .{ .variant = .rp2a07 },
        .famicom => .{ .variant = .rp2a03e },
        .famicom_av => .{ .variant = .rp2a03g },
    };
}

/// Get default PPU model for console variant
pub fn defaultPpuModel(console: types.ConsoleVariant) types.PpuModel {
    // ... similar pattern
}

/// Get default CIC model for console variant
pub fn defaultCicModel(console: types.ConsoleVariant) types.CicModel {
    // ... similar pattern
}
```

#### Phase 1.7.3: Extract State Module (1 hour)

**Create:** `src/config/State.zig` (~150 lines)

```zig
//! Config state structure
//! Holds all configuration values and provides thread-safe access

const std = @import("std");
const types = @import("types.zig"); // Re-export facade

pub const ConfigState = struct {
    /// Console variant (defines default hardware configuration)
    console: types.ConsoleVariant = .nes_ntsc_frontloader,

    /// CPU configuration
    cpu: types.CpuModel = .{},

    /// PPU configuration
    ppu: types.PpuModel = .{},

    /// CIC lockout chip configuration
    cic: types.CicModel = .{},

    /// Controller configuration
    controllers: types.ControllerModel = .{},

    /// Video output configuration
    video: types.VideoConfig = .{},

    /// Audio configuration
    audio: types.AudioConfig = .{},

    /// Input configuration
    input: types.InputConfig = .{},

    /// Arena allocator for config lifetime
    arena: std.heap.ArenaAllocator,

    /// Mutex for thread-safe reload operations
    mutex: std.Thread.Mutex = .{},

    pub fn init(allocator: std.mem.Allocator) ConfigState {
        return .{
            .arena = std.heap.ArenaAllocator.init(allocator),
        };
    }

    pub fn deinit(self: *ConfigState) void {
        self.arena.deinit();
    }

    /// Copy values from another ConfigState
    pub fn copyFrom(self: *ConfigState, other: ConfigState) void {
        self.console = other.console;
        self.cpu = other.cpu;
        self.ppu = other.ppu;
        self.cic = other.cic;
        self.controllers = other.controllers;
        self.video = other.video;
        self.audio = other.audio;
        self.input = other.input;
    }
};
```

#### Phase 1.7.4: Create Types Re-export Facade (30 min)

**Create:** `src/config/types.zig` (~40 lines)

```zig
//! Type definitions re-export facade
//! Single import point for all config types

// Hardware types
pub const ConsoleVariant = @import("types/hardware.zig").ConsoleVariant;
pub const CpuVariant = @import("types/hardware.zig").CpuVariant;
pub const CpuModel = @import("types/hardware.zig").CpuModel;
pub const CicVariant = @import("types/hardware.zig").CicVariant;
pub const CicEmulation = @import("types/hardware.zig").CicEmulation;
pub const CicModel = @import("types/hardware.zig").CicModel;
pub const ControllerType = @import("types/hardware.zig").ControllerType;
pub const ControllerModel = @import("types/hardware.zig").ControllerModel;

// PPU/Video types
pub const PpuVariant = @import("types/ppu.zig").PpuVariant;
pub const VideoRegion = @import("types/ppu.zig").VideoRegion;
pub const AccuracyLevel = @import("types/ppu.zig").AccuracyLevel;
pub const VideoBackend = @import("types/ppu.zig").VideoBackend;
pub const PpuModel = @import("types/ppu.zig").PpuModel;

// Settings types
pub const VideoConfig = @import("types/settings.zig").VideoConfig;
pub const AudioConfig = @import("types/settings.zig").AudioConfig;
pub const InputConfig = @import("types/settings.zig").InputConfig;
```

#### Phase 1.7.5: Refactor Config.zig to Facade (1 hour)

**Result:** `src/config/Config.zig` (~50 lines)

```zig
//! RAMBO Configuration System
//!
//! Thread-safe configuration management using KDL-style syntax.
//!
//! This is now a facade that re-exports all types and delegates
//! implementation to specialized modules.

const std = @import("std");

// Re-export all types (preserves existing API)
pub const ConsoleVariant = @import("types.zig").ConsoleVariant;
pub const CpuVariant = @import("types.zig").CpuVariant;
pub const CpuModel = @import("types.zig").CpuModel;
pub const CicVariant = @import("types.zig").CicVariant;
pub const CicEmulation = @import("types.zig").CicEmulation;
pub const CicModel = @import("types.zig").CicModel;
pub const ControllerType = @import("types.zig").ControllerType;
pub const ControllerModel = @import("types.zig").ControllerModel;
pub const PpuVariant = @import("types.zig").PpuVariant;
pub const VideoRegion = @import("types.zig").VideoRegion;
pub const AccuracyLevel = @import("types.zig").AccuracyLevel;
pub const VideoBackend = @import("types.zig").VideoBackend;
pub const PpuModel = @import("types.zig").PpuModel;
pub const VideoConfig = @import("types.zig").VideoConfig;
pub const AudioConfig = @import("types.zig").AudioConfig;
pub const InputConfig = @import("types.zig").InputConfig;

// Import implementation
const ConfigState = @import("State.zig").ConfigState;

/// Main Config facade - delegates to ConfigState
pub const Config = ConfigState;

// Run config tests
test {
    @import("std").testing.refAllDeclsRecursive(@This());
}
```

### Final Directory Structure

```
src/config/
├── Config.zig              # 50 lines - Facade + re-exports
├── State.zig               # 150 lines - ConfigState struct
├── types.zig               # 40 lines - Type re-export facade
├── types/
│   ├── hardware.zig        # 150 lines - Hardware types
│   ├── ppu.zig            # 90 lines - PPU/video types
│   └── settings.zig       # 20 lines - Runtime settings
├── defaults.zig            # 100 lines - Default values
└── parser.zig              # 280 lines - KDL parser (existing)
```

### Validation Checklist

- [ ] All types re-exported through Config.zig
- [ ] parser_test.zig still passes (no changes needed)
- [ ] No external imports break (Config.zig preserves API)
- [ ] `zig build test` shows 941/951 passing (baseline maintained)
- [ ] No compiler warnings

### Risk Assessment: 🟢 LOW

**Why Low Risk?**
- Pure type extraction (no logic changes)
- Existing parser.zig already separate
- Only 1 test file (parser_test.zig)
- Re-export pattern preserves 100% API compatibility
- No threading concerns (config loaded once at startup)

---

## Part 2: Debugger.zig Decomposition (Extension Milestone)

### Current Structure Analysis

**File:** `src/debugger/Debugger.zig` (1,243 lines)

**Type Definitions (Lines 26-165, ~140 lines):**
1. `DebugCallback` (struct, 16 lines)
2. `DebugMode` (enum, 18 lines)
3. `BreakpointType` (enum, 12 lines)
4. `Breakpoint` (struct, 20 lines)
5. `Watchpoint` (struct, 16 lines)
6. `StepState` (struct, 10 lines)
7. `HistoryEntry` (struct, 9 lines)
8. `DebugStats` (struct, 8 lines)
9. `StatusFlag` (enum, 10 lines)
10. `StateModification` (union, 20 lines)

**Main Debugger Struct (Lines 167-1243, ~1,076 lines):**

Functional sections identified:
1. **Initialization** (lines 213-236, ~24 lines)
2. **Breakpoint Management** (lines 238-391, ~154 lines)
3. **Watchpoint Management** (lines 393-564, ~172 lines)
4. **Step Execution** (lines 566-720, ~155 lines)
5. **History Management** (lines 722-845, ~124 lines)
6. **State Inspection** (lines 847-970, ~124 lines)
7. **State Modification** (lines 972-1120, ~149 lines)
8. **Helper Functions** (lines 1122-1243, ~122 lines)

**Test File:**
- `tests/debugger/debugger_test.zig` (1,849 lines) - Comprehensive test suite

### Extraction Strategy

#### Phase 2.1: Extract Type Definitions (2 hours)

**Create:** `src/debugger/types.zig` (~160 lines)

```zig
//! Debugger type definitions
//! All types used by the debugger system

const std = @import("std");
const EmulationState = @import("../emulation/State.zig").EmulationState;

/// User-defined callback interface
pub const DebugCallback = struct {
    onBeforeInstruction: ?*const fn (self: *anyopaque, state: *const EmulationState) bool = null,
    onMemoryAccess: ?*const fn (self: *anyopaque, address: u16, value: u8, is_write: bool) bool = null,
    userdata: *anyopaque,
};

/// Debugger execution mode
pub const DebugMode = enum {
    running,
    paused,
    step_instruction,
    step_over,
    step_out,
    step_scanline,
    step_frame,
};

// ... all other types
```

#### Phase 2.2: Extract Breakpoint Logic (3 hours)

**Create:** `src/debugger/breakpoints.zig` (~200 lines)

```zig
//! Breakpoint management logic
//! Pure functions operating on DebuggerState

const types = @import("types.zig");

/// Add breakpoint to debugger state
pub fn add(state: anytype, address: u16, bp_type: types.BreakpointType) !void {
    // Check if breakpoint already exists
    for (state.breakpoints[0..256]) |*maybe_bp| {
        if (maybe_bp.*) |*bp| {
            if (bp.address == address and bp.type == bp_type) {
                if (!bp.enabled) {
                    bp.enabled = true;
                    if (isMemoryBreakpointType(bp_type)) {
                        state.memory_breakpoint_enabled_count += 1;
                    }
                }
                return;
            }
        }
    }

    // Check capacity
    if (state.breakpoint_count >= 256) {
        return error.BreakpointLimitReached;
    }

    // Find first null slot
    var slot_index: ?usize = null;
    for (state.breakpoints[0..256], 0..) |maybe_bp, i| {
        if (maybe_bp == null) {
            slot_index = i;
            break;
        }
    }

    // Add breakpoint
    const index = slot_index.?;
    state.breakpoints[index] = .{
        .address = address,
        .type = bp_type,
    };
    state.breakpoint_count += 1;
    if (isMemoryBreakpointType(bp_type)) {
        state.memory_breakpoint_enabled_count += 1;
    }
}

/// Remove breakpoint from debugger state
pub fn remove(state: anytype, address: u16, bp_type: types.BreakpointType) bool {
    // ... extraction of removeBreakpoint logic
}

// ... other breakpoint functions
```

#### Phase 2.3: Extract Watchpoint Logic (3 hours)

**Create:** `src/debugger/watchpoints.zig` (~210 lines)

Similar pattern to breakpoints.zig, pure functions operating on debugger state.

#### Phase 2.4: Extract Stepping Logic (2 hours)

**Create:** `src/debugger/stepping.zig` (~180 lines)

```zig
//! Step execution logic
//! Handles step-over, step-into, step-out, step-scanline, step-frame

const types = @import("types.zig");
const EmulationState = @import("../emulation/State.zig").EmulationState;

/// Determine if debugger should halt at current state
pub fn shouldHalt(
    debugger_state: anytype,
    emulation_state: *const EmulationState,
) bool {
    // ... extraction of shouldBreak logic
}

/// Update step state after instruction
pub fn updateStepState(
    step_state: *types.StepState,
    emulation_state: *const EmulationState,
) void {
    // ... extraction of step state update logic
}

// ... other stepping functions
```

#### Phase 2.5: Extract History Management (2 hours)

**Create:** `src/debugger/history.zig` (~150 lines)

```zig
//! Execution history management
//! Maintains circular buffer of execution snapshots

const std = @import("std");
const types = @import("types.zig");
const Snapshot = @import("../snapshot/Snapshot.zig");

/// Add history entry
pub fn addEntry(
    history: *std.ArrayList(types.HistoryEntry),
    allocator: std.mem.Allocator,
    snapshot: []const u8,
    max_size: usize,
) !void {
    // ... extraction of addHistoryEntry logic
}

/// Clear history
pub fn clear(
    history: *std.ArrayList(types.HistoryEntry),
    allocator: std.mem.Allocator,
) void {
    // ... extraction of clearHistory logic
}

// ... other history functions
```

#### Phase 2.6: Extract State Inspection (1 hour)

**Create:** `src/debugger/inspection.zig` (~140 lines)

Pure read-only functions for inspecting emulation state.

#### Phase 2.7: Extract State Modification (2 hours)

**Create:** `src/debugger/modification.zig` (~170 lines)

Functions for modifying emulation state (registers, memory, etc.).

#### Phase 2.8: Create State Module (1 hour)

**Create:** `src/debugger/State.zig` (~200 lines)

```zig
//! Debugger state structure
//! Holds all debugger data (breakpoints, watchpoints, history, etc.)

const std = @import("std");
const types = @import("types.zig");
const Config = @import("../config/Config.zig").Config;

pub const DebuggerState = struct {
    const magic_value: u64 = 0xDEB6_6170_5055_4247;

    allocator: std.mem.Allocator,
    config: *const Config,
    magic: u64 = magic_value,

    mode: types.DebugMode = .running,

    // Breakpoints
    breakpoints: [256]?types.Breakpoint = [_]?types.Breakpoint{null} ** 256,
    breakpoint_count: usize = 0,
    memory_breakpoint_enabled_count: usize = 0,

    // Watchpoints
    watchpoints: [256]?types.Watchpoint = [_]?types.Watchpoint{null} ** 256,
    watchpoint_count: usize = 0,
    watchpoint_enabled_count: usize = 0,

    // Step state
    step_state: types.StepState = .{},

    // History
    history: std.ArrayList(types.HistoryEntry),
    history_max_size: usize = 100,

    // Modifications
    modifications: std.ArrayList(types.StateModification),
    modifications_max_size: usize = 1000,

    // Stats
    stats: types.DebugStats = .{},

    // Buffers
    break_reason_buffer: [256]u8 = undefined,
    break_reason_len: usize = 0,

    // Callbacks
    callbacks: [8]?types.DebugCallback = [_]?types.DebugCallback{null} ** 8,
    callback_count: usize = 0,

    pub fn init(allocator: std.mem.Allocator, config: *const Config) DebuggerState {
        return .{
            .allocator = allocator,
            .config = config,
            .history = std.ArrayList(types.HistoryEntry).init(allocator),
            .modifications = std.ArrayList(types.StateModification).init(allocator),
        };
    }

    pub fn deinit(self: *DebuggerState) void {
        // Free history snapshots
        for (self.history.items) |entry| {
            self.allocator.free(entry.snapshot);
        }
        self.history.deinit();
        self.modifications.deinit();
    }
};
```

#### Phase 2.9: Refactor Debugger.zig to Facade (1 hour)

**Result:** `src/debugger/Debugger.zig` (~150 lines)

```zig
//! Debugger System
//!
//! This is now a facade that re-exports all types and delegates
//! implementation to specialized modules following State/Logic pattern.

const std = @import("std");

// Re-export all types (preserves existing API)
pub const DebugCallback = @import("types.zig").DebugCallback;
pub const DebugMode = @import("types.zig").DebugMode;
pub const BreakpointType = @import("types.zig").BreakpointType;
pub const Breakpoint = @import("types.zig").Breakpoint;
pub const Watchpoint = @import("types.zig").Watchpoint;
pub const HistoryEntry = @import("types.zig").HistoryEntry;
pub const DebugStats = @import("types.zig").DebugStats;
pub const StatusFlag = @import("types.zig").StatusFlag;
pub const StateModification = @import("types.zig").StateModification;

// Import implementation modules
const DebuggerState = @import("State.zig").DebuggerState;
const Breakpoints = @import("breakpoints.zig");
const Watchpoints = @import("watchpoints.zig");
const Stepping = @import("stepping.zig");
const History = @import("history.zig");
const Inspection = @import("inspection.zig");
const Modification = @import("modification.zig");

/// Main Debugger facade - wraps DebuggerState with inline delegation
pub const Debugger = struct {
    state: DebuggerState,

    pub fn init(allocator: std.mem.Allocator, config: *const Config) Debugger {
        return .{ .state = DebuggerState.init(allocator, config) };
    }

    pub fn deinit(self: *Debugger) void {
        self.state.deinit();
    }

    // Inline delegation to breakpoint module
    pub inline fn addBreakpoint(self: *Debugger, address: u16, bp_type: BreakpointType) !void {
        return Breakpoints.add(&self.state, address, bp_type);
    }

    pub inline fn removeBreakpoint(self: *Debugger, address: u16, bp_type: BreakpointType) bool {
        return Breakpoints.remove(&self.state, address, bp_type);
    }

    // ... all other methods as inline delegation
};

test {
    @import("std").testing.refAllDeclsRecursive(@This());
}
```

### Final Directory Structure

```
src/debugger/
├── Debugger.zig            # 150 lines - Facade + inline delegation
├── State.zig               # 200 lines - DebuggerState struct
├── types.zig               # 160 lines - Type definitions
├── breakpoints.zig         # 200 lines - Breakpoint logic
├── watchpoints.zig         # 210 lines - Watchpoint logic
├── stepping.zig            # 180 lines - Step execution logic
├── history.zig             # 150 lines - History management
├── inspection.zig          # 140 lines - State inspection
└── modification.zig        # 170 lines - State modification
```

### Validation Checklist

- [ ] All types re-exported through Debugger.zig
- [ ] debugger_test.zig updated (import changes only)
- [ ] All public methods preserved as inline delegation
- [ ] `zig build test` shows 941/951 passing (baseline maintained)
- [ ] No compiler warnings
- [ ] Debugger functionality verified in integration tests

### Risk Assessment: 🟡 MEDIUM

**Why Medium Risk?**
- Complex logic with RT-safety requirements
- Integration with EmulationState (external dependency)
- 1,849 lines of tests (potential import updates needed)
- Thread-safety concerns (callbacks, modifications)

**Mitigation:**
- Follow proven State.zig extraction pattern
- Inline delegation preserves performance
- Incremental extraction (one module at a time)
- Comprehensive test validation after each step

---

## Implementation Timeline

### Milestone 1.7: Config Decomposition (4-6 hours)

| Task | Duration | Risk | Validation |
|------|----------|------|------------|
| 1.7.1 Extract type definitions | 2-3h | 🟢 Zero | Build + test |
| 1.7.2 Extract defaults module | 1h | 🟢 Zero | Build + test |
| 1.7.3 Extract State module | 1h | 🟢 Zero | Build + test |
| 1.7.4 Create types facade | 30m | 🟢 Zero | Build + test |
| 1.7.5 Refactor Config.zig | 1h | 🟢 Zero | Build + test |
| **Total** | **5.5h** | **🟢 LOW** | **Build + full test suite** |

### Extension Milestone: Debugger Decomposition (8-12 hours)

| Task | Duration | Risk | Validation |
|------|----------|------|------------|
| 2.1 Extract type definitions | 2h | 🟢 Zero | Build + test |
| 2.2 Extract breakpoint logic | 3h | 🟡 Medium | Build + test |
| 2.3 Extract watchpoint logic | 3h | 🟡 Medium | Build + test |
| 2.4 Extract stepping logic | 2h | 🟡 Medium | Build + test |
| 2.5 Extract history management | 2h | 🟢 Low | Build + test |
| 2.6 Extract state inspection | 1h | 🟢 Low | Build + test |
| 2.7 Extract state modification | 2h | 🟡 Medium | Build + test |
| 2.8 Create State module | 1h | 🟢 Low | Build + test |
| 2.9 Refactor Debugger.zig | 1h | 🟢 Low | Build + test |
| **Total** | **17h** | **🟡 MEDIUM** | **Build + full test suite** |

**Combined Total:** 22.5 hours (~3 days of focused work)

---

## Validation Strategy

### Per-Module Validation

After each extraction:

```bash
# 1. Build verification
zig build

# 2. Full test suite
zig build test

# 3. Specific subsystem tests
zig build test-unit        # Quick smoke test
zig build test-integration # Full validation

# 4. Check for regressions
# Expected: 941/951 passing (current baseline)
```

### Exit Criteria

**Config Decomposition (Milestone 1.7):**
- ✅ Config.zig reduced to ~50 lines (facade only)
- ✅ All types extracted to modules
- ✅ parser_test.zig passes unchanged
- ✅ No new test failures
- ✅ Build completes without warnings

**Debugger Decomposition (Extension):**
- ✅ Debugger.zig reduced to ~150 lines (facade + delegation)
- ✅ All logic extracted to specialized modules
- ✅ debugger_test.zig updated and passing
- ✅ No new test failures
- ✅ Build completes without warnings
- ✅ Integration tests verify debugger functionality

### Rollback Strategy

```bash
# Each phase gets its own branch
git checkout -b milestone-1.7-config-decomposition
git checkout -b extension-debugger-decomposition

# If validation fails:
git checkout main
git branch -D failed-branch-name
# Start over with lessons learned
```

---

## Success Metrics

### Quantitative

| Metric | Config.zig | Debugger.zig | Combined |
|--------|------------|--------------|----------|
| **Before** | 782 lines | 1,243 lines | 2,025 lines |
| **After (Facade)** | ~50 lines | ~150 lines | ~200 lines |
| **After (Total)** | ~690 lines | ~1,510 lines | ~2,200 lines |
| **Reduction (Facade)** | -93.6% | -87.9% | -90.1% |
| **Overhead** | +175 lines | +417 lines | +592 lines |
| **Overhead %** | +22.4% | +21.2% | +29.2% |

**Overhead breakdown:**
- File headers and documentation
- Module separation boundaries
- Type re-export facades
- Import statements

### Qualitative

- ✅ **Navigation:** Find any debugger function in <5 seconds
- ✅ **Comprehension:** Understand module purpose from filename
- ✅ **Maintenance:** Make changes without hunting through 1,200-line files
- ✅ **Testing:** Identify relevant module for any test case
- ✅ **Consistency:** Matches State/Logic pattern from rest of codebase

---

## Documentation Updates

### Required Updates

**After Milestone 1.7 (Config):**
- [ ] Update `docs/CURRENT-STATUS.md` - File counts, structure
- [ ] Update `docs/refactoring/PHASE-1-PROGRESS.md` - Mark M1.7 complete
- [ ] Update `docs/refactoring/PHASE-1-DEVELOPMENT-GUIDE.md` - Check off M1.7
- [ ] Update `CLAUDE.md` - Config structure section

**After Debugger Extension:**
- [ ] Update `docs/CURRENT-STATUS.md` - File counts, structure
- [ ] Update `docs/refactoring/PHASE-1-PROGRESS.md` - Add extension milestone
- [ ] Update `CLAUDE.md` - Debugger architecture section
- [ ] Create migration guide for debugger API users

---

## Key Design Decisions

### 1. Type Organization

**Config Types:** Grouped by concern
- `hardware.zig` - Physical console configuration
- `ppu.zig` - Display/rendering configuration
- `settings.zig` - Runtime settings

**Debugger Types:** Single `types.zig`
- All debugger types in one module (simpler, fewer files)
- Types are cohesive (all debugger-related)

### 2. State/Logic Separation

**Config:** Minimal logic extraction
- Types → dedicated modules
- State → ConfigState struct
- Logic → mostly in parser.zig (already separate)

**Debugger:** Full State/Logic split
- State → DebuggerState struct
- Logic → specialized modules (breakpoints, watchpoints, etc.)
- Facade → inline delegation for zero overhead

### 3. API Preservation

Both modules use **re-export pattern**:
```zig
// Config.zig
pub const ConsoleVariant = @import("types.zig").ConsoleVariant;
// ... all types re-exported

// Debugger.zig
pub const DebugCallback = @import("types.zig").DebugCallback;
// ... all types re-exported
```

This ensures **100% API compatibility** with zero test changes (except imports).

### 4. Inline Delegation

**Debugger** uses inline delegation for performance:
```zig
pub inline fn addBreakpoint(self: *Debugger, address: u16, bp_type: BreakpointType) !void {
    return Breakpoints.add(&self.state, address, bp_type);
}
```

Compiler inlines these wrappers → **zero runtime overhead**.

---

## Lessons from State.zig Extraction

### What Worked Well ✅

1. **Incremental extraction** - One module at a time, validate each step
2. **Re-export pattern** - Preserved API, zero test breakage
3. **Inline delegation** - Zero performance overhead
4. **Clear module boundaries** - Easy to navigate, maintain
5. **Comprehensive documentation** - Every module has clear purpose

### What to Improve 📈

1. **Plan imports carefully** - Avoid circular dependencies
2. **Test early and often** - Don't batch multiple extractions
3. **Document side effects** - Critical for RT-safe code
4. **Use anytype sparingly** - Good for duck typing, can obscure errors

### Applying to Config/Debugger

- **Config:** Simpler than State.zig - mostly types, minimal logic
- **Debugger:** Similar complexity to State.zig - use proven patterns
- **Both:** Follow established State/Logic pattern for consistency

---

## Conclusion

Both **Config.zig** and **Debugger.zig** are ready for decomposition using proven extraction patterns from State.zig and VulkanLogic.zig.

### Recommendation: ✅ **PROCEED**

**Order of Execution:**
1. **Milestone 1.7:** Config Decomposition (4-6 hours, LOW risk)
2. **Extension:** Debugger Decomposition (8-12 hours, MEDIUM risk)

**Total Effort:** 12-18 hours (~2-3 days)

**Expected Outcome:**
- Config.zig: 782 → 50 lines (-93.6%)
- Debugger.zig: 1,243 → 150 lines (-87.9%)
- Total: 2,025 → 200 lines (-90.1%)
- Zero functional changes
- Zero API breakage
- Improved maintainability

---

**Document Version:** 1.0
**Last Updated:** 2025-10-09
**Status:** Ready for Implementation
**Author:** Claude Code (AI)

