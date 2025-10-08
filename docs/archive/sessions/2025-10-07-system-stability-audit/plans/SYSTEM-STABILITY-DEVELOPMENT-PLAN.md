# RAMBO NES Emulator - System Stability Development Plan

**Date:** 2025-10-07
**Session:** System Stability Investigation
**Status:** 📋 **READY FOR EXECUTION**
**Priority:** 🔴 **CRITICAL - ALL OTHER WORK SUSPENDED**

---

## Overview

This development plan addresses **1 SHOWSTOPPER**, **3 CRITICAL**, **7 HIGH**, and **10 MEDIUM** priority issues identified in the comprehensive system audit. All work is organized into 4 sequential phases with clear validation criteria and no circular dependencies.

**Total Estimated Time:** 34-49 hours (4.25-6 working days)
**Goal:** Production-stable emulator with commercial ROM playability

---

## Guiding Principles

### Development Rules

1. **NO NEW FEATURES** until Phase 4 complete
2. **ALL FIXES MUST HAVE TESTS** (test-first development)
3. **VALIDATE EACH PHASE** before proceeding to next
4. **DOCUMENT ALL CHANGES** in session folder
5. **RUN FULL TEST SUITE** after every change

### Session Organization

All work confined to:
```
docs/sessions/2025-10-07-system-stability-audit/
├── agents/           # Agent audit reports (COMPLETE)
├── findings/         # Comprehensive findings (COMPLETE)
├── plans/            # This document
├── tests/            # Test implementations
├── fixes/            # Fix implementations
├── validation/       # Validation results
└── README.md         # Session summary
```

### Quality Gates

Each phase must pass:
- ✅ All existing tests still pass (896/900 baseline)
- ✅ New tests for fixes added and passing
- ✅ No new compiler warnings
- ✅ Code review by second agent
- ✅ nesdev.org spec compliance verified

---

## Phase 1: SHOWSTOPPER FIX (2-3 hours)

**Objective:** Fix NMI race condition to enable commercial ROM playability
**Blocking:** All game testing and playability validation
**Success Criteria:** Mario 1, BurgerTime, Donkey Kong boot to title screens with rendering enabled

### Task 1.1: Implement NMI Atomic Latch (90 minutes)

**File:** `src/emulation/Ppu.zig`

**Current Code (BROKEN):**
```zig
// Line 130-133
if (scanline == 241 and dot == 1) {
    state.status.vblank = true;  // ← VBlank visible BEFORE NMI latched
    // NOTE: Do NOT set frame_complete here! Frame continues through VBlank.
}
```

**Fixed Code:**
```zig
// VBlank flag set AND NMI level latched ATOMICALLY
if (scanline == 241 and dot == 1) {
    state.status.vblank = true;

    // FIX: Latch NMI level immediately, before $2002 can be read
    // This prevents race condition where CPU reads $2002 between
    // VBlank set and NMI level computation
    flags.assert_nmi = state.ctrl.nmi_enable;
}
```

**Dependencies:** None
**Testing:** Task 1.2
**Validation:** Task 1.3

### Task 1.2: Add NMI Timing Regression Tests (60 minutes)

**File:** `tests/ppu/vblank_nmi_timing_test.zig` (NEW)

**Test Cases (5 tests):**

```zig
test "VBlank NMI: Flag not set at scanline 241 dot 0" {
    // Verify VBlank not set BEFORE 241.1
}

test "VBlank NMI: Flag set at scanline 241 dot 1 per nesdev.org" {
    // nesdev.org: VBlank set at 241.1, not 241.0
}

test "VBlank NMI: NMI fires when vblank && nmi_enable both true" {
    // Verify NMI line asserted correctly
}

test "VBlank NMI: Reading $2002 at 241.1 clears flag but NMI still fires" {
    // CRITICAL: The race condition fix test
    // Read $2002 on exact cycle VBlank sets
    // NMI should STILL fire because it was latched
}

test "VBlank NMI: Reading $2002 before 241.1 prevents NMI" {
    // Reading BEFORE VBlank set should not suppress NMI
    // (VBlank not set yet, nothing to suppress)
}
```

**Helper Required:**
```zig
// Add to TestHarness:
pub fn seekToScanlineDot(self: *Harness, scanline: u16, dot: u16) void {
    while (self.state.clock.scanline() != scanline or
           self.state.clock.dot() != dot) {
        self.state.tick();
    }
}
```

**Dependencies:** Task 1.1 (fix must exist to test it)
**Validation:** All 5 tests must pass

### Task 1.3: Validate with Commercial ROMs (30 minutes)

**Process:**

1. Build emulator with fix: `zig build`
2. Run AccuracyCoin (baseline): Should still pass
3. Run Mario 1 for 180 frames (3 seconds):
   - Check PPUMASK != $00 (rendering enabled)
   - Check framebuffer has >10,000 non-zero pixels
   - Check game advanced past title screen
4. Run BurgerTime for 120 frames
5. Run Donkey Kong for 150 frames

**Validation Script:**
```bash
#!/bin/bash
# tests/validation/validate_phase1.sh

echo "Phase 1 Validation: NMI Race Condition Fix"
echo "=========================================="

# Test 1: Baseline (AccuracyCoin should still pass)
echo "[1/4] Running AccuracyCoin..."
zig build test-integration 2>&1 | grep "accuracycoin" || exit 1

# Test 2: Mario 1
echo "[2/4] Running Super Mario Bros..."
timeout 5s ./zig-out/bin/RAMBO tests/data/Mario/Super\ Mario\ Bros.\ \(World\).nes 2>&1 | grep "PPUMASK" || exit 1

# Test 3: BurgerTime
echo "[3/4] Running BurgerTime..."
timeout 3s ./zig-out/bin/RAMBO tests/data/BurgerTime\ \(USA\).nes || exit 1

# Test 4: Donkey Kong
echo "[4/4] Running Donkey Kong..."
timeout 4s ./zig-out/bin/RAMBO tests/data/Donkey\ Kong/Donkey\ Kong\ \(World\)\ \(Rev\ 1\).nes || exit 1

echo "✅ Phase 1 Validation PASSED"
```

**Success Criteria:**
- ✅ All 5 new tests pass
- ✅ AccuracyCoin still passes
- ✅ Mario 1 boots with rendering enabled
- ✅ No regressions in existing 896 tests

**Estimated Time:** 2-3 hours
**Blocking:** Entire project (nothing can proceed until this is fixed)

---

## Phase 2: CRITICAL STABILITY FIXES (13-19 hours)

**Objective:** Fix remaining CRITICAL threading/testing issues
**Success Criteria:** Stable framebuffer rendering, comprehensive test coverage

### Task 2.1: Fix FrameMailbox Race Condition (3-4 hours)

**File:** `src/mailboxes/FrameMailbox.zig`

**Current Implementation (BROKEN):**
```zig
pub const FrameMailbox = struct {
    write_buffer: []u32,
    read_buffer: []u32,
    mutex: std.Thread.Mutex,              // ← Mixed sync!
    has_new_frame: std.atomic.Value(bool), // ← Mixed sync!
    // ...
};
```

**Fixed Implementation (Atomic Pointer Swap):**
```zig
pub const FrameMailbox = struct {
    buffer_a: []u32,
    buffer_b: []u32,
    current_write: std.atomic.Value(*[]u32), // ← Pure atomic
    current_read: std.atomic.Value(*[]u32),  // ← Pure atomic
    frame_count: std.atomic.Value(u64),
    frames_dropped: std.atomic.Value(u64), // ← New: track drops

    pub fn swapBuffers(self: *FrameMailbox) void {
        // Atomic pointer swap - lock-free!
        const old_write = self.current_write.load(.acquire);
        const old_read = self.current_read.load(.acquire);

        // Check if previous frame consumed
        if (old_write == old_read) {
            // Frame not consumed yet - increment drop counter
            _ = self.frames_dropped.fetchAdd(1, .monotonic);
        }

        // Swap pointers atomically
        self.current_write.store(old_read, .release);
        self.current_read.store(old_write, .release);

        _ = self.frame_count.fetchAdd(1, .monotonic);
    }

    pub fn getReadBuffer(self: *const FrameMailbox) []const u32 {
        // Pure atomic - no mutex needed
        const ptr = self.current_read.load(.acquire);
        return ptr.*;
    }
};
```

**Dependencies:** None
**Testing:** Add `tests/mailboxes/framebuffer_race_test.zig`
**Validation:** Multi-threaded stress test (spawn 4 writer + 4 reader threads)

### Task 2.2: Add Frame Pipeline Synchronization (2 hours)

**Enhancements:**
1. Frame drop detection (already added in Task 2.1)
2. Optional blocking mode for testing
3. Frame statistics API

**New Methods:**
```zig
pub fn getFrameDropCount(self: *const FrameMailbox) u64 {
    return self.frames_dropped.load(.monotonic);
}

pub fn resetStatistics(self: *FrameMailbox) void {
    self.frames_dropped.store(0, .monotonic);
}

pub fn swapBuffersBlocking(self: *FrameMailbox, timeout_ns: u64) !void {
    // Wait for previous frame to be consumed (for testing)
    const start = std.time.nanoTimestamp();
    while (self.current_write.load(.acquire) ==
           self.current_read.load(.acquire)) {
        if (std.time.nanoTimestamp() - start > timeout_ns) {
            return error.Timeout;
        }
        std.Thread.yield() catch {};
    }
    self.swapBuffers();
}
```

**Dependencies:** Task 2.1
**Testing:** `tests/mailboxes/frame_pipeline_test.zig`

### Task 2.3: Create Framebuffer Validation Framework (3-4 hours)

**File:** `tests/visual/framebuffer_validation.zig` (NEW)

**Framework Functions:**

```zig
/// Count non-zero pixels in framebuffer
pub fn countNonZeroPixels(framebuffer: []const u32) usize {
    var count: usize = 0;
    for (framebuffer) |pixel| {
        if (pixel != 0) count += 1;
    }
    return count;
}

/// Calculate CRC64 hash for regression testing
pub fn framebufferHash(framebuffer: []const u32) u64 {
    var hasher = std.hash.Crc64.init();
    const bytes = std.mem.sliceAsBytes(framebuffer);
    hasher.update(bytes);
    return hasher.final();
}

/// Compare framebuffers with tolerance
pub fn framebuffersDiffer(
    fb1: []const u32,
    fb2: []const u32,
    tolerance_percent: f32
) bool {
    var diff_count: usize = 0;
    for (fb1, fb2) |p1, p2| {
        if (p1 != p2) diff_count += 1;
    }
    const diff_ratio = @as(f32, @floatFromInt(diff_count)) /
                       @as(f32, @floatFromInt(fb1.len));
    return diff_ratio > (tolerance_percent / 100.0);
}

/// Save framebuffer as PPM (portable pixmap)
pub fn saveFramebufferPPM(
    framebuffer: []const u32,
    path: []const u8,
    allocator: std.mem.Allocator
) !void {
    // Simple PPM format (P3 - ASCII, easy to debug)
    const file = try std.fs.cwd().createFile(path, .{});
    defer file.close();

    var writer = file.writer();
    try writer.print("P3\n256 240\n255\n", .{});

    for (framebuffer, 0..) |pixel, i| {
        const r = (pixel >> 16) & 0xFF;
        const g = (pixel >> 8) & 0xFF;
        const b = pixel & 0xFF;
        try writer.print("{d} {d} {d} ", .{r, g, b});
        if ((i + 1) % 256 == 0) try writer.writeByte('\n');
    }
}
```

**Unit Tests:**
```zig
test "Framebuffer Validation: Count non-zero pixels" { }
test "Framebuffer Validation: Hash consistency" { }
test "Framebuffer Validation: Diff tolerance" { }
test "Framebuffer Validation: PPM export" { }
```

**Dependencies:** None
**Testing:** Self-testing (unit tests above)

### Task 2.4: Add Commercial ROM Tests (6-8 hours)

**File:** `tests/integration/commercial_rom_test.zig` (NEW)

**Test Structure:**

```zig
const CommercialRomTest = struct {
    name: []const u8,
    path: []const u8,
    frames_to_stable: usize,
    min_non_zero_pixels: usize,
    should_enable_rendering: bool,
    expected_hash: ?u64, // Golden hash for regression
};

const COMMERCIAL_ROMS = [_]CommercialRomTest{
    .{
        .name = "Super Mario Bros.",
        .path = "tests/data/Mario/Super Mario Bros. (World).nes",
        .frames_to_stable = 180,
        .min_non_zero_pixels = 10000,
        .should_enable_rendering = true,
        .expected_hash = null, // Generate on first run
    },
    .{
        .name = "BurgerTime",
        .path = "tests/data/BurgerTime (USA).nes",
        .frames_to_stable = 120,
        .min_non_zero_pixels = 8000,
        .should_enable_rendering = true,
        .expected_hash = null,
    },
    .{
        .name = "Donkey Kong",
        .path = "tests/data/Donkey Kong/Donkey Kong (World) (Rev 1).nes",
        .frames_to_stable = 150,
        .min_non_zero_pixels = 12000,
        .should_enable_rendering = true,
        .expected_hash = null,
    },
    .{
        .name = "Balloon Fight",
        .path = "tests/data/Balloon Fight (USA, Europe, Korea) (En).nes",
        .frames_to_stable = 100,
        .min_non_zero_pixels = 5000,
        .should_enable_rendering = true,
        .expected_hash = null,
    },
    .{
        .name = "Ice Climber",
        .path = "tests/data/Ice Climber (USA, Europe, Korea) (En).nes",
        .frames_to_stable = 110,
        .min_non_zero_pixels = 6000,
        .should_enable_rendering = true,
        .expected_hash = null,
    },
    // Add 10-15 more Mapper 0 games
};

test "Commercial ROMs: All load without crash" {
    for (COMMERCIAL_ROMS) |rom_test| {
        // Load ROM and run for 10 frames
        // Validate no crash/panic
    }
}

test "Commercial ROMs: Title screens render (non-blank)" {
    for (COMMERCIAL_ROMS) |rom_test| {
        // Run to frames_to_stable
        // Count non-zero pixels
        // Validate > min_non_zero_pixels
    }
}

test "Commercial ROMs: Rendering enabled (PPUMASK)" {
    for (COMMERCIAL_ROMS) |rom_test| {
        // Run to frames_to_stable
        // Check PPUMASK bits 3/4 set
    }
}

test "Commercial ROMs: Visual regression (hash check)" {
    for (COMMERCIAL_ROMS) |rom_test| {
        if (rom_test.expected_hash) |expected| {
            // Run to frames_to_stable
            // Hash framebuffer
            // Compare to golden hash
        }
    }
}
```

**Test Helper (ROM Test Runner):**

```zig
// tests/helpers/RomTestRunner.zig (NEW)
pub const RomTestRunner = struct {
    state: *EmulationState,
    allocator: std.mem.Allocator,

    pub fn init(
        allocator: std.mem.Allocator,
        rom_path: []const u8,
        options: struct {
            max_frames: usize = 60,
            verbose: bool = false,
        }
    ) !RomTestRunner {
        // Load ROM
        // Initialize emulation state
        // Return runner
    }

    pub fn deinit(self: *RomTestRunner) void {
        // Cleanup
    }

    pub fn runFrames(self: *RomTestRunner, frame_count: usize) !void {
        for (0..frame_count) |_| {
            // Run one frame worth of cycles
            while (!self.state.isFrameComplete()) {
                self.state.tick();
            }
        }
    }

    pub fn getFramebuffer(self: *const RomTestRunner) []const u32 {
        return self.state.framebuffer orelse &[_]u32{};
    }

    pub fn getPpuMask(self: *const RomTestRunner) u8 {
        return self.state.ppu.mask.toByte();
    }
};
```

**Dependencies:** Task 2.3 (framebuffer validation)
**Validation:** All ROMs load, render, and pass visual checks

**Estimated Phase 2 Time:** 14-18 hours

---

## Phase 3: HIGH PRIORITY FIXES (15-21 hours)

**Objective:** Fix remaining HIGH issues for production stability
**Success Criteria:** All timing issues resolved, comprehensive test coverage

### Task 3.1: Fix PPUSTATUS Read Timing (30 minutes)

**File:** `src/emulation/State.zig:377-384`

**Current Code:**
```zig
0x2000...0x3FFF => blk: {
    const reg = address & 0x07;
    const result = PpuLogic.readRegister(&self.ppu, cart_ptr, reg);
    if (reg == 0x02) {
        self.refreshPpuNmiLevel();  // ← AFTER read
    }
    break :blk result;
}
```

**Fixed Code:**
```zig
0x2000...0x3FFF => blk: {
    const reg = address & 0x07;

    // FIX: Refresh NMI level BEFORE and AFTER $2002 read
    if (reg == 0x02) {
        self.refreshPpuNmiLevel();  // BEFORE: Capture current level
    }

    const result = PpuLogic.readRegister(&self.ppu, cart_ptr, reg);

    if (reg == 0x02) {
        self.refreshPpuNmiLevel();  // AFTER: Update after VBlank cleared
    }

    break :blk result;
}
```

**Dependencies:** None
**Testing:** Add test to `vblank_nmi_timing_test.zig`
**Validation:** Ensure NMI suppression window matches nesdev.org spec

### Task 3.2: Fix NMI Edge Detection Timing (1-2 hours)

**File:** `src/emulation/State.zig:1142-1148`

**Current Code:**
```zig
// Check at START of instruction fetch
if (self.cpu.state == .fetch_opcode) {
    CpuLogic.checkInterrupts(&self.cpu);
    // ...
}
```

**Fixed Code:**
```zig
// Check at END of instruction execution (per nesdev.org)
if (self.cpu.state == .execute) {
    // Execute instruction...

    // Check interrupts AFTER execution completes
    CpuLogic.checkInterrupts(&self.cpu);
    if (self.cpu.pending_interrupt != .none) {
        CpuLogic.startInterruptSequence(&self.cpu);
        return;
    }

    // Transition to fetch
    self.cpu.state = .fetch_opcode;
} else if (self.cpu.state == .fetch_opcode) {
    // Already checked interrupts, proceed with fetch
    // ...
}
```

**Dependencies:** None
**Testing:** Add NMI latency test
**Validation:** NMI latency ≤ instruction length (not instruction + 1)

### Task 3.3: Add PPU Warm-Up Period Tests (3 hours)

**File:** `tests/ppu/warmup_period_test.zig` (NEW)

**Test Cases (7 tests):**
```zig
test "PPU Warm-up: PPUCTRL writes ignored before 29658 cycles" { }
test "PPU Warm-up: PPUMASK writes ignored during warm-up" { }
test "PPU Warm-up: PPUSCROLL writes ignored during warm-up" { }
test "PPU Warm-up: PPUADDR writes ignored during warm-up" { }
test "PPU Warm-up: Completes after 29658 CPU cycles" { }
test "PPU Warm-up: RESET skips warm-up period" { }
test "PPU Warm-up: PPUDATA reads/writes allowed during warm-up" { }
```

**Dependencies:** None (testing existing fix)
**Validation:** All 7 tests pass

### Task 3.4: Add Rendering Enable/Disable Tests (4 hours)

**File:** `tests/ppu/rendering_state_test.zig` (NEW)

**Test Cases (6 tests):**
```zig
test "PPU Rendering: Enable rendering mid-frame" { }
test "PPU Rendering: Disable rendering mid-frame" { }
test "PPU Rendering: Enable BG only (sprites disabled)" { }
test "PPU Rendering: Enable sprites only (BG disabled)" { }
test "PPU Rendering: Leftmost 8 pixels clipping (BG)" { }
test "PPU Rendering: Leftmost 8 pixels clipping (sprites)" { }
```

**Dependencies:** Task 2.3 (framebuffer validation)
**Validation:** Framebuffer output changes correctly with PPUMASK

### Task 3.5: Fix Unbounded Input Event Buffers (2 hours)

**File:** `src/main.zig:104-109`

**Current Code:**
```zig
var window_events: [16]RAMBO.Mailboxes.XdgWindowEvent = undefined;
var input_events: [32]RAMBO.Mailboxes.XdgInputEvent = undefined;
const input_count = mailboxes.xdg_input_event.drainEvents(&input_events);
// ❌ NO overflow check
```

**Fixed Code:**
```zig
var window_events: [16]RAMBO.Mailboxes.XdgWindowEvent = undefined;
var input_events: [32]RAMBO.Mailboxes.XdgInputEvent = undefined;

// Check mailbox count before draining
const available_events = mailboxes.xdg_input_event.getEventCount();
if (available_events > input_events.len) {
    std.debug.print("WARNING: Input buffer overflow! {d} events, buffer size {d}\n",
                   .{available_events, input_events.len});
    // Drain in batches to prevent overflow
    var remaining = available_events;
    while (remaining > 0) {
        const batch_size = @min(remaining, input_events.len);
        const count = mailboxes.xdg_input_event.drainEvents(input_events[0..batch_size]);
        // Process batch...
        remaining -= count;
    }
} else {
    const input_count = mailboxes.xdg_input_event.drainEvents(&input_events);
    // Process normally...
}
```

**Alternative:** Use dynamic allocation with arena allocator

**Dependencies:** None
**Testing:** Stress test with rapid input
**Validation:** No buffer overflow under load

### Task 3.6: Add EmulationThread Timer Error Recovery (2-3 hours)

**File:** `src/threads/EmulationThread.zig:66-70`

**Current Code:**
```zig
_ = result catch |err| {
    std.debug.print("[Emulation] Timer error: {}\n", .{err});
    return .disarm;  // ❌ Immediate termination
};
```

**Fixed Code:**
```zig
const MAX_RETRIES = 3;
const BACKOFF_BASE_MS = 10;

_ = result catch |err| {
    self.error_count += 1;
    std.debug.print("[Emulation] Timer error #{d}: {}\n",
                   .{self.error_count, err});

    if (self.error_count > MAX_RETRIES) {
        std.debug.print("[Emulation] Max retries exceeded, disarming\n", .{});
        return .disarm;
    }

    // Exponential backoff
    const backoff_ms = BACKOFF_BASE_MS *
                       std.math.pow(u64, 2, self.error_count - 1);
    std.Thread.sleep(backoff_ms * std.time.ns_per_ms);

    std.debug.print("[Emulation] Retrying timer (backoff={d}ms)...\n",
                   .{backoff_ms});
    return .rearm;  // Try again
};

// Reset error count on successful execution
self.error_count = 0;
```

**Dependencies:** None
**Testing:** Inject timer errors artificially
**Validation:** Thread recovers from transient errors

### Task 3.7: Fix Controller Input Timing (1 hour)

**File:** `src/main.zig:138`

**Current Code:**
```zig
std.Thread.sleep(100_000_000); // 100ms - TOO SLOW!
```

**Fixed Code:**
```zig
std.Thread.sleep(16_666_666); // 16.6ms (60 Hz frame rate)
```

**Dependencies:** None
**Testing:** Input latency measurement
**Validation:** Input latency ≤ 1 frame (16.6ms)

**Estimated Phase 3 Time:** 13.5-18.5 hours

---

## Phase 4: VALIDATION & STABILIZATION (4-6 hours)

**Objective:** Comprehensive validation of all fixes
**Success Criteria:** 72-hour stability, all tests passing, commercial ROM playability

### Task 4.1: Full Test Suite Validation (1 hour)

```bash
# Run ALL tests
zig build test

# Expected results:
# - 896 baseline tests still passing
# - +60 new tests (Phase 1-3) passing
# Total: 956/956 tests passing (100%)
```

**Validation:**
- ✅ All existing tests still pass
- ✅ All new tests pass
- ✅ No test skips or todos
- ✅ Test coverage >75%

### Task 4.2: Commercial ROM Comprehensive Testing (2 hours)

**Test Matrix:**

| ROM | Mapper | Load | Render | Input | Pass |
|-----|--------|------|--------|-------|------|
| Super Mario Bros. | 0 | ✅ | ✅ | ✅ | ✅ |
| BurgerTime | 0 | ✅ | ✅ | ✅ | ✅ |
| Donkey Kong | 0 | ✅ | ✅ | ✅ | ✅ |
| Balloon Fight | 0 | ✅ | ✅ | ✅ | ✅ |
| Ice Climber | 0 | ✅ | ✅ | ✅ | ✅ |
| Excitebike | 0 | ✅ | ✅ | ✅ | ✅ |
| Kung Fu | 0 | ✅ | ✅ | ✅ | ✅ |
| Popeye | 0 | ✅ | ✅ | ✅ | ✅ |
| (20+ more) | 0 | ... | ... | ... | ... |

**Validation Script:**
```bash
#!/bin/bash
# tests/validation/validate_commercial_roms.sh

echo "Commercial ROM Comprehensive Testing"
echo "===================================="

PASS=0
FAIL=0

for rom in tests/data/*.nes tests/data/*/*.nes; do
    if [[ -f "$rom" ]]; then
        echo "Testing: $rom"
        timeout 10s ./zig-out/bin/RAMBO "$rom" > /tmp/rom_test.log 2>&1

        if grep -q "PPUMASK" /tmp/rom_test.log; then
            echo "  ✅ PASS"
            ((PASS++))
        else
            echo "  ❌ FAIL"
            ((FAIL++))
        fi
    fi
done

echo ""
echo "Results: $PASS passed, $FAIL failed"
```

**Success Criteria:**
- ✅ >90% of Mapper 0 ROMs load successfully
- ✅ >80% of Mapper 0 ROMs render correctly
- ✅ No crashes or panics

### Task 4.3: 72-Hour Stability Soak Test (1 hour setup + 72 hours run)

**Test Configuration:**
```zig
// tests/stability/soak_test.zig
test "Stability: 72-hour continuous operation" {
    const DURATION_HOURS = 72;
    const FRAME_COUNT = DURATION_HOURS * 3600 * 60; // 60 FPS

    var state = try EmulationState.init(allocator);
    defer state.deinit();

    // Load long-running ROM
    try state.loadRom("tests/data/Mario/Super Mario Bros. (World).nes");

    var frame: usize = 0;
    while (frame < FRAME_COUNT) : (frame += 1) {
        // Run one frame
        state.emulateFrame() catch |err| {
            std.debug.print("FAILURE at frame {d}: {}\n", .{frame, err});
            return err;
        };

        // Log progress every hour
        if (frame % (3600 * 60) == 0) {
            const hours = frame / (3600 * 60);
            std.debug.print("[Soak Test] {d} hours completed\n", .{hours});
        }
    }

    std.debug.print("✅ 72-hour soak test PASSED\n", .{});
}
```

**Validation:**
- ✅ No crashes or panics
- ✅ No memory leaks
- ✅ Consistent frame timing
- ✅ Frame drop rate <0.1%

### Task 4.4: Performance Regression Validation (30 minutes)

**Benchmark Suite:**
```zig
// tests/benchmarks/performance_test.zig

test "Performance: CPU emulation speed" {
    // Measure CPU cycles/second
    // Baseline: >1.79 MHz (hardware speed)
}

test "Performance: PPU rendering speed" {
    // Measure frames/second
    // Baseline: >60 FPS sustained
}

test "Performance: Frame time consistency" {
    // Measure frame time variance
    // Baseline: σ < 1ms
}
```

**Validation:**
- ✅ CPU speed ≥ 1.79 MHz
- ✅ Frame rate ≥ 60 FPS
- ✅ Frame time variance ≤ 1ms

**Estimated Phase 4 Time:** 4-6 hours (+ 72 hours soak time)

---

## Quality Assurance Checklist

### Code Quality

- [ ] All code follows Zig style guide
- [ ] No compiler warnings
- [ ] No TODO/FIXME comments in production code
- [ ] All public APIs documented
- [ ] Error handling comprehensive

### Testing

- [ ] All unit tests passing (100%)
- [ ] All integration tests passing (100%)
- [ ] Commercial ROM tests passing (>90%)
- [ ] nesdev.org spec compliance verified
- [ ] Visual regression tests passing

### Documentation

- [ ] All fixes documented in session folder
- [ ] CLAUDE.md updated with new status
- [ ] Session README.md summarizes work
- [ ] All nesdev.org citations added to tests

### Performance

- [ ] No performance regressions
- [ ] Memory usage stable
- [ ] Frame timing consistent
- [ ] CPU/PPU emulation speed maintained

### Stability

- [ ] 72-hour soak test passed
- [ ] No thread deadlocks
- [ ] No race conditions
- [ ] Error recovery functional

---

## Risk Mitigation

### Identified Risks

**Risk 1: NMI Fix Breaks Existing Tests**
- **Mitigation:** Run full test suite after every change
- **Rollback Plan:** Git commits for each task

**Risk 2: FrameMailbox Atomic Refactor Too Complex**
- **Mitigation:** Incremental changes with intermediate testing
- **Alternative:** Keep mutex-based approach, add overflow protection

**Risk 3: 72-Hour Soak Test Reveals New Issues**
- **Mitigation:** Address issues as they arise, extend timeline if needed
- **Acceptance:** Some long-term stability issues may require Phase 5

**Risk 4: Commercial ROMs Still Don't Work**
- **Mitigation:** Debug systematically with nesdev.org documentation
- **Escalation:** Consult NES emulation community if stuck >8 hours

### Contingency Plans

**If Phase 1 Fails:**
- Revert NMI fix
- Implement alternative approach (delay VBlank visibility)
- Consult nesdev.org forum

**If Phase 2 Extends Beyond 19 Hours:**
- Re-prioritize: Complete FrameMailbox + framebuffer validation only
- Defer commercial ROM tests to Phase 5

**If Phase 3 Extends Beyond 21 Hours:**
- Complete only P0 tasks (unbounded buffers, timer recovery)
- Defer timing fixes to Phase 5

**If Phase 4 Soak Test Fails:**
- Collect diagnostic data
- Root cause analysis
- Create Phase 5 for long-term stability

---

## Success Metrics

### Phase 1 Success
- ✅ Mario 1 boots to title with rendering
- ✅ 5/5 new NMI tests passing
- ✅ 0 regressions

### Phase 2 Success
- ✅ FrameMailbox race-free
- ✅ >90% commercial ROMs load
- ✅ Framebuffer validation framework functional

### Phase 3 Success
- ✅ All HIGH issues fixed
- ✅ Comprehensive test coverage
- ✅ nesdev.org spec compliance verified

### Phase 4 Success
- ✅ 956/956 tests passing
- ✅ 72-hour soak test passed
- ✅ >80% commercial ROMs playable
- ✅ Production-stable emulator

---

## Timeline

### Optimistic (34 hours)
- **Week 1:** Phase 1 (2h) + Phase 2 (14h) + Phase 3 Start (8h)
- **Week 2:** Phase 3 Complete (6h) + Phase 4 (4h)
- **Total:** 2 weeks

### Realistic (42 hours)
- **Week 1:** Phase 1 (3h) + Phase 2 (16h) + Phase 3 Start (12h)
- **Week 2:** Phase 3 Complete (7h) + Phase 4 (5h) + Buffer (2h)
- **Total:** 2.5 weeks

### Pessimistic (49 hours)
- **Week 1:** Phase 1 (3h) + Phase 2 (19h) + Phase 3 Start (10h)
- **Week 2:** Phase 3 Complete (11h) + Phase 4 (6h)
- **Week 3:** Buffer/Debug (4h)
- **Total:** 3 weeks

**Recommended:** Plan for **Realistic** timeline (2.5 weeks)

---

## Next Steps

### Immediate (This Session)
1. ✅ Create this development plan (COMPLETE)
2. ⬜ Review plan with user
3. ⬜ Get approval to proceed
4. ⬜ Begin Phase 1 Task 1.1 (NMI atomic latch)

### Phase 1 (Days 1-2)
1. Implement NMI atomic latch
2. Add NMI timing tests
3. Validate with commercial ROMs
4. Celebrate first playable games!

### Phase 2 (Days 3-7)
1. Fix FrameMailbox race
2. Add frame synchronization
3. Create framebuffer validation
4. Add commercial ROM tests

### Phase 3 (Days 8-13)
1. Fix timing issues
2. Add comprehensive tests
3. Fix stability issues

### Phase 4 (Days 14-16 + 72h soak)
1. Full validation
2. Soak test
3. Performance validation
4. Production release

---

## Conclusion

This plan provides a clear, systematic path from **"showstopper bugs"** to **"production-stable emulator"** in 2-3 weeks of focused work.

**Key Success Factors:**
1. **Test-first development** - Every fix has tests
2. **Incremental validation** - Verify each phase before proceeding
3. **No circular dependencies** - Clear task ordering
4. **Quality gates** - Strict pass/fail criteria
5. **Risk mitigation** - Contingencies for every phase

**After Completion:**
- Commercial ROM playability ✅
- Production stability ✅
- Comprehensive test coverage ✅
- Ready for mapper expansion ✅
- Ready for audio implementation ✅

**The foundation will be rock-solid, and all future development will build on a stable base.**

---

**Document Status:** ✅ COMPLETE - Ready for Review
**Next Action:** Present to user for approval
**Session Folder:** `docs/sessions/2025-10-07-system-stability-audit/`
