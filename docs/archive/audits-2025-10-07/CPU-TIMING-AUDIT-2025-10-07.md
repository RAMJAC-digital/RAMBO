# CPU Timing Decoupling Audit
**Date:** 2025-10-07
**Phase:** 3 - CPU Timing Migration
**Status:** IN PROGRESS

## Executive Summary

This audit identifies all `cpu.cycle_count` references and plans their migration to use `MasterClock.cpuCycles()` for external timing control.

### Current Architecture (BEFORE)

```zig
// CPU State owns timing
pub const CpuState = struct {
    cycle_count: u64 = 0,  // ← TIMING OWNERSHIP (BAD!)

    // ... registers ...
};

// EmulationState increments in 3 places
fn tickCpu(self: *EmulationState) void {
    self.cpu.cycle_count += 1;  // ← INCREMENT #1
}

fn tickDma(self: *EmulationState) void {
    self.cpu.cycle_count += 1;  // ← INCREMENT #2 (DMA stall)
}

fn tickDmcDma(self: *EmulationState) void {
    self.cpu.cycle_count += 1;  // ← INCREMENT #3 (DMC stall)
}
```

### Target Architecture (AFTER)

```zig
// CPU State is pure data (no timing)
pub const CpuState = struct {
    // cycle_count REMOVED!

    // ... registers only ...
};

// MasterClock provides CPU cycles (derived)
clock.cpuCycles()  // Returns ppu_cycles / 3

// No increments needed - clock is already advanced!
fn tickCpu(self: *EmulationState) void {
    // NO INCREMENT - timing comes from clock
    const cpu_cycles = self.clock.cpuCycles();
}
```

## Reference Audit

### Source Files (11 references)

#### 1. src/cpu/State.zig (1 definition)
```
Line 147: cycle_count: u64 = 0,  // Total cycles since power-on
```
**Action:** DELETE field entirely

#### 2. src/emulation/State.zig (7 references)

**Increments (3):**
```
Line 1000: self.cpu.cycle_count += 1;           // tickCpu()
Line 1580: self.cpu.cycle_count += 1;           // tickDma()
Line 1630: self.cpu.cycle_count += 1;           // tickDmcDma()
```
**Action:** REMOVE all increments (clock is already advanced)

**Usage (1):**
```
Line 1005: if (!self.ppu.warmup_complete and self.cpu.cycle_count >= 29658)
```
**Action:** Replace with `self.clock.cpuCycles() >= 29658`

**Tests (3):**
```
Line 1840: const initial_cpu_cycles = state.cpu.cycle_count;
Line 1846: try testing.expectEqual(initial_cpu_cycles, state.cpu.cycle_count);
Line 1851: try testing.expectEqual(initial_cpu_cycles + 1, state.cpu.cycle_count);
```
**Action:** Replace with `state.clock.cpuCycles()`

#### 3. src/snapshot/state.zig (2 references)
```
Line 104: try writer.writeInt(u64, cpu.cycle_count, .little);
Line 143: .cycle_count = try reader.readInt(u64, .little),
```
**Action:** REMOVE serialization (MasterClock already stores ppu_cycles)

### Test Files (57 references)

#### 1. tests/cpu/instructions_test.zig (19 refs)
- Pattern: `state.cpu.cycle_count` in timing assertions
- **Action:** Replace with `state.clock.cpuCycles()`

#### 2. tests/cpu/diagnostics/timing_trace_test.zig (15 refs)
- Pattern: Cycle counting in trace validation
- **Action:** Replace with `state.clock.cpuCycles()`

#### 3. tests/cpu/rmw_test.zig (9 refs)
- Pattern: RMW instruction timing verification
- **Action:** Replace with `state.clock.cpuCycles()`

#### 4. tests/cpu/opcodes/control_flow_test.zig (8 refs)
- Pattern: Branch timing verification
- **Action:** Replace with `state.clock.cpuCycles()`

#### 5. tests/snapshot/snapshot_integration_test.zig (2 refs)
- Pattern: Snapshot state verification
- **Action:** Replace with `state.clock.cpuCycles()`

#### 6. tests/integration/rom_test_runner.zig (2 refs)
- Pattern: Cycle counting in test ROMs
- **Action:** Replace with `state.clock.cpuCycles()`

#### 7. tests/integration/oam_dma_test.zig (2 refs)
- Pattern: DMA cycle verification
- **Action:** Replace with `state.clock.cpuCycles()`

## Migration Plan

### Phase 3.1: Core Source Files (HIGH PRIORITY)
1. Remove `cycle_count` field from CpuState
2. Remove 3 increments from EmulationState
3. Update warmup check to use clock
4. Update EmulationState tests (3 refs)
5. Remove snapshot serialization

**Estimated Time:** 1 hour

### Phase 3.2: CPU Tests (MEDIUM PRIORITY)
1. Migrate instructions_test.zig (19 refs)
2. Migrate timing_trace_test.zig (15 refs)
3. Migrate rmw_test.zig (9 refs)
4. Migrate control_flow_test.zig (8 refs)

**Estimated Time:** 1.5 hours

### Phase 3.3: Integration Tests (LOW PRIORITY)
1. Migrate rom_test_runner.zig (2 refs)
2. Migrate oam_dma_test.zig (2 refs)
3. Migrate snapshot_integration_test.zig (2 refs)

**Estimated Time:** 30 minutes

### Phase 3.4: Verification
1. Run full test suite (target: >= 899 passing)
2. Verify AccuracyCoin still passes
3. Test commercial ROMs (Mario, Burger Time)

**Estimated Time:** 15 minutes

**Total Estimated Time:** 3-3.5 hours

## Success Criteria

- ✅ Zero `cycle_count` references in codebase
- ✅ All timing derived from MasterClock
- ✅ Test count >= 899 (no regressions)
- ✅ AccuracyCoin passes ($00 $00 $00 $00)
- ✅ Commercial ROMs render correctly

## Benefits

1. **Architectural Consistency:** CPU timing follows same pattern as PPU
2. **Single Source of Truth:** All timing from MasterClock.ppu_cycles
3. **Simplified State:** CpuState is pure register data (fully serializable)
4. **External Control:** Enables debugger stepping, save states, rewind
5. **Zero Overhead:** Derived timing is simple integer division (ppu_cycles / 3)

## Risks & Mitigation

**Risk:** Tests rely on exact CPU cycle counts
**Mitigation:** clock.cpuCycles() provides exact same values as old cycle_count

**Risk:** Snapshot format changes
**Mitigation:** Already breaking snapshots from Phase 2, acceptable

**Risk:** Performance impact from method calls
**Mitigation:** cpuCycles() is inline-able, zero overhead

---

**Status:** Ready for migration
**Approval:** User requested full CPU decoupling using same principles as PPU
**Next Step:** Execute Phase 3.1 (core source files)
