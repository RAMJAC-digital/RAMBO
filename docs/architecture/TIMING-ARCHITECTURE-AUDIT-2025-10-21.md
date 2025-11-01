# RAMBO NES Emulator Timing Architecture Analysis
## Sub-Cycle VBlank Timing Implementation Requirements

**Date:** 2025-10-21
**Version:** RAMBO 0.2.0-alpha (1023/1041 tests passing)
**Author:** Documentation Architect

## Executive Summary

This document provides a comprehensive analysis of RAMBO's current timing architecture, focusing on the VBlank flag visibility and CPU read race conditions. The analysis identifies the current execution order, timing mechanisms, and specific code locations that require modification to implement correct sub-cycle timing for hardware-accurate VBlank behavior.

The primary issue is that RAMBO currently lacks sub-cycle granularity for handling same-cycle CPU reads and PPU VBlank sets, leading to incorrect behavior where the VBlank flag may not be visible when it should be according to hardware specifications.

## Table of Contents

1. [Current Architecture Overview](#1-current-architecture-overview)
2. [Execution Order Analysis](#2-execution-order-analysis)
3. [VBlank Timing Mechanisms](#3-vblank-timing-mechanisms)
4. [Critical Code Locations](#4-critical-code-locations)
5. [Required Modifications](#5-required-modifications)
6. [Implementation Roadmap](#6-implementation-roadmap)

---

## 1. Current Architecture Overview

### 1.1 Master Clock System

The RAMBO emulator uses a **single master clock** (`MasterClock.zig`) as the sole source of truth for all timing:

```zig
pub const MasterClock = struct {
    /// Total PPU cycles elapsed since power-on
    ppu_cycles: u64 = 0,

    /// Derived timing (all calculated from ppu_cycles)
    pub fn scanline(self: MasterClock) u16 { ... }  // (ppu_cycles / 341) % 262
    pub fn dot(self: MasterClock) u16 { ... }        // ppu_cycles % 341
    pub fn isCpuTick(self: MasterClock) bool { ... } // (ppu_cycles % 3) == 0
}
```

**Key Characteristics:**
- PPU cycle granularity (5.369318 MHz)
- CPU executes every 3rd PPU cycle (1.789773 MHz)
- All timing derived from single counter
- No sub-cycle timing capability

### 1.2 Three-Thread Architecture

```
┌─────────────┐     ┌──────────────┐     ┌────────────┐
│ Main Thread │────>│  Emulation   │────>│   Render   │
│(Coordinator)│     │   Thread     │     │   Thread   │
└─────────────┘     │   (RT-safe)  │     │  (Vulkan)  │
                    └──────────────┘     └────────────┘
                            │
                    ┌───────▼────────┐
                    │ tick() function│
                    │ (Master Loop)  │
                    └────────────────┘
```

### 1.3 Component State/Logic Separation

All components follow a strict pattern:
- **State modules**: Pure data structures (e.g., `PpuState`, `CpuState`)
- **Logic modules**: Pure functions operating on state (e.g., `PpuLogic`, `CpuLogic`)
- **EmulationState**: Owns all component states, coordinates execution

---

## 2. Execution Order Analysis

### 2.1 Current tick() Function Execution Order

**Location:** `src/emulation/State.zig:593-644`

```zig
pub fn tick(self: *EmulationState) void {
    // 1. Advance master clock
    const step = self.nextTimingStep();

    // 2. PPU executes FIRST (every cycle)
    var ppu_result = self.stepPpuCycle(scanline, dot);
    self.applyPpuCycleResult(ppu_result);

    // 3. APU executes SECOND (every 3rd cycle)
    if (step.apu_tick) {
        const apu_result = self.stepApuCycle();
    }

    // 4. CPU executes LAST (every 3rd cycle)
    if (step.cpu_tick) {
        self.cpu.irq_line = /* update from sources */;
        _ = self.stepCpuCycle();
    }
}
```

**Critical Finding:**
- **PPU executes BEFORE CPU on the same cycle**
- This means PPU sets VBlank flag at scanline 241, dot 1
- CPU then reads $2002 after PPU has already set the flag
- No sub-cycle ordering possible with current architecture

### 2.2 PPU Event Timing

**Location:** `src/ppu/Logic.zig:398-402`

```zig
// Signal VBlank start (scanline 241 dot 1)
if (scanline == 241 and dot == 1) {
    flags.nmi_signal = true;  // Signal to EmulationState
}
```

**Location:** `src/emulation/State.zig:660-665`

```zig
if (result.nmi_signal) {
    // VBlank flag set at scanline 241 dot 1
    self.vblank_ledger.last_set_cycle = self.clock.ppu_cycles;
}
```

### 2.3 CPU $2002 Read Handling

**Location:** `src/emulation/State.zig:284-310` (busRead function)

```zig
// PPU registers + mirrors ($2000-$3FFF)
0x2000...0x3FFF => blk: {
    const is_status_read = (address & 0x0007) == 0x0002;

    if (is_status_read) {
        // Race condition detection (lines 291-303)
        const now = self.clock.ppu_cycles;
        const last_set = self.vblank_ledger.last_set_cycle;
        if (last_set > last_clear) {
            const delta = if (now >= last_set) now - last_set else 0;
            if (delta <= 2) {
                self.vblank_ledger.last_race_cycle = last_set;
            }
        }
    }

    const result = PpuLogic.readRegister(...);
    ppu_read_result = result;
    break :blk result.value;
}
```

**Then at lines 355-360:**

```zig
// Update last_read_cycle AFTER the read
if (ppu_read_result) |result| {
    if (result.read_2002) {
        const now = self.clock.ppu_cycles;
        self.vblank_ledger.last_read_cycle = now;
    }
}
```

---

## 3. VBlank Timing Mechanisms

### 3.1 VBlankLedger State Management

**Location:** `src/emulation/VBlankLedger.zig`

```zig
pub const VBlankLedger = struct {
    last_set_cycle: u64 = 0,      // When VBlank was set (241,1)
    last_clear_cycle: u64 = 0,    // When VBlank was cleared (261,1)
    last_read_cycle: u64 = 0,     // When $2002 was last read
    last_race_cycle: u64 = 0,     // Race condition tracking

    pub inline fn isFlagVisible(self: VBlankLedger) bool {
        if (!self.isActive()) return false;  // Not in VBlank period
        if (self.last_read_cycle >= self.last_set_cycle) return false;  // Already read
        return true;
    }
}
```

**Key Behavior:**
- Tracks timestamps of VBlank events
- Determines flag visibility based on event ordering
- **Problem:** All timestamps are at PPU cycle granularity

### 3.2 Current Race Condition Logic

The current implementation attempts to detect race conditions but lacks proper sub-cycle timing:

1. **Detection** (State.zig:291-303): Checks if read occurs within 0-2 cycles of VBlank set
2. **Suppression** (VBlankLedger:51-53): Suppresses NMI if race detected
3. **Flag Visibility** (VBlankLedger:35-45): Flag still visible during race (correct)

**Issue:** Without sub-cycle timing, cannot distinguish between:
- CPU read happening BEFORE PPU sets flag (should read 0)
- CPU read happening AFTER PPU sets flag (should read 1)

---

## 4. Critical Code Locations

### 4.1 Timing Control Points

| Component | File | Function | Line | Description |
|-----------|------|----------|------|-------------|
| Master Clock | `MasterClock.zig` | `advance()` | 53 | Only timing advancement point |
| Emulation | `State.zig` | `nextTimingStep()` | 531 | Scheduler for timing decisions |
| Emulation | `State.zig` | `tick()` | 593 | Main emulation loop |

### 4.2 VBlank State Changes

| Event | File | Function | Line | Action |
|-------|------|----------|------|--------|
| VBlank Set | `ppu/Logic.zig` | `tick()` | 398-402 | Signals VBlank start |
| Apply Signal | `State.zig` | `applyPpuCycleResult()` | 663 | Updates ledger timestamp |
| VBlank Clear | `ppu/Logic.zig` | `tick()` | 405-417 | Signals VBlank end |
| Apply Clear | `State.zig` | `applyPpuCycleResult()` | 669 | Updates ledger timestamp |

### 4.3 $2002 Read Path

| Step | File | Function | Line | Action |
|------|------|----------|------|--------|
| Bus Read | `State.zig` | `busRead()` | 284 | Entry point for CPU reads |
| Race Check | `State.zig` | `busRead()` | 291-303 | Attempts race detection |
| PPU Read | `ppu/registers.zig` | `readRegister()` | 80-107 | Builds status byte |
| Flag Check | `ppu/registers.zig` | `readRegister()` | 86 | Calls `isFlagVisible()` |
| Update Timestamp | `State.zig` | `busRead()` | 358 | Updates `last_read_cycle` |

### 4.4 Flag Visibility Decision

**Location:** `src/emulation/VBlankLedger.zig:35-45`

```zig
pub inline fn isFlagVisible(self: VBlankLedger) bool {
    // Current logic only considers cycle-level timing
    if (!self.isActive()) return false;
    if (self.last_read_cycle >= self.last_set_cycle) return false;
    return true;
}
```

---

## 5. Required Modifications

### 5.1 Sub-Cycle Timing Implementation

To correctly handle same-cycle CPU reads and PPU VBlank sets, the following modifications are required:

#### 5.1.1 Add Sub-Cycle Phase Tracking

**Location:** `src/emulation/MasterClock.zig`

```zig
pub const SubCyclePhase = enum(u2) {
    early = 0,   // PPU internal state changes
    middle = 1,  // PPU register visibility
    late = 2,    // CPU execution
    end = 3,     // Cycle completion
};

pub const MasterClock = struct {
    ppu_cycles: u64 = 0,
    sub_phase: SubCyclePhase = .early,  // NEW: Sub-cycle phase

    // NEW: Get current sub-cycle timestamp
    pub fn getSubCycleTimestamp(self: MasterClock) u64 {
        return (self.ppu_cycles << 2) | @intFromEnum(self.sub_phase);
    }
}
```

#### 5.1.2 Update VBlankLedger with Sub-Cycle Precision

**Location:** `src/emulation/VBlankLedger.zig`

```zig
pub const VBlankLedger = struct {
    last_set_timestamp: u64 = 0,     // Sub-cycle precision
    last_clear_timestamp: u64 = 0,   // Sub-cycle precision
    last_read_timestamp: u64 = 0,    // Sub-cycle precision

    pub inline fn isFlagVisible(self: VBlankLedger, current_timestamp: u64) bool {
        // Check if VBlank was set BEFORE current timestamp
        if (self.last_set_timestamp == 0) return false;
        if (self.last_set_timestamp > current_timestamp) return false;  // Not set yet
        if (self.last_clear_timestamp >= self.last_set_timestamp) return false;
        if (self.last_read_timestamp >= self.last_set_timestamp) return false;
        return true;
    }
}
```

#### 5.1.3 Modified Execution Order in tick()

**Location:** `src/emulation/State.zig:tick()`

```zig
pub fn tick(self: *EmulationState) void {
    // Advance master clock (full cycle)
    const step = self.nextTimingStep();

    // Sub-cycle phase 0: PPU internal state changes
    self.clock.sub_phase = .early;
    if (ppu_should_set_vblank) {
        self.vblank_ledger.last_set_timestamp = self.clock.getSubCycleTimestamp();
    }

    // Sub-cycle phase 1: Register visibility window
    self.clock.sub_phase = .middle;
    // VBlank flag now visible to reads

    // Sub-cycle phase 2: CPU execution
    self.clock.sub_phase = .late;
    if (step.cpu_tick) {
        // CPU reads will see correct flag state based on sub-cycle timing
        _ = self.stepCpuCycle();
    }

    // Sub-cycle phase 3: Cycle completion
    self.clock.sub_phase = .end;
    // PPU rendering continues
}
```

### 5.2 Specific Code Changes Required

#### 5.2.1 MasterClock.zig Modifications

**Add (after line 40):**
```zig
/// Sub-cycle phase for ordering same-cycle events
sub_phase: SubCyclePhase = .early,

/// Get timestamp with sub-cycle precision
pub fn getSubCycleTimestamp(self: MasterClock) u64 {
    return (self.ppu_cycles << 2) | @intFromEnum(self.sub_phase);
}
```

#### 5.2.2 VBlankLedger.zig Modifications

**Replace all u64 timestamp fields with sub-cycle precision:**
- Change field names from `*_cycle` to `*_timestamp`
- Update all methods to use sub-cycle timestamps
- Modify `isFlagVisible()` to accept current timestamp parameter

#### 5.2.3 State.zig tick() Modifications

**Lines 593-644:** Complete restructure to implement sub-cycle phases:

1. **Phase 0 (early):** PPU state changes (VBlank set)
2. **Phase 1 (middle):** Register visibility updates
3. **Phase 2 (late):** CPU execution with correct visibility
4. **Phase 3 (end):** Complete cycle, prepare for next

#### 5.2.4 Bus Read Modifications

**Lines 284-310:** Update race condition detection:
```zig
if (is_status_read) {
    const current_timestamp = self.clock.getSubCycleTimestamp();
    // Check if reading in same cycle as VBlank set
    const same_cycle = (current_timestamp >> 2) == (self.vblank_ledger.last_set_timestamp >> 2);
    if (same_cycle) {
        // Compare sub-cycle phases for race condition
        const read_phase = @intFromEnum(self.clock.sub_phase);
        const set_phase = @truncate(u2, self.vblank_ledger.last_set_timestamp);
        if (read_phase <= set_phase) {
            // Race: CPU reads before or simultaneously with PPU set
            self.vblank_ledger.last_race_timestamp = current_timestamp;
        }
    }
}
```

### 5.3 Testing Considerations

The modifications must maintain compatibility with existing tests while fixing the specific VBlank timing issues:

1. **Preserve existing behavior** for non-race conditions
2. **Fix test cases** that expect hardware-accurate race behavior
3. **Add new tests** for sub-cycle timing validation
4. **Verify commercial ROM compatibility** (SMB, Kirby, etc.)

---

## 6. Implementation Roadmap

### Phase 1: Infrastructure (2-3 hours)
1. Add `SubCyclePhase` enum to MasterClock
2. Implement `getSubCycleTimestamp()` method
3. Update VBlankLedger fields to use timestamps
4. Add unit tests for sub-cycle timestamp logic

### Phase 2: Execution Order (3-4 hours)
1. Restructure `tick()` function with sub-cycle phases
2. Move PPU VBlank setting to phase 0
3. Move CPU execution to phase 2
4. Verify PPU rendering still works correctly

### Phase 3: Flag Visibility (2-3 hours)
1. Update `isFlagVisible()` with timestamp comparison
2. Modify `busRead()` race detection logic
3. Update `readRegister()` to pass current timestamp
4. Test with problematic ROMs

### Phase 4: Validation (2-3 hours)
1. Run full test suite
2. Test commercial ROMs (SMB, Kirby, Battletoads)
3. Verify no regressions in working games
4. Document any remaining issues

### Total Estimated Time: 9-13 hours

---

## Appendix A: Hardware Reference

### NES PPU VBlank Timing Specification

According to NESDev Wiki and hardware testing:

1. **VBlank Flag Setting:**
   - Occurs at scanline 241, dot 1
   - Flag becomes visible to CPU reads ~2-3 PPU dots later
   - Exact timing varies by hardware revision

2. **Same-Cycle Behavior:**
   - If CPU reads $2002 on same PPU cycle as VBlank set:
     - Early 2C02: Reads 0 (flag not visible yet)
     - Late 2C02: Reads 1 (flag visible)
     - 2C07: Always reads 1
   - Race window: 0-2 PPU cycles after set

3. **NMI Generation:**
   - Triggered by VBlank flag rising edge
   - Suppressed if $2002 read races with flag set
   - Also suppressed during first frame after power-on

### Testing Methodology

The following test ROMs validate VBlank timing:
- `vbl_nmi_timing/1.frame_basics.nes`
- `vbl_nmi_timing/2.vbl_timing.nes`
- `vbl_nmi_timing/3.even_odd_frames.nes`
- `vbl_nmi_timing/4.vbl_clear_timing.nes`
- `vbl_nmi_timing/5.nmi_suppression.nes`
- `vbl_nmi_timing/6.suppression_edge.nes`
- `vbl_nmi_timing/7.nmi_on_timing.nes`

---

## Appendix B: Current Test Results

### Failing Tests Related to VBlank Timing

From `docs/STATUS.md`:
- `tests/integration/vbl_nmi_timing_test.zig` - 6 failures
- Specific issues with race conditions and suppression edge cases

### Working Games That May Be Affected

1. **Super Mario Bros:** Green line on left (fine X scroll issue)
2. **Kirby's Adventure:** Dialog boxes not rendering
3. **SMB3:** Floor disappears after few frames

These issues may or may not be related to VBlank timing, but proper sub-cycle implementation will eliminate timing as a potential cause.

---

## Conclusion

The RAMBO emulator currently lacks the sub-cycle timing precision necessary to correctly handle VBlank flag visibility during same-cycle CPU reads and PPU state changes. The architecture is well-structured with clear separation of concerns, making the required modifications straightforward to implement.

The proposed solution adds sub-cycle phase tracking to the master clock and updates the VBlankLedger to use sub-cycle timestamps. This allows proper ordering of events within a single PPU cycle, resolving the race condition issues identified in failing tests.

Implementation should proceed carefully to avoid breaking existing functionality while adding the required precision for hardware-accurate VBlank behavior.

---

**Document Version:** 1.0
**Last Updated:** 2025-10-21
**Next Review:** After Phase 1 implementation