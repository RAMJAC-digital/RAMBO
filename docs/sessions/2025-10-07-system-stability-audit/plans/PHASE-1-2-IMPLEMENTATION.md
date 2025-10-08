# Phase 1+2 Implementation Plan - NMI Fix + Pure Atomic FrameMailbox

**Date:** 2025-10-07
**Status:** 🚀 EXECUTING
**Estimated Time:** 5-7 hours (Phase 1: 2-3h, Phase 2: 3-4h)

---

## Design Principles

### 1. Pure Atomics - NO Mutex
- FrameMailbox uses **ONLY** atomic operations
- Lock-free ring buffer with preallocated buffers
- Simple, straightforward implementation

### 2. Zero Allocations Per Frame
- All buffers preallocated at initialization
- Ring buffer with fixed-size slots
- NTSC: 256×240 = 61,440 pixels, PAL: 256×240 (same, we handle timing not resolution)

### 3. libxev Threading
- Use existing libxev integration for thread management
- No new threading primitives
- Address segfault/failing test issues

### 4. Vulkan State Management
- Clear buffer ownership at all times
- Proper ordering: PPU write → swap → Vulkan read
- No race conditions in texture upload

### 5. Test Stability
- All existing 896 tests must continue passing
- Add new tests for fixes
- No regressions

---

## Phase 1: NMI Showstopper Fix (2-3 hours)

### Implementation Strategy

**Objective:** Fix NMI race condition with minimal, surgical change

**Key Constraint:** Change ONLY what's necessary, validate thoroughly

### Task 1.1: Implement NMI Atomic Latch (60 minutes)

#### Current Problem Analysis

**File:** `src/emulation/Ppu.zig:130-133`

```zig
// CURRENT (BROKEN):
if (scanline == 241 and dot == 1) {
    state.status.vblank = true;  // ← VBlank visible to $2002 reads
    // ... NMI computed LATER in State.zig:670-671
}
```

**Race Window:**
1. VBlank flag set (visible to CPU)
2. CPU can read $2002 HERE (clears flag)
3. NMI level computed (sees cleared flag)
4. NMI never fires

#### Fix Implementation

**File:** `src/emulation/Ppu.zig`

**Change Location:** Lines 130-133

**BEFORE:**
```zig
// === VBlank ===
if (scanline == 241 and dot == 1) {
    state.status.vblank = true;
    // NOTE: Do NOT set frame_complete here! Frame continues through VBlank.
}
```

**AFTER:**
```zig
// === VBlank ===
if (scanline == 241 and dot == 1) {
    state.status.vblank = true;

    // FIX: Latch NMI level ATOMICALLY with VBlank flag set
    // This prevents race condition where CPU reads $2002 between
    // VBlank set and NMI level computation (per nesdev.org)
    // Reading $2002 can now clear vblank, but NMI already latched
    flags.assert_nmi = state.ctrl.nmi_enable;

    // NOTE: Do NOT set frame_complete here! Frame continues through VBlank.
}
```

**Validation:**
- VBlank flag set and NMI latched in **same operation**
- $2002 read can clear flag, but NMI already determined
- No changes to EmulationState NMI handling needed

#### Testing Strategy

**File:** `tests/ppu/vblank_nmi_timing_test.zig` (NEW)

**Test Helper First:**

```zig
// Add to src/test_harness/Harness.zig
pub fn seekToScanlineDot(self: *Harness, target_scanline: u16, target_dot: u16) void {
    // Advance emulation to exact scanline.dot position
    const max_cycles: usize = 100_000; // Safety limit
    var cycles: usize = 0;

    while (cycles < max_cycles) : (cycles += 1) {
        const current_sl = self.state.clock.scanline();
        const current_dot = self.state.clock.dot();

        if (current_sl == target_scanline and current_dot == target_dot) {
            return; // Exact position reached
        }

        self.state.tick();
    }

    @panic("seekToScanlineDot: Failed to reach target position");
}

pub fn getScanline(self: *const Harness) u16 {
    return self.state.clock.scanline();
}

pub fn getDot(self: *const Harness) u16 {
    return self.state.clock.dot();
}
```

**Critical Test Cases:**

```zig
//! VBlank NMI Timing Tests
//!
//! Hardware Reference: https://www.nesdev.org/wiki/PPU_frame_timing#VBlank_Flag
//! Hardware Reference: https://www.nesdev.org/wiki/NMI
//!
//! Tests the critical NMI race condition fix:
//! - VBlank flag set at scanline 241, dot 1
//! - NMI must be latched ATOMICALLY with VBlank set
//! - Reading $2002 clears VBlank but NMI should still fire

const std = @import("std");
const testing = std.testing;
const RAMBO = @import("RAMBO");
const Harness = RAMBO.TestHarness.Harness;

test "VBlank NMI: Flag NOT set at scanline 241 dot 0" {
    var harness = try Harness.init(testing.allocator);
    defer harness.deinit();

    // Skip warm-up period
    harness.state.ppu.warmup_complete = true;

    // Seek to scanline 241, dot 0 (BEFORE VBlank)
    harness.seekToScanlineDot(241, 0);

    // VBlank should NOT be set yet
    try testing.expect(!harness.state.ppu.status.vblank);
    try testing.expectEqual(@as(u16, 241), harness.getScanline());
    try testing.expectEqual(@as(u16, 0), harness.getDot());
}

test "VBlank NMI: Flag set at scanline 241 dot 1 per nesdev.org" {
    var harness = try Harness.init(testing.allocator);
    defer harness.deinit();

    harness.state.ppu.warmup_complete = true;

    // Seek to scanline 241, dot 1 (VBlank set point)
    harness.seekToScanlineDot(241, 1);

    // VBlank should NOW be set
    try testing.expect(harness.state.ppu.status.vblank);
    try testing.expectEqual(@as(u16, 241), harness.getScanline());
    try testing.expectEqual(@as(u16, 1), harness.getDot());
}

test "VBlank NMI: NMI fires when vblank && nmi_enable both true" {
    var harness = try Harness.init(testing.allocator);
    defer harness.deinit();

    harness.state.ppu.warmup_complete = true;

    // Enable NMI generation
    harness.state.ppu.ctrl.nmi_enable = true;

    // Advance to BEFORE VBlank
    harness.seekToScanlineDot(241, 0);
    try testing.expect(!harness.state.cpu.nmi_line);

    // Tick to dot 1 (VBlank set)
    harness.state.tick();

    // NMI line should be asserted
    try testing.expect(harness.state.cpu.nmi_line);
}

test "VBlank NMI: Reading $2002 at 241.1 clears flag but NMI STILL fires" {
    // THIS IS THE CRITICAL RACE CONDITION TEST
    var harness = try Harness.init(testing.allocator);
    defer harness.deinit();

    harness.state.ppu.warmup_complete = true;
    harness.state.ppu.ctrl.nmi_enable = true;

    // Advance to dot 0 (one cycle before VBlank)
    harness.seekToScanlineDot(241, 0);

    // Tick to dot 1 - this sets VBlank AND latches NMI atomically
    harness.state.tick();

    // VBlank should be set
    try testing.expect(harness.state.ppu.status.vblank);

    // NMI should be latched
    try testing.expect(harness.state.cpu.nmi_line);

    // NOW: Simulate the race condition - CPU reads $2002
    // This would previously suppress NMI, but should no longer
    _ = harness.state.busRead(0x2002);

    // VBlank flag should be CLEARED by the read
    try testing.expect(!harness.state.ppu.status.vblank);

    // BUT: NMI line should STILL be asserted (already latched!)
    try testing.expect(harness.state.cpu.nmi_line);

    // This is the FIX: NMI was latched BEFORE $2002 could clear the flag
}

test "VBlank NMI: Reading $2002 BEFORE 241.1 does not affect NMI" {
    var harness = try Harness.init(testing.allocator);
    defer harness.deinit();

    harness.state.ppu.warmup_complete = true;
    harness.state.ppu.ctrl.nmi_enable = true;

    // Advance to dot 0 (before VBlank)
    harness.seekToScanlineDot(241, 0);

    // Read $2002 BEFORE VBlank sets
    _ = harness.state.busRead(0x2002);

    // VBlank not set yet, so nothing to clear
    try testing.expect(!harness.state.ppu.status.vblank);
    try testing.expect(!harness.state.cpu.nmi_line);

    // Tick to dot 1 - VBlank sets normally
    harness.state.tick();

    // VBlank and NMI should both be active
    try testing.expect(harness.state.ppu.status.vblank);
    try testing.expect(harness.state.cpu.nmi_line);
}
```

**Validation:**
- All 5 tests must pass
- Existing 896 tests must still pass
- No compiler warnings

**Estimated Time:** 60 minutes (implementation + tests)

---

### Task 1.2: Validate with Commercial ROMs (30 minutes)

**Manual Test Script:**

```bash
#!/bin/bash
# tests/validation/phase1_commercial_roms.sh

echo "=== Phase 1 Validation: Commercial ROM Boot Test ==="
echo ""

# Build with fix
echo "[1/5] Building with NMI fix..."
zig build || exit 1

# Test 1: Baseline (AccuracyCoin should still pass)
echo ""
echo "[2/5] Baseline: AccuracyCoin..."
timeout 10s ./zig-out/bin/RAMBO tests/data/AccuracyCoin.nes 2>&1 | tee /tmp/accuracycoin.log
if grep -q "PASS" /tmp/accuracycoin.log; then
    echo "✅ AccuracyCoin: PASS"
else
    echo "❌ AccuracyCoin: FAIL (REGRESSION!)"
    exit 1
fi

# Test 2: Mario 1
echo ""
echo "[3/5] Super Mario Bros..."
timeout 5s ./zig-out/bin/RAMBO "tests/data/Mario/Super Mario Bros. (World).nes" 2>&1 | tee /tmp/mario.log
if grep -q "Frame" /tmp/mario.log; then
    echo "✅ Mario 1: Boots (check rendering manually)"
else
    echo "❌ Mario 1: Failed to boot"
fi

# Test 3: BurgerTime
echo ""
echo "[4/5] BurgerTime..."
timeout 3s ./zig-out/bin/RAMBO "tests/data/BurgerTime (USA).nes" 2>&1 | tee /tmp/burgertime.log
if grep -q "Frame" /tmp/burgertime.log; then
    echo "✅ BurgerTime: Boots"
else
    echo "❌ BurgerTime: Failed"
fi

# Test 4: Donkey Kong
echo ""
echo "[5/5] Donkey Kong..."
timeout 4s ./zig-out/bin/RAMBO "tests/data/Donkey Kong/Donkey Kong (World) (Rev 1).nes" 2>&1 | tee /tmp/dk.log
if grep -q "Frame" /tmp/dk.log; then
    echo "✅ Donkey Kong: Boots"
else
    echo "❌ Donkey Kong: Failed"
fi

echo ""
echo "=== Phase 1 Validation Complete ==="
echo "Visual Check: Run games manually and verify rendering enabled"
```

**Manual Validation Checklist:**
- [ ] Mario 1 displays title screen with graphics
- [ ] PPUMASK != $00 (rendering enabled)
- [ ] Game responds to input (START button)
- [ ] No crashes or hangs

**Estimated Time:** 30 minutes

---

## Phase 2: Pure Atomic FrameMailbox (3-4 hours)

### Design: Simple Lock-Free Ring Buffer

**Core Principles:**
1. **Pure atomics** - NO mutex, NO locks
2. **Preallocated buffers** - Zero allocations after init
3. **Ring buffer** - Fixed size, circular indexing
4. **Single writer, single reader** (SPSC queue)
5. **NTSC/PAL agnostic** - Handle both with same buffer size

### Architecture

```
Ring Buffer Layout:
┌─────────────────────────────────────────┐
│ Buffer 0: [61,440 pixels] RGBA u32     │ ← Write here
├─────────────────────────────────────────┤
│ Buffer 1: [61,440 pixels] RGBA u32     │ ← Read from here
├─────────────────────────────────────────┤
│ Buffer 2: [61,440 pixels] RGBA u32     │ ← Spare/overflow
└─────────────────────────────────────────┘

Atomic Indices:
- write_index: atomic u32 (which buffer PPU writes to)
- read_index: atomic u32 (which buffer Vulkan reads from)

State Machine:
- PPU completes frame → swapBuffers() → atomic increment write_index
- Vulkan polls → getReadBuffer() → returns buffer at read_index
- After Vulkan consumes → consumeFrame() → atomic increment read_index
```

### Task 2.1: Design Pure Atomic FrameMailbox (45 minutes)

**File:** `src/mailboxes/FrameMailbox.zig` (REFACTOR)

**New Implementation:**

```zig
//! FrameMailbox - Lock-free frame buffer exchange
//!
//! Design:
//! - Pure atomic operations (no mutex)
//! - Ring buffer with 3 preallocated buffers
//! - SPSC (Single Producer, Single Consumer)
//! - Zero allocations after initialization
//! - NTSC/PAL agnostic (same 256×240 resolution)
//!
//! Buffer Flow:
//! PPU (writer) → swapBuffers() → increment write_index
//! Vulkan (reader) → getReadBuffer() → read at read_index
//! Vulkan → consumeFrame() → increment read_index

const std = @import("std");

pub const FRAME_WIDTH = 256;
pub const FRAME_HEIGHT = 240;
pub const FRAME_PIXELS = FRAME_WIDTH * FRAME_HEIGHT; // 61,440
pub const RING_BUFFER_SIZE = 3; // 3 buffers for triple-buffering

pub const FrameMailbox = struct {
    /// Ring buffer of preallocated frame buffers
    buffers: [RING_BUFFER_SIZE][FRAME_PIXELS]u32,

    /// Atomic write index (PPU writes here)
    write_index: std.atomic.Value(u32),

    /// Atomic read index (Vulkan reads here)
    read_index: std.atomic.Value(u32),

    /// Frame counter (monotonic increment)
    frame_count: std.atomic.Value(u64),

    /// Frames dropped (when ring buffer full)
    frames_dropped: std.atomic.Value(u64),

    pub fn init() FrameMailbox {
        return .{
            .buffers = [_][FRAME_PIXELS]u32{[_]u32{0} ** FRAME_PIXELS} ** RING_BUFFER_SIZE,
            .write_index = std.atomic.Value(u32).init(0),
            .read_index = std.atomic.Value(u32).init(0),
            .frame_count = std.atomic.Value(u64).init(0),
            .frames_dropped = std.atomic.Value(u64).init(0),
        };
    }

    /// Get write buffer for PPU to render into
    /// Called by EmulationThread every frame
    pub fn getWriteBuffer(self: *FrameMailbox) []u32 {
        const index = self.write_index.load(.acquire);
        return &self.buffers[index % RING_BUFFER_SIZE];
    }

    /// Swap buffers after PPU completes frame
    /// Called by EmulationThread after emulateFrame()
    pub fn swapBuffers(self: *FrameMailbox) void {
        const current_write = self.write_index.load(.acquire);
        const current_read = self.read_index.load(.acquire);

        // Calculate next write position
        const next_write = (current_write + 1) % RING_BUFFER_SIZE;

        // Check if we're about to overwrite unconsumed frame
        // (This happens if read_index hasn't advanced)
        if (next_write == current_read % RING_BUFFER_SIZE) {
            // Ring buffer full - frame drop
            _ = self.frames_dropped.fetchAdd(1, .monotonic);
        }

        // Advance write index (release semantics for memory ordering)
        self.write_index.store(next_write, .release);

        // Increment frame counter
        _ = self.frame_count.fetchAdd(1, .monotonic);
    }

    /// Get read buffer for Vulkan to display
    /// Called by RenderThread
    pub fn getReadBuffer(self: *const FrameMailbox) []const u32 {
        const index = self.read_index.load(.acquire);
        return &self.buffers[index % RING_BUFFER_SIZE];
    }

    /// Check if new frame available
    /// Returns true if write_index ahead of read_index
    pub fn hasNewFrame(self: *const FrameMailbox) bool {
        const write_idx = self.write_index.load(.acquire);
        const read_idx = self.read_index.load(.acquire);

        // New frame available if indices differ
        return write_idx != read_idx;
    }

    /// Consume current frame and advance to next
    /// Called by RenderThread after uploading to Vulkan
    pub fn consumeFrame(self: *FrameMailbox) void {
        const current_read = self.read_index.load(.acquire);
        const next_read = (current_read + 1) % RING_BUFFER_SIZE;

        // Advance read index
        self.read_index.store(next_read, .release);
    }

    /// Get frame statistics
    pub fn getFrameCount(self: *const FrameMailbox) u64 {
        return self.frame_count.load(.monotonic);
    }

    pub fn getFramesDropped(self: *const FrameMailbox) u64 {
        return self.frames_dropped.load(.monotonic);
    }

    pub fn resetStatistics(self: *FrameMailbox) void {
        self.frames_dropped.store(0, .monotonic);
    }
};
```

**Key Design Points:**
- ✅ Pure atomics - no mutex anywhere
- ✅ Preallocated - all buffers initialized in `init()`
- ✅ Ring buffer - 3 buffers for triple-buffering
- ✅ NTSC/PAL same size (256×240 for both)
- ✅ Frame drop detection built-in
- ✅ Simple - ~80 lines, straightforward logic

### Task 2.2: Update EmulationThread Integration (30 minutes)

**File:** `src/threads/EmulationThread.zig`

**Changes Needed:**

```zig
// In timerCallback():

// Get write buffer for PPU frame output
const write_buffer = ctx.mailboxes.frame.getWriteBuffer();
ctx.state.framebuffer = write_buffer;

// Emulate one frame
const cycles = ctx.state.emulateFrame();

// Post completed frame (pure atomic swap)
ctx.mailboxes.frame.swapBuffers();

// Clear framebuffer reference (no longer valid after swap)
ctx.state.framebuffer = null;
```

**Validation:**
- No allocations in hot path
- Frame buffer ownership clear
- Atomic operations only

### Task 2.3: Update RenderThread Integration (30 minutes)

**File:** `src/threads/RenderThread.zig`

**Changes Needed:**

```zig
pub fn run(ctx: *Context) !void {
    while (ctx.running.load(.acquire)) {
        // Check for new frame (pure atomic read)
        if (ctx.mailboxes.frame.hasNewFrame()) {
            // Get read buffer (pure atomic)
            const framebuffer = ctx.mailboxes.frame.getReadBuffer();

            // Upload to Vulkan
            try ctx.vulkan.uploadTexture(framebuffer);

            // Render frame
            try ctx.vulkan.renderFrame();

            // Mark frame consumed (pure atomic)
            ctx.mailboxes.frame.consumeFrame();
        }

        // Small sleep to avoid busy-wait (TODO: use condition variable in future)
        std.Thread.sleep(1_000_000); // 1ms
    }
}
```

**Validation:**
- Clear buffer ownership
- No race conditions in texture upload
- Proper Vulkan ordering

### Task 2.4: NTSC/PAL Handling (15 minutes)

**Analysis:**
- NTSC: 262 scanlines × 341 dots
- PAL: 312 scanlines × 341 dots
- **But:** Visible area is SAME (256×240 for both)
- **Conclusion:** No buffer size changes needed!

**Documentation Update:**

```zig
// src/mailboxes/FrameMailbox.zig comment:

// Frame buffer dimensions:
// - NTSC: 262 scanlines, 341 dots per scanline
// - PAL: 312 scanlines, 341 dots per scanline
// - Visible area (both): 256 pixels × 240 scanlines
// - Buffer size: 61,440 pixels (RGBA u32)
//
// Timing differences handled by MasterClock, not buffer size.
```

**No code changes needed** - existing implementation handles both!

### Task 2.5: Add FrameMailbox Tests (60 minutes)

**File:** `tests/mailboxes/frame_mailbox_test.zig` (NEW)

```zig
const std = @import("std");
const testing = std.testing;
const FrameMailbox = @import("RAMBO").Mailboxes.FrameMailbox;

test "FrameMailbox: Initialization" {
    var mailbox = FrameMailbox.init();

    // Buffers should be zeroed
    try testing.expectEqual(@as(u64, 0), mailbox.getFrameCount());
    try testing.expectEqual(@as(u64, 0), mailbox.getFramesDropped());

    // No frames available initially
    try testing.expect(!mailbox.hasNewFrame());
}

test "FrameMailbox: Write and read buffer access" {
    var mailbox = FrameMailbox.init();

    // Get write buffer and write pattern
    const write_buf = mailbox.getWriteBuffer();
    write_buf[0] = 0xDEADBEEF;
    write_buf[100] = 0xCAFEBABE;

    // Swap buffers
    mailbox.swapBuffers();

    // Should have new frame
    try testing.expect(mailbox.hasNewFrame());

    // Read buffer should contain pattern
    const read_buf = mailbox.getReadBuffer();
    try testing.expectEqual(@as(u32, 0xDEADBEEF), read_buf[0]);
    try testing.expectEqual(@as(u32, 0xCAFEBABE), read_buf[100]);
}

test "FrameMailbox: Frame counter increments" {
    var mailbox = FrameMailbox.init();

    try testing.expectEqual(@as(u64, 0), mailbox.getFrameCount());

    mailbox.swapBuffers();
    try testing.expectEqual(@as(u64, 1), mailbox.getFrameCount());

    mailbox.swapBuffers();
    try testing.expectEqual(@as(u64, 2), mailbox.getFrameCount());
}

test "FrameMailbox: Frame drop detection" {
    var mailbox = FrameMailbox.init();

    // Fill ring buffer without consuming
    mailbox.swapBuffers(); // Frame 1
    mailbox.swapBuffers(); // Frame 2
    mailbox.swapBuffers(); // Frame 3 - should drop frame 1

    // Should have dropped 1 frame
    try testing.expectEqual(@as(u64, 1), mailbox.getFramesDropped());
}

test "FrameMailbox: Consumer advances read index" {
    var mailbox = FrameMailbox.init();

    // Write and swap
    mailbox.swapBuffers();
    try testing.expect(mailbox.hasNewFrame());

    // Consume
    mailbox.consumeFrame();
    try testing.expect(!mailbox.hasNewFrame());
}

test "FrameMailbox: Ring buffer wraps correctly" {
    var mailbox = FrameMailbox.init();

    // Write 10 frames with proper consumption
    for (0..10) |i| {
        const write_buf = mailbox.getWriteBuffer();
        write_buf[0] = @intCast(i);

        mailbox.swapBuffers();

        const read_buf = mailbox.getReadBuffer();
        try testing.expectEqual(@as(u32, @intCast(i)), read_buf[0]);

        mailbox.consumeFrame();
    }

    // No frames should be dropped
    try testing.expectEqual(@as(u64, 0), mailbox.getFramesDropped());
    try testing.expectEqual(@as(u64, 10), mailbox.getFrameCount());
}
```

**Validation:**
- All tests pass
- No allocations detected
- Atomic operations verified

---

## Validation Checklist

### Phase 1 Completion Criteria
- [ ] NMI atomic latch implemented
- [ ] 5/5 NMI timing tests passing
- [ ] All existing 896 tests still passing
- [ ] Mario 1 boots to title with rendering
- [ ] BurgerTime boots successfully
- [ ] Donkey Kong boots successfully
- [ ] No compiler warnings
- [ ] No new allocations in hot path

### Phase 2 Completion Criteria
- [ ] FrameMailbox refactored to pure atomics
- [ ] No mutex usage in FrameMailbox
- [ ] All buffers preallocated in init()
- [ ] Ring buffer logic working correctly
- [ ] 6/6 FrameMailbox tests passing
- [ ] Frame drop detection functional
- [ ] Vulkan texture upload working
- [ ] No frame corruption or tearing
- [ ] No new allocations per frame verified
- [ ] NTSC/PAL both work (same buffer size)

---

## Risk Mitigation

### Risk: Test Segfaults with libxev
**Cause:** Thread cleanup or timer issues
**Mitigation:**
- Review libxev thread spawning
- Ensure proper cleanup in defer blocks
- Add error recovery in timer callback

### Risk: Vulkan Ordering Issues
**Cause:** Buffer swap during texture upload
**Mitigation:**
- Clear ownership model: PPU → swap → Vulkan
- No concurrent access to same buffer
- Document buffer lifecycle

### Risk: Regressions in Existing Tests
**Cause:** Changes to frame pipeline
**Mitigation:**
- Run full test suite after every change
- Git commit per task for rollback
- Isolate changes to specific files

---

## Execution Timeline

### Hour 0-1: NMI Fix Implementation
- Modify Ppu.zig (atomic latch)
- Add test helper to Harness
- Implement 5 NMI tests

### Hour 1-2: NMI Validation
- Run full test suite (896 tests)
- Manual commercial ROM testing
- Document results

### Hour 2-3: FrameMailbox Design
- Implement pure atomic ring buffer
- Remove all mutex usage
- Validate zero allocations

### Hour 3-4: Thread Integration
- Update EmulationThread
- Update RenderThread
- Test buffer flow

### Hour 4-5: Testing & Validation
- Implement 6 FrameMailbox tests
- Run full test suite
- Validate frame drop detection

### Hour 5-6: Final Validation
- Commercial ROM testing
- Performance validation
- Documentation updates

---

## Success Metrics

### Phase 1 Success
- ✅ NMI race condition eliminated
- ✅ Games boot past title screen
- ✅ Zero test regressions

### Phase 2 Success
- ✅ Pure atomic implementation (no mutex)
- ✅ Zero allocations per frame
- ✅ Stable frame rendering
- ✅ Frame drop detection working

---

**Status:** Ready to execute
**Next Action:** Implement Task 1.1 (NMI atomic latch)
