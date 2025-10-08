# RAMBO NES Emulator - Comprehensive System Stability Audit Findings

**Date:** 2025-10-07
**Session:** System Stability Investigation
**Status:** ⚠️ **CRITICAL ISSUES IDENTIFIED - DEVELOPMENT HALT REQUIRED**
**Overall System Health:** 🔴 **6/10** - Functional but unstable

---

## Executive Summary

This comprehensive audit has identified **1 SHOWSTOPPER bug**, **3 CRITICAL issues**, **7 HIGH-priority problems**, and **10 MEDIUM-priority concerns** preventing commercial ROM playability and threatening system stability.

### Root Cause Analysis: Blank Screen Issue

**Primary Showstopper:** NMI Race Condition (Code Review Issue #1)
- Commercial games (Mario 1, Burger Time, Donkey Kong) read $2002 (PPUSTATUS) during VBlank set cycle
- VBlank flag becomes visible before NMI level is computed
- $2002 read clears VBlank flag before NMI edge detector sees transition
- Games never receive NMI interrupt → game logic never runs → blank screen

**Contributing Factors:**
1. No framebuffer validation tests (QA Issue #1)
2. FrameMailbox race conditions (Architecture Issue #1)
3. Missing PPU warm-up period tests (QA Issue #3)
4. Rendering enable/disable untested (QA Issue #5)

### Audit Scope

**Three Independent Reviews Conducted:**
1. **Code Review Agent** - Hardware correctness vs nesdev.org spec
2. **QA Test Coverage Agent** - Test gaps and spec compliance
3. **Architecture Stability Agent** - Threading, synchronization, stability

**Findings Cross-Verified Against:**
- nesdev.org/wiki/NMI
- nesdev.org/wiki/PPU_frame_timing
- nesdev.org/wiki/PPU_registers
- Existing codebase implementation

---

## CRITICAL Issues (Blocking Playability)

### 🔴 SHOWSTOPPER #1: NMI Race Condition

**Severity:** CRITICAL
**Impact:** Games miss NMI interrupts → blank screens, frozen gameplay
**Source:** Code Review Agent, verified via nesdev.org
**Files Affected:**
- `src/emulation/State.zig:670-671, 1142-1147`
- `src/emulation/Ppu.zig:130-133`
- `src/cpu/Logic.zig:76-92`
- `src/ppu/Logic.zig:206`

**Problem Description:**

VBlank flag is set BEFORE NMI level is computed, creating race window:

```
Timeline:
═══════════════════════════════════════════════════════
PPU scanline 241, dot 1:
  [1] state.status.vblank = true        ← VBlank NOW visible to $2002

  [2] CPU can read $2002 HERE!
      → Returns VBlank=1 (sees flag)
      → Clears VBlank flag
      → Game thinks NMI will fire

  [3] stepPpuCycle() completes
      → Computes NMI level: vblank (now FALSE!) && nmi_enable
      → Result: NMI stays LOW

  [4] checkInterrupts() at next fetch_opcode
      → Sees nmi_line still FALSE
      → No edge transition detected
      → NMI never triggers!

Game waits forever for NMI that never comes.
═══════════════════════════════════════════════════════
```

**nesdev.org Confirmation:**

> "Reading $2002 on the same PPU clock or one later reads it as set, clears it, and suppresses NMI"
> "This is due to the $2002 read pulling the NMI line back up too quickly after it drops"

**Reproduction:**
1. Load Super Mario Bros. or BurgerTime
2. Game boots, displays logo (pre-warm-up period)
3. Game enables NMI (PPUCTRL bit 7 = 1)
4. VBlank sets at scanline 241.1
5. Game main loop reads $2002 to check VBlank (common pattern)
6. Read happens on EXACT cycle VBlank sets
7. VBlank cleared, NMI suppressed
8. Game hangs waiting for NMI

**Evidence:**
- CLAUDE.md line 117: "Games not enabling rendering (PPUMASK=$00)"
- CONTROLLER-INPUT-FIX-2025-10-07.md: "Games stuck at title screens"
- PPU-WARMUP-PERIOD-FIX.md: "Commercial games showed blank screens"

**Fix Required:** Latch NMI level ATOMICALLY with VBlank flag set

```zig
// src/emulation/Ppu.zig:130-133
if (scanline == 241 and dot == 1) {
    state.status.vblank = true;
    // FIX: Latch NMI level immediately, before $2002 can be read
    flags.assert_nmi = state.ctrl.nmi_enable;  // Atomic latch
}

// $2002 read can now clear vblank, but NMI already latched and will fire
```

**Estimated Fix Time:** 2-3 hours (requires careful testing)
**Priority:** P0 - MUST FIX IMMEDIATELY

---

### 🔴 CRITICAL #2: FrameMailbox Race Condition

**Severity:** CRITICAL
**Impact:** Incorrect frame display, data races, potential crashes
**Source:** Architecture Stability Agent
**Files Affected:** `src/mailboxes/FrameMailbox.zig`

**Problem Description:**

Mixed synchronization primitives (mutex + atomic) create race condition:

```zig
// Writer (EmulationThread):
pub fn swapBuffers(self: *FrameMailbox) void {
    self.mutex.lock();        // ← Mutex protection
    defer self.mutex.unlock();
    // Swap buffers...
    self.has_new_frame.store(true, .release);  // ← Atomic flag
}

// Reader (RenderThread):
pub fn hasNewFrame(self: *const FrameMailbox) bool {
    return self.has_new_frame.load(.acquire);  // ← NO MUTEX!
}

pub fn getReadBuffer(self: *FrameMailbox) []const u32 {
    self.mutex.lock();        // ← Mutex HERE
    defer self.mutex.unlock();
    return self.read_buffer;
}
```

**Race Scenario:**
```
RenderThread checks hasNewFrame() [atomic, no mutex] → TRUE
EmulationThread calls swapBuffers() [mutex, swaps buffers]
RenderThread calls getReadBuffer() [mutex, gets NEW buffer instead of intended one]
Result: Reading wrong frame data
```

**Fix Required:** Use consistent synchronization (atomic pointer swap recommended)

**Estimated Fix Time:** 3-4 hours
**Priority:** P0 - MUST FIX BEFORE RELEASE

---

### 🔴 CRITICAL #3: Frame Pipeline Synchronization Gap

**Severity:** CRITICAL
**Impact:** Frame overwrites, lost frames, no diagnostic capability
**Source:** Architecture Stability Agent
**Files Affected:** `src/mailboxes/FrameMailbox.zig:swapBuffers()`

**Problem Description:**

No mechanism to detect if emulation produces frames faster than rendering consumes:

```zig
pub fn swapBuffers(self: *FrameMailbox) void {
    // ❌ NO CHECK if previous frame was consumed!
    // Just overwrites read_buffer silently
}
```

**Impact:** Silent frame drops with no way to diagnose

**Fix Required:** Add frame drop counter and optional blocking mode

**Estimated Fix Time:** 2 hours
**Priority:** P0 - Required for stability

---

### 🔴 CRITICAL #4: NO Framebuffer Validation Tests

**Severity:** CRITICAL (Testing Gap)
**Impact:** PPU renders but output never verified
**Source:** QA Test Coverage Agent
**Files Affected:** `tests/` (missing test files)

**Problem Description:**

- 778 tests total, but ZERO test framebuffer pixel output
- PPU rendering pipeline completely untested end-to-end
- 185 commercial ROMs available, NONE tested beyond loading

**Gaps Identified:**
- ❌ NO pixel counting tests
- ❌ NO visual regression tests
- ❌ NO rendering enable/disable validation
- ❌ NO commercial ROM rendering tests

**Fix Required:** Create framebuffer validation framework + commercial ROM tests

**Estimated Fix Time:** 8-12 hours
**Priority:** P0 - Required for playability validation

---

## HIGH Priority Issues

### ⚠️ HIGH #1: PPUSTATUS Read Timing Window

**Severity:** HIGH
**Impact:** NMI suppression window too wide
**Source:** Code Review Agent
**Files Affected:** `src/emulation/State.zig:382`, `src/ppu/Logic.zig:206`

**Problem:**
```zig
const result = PpuLogic.readRegister(&self.ppu, cart_ptr, reg);
if (reg == 0x02) {
    self.refreshPpuNmiLevel();  // ← Happens AFTER read completes
}
```

NMI level refresh happens AFTER VBlank flag already cleared.

**Fix:** Call `refreshPpuNmiLevel()` BEFORE AND AFTER $2002 read

**Estimated Fix Time:** 30 minutes
**Priority:** P1

---

### ⚠️ HIGH #2: NMI Edge Detection Only at Instruction Fetch

**Severity:** HIGH
**Impact:** NMI latency up to 7 CPU cycles
**Source:** Code Review Agent
**Files Affected:** `src/emulation/State.zig:1142-1147`

**Problem:**

```zig
if (self.cpu.state == .fetch_opcode) {
    CpuLogic.checkInterrupts(&self.cpu);  // ← Only polled here!
}
```

NMI can trigger mid-instruction but won't be detected until NEXT instruction.

**nesdev.org says:**
> "The CPU checks for interrupts on the last cycle of each instruction"

**Our implementation:** Only checks at first cycle of NEXT instruction

**Impact:** 2-7 cycle NMI latency depending on instruction length

**Fix:** Poll NMI at END of instruction execution, not beginning of fetch

**Estimated Fix Time:** 1-2 hours
**Priority:** P1

---

### ⚠️ HIGH #3: NO PPU Warm-Up Period Tests

**Severity:** HIGH (Testing Gap)
**Impact:** Recent fix lacks regression tests
**Source:** QA Test Coverage Agent
**Files Affected:** `tests/ppu/` (missing warmup_period_test.zig)

**Problem:**

PPU warm-up period fix documented (CLAUDE.md:53-94) but ZERO regression tests:
- ❌ NO test for 29,658 cycle count
- ❌ NO test for register write blocking
- ❌ NO test for RESET vs power-on distinction

**Risk:** Future refactoring could break warm-up period again

**Fix Required:** Create `tests/ppu/warmup_period_test.zig` with 6-7 test cases

**Estimated Fix Time:** 3 hours
**Priority:** P1 - Prevent regression

---

### ⚠️ HIGH #4: NO Rendering Enable/Disable Tests

**Severity:** HIGH (Testing Gap)
**Impact:** PPUMASK state transitions completely untested
**Source:** QA Test Coverage Agent

**Problem:**

Current issue: "Games not enabling rendering (PPUMASK=$00)" (CLAUDE.md:117)

But ZERO tests for:
- ❌ Enabling rendering mid-frame
- ❌ Disabling rendering mid-frame
- ❌ BG-only vs sprites-only modes
- ❌ Leftmost 8-pixel clipping

**Fix Required:** Create `tests/ppu/rendering_state_test.zig`

**Estimated Fix Time:** 4 hours
**Priority:** P1 - Blocking current issue diagnosis

---

### ⚠️ HIGH #5: NO VBlank NMI Timing Tests

**Severity:** HIGH (Testing Gap)
**Impact:** Critical race window (241.0-241.1) completely untested
**Source:** QA Test Coverage Agent

**Problem:**

Showstopper bug (NMI race) has ZERO test coverage:
- ❌ NO test for reading $2002 at 241.0 (before VBlank)
- ❌ NO test for reading $2002 at 241.1 (during VBlank set)
- ❌ NO test for reading $2002 at 241.2 (after VBlank set)
- ❌ NO test for NMI suppression window

**Fix Required:** Create `tests/ppu/vblank_timing_test.zig`

**Estimated Fix Time:** 3 hours
**Priority:** P1 - Prevent regression of showstopper fix

---

### ⚠️ HIGH #6: Unbounded Input Event Buffers

**Severity:** HIGH
**Impact:** Memory corruption, undefined behavior
**Source:** Architecture Stability Agent
**Files Affected:** `src/main.zig:104-109`

**Problem:**

```zig
var window_events: [16]RAMBO.Mailboxes.XdgWindowEvent = undefined;
var input_events: [32]RAMBO.Mailboxes.XdgInputEvent = undefined;
const input_count = mailboxes.xdg_input_event.drainEvents(&input_events);
// ❌ NO overflow checking! If >32 events, buffer overflow
```

**Impact:** Rapid keyboard input can cause memory corruption

**Fix Required:** Add bounds checking or dynamic allocation

**Estimated Fix Time:** 2 hours
**Priority:** P1 - Memory safety

---

### ⚠️ HIGH #7: EmulationThread Timer Error Recovery

**Severity:** HIGH
**Impact:** Thread termination on transient errors
**Source:** Architecture Stability Agent
**Files Affected:** `src/threads/EmulationThread.zig:66-70`

**Problem:**

```zig
_ = result catch |err| {
    std.debug.print("[Emulation] Timer error: {}\n", .{err});
    return .disarm;  // ❌ Immediate termination!
}
```

Any timer error causes immediate thread death with no recovery.

**Fix Required:** Implement exponential backoff retry with error counting

**Estimated Fix Time:** 2-3 hours
**Priority:** P1 - Stability

---

## MEDIUM Priority Issues

### 🟡 MEDIUM #1: Controller Input Timing Mismatch

**Severity:** MEDIUM
**Impact:** 6 frames of input latency
**Source:** Architecture Stability Agent
**Files Affected:** `src/main.zig:138`, `src/threads/EmulationThread.zig`

**Problem:**

Main thread updates controller input every **100ms**:
```zig
std.Thread.sleep(100_000_000); // 100ms
```

But EmulationThread expects updates every frame (**16.6ms**):
```zig
const input = ctx.mailboxes.controller_input.getInput();
```

**Impact:** 6 frames of input latency (100ms / 16.6ms ≈ 6)

**Fix:** Update input at frame rate (16.6ms), not 100ms

**Estimated Fix Time:** 1 hour
**Priority:** P2

---

### 🟡 MEDIUM #2-#10: See Agent Reports for Details

Additional MEDIUM issues documented in individual agent reports:
- PPU register write ordering during warm-up (Code Review #4)
- Frame complete comment clarity (Code Review #5)
- APU open bus behavior (Code Review #6)
- DMA state machine reentrancy (Architecture #4.3)
- Framebuffer pointer aliasing (Architecture #2.1)
- PPU warm-up state mutation (Architecture #2.2)
- Frame drop detection (Architecture #3.1)
- Infinite loop protection inconsistency (Architecture #5.1)
- Cartridge IRQ polling overhead (Architecture #5.2)

**Estimated Total Fix Time for MEDIUM:** 8-12 hours
**Priority:** P2 - Post-playability refinement

---

## Test Coverage Summary

### Current Test Stats (Per QA Agent Report)

- **Total Tests:** 778 test cases across 53 test files (~16,078 lines)
- **Commercial ROMs Available:** 185 .nes files in tests/data/
- **Commercial ROMs Tested:** **0** (ZERO!)
- **Overall Coverage Score:** **67.5/100** (GOOD with critical gaps)

### Component Scores

| Component | Score | Status | Critical Gaps |
|-----------|-------|--------|---------------|
| CPU | 95/100 | ✅ Excellent | Timing deviation not regression-tested |
| PPU Sprites | 90/100 | ✅ Excellent | No sprite DMA timing tests |
| PPU Background | 60/100 | 🟡 Good | Warm-up, VBlank timing, rendering states |
| APU | 75/100 | 🟡 Good | Integration tests, waveform generation |
| Bus/Memory | 65/100 | 🟡 Adequate | Open bus decay, edge cases |
| Controller I/O | 85/100 | ✅ Good | 22 TODO stubs in integration tests |
| Cartridge | 70/100 | 🟡 Good | Mapper expansion tests needed |
| Debugger | 100/100 | ✅ Excellent | No gaps identified |
| **Integration** | **30/100** | 🔴 **Poor** | **End-to-end, framebuffer, visual** |
| **Commercial ROMs** | **5/100** | 🔴 **Critical** | **NO testing beyond load** |

### Critical Test Gaps (P0)

1. ❌ **NO framebuffer validation tests** - PPU renders but never verified
2. ❌ **NO commercial ROM visual regression tests** - 0 of 185 ROMs tested
3. ❌ **NO PPU warm-up period regression tests** - Recent fix vulnerable
4. ❌ **NO VBlank NMI timing race tests** - Showstopper bug untested
5. ❌ **NO rendering enable/disable tests** - PPUMASK transitions untested

### nesdev.org Spec Compliance

**Current Status:** 🔴 **POOR**

- **Test References:** Only 5 nesdev.org citations in test code
- **Source References:** 13 nesdev.org citations in src/ code
- **Spec Assertions:** Minimal "per nesdev.org" test assertions

**Required Actions:**
1. Add nesdev.org URL comments to all hardware behavior tests
2. Create `tests/spec_compliance/` directory with dedicated spec tests
3. Use explicit spec assertion pattern in all tests

---

## Architecture Stability Summary

### Threading Architecture

**Overall Rating:** 🟡 **6/10** - Functional but with critical issues

**Positive Findings:**
- ✅ Clean State/Logic separation
- ✅ Lock-free mailbox design (mostly correct)
- ✅ Cycle-accurate timing with MasterClock
- ✅ Zero-cost abstraction for mappers
- ✅ RT-safe emulation loop (no allocations)

**Critical Issues:**
- 🔴 FrameMailbox mixed sync primitives (CRITICAL)
- 🔴 Frame pipeline synchronization gap (CRITICAL)
- ⚠️ Timer error recovery missing (HIGH)
- ⚠️ Unbounded event buffers (HIGH)
- 🟡 Controller input timing mismatch (MEDIUM)

### State Management

**Issues Identified:**
- Framebuffer pointer aliasing (HIGH)
- PPU warm-up state mutation in tick (MEDIUM)
- Frame count unsynchronized reads (LOW)

### Thread Coordination

**Topology:**
```
Main Thread → EmulationThread (60 Hz) → FrameMailbox → RenderThread
     ↓
 Input (100ms) → ControllerInputMailbox → EmulationThread
```

**Coordination Issues:**
- Input timing mismatch (100ms vs 16.6ms)
- No error recovery on thread panic
- RenderThread busy-wait (1ms polling)

---

## Root Cause: Why AccuracyCoin Works But Commercial Games Don't

### Test ROMs vs Commercial Games

**AccuracyCoin/nestest:**
- Simple execution patterns
- Don't rely on precise NMI timing
- Minimal $2002 polling
- Designed for deterministic testing

**Commercial Games (Mario, BurgerTime, etc.):**
- Complex main loops with VBlank polling
- Read $2002 every frame to check VBlank
- Rely on EXACT NMI timing for game logic
- Hit the race window frequently

### Timing Window Analysis

**nesdev.org specification:**
> "Reading $2002 within a few PPU clocks of when VBL is set results in special-case behavior:
> - Reading one PPU clock before reads it as clear
> - Reading on the same PPU clock or one later reads it as set, clears it, and suppresses NMI"

**Our implementation:**
- VBlank flag visible immediately (Ppu.zig:131)
- NMI level computed AFTER flag visible (State.zig:670-671)
- Race window: ~1-3 PPU cycles (0.3-0.9 CPU cycles)

**Why games hit this:**
- Games poll $2002 in tight loops
- Probability of hitting exact cycle is HIGH
- Once hit, game hangs forever waiting for NMI

---

## Verification Against nesdev.org

### NMI Behavior (Verified ✅)

**nesdev.org/wiki/NMI:**
> "PPU pulls /NMI low if and only if both vblank_flag and NMI_output are true"
> "By toggling NMI_output during vertical blank without reading PPUSTATUS, a program can cause /NMI to be pulled low multiple times"

**Our implementation:** ✅ MATCHES (when not in race window)

### VBlank Flag Timing (Verified ✅)

**nesdev.org/wiki/PPU_frame_timing:**
> "Reading $2002 on the same PPU clock or one later reads it as set, clears it, and suppresses NMI"

**Our implementation:** ⚠️ VULNERABLE to race condition

### PPU Power-Up State (Verified ✅)

**nesdev.org/wiki/PPU_power_up_state:**
> "PPU ignores writes to certain registers for approximately 29,658 CPU cycles after power-on"

**Our implementation:** ✅ CORRECT (src/ppu/Logic.zig:280)

---

## Summary of Findings by Severity

### CRITICAL (Must Fix Immediately - 4 issues)
1. NMI Race Condition (Showstopper)
2. FrameMailbox Race Condition
3. Frame Pipeline Synchronization Gap
4. NO Framebuffer Validation Tests

**Estimated Fix Time:** 15-22 hours

### HIGH (Fix Before Release - 7 issues)
1. PPUSTATUS Read Timing Window
2. NMI Edge Detection Timing
3. NO PPU Warm-Up Period Tests
4. NO Rendering Enable/Disable Tests
5. NO VBlank NMI Timing Tests
6. Unbounded Input Event Buffers
7. EmulationThread Timer Error Recovery

**Estimated Fix Time:** 15-21 hours

### MEDIUM (Post-Playability - 10 issues)
Various architectural and testing improvements

**Estimated Fix Time:** 8-12 hours

### LOW (Future Enhancement - 5 issues)
Documentation, optimization, minor issues

**Estimated Fix Time:** 4-6 hours

---

## Immediate Actions Required

### STOP ALL DEVELOPMENT

Before ANY new features or mapper expansion:
1. ✅ This comprehensive audit (COMPLETE)
2. ⬜ Fix CRITICAL issues #1-4 (15-22 hours)
3. ⬜ Fix HIGH issues #1-7 (15-21 hours)
4. ⬜ Validate fixes with commercial ROM tests
5. ⬜ Create system stability development plan

### Critical Path to Stability

```
Phase 1: SHOWSTOPPER FIX (2-3 hours)
├── Fix NMI race condition (atomic latch)
├── Add NMI timing regression tests
└── Validate with Mario 1, BurgerTime, Donkey Kong

Phase 2: CRITICAL FIXES (13-19 hours)
├── Fix FrameMailbox race condition
├── Add frame pipeline synchronization
├── Create framebuffer validation framework
├── Add commercial ROM tests
└── Validate all 185 ROMs load and render

Phase 3: HIGH FIXES (15-21 hours)
├── Fix PPUSTATUS read timing
├── Fix NMI edge detection timing
├── Add PPU warm-up period tests
├── Add rendering enable/disable tests
├── Add VBlank timing tests
├── Fix unbounded event buffers
└── Add timer error recovery

Phase 4: VALIDATE STABILITY (4-6 hours)
├── Run full test suite (896 tests)
├── Test all commercial ROMs
├── 72-hour stability soak test
└── Performance regression validation
```

**Total Estimated Time:** 34-49 hours (4.25-6 working days)

---

## Conclusion

The RAMBO NES emulator is **architecturally sound but critically unstable** due to:
1. **Showstopper NMI race condition** preventing commercial ROM playability
2. **Critical test coverage gaps** allowing bugs to slip through
3. **Threading synchronization issues** threatening stability
4. **Insufficient hardware spec compliance** in testing

**The path forward is clear:**
1. Fix the NMI race condition (2-3 hours) → Games should boot
2. Fix FrameMailbox race (3-4 hours) → Stable rendering
3. Add framebuffer/commercial ROM tests (8-12 hours) → Prevent regression
4. Fix remaining HIGH issues (15-21 hours) → Production stability

**After these fixes:** The emulator will be stable, fully tested, and ready for mapper expansion or audio implementation.

**Before these fixes:** ANY additional development risks:
- Cascading bugs
- Unstable releases
- Wasted effort on untested code
- User frustration

---

**Generated:** 2025-10-07
**Session:** docs/sessions/2025-10-07-system-stability-audit/
**Agent Reports:**
- findings/code-review-findings.md
- findings/qa-test-coverage.md
- findings/architecture-stability.md

**Next Document:** SYSTEM-STABILITY-DEVELOPMENT-PLAN.md
