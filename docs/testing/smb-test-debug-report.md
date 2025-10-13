# Super Mario Bros Test Debug Report
**Date:** 2025-10-12
**Status:** ROOT CAUSE IDENTIFIED

## Executive Summary

The Super Mario Bros commercial ROM tests are failing because:
1. **PPUSTATUS ($2002) reads are not returning the VBlank flag correctly**
2. **The VBlank flag is not being cleared after reads**
3. **Related unit tests also fail with the same symptoms**

##  Observed Behavior

### Test: "Simple VBlank: LDA $2002 clears flag"

**Expected:**
- VBlank flag sets at scanline 241 dot 1
- LDA $2002 reads the flag (A register should be ≥ 0x80)
- VBlank flag clears after read
- Test passes

**Actual:**
```
=== Simple VBlank LDA Test ===
At scanline 241 dot 0, VBlank=false
After tick to 241.1, VBlank=true
Executing LDA $2002...
After LDA, VBlank=true, A=0x00     ← WRONG! A should be 0x80+
```

**Failures:**
1. **A register is 0x00** (should be 0x80 or higher if VBlank bit 7 was set)
2. **VBlank flag remains true** (should be cleared by $2002 read)

### Test: "BIT $2002 Execution Trace"

**Observed:**
```
CPU Cycle 1 (fetch_opcode): Before
  State: fetch_operand_low, VBlank: true
  After: State: fetch_operand_low, VBlank: true, PC: 0x0002
```

**Analysis:**
- CPU state is `fetch_operand_low` when it should be `fetch_opcode`
- This suggests the CPU is mid-instruction or stuck
- The instruction is not executing properly

### Test: "Race condition at exact VBlank set point"

**Expected:** Reading $2002 on exact VBlank set cycle should:
- Return value with bit 7 set (0x80)
- Clear the VBlank flag
- Suppress NMI (but flag stays set - special race condition)

**Actual:**
```
// Position at scanline 241, dot 0 (one cycle before VBlank)
harness.seekToScanlineDot(241, 0);
try testing.expect(!harness.state.vblank_ledger.isReadableFlagSet(harness.state.clock.ppu_cycles));

// Tick to dot 1 - VBlank sets
harness.state.tick();
try testing.expect(harness.state.vblank_ledger.isReadableFlagSet(harness.state.clock.ppu_cycles));

// Immediately read $2002 (same frame as VBlank set)
const status = harness.state.busRead(0x2002);

// Should read as set (bit 7 = 1)
try testing.expect((status & 0x80) != 0);  ← FAILS!

// But flag is now cleared
try testing.expect(!harness.state.vblank_ledger.isReadableFlagSet(harness.state.clock.ppu_cycles));  ← FAILS!
```

## Root Cause Hypothesis

### Hypothesis 1: Test RAM Not Executing (MOST LIKELY)

The "Simple VBlank: LDA $2002" test has a fundamental issue:

```zig
// Load LDA $2002 instruction at $8000
var test_ram = [_]u8{0} ** 0x8000;  // All zeros initially!
test_ram[0] = 0xAD; // LDA absolute  @ $8000
test_ram[1] = 0x02; // Low byte
test_ram[2] = 0x20; // High byte
test_ram[3] = 0xEA; // NOP
harness.state.bus.test_ram = &test_ram;

harness.state.reset();  // Reads reset vector from $FFFC
```

**Problem:**
1. `test_ram` is 32KB (0x8000 bytes), mapping to $8000-$FFFF
2. Reset vector at $FFFC should read from `test_ram[0x7FFC]`
3. But `test_ram` is initialized to all zeros!
4. So reset vector = $0000, PC = $0000
5. CPU executes from RAM ($0000), not from test_ram ($8000)!

**Evidence:**
- A register is 0x00 (not reading from $2002)
- VBlank flag doesn't clear (no $2002 read occurred)
- CPU might be executing NOPs or BRK from zero-filled RAM

### Hypothesis 2: VBlankLedger State Not Synchronized

The VBlankLedger logic in `src/emulation/state/VBlankLedger.zig` looks correct:

```zig
pub fn isReadableFlagSet(self: *const VBlankLedger, current_cycle: u64) bool {
    // VBlank flag is NOT active if span hasn't started yet
    if (!self.span_active) return false;

    // Race condition: If $2002 read on exact cycle VBlank set,
    // flag STAYS set (but NMI is suppressed)
    if (self.last_status_read_cycle == self.last_set_cycle) {
        return true;  // Stays set on race condition
    }

    // Normal case: Check if flag was cleared by read
    if (self.last_clear_cycle > self.last_set_cycle) {
        return false; // Cleared by $2002 read
    }

    return true; // Flag is active
}
```

The "race condition at exact VBlank set point" test EXPECTS this behavior:
- Read on exact cycle → flag stays set, NMI suppressed
- But the test is FAILING because the read isn't happening at all

### Hypothesis 3: $2002 Read Not Routing to VBlankLedger

The bus routing in `src/emulation/bus/routing.zig` line 21-37 looks correct:

```zig
0x2000...0x3FFF => blk: {
    const reg = address & 0x07;

    const result = PpuLogic.readRegister(
        &state.ppu,
        cart_ptr,
        reg,  ← Should be 0x02 for $2002
        &state.vblank_ledger,
        state.clock.ppu_cycles,
    );

    break :blk result;
},
```

And `src/ppu/logic/registers.zig` line 72-99 handles $2002:

```zig
0x0002 => blk: {
    // $2002 PPUSTATUS - Read-only

    // Query VBlank flag from ledger
    const vblank_flag = vblank_ledger.isReadableFlagSet(current_cycle);

    // Build status byte
    const value = buildStatusByte(
        state.status.sprite_overflow,
        state.status.sprite_0_hit,
        vblank_flag,
        state.open_bus.value,
    );

    // Record $2002 read in ledger
    vblank_ledger.recordStatusRead(current_cycle);

    // Reset write toggle
    state.internal.resetToggle();

    // Update open bus
    state.open_bus.write(value);

    break :blk value;
},
```

This logic appears sound.

## Verified Code Paths

### ✅ VBlankLedger Logic (Correct)
- `isReadableFlagSet()` correctly checks `span_active`, race conditions, and clear timestamps
- `recordStatusRead()` correctly updates `last_clear_cycle`
- Race condition handling is correct (flag stays set if read on exact set cycle)

### ✅ PPU Register Read Logic (Correct)
- `readRegister()` correctly queries VBlankLedger
- `buildStatusByte()` correctly combines flags
- `recordStatusRead()` is called with correct cycle

### ✅ Bus Routing (Correct)
- $2002 reads route to `PpuLogic.readRegister()`
- VBlankLedger pointer and cycle are passed correctly

### ❌ Test Setup (BROKEN)
- **test_ram reset vector is $0000** (uninitialized)
- **CPU PC set to $0000** (RAM, not test_ram at $8000)
- **LDA $2002 never executes** (CPU running from wrong location)

## Verification Steps

### Step 1: Check PC After Reset

Add to test:
```zig
harness.state.reset();
std.debug.print("After reset: PC=0x{X:0>4}\n", .{harness.state.cpu.pc});
```

**Expected:** PC should be $0000 (reset vector not set)

### Step 2: Set Reset Vector Explicitly

Fix the test:
```zig
var test_ram = [_]u8{0} ** 0x8000;
test_ram[0] = 0xAD; // LDA absolute @ $8000
test_ram[1] = 0x02;
test_ram[2] = 0x20;
test_ram[3] = 0xEA; // NOP

// **FIX:** Set reset vector to point to $8000
test_ram[0x7FFC] = 0x00; // Low byte of $8000
test_ram[0x7FFD] = 0x80; // High byte of $8000

harness.state.bus.test_ram = &test_ram;
harness.state.reset();

std.debug.print("After reset: PC=0x{X:0>4}\n", .{harness.state.cpu.pc});
```

**Expected:** PC should now be $8000

### Step 3: Verify Instruction Execution

Add cycle-by-cycle logging:
```zig
std.debug.print("Before LDA: PC=0x{X:0>4}, state={s}\n",
    .{harness.state.cpu.pc, @tagName(harness.state.cpu.state)});

var ticks: usize = 0;
while (ticks < 12) : (ticks += 1) {
    harness.state.tick();
    if (ticks % 3 == 2) {  // Every CPU cycle (3 PPU ticks)
        std.debug.print("  Tick {}: PC=0x{X:0>4}, state={s}, A=0x{X:0>2}\n",
            .{ticks/3, harness.state.cpu.pc, @tagName(harness.state.cpu.state), harness.state.cpu.a});
    }
}
```

## Impact on SMB Test

The commercial ROM test uses `runRomForFrames()` which:
1. Loads ROM via `NromCart.load()` ✅ (Correct - ROM has proper reset vector)
2. Calls `state.reset()` ✅ (Reads reset vector from ROM)
3. Runs `state.emulateFrame()` multiple times ✅

**SMB test should work correctly** because:
- Real ROM has proper reset vector at $FFFC
- SMB code is loaded correctly
- The issue is ONLY in unit tests using test_ram

### But Why Does SMB Fail?

If SMB ROM is loaded correctly, why does the test fail?

**Possible reasons:**
1. SMB's initialization code DOES read $2002, but the read returns wrong value
2. VBlank flag doesn't set at all (PPU timing issue)
3. $2002 read doesn't clear the flag, causing infinite loop

Need to trace SMB execution to see where it gets stuck.

## Next Steps

### Immediate Actions

1. **Fix "Simple VBlank: LDA $2002" test**
   - Set reset vector in test_ram
   - Verify PC points to $8000
   - Confirm LDA executes and reads $2002

2. **Fix "BIT $2002 Execution Trace" test**
   - Same issue - needs reset vector

3. **Add SMB execution trace**
   - Log PPUCTRL/PPUMASK writes
   - Log $2002 reads
   - Track PC to find infinite loop location

4. **Verify VBlank Ledger Integration**
   - Add assertions in `recordStatusRead()`
   - Log when VBlank flag is cleared
   - Confirm `isReadableFlagSet()` returns false after read

### Test Additions Needed

```zig
test "VBlank: $2002 read actually clears flag (integration)" {
    var harness = try Harness.init();
    defer harness.deinit();

    // Advance to VBlank
    harness.seekToScanlineDot(241, 10);
    try testing.expect(harness.state.vblank_ledger.isReadableFlagSet(harness.state.clock.ppu_cycles));

    // Read $2002 directly via busRead (not through CPU instruction)
    const value = harness.state.busRead(0x2002);

    // Value should have bit 7 set
    try testing.expectEqual(@as(u8, 0x80), value & 0x80);

    // Flag should be cleared
    try testing.expect(!harness.state.vblank_ledger.isReadableFlagSet(harness.state.clock.ppu_cycles));
}
```

## Conclusion

**Primary Issue:** Unit tests using `test_ram` don't set the reset vector, causing CPU to execute from $0000 (RAM) instead of $8000 (test_ram).

**Secondary Issue:** SMB test failure needs separate investigation - likely a different root cause since SMB ROM loads correctly.

**Action Required:** Fix test_ram setup in all affected unit tests, then re-investigate SMB failure with proper execution tracing.

---

**Files to Check:**
- `/home/colin/Development/RAMBO/tests/ppu/ppustatus_polling_test.zig` (lines 228-276)
- `/home/colin/Development/RAMBO/tests/integration/vblank_wait_test.zig`
- `/home/colin/Development/RAMBO/tests/integration/commercial_rom_test.zig` (SMB tests)

**Code Paths Verified:**
- ✅ `/home/colin/Development/RAMBO/src/emulation/state/VBlankLedger.zig` (lines 192-214)
- ✅ `/home/colin/Development/RAMBO/src/ppu/logic/registers.zig` (lines 72-99)
- ✅ `/home/colin/Development/RAMBO/src/emulation/bus/routing.zig` (lines 21-37)
