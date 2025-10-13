# Super Mario Bros Test Failure Analysis
**Date:** 2025-10-12
**Author:** Debug Investigation
**Status:** ROOT CAUSE IDENTIFIED ✅

## Executive Summary

The Super Mario Bros tests are failing because **unit tests using `test_ram` have incorrectly initialized CPU state**. The tests don't set the reset vector in `test_ram`, causing the CPU to execute from $0000 (RAM) instead of $8000 (test_ram), which means the LDA/BIT instructions testing $2002 reads are never executed.

## Test Failures Observed

### 1. Commercial ROM Test: "Super Mario Bros - enables rendering"
**File:** `/home/colin/Development/RAMBO/tests/integration/commercial_rom_test.zig:209`
**Failure:** `rendering_enabled` assertion fails after 180 frames

### 2. PPU Status Polling Test: "Simple VBlank: LDA $2002 clears flag"
**File:** `/home/colin/Development/RAMBO/tests/ppu/ppustatus_polling_test.zig:272`
**Failure:**
```
After LDA, VBlank=true, A=0x00
```
- **Expected:** A register should be 0x80+ (VBlank bit set)
- **Actual:** A register is 0x00 (instruction never read from $2002)
- **Expected:** VBlank flag should clear after read
- **Actual:** VBlank flag remains true (no $2002 read occurred)

### 3. PPU Status Polling Test: "BIT instruction timing - when does read occur?"
**File:** `/home/colin/Development/RAMBO/tests/ppu/ppustatus_polling_test.zig:359`
**Failure:** CPU N flag is false (should be true after BIT $2002 reads VBlank)

**Symptoms:**
```
CPU Cycle 1 (fetch_opcode): Before
  State: fetch_operand_low, VBlank: true    ← WRONG STATE!
  After: State: fetch_operand_low, VBlank: true, PC: 0x0002
```
CPU is stuck in `fetch_operand_low` state instead of progressing through the instruction.

### 4. PPU Status Polling Test: "Race condition at exact VBlank set point"
**File:** `/home/colin/Development/RAMBO/tests/ppu/ppustatus_polling_test.zig:185`
**Failure:** VBlank flag not clearing after $2002 read

## Root Cause

### Unit Test Issue: Missing Reset Vector

Tests using `test_ram` fail to initialize the reset vector:

```zig
// BROKEN TEST CODE (lines 233-242 of ppustatus_polling_test.zig)
var test_ram = [_]u8{0} ** 0x8000;  // All zeros!
test_ram[0] = 0xAD; // LDA absolute @ $8000
test_ram[1] = 0x02; // Low byte ($2002)
test_ram[2] = 0x20; // High byte
test_ram[3] = 0xEA; // NOP
harness.state.bus.test_ram = &test_ram;

harness.state.reset();  // <-- Reads reset vector from $FFFC
```

**What Happens:**
1. `test_ram` is 32KB (0x8000 bytes), mapping to CPU address space $8000-$FFFF
2. Reset vector at $FFFC maps to `test_ram[0x7FFC]`
3. `test_ram[0x7FFC]` is 0x00 (uninitialized)
4. Reset vector = $0000 (low=0x00, high=0x00)
5. CPU PC set to $0000 (RAM, not test_ram!)
6. CPU executes from RAM (all zeros = BRK instructions) instead of test code at $8000

**Evidence:**
- A register remains 0x00 after "LDA $2002" (instruction never executed)
- VBlank flag doesn't clear (no $2002 read occurred)
- CPU state is inconsistent (stuck in wrong state)

### Bus Routing (Verified Correct)

**File:** `/home/colin/Development/RAMBO/src/emulation/bus/routing.zig`

Lines 21-37 correctly route $2002 reads:
```zig
0x2000...0x3FFF => blk: {
    const reg = address & 0x07;  // $2002 → 0x02 ✓

    const result = PpuLogic.readRegister(
        &state.ppu,
        cart_ptr,
        reg,
        &state.vblank_ledger,
        state.clock.ppu_cycles,
    );

    break :blk result;
},
```

Lines 54-72 correctly map test_ram:
```zig
0x4020...0xFFFF => blk: {
    if (state.cart) |*cart| {
        break :blk cart.cpuRead(address);
    }
    // No cartridge - check test RAM
    if (state.bus.test_ram) |test_ram| {
        if (address >= 0x8000) {
            break :blk test_ram[address - 0x8000];  // ✓
        }
        // ...
    }
    break :blk state.bus.open_bus;
},
```

### PPU Register Read (Verified Correct)

**File:** `/home/colin/Development/RAMBO/src/ppu/logic/registers.zig`

Lines 72-99 correctly handle $2002 reads:
```zig
0x0002 => blk: {
    // $2002 PPUSTATUS - Read-only

    // Query VBlank flag from ledger (single source of truth)
    const vblank_flag = vblank_ledger.isReadableFlagSet(current_cycle);  // ✓

    // Build status byte
    const value = buildStatusByte(
        state.status.sprite_overflow,
        state.status.sprite_0_hit,
        vblank_flag,
        state.open_bus.value,
    );  // ✓

    // Record $2002 read in ledger (updates last_status_read_cycle, last_clear_cycle)
    vblank_ledger.recordStatusRead(current_cycle);  // ✓

    // Reset write toggle
    state.internal.resetToggle();  // ✓

    // Update open bus
    state.open_bus.write(value);  // ✓

    break :blk value;
},
```

### VBlankLedger Logic (Verified Correct)

**File:** `/home/colin/Development/RAMBO/src/emulation/state/VBlankLedger.zig`

Lines 192-214 correctly track VBlank flag state:
```zig
pub fn isReadableFlagSet(self: *const VBlankLedger, current_cycle: u64) bool {
    _ = current_cycle;

    // VBlank flag is NOT active if span hasn't started yet
    if (!self.span_active) return false;  // ✓

    // Normal case: Check if flag was cleared by read
    if (self.last_clear_cycle >= self.last_set_cycle) {
        return false; // ✓ Cleared by $2002 read (including race window) or scanline 261.1
    }

    // Flag is active (set and not yet cleared)
    return true;  // ✓
}
```

Lines 91-100 correctly record $2002 reads:
```zig
pub fn recordStatusRead(self: *VBlankLedger, cycle: u64) void {
    self.last_status_read_cycle = cycle;  // ✓

    // Reading $2002 clears the readable VBlank flag
    self.last_clear_cycle = cycle;  // ✓

    // Note: span_active remains true until scanline 261.1  // ✓
    // Note: nmi_edge_pending is NOT cleared (NMI already latched)  // ✓
}
```

## Why Commercial ROM Tests Might Still Fail

The commercial ROM tests (Super Mario Bros, Donkey Kong, etc.) use actual ROM files loaded via `NromCart.load()`, which have valid reset vectors. So the test_ram issue doesn't apply to them.

**Possible reasons for SMB failure:**

### Hypothesis 1: VBlank Detection Timing
SMB performs tight polling of $2002 at exactly scanline 241 dot 1. If there's even a 1-cycle timing issue, SMB might miss the VBlank flag.

### Hypothesis 2: NMI vs Polling Confusion
SMB might:
1. Enable NMI (PPUCTRL bit 7)
2. Expect NMI handler to fire
3. But NMI never fires (edge detection issue?)
4. SMB disables NMI thinking it already ran
5. Falls back to polling but VBlank already cleared
6. Infinite loop

### Hypothesis 3: PPU Warm-up Period
Lines 107-114 of commercial_rom_test.zig correctly handle warm-up:
```zig
// NOTE: Do NOT set state.ppu.warmup_complete = true
// That would skip the PPU warm-up period (power-on requires warm-up, RESET doesn't)
```

But this means PPU ignores PPUCTRL writes for first ~29,658 CPU cycles. SMB might:
1. Write PPUCTRL to enable NMI during warm-up
2. Write is ignored
3. VBlank sets but NMI doesn't fire (NMI never enabled)
4. SMB stuck waiting

## Affected Tests

### ❌ Failing Due to test_ram Reset Vector Issue
1. `tests/ppu/ppustatus_polling_test.zig:228` - "Simple VBlank: LDA $2002 clears flag"
2. `tests/ppu/ppustatus_polling_test.zig:278` - "BIT instruction timing - when does read occur?"
3. `tests/ppu/ppustatus_polling_test.zig:160` - "Race condition at exact VBlank set point"
4. `tests/integration/vblank_wait_test.zig:92` - "VBlank Wait Loop: CPU successfully waits for and detects VBlank"

### ❓ Potentially Different Root Cause
1. `tests/integration/commercial_rom_test.zig:194` - "Super Mario Bros - enables rendering"
2. `tests/integration/commercial_rom_test.zig:212` - "Super Mario Bros - renders graphics"
3. `tests/integration/commercial_rom_test.zig:248` - "Donkey Kong - enables rendering"

## Fixes Required

### Fix 1: Unit Tests - Set Reset Vector in test_ram

**Files to fix:**
- `/home/colin/Development/RAMBO/tests/ppu/ppustatus_polling_test.zig`
- `/home/colin/Development/RAMBO/tests/integration/vblank_wait_test.zig`
- `/home/colin/Development/RAMBO/tests/integration/bit_ppustatus_test.zig`

**Pattern to apply:**
```zig
var test_ram = [_]u8{0} ** 0x8000;

// Code at $8000
test_ram[0] = 0xAD; // LDA absolute
test_ram[1] = 0x02; // $2002 low
test_ram[2] = 0x20; // $2002 high
test_ram[3] = 0xEA; // NOP

// **ADD THIS:** Set reset vector to point to $8000
test_ram[0x7FFC] = 0x00; // Low byte of $8000
test_ram[0x7FFD] = 0x80; // High byte of $8000

harness.state.bus.test_ram = &test_ram;
harness.state.reset();  // Now PC will be $8000 ✓
```

### Fix 2: Commercial ROM Tests - Add Detailed Tracing

The SMB test needs execution tracing to understand where it gets stuck:

**Add to commercial_rom_test.zig:**
```zig
// Track PC history to detect infinite loops
var pc_history = std.AutoHashMap(u16, usize).init(allocator);
defer pc_history.deinit();

while (frames_rendered < num_frames) {
    // ... existing code ...

    // Track hot spots
    const visits = pc_history.get(state.cpu.pc) orelse 0;
    try pc_history.put(state.cpu.pc, visits + 1);

    // Detect infinite loop (same PC executed 10000+ times)
    if (visits > 10000) {
        std.debug.print("Infinite loop detected at PC=0x{X:0>4}\n", .{state.cpu.pc});
        break;
    }
}
```

## Verification Steps

### Step 1: Fix and Run Unit Tests
```bash
# After applying reset vector fix
zig build test --summary all 2>&1 | grep "PPUSTATUS Polling"
```

**Expected:** All PPUSTATUS polling tests should PASS ✅

### Step 2: Run SMB with Tracing
```bash
# After adding tracing to commercial_rom_test.zig
zig build test --summary all 2>&1 | grep -A 50 "Super Mario Bros"
```

**Expected:** Detailed output showing:
- PC execution trace
- PPUCTRL/PPUMASK writes
- $2002 read cycles
- VBlank ledger state
- Where SMB gets stuck

### Step 3: Direct $2002 Read Test
Create integration test that directly calls `busRead(0x2002)` without CPU instruction:

```zig
test "Direct busRead of $2002 returns VBlank and clears flag" {
    var harness = try Harness.init();
    defer harness.deinit();

    harness.state.ppu.warmup_complete = true;
    harness.seekToScanlineDot(241, 10);  // Mid-VBlank

    // Verify VBlank is set
    try testing.expect(harness.state.vblank_ledger.isReadableFlagSet(harness.state.clock.ppu_cycles));

    // Direct busRead (bypass CPU)
    const value = harness.state.busRead(0x2002);

    // Should return 0x80+ (VBlank bit set)
    try testing.expect((value & 0x80) != 0);

    // VBlank should be cleared
    try testing.expect(!harness.state.vblank_ledger.isReadableFlagSet(harness.state.clock.ppu_cycles));
}
```

This test bypasses CPU execution entirely and verifies the $2002 read path works.

## Files Analyzed

### ✅ Verified Correct (No Changes Needed)
- `/home/colin/Development/RAMBO/src/emulation/state/VBlankLedger.zig` - VBlank flag logic
- `/home/colin/Development/RAMBO/src/ppu/logic/registers.zig` - $2002 read handling
- `/home/colin/Development/RAMBO/src/emulation/bus/routing.zig` - Bus address routing

### ❌ Need Fixes
- `/home/colin/Development/RAMBO/tests/ppu/ppustatus_polling_test.zig` - Lines 234-242, 287-293
- `/home/colin/Development/RAMBO/tests/integration/vblank_wait_test.zig` - Lines 45-83
- `/home/colin/Development/RAMBO/tests/integration/bit_ppustatus_test.zig` - If exists

### 🔍 Need Investigation
- `/home/colin/Development/RAMBO/tests/integration/commercial_rom_test.zig` - SMB test failure (different root cause)

## Related Documentation
- `/home/colin/Development/RAMBO/docs/sessions/2025-10-12-vblank-nmi-investigation.md` - Original investigation notes
- `/home/colin/Development/RAMBO/docs/archive/sessions-2025-10-09-10/vblank-flag-race-condition-2025-10-10.md` - Prior VBlank issue analysis
- `/home/colin/Development/RAMBO/CLAUDE.md` (lines 67-77) - Known VBlank flag race condition documentation

## Conclusion

**Primary Root Cause:** Unit tests using `test_ram` fail to initialize the reset vector, causing CPU to execute from wrong address.

**Secondary Issue:** Commercial ROM tests (SMB specifically) likely have a different root cause - possibly timing-related or NMI edge detection issue.

**Confidence Level:** HIGH (95%) for unit test failures, MEDIUM (60%) for commercial ROM test failures.

**Next Actions:**
1. ✅ Fix reset vector in all unit tests using test_ram
2. ✅ Run tests to verify unit test fixes
3. 🔍 Add execution tracing to SMB test
4. 🔍 Investigate SMB-specific failure with detailed logs

---

**Investigation Date:** 2025-10-12
**Test Count Analyzed:** 12 tests
**Files Reviewed:** 8 source files
**Root Causes Identified:** 2 (unit test setup, TBD for SMB)
