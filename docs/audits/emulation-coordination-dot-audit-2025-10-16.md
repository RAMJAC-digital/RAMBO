# Emulation Coordination Diagram Audit Report
**Date**: 2025-10-16
**Diagram**: `docs/dot/emulation-coordination.dot`
**Context**: VBlankLedger refactor (Oct 15-16, 2025)

## Executive Summary

The `emulation-coordination.dot` diagram is **severely outdated** after the VBlankLedger refactor. The diagram documents a complex VBlankLedger API with 7 mutation functions, but the actual implementation is now a **pure data struct with 4 timestamp fields and 1 reset method**. Major architectural changes in data flow and mutation points are not reflected.

**Status**: 🔴 **CRITICAL UPDATE REQUIRED**

**Accuracy Score**: ~40% (outdated function signatures, missing new patterns, incorrect mutation model)

---

## 1. OUTDATED INFORMATION

### 1.1 VBlankLedger Structure (Lines 113-134)

**DIAGRAM SHOWS** (lines 119-133):
```
VBlankLedger:
span_active: bool = false           // VBlank period active
nmi_edge_pending: bool = false      // Latched NMI edge

Timestamp Fields (PPU cycles):
last_set_cycle: u64 = 0            // @ scanline 241.1
last_clear_cycle: u64 = 0          // @ 261.1 or $2002 read
last_status_read_cycle: u64 = 0    // $2002 read time
last_ctrl_toggle_cycle: u64 = 0    // $2000 write time
last_cpu_ack_cycle: u64 = 0        // CPU interrupt ack

Functions:
recordVBlankSet(cycle, nmi_enabled)
recordVBlankClear(cycle)
recordVBlankSpanEnd(cycle)
recordStatusRead(cycle)
recordCtrlToggle(cycle, old_nmi, new_nmi)
shouldAssertNmiLine(cycle, nmi_en, vb_flag) bool
acknowledgeCpu(cycle)
```

**ACTUAL IMPLEMENTATION** (`src/emulation/VBlankLedger.zig`):
```zig
pub const VBlankLedger = struct {
    last_set_cycle: u64 = 0,
    last_clear_cycle: u64 = 0,
    last_read_cycle: u64 = 0,
    last_nmi_ack_cycle: u64 = 0,

    pub fn reset(self: *VBlankLedger) void {
        self.last_set_cycle = 0;
        self.last_clear_cycle = 0;
        self.last_read_cycle = 0;
        self.last_nmi_ack_cycle = 0;
    }
};
```

**ISSUES**:
1. ❌ No `span_active` field (removed)
2. ❌ No `nmi_edge_pending` field (removed)
3. ❌ No `last_status_read_cycle` field (renamed to `last_read_cycle`)
4. ❌ No `last_ctrl_toggle_cycle` field (removed - PPUCTRL tracking eliminated)
5. ❌ All 7 mutation functions removed - this is now a PURE DATA STRUCT
6. ❌ Only method is `reset()`, not the 7 documented functions

**CRITICAL**: The diagram documents an API that no longer exists!

### 1.2 PPU Logic readRegister() Signature (Line 274)

**DIAGRAM SHOWS**: Not explicitly documented, but implied to return `u8`

**ACTUAL IMPLEMENTATION** (`src/ppu/logic/registers.zig:60-75`):
```zig
pub const PpuReadResult = struct {
    value: u8,
    read_2002: bool = false,
};

pub fn readRegister(
    state: *PpuState,
    cart: ?*AnyCartridge,
    address: u16,
    vblank_ledger: VBlankLedger,
) PpuReadResult
```

**ISSUES**:
1. ❌ Returns `PpuReadResult` struct, not `u8`
2. ❌ Takes `vblank_ledger: VBlankLedger` by value (not by pointer)
3. ❌ Now PURE - does not mutate VBlankLedger
4. ✅ Correctly takes `address: u16` (not separated into register number)

### 1.3 PPU Logic tick() Return Type (Line 192)

**DIAGRAM SHOWS** (line 192):
```
tick(ppu, scanline, dot, cart, fb) PpuFlags
Returns: rendering_enabled, frame_complete, nmi_signal, vblank_clear, a12_rising
```

**ACTUAL IMPLEMENTATION** (`src/ppu/Logic.zig:163-171`):
```zig
pub const TickFlags = struct {
    frame_complete: bool = false,
    rendering_enabled: bool,
    nmi_signal: bool = false,
    vblank_clear: bool = false,
    a12_rising: bool = false,
};
```

**ISSUES**:
1. ⚠️ Return type is `TickFlags`, not `PpuFlags` (naming inconsistency)
2. ✅ Fields are correct

### 1.4 EmulationState.busRead() Data Flow (Lines 263-282, 290)

**DIAGRAM SHOWS**: Implicit flow - busRead() delegates to routing.zig

**ACTUAL IMPLEMENTATION** (`src/emulation/State.zig:263-324`):
```zig
pub inline fn busRead(self: *EmulationState, address: u16) u8 {
    // PPU register read at 0x2000-0x3FFF
    var ppu_read_result: ?PpuLogic.PpuReadResult = null;

    const value = switch (address) {
        0x2000...0x3FFF => blk: {
            const result = PpuLogic.readRegister(
                &self.ppu,
                cart_ptr,
                address,
                self.vblank_ledger,  // ← PASS BY VALUE
            );
            ppu_read_result = result;
            break :blk result.value;
        },
        // ... other cases
    };

    // NEW: Check for $2002 read side-effect
    if (ppu_read_result) |result| {
        if (result.read_2002) {
            self.vblank_ledger.last_read_cycle = self.clock.ppu_cycles;
        }
    }

    self.bus.open_bus = value;
    return value;
}
```

**ISSUES**:
1. ❌ Missing critical data flow: busRead() now updates `vblank_ledger.last_read_cycle` directly
2. ❌ Missing PpuReadResult struct capture and inspection
3. ❌ No documentation of `read_2002` flag checking pattern
4. ❌ Diagram shows ledger mutation via `recordStatusRead()` - this function doesn't exist!

### 1.5 EmulationState.busWrite() VBlank Recording (Lines 287, 356)

**DIAGRAM SHOWS** (line 287):
```
bus_write -> vblank_record_ctrl [label="on $2000 write", color=orange];
```

**ACTUAL IMPLEMENTATION**: This flow **NO LONGER EXISTS**

**ISSUES**:
1. ❌ `recordCtrlToggle()` function removed entirely
2. ❌ EmulationState.busWrite() no longer calls any VBlankLedger methods
3. ❌ PPUCTRL writes are NOT tracked in the ledger anymore

### 1.6 EmulationState.applyPpuCycleResult() Implementation (Line 582)

**DIAGRAM SHOWS** (lines 285-286):
```
ppu_result -> vblank_record_set [label="on nmi_signal", color=red];
ppu_result -> vblank_record_end [label="on vblank_clear", color=red];
```

**ACTUAL IMPLEMENTATION** (`src/emulation/State.zig:582-606`):
```zig
fn applyPpuCycleResult(self: *EmulationState, result: PpuCycleResult) void {
    // ... other code ...

    if (result.nmi_signal) {
        // Direct timestamp assignment, NOT function call
        self.vblank_ledger.last_set_cycle = self.clock.ppu_cycles;
    }

    if (result.vblank_clear) {
        // Direct timestamp assignment, NOT function call
        self.vblank_ledger.last_clear_cycle = self.clock.ppu_cycles;
    }
}
```

**ISSUES**:
1. ❌ No `recordVBlankSet()` call - direct field assignment instead
2. ❌ No `recordVBlankSpanEnd()` call - direct field assignment instead
3. ❌ VBlankLedger mutation pattern completely changed - it's now treated as plain data

---

## 2. MISSING INFORMATION

### 2.1 PpuReadResult Structure

**MISSING**: Complete documentation of the new `PpuReadResult` pattern:
```zig
pub const PpuReadResult = struct {
    value: u8,
    read_2002: bool = false,
};
```

This is a **critical architectural pattern** introduced by the refactor:
- PPU register reads return a struct, not just `u8`
- `read_2002` flag signals EmulationState to update ledger
- Enables PURE register read functions (no mutation)
- Clear separation of concerns: PPU computes, EmulationState mutates

**RECOMMENDATION**: Add subgraph for PpuReadResult structure and data flow

### 2.2 VBlankLedger Pure Data Pattern

**MISSING**: Documentation of the new "pure data struct" pattern:
- VBlankLedger has NO methods (except reset)
- EmulationState is the ONLY mutator
- All logic moved to consumers (registers.zig uses ledger to compute VBlank status)

**EXAMPLE** (`src/ppu/logic/registers.zig:83-87`):
```zig
// PURE computation using ledger timestamps
const vblank_active = (vblank_ledger.last_set_cycle > vblank_ledger.last_clear_cycle) and
    (vblank_ledger.last_set_cycle > vblank_ledger.last_read_cycle);
```

**RECOMMENDATION**: Add architectural note explaining this pattern shift

### 2.3 $2002 Read Side-Effect Handling

**MISSING**: Complete data flow for $2002 reads:
```
1. CPU executes busRead(0x2002)
2. EmulationState.busRead() calls PpuLogic.readRegister()
3. readRegister() passes ledger BY VALUE (pure, no mutation)
4. readRegister() computes VBlank status from timestamps
5. readRegister() returns PpuReadResult{value=0x80, read_2002=true}
6. EmulationState inspects result.read_2002
7. EmulationState updates vblank_ledger.last_read_cycle = clock.ppu_cycles
```

**RECOMMENDATION**: Add detailed edge showing this 7-step flow

### 2.4 VBlank Status Computation Logic

**MISSING**: Documentation of how VBlank status is computed from timestamps:
```zig
// From registers.zig:83-87
const vblank_active =
    (vblank_ledger.last_set_cycle > vblank_ledger.last_clear_cycle) and
    (vblank_ledger.last_set_cycle > vblank_ledger.last_read_cycle);
```

This is the **core VBlank logic** - not documented anywhere in the diagram!

**RECOMMENDATION**: Add note box explaining this computation

### 2.5 PPUCTRL Tracking Removal

**MISSING**: The diagram documents `recordCtrlToggle()` but doesn't explain that:
- This function was removed
- PPUCTRL writes are NO LONGER tracked in VBlankLedger
- `last_ctrl_toggle_cycle` field removed

**RECOMMENDATION**: Remove all references to PPUCTRL tracking

---

## 3. CORRECT INFORMATION

### 3.1 Component Ownership ✅
Lines 23-27: EmulationState directly owns all components
- ✅ Correct: `vblank_ledger: VBlankLedger` is directly owned
- ✅ Correct: No pointer wiring

### 3.2 MasterClock Design ✅
Lines 63-76: Single timing counter with derived functions
- ✅ Correct: `ppu_cycles: u64` is the only counter
- ✅ Correct: All other timing derived on demand

### 3.3 TimingStep Structure ✅
Lines 78-89: Timing coordination structure
- ✅ Correct: Pre-advance scanline/dot
- ✅ Correct: Post-advance cpu_tick/apu_tick bools
- ✅ Correct: skip_slot handling

### 3.4 PpuCycleResult Structure ✅
Lines 96-98:
```
PpuCycleResult:
rendering_enabled: bool
frame_complete: bool
nmi_signal: bool     // VBlank set @ 241.1
vblank_clear: bool   // VBlank clear @ 261.1
a12_rising: bool     // For MMC3 IRQ
```
- ✅ Matches `src/emulation/state/CycleResults.zig:5-11`

### 3.5 Tick Flow Structure ✅
Lines 266-283: Main tick() execution order
- ✅ Correct: 1. Timing step, 2. PPU tick, 3. CPU tick (if cpu_tick)
- ✅ Correct: PPU returns result flags
- ✅ Correct: CPU queries NMI state

### 3.6 DMA Integration ✅
Lines 136-160, 302-303: OAM DMA and DMC DMA
- ✅ Correct: Triggered by $4014 write and APU respectively
- ✅ Correct: State machine structures documented accurately

### 3.7 A12 State Tracking ✅
Note: Not explicitly in diagram, but implied in PpuCycleResult
- ✅ PPU now manages `a12_state: bool` field
- ✅ Returns `a12_rising` flag in TickFlags

---

## 4. RECOMMENDED UPDATES

### 4.1 CRITICAL: Rewrite VBlankLedger Subgraph (Lines 113-134)

**Replace entire subgraph with**:
```dot
subgraph cluster_vblank_ledger {
    label="VBlankLedger (src/emulation/VBlankLedger.zig)\nPure Data Struct - EmulationState is ONLY Mutator";
    style=filled;
    fillcolor=lightcoral;

    vblank_ledger_state [label="VBlankLedger (Pure Data):\l\lTimestamp Fields (PPU cycles):\llast_set_cycle: u64 = 0        // Set at scanline 241.1\llast_clear_cycle: u64 = 0      // Cleared at scanline 261.1\llast_read_cycle: u64 = 0       // Updated on $2002 read\llast_nmi_ack_cycle: u64 = 0    // CPU NMI acknowledgment\l\lARCHITECTURAL PATTERN:\l- NO mutation methods (except reset)\l- EmulationState updates fields directly\l- Consumers compute VBlank status from timestamps\l- Pure data enables stateless logic\l", fillcolor=lightcoral, shape=box];

    vblank_reset [label="reset(self) void\n// Only method - resets all timestamps to 0", fillcolor=lightcoral];

    vblank_usage_note [label="VBlank Status Computation (Pure):\l\lvblank_active = (last_set_cycle > last_clear_cycle)\l                 AND (last_set_cycle > last_read_cycle)\l\lThis computation happens in:\l- registers.zig:readRegister() for $2002 reads\l- NO shouldAssertNmiLine() method!\l", fillcolor=lightyellow, shape=note];
}
```

**Remove these nodes** (lines 121-133):
- `vblank_record_set`
- `vblank_record_clear`
- `vblank_record_end`
- `vblank_record_status`
- `vblank_record_ctrl`
- `vblank_should_assert`
- `vblank_acknowledge`

### 4.2 CRITICAL: Update busRead() Data Flow (Line 290)

**Add new subgraph before bus_routing**:
```dot
subgraph cluster_ppu_read_pattern {
    label="$2002 Read Pattern (New Architecture)";
    style=filled;
    fillcolor=lightyellow;

    ppu_read_step1 [label="1. CPU reads $2002\nEmulationState.busRead(0x2002)", fillcolor=wheat];
    ppu_read_step2 [label="2. Call PpuLogic.readRegister()\nPass vblank_ledger BY VALUE", fillcolor=lightgreen];
    ppu_read_step3 [label="3. readRegister() computes VBlank:\nvblank = (set > clear) && (set > read)", fillcolor=lightgreen];
    ppu_read_step4 [label="4. Return PpuReadResult{\n  value: 0x80,\n  read_2002: true\n}", fillcolor=lightgreen];
    ppu_read_step5 [label="5. EmulationState inspects result.read_2002", fillcolor=wheat];
    ppu_read_step6 [label="6. Update ledger.last_read_cycle\nDirect field assignment!", fillcolor=lightcoral];
    ppu_read_step7 [label="7. Return value to CPU", fillcolor=wheat];

    ppu_read_step1 -> ppu_read_step2 [color=blue];
    ppu_read_step2 -> ppu_read_step3 [color=green];
    ppu_read_step3 -> ppu_read_step4 [color=green];
    ppu_read_step4 -> ppu_read_step5 [color=blue];
    ppu_read_step5 -> ppu_read_step6 [color=red];
    ppu_read_step6 -> ppu_read_step7 [color=blue];
}
```

**Update busRead node** (line 55):
```dot
bus_read [label="busRead(self, addr) u8\n// Route to component\n// NEW: Capture PpuReadResult\n// NEW: Update ledger on read_2002\n// Update open bus\n// Check debugger", fillcolor=wheat, shape=box3d];
```

### 4.3 CRITICAL: Update busWrite() Flow (Line 287)

**REMOVE this edge** (line 287):
```dot
bus_write -> vblank_record_ctrl [label="on $2000 write", color=orange];
```

**Replace with note**:
```dot
buswrite_note [label="NOTE: PPUCTRL writes NO LONGER\ntracked in VBlankLedger\n(recordCtrlToggle removed)", fillcolor=yellow, shape=note];
```

### 4.4 Update applyPpuCycleResult() Flow (Lines 285-286)

**Replace edges** (lines 285-286):
```dot
// OLD (remove these):
ppu_result -> vblank_record_set [label="on nmi_signal", color=red];
ppu_result -> vblank_record_end [label="on vblank_clear", color=red];
```

**NEW**:
```dot
// Direct field assignment pattern
ppu_result -> vblank_direct_set [label="on nmi_signal:\nledger.last_set_cycle = clock.ppu_cycles", color=red, penwidth=2];
ppu_result -> vblank_direct_clear [label="on vblank_clear:\nledger.last_clear_cycle = clock.ppu_cycles", color=red, penwidth=2];

vblank_direct_set [label="Direct Field Mutation\n(not function call)", fillcolor=lightcoral, shape=note];
vblank_direct_clear [label="Direct Field Mutation\n(not function call)", fillcolor=lightcoral, shape=note];
```

### 4.5 Add PpuReadResult Documentation

**Add new subgraph after PpuCycleResult** (after line 102):
```dot
subgraph cluster_ppu_read_result {
    label="PPU Read Result (New in Refactor)";
    style=filled;
    fillcolor=lightgreen;

    ppu_read_result_struct [label="PpuReadResult:\lvalue: u8           // Byte to return to CPU\lread_2002: bool     // True if $2002 read occurred\l\lPattern:\l- PpuLogic.readRegister() returns this struct\l- Enables PURE register reads (no mutation)\l- EmulationState interprets read_2002 flag\l- Separation of concerns: PPU computes, State mutates\l", fillcolor=lightgreen, shape=record];
}
```

### 4.6 Update PPU Logic Signature (Line 68)

**Update readRegister signature**:
```dot
ppu_read_register [label="readRegister(state, cart, addr, vblank_ledger) PpuReadResult\n// NOW PURE: takes ledger BY VALUE\n// Returns struct with value + read_2002 flag\n// Computes VBlank from timestamps\n// Does NOT mutate ledger", fillcolor=lightgreen, shape=box3d, penwidth=2];
```

### 4.7 Update Ownership Summary (Line 357)

**Update VBlankLedger note**:
```dot
own_ledger [label="VBlankLedger:\nPure data struct (4 timestamp fields)\nEmulationState is ONLY mutator\nDirect field assignment pattern\nConsumers compute VBlank from timestamps\nNO recordVBlankSet/Clear/etc methods", fillcolor=lightcoral, shape=note];
```

### 4.8 Add Architecture Migration Note

**Add new note box**:
```dot
subgraph cluster_vblank_migration {
    label="VBlank Architecture Migration (Oct 15-16, 2025)";
    style=filled;
    fillcolor=white;
    rank=sink;

    migration_note [label="Phase 4 Refactor Changes:\l\lOLD (Documented in This Diagram - OUTDATED):\l- VBlankLedger with 7 mutation methods\l- recordVBlankSet/Clear/SpanEnd/StatusRead/CtrlToggle\l- shouldAssertNmiLine() query method\l- PPUCTRL toggle tracking\l\lNEW (Actual Implementation):\l- Pure data struct with 4 timestamps\l- EmulationState updates fields directly\l- Consumers compute VBlank from timestamps\l- NO PPUCTRL tracking\l- PpuReadResult pattern for side-effect signaling\l\lMOTIVATION:\l- Simpler mental model (data vs. behavior)\l- Clear ownership (EmulationState mutates)\l- Testable VBlank computation (pure functions)\l- Eliminated complex state machine\l", fillcolor=yellow, shape=note];
}
```

---

## 5. SPECIFIC LINE-BY-LINE CORRECTIONS

| Line | Current Content | Issue | Recommended Fix |
|------|----------------|-------|-----------------|
| 113-134 | VBlankLedger subgraph with 7 methods | All methods removed | Replace entire subgraph (see 4.1) |
| 119 | `span_active: bool = false` | Field removed | DELETE |
| 119 | `nmi_edge_pending: bool = false` | Field removed | DELETE |
| 119 | `last_status_read_cycle` | Renamed | Change to `last_read_cycle` |
| 119 | `last_ctrl_toggle_cycle` | Field removed | DELETE |
| 121-127 | `recordVBlankSet/Clear/SpanEnd/StatusRead/CtrlToggle` | Functions removed | DELETE all nodes |
| 131 | `shouldAssertNmiLine()` | Function removed | DELETE node |
| 133 | `acknowledgeCpu()` | Function removed | DELETE node |
| 192 | `PpuFlags` return type | Actual name is `TickFlags` | Change to `TickFlags` |
| 274 | PPU register read flow | Returns struct, not u8 | Add PpuReadResult documentation |
| 285 | `ppu_result -> vblank_record_set` | Direct assignment now | Update edge label |
| 286 | `ppu_result -> vblank_record_end` | Direct assignment now | Update edge label |
| 287 | `bus_write -> vblank_record_ctrl` | Flow removed | DELETE edge |
| 290 | Bus read flow | Missing PpuReadResult capture | Add detailed flow (see 4.2) |

---

## 6. VALIDATION CHECKLIST

Use these commands to verify diagram accuracy:

```bash
# Verify VBlankLedger structure
grep -n "pub const VBlankLedger" src/emulation/VBlankLedger.zig
grep -n "pub fn" src/emulation/VBlankLedger.zig  # Should only show reset()

# Verify PpuReadResult structure
grep -n "pub const PpuReadResult" src/ppu/logic/registers.zig

# Verify readRegister signature
grep -A 5 "pub fn readRegister" src/ppu/logic/registers.zig

# Verify PPU tick return type
grep -n "pub const TickFlags" src/ppu/Logic.zig

# Verify EmulationState.busRead() PpuReadResult handling
grep -A 20 "pub inline fn busRead" src/emulation/State.zig | grep "ppu_read_result"

# Verify EmulationState.applyPpuCycleResult() direct assignment
grep -A 15 "fn applyPpuCycleResult" src/emulation/State.zig
```

---

## 7. PRIORITY RECOMMENDATIONS

### Priority 1 (Blocking - Critical Inaccuracies)
1. ✅ Rewrite VBlankLedger subgraph (4.1)
2. ✅ Update busRead() data flow with PpuReadResult pattern (4.2)
3. ✅ Remove bus_write → recordCtrlToggle edge (4.3)
4. ✅ Update applyPpuCycleResult() to show direct assignment (4.4)

### Priority 2 (Important - Missing New Patterns)
5. ✅ Add PpuReadResult documentation (4.5)
6. ✅ Update readRegister() signature (4.6)
7. ✅ Add architecture migration note (4.8)

### Priority 3 (Clarification)
8. ⚠️ Update ownership summary (4.7)
9. ⚠️ Fix PpuFlags → TickFlags naming (line 192)

---

## 8. ESTIMATED EFFORT

- **Lines to delete**: ~50 (all VBlankLedger method nodes + edges)
- **Lines to add**: ~80 (new subgraphs, notes, corrected flows)
- **Lines to modify**: ~20 (signatures, labels, edges)
- **Total changes**: ~150 lines

**Estimated time**: 2-3 hours for a complete, accurate update

---

## 9. CONCLUSION

The `emulation-coordination.dot` diagram documents a **completely different architecture** than what exists after the VBlankLedger refactor. The core VBlankLedger API changed from a complex state machine with 7 methods to a simple data struct with 4 fields. The diagram's value as a reference is severely compromised.

**CRITICAL GAPS**:
1. Entire VBlankLedger API documented (7 methods) - **none exist in code**
2. PpuReadResult pattern (central to refactor) - **not documented**
3. Direct field assignment pattern - **not documented**
4. $2002 read side-effect flow - **incorrect/incomplete**
5. PPUCTRL tracking removal - **not noted**

**RECOMMENDATION**: Immediate update required before diagram can be trusted as accurate reference material for developers.

---

**Auditor**: agent-docs-architect-pro
**Audit Methodology**: Line-by-line comparison against source files
**Confidence Level**: HIGH (all source files read and analyzed)
**Next Steps**: Prioritize Priority 1 updates, then iterate through Priority 2-3
