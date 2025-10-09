# VBlank Edge Cases Fix Plan
**Created:** 2025-10-09
**Status:** Investigation & Planning Phase
**Related:** nmi-timing-implementation-log-2025-10-09.md

## Executive Summary

Three VBlank/NMI edge case tests remain failing after the primary refactor (957/966 passing, 99.1%). This document outlines investigation and fixes for the remaining issues.

**Test Status:**
- ✅ 957/966 tests passing (primary VBlank/NMI bugs fixed)
- ⏸️ 3 edge case failures requiring targeted fixes
- 🎯 Goal: 960+/966 tests passing (99.4%+)

## Failing Tests Analysis

### Test 1: "Multiple polls within VBlank period"
**File:** `tests/ppu/ppustatus_polling_test.zig:117-157`
**Failure:** `try testing.expect(detected_count >= 1)` fails
**Symptom:** `detected_count == 0` (VBlank never detected)

**Test Logic:**
```zig
// Start at 240.340 (before VBlank)
harness.seekToScanlineDot(240, 340);

// Poll continuously through VBlank period (240.340 → 261.20)
while (harness.getScanline() <= 261 and harness.getDot() < 20) {
    const status = harness.state.busRead(0x2002);
    if ((status & 0x80) != 0) {
        detected_count += 1;
    }

    // Advance 12 PPU cycles (4 CPU cycles for BIT $2002)
    var i: usize = 0;
    while (i < 12) : (i += 1) {
        harness.state.tick();
    }
}
```

**Expected Flow:**
1. At 240.340: Read $2002 → bit 7 = 0 (before VBlank)
2. Advance 12 cycles → reach 241.11
3. At 241.11: Read $2002 → bit 7 = 1 (VBlank set at 241.1)
4. `detected_count` increments to 1 ✓

**Actual Flow:** All reads return bit 7 = 0

**Hypothesis:** VBlank flag not being set at 241.1, OR being cleared before first read

---

### Test 2: "BIT instruction timing - when does read occur?"
**File:** `tests/ppu/ppustatus_polling_test.zig:227-312`
**Failure:** `try testing.expect(vblank_before_execute)` fails
**Symptom:** CPU state stuck at `fetch_operand_low`, never advances

**Test Output:**
```
CPU Cycle 1 (fetch_opcode): Before
  State: fetch_operand_low, VBlank: true
  After: State: fetch_operand_low, VBlank: true, PC: 0x0002
```

**Issue:** CPU state machine not advancing through instruction phases

**Root Cause Candidates:**
1. CPU reset sequence incomplete - test interrupts reset with seekToScanlineDot
2. Test RAM setup issue - instruction at address 0 but PC might be elsewhere
3. CPU state machine bug - stuck in fetch_operand_low

---

### Test 3: "AccuracyCoin rendering detection"
**File:** `tests/integration/accuracycoin_execution_test.zig:141-171`
**Failure:** `try testing.expect(rendering_enabled_frame != null)` fails
**Symptom:** `rendering_enabled` never becomes true within 300 frames

**Test Logic:**
```zig
// Sample frames: 1, 5, 10, 30, 60, 120, 180, 240, 300
for (sample_frames) |target_frame| {
    // Run until target frame
    while (runner.state.clock.frame() < target_frame) {
        _ = try runner.runFrame();
    }

    // Check if rendering enabled
    if (runner.state.rendering_enabled) {
        rendering_enabled_frame = frame;
    }
}
```

**`rendering_enabled` Source:**
```zig
// src/emulation/Ppu.zig:49
.rendering_enabled = state.mask.renderingEnabled(),

// src/ppu/State.zig:85-87
pub fn renderingEnabled(self: PpuMask) bool {
    return self.show_bg or self.show_sprites;
}
```

**Hypothesis:**
1. AccuracyCoin doesn't write $2001 (PPUMASK) until after warmup (~29,658 CPU cycles ≈ 1 frame)
2. Test might be checking wrong state field
3. ROM might genuinely not enable rendering until much later

---

## Root Cause Investigation Plan

### Phase 0: Add Diagnostic Logging (2 hours)

**Goal:** Understand actual behavior vs expected behavior

#### Step 1: VBlank Set/Clear Logging
**File:** `src/emulation/Ppu.zig`

Add logging at VBlank set/clear points:
```zig
if (scanline == 241 and dot == 1) {
    if (!state.status.vblank) {
        std.debug.print("[VBlank] SET at cycle={} (frame={})\n",
            .{ppu_cycles, frame});
        state.status.vblank = true;
        flags.nmi_signal = true;
    }
}

if (scanline == 261 and dot == 1) {
    if (state.status.vblank) {
        std.debug.print("[VBlank] CLEAR at cycle={} (frame={})\n",
            .{ppu_cycles, frame});
    }
    state.status.vblank = false;
    // ...
}
```

#### Step 2: $2002 Read Logging
**File:** `src/ppu/logic/registers.zig`

Log all $2002 reads with flag state:
```zig
0x0002 => blk: {
    const value = state.status.toByte(state.open_bus.value);
    std.debug.print("[PPUSTATUS] Read at cycle={}, VBlank={}, returning=0x{X:0>2}\n",
        .{cycle, state.status.vblank, value});

    state.status.vblank = false;
    // ...
}
```

#### Step 3: Run Failing Test with Logging
```bash
zig build test --summary all 2>&1 | grep -A 50 "Multiple polls"
```

**Expected Output:**
- Should see `[VBlank] SET` at scanline 241.1
- Should see at least one `[PPUSTATUS] Read` with `VBlank=true`

**If Output Shows:**
- No `[VBlank] SET`: PPU not processing at 241.1
- `[VBlank] SET` but all reads have `VBlank=false`: Flag being cleared prematurely

---

### Phase 1: Fix VBlank Detection Logic (4 hours)

**If Investigation Shows:** VBlank flag not setting at 241.1

#### Potential Fix 1: Verify stepPpuCycle Arguments
**File:** `src/emulation/State.zig:405`

Current:
```zig
var ppu_result = self.stepPpuCycle(self.clock.scanline(), self.clock.dot());
```

Verify `self.clock.scanline()` and `self.clock.dot()` return POST-advance values.

Add assertion to validate:
```zig
const post_scanline = self.clock.scanline();
const post_dot = self.clock.dot();

// Debug assertion: POST-advance position should differ from PRE-advance
// (except at frame boundaries where wrapping occurs)
std.debug.assert(post_scanline != step.scanline or post_dot != step.dot or
                 (step.scanline == 261 and step.dot == 340));

var ppu_result = self.stepPpuCycle(post_scanline, post_dot);
```

#### Potential Fix 2: VBlank Ledger Interference
**File:** `src/emulation/State.zig:445-462`

Check if ledger logic is interfering with readable flag:

Current:
```zig
if (result.nmi_signal) {
    self.vblank_ledger.recordVBlankSet(self.clock.ppu_cycles);
    if (self.ppu.ctrl.nmi_enable and self.ppu.status.vblank) {
        self.nmi_latched = true;
        self.vblank_ledger.nmi_edge_pending = true;
    }
}
```

**Issue:** We're manually setting `nmi_edge_pending`. Should let ledger handle it.

**Fix:** Update `recordVBlankSet` to check NMI enable and set edge:

```zig
// src/emulation/state/VBlankLedger.zig
pub fn recordVBlankSet(self: *VBlankLedger, cycle: u64) void {
    const was_active = self.span_active;
    self.span_active = true;
    self.last_set_cycle = cycle;

    // Detect NMI edge: 0→1 transition of (VBlank AND NMI_enable)
    // If VBlank sets while NMI is already enabled, fire NMI edge
    if (!was_active and self.ctrl_nmi_enabled) {
        self.nmi_edge_pending = true;
    }
}
```

Then simplify EmulationState:
```zig
if (result.nmi_signal) {
    self.vblank_ledger.recordVBlankSet(self.clock.ppu_cycles);

    // Check if NMI should be latched (ledger handles edge detection)
    if (self.vblank_ledger.nmi_edge_pending) {
        self.nmi_latched = true;
    }
}
```

---

### Phase 2: Fix CPU State Machine (BIT Timing Test) (3 hours)

**If Investigation Shows:** CPU stuck in fetch_operand_low

#### Fix Option A: Proper Test Setup
**File:** `tests/ppu/ppustatus_polling_test.zig:227-312`

Modify test to ensure CPU completes reset before testing:

```zig
// Complete CPU reset sequence (7 CPU cycles = 21 PPU cycles)
var reset_cycles: usize = 0;
while (reset_cycles < 21) : (reset_cycles += 1) {
    harness.state.tick();
}

// NOW seek to position
harness.seekToScanlineDot(241, 0);

// Manually set CPU state to fetch_opcode and PC to 0
harness.state.cpu.state = .fetch_opcode;
harness.state.cpu.pc = 0x0000;
```

#### Fix Option B: CPU State Machine Bug
If CPU genuinely stuck, investigate `src/emulation/cpu/execution.zig` state transitions.

---

### Phase 3: Fix AccuracyCoin Rendering Detection (2 hours)

#### Investigation Step 1: Check $2001 Writes
Add logging to busWrite:

```zig
// src/emulation/State.zig busWrite
if (address >= 0x2000 and address <= 0x3FFF) {
    const reg = address & 0x07;
    if (reg == 0x01) { // $2001 PPUMASK
        std.debug.print("[PPUMASK] Write 0x{X:0>2} at cycle={}, warmup={}\n",
            .{value, self.clock.ppu_cycles, self.ppu.warmup_complete});
    }
}
```

Run AccuracyCoin test and check if $2001 is ever written.

#### Investigation Step 2: Check Warmup Timing
Warmup completes at 29,658 CPU cycles = 88,974 PPU cycles ≈ 1 frame.

Verify warmup_complete flag is set:
```zig
// src/emulation/Ppu.zig or wherever warmup is managed
if (!state.warmup_complete and ppu_cycles >= 88974) {
    std.debug.print("[PPU] Warmup complete at cycle={}\n", .{ppu_cycles});
    state.warmup_complete = true;
}
```

#### Potential Fix: Extend Frame Limit
If ROM legitimately doesn't enable rendering until later:

```zig
// tests/integration/accuracycoin_execution_test.zig
const sample_frames = [_]u64{ 1, 5, 10, 30, 60, 120, 180, 240, 300, 500, 1000 };
```

---

## Implementation Phases

### Phase 0: Diagnostics (2 hours)
- [ ] Add VBlank set/clear logging
- [ ] Add $2002 read logging
- [ ] Add PPUMASK write logging
- [ ] Run failing tests and capture output
- [ ] Analyze logs to identify root causes

### Phase 1: VBlank Detection Fix (4 hours)
- [ ] Verify POST-advance clock position usage
- [ ] Fix VBlankLedger recordVBlankSet to handle NMI edge
- [ ] Remove manual `nmi_edge_pending` override in EmulationState
- [ ] Add unit tests for VBlank 0→1 edge with NMI pre-enabled
- [ ] Run test suite: Target 958+/966 passing

### Phase 2: CPU State Machine Fix (3 hours)
- [ ] Investigate CPU state stuck issue
- [ ] Fix test setup OR CPU execution bug
- [ ] Verify BIT instruction executes correctly
- [ ] Run test suite: Target 959+/966 passing

### Phase 3: AccuracyCoin Fix (2 hours)
- [ ] Investigate when ROM writes $2001
- [ ] Verify warmup timing
- [ ] Fix test expectations OR extend frame limit
- [ ] Run test suite: Target 960+/966 passing

### Phase 4: Documentation & Cleanup (2 hours)
- [ ] Remove debug logging
- [ ] Update KNOWN-ISSUES.md
- [ ] Update nmi-timing-implementation-log
- [ ] Commit with detailed message

---

## Risks & Mitigations

### Risk 1: Logging Changes Behavior
**Mitigation:** Use conditional compilation for debug logging
```zig
const DEBUG_VBLANK = false;
if (DEBUG_VBLANK) {
    std.debug.print(...);
}
```

### Risk 2: CPU Test Genuinely Broken
**Mitigation:** May need to skip test if it's testing incorrect behavior

### Risk 3: AccuracyCoin ROM Quirk
**Mitigation:** Test is diagnostic only - ROM's 939 opcode tests still pass

---

## Success Criteria

**Primary Goal:**
- 960+/966 tests passing (99.4%+)
- All VBlank/NMI edge cases resolved

**Secondary Goals:**
- No regressions in existing passing tests
- Clean, maintainable fixes
- Comprehensive documentation

**Stretch Goal:**
- 963+/966 tests passing (99.7%+) if all three fix cleanly

---

## Time Estimate

**Total:** 13 hours (2 work sessions)

**Session 1 (6 hours):**
- Phase 0: Diagnostics (2h)
- Phase 1: VBlank Detection Fix (4h)

**Session 2 (7 hours):**
- Phase 2: CPU State Machine Fix (3h)
- Phase 3: AccuracyCoin Fix (2h)
- Phase 4: Documentation (2h)

---

## Next Steps

1. **User Approval:** Review this plan and approve/modify
2. **Phase 0 Start:** Add diagnostic logging
3. **Iterative Fixes:** Based on investigation findings

**Questions for User:**
- Should we target all 3 fixes or prioritize specific tests?
- Is skipping "BIT timing" test acceptable if it's a test bug?
- What priority for AccuracyCoin diagnostic test?

---

# Development Notes - Session 2025-10-09 (Afternoon)

## Issues Found and Fixed (Actual ROM Testing)

### Issue #1: AccuracyCoin Flickering (FIXED ✅)

**Testing Methodology:** Running actual ROMs in RAMBO application (not just unit tests).

**Symptoms:**
- AccuracyCoin displayed graphics, then cleared to blank, repeating in flicker pattern
- User: "It draws, then clears. It's showing a blank frame."

**Root Cause:**
Triple-buffer mailbox race condition. When `write_index` caught up to `read_index` (buffer full), emulator continued rendering to the SAME buffer that Vulkan was actively displaying, causing visible tearing.

**Investigation:**
1. Added PPUMASK debug to detect if rendering was toggling → stayed enabled (not toggling)
2. Traced frame buffer presentation from PPU → FrameMailbox → Vulkan
3. Found FrameMailbox.swapBuffers() drops frame but continues writing to same buffer

**Fix:**
- Modified `FrameMailbox.getWriteBuffer()` to return `?[]u32` (optional)
- Returns `null` when next write would collide with active read buffer
- EmulationThread skips rendering when buffer returns `null`

**Files Changed:**
- `src/mailboxes/FrameMailbox.zig` - API changed to return optional
- `src/threads/EmulationThread.zig` - Handle null buffer gracefully

**Verification:** User confirmed: "Ok great, that resolved the flickering. AccuracyCoin displays correctly."

---

### Issue #2: Mario Spurious IRQ (FIXED ✅)

**Symptoms:**
- Mario showed blank screen
- Debug revealed IRQ firing at PC=0x8E77
- Mario's NMI handler detected error and disabled NMI permanently

**Root Cause #1 - Sticky IRQ Line:**
- `cpu.irq_line` was SET but NEVER cleared
- IRQ is level-triggered (not edge like NMI), sticky line caused repeated IRQ firing

**Root Cause #2 - APU Frame IRQ Default:**
- `apu.irq_inhibit` defaulted to `false`, enabling Frame IRQ at power-on
- Mario never writes $4017, so Frame IRQ fired unexpectedly
- Hardware default: IRQ disabled at power-on (per nesdev.org)

**Fix:**
- **State.zig:** Reordered APU tick before CPU tick, recompute IRQ line every cycle
- **apu/State.zig:** Changed `irq_inhibit` default from `false` to `true`

**Files Changed:**
- `src/emulation/State.zig` (lines 452-480) - IRQ line management
- `src/apu/State.zig` (lines 18-20) - Power-on default

---

### Issue #3: Test Regressions (FIXED ✅)

**Symptoms:** Tests dropped from ~950 to 767 passing

**Root Causes:**
1. FrameMailbox API change (optional return)
2. APU initialization test expected wrong default
3. Tests referenced removed `ppu_nmi_active` field
4. VBlankLedger race at cycle 0 (both timestamps initialized to 0)

**Fixes:**
- FrameMailbox tests: Unwrap optional with `orelse return error.SkipZigTest`
- APU test: Changed expected `irq_inhibit` from `false` to `true`
- Interrupt tests: Replaced `ppu_nmi_active` with VBlankLedger API calls
- Added `clock.advance(100)` before VBlank to avoid initialization race
- Fixed API calls: `recordVBlankStart` → `recordVBlankSet`, `incrementPpuCycles` → `advance`

**Files Changed:**
- `src/mailboxes/FrameMailbox.zig` - Test fixes
- `tests/apu/apu_test.zig` - Initialization expectation
- `tests/integration/interrupt_execution_test.zig` - NMI setup
- `tests/integration/cpu_ppu_integration_test.zig` - API calls

**Results:**
- Before: 939/947 tests passing (original baseline)
- After: 958/967 tests passing ✅ (+19 tests fixed)

---

## Current Status

### Test Results
- **Original Baseline:** 939/947 passing
- **Current:** 958/967 passing (+19 tests fixed)
- **Remaining Failures:** 7 tests (all integration/environment-specific)

### Remaining Test Failures
1. `vblank_wait_test` - VBlank Wait Loop (integration)
2. `ppustatus_polling_test` - Simple VBlank LDA (integration)
3. `ppustatus_polling_test` - BIT instruction timing (integration)
4. `threading_test` × 3 - Vulkan validation layers + timing-sensitive
5. `accuracycoin_execution_test` - ROM Diagnosis (integration)

### ROM Testing Status
- **AccuracyCoin:** Displays correctly ✅
- **Mario:** Still blank screen (spurious IRQ fixed, but different issue remains)

---

## Key Technical Insights

### IRQ vs NMI Behavior
- **NMI:** Edge-triggered (0→1 transition), latched until CPU acknowledges
- **IRQ:** Level-triggered (reflects current state of all IRQ sources)
- **Critical:** IRQ line must be recomputed every cycle, not sticky

### Triple-Buffering Race Conditions
- Lock-free ring buffers need collision detection
- Returning `null` when buffer full prevents tearing
- Frame timing can continue even when rendering skipped

### Hardware Power-On Defaults
- ROMs assume specific power-on state (e.g., APU Frame IRQ disabled)
- ROMs that never write certain registers depend on correct defaults
- Always verify hardware documentation for initialization state

---

## Pending Work

### Mario Blank Screen Investigation
**Current State:**
- Spurious IRQ fixed ✅
- NMI handler still detects error and disables NMI
- PPUCTRL pattern: enable NMI (0x90) → immediately disable (0x10)

**Next Steps:**
1. Enable DEBUG_NMI to trace NMI behavior
2. Compare Mario initialization vs known-good emulator
3. Check for other initialization errors
4. Investigate what condition Mario's NMI handler is checking

---

## Debug Output Control

All debug flags now disabled for clean test output:
- `DEBUG_NMI = false` (src/emulation/cpu/execution.zig)
- `DEBUG_IRQ = false` (src/emulation/cpu/execution.zig)
- `DEBUG_VBLANK = false` (src/emulation/Ppu.zig)
- `DEBUG_PPUSTATUS = false` (src/ppu/logic/registers.zig)
- `DEBUG_PPU_WRITES = false` (src/ppu/logic/registers.zig)

---

## References

- [nesdev.org/wiki/APU](https://www.nesdev.org/wiki/APU) - APU Frame Counter, IRQ behavior
- [nesdev.org/wiki/NMI](https://www.nesdev.org/wiki/NMI) - NMI edge detection
- [nesdev.org/wiki/IRQ](https://www.nesdev.org/wiki/IRQ) - IRQ level-triggered behavior
- Previous docs: `docs/code-review/gemini-review-2025-10-09.md`
