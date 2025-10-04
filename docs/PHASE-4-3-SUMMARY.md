# Phase 4.3: Snapshot + Debugger System - Executive Summary

**Status:** ✅ Design Complete - Ready for Implementation
**Full Spec:** [PHASE-4-3-SNAPSHOT-DEBUGGER-SPEC.md](./PHASE-4-3-SNAPSHOT-DEBUGGER-SPEC.md)

---

## Quick Reference

### Size Estimates

**State Snapshot Sizes:**
- Core state (no framebuffer): **~5 KB**
- With framebuffer (256×240×4): **~250 KB**
- Full cartridge embed (typical): **+32 KB**
- JSON format overhead: **~160% of binary** (Base64 encoding)

### Implementation Effort

**Total Estimated Time: 26-33 hours**

| Phase | Tasks | Time |
|-------|-------|------|
| Phase 1: Snapshot System | Binary/JSON serialization, cartridge handling | 8-10 hours |
| Phase 2: Debugger Core | Breakpoints, watchpoints, step execution | 10-12 hours |
| Phase 3: Debugger Advanced | State manipulation, callbacks, disassembly | 6-8 hours |
| Phase 4: Documentation | User docs, examples, API reference | 2-3 hours |

---

## Architecture Overview

### Snapshot System

**Two Formats:**

1. **Binary (Production)** - Compact, ~500KB with framebuffer
   - Little-endian for cross-platform compatibility
   - CRC32 checksum for integrity validation
   - Versioned header for future compatibility

2. **JSON (Debugging)** - Human-readable, ~800KB with framebuffer
   - Schema versioned for compatibility
   - Base64 encoding for binary data (RAM, VRAM, etc.)
   - Easy to inspect and diff

**Cartridge Handling:**

- **Reference Mode** (recommended): Store ROM path/hash only (~5KB snapshots)
- **Embed Mode** (portable): Store full ROM data (~40KB snapshots)

### Debugger System

**External Wrapper Pattern:**
- Wraps `EmulationState` without modifying it
- No allocator in core state (maintains purity)
- State/Logic separation preserved

**Features:**

1. **Breakpoints**
   - PC breakpoints
   - Opcode breakpoints
   - Memory read/write breakpoints
   - Conditional breakpoints (register values, flags)

2. **Watchpoints**
   - Memory read/write/access watchpoints
   - Address range support
   - Hit count tracking

3. **Step Execution**
   - Step one CPU instruction
   - Step one CPU cycle
   - Step one PPU cycle
   - Step one scanline
   - Step one frame
   - Run until PC/scanline

4. **Execution History**
   - Circular buffer (512 entries recommended)
   - Captures PC, registers, scanline, dot per instruction
   - ~16KB memory overhead

5. **State Manipulation**
   - Modify CPU registers
   - Modify memory
   - Set PC directly

6. **Event Callbacks**
   - Breakpoint hit
   - Watchpoint hit
   - Step complete
   - Frame complete
   - NMI/IRQ triggered

---

## Critical Design Decisions

### ✅ Resolved Questions

1. **Config.Config owns ArenaAllocator**
   - **Solution:** Serialize config values only, skip arena/mutex, provide config externally on restore

2. **Cartridge ROM data handling**
   - **Solution:** Two modes - reference (path/hash) and embed (full data)

3. **Binary format endianness**
   - **Solution:** Little-endian for cross-platform compatibility

4. **JSON schema versioning**
   - **Solution:** Schema version in JSON root, migration support for old versions

5. **Framebuffer inclusion**
   - **Solution:** Optional - flag in header determines presence

### ⚠️ Implementation Decisions (To Be Made)

1. **Execution history buffer size?**
   - Recommendation: 512 entries (~16KB) - covers typical debug scenarios

2. **Snapshot compression?**
   - Recommendation: Start without compression, add later if needed

3. **Mapper state serialization?**
   - Recommendation: Generic `getState()`/`setState()` interface for all mappers

4. **Breakpoint expression language?**
   - Recommendation: Start with simple conditions, add expressions in Phase 5

---

## File Organization

### New Files to Create

```
src/snapshot/
├── Snapshot.zig          # Main API (300 lines)
├── binary.zig            # Binary serialization (400 lines)
├── json.zig              # JSON serialization (300 lines)
├── cartridge.zig         # Cartridge snapshot (200 lines)
└── checksum.zig          # CRC32 utilities (100 lines)

src/debugger/
├── Debugger.zig          # Main API (400 lines)
├── breakpoints.zig       # Breakpoint manager (250 lines)
├── watchpoints.zig       # Watchpoint manager (200 lines)
├── history.zig           # Execution history (150 lines)
├── callbacks.zig         # Callback system (150 lines)
└── disassembler.zig      # Disassembly (300 lines)
```

**Estimated Total:** ~3,500 lines (excluding tests)

---

## API Quick Reference

### Snapshot API

```zig
// Save state to binary format
const snapshot = try Snapshot.saveBinary(
    allocator,
    &state,
    &config,
    null,  // cartridge (optional)
    .reference,  // cartridge mode
    null,  // framebuffer (optional)
);

// Load state from binary format
var restored = try Snapshot.loadBinary(
    allocator,
    snapshot_data,
    &config,
    null,  // cartridge (optional)
);

// JSON variants
const json_snapshot = try Snapshot.saveJson(...);
var restored_json = try Snapshot.loadJson(...);

// Verify integrity
try Snapshot.verify(snapshot_data);

// Get metadata without full load
const metadata = try Snapshot.getMetadata(snapshot_data);
```

### Debugger API

```zig
// Initialize debugger
var debugger = try Debugger.init(allocator, &state);
defer debugger.deinit();

// Add breakpoints
const bp_id = try debugger.addBreakpointPc(0x8000);
try debugger.addBreakpointOpcode(0x00);  // BRK
try debugger.addBreakpointWrite(0x2000);  // PPU_CTRL

// Add watchpoints
const wp_id = try debugger.addWatchpoint(.write, 0x2000, 0x2007);

// Execution control
const reason = try debugger.run();  // Run until breakpoint
try debugger.stepInstruction();
try debugger.stepCpuCycle();
try debugger.stepFrame();
try debugger.runUntilPc(0x8100);

// State inspection
const cpu = debugger.getCpuState();
const value = debugger.readMemory(0x8000);
const history = debugger.getRecentInstructions(10);

// State manipulation
try debugger.setCpuRegister(.a, 0x42);
debugger.setCpuPc(0x8000);
debugger.writeMemory(0x0200, 0xFF);

// Event callbacks
try debugger.onEvent(.breakpoint_hit, callback_fn, context);
```

### Disassembler API

```zig
// Disassemble single instruction
const instr = try Disassembler.disassemble(&state, 0x8000);

// Disassemble range
const instructions = try Disassembler.disassembleRange(
    allocator,
    &state,
    0x8000,
    10,  // count
);
defer allocator.free(instructions);

for (instructions) |instr| {
    std.debug.print("${X:0>4}: {s} {s}\n", .{
        instr.address,
        instr.mnemonic,
        instr.operand orelse "",
    });
}
```

---

## Conflict Analysis

### ✅ No Conflicts Detected

**EmulationState Purity:**
- ✅ No allocator added to EmulationState
- ✅ No hidden state introduced
- ✅ State/Logic separation preserved
- ✅ All snapshot/debug state is external

**Architecture Compatibility:**
- ✅ External wrapper pattern (Debugger wraps EmulationState)
- ✅ Config handled correctly (values serialized, arena/mutex skipped)
- ✅ Cartridge handled correctly (reference or embed modes)
- ✅ Pointers reconstructed externally via `connectComponents()`

**RT-Safety:**
- ✅ Snapshot/debugger are non-RT tools (offline usage only)
- ✅ No blocking operations in `EmulationState.tick()`
- ✅ No mutexes or locks in core emulation

---

## Dependencies

**No new external dependencies required!**

All functionality uses existing Zig standard library:
- `std.json` - JSON serialization
- `std.base64` - Base64 encoding for JSON
- `std.crypto.hash.crc32` - Checksum
- `std.ArrayList` - Dynamic arrays

---

## Test Strategy

### Snapshot Tests

- ✅ Binary round-trip (save + load = identical state)
- ✅ JSON round-trip (save + load = identical state)
- ✅ Cartridge reference mode (ROM path/hash)
- ✅ Cartridge embed mode (full ROM data)
- ✅ With/without framebuffer
- ✅ Checksum validation (detect corruption)
- ✅ Cross-version compatibility

### Debugger Tests

- ✅ PC breakpoints
- ✅ Opcode breakpoints
- ✅ Memory read/write breakpoints
- ✅ Watchpoints (read/write/access)
- ✅ Step execution (instruction/cycle/scanline/frame)
- ✅ Execution history (circular buffer)
- ✅ State manipulation (registers/memory)
- ✅ Event callbacks

### Integration Tests

- ✅ Complete snapshot cycle (save binary + JSON, load both, verify identical)
- ✅ Debugger with snapshots (breakpoint → save → continue → restore)
- ✅ Cartridge state preservation (mapper state across snapshot/restore)

---

## Success Criteria

### Functional Requirements

**Snapshot System:**
- [ ] Save/load EmulationState to binary format
- [ ] Save/load EmulationState to JSON format
- [ ] Support cartridge reference mode (ROM path/hash)
- [ ] Support cartridge embed mode (full ROM data)
- [ ] Optional framebuffer inclusion
- [ ] CRC32 checksum validation
- [ ] Cross-platform compatibility (endianness handling)

**Debugger System:**
- [ ] PC breakpoints
- [ ] Opcode breakpoints
- [ ] Memory read/write breakpoints
- [ ] Watchpoints with address ranges
- [ ] Step execution (instruction, cycle, scanline, frame)
- [ ] Run-until modes (PC, scanline)
- [ ] Execution history (circular buffer)
- [ ] State manipulation (registers, memory)
- [ ] Event callbacks

**Integration:**
- [ ] No modifications to EmulationState
- [ ] State/Logic separation maintained
- [ ] No RT-safety violations
- [ ] Build system integration
- [ ] Comprehensive test coverage (>90%)

### Quality Metrics

**Performance:**
- Binary snapshot save/load: **<10ms** for typical state (~5KB)
- JSON snapshot save/load: **<50ms** for typical state (~8KB)
- Debugger breakpoint check: **<1μs** overhead per instruction

**Memory:**
- Snapshot overhead: **<1MB** temporary allocations during save/load
- Debugger overhead: **<100KB** for typical debug session (512 history entries)

---

## Next Steps

1. **Review this specification** - Ensure all requirements are understood
2. **Create Phase 4.3 implementation branch** - `task/phase-4-3-snapshot-debugger`
3. **Implement Phase 1: Snapshot System** (8-10 hours)
   - Binary serialization
   - Cartridge handling
   - JSON serialization
   - Integration & testing
4. **Implement Phase 2: Debugger Core** (10-12 hours)
   - Debugger foundation
   - Breakpoint system
   - Watchpoint system
   - Step execution
   - Execution history
5. **Implement Phase 3: Debugger Advanced** (6-8 hours)
   - State manipulation
   - Callback system
   - Disassembler
   - Integration & testing
6. **Phase 4: Documentation** (2-3 hours)
   - User documentation
   - Example code
   - API reference

---

## Questions?

All critical questions have been addressed in the full specification. See [PHASE-4-3-SNAPSHOT-DEBUGGER-SPEC.md](./PHASE-4-3-SNAPSHOT-DEBUGGER-SPEC.md) Section 9 for detailed answers.

**Key Points:**
- Config arena/mutex handling: Resolved ✅
- Cartridge ROM data handling: Resolved ✅
- Endianness for cross-platform: Resolved ✅
- JSON schema versioning: Resolved ✅
- Framebuffer inclusion: Resolved ✅

**Implementation decisions** (to be made during implementation):
- Execution history buffer size (recommend 512 entries)
- Snapshot compression (recommend start without, add later)
- Mapper state interface (recommend generic getState/setState)

---

**Full Specification:** [PHASE-4-3-SNAPSHOT-DEBUGGER-SPEC.md](./PHASE-4-3-SNAPSHOT-DEBUGGER-SPEC.md)

**Status:** ✅ **READY FOR IMPLEMENTATION**
