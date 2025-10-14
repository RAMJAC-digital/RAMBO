# SMB Animation Freeze - Quick Diagnostic Tests
**Date:** 2025-10-14
**Purpose:** Fast tests to identify root cause of SMB animation freeze
**Time Required:** 1-2 hours total

---

## Background

**Problem:** SMB title screen displays correctly but animations frozen (coin, text)
**AccuracyCoin Status:** PASSING (sprite 0 hit tests working)
**Working ROMs:** Circus Charlie, Dig Dug animate correctly

**Key Finding:** AccuracyCoin tests sprite 0 hit thoroughly but doesn't test **frame-to-frame sprite animation workflows**.

---

## Quick Test 1: OAMDMA Execution (15 minutes)

**Hypothesis:** SMB calls OAMDMA every frame, but our emulator doesn't execute it.

**Test Code:** Add to `src/emulation/State.zig` in `busWrite()` around line handling $4014:

```zig
// In busWrite() case for $4014 (OAMDMA)
if (address == 0x4014) {
    std.debug.print("[Frame {}] OAMDMA: page=${X:02}\n", .{self.clock.frame(), value});
    // ... existing DMA code ...
}
```

**Expected Output:**
```
[Frame 180] OAMDMA: page=$02
[Frame 181] OAMDMA: page=$02
[Frame 182] OAMDMA: page=$02
... (continues every frame)
```

**If No Output After Frame 180:**
- SMB not calling OAMDMA → game logic bug, not emulator bug
- Check SMB's NMI handler with debugger

**If Output Appears:**
- OAMDMA is being called → problem is in DMA implementation or OAM handling

---

## Quick Test 2: OAMADDR Reset (15 minutes)

**Hypothesis:** OAMADDR ($2003) doesn't reset during sprite evaluation, causing OAMDMA to write to wrong offset.

**Hardware Behavior (NESDev Wiki):**
> "OAMADDR is set to 0 during each of ticks 257-320 of the pre-render and visible scanlines."

**Test Code:** Add to `src/ppu/Logic.zig` in main tick function:

```zig
pub fn tick(ppu: *PpuState, ...) void {
    const scanline = ppu.scanline;
    const cycle = ppu.cycle;

    // Check OAMADDR reset during sprite tile fetch
    if ((scanline < 240 or scanline == 261) and cycle == 257) {
        if (ppu.oam_addr != 0) {
            std.debug.print("[OAMADDR BUG] Scanline {}: OAMADDR=${X:02} (should be 0)\n",
                .{scanline, ppu.oam_addr});
        }
        // TEMPORARY FIX: Force reset for testing
        ppu.oam_addr = 0;
    }

    // ... rest of tick logic ...
}
```

**Expected Output:**
- No error messages → OAMADDR resets correctly
- Error messages → **BUG FOUND**, temporary fix applied

**If This Fixes Animation:**
- Make OAMADDR reset permanent in sprite evaluation logic
- Remove debug print
- Verify AccuracyCoin still passes

---

## Quick Test 3: Secondary OAM Clearing (20 minutes)

**Hypothesis:** Secondary OAM (internal 32-byte buffer) not cleared between frames, causing sprite evaluation to fail.

**Hardware Behavior:**
- Cycles 1-64 of each visible scanline: Clear secondary OAM to $FF
- If not cleared, sprite evaluation uses garbage data from previous frame

**Test Code:** Add to `src/ppu/Logic.zig`:

```zig
pub fn tick(ppu: *PpuState, ...) void {
    const scanline = ppu.scanline;
    const cycle = ppu.cycle;

    // Clear secondary OAM during cycles 1-64 (odd cycles write $FF)
    if ((scanline < 240 or scanline == 261) and cycle >= 1 and cycle <= 64) {
        if (cycle % 2 == 1) {
            const clear_index = (cycle - 1) / 2;
            ppu.secondary_oam[clear_index] = 0xFF;
        }
    }

    // Verify clearing at start of frame
    if (scanline == 0 and cycle == 1) {
        var all_ff = true;
        for (ppu.secondary_oam, 0..) |byte, i| {
            if (byte != 0xFF) {
                std.debug.print("[Secondary OAM BUG] Index {}: ${X:02} (expected $FF)\n", .{i, byte});
                all_ff = false;
            }
        }
        if (all_ff) {
            std.debug.print("[Frame {}] Secondary OAM: OK (all $FF)\n", .{/* frame */});
        }
    }

    // ... rest of tick logic ...
}
```

**Expected Output:**
- "Secondary OAM: OK" every frame → clearing works
- Error messages → **BUG FOUND**, fix implemented inline

**If This Fixes Animation:**
- Keep secondary OAM clear logic
- Remove debug prints
- Verify AccuracyCoin still passes

---

## Quick Test 4: OAM Contents Comparison (20 minutes)

**Hypothesis:** OAM not updating between frames despite OAMDMA being called.

**Test Code:** Add to `src/emulation/State.zig` or main loop:

```zig
// Somewhere accessible to main loop
var oam_snapshot: [256]u8 = undefined;
var snapshot_frame: u32 = 0;
var snapshot_taken = false;

// At end of VBlank (scanline 240)
if (self.clock.frame() >= 180 and scanline == 240 and cycle == 0) {
    if (self.clock.frame() == 180) {
        // First snapshot
        @memcpy(&oam_snapshot, &self.ppu.oam);
        snapshot_frame = 180;
        snapshot_taken = true;
        std.debug.print("[Frame 180] OAM snapshot taken\n", .{});
    } else if (snapshot_taken and self.clock.frame() == snapshot_frame + 1) {
        // Compare with previous frame
        var changed_count: u32 = 0;
        for (self.ppu.oam, 0..) |byte, i| {
            if (byte != oam_snapshot[i]) {
                changed_count += 1;
                if (changed_count <= 10) { // Print first 10 changes
                    std.debug.print("  OAM[{}]: ${X:02} -> ${X:02}\n",
                        .{i, oam_snapshot[i], byte});
                }
            }
        }
        std.debug.print("[Frame {}] OAM changes: {} bytes\n",
            .{self.clock.frame(), changed_count});

        // Update snapshot for next comparison
        @memcpy(&oam_snapshot, &self.ppu.oam);
        snapshot_frame = self.clock.frame();

        // Stop after 10 frames
        if (self.clock.frame() >= 190) {
            snapshot_taken = false;
        }
    }
}
```

**Expected Output:**
```
[Frame 180] OAM snapshot taken
[Frame 181] OAM changes: 0 bytes   ← FIRST FRAME: OK (no animation yet)
[Frame 182] OAM changes: 8 bytes   ← Animation starts
  OAM[0]: $50 -> $51  (Y position)
  OAM[3]: $64 -> $64  (X position unchanged)
  ...
[Frame 183] OAM changes: 8 bytes   ← Continues
```

**If No Changes After Frame 182:**
- **BUG CONFIRMED:** OAM not updating
- Either OAMDMA not transferring, or source RAM not updating

**If Changes Detected:**
- OAM IS updating, but rendering not reflecting changes
- Problem in PPU rendering logic, not OAM system

---

## Quick Test 5: Source RAM Inspection (15 minutes)

**Hypothesis:** SMB updates OAM source data in RAM, but OAMDMA reads from wrong page.

**Test Code:** Add before OAMDMA execution in `busWrite()`:

```zig
// In busWrite() case for $4014
if (address == 0x4014) {
    const page = value;
    const page_addr = @as(u16, page) << 8;

    std.debug.print("[Frame {}] OAMDMA source page: ${X:02}\n", .{self.clock.frame(), page});

    // Print first 16 bytes of source page
    std.debug.print("  Source data: ", .{});
    for (0..16) |i| {
        const source_byte = self.busRead(@intCast(page_addr + i));
        std.debug.print("${X:02} ", .{source_byte});
    }
    std.debug.print("\n", .{});

    // ... existing DMA transfer code ...
}
```

**Expected Output:**
```
[Frame 181] OAMDMA source page: $02
  Source data: $50 $FC $00 $64 $58 $FC $01 $6C ...  ← Valid sprite data
[Frame 182] OAMDMA source page: $02
  Source data: $51 $FC $00 $64 $59 $FC $01 $6C ...  ← Y positions incremented
```

**If Source Data All Zeros:**
- SMB not writing to page $02 → wrong page number, or game logic bug

**If Source Data Not Changing:**
- SMB's NMI handler not updating sprite positions
- Check NMI execution with debugger

**If Source Data Changes But OAM Doesn't:**
- **BUG IN OAMDMA TRANSFER** → DMA not copying correctly

---

## Decision Tree

```
Start
  │
  ├─ Test 1: Is OAMDMA being called every frame?
  │    ├─ NO  → SMB game logic issue, use debugger to trace NMI handler
  │    └─ YES → Continue to Test 2
  │
  ├─ Test 2: Does OAMADDR reset to 0 at cycle 257?
  │    ├─ NO  → **BUG FOUND**, add OAMADDR reset, verify fix
  │    └─ YES → Continue to Test 3
  │
  ├─ Test 3: Is secondary OAM cleared to $FF during cycles 1-64?
  │    ├─ NO  → **BUG FOUND**, add clearing logic, verify fix
  │    └─ YES → Continue to Test 4
  │
  ├─ Test 4: Does OAM content change between frames 181-182?
  │    ├─ NO  → Continue to Test 5
  │    └─ YES → Problem in rendering, not OAM (investigate PPU rendering path)
  │
  └─ Test 5: Does source RAM ($02xx) change between frames?
       ├─ NO  → SMB NMI handler not running, use debugger
       └─ YES → **BUG IN OAMDMA TRANSFER**, verify DMA logic
```

---

## Expected Results

### Most Likely Outcome (70% confidence)
**Test 2 FAILS:** OAMADDR not resetting → OAMDMA writes to wrong offset

**Fix:**
```zig
// In src/ppu/Logic.zig sprite tile fetch phase
if ((scanline < 240 or scanline == 261) and cycle >= 257 and cycle <= 320) {
    ppu.oam_addr = 0; // Hardware resets OAMADDR during sprite tile fetch
}
```

---

### Second Most Likely (20% confidence)
**Test 3 FAILS:** Secondary OAM not clearing → sprite evaluation fails

**Fix:**
```zig
// In src/ppu/Logic.zig cycles 1-64
if ((scanline < 240 or scanline == 261) and cycle >= 1 and cycle <= 64 and cycle % 2 == 1) {
    const clear_index = (cycle - 1) / 2;
    ppu.secondary_oam[clear_index] = 0xFF;
}
```

---

### Least Likely (10% confidence)
**All Tests Pass:** SMB game logic issue

**Action:** Use debugger to trace NMI handler:
```bash
./zig-out/bin/RAMBO "tests/data/Mario/Super Mario Bros. (World).nes" \
    --inspect --break-at 0x4014
```

Check:
- Is NMI handler incrementing frame counter?
- Are sprite position variables in zero-page RAM changing?
- Is there a stuck wait loop waiting for condition that never becomes true?

---

## Cleanup After Testing

Once root cause found and fixed:

1. Remove all `std.debug.print()` statements
2. Run full test suite: `zig build test`
3. Verify AccuracyCoin still passes
4. Test all commercial ROMs:
   - Super Mario Bros (should animate now)
   - Circus Charlie (should still work)
   - Dig Dug (should still work)
   - Donkey Kong, BurgerTime, Bomberman (verify no regressions)
5. Update `docs/CURRENT-ISSUES.md` with resolution
6. Commit fix with detailed message

---

## References

- Full Analysis: `docs/investigations/AccuracyCoin_Sprite_Coverage_Analysis.md`
- NESDev Wiki: [PPU Sprite Evaluation](https://www.nesdev.org/wiki/PPU_sprite_evaluation)
- NESDev Wiki: [PPU OAM](https://www.nesdev.org/wiki/PPU_OAM)
- Investigation Matrix: `docs/sessions/SMB_INVESTIGATION_MATRIX.md`

---

**Status:** Ready for immediate testing
**Estimated Time:** 1-2 hours to run all tests and identify root cause
**Confidence:** 90% that one of these tests will reveal the bug
