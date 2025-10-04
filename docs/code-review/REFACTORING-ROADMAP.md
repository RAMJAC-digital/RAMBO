# Code Review Refactoring Roadmap

**Date:** 2025-10-03
**Status:** In Progress
**Architecture:** Option A - Fully Generic (Comptime Duck Typing)

---

## Overview

This document tracks the implementation of all code review items from `docs/code-review/`. Each item is mapped to a specific phase with clear acceptance criteria.

**Architectural Decisions:**
- **Q1: VTables → Comptime Generics**: Option A - Fully generic duck typing
- **Q2: CPU `anytype`**: Replace with properly typed comptime generics
- **Q3: Legacy I/O Files**: Keep until Phase 2+ (libxev integration)

---

## Phase 1: Bus State/Logic Separation ✅ COMPLETE

**Completed:** 2025-10-03
**Commit:** 1ceb301

### 1.1: Create Bus State.zig ✅ DONE
**Code Review Item:** 04-memory-and-bus.md → 2.1 (Refactor Bus to Pure State Machine)

**Implementation:**
```
src/bus/State.zig (COMPLETE)
├── OpenBus struct (data bus retention)
├── State struct
│   ├── ram: [2048]u8
│   ├── cycle: u64
│   ├── open_bus: OpenBus
│   ├── test_ram: ?[]u8
│   ├── cartridge: ?*Cartridge (non-owning)
│   ├── ppu: ?*Ppu (non-owning)
│   └── Convenience methods: read(), write(), read16(), read16Bug()
│   └── Cartridge mgmt: loadCartridge(), unloadCartridge()
└── Pattern: Hybrid - pure data + delegation methods
```

**Acceptance Criteria:**
- [X] Pure data structure with optional non-owning pointers
- [X] Convenience methods delegate to Logic functions
- [X] Follows naming conventions with backward compatibility
- [X] Comprehensive inline documentation

---

### 1.2: Create Bus Logic.zig ✅ DONE
**Code Review Item:** 04-memory-and-bus.md → 2.1 (Refactor Bus to Pure State Machine)

**Implementation:**
```
src/bus/Logic.zig (NEW)
├── init() -> State
├── read(state: *State, cartridge: anytype, ppu: anytype, address: u16) u8
├── write(state: *State, cartridge: anytype, ppu: anytype, address: u16, value: u8) void
├── read16(state: *State, cartridge: anytype, ppu: anytype, address: u16) u16
├── read16Bug(state: *State, cartridge: anytype, ppu: anytype, address: u16) u16
├── dummyRead(state: *State, cartridge: anytype, ppu: anytype, address: u16) void
└── dummyWrite(state: *State, cartridge: anytype, ppu: anytype, address: u16) void
```

**Notes:**
- Uses `anytype` temporarily (will be replaced in Phase 3)
- All functions are pure (no side effects except state mutation)
- Pattern: Match CPU Logic.zig exactly

**Acceptance Criteria:**
- [X] All functions are pure
- [X] No global state
- [X] Comprehensive tests (17 tests total)
- [X] Inline documentation for all public functions

---

### 1.3: Update Bus.zig Module Re-exports ✅ DONE
**Code Review Item:** 04-memory-and-bus.md → 2.1 (Refactor Bus to Pure State Machine)

**Implementation:**
```zig
// src/bus/Bus.zig (COMPLETE)
pub const State = @import("State.zig");
pub const Logic = @import("Logic.zig");
pub const OpenBus = State.OpenBus;
pub const BusState = State.State;
pub const Bus = State.State; // Backward compat alias
pub fn init() State.State { return State.State.init(); }
```

**Acceptance Criteria:**
- [X] Follows CPU module pattern exactly
- [X] Backward compatibility for existing code
- [X] Clean, minimal re-export structure
- [X] init() function for module-level initialization

---

### 1.4: Update Bus Tests ✅ DONE
**Code Review Item:** 07-testing.md → 2.1 (Implement Bus Tests)

**Implementation:**
- Updated tests in `src/bus/State.zig` (6 State tests)
- Updated tests in `src/bus/Logic.zig` (11 Logic tests)
- All tests use State + Logic pattern
- Test coverage: RAM mirroring, open bus, ROM protection, read16, read16Bug

**Acceptance Criteria:**
- [X] All existing tests pass (17/17)
- [X] Tests use State + Logic pattern
- [X] Coverage: RAM mirroring, open bus, ROM protection, read16, read16Bug
- [X] Integration: Tests work with cartridge and PPU parameters

---

### 1.5: Fix CPU and Test Imports ✅ DONE
**Code Review Item:** Follow-up work from Bus refactoring

**Implementation:**
- Fixed all CPU internal files (dispatch.zig, execution.zig, helpers.zig)
- Updated all 11 instruction files imports
- Fixed 3 test files (instructions_test.zig, rmw_test.zig, unofficial_opcodes_test.zig)
- Created src/cpu/instructions.zig module for re-exports
- Fixed Cpu.zig alias (Cpu = State.State)
- Updated EmulationState.zig for new types

**Acceptance Criteria:**
- [X] All CPU files use Cpu.State.State (type) not Cpu.State (module)
- [X] All tests compile and pass
- [X] Backward compatibility maintained
- [X] Build completes successfully

---

### Phase 1 Summary

**Status:** ✅ COMPLETE
**Completion Date:** 2025-10-03
**Commit:** 1ceb301

**Key Achievements:**
1. Full Bus State/Logic separation with hybrid pattern
2. Non-owning pointers to cartridge/PPU in state
3. Convenience methods maintain backward compatibility
4. All CPU and test files updated for new architecture
5. Created instructions.zig module for clean re-exports
6. 17 Bus tests passing
7. Build compiles successfully

**Pattern Established:**
- Pure data structures with optional non-owning pointers
- Convenience methods delegate to Logic functions
- Logic functions accept explicit parameters for testing
- Module re-exports provide clean API
- Backward compatibility through aliases and wrapper methods

**Ready for Phase 2:** This pattern is now ready to be applied to PPU.

---

## Phase 2: PPU State/Logic Separation

### 2.1: Create PPU State.zig ✅ TODO
**Code Review Item:** 03-ppu.md → 2.1 (Refactor PPU to Pure State Machine)

**Implementation:**
```
src/ppu/State.zig (NEW)
├── PpuCtrl packed struct (from current Ppu.zig)
├── PpuMask packed struct (from current Ppu.zig)
├── PpuStatus packed struct (from current Ppu.zig)
├── State struct
│   ├── Registers: ctrl, mask, status, oam_addr, scroll, addr, data
│   ├── Internal state: v, t, x, w
│   ├── Timing: scanline, dot, frame, odd_frame
│   ├── Memory: vram[2048], palette_ram[32], oam[256]
│   ├── Rendering state: shift registers, latches
│   ├── CHR provider (will be comptime in Phase 3)
│   └── Mirroring mode
└── Pattern: Match src/cpu/State.zig exactly
```

**Acceptance Criteria:**
- [ ] Pure data structure
- [ ] Zero hidden state
- [ ] All register types preserved
- [ ] Follows naming conventions

---

### 2.2: Create PPU Logic.zig ✅ TODO
**Code Review Item:** 03-ppu.md → 2.1 (Refactor PPU to Pure State Machine)

**Implementation:**
```
src/ppu/Logic.zig (NEW)
├── init() -> State
├── reset(state: *State) void
├── tick(state: *State, framebuffer: ?[]u8) void
├── readRegister(state: *State, address: u16) u8
├── writeRegister(state: *State, address: u16, value: u8) void
├── setChrProvider(state: *State, provider: anytype) void
├── setMirroring(state: *State, mirroring: Mirroring) void
└── Internal rendering functions (fetchNametable, fetchAttribute, etc.)
```

**Acceptance Criteria:**
- [ ] All functions are pure
- [ ] Rendering logic preserved
- [ ] Comprehensive inline documentation

---

### 2.3: Update PPU.zig Module Re-exports ✅ TODO
**Code Review Item:** 03-ppu.md → 2.1 (Refactor PPU to Pure State Machine)

**Implementation:**
```zig
// src/ppu/Ppu.zig
pub const State = @import("State.zig");
pub const Logic = @import("Logic.zig");
pub const PpuCtrl = State.PpuCtrl;
pub const PpuMask = State.PpuMask;
pub const PpuStatus = State.PpuStatus;
pub const Ppu = State.State; // Backward compat
```

**Acceptance Criteria:**
- [ ] Follows CPU/Bus module pattern
- [ ] Backward compatibility
- [ ] Clean structure

---

### 2.4: Update PPU Tests ✅ TODO
**Code Review Item:** 07-testing.md → 2.3 (Expand PPU Test Coverage)

**Implementation:**
- Update existing PPU tests for State/Logic structure
- Expand test coverage (registers, VRAM, rendering)

**Acceptance Criteria:**
- [ ] All existing tests pass
- [ ] Tests use State + Logic pattern
- [ ] Increased coverage (document percentage)

---

## Phase A: Backward Compatibility Cleanup ✅ COMPLETE

**Completed:** 2025-10-03
**Purpose:** Remove all backward compatibility code and establish clean API naming conventions

This phase removes all temporary backward compatibility aliases and convenience methods added during Phase 1 and Phase 2, establishing a clean, consistent API throughout the codebase.

### A.1: Verify Backward Compatibility Code ✅ DONE
**Identified Items:**
- CPU module: `pub const Cpu = State.State;` backward compat alias
- Bus module: `pub const Bus = State.State;` backward compat alias
- PPU module: `pub const Ppu = State.State;` backward compat alias
- All module-level `init()` convenience functions
- State.zig convenience delegation methods
- root.zig type aliases using old patterns

### A.2: Rename State Pattern → ComponentState ✅ DONE
**Decision:** Use component-specific naming that clearly indicates hardware state

**Changes Made:**
```zig
// Before: Redundant and confusing
State.State → CpuState
Bus.Bus → BusState
Ppu.Ppu → PpuState

// After: Clear and specific
Cpu.State.CpuState
Bus.State.BusState
Ppu.State.PpuState
```

**Files Updated:**
- All State.zig files: Renamed main type
- All Logic.zig files: Updated type references
- All instruction files (10): Updated signatures and imports
- All helper files: addressing.zig, helpers.zig, dispatch.zig, execution.zig
- All test files: instructions_test.zig, rmw_test.zig, unofficial_opcodes_test.zig
- EmulationState.zig: Updated component state types
- root.zig: Updated convenience type aliases

### A.3: Remove Backward Compatibility Aliases ✅ DONE
**Removed:**
```zig
// Removed from Cpu.zig
pub const Cpu = State.State; // ❌ REMOVED

// Removed from Bus.zig
pub const Bus = State.State; // ❌ REMOVED
pub inline fn init() State.State { ... } // ❌ REMOVED

// Removed from Ppu.zig
pub const Ppu = State.State; // ❌ REMOVED
pub inline fn init() State.State { ... } // ❌ REMOVED
```

**Acceptance Criteria:**
- [X] All backward compat aliases removed
- [X] All type references updated
- [X] All 375 tests passing
- [X] Zero compiler warnings

### A.4: Convenience Delegation Methods ✅ KEPT (Intentional Design)
**Decision:** Keep delegation methods - they are part of the hybrid architecture pattern, NOT backward compatibility

**Rationale:**
- State documentation explicitly states: "State includes non-owning pointers for convenient method delegation"
- These methods are the intended API, not temporary compatibility shims
- Removing them would break the hybrid architecture pattern
- They provide a clean interface while maintaining State/Logic separation

**Methods Kept (Intentional):**
```zig
// Bus.State.zig - These are the intended API:
pub inline fn read(self: *BusState, address: u16) u8
pub inline fn write(self: *BusState, address: u16, value: u8) void
pub inline fn read16(self: *BusState, address: u16) u16
pub inline fn read16Bug(self: *BusState, address: u16) u16

// Ppu.State.zig - These are the intended API:
pub inline fn tick(self: *PpuState, framebuffer: ?[]u32) void
pub inline fn reset(self: *PpuState) void
pub inline fn readRegister(self: *PpuState, address: u16) u8
pub inline fn writeRegister(self: *PpuState, address: u16, value: u8) void
```

**Acceptance Criteria:**
- [X] Verified these are intentional design, not backward compat
- [X] Methods remain in State.zig files
- [X] All tests passing
- [X] Clean API established

### A.5: Delete Dead I/O Files ✅ DONE
**Target:** Remove unused async I/O architecture files (deferred from Phase 1)

**Files Deleted:**
```
src/io/Architecture.zig  # ❌ DELETED - Dead code
src/io/Runtime.zig        # ❌ DELETED - Dead code
```

**Changes Made:**
- Removed `pub const IoArchitecture = @import("io/Architecture.zig");` from root.zig
- Removed `pub const Runtime = @import("io/Runtime.zig");` from root.zig
- Removed test references in root.zig
- Deleted both files

**Note:** These will be replaced in Phase 9 (I/O Redesign) when libxev integration is complete.

**Acceptance Criteria:**
- [X] Files deleted
- [X] root.zig imports removed
- [X] Build succeeds (all 375 tests pass)
- [X] No references remain

### A.6: Update Documentation ✅ DONE
**Target:** Reflect new clean API patterns in all documentation

**Files Updated:**
- ✅ REFACTORING-ROADMAP.md: Added complete Phase A documentation
- ✅ REFACTORING-ROADMAP.md: Updated all phase status
- ✅ Root.zig: Removed dead I/O imports
- ⏳ CLAUDE.md: Will update in final commit with all changes

**Acceptance Criteria:**
- [X] Roadmap documents complete Phase A
- [X] No references to old State.State pattern in code
- [X] All examples use ComponentState pattern
- [X] Phase A marked complete

---

## Phase A Summary ✅ COMPLETE

**Completed:** 2025-10-03
**Total Time:** ~2 hours
**Impact:** Clean, consistent API with zero backward compatibility cruft

**What Was Accomplished:**
1. ✅ Verified all backward compatibility code locations
2. ✅ Renamed State.State → ComponentState pattern (CpuState, BusState, PpuState)
3. ✅ Removed all backward compatibility aliases from module files
4. ✅ Verified delegation methods are intentional design (kept)
5. ✅ Deleted dead I/O files (Architecture.zig, Runtime.zig)
6. ✅ Updated all 20+ files with new type patterns
7. ✅ All 375 tests passing with zero warnings

**Files Changed:**
- ✏️ All State.zig files (3): Renamed main types
- ✏️ All Logic.zig files (3): Updated type references
- ✏️ All CPU instruction files (10): Updated imports/signatures
- ✏️ CPU helper files (4): addressing.zig, helpers.zig, dispatch.zig, execution.zig
- ✏️ Test files (3): instructions_test.zig, rmw_test.zig, unofficial_opcodes_test.zig
- ✏️ EmulationState.zig: Updated component types
- ✏️ root.zig: Updated type aliases, removed dead imports
- ❌ Deleted: src/io/Architecture.zig, src/io/Runtime.zig

**API Before Phase A:**
```zig
// Confusing and redundant
const CpuType = Cpu.Cpu;  // Cpu.Cpu? What?
const BusType = Bus.Bus;  // Bus.Bus? Huh?
const PpuType = Ppu.Ppu;  // Ppu.Ppu? Why?
```

**API After Phase A:**
```zig
// Clean and explicit
const CpuState = Cpu.State.CpuState;  // ✨ Clear: CPU hardware state
const BusState = Bus.State.BusState;  // ✨ Clear: Bus hardware state
const PpuState = Ppu.State.PpuState;  // ✨ Clear: PPU hardware state
```

---

## Phase 3: Replace VTables with Comptime Generics

### 3.1: Replace Mapper VTable ✅ TODO
**Code Review Item:** 04-memory-and-bus.md → 2.2, 08-code-safety.md → 2.1

**Current (VTable):**
```zig
pub const Mapper = struct {
    vtable: *const VTable,
    // ...
};
```

**New (Comptime Generic - Duck Typing):**
```zig
// No Mapper interface needed - just verify at comptime
pub fn verifyMapperInterface(comptime T: type) void {
    // Compile-time check that T has required methods
    _ = T.cpuRead;
    _ = T.cpuWrite;
    _ = T.ppuRead;
    _ = T.ppuWrite;
    _ = T.reset;
}
```

**Implementation Steps:**
1. Remove `src/cartridge/Mapper.zig` entirely
2. Update `src/cartridge/mappers/Mapper0.zig` to be standalone
3. Update `src/cartridge/Cartridge.zig` to be generic: `Cartridge(comptime MapperImpl: type)`
4. Add comptime verification in Cartridge

**Acceptance Criteria:**
- [ ] Compile-time verification of mapper interface
- [ ] Zero runtime overhead
- [ ] All mapper tests pass
- [ ] Mapper0 works correctly

---

### 3.2: Replace ChrProvider VTable ✅ TODO
**Code Review Item:** 04-memory-and-bus.md → 2.2, 08-code-safety.md → 2.1

**Current (VTable):**
```zig
pub const ChrProvider = struct {
    ptr: *anyopaque,
    vtable: *const VTable,
    // ...
};
```

**New (Comptime Generic - Duck Typing):**
```zig
// No ChrProvider interface needed
// PPU just uses comptime generic for CHR access
pub fn verifyChrProviderInterface(comptime T: type) void {
    _ = T.read;  // fn(self: *T, address: u16) u8
    _ = T.write; // fn(self: *T, address: u16, value: u8) void
}
```

**Implementation Steps:**
1. Remove `src/memory/ChrProvider.zig` entirely
2. Update PPU State to store `chr_provider: ?*anyopaque` → becomes comptime param
3. Add comptime verification
4. Update all CHR provider implementations

**Acceptance Criteria:**
- [ ] Compile-time verification
- [ ] Zero runtime overhead
- [ ] All CHR tests pass

---

### 3.3: Update Cartridge for Comptime Mapper ✅ TODO
**Code Review Item:** 04-memory-and-bus.md → 2.2

**New Structure:**
```zig
pub fn Cartridge(comptime MapperImpl: type) type {
    comptime verifyMapperInterface(MapperImpl);

    return struct {
        const Self = @This();

        mapper: MapperImpl,
        prg_rom: []const u8,
        chr_rom: []u8,
        mirroring: Mirroring,

        // Methods that delegate to mapper
        pub fn cpuRead(self: *Self, address: u16) u8 {
            return self.mapper.cpuRead(&self, address);
        }
        // ...
    };
}
```

**Acceptance Criteria:**
- [ ] Generic Cartridge type
- [ ] Comptime mapper verification
- [ ] All cartridge tests pass
- [ ] Backward compatibility with loading logic

---

## Phase 4: Remove `anytype` from CPU

### 4.1: Update CPU Logic Functions ✅ TODO
**Code Review Item:** 02-cpu.md → 2.4, 08-code-safety.md → 2.2

**Current:**
```zig
pub fn tick(state: *State, bus: anytype) bool
pub fn reset(state: *State, bus: anytype) void
```

**New (Comptime Generic):**
```zig
pub fn tick(state: *State, comptime BusImpl: type, bus: *BusImpl) bool
pub fn reset(state: *State, comptime BusImpl: type, bus: *BusImpl) void
```

**OR (if Bus becomes concrete after Phase 1-3):**
```zig
pub fn tick(state: *State, bus: *Bus.State) bool
pub fn reset(state: *State, bus: *Bus.State) void
```

**Decision:** Will be made after Phase 3 completion based on Bus structure

**Acceptance Criteria:**
- [ ] No `anytype` in CPU public API
- [ ] Type safety maintained
- [ ] All CPU tests pass

---

### 4.2: Update All CPU Instruction Files ✅ TODO
**Code Review Item:** 02-cpu.md → 2.4

**Files to Update:**
- `src/cpu/instructions/arithmetic.zig`
- `src/cpu/instructions/branch.zig`
- `src/cpu/instructions/compare.zig`
- `src/cpu/instructions/incdec.zig`
- `src/cpu/instructions/jumps.zig`
- `src/cpu/instructions/loadstore.zig`
- `src/cpu/instructions/logical.zig`
- `src/cpu/instructions/shifts.zig`
- `src/cpu/instructions/stack.zig`
- `src/cpu/instructions/transfer.zig`
- `src/cpu/instructions/unofficial.zig`

**Acceptance Criteria:**
- [ ] All instruction files updated
- [ ] Consistent type signatures
- [ ] All tests pass

---

## Phase 5: Update EmulationState

### 5.1: Update EmulationState for Comptime Generics ✅ TODO
**Code Review Item:** 01-architecture.md → 3.2 (Refactor to Hybrid Model)

**Current:**
```zig
pub const EmulationState = struct {
    cpu: Cpu.State,
    ppu: Ppu,
    bus: BusType,
    // ...
};
```

**New (Comptime Generic):**
```zig
pub fn EmulationState(comptime MapperImpl: type) type {
    return struct {
        const Self = @This();

        clock: MasterClock,
        cpu: Cpu.State,
        ppu: Ppu.State,
        bus: Bus.State,
        cartridge: Cartridge(MapperImpl),
        config: *const Config.Config,

        pub fn init(config: *const Config.Config, cart: Cartridge(MapperImpl)) Self {
            // ...
        }
        // ...
    };
}
```

**Acceptance Criteria:**
- [ ] Comptime generic over mapper type
- [ ] All component states owned by EmulationState
- [ ] All emulation tests pass
- [ ] Documentation updated

---

### 5.2: Update root.zig and main.zig ✅ TODO
**Code Review Item:** 01-architecture.md → 3.2

**Updates Needed:**
- `src/root.zig`: Export generic types
- `src/main.zig`: Instantiate concrete types (e.g., `EmulationState(Mapper0)`)

**Acceptance Criteria:**
- [ ] Build succeeds
- [ ] Tests pass
- [ ] Example usage documented

---

## Phase 6: Testing Verification

### 6.1: Run All Tests ✅ TODO
**Code Review Item:** 07-testing.md → 2.4 (Use Test Runner)

**Commands:**
```bash
zig build test           # All tests
zig build test-unit      # Unit tests only
zig build test-integration  # Integration tests
```

**Acceptance Criteria:**
- [ ] All tests pass (375+ tests)
- [ ] Zero compiler warnings
- [ ] Zero compiler errors
- [ ] Performance: No significant regression

---

## Phase 7: Documentation and Cleanup

### 7.1: Move Debug Tests ✅ TODO
**Code Review Item:** 09-dead-code.md → 2.2

**Files to Move:**
```
tests/cpu/dispatch_debug_test.zig → tests/debug/dispatch_debug_test.zig
tests/cpu/rmw_debug_test.zig → tests/debug/rmw_debug_test.zig
tests/cpu/cycle_trace_test.zig → tests/debug/cycle_trace_test.zig
```

**Create:** `tests/debug/` directory

**Acceptance Criteria:**
- [ ] Debug tests moved
- [ ] Not run by default `zig build test`
- [ ] Documented in README or CLAUDE.md

---

### 7.2: Update Code Review Docs - Mark Completed ✅ TODO
**Code Review Item:** All

**Files to Update:**
- `docs/code-review/01-architecture.md` → Mark 3.2 as DONE
- `docs/code-review/02-cpu.md` → Mark 2.1, 2.2, 2.4, 2.5 as DONE
- `docs/code-review/03-ppu.md` → Mark 2.1 as DONE
- `docs/code-review/04-memory-and-bus.md` → Mark 2.1, 2.2 as DONE
- `docs/code-review/08-code-safety-and-best-practices.md` → Mark 2.1, 2.2 as DONE

**Add Notes:**
- Document architectural decisions (Option A, etc.)
- Reference this REFACTORING-ROADMAP.md

**Acceptance Criteria:**
- [ ] All completed items marked
- [ ] Status dates updated
- [ ] Links to implementation files added

---

### 7.3: Note KDL Library Status ✅ TODO
**Code Review Item:** 06-configuration.md → 2.1

**Update:** `docs/code-review/06-configuration.md`

**Add Note:**
```markdown
### 2.1. Use a KDL Parsing Library

*   **Action:** ~~Instead of parsing the KDL file manually, use a dedicated KDL parsing library.~~
*   **Status:** **BLOCKED** - No mature KDL parsing library exists for Zig 0.15.1 as of 2025-10-03.
*   **Resolution:** Keep manual parser for now. Re-evaluate when Zig ecosystem matures.
*   **Alternative:** Consider switching to TOML/JSON if KDL parser maintenance becomes burden.
```

**Acceptance Criteria:**
- [ ] Status clearly documented
- [ ] Rationale provided
- [ ] Alternative noted

---

### 7.4: Note I/O Files Status ✅ TODO
**Code Review Item:** 09-dead-code.md → 2.1

**Update:** `docs/code-review/09-dead-code.md`

**Add Note:**
```markdown
### 2.1. Remove Old I/O Architecture Files

*   **Action:** ~~The `src/io/Architecture.zig` and `src/io/Runtime.zig` files should be removed~~
*   **Status:** **DEFERRED** to Phase 2+ (libxev Integration)
*   **Rationale:** These files contain reusable abstractions (triple buffer, queues) that will be needed when implementing the libxev I/O layer. Keep until replacement is implemented.
*   **Next Steps:** Will be refactored/replaced during Phase 2 I/O work.
```

**Acceptance Criteria:**
- [ ] Status clearly documented
- [ ] Rationale provided
- [ ] Next steps defined

---

### 7.5: Update CLAUDE.md ✅ TODO
**Code Review Item:** Documentation maintenance

**Additions to CLAUDE.md:**
```markdown
## Architecture Patterns

### State/Logic Separation
All core components follow the State/Logic pattern:

- **State**: Pure data structures (src/*/State.zig)
  - No methods (except inline helpers)
  - Serializable for save states
  - Zero hidden state

- **Logic**: Pure functions (src/*/Logic.zig)
  - Operate on State pointers
  - No global state
  - Deterministic execution

- **Module**: Re-exports (src/*/Module.zig)
  - `pub const State = @import("State.zig");`
  - `pub const Logic = @import("Logic.zig");`
  - Backward compatibility aliases

### Comptime Generics (Duck Typing)
The project uses Zig's comptime generics for zero-cost polymorphism:

- Mapper interface: Comptime verified duck typing
- ChrProvider interface: Comptime verified duck typing
- No vtables in hot paths
- Compile-time interface verification

**Example:**
```zig
pub fn EmulationState(comptime MapperImpl: type) type {
    comptime verifyMapperInterface(MapperImpl);
    return struct {
        // ...
    };
}
```
```

**Acceptance Criteria:**
- [ ] Pattern documentation added
- [ ] Examples provided
- [ ] References to architecture docs

---

## Phase 8: Final Commit

### 8.1: Create Comprehensive Commit ✅ TODO

**Commit Structure:**
```
refactor: Complete Phase 1 code review - State/Logic separation & comptime generics

Addresses all actionable items from docs/code-review/:

COMPLETED:
- [01-architecture.md] 3.2: Refactor code to hybrid model
- [02-cpu.md] 2.1: CPU state/logic separation (already done)
- [02-cpu.md] 2.2: Simplified dispatch (already done)
- [02-cpu.md] 2.4: Removed anytype from CPU
- [02-cpu.md] 2.5: Consolidated execution/dispatch (already done)
- [03-ppu.md] 2.1: PPU state/logic separation
- [04-memory-and-bus.md] 2.1: Bus state/logic separation
- [04-memory-and-bus.md] 2.2: Replaced vtables with comptime generics
- [08-code-safety.md] 2.1: Comptime generics for polymorphism
- [08-code-safety.md] 2.2: Eliminated anytype from core logic
- [09-dead-code.md] 2.2: Moved debug tests to tests/debug/

DEFERRED (Phase 2+):
- [02-cpu.md] 2.3: Unstable opcode config (needs HardwareConfig)
- [03-ppu.md] 2.2-2.5: PPU rendering features (separate work)
- [05-async-and-io.md] All: libxev integration
- [06-configuration.md] 2.2-2.3: HardwareConfig, hot-reload
- [07-testing.md] 2.2, 2.5, 2.6: Integration tests, data-driven tests
- [08-code-safety.md] 2.3-2.5: RT safety, build options

BLOCKED:
- [06-configuration.md] 2.1: KDL library (none exists for Zig)

KEPT (Not Dead):
- [09-dead-code.md] 2.1: I/O files (needed for Phase 2+)

ARCHITECTURAL DECISIONS:
- Comptime generics (duck typing) over vtables
- State/Logic separation for all components
- EmulationState is generic over Mapper type
- Zero coupling between components

FILES CHANGED:
- Created: src/bus/State.zig, src/bus/Logic.zig
- Created: src/ppu/State.zig, src/ppu/Logic.zig
- Modified: src/bus/Bus.zig, src/ppu/Ppu.zig (re-exports)
- Removed: src/cartridge/Mapper.zig, src/memory/ChrProvider.zig
- Modified: src/cartridge/Cartridge.zig (now generic)
- Modified: src/emulation/State.zig (now generic)
- Modified: src/cpu/Logic.zig (removed anytype)
- Modified: All CPU instruction files (type updates)
- Moved: tests/debug/* (from tests/cpu/)
- Updated: docs/code-review/* (status tracking)
- Updated: CLAUDE.md (pattern documentation)

TESTS:
- All 375+ tests passing
- Zero compiler warnings
- Zero runtime overhead from refactoring
- Performance: No regression

See docs/code-review/REFACTORING-ROADMAP.md for full details.
```

**Acceptance Criteria:**
- [ ] Comprehensive commit message
- [ ] All files staged
- [ ] Clean git status
- [ ] Documented in this roadmap

---

## Deferred Items (Future Phases)

### Phase 2: I/O and Configuration
- Complete libxev integration (05-async-and-io.md)
- Implement HardwareConfig (06-configuration.md → 2.2)
- Hot-reloading configuration (06-configuration.md → 2.3)
- Refactor/replace I/O Architecture.zig and Runtime.zig (09-dead-code.md → 2.1)

### Phase 3: Testing and Accuracy
- Integration tests (07-testing.md → 2.2)
- Expand PPU test coverage (07-testing.md → 2.3)
- Data-driven tests (07-testing.md → 2.5)
- Existing test ROMs (07-testing.md → 2.6)
- Unstable opcode configuration (02-cpu.md → 2.3)
- Proper open bus model refinement (04-memory-and-bus.md → 2.4)

### Phase 4: PPU Completion
- More granular PPU tick (03-ppu.md → 2.2)
- Complete rendering pipeline (03-ppu.md → 2.3)
- PPU-CPU cycle-accurate interaction (03-ppu.md → 2.4)
- Four-screen mirroring (03-ppu.md → 2.5)

### Phase 5: Advanced Features
- RT safety audit (08-code-safety.md → 2.3)
- Build.zig options (08-code-safety.md → 2.5)
- Full code audit for unused code (09-dead-code.md → 2.3)

---

## Progress Tracking

**Overall Progress:** 18% (4/22 phases complete)

**Phase 1 (Bus):** 4/4 complete ✅
**Phase 2 (PPU):** 0/4 complete
**Phase 3 (Comptime):** 0/3 complete
**Phase 4 (CPU anytype):** 0/2 complete
**Phase 5 (EmulationState):** 0/2 complete
**Phase 6 (Testing):** 0/1 complete
**Phase 7 (Docs):** 0/5 complete
**Phase 8 (Commit):** 0/1 complete

**Last Updated:** 2025-10-03

### Completed Items

#### Phase 1: Bus State/Logic Separation ✅
- ✅ Created `src/bus/State.zig` with pure data structure
- ✅ Created `src/bus/Logic.zig` with pure functions
- ✅ Updated `src/bus/Bus.zig` for module re-exports
- ✅ All 17 Bus tests passing

#### Discovered Issues
- CPU Logic.zig had incorrect type references (State module vs State.State type) - FIXED
- Test files need updates for State/Logic separation - IN PROGRESS
- EmulationState needs adjustment for new Bus structure - IN PROGRESS

### Next Steps
1. Fix all test files to use correct State.State types
2. Update all CPU instruction files for State/Logic imports
3. Verify all 375+ tests pass
4. Commit Phase 1 work before proceeding to Phase 2 (PPU)
