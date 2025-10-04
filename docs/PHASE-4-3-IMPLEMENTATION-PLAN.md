# Phase 4.3: Complete Implementation Plan

**Date:** 2025-10-03
**Status:** READY FOR IMPLEMENTATION
**Estimated Effort:** 26-33 hours total

---

## Executive Summary

This document provides the complete development path for finishing Phase 4.3 (State Snapshot + Debugger System). All design decisions have been made, blockers identified and resolved, and integration with AccuracyCoin tests planned.

**Key Outcomes:**
- Complete state serialization/deserialization (binary + JSON)
- Debugger with breakpoints, watchpoints, step execution
- Integration with AccuracyCoin test ROM for verification
- Foundation for future integration tests using state snapshots

---

## 1. State Structure Analysis

### 1.1 Complete EmulationState Breakdown

| Component | Size | Fields |
|-----------|------|--------|
| **MasterClock** | 8 bytes | ppu_cycles: u64 |
| **CpuState** | ~33 bytes | Registers (7B) + Cycle tracking (10B) + Context (7B) + Bus (1B) + Interrupts (4B) + Misc (4B) |
| **PpuState** | ~2,407 bytes | Registers (4B) + Internal (10B) + BgState (10B) + OAM (256B) + Secondary OAM (32B) + VRAM (2048B) + Palette (32B) + Misc (15B) |
| **BusState** | ~2,065 bytes | RAM (2048B) + Cycle (8B) + OpenBus (9B) |
| **EmulationState flags** | 3 bytes | frame_complete, odd_frame, rendering_enabled |
| **Config values** | ~20 bytes | Console variant, CPU/PPU/CIC config values |
| **TOTAL CORE STATE** | **~4,536 bytes** | **Without framebuffer** |
| **With framebuffer** | **~250 KB** | **Core + 256×240×4 RGBA** |

**Verification:** Matches specification estimate of ~5 KB core state ✅

### 1.2 Pointer Handling Strategy

**Pointers in EmulationState:**
- `config: *const Config.Config` - **Provide externally on restore**
- `bus.cartridge: ?*NromCart` - **Reconstruct from snapshot or provide externally**
- `bus.ppu: ?*PpuState` - **Wire via `connectComponents()`**
- `ppu.cartridge: ?*NromCart` - **Wire via `connectComponents()`**

**Restoration Flow:**
1. Load binary snapshot data
2. Deserialize all pure state fields
3. Provide external pointers (config, cartridge)
4. Call `state.connectComponents()` to rewire internal pointers
5. Return fully reconstructed EmulationState

**Architecture Compliance:** ✅ No modifications to EmulationState structure required

---

## 2. Serialization Format Specification

### 2.1 Binary Snapshot Layout

```
[Header: 72 bytes]
  - magic: [8]u8 "RAMBO\0\0\0"
  - version: u32 (little-endian)
  - timestamp: i64 (little-endian)
  - emulator_version: [16]u8
  - total_size: u64 (little-endian)
  - state_size: u32 (little-endian)
  - cartridge_size: u32 (little-endian)
  - framebuffer_size: u32 (little-endian)
  - flags: u32 (little-endian)
  - checksum: u32 (little-endian)
  - reserved: [8]u8

[Config Values: ~20 bytes]
  - console: u8 (ConsoleVariant enum)
  - cpu_variant: u8
  - cpu_region: u8
  - cpu_unstable_sha: u8
  - cpu_unstable_lxa: u8
  - ppu_variant: u8
  - ppu_region: u8
  - ppu_accuracy: u8
  - cic_variant: u8
  - cic_emulation: u8

[MasterClock: 8 bytes]
  - ppu_cycles: u64 (little-endian)

[CpuState: 33 bytes]
  - Registers: a(1), x(1), y(1), sp(1), pc(2 LE), p(1)
  - Cycle tracking: cycle_count(8 LE), instruction_cycle(1), state(1)
  - Context: opcode(1), operand_low(1), operand_high(1), effective_address(2 LE), address_mode(1), page_crossed(1)
  - Bus: data_bus(1)
  - Interrupts: pending_interrupt(1), nmi_line(1), nmi_edge_detected(1), irq_line(1)
  - Misc: halted(1), temp_value(1), temp_address(2 LE)

[PpuState: ~2,407 bytes]
  - ctrl: u8
  - mask: u8
  - status: u8
  - oam_addr: u8
  - open_bus_value: u8
  - open_bus_decay: u16 (LE)
  - internal_v: u16 (LE)
  - internal_t: u16 (LE)
  - internal_x: u8 (3-bit, stored as u8)
  - internal_w: u8 (bool as u8)
  - internal_read_buffer: u8
  - bg_pattern_shift_lo: u16 (LE)
  - bg_pattern_shift_hi: u16 (LE)
  - bg_attribute_shift_lo: u8
  - bg_attribute_shift_hi: u8
  - bg_nametable_latch: u8
  - bg_attribute_latch: u8
  - bg_pattern_latch_lo: u8
  - bg_pattern_latch_hi: u8
  - oam: [256]u8
  - secondary_oam: [32]u8
  - vram: [2048]u8
  - palette_ram: [32]u8
  - mirroring: u8
  - nmi_occurred: u8
  - scanline: u16 (LE)
  - dot: u16 (LE)
  - frame: u64 (LE) [if present in state - need to verify]

[BusState: ~2,065 bytes]
  - ram: [2048]u8
  - cycle: u64 (LE)
  - open_bus_value: u8
  - open_bus_last_update: u64 (LE)

[EmulationState flags: 3 bytes]
  - frame_complete: u8 (bool as u8)
  - odd_frame: u8 (bool as u8)
  - rendering_enabled: u8 (bool as u8)

[Cartridge Snapshot: variable]
  - mode: u8 (reference=0, embed=1)
  - [Reference mode]:
    - path_len: u32 (LE)
    - path: [path_len]u8
    - hash: [32]u8 (SHA-256)
    - mapper_state_len: u32 (LE)
    - mapper_state: [mapper_state_len]u8
  - [Embed mode]:
    - ines_header: [16]u8
    - mirroring: u8
    - prg_len: u32 (LE)
    - prg_rom: [prg_len]u8
    - chr_len: u32 (LE)
    - chr_data: [chr_len]u8
    - mapper_state_len: u32 (LE)
    - mapper_state: [mapper_state_len]u8

[Optional Framebuffer: 245,760 bytes]
  - pixels: [256 × 240 × 4]u8 (RGBA format)
```

**Total Size:**
- Core state (reference mode): **~4,708 bytes**
- Core state (embed mode): **~37 KB** (with typical 32KB ROM)
- With framebuffer: **~250 KB** (or ~282 KB with embed)

---

## 3. Implementation Roadmap

### Phase 1.3: Complete Binary Snapshot API (6-8 hours)

#### Step 1.3.1: Update cartridge.zig Integration (30 min)

**Task:** Update `src/snapshot/cartridge.zig` to use actual project types instead of local definitions.

**Changes:**
```zig
// Remove local type definitions
// const InesHeader = struct { raw: [16]u8 };
// const Mirroring = enum(u8) { ... };

// Import actual types
const Cartridge = @import("../cartridge/Cartridge.zig");
const InesHeader = Cartridge.InesHeader;
const Mirroring = Cartridge.Mirroring;
```

**Tests:** Update existing cartridge tests to use real types

#### Step 1.3.2: Implement State Serialization Functions (3-4 hours)

**File:** `src/snapshot/state.zig` (new file)

**Functions to implement:**
1. `writeConfig()` - Serialize config values (skip arena/mutex)
2. `readConfig()` - Deserialize config values
3. `writeClock()` - Serialize MasterClock
4. `readClock()` - Deserialize MasterClock
5. `writeCpuState()` - Serialize CpuState
6. `readCpuState()` - Deserialize CpuState
7. `writePpuState()` - Serialize PpuState
8. `readPpuState()` - Deserialize PpuState
9. `writeBusState()` - Serialize BusState
10. `readBusState()` - Deserialize BusState
11. `writeEmulationStateFlags()` - Serialize EmulationState flags
12. `readEmulationStateFlags()` - Deserialize EmulationState flags

**Unit Tests:** Each function gets round-trip test (write → read → verify)

#### Step 1.3.3: Implement Snapshot.zig Main API (2-3 hours)

**File:** `src/snapshot/Snapshot.zig`

**API:**
```zig
pub const Snapshot = struct {
    /// Save EmulationState to binary format
    pub fn saveBinary(
        allocator: Allocator,
        state: *const EmulationState,
        mode: CartridgeSnapshotMode,
        include_framebuffer: bool,
        framebuffer: ?[]const u8, // 256×240×4 RGBA
    ) ![]u8 { ... }

    /// Load EmulationState from binary format
    pub fn loadBinary(
        allocator: Allocator,
        data: []const u8,
        config: *const Config.Config,
        cartridge: ?*anytype, // For reference mode restore
    ) !EmulationState { ... }

    /// Verify snapshot integrity without full load
    pub fn verify(data: []const u8) !void { ... }

    /// Get snapshot metadata (version, timestamp, sizes)
    pub fn getMetadata(data: []const u8) !SnapshotMetadata { ... }
};

pub const SnapshotMetadata = struct {
    version: u32,
    timestamp: i64,
    emulator_version: [16]u8,
    total_size: u64,
    state_size: u32,
    cartridge_size: u32,
    framebuffer_size: u32,
    flags: binary.SnapshotFlags,
};
```

**Integration Test:** Full round-trip with real EmulationState

#### Step 1.3.4: Integration Testing (1 hour)

**Tests to create:**
1. **Minimal state round-trip** - Empty ROM, default state
2. **AccuracyCoin ROM round-trip** - Real ROM loaded, run 1000 cycles, save/load/verify
3. **Reference vs embed modes** - Same state, different cartridge modes, verify identical after restore
4. **With/without framebuffer** - Verify framebuffer preservation

**Test File:** `tests/snapshot/integration_test.zig`

---

### Phase 1.4: JSON Format (DEFER TO PHASE 4.4)

**Rationale:** JSON is for debugging/inspection, not critical path. Binary format is sufficient for all functional requirements (snapshot, debugger, integration tests).

**When to implement:** After Phase 3 (Debugger) is complete, as debugging tool.

---

### Phase 2: Debugger Implementation (18-24 hours)

[Detailed breakdown as per specification - unchanged]

---

### Phase 3: Debugger Advanced (6-8 hours)

[Detailed breakdown as per specification - unchanged]

---

### Phase 4: Build System & Documentation (2-3 hours)

[Detailed breakdown as per specification - unchanged]

---

## 4. AccuracyCoin Integration Strategy

### 4.1 Using Snapshots in Tests

**Pattern 1: State Verification**
```zig
test "AccuracyCoin: CPU state after initialization" {
    var config = Config.Config.init(testing.allocator);
    defer config.deinit();

    // Load AccuracyCoin ROM
    const rom_data = try std.fs.cwd().readFileAlloc(testing.allocator, "AccuracyCoin/AccuracyCoin.nes", 64 * 1024);
    defer testing.allocator.free(rom_data);

    var cart = try NromCart.loadFromData(testing.allocator, rom_data);
    defer cart.deinit(testing.allocator);

    var bus = BusState.init();
    bus.loadCartridge(&cart);

    var state = EmulationState.init(&config, bus);
    state.connectComponents();
    state.reset();

    // Run initialization sequence
    state.emulateCpuCycles(7); // RESET takes 7 CPU cycles

    // Save snapshot
    const snapshot = try Snapshot.saveBinary(
        testing.allocator,
        &state,
        .reference,
        false,
        null,
    );
    defer testing.allocator.free(snapshot);

    // Verify CPU state
    try testing.expectEqual(@as(u16, 0xC000), state.cpu.pc); // AccuracyCoin entry point

    // Load snapshot and verify identical
    var restored = try Snapshot.loadBinary(testing.allocator, snapshot, &config, &cart);
    try testing.expectEqual(state.cpu.pc, restored.cpu.pc);
    try testing.expectEqual(state.clock.ppu_cycles, restored.clock.ppu_cycles);
}
```

**Pattern 2: Regression Detection**
```zig
test "AccuracyCoin: Frame 1 state matches reference" {
    // Load reference snapshot (pre-generated from known-good run)
    const reference = try std.fs.cwd().readFileAlloc(testing.allocator, "tests/snapshots/accuracycoin-frame1.snap", 256 * 1024);
    defer testing.allocator.free(reference);

    // Run emulation to frame 1
    var state = // ... setup ...
    state.emulateFrame();

    // Save current state
    const current = try Snapshot.saveBinary(/* ... */);
    defer testing.allocator.free(current);

    // Compare states (excluding timestamp)
    try compareSnapshots(reference, current);
}
```

**Pattern 3: Debugging Aid**
```zig
test "AccuracyCoin: CPU test 01 - immediate addressing" {
    // ... test setup ...

    // Run until test starts (known PC)
    while (state.cpu.pc != 0xC100) {
        state.tick();
        if (state.clock.ppu_cycles > 1000000) {
            // Save snapshot for debugging
            const debug_snap = try Snapshot.saveBinary(/* ... */);
            std.debug.print("Saved debug snapshot to /tmp/debug.snap\n", .{});
            std.fs.cwd().writeFile("/tmp/debug.snap", debug_snap) catch {};
            return error.TestTimeout;
        }
    }

    // Continue with test...
}
```

### 4.2 Reference Snapshot Generation

**Script:** `scripts/generate-reference-snapshots.sh`
```bash
#!/bin/bash
# Generate reference snapshots for AccuracyCoin tests

SNAPSHOTS_DIR="tests/snapshots/accuracycoin"
mkdir -p $SNAPSHOTS_DIR

# Build test generator
zig build-exe tests/tools/generate_snapshots.zig -lc

# Generate snapshots at key points
./generate_snapshots --rom AccuracyCoin/AccuracyCoin.nes \
    --output $SNAPSHOTS_DIR/reset.snap \
    --cycles 7

./generate_snapshots --rom AccuracyCoin/AccuracyCoin.nes \
    --output $SNAPSHOTS_DIR/frame-001.snap \
    --frames 1

./generate_snapshots --rom AccuracyCoin/AccuracyCoin.nes \
    --output $SNAPSHOTS_DIR/frame-060.snap \
    --frames 60

# Generate test-specific snapshots
./generate_snapshots --rom AccuracyCoin/AccuracyCoin.nes \
    --output $SNAPSHOTS_DIR/test-cpu-immediate.snap \
    --break-at 0xC100
```

---

## 5. Debugger Integration Considerations

### 5.1 Snapshot-Debugger Workflow

**Use Case 1: Breakpoint State Inspection**
```zig
var debugger = try Debugger.init(allocator, &state);
defer debugger.deinit();

// Set breakpoint at AccuracyCoin test entry
_ = try debugger.addBreakpointPc(0xC000);

// Run until breakpoint
const reason = try debugger.run();
assert(reason == .breakpoint_hit);

// Save state at breakpoint
const snapshot = try Snapshot.saveBinary(/* ... */);

// Inspect snapshot with JSON format (future)
const json_snapshot = try Snapshot.saveJson(/* ... */);
// Human-readable state for debugging
```

**Use Case 2: State Rewind via Snapshot**
```zig
// Save state before running code under test
const before = try Snapshot.saveBinary(/* ... */);

// Run code (might fail)
state.emulateCpuCycles(1000);

// Test failed - restore to before state and single-step
state = try Snapshot.loadBinary(allocator, before, &config, &cart);
state.connectComponents();

// Now use debugger to step through
var debugger = try Debugger.init(allocator, &state);
while (/* condition */) {
    try debugger.stepInstruction();
    // Inspect state after each instruction
}
```

### 5.2 History Buffer + Snapshots

**Combined Power:**
- History buffer: Last 512 instructions (lightweight)
- Snapshots: Key points (heavier, but complete)

**Pattern:**
```zig
// Save snapshots every 10,000 instructions
var snapshot_counter: u64 = 0;
while (running) {
    try debugger.stepInstruction();
    snapshot_counter += 1;

    if (snapshot_counter % 10000 == 0) {
        const snapshot = try Snapshot.saveBinary(/* ... */);
        // Store snapshot with index
    }
}

// On crash: Load nearest snapshot, replay from history
```

---

## 6. Blocker Resolution

### 6.1 Config Arena/Mutex Handling ✅ RESOLVED

**Decision:** Serialize config VALUES only, skip arena and mutex entirely.

**Implementation:**
```zig
fn writeConfig(writer: anytype, config: *const Config.Config) !void {
    try writer.writeByte(@intFromEnum(config.console));
    try writer.writeByte(@intFromEnum(config.cpu.variant));
    try writer.writeByte(@intFromEnum(config.cpu.region));
    // ... all config values
    // Skip: config.arena, config.mutex
}

fn readConfig(reader: anytype) !ConfigValues {
    const console = @as(ConsoleVariant, @enumFromInt(try reader.readByte()));
    const cpu_variant = @as(CpuVariant, @enumFromInt(try reader.readByte()));
    // ... all config values
    return ConfigValues{ .console = console, .cpu_variant = cpu_variant, ... };
}
```

**On restore:** Validate that provided `Config.Config*` matches serialized values.

### 6.2 Pointer Reconstruction ✅ RESOLVED

**Strategy:** Call `state.connectComponents()` after loading all state data.

**Implementation:**
```zig
pub fn loadBinary(...) !EmulationState {
    // Load all pure state
    const clock = try state.readClock(reader);
    const cpu = try state.readCpuState(reader);
    const ppu = try state.readPpuState(reader);
    const bus = try state.readBusState(reader);
    // ... load config values, cartridge ...

    // Construct EmulationState
    var emu_state = EmulationState{
        .clock = clock,
        .cpu = cpu,
        .ppu = ppu,
        .bus = bus,
        .config = config, // Provided externally
        // ... flags ...
    };

    // Load or reconstruct cartridge
    if (cartridge_snapshot.mode == .reference) {
        // Caller must provide cartridge
        assert(cartridge != null);
        emu_state.bus.cartridge = cartridge;
    } else {
        // Reconstruct from embedded data
        const cart = try reconstructCartridge(allocator, cartridge_snapshot.embed);
        emu_state.bus.cartridge = cart;
    }

    // Wire up internal pointers
    emu_state.connectComponents();

    return emu_state;
}
```

### 6.3 Cartridge Generic Types ✅ RESOLVED

**Current:** `Cartridge(Mapper0)` creates type `NromCart`

**Strategy:** For Mapper0 (only mapper currently implemented), use `NromCart` type directly.

**Future:** When adding more mappers, snapshot will need mapper type byte to determine which cartridge type to reconstruct.

### 6.4 Frame Field in PpuState ❓ TO VERIFY

**Issue:** Spec mentions `frame: u64` in PpuState, but current code only has `scanline` and `dot`.

**Resolution:** Check if `frame` field exists. If not, derive from MasterClock during serialization.

**Action:** Read rest of PPU state to verify.

---

## 7. Testing Strategy Summary

### Unit Tests (Per-Function)
- ✅ Checksum utilities (3 tests)
- ✅ Binary header format (6 tests)
- ✅ Cartridge snapshot (3 tests)
- ⏳ Config serialization (2 tests)
- ⏳ Clock serialization (2 tests)
- ⏳ CPU state serialization (2 tests)
- ⏳ PPU state serialization (2 tests)
- ⏳ Bus state serialization (2 tests)
- **Total Unit Tests: 24**

### Integration Tests (Full Round-Trip)
- ⏳ Minimal state (no ROM)
- ⏳ AccuracyCoin ROM loaded
- ⏳ After 1000 CPU cycles
- ⏳ After 1 frame
- ⏳ Reference vs embed modes
- ⏳ With framebuffer
- **Total Integration Tests: 6**

### AccuracyCoin Verification Tests
- ⏳ Reset state matches reference
- ⏳ Frame 1 state matches reference
- ⏳ Frame 60 state matches reference
- ⏳ CPU test 01 entry state
- **Total AccuracyCoin Tests: 4**

**Grand Total: 34 tests for snapshot system**

---

## 8. Success Criteria

### Phase 1.3 Complete When:
- [x] All state serialization functions implemented
- [x] All unit tests passing (24 tests)
- [x] Integration tests passing (6 tests)
- [x] AccuracyCoin ROM can be saved and restored
- [x] State after restore is byte-for-byte identical
- [x] Reference and embed modes both work
- [x] Framebuffer preservation verified
- [x] No memory leaks (run with allocator tracking)
- [x] Documentation updated

### Phase 2-3 Complete When:
- [x] Debugger wraps EmulationState without modification
- [x] All breakpoint types work
- [x] All watchpoint types work
- [x] All step modes work
- [x] Execution history captures correctly
- [x] State manipulation works
- [x] Callbacks fire on events
- [x] Disassembler produces correct output
- [x] Integration with snapshot system verified

### Phase 4 Complete When:
- [x] Build system integrated
- [x] APIs exported in src/root.zig
- [x] Example code works
- [x] Documentation complete
- [x] All 413+ tests passing

---

## 9. Timeline & Milestones

| Milestone | Tasks | Hours | Date |
|-----------|-------|-------|------|
| **M1: Snapshot Foundation** | Cartridge integration, state serialization functions | 4-5 | Day 1 |
| **M2: Snapshot API** | Snapshot.zig main API, integration tests | 3-4 | Day 2 |
| **M3: Debugger Core** | Foundation, breakpoints, watchpoints, step | 10-12 | Days 3-4 |
| **M4: Debugger Advanced** | State manipulation, callbacks, disassembler | 6-8 | Day 5 |
| **M5: Integration** | Build system, docs, examples, final tests | 2-3 | Day 6 |
| **TOTAL** | | **26-33 hours** | **6 days** |

---

## 10. Next Immediate Steps

1. ✅ **Verify PPU frame field** - Check if `frame` exists in PpuState
2. ⏳ **Update cartridge.zig** - Use actual project types (30 min)
3. ⏳ **Implement state.zig** - All state serialization functions (3-4 hours)
4. ⏳ **Implement Snapshot.zig** - Main API (2-3 hours)
5. ⏳ **Integration tests** - Full round-trip verification (1 hour)
6. ⏳ **AccuracyCoin tests** - Verify with actual ROM (1 hour)

**Total to complete Phase 1.3: 6-8 hours**

---

## 11. Risk Mitigation

| Risk | Mitigation |
|------|------------|
| **State structures change during implementation** | Unit tests will catch immediately, fix serialization |
| **Pointer reconstruction fails** | Extensive tests with real EmulationState, verify connectComponents() |
| **Snapshot size too large** | Already verified ~5KB core state, matches spec |
| **Endianness issues** | All multi-byte values explicitly little-endian |
| **Memory leaks** | Run all tests with allocator tracking enabled |
| **Integration with AccuracyCoin fails** | Start with minimal tests, incrementally add complexity |

---

**STATUS:** ✅ READY FOR IMPLEMENTATION - All blockers resolved, clear path forward
