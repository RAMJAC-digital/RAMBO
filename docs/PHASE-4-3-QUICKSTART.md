# Phase 4.3: Quick Start Implementation Guide

**For developers starting Phase 4.3 implementation**

This guide provides the fastest path from specification to working code. Start here if you want to begin implementing immediately.

---

## ⚡ Quick Start Checklist

### Before You Begin

- [ ] Read [PHASE-4-3-INDEX.md](./PHASE-4-3-INDEX.md) - 5 min overview
- [ ] Skim [PHASE-4-3-SUMMARY.md](./PHASE-4-3-SUMMARY.md) - 10 min quick reference
- [ ] Review [PHASE-4-3-ARCHITECTURE.md](./PHASE-4-3-ARCHITECTURE.md) diagrams - 15 min visual understanding
- [ ] Keep [PHASE-4-3-SNAPSHOT-DEBUGGER-SPEC.md](./PHASE-4-3-SNAPSHOT-DEBUGGER-SPEC.md) open for detailed reference

**Total prep time: ~30 minutes**

---

## 🚀 Implementation Order

Follow this exact order for fastest progress with minimal blockers:

### Phase 1: Snapshot System (Day 1-2, 8-10 hours)

#### Step 1.1: Binary Serialization Core (3-4 hours)

**Create files:**
```bash
mkdir -p src/snapshot tests/snapshot
touch src/snapshot/Snapshot.zig
touch src/snapshot/binary.zig
touch src/snapshot/checksum.zig
touch tests/snapshot/binary_test.zig
```

**Implement (in order):**

1. `src/snapshot/binary.zig` - Basic types
   ```zig
   pub const SnapshotHeader = packed struct {
       magic: [8]u8 = "RAMBO\x00\x00\x00".*,
       version: u32,
       timestamp: i64,
       // ... (see spec Section 2.2)
   };
   ```

2. `src/snapshot/checksum.zig` - CRC32
   ```zig
   pub fn calculate(data: []const u8) u32 {
       return std.crypto.hash.crc32(data);
   }
   ```

3. `src/snapshot/binary.zig` - Write functions
   - `writeHeader()`
   - `writeConfig()`
   - `writeState()`
   - Use spec Section 2.2 for exact format

4. `tests/snapshot/binary_test.zig` - Basic tests
   ```zig
   test "Binary: write and verify header" {
       // Test header writing
   }
   ```

**Validation:** Header can be written and checksum verified

#### Step 1.2: Cartridge Handling (2-3 hours)

**Create files:**
```bash
touch src/snapshot/cartridge.zig
touch tests/snapshot/cartridge_test.zig
```

**Implement (in order):**

1. `src/snapshot/cartridge.zig` - Cartridge snapshot types
   ```zig
   pub const CartridgeSnapshotMode = enum {
       reference,
       embed,
   };

   pub const CartridgeSnapshot = union(CartridgeSnapshotMode) {
       // ... (see spec Section 2.3)
   };
   ```

2. Reference mode implementation
   - Store ROM path
   - Calculate SHA-256 hash
   - Serialize to binary

3. Embed mode implementation
   - Store iNES header
   - Store PRG ROM data
   - Store CHR data
   - Store mapper state (placeholder for now)

**Validation:** Cartridge data can be saved in both modes

#### Step 1.3: Complete Binary Save/Load (2-3 hours)

**Update files:**
```bash
# src/snapshot/Snapshot.zig - Main API
# src/snapshot/binary.zig - Read functions
```

**Implement (in order):**

1. Complete `binary.zig` read functions
   - `readHeader()`
   - `readConfig()`
   - `readState()`

2. Complete `Snapshot.zig` API
   ```zig
   pub fn saveBinary(...) ![]u8 {
       // Allocate buffer
       // Write header
       // Write config
       // Write state
       // Write cartridge
       // Calculate checksum
       // Return buffer
   }

   pub fn loadBinary(...) !EmulationState {
       // Verify header
       // Parse config
       // Parse state
       // Parse cartridge
       // Reconstruct EmulationState
       // Call connectComponents()
       // Return state
   }
   ```

3. Write comprehensive tests
   ```zig
   test "Snapshot: binary round-trip" {
       // Create state
       // Save binary
       // Load binary
       // Verify identical
   }
   ```

**Validation:** Complete binary round-trip works (save → load → identical state)

#### Step 1.4: JSON Format (2-3 hours)

**Create files:**
```bash
touch src/snapshot/json.zig
touch tests/snapshot/json_test.zig
```

**Implement (in order):**

1. JSON schema types (see spec Section 2.4)
   ```zig
   const SnapshotJson = struct {
       version: u32,
       timestamp: []const u8,
       emulator_version: []const u8,
       config: ConfigJson,
       clock: ClockJson,
       cpu: CpuJson,
       ppu: PpuJson,
       bus: BusJson,
       cartridge: CartridgeJson,
   };
   ```

2. Serialization functions
   - Use `std.json.stringify()`
   - Base64 encode binary data (RAM, VRAM, etc.)

3. Deserialization functions
   - Use `std.json.parseFromSlice()`
   - Base64 decode binary data

4. Update `Snapshot.zig` with JSON API
   ```zig
   pub fn saveJson(...) ![]u8 { /* ... */ }
   pub fn loadJson(...) !EmulationState { /* ... */ }
   ```

**Validation:** JSON round-trip works, human-readable output verified

---

### Phase 2: Debugger Core (Day 3-4, 10-12 hours)

#### Step 2.1: Debugger Foundation (2-3 hours)

**Create files:**
```bash
mkdir -p src/debugger tests/debugger
touch src/debugger/Debugger.zig
touch tests/debugger/debugger_test.zig
```

**Implement (in order):**

1. Basic `Debugger` struct (see spec Section 3.1)
   ```zig
   pub const Debugger = struct {
       state: *EmulationState,
       allocator: std.mem.Allocator,
       breakpoints: BreakpointManager,
       watchpoints: WatchpointManager,
       history: ExecutionHistory,
       step_mode: StepMode,
       callbacks: CallbackManager,

       pub fn init(allocator: Allocator, state: *EmulationState) !Debugger {
           // Initialize all managers
       }

       pub fn deinit(self: *Debugger) void {
           // Cleanup all managers
       }
   };
   ```

2. Basic run loop (without breakpoints)
   ```zig
   pub fn run(self: *Debugger) !DebugStopReason {
       while (true) {
           self.state.tick();
           // Check conditions
           // Return when stop condition met
       }
   }
   ```

**Validation:** Debugger can wrap state and run emulation

#### Step 2.2: Breakpoint System (3-4 hours)

**Create files:**
```bash
touch src/debugger/breakpoints.zig
touch tests/debugger/breakpoint_test.zig
```

**Implement (in order):**

1. Breakpoint types (see spec Section 3.2)
   ```zig
   pub const Breakpoint = struct {
       id: u32,
       type: BreakpointType,
       enabled: bool,
       hit_count: u64,
       condition: BreakpointCondition,
   };
   ```

2. BreakpointManager
   ```zig
   pub const BreakpointManager = struct {
       breakpoints: ArrayList(Breakpoint),
       next_id: u32,

       pub fn add(self: *Self, condition: BreakpointCondition) !u32 { /* ... */ }
       pub fn remove(self: *Self, id: u32) !void { /* ... */ }
       pub fn check(self: *Self, state: *const EmulationState) ?u32 { /* ... */ }
   };
   ```

3. Integrate with Debugger.run()
   ```zig
   pub fn run(self: *Debugger) !DebugStopReason {
       while (true) {
           // Check breakpoints BEFORE tick
           if (self.breakpoints.check(self.state)) |bp_id| {
               return .breakpoint;
           }
           self.state.tick();
       }
   }
   ```

4. Add convenience methods to Debugger
   ```zig
   pub fn addBreakpointPc(self: *Debugger, address: u16) !u32 { /* ... */ }
   pub fn addBreakpointOpcode(self: *Debugger, opcode: u8) !u32 { /* ... */ }
   ```

**Validation:** PC and opcode breakpoints work correctly

#### Step 2.3: Watchpoint System (2-3 hours)

**Create files:**
```bash
touch src/debugger/watchpoints.zig
touch tests/debugger/watchpoint_test.zig
```

**Implement (in order):**

1. Watchpoint types (see spec Section 3.3)
   ```zig
   pub const Watchpoint = struct {
       id: u32,
       type: WatchpointType,
       address_range: AddressRange,
       enabled: bool,
       hit_count: u64,
       log_access: bool,
   };
   ```

2. WatchpointManager (similar to BreakpointManager)

3. Integrate with Debugger (check AFTER tick for memory access)

**Validation:** Memory watchpoints trigger correctly

#### Step 2.4: Step Execution (2-3 hours)

**Implement (in order):**

1. Step modes (see spec Section 3.4)
   ```zig
   pub const StepMode = enum {
       none, instruction, cycle_cpu, cycle_ppu, scanline, frame, until_pc, until_scanline,
   };
   ```

2. Step functions in Debugger
   ```zig
   pub fn stepInstruction(self: *Debugger) !void {
       self.step_mode = .instruction;
       const initial_pc = self.state.cpu.pc;
       while (self.state.cpu.pc == initial_pc or self.state.cpu.state != .fetch_opcode) {
           self.state.tick();
       }
   }

   pub fn stepCpuCycle(self: *Debugger) !void {
       // Tick 3 PPU cycles (1 CPU cycle)
       self.state.tick();
       self.state.tick();
       self.state.tick();
   }

   pub fn stepPpuCycle(self: *Debugger) !void {
       self.state.tick();  // 1 PPU cycle
   }
   ```

**Validation:** All step modes work correctly

#### Step 2.5: Execution History (1 hour)

**Create files:**
```bash
touch src/debugger/history.zig
touch tests/debugger/history_test.zig
```

**Implement (in order):**

1. History entry (see spec Section 3.5)
   ```zig
   pub const ExecutionHistoryEntry = struct {
       cycle: u64,
       pc: u16,
       opcode: u8,
       a: u8, x: u8, y: u8, sp: u8, p: u8,
       scanline: u16,
       dot: u16,
   };
   ```

2. Circular buffer
   ```zig
   pub const ExecutionHistory = struct {
       entries: []ExecutionHistoryEntry,
       capacity: usize,
       write_index: usize,
       count: usize,

       pub fn push(self: *Self, entry: ExecutionHistoryEntry) void { /* ... */ }
       pub fn get(self: *const Self, index: usize) ?ExecutionHistoryEntry { /* ... */ }
   };
   ```

3. Integrate with Debugger (push after each instruction)

**Validation:** History captures recent instructions correctly

---

### Phase 3: Debugger Advanced (Day 5, 6-8 hours)

#### Step 3.1: State Manipulation (2-3 hours)

**Implement in Debugger.zig:**

```zig
pub fn setCpuRegister(self: *Debugger, register: CpuRegister, value: u16) !void {
    switch (register) {
        .a => self.state.cpu.a = @truncate(value),
        .x => self.state.cpu.x = @truncate(value),
        .y => self.state.cpu.y = @truncate(value),
        .sp => self.state.cpu.sp = @truncate(value),
        .pc => self.state.cpu.pc = value,
    }
}

pub fn setCpuPc(self: *Debugger, pc: u16) void {
    self.state.cpu.pc = pc;
}

pub fn writeMemory(self: *Debugger, address: u16, value: u8) void {
    self.state.bus.write(address, value);
}

pub fn readMemory(self: *const Debugger, address: u16) u8 {
    return self.state.bus.read(address);
}
```

**Validation:** State can be modified and persists

#### Step 3.2: Callback System (2-3 hours)

**Create files:**
```bash
touch src/debugger/callbacks.zig
touch tests/debugger/callback_test.zig
```

**Implement (in order):**

1. Callback types (see spec Section 3.6)
   ```zig
   pub const DebugCallback = *const fn(
       event: DebugEvent,
       context: ?*anyopaque,
       state: *const EmulationState
   ) void;
   ```

2. CallbackManager
   ```zig
   pub const CallbackManager = struct {
       callbacks: ArrayList(CallbackEntry),

       pub fn register(self: *Self, event: DebugEvent, callback: DebugCallback, context: ?*anyopaque) !void { /* ... */ }
       pub fn trigger(self: *Self, event: DebugEvent, state: *const EmulationState) void { /* ... */ }
   };
   ```

3. Integrate with Debugger (trigger on breakpoints, watchpoints, etc.)

**Validation:** Callbacks fire on events

#### Step 3.3: Disassembler (2-3 hours)

**Create files:**
```bash
touch src/debugger/disassembler.zig
touch tests/debugger/disassembler_test.zig
```

**Implement (in order):**

1. Disassembled instruction type (see spec Section 4.3)
   ```zig
   pub const DisassembledInstruction = struct {
       address: u16,
       opcode: u8,
       mnemonic: []const u8,
       operand: ?[]const u8,
       bytes: [3]u8,
       length: u8,
       cycles: u8,
       mode: AddressingMode,
   };
   ```

2. Opcode lookup table (reuse from cpu/opcodes.zig)

3. Disassembly functions
   ```zig
   pub fn disassemble(state: *const EmulationState, address: u16) !DisassembledInstruction {
       const opcode = state.bus.read(address);
       const info = opcodes.OPCODE_TABLE[opcode];
       // Build DisassembledInstruction from opcode info
   }
   ```

**Validation:** Instructions disassemble correctly with operands

---

### Phase 4: Documentation & Polish (Day 6, 2-3 hours)

#### Step 4.1: Build System Integration

**Update build.zig:**

```zig
// Add snapshot module
const snapshot_module = b.addModule("snapshot", .{
    .root_source_file = .{ .path = "src/snapshot/Snapshot.zig" },
});

// Add debugger module
const debugger_module = b.addModule("debugger", .{
    .root_source_file = .{ .path = "src/debugger/Debugger.zig" },
});

// Add snapshot tests
const snapshot_tests = b.addTest(.{
    .root_source_file = .{ .path = "src/snapshot/Snapshot.zig" },
    .target = target,
    .optimize = optimize,
});

// Add debugger tests
const debugger_tests = b.addTest(.{
    .root_source_file = .{ .path = "src/debugger/Debugger.zig" },
    .target = target,
    .optimize = optimize,
});

const test_snapshot_step = b.step("test-snapshot", "Run snapshot tests");
test_snapshot_step.dependOn(&b.addRunArtifact(snapshot_tests).step);

const test_debugger_step = b.step("test-debugger", "Run debugger tests");
test_debugger_step.dependOn(&b.addRunArtifact(debugger_tests).step);
```

**Verify:**
```bash
zig build test-snapshot
zig build test-debugger
```

#### Step 4.2: Export APIs

**Update src/root.zig:**

```zig
pub const Snapshot = @import("snapshot/Snapshot.zig");
pub const Debugger = @import("debugger/Debugger.zig");
```

#### Step 4.3: Example Code

Create `examples/snapshot_demo.zig`:
```zig
// See spec Appendix B for complete example
```

Create `examples/debugger_demo.zig`:
```zig
// See spec Appendix B for complete example
```

---

## 🧪 Testing Strategy

### Quick Test Script

Create `scripts/test-phase-4-3.sh`:

```bash
#!/bin/bash

echo "Testing Phase 4.3 Implementation..."

# Test snapshot system
echo "→ Testing snapshot binary round-trip..."
zig build test-snapshot --summary all

# Test debugger system
echo "→ Testing debugger functionality..."
zig build test-debugger --summary all

# Integration test
echo "→ Testing snapshot + debugger integration..."
zig build test-integration --summary all

echo "✅ All Phase 4.3 tests complete"
```

### Validation Checklist

After each phase, verify:

**Phase 1 (Snapshot):**
- [ ] Binary round-trip: save → load → identical
- [ ] JSON round-trip: save → load → identical
- [ ] Cartridge reference mode works
- [ ] Cartridge embed mode works
- [ ] Checksum detects corruption
- [ ] All component state preserved

**Phase 2 (Debugger Core):**
- [ ] Debugger wraps state without modification
- [ ] PC breakpoints trigger correctly
- [ ] Opcode breakpoints trigger correctly
- [ ] Memory breakpoints trigger correctly
- [ ] Watchpoints detect reads/writes
- [ ] Step instruction advances correctly
- [ ] Step cycle advances correctly
- [ ] History captures instructions

**Phase 3 (Debugger Advanced):**
- [ ] Registers can be modified
- [ ] Memory can be modified
- [ ] Callbacks fire on events
- [ ] Disassembler produces correct output

---

## 📋 Common Pitfalls & Solutions

### Pitfall 1: Config Serialization
**Problem:** Trying to serialize Config.arena or Config.mutex
**Solution:** Only serialize config values (enums, ints, bools). Skip arena and mutex entirely.

### Pitfall 2: Pointer Reconstruction
**Problem:** Snapshot contains invalid pointers after load
**Solution:** All pointers (config, cartridge, ppu) provided externally, then call `state.connectComponents()`

### Pitfall 3: Endianness
**Problem:** Snapshot loads incorrectly on different platforms
**Solution:** Always write multi-byte values in little-endian format (see spec Section 8.2)

### Pitfall 4: Breakpoint Timing
**Problem:** Breakpoints checked after instruction executes
**Solution:** Check breakpoints BEFORE calling `state.tick()`

### Pitfall 5: History Buffer Overflow
**Problem:** History buffer grows without bound
**Solution:** Use circular buffer with fixed capacity (512 entries recommended)

---

## 🔍 Debug Tips

### Snapshot Debugging

```zig
// Enable verbose logging
const log = std.log.scoped(.snapshot);

// In binary.zig
log.debug("Writing header: magic={s}, version={}, size={}", .{
    header.magic,
    header.version,
    header.total_size,
});

// Verify state equality
fn stateEquals(a: *const EmulationState, b: *const EmulationState) bool {
    if (a.clock.ppu_cycles != b.clock.ppu_cycles) {
        log.err("Clock mismatch: {} != {}", .{a.clock.ppu_cycles, b.clock.ppu_cycles});
        return false;
    }
    // ... check all fields
}
```

### Debugger Debugging

```zig
// Log breakpoint checks
log.debug("Checking breakpoint: PC=0x{X:0>4}, expected=0x{X:0>4}", .{
    state.cpu.pc,
    breakpoint.condition.pc,
});

// Log step execution
log.debug("Step instruction: initial_pc=0x{X:0>4}, state={s}", .{
    initial_pc,
    @tagName(state.cpu.state),
});
```

---

## ✅ Success Verification

After completing all phases:

1. **Run full test suite:**
   ```bash
   zig build test
   zig build test-snapshot
   zig build test-debugger
   zig build test-integration
   ```

2. **Verify snapshot round-trip:**
   ```bash
   zig build run
   # Save state, load state, verify identical
   ```

3. **Verify debugger functionality:**
   ```bash
   # Run examples/debugger_demo.zig
   # Set breakpoints, step through code, inspect state
   ```

4. **Check performance:**
   - Binary snapshot save/load: <10ms
   - JSON snapshot save/load: <50ms
   - Debugger overhead: <1μs per instruction

5. **Review code quality:**
   - [ ] All functions documented
   - [ ] All public APIs have tests
   - [ ] No memory leaks (run with allocator tracking)
   - [ ] No undefined behavior (run with sanitizers)

---

## 📚 Reference Documents

Keep these open while implementing:

1. **[PHASE-4-3-SNAPSHOT-DEBUGGER-SPEC.md](./PHASE-4-3-SNAPSHOT-DEBUGGER-SPEC.md)** - Detailed API specs
2. **[PHASE-4-3-ARCHITECTURE.md](./PHASE-4-3-ARCHITECTURE.md)** - Visual diagrams
3. **[PHASE-4-3-SUMMARY.md](./PHASE-4-3-SUMMARY.md)** - Quick API reference

---

## 🎯 Next Steps After Completion

Once Phase 4.3 is complete:

1. **Integration with Phase 4.1/4.2** (Sprite rendering)
   - Use snapshot to save/load states during sprite testing
   - Use debugger to step through sprite rendering logic

2. **Integration with Phase 4.4** (Video display)
   - Snapshot framebuffer for display testing
   - Debug rendering pipeline with breakpoints

3. **Future Enhancements**
   - Movie recording (snapshot sequence)
   - Rewind functionality
   - Network debugging protocol
   - Visual debugger UI

---

**Good luck with implementation! All design decisions are made, all questions are answered, and the path is clear. Follow this guide and you'll have a working snapshot + debugger system in 26-33 hours.**

**Need help?** Reference the full specification or architecture docs for detailed information on any topic.
