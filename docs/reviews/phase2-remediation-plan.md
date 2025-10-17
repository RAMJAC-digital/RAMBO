# Phase 2 Remediation Plan

**Date:** 2025-10-17
**Status:** Ready for Execution
**Estimated Total Effort:** 20-33 hours (P0-P1 tasks)

---

## Executive Summary

Phase 2 implementation is **EXCELLENT** and production-ready. This remediation plan addresses minor test coverage gaps and investigates remaining game compatibility issues (which are mapper-related, not Phase 2 bugs).

**No blocking issues found in Phase 2 implementation.**

---

## Priority 0: Critical (Before Next Development Phase)

### Task 1: Add PPUMASK Delay Tests

**Estimated Effort:** 4-6 hours
**Files to Create/Modify:**
- `tests/ppu/ppumask_delay_test.zig` (new file)

**Implementation:**

```zig
// tests/ppu/ppumask_delay_test.zig

const std = @import("std");
const testing = std.testing;
const PpuState = @import("../../src/ppu/State.zig").PpuState;
const PpuLogic = @import("../../src/ppu/Logic.zig");
const PpuMask = @import("../../src/ppu/registers.zig").PpuMask;

test "PPUMASK: Rendering enable propagation delay (3-4 dots)" {
    var ppu = PpuState{};
    ppu.mask = PpuMask{ .show_background = false, .show_sprites = false };

    // Scanline 0, dot 100: Enable rendering
    ppu.scanline = 0;
    ppu.dot = 100;
    ppu.mask = PpuMask{ .show_background = true, .show_sprites = true };

    // Immediately after write: Should still use OLD mask (disabled)
    try testing.expect(!ppu.getEffectiveMask().show_background);
    try testing.expect(!ppu.getEffectiveMask().show_sprites);

    // Advance 1 dot: Still old mask
    PpuLogic.tick(&ppu, null);
    try testing.expect(!ppu.getEffectiveMask().show_background);

    // Advance 2 dots: Still old mask
    PpuLogic.tick(&ppu, null);
    try testing.expect(!ppu.getEffectiveMask().show_background);

    // Advance 3 dots: Still old mask
    PpuLogic.tick(&ppu, null);
    try testing.expect(!ppu.getEffectiveMask().show_background);

    // Advance 4 dots: NOW new mask takes effect
    PpuLogic.tick(&ppu, null);
    try testing.expect(ppu.getEffectiveMask().show_background);
    try testing.expect(ppu.getEffectiveMask().show_sprites);
}

test "PPUMASK: Rendering disable propagation delay" {
    var ppu = PpuState{};
    ppu.mask = PpuMask{ .show_background = true, .show_sprites = true };

    // Enable rendering for 4 dots to fill delay buffer
    ppu.scanline = 0;
    ppu.dot = 100;
    PpuLogic.tick(&ppu, null);
    PpuLogic.tick(&ppu, null);
    PpuLogic.tick(&ppu, null);
    PpuLogic.tick(&ppu, null);

    // Disable rendering at dot 104
    ppu.mask = PpuMask{ .show_background = false, .show_sprites = false };

    // Effective mask should still show enabled (3-4 dot delay)
    try testing.expect(ppu.getEffectiveMask().show_background);

    // Advance 4 dots
    PpuLogic.tick(&ppu, null);
    PpuLogic.tick(&ppu, null);
    PpuLogic.tick(&ppu, null);
    PpuLogic.tick(&ppu, null);

    // Now should be disabled
    try testing.expect(!ppu.getEffectiveMask().show_background);
}

test "PPUMASK: Greyscale mode timing" {
    var ppu = PpuState{};
    ppu.mask = PpuMask{ .greyscale = false };

    // Fill delay buffer
    ppu.scanline = 0;
    ppu.dot = 100;
    PpuLogic.tick(&ppu, null);
    PpuLogic.tick(&ppu, null);
    PpuLogic.tick(&ppu, null);
    PpuLogic.tick(&ppu, null);

    // Enable greyscale
    ppu.mask = PpuMask{ .greyscale = true };

    // Should not take effect immediately
    try testing.expect(!ppu.getEffectiveMask().greyscale);

    // Advance 4 dots
    PpuLogic.tick(&ppu, null);
    PpuLogic.tick(&ppu, null);
    PpuLogic.tick(&ppu, null);
    PpuLogic.tick(&ppu, null);

    // Now should be enabled
    try testing.expect(ppu.getEffectiveMask().greyscale);
}

test "PPUMASK: Multiple rapid changes" {
    var ppu = PpuState{};

    // Fill delay buffer with disabled state
    ppu.mask = PpuMask{ .show_background = false };
    ppu.scanline = 0;
    ppu.dot = 100;
    PpuLogic.tick(&ppu, null);
    PpuLogic.tick(&ppu, null);
    PpuLogic.tick(&ppu, null);
    PpuLogic.tick(&ppu, null);

    // Rapid toggle: enable -> disable -> enable
    ppu.mask = PpuMask{ .show_background = true };
    PpuLogic.tick(&ppu, null);

    ppu.mask = PpuMask{ .show_background = false };
    PpuLogic.tick(&ppu, null);

    ppu.mask = PpuMask{ .show_background = true };
    PpuLogic.tick(&ppu, null);

    // Effective mask should be cycling through delayed states
    // This tests the circular buffer behavior
    try testing.expect(!ppu.getEffectiveMask().show_background); // Still original disabled

    PpuLogic.tick(&ppu, null);
    try testing.expect(ppu.getEffectiveMask().show_background); // First enable takes effect
}
```

**Registration in build.zig:**

```zig
// In build/tests.zig, add to ppu_tests array:
.{ "tests/ppu/ppumask_delay_test.zig", "PPUMASK", .ppu },
```

**Verification:**

```bash
zig build test 2>&1 | grep "PPUMASK"
# Should show 4/4 tests passing
```

**Success Criteria:**
- [ ] All 4 tests pass
- [ ] No regressions in existing tests
- [ ] Code coverage for PPUMASK delay behavior complete

---

### Task 2: Investigate MMC3 Mapper

**Estimated Effort:** 8-16 hours
**Priority:** P0 (blocking game compatibility)

**Phase 1: Verify MMC3 Existence (30 minutes)**

```bash
# Check if MMC3 mapper exists
ls src/cartridge/mappers/Mapper4.zig

# Check mapper registry
grep -n "Mapper4" src/cartridge/mappers/registry.zig
```

**Expected:** If file doesn't exist, MMC3 is not implemented (most likely)

**Phase 2: Review MMC3 Implementation (2-4 hours)**

If Mapper4.zig exists:

```bash
# Review implementation
cat src/cartridge/mappers/Mapper4.zig

# Check against nesdev specification
# Open: https://www.nesdev.org/wiki/MMC3
```

**Key areas to verify:**
- [ ] IRQ counter decrements at specific PPU cycles
- [ ] IRQ counter reload on A12 rise (scanline detection)
- [ ] CHR ROM bank switching (8 banks)
- [ ] PRG ROM bank switching
- [ ] Mirroring control

**Phase 3: Add Debug Logging (2-3 hours)**

If MMC3 exists but games fail:

```zig
// In Mapper4.zig, add debug logging

pub fn ppuRead(self: *Mapper4, address: u16) u8 {
    // Detect A12 rise (scanline detection for IRQ)
    const a12_high = (address & 0x1000) != 0;

    if (a12_high and !self.last_a12) {
        std.debug.print("MMC3 A12 rise detected at address ${X:0>4}\n", .{address});
        std.debug.print("  IRQ counter: {}\n", .{self.irq_counter});
        std.debug.print("  IRQ enabled: {}\n", .{self.irq_enable});

        // Decrement counter
        if (self.irq_counter == 0) {
            self.irq_counter = self.irq_reload;
        } else {
            self.irq_counter -= 1;
            if (self.irq_counter == 0 and self.irq_enable) {
                std.debug.print("  IRQ TRIGGERED!\n", .{});
                self.irq_pending = true;
            }
        }
    }

    self.last_a12 = a12_high;

    // ... rest of read logic
}
```

**Phase 4: Test with SMB3 (1-2 hours)**

```bash
# Run SMB3 with debug logging
./zig-out/bin/RAMBO roms/smb3.nes 2>&1 | tee /tmp/smb3_mmc3_debug.txt

# Look for IRQ patterns
grep "IRQ" /tmp/smb3_mmc3_debug.txt | head -50
```

**Expected findings:**
- IRQ should fire near scanline 0 (for status bar split)
- Counter should decrement each scanline
- If IRQ never fires → problem with A12 detection or counter logic
- If IRQ fires wrong time → counter reload value issue

**Phase 5: Create MMC3 Test Suite (4-6 hours)**

```zig
// tests/cartridge/mapper4_test.zig

test "MMC3: IRQ counter decrements on A12 rise" {
    // Create Mapper4 instance
    // Simulate PPU reads with A12 toggling
    // Verify counter decrements
}

test "MMC3: IRQ fires when counter reaches zero" {
    // Set IRQ enable
    // Count down to zero
    // Verify IRQ pending flag set
}

test "MMC3: CHR bank switching" {
    // Write to bank select registers
    // Verify correct CHR ROM banks selected
}
```

**Phase 6: Fix Issues Found (Variable - 2-8 hours)**

Common MMC3 bugs:
1. A12 rise detection incorrect (check PPU addresses carefully)
2. IRQ counter reload timing wrong
3. CHR bank calculations off by one
4. Mirroring not updated correctly

**Success Criteria:**
- [ ] MMC3 implementation verified or created
- [ ] IRQ counter behavior matches nesdev.org
- [ ] CHR bank switching correct
- [ ] SMB3 checkered floor displays correctly
- [ ] Kirby dialog box renders

**Fallback:**
If MMC3 issues are complex, defer to separate milestone and document as "known limitation."

---

### Task 3: Identify Paperboy Mapper

**Estimated Effort:** 30 minutes

**Implementation:**

```bash
# Extract mapper number from ROM header
xxd -l 16 roms/paperboy.nes

# Byte 6 (0-indexed) contains mapper low nibble
# Byte 7 contains mapper high nibble

# Example:
# 00000000: 4e45 531a 0810 1000 0000 0000 0000 0000  NES.............
#                     ^^-- Byte 6 (mapper low)
#                       ^^-- Byte 7 (mapper high)
# Mapper = (byte7 & 0xF0) | (byte6 >> 4)
```

**Create helper script:**

```zig
// tools/rom_info.zig

const std = @import("std");

pub fn main() !void {
    const args = try std.process.argsAlloc(std.heap.page_allocator);
    defer std.process.argsFree(std.heap.page_allocator, args);

    if (args.len < 2) {
        std.debug.print("Usage: rom_info <rom_file>\n", .{});
        return;
    }

    const file = try std.fs.cwd().openFile(args[1], .{});
    defer file.close();

    var header: [16]u8 = undefined;
    _ = try file.read(&header);

    const mapper_low = header[6] >> 4;
    const mapper_high = header[7] & 0xF0;
    const mapper = mapper_high | mapper_low;

    std.debug.print("ROM: {s}\n", .{args[1]});
    std.debug.print("Mapper: {}\n", .{mapper});
    std.debug.print("PRG ROM banks: {}\n", .{header[4]});
    std.debug.print("CHR ROM banks: {}\n", .{header[5]});
}
```

**Usage:**

```bash
zig run tools/rom_info.zig -- roms/paperboy.nes

# Check if mapper implemented
grep "Mapper<number>" src/cartridge/mappers/registry.zig
```

**Success Criteria:**
- [ ] Paperboy mapper identified
- [ ] Mapper implementation status known
- [ ] Added to compatibility tracking document

---

## Priority 1: High (Next 1-2 Weeks)

### Task 4: Add Attribute Synchronization Tests

**Estimated Effort:** 3-4 hours
**Files:** `tests/ppu/attribute_sync_test.zig` (new)

**Implementation:**

```zig
test "Attribute shift register: Fine X synchronization" {
    var ppu = PpuState{};

    // Set up attribute shift registers
    ppu.bg_state.attribute_shift_lo = 0b1010101010101010;
    ppu.bg_state.attribute_shift_hi = 0b1100110011001100;

    // Test at different fine X values
    for (0..8) |fine_x| {
        ppu.fine_x = @intCast(fine_x);

        const shift_amount: u4 = @intCast(15 - fine_x);
        const expected_bit0 = (ppu.bg_state.attribute_shift_lo >> shift_amount) & 1;
        const expected_bit1 = (ppu.bg_state.attribute_shift_hi >> shift_amount) & 1;

        // Get actual pixel (would call getBackgroundPixel)
        // Verify attribute bits match expected

        // This validates that attribute samples same position as pattern data
    }
}

test "Attribute shift register: Mid-scanline attribute change" {
    // Set up PPU mid-scanline
    // Change attribute table entry
    // Verify next tile prefetch uses new attribute
    // Verify shift register loads correctly
}
```

**Success Criteria:**
- [ ] 2-3 tests added and passing
- [ ] Validates Phase 2B fix behavior
- [ ] Documents expected hardware behavior

---

### Task 5: Add Sprite Prefetch Tests

**Estimated Effort:** 2-3 hours
**Files:** `tests/ppu/sprite_prefetch_test.zig` (new)

**Implementation:**

```zig
test "Sprite prefetch: Next scanline timing" {
    var ppu = PpuState{};

    // Set up sprite at Y=100
    ppu.oam[0] = 100; // Y position
    ppu.oam[1] = 0x00; // Tile index
    ppu.oam[2] = 0x00; // Attributes
    ppu.oam[3] = 50; // X position

    // At scanline 100, sprite should be evaluated for scanline 101
    ppu.scanline = 100;
    ppu.dot = 256;

    // Run sprite evaluation
    // Verify sprite appears at Y=101, not Y=100
}

test "Sprite prefetch: Pattern fetch timing" {
    // Verify pattern fetch occurs during scanline N for rendering at N+1
}
```

**Success Criteria:**
- [ ] 2 tests added and passing
- [ ] Validates Phase 2A behavior
- [ ] Covers sprite evaluation and pattern fetch

---

### Task 6: Consolidate Documentation

**Estimated Effort:** 2-3 hours

**Phase 1: Create Summary Documents**

```bash
# Create implementation summaries
cat > docs/implementation/phase2-summary.md << 'EOF'
# Phase 2 Summary

Quick reference for Phase 2 implementation (2025-10-15 to 2025-10-17).

## Phases

- **2A:** Shift register prefetch timing (commit 9abdcac)
- **2B:** Attribute synchronization (commit d2b6d3f) - FIXED SMB1
- **2C:** PPUCTRL immediate effect (commit 489e7c4)
- **2D:** PPUMASK 3-4 dot delay (commit 33d4f73)
- **2E:** DMA refactor (commits 57ecd81, 4165d17, b2e12e7)

## Results

- Test coverage: 990 → 1027 passing (+37 tests)
- Code reduction: -700 lines (DMA system)
- Performance: +5-10% improvement
- Game compatibility: SMB1 palette bug fixed

## See Also

- `phase2-ppu-fixes.md` - Detailed PPU implementation
- `phase2-dma-refactor.md` - DMA architecture details
EOF

# Create PPU fixes detail
cat > docs/implementation/phase2-ppu-fixes.md << 'EOF'
# Phase 2: PPU Rendering Fixes (2A-2D)

Detailed documentation of PPU timing fixes implemented in Phase 2.

[Content from session docs consolidated here]
EOF

# Create DMA refactor detail
cat > docs/implementation/phase2-dma-refactor.md << 'EOF'
# Phase 2E: DMA System Refactor

Complete documentation of DMA architectural transformation.

[Content from session docs consolidated here]
EOF
```

**Phase 2: Create ARCHITECTURE.md**

```bash
cat > ARCHITECTURE.md << 'EOF'
# RAMBO Architecture Guide

Quick reference for common patterns and idioms.

## VBlank Pattern (Timestamp-Based State)

**Used by:** VBlankLedger, DmaInteractionLedger, NMI edge detection

**Example:**
```zig
pub const VBlankLedger = struct {
    last_set_cycle: u64 = 0,
    last_clear_cycle: u64 = 0,

    pub fn reset(self: *VBlankLedger) void {
        self.* = .{};
    }
};

// Usage in execution.zig:
const vblank_active = (ledger.last_set_cycle > ledger.last_clear_cycle);
```

[More patterns...]
EOF
```

**Phase 3: Archive Session Docs**

```bash
# Move session docs to archive
mkdir -p docs/archive/sessions-phase2
mv docs/sessions/2025-10-16-phase2e-*.md docs/archive/sessions-phase2/
mv docs/sessions/2025-10-15-*.md docs/archive/sessions-phase2/

# Update README to point to new structure
```

**Success Criteria:**
- [ ] 3 summary docs created
- [ ] ARCHITECTURE.md added with patterns
- [ ] Session docs archived (not deleted)
- [ ] README updated with new structure

---

## Priority 2: Medium (Nice to Have)

### Task 7: Extract DMC Cycle Helper

**Estimated Effort:** 30 minutes
**Files:** `src/emulation/dma/logic.zig`

**Implementation:**

```zig
// Add helper function
fn dmcIsHaltingOam(dmc_dma: *const DmcDma) bool {
    return dmc_dma.rdy_low and
           (dmc_dma.stall_cycles_remaining == 4 or  // Halt cycle
            dmc_dma.stall_cycles_remaining == 1);   // Read cycle
}

// Replace inline check:
// const dmc_is_halting = state.dmc_dma.rdy_low and
//     (state.dmc_dma.stall_cycles_remaining == 4 or
//      state.dmc_dma.stall_cycles_remaining == 1);

const dmc_is_halting = dmcIsHaltingOam(&state.dmc_dma);
```

**Success Criteria:**
- [ ] Helper function added
- [ ] All uses updated
- [ ] No functional changes
- [ ] Tests still pass

---

### Task 8-10: See Full Remediation Plan

Tasks 8-10 (inline docs, DMA stress tests, benchmarks) are lower priority and detailed in the comprehensive review document.

---

## Execution Order

### Day 1 (8 hours)
1. Task 1: PPUMASK tests (4-6 hours)
2. Task 3: Identify Paperboy mapper (30 minutes)
3. Task 2 Phase 1-2: Verify MMC3 existence and review (2-3 hours)

### Day 2 (8 hours)
1. Task 2 Phase 3-4: MMC3 debug logging and testing (3-5 hours)
2. Task 4: Attribute sync tests (3-4 hours)

### Day 3 (8 hours)
1. Task 2 Phase 5-6: MMC3 test suite and fixes (6-8 hours)
2. Task 5: Sprite prefetch tests (2-3 hours)

### Day 4 (4 hours)
1. Task 6: Documentation consolidation (2-3 hours)
2. Task 7: Extract helper function (30 minutes)
3. Final verification and testing (1 hour)

**Total:** 28-33 hours over 4 days

---

## Verification Checklist

After completing P0-P1 tasks:

- [ ] All new tests passing
- [ ] Zero regressions in existing tests
- [ ] MMC3 games working OR documented as known limitation
- [ ] Paperboy mapper identified and tracked
- [ ] Documentation consolidated and accessible
- [ ] Test coverage gaps filled
- [ ] Ready to proceed to next development phase

---

## Contingency Plans

### If MMC3 Investigation Takes Longer Than Expected

**Fallback:**
- Document current findings
- Create MMC3 implementation ticket
- Move to separate milestone
- Continue with other tasks

### If New Tests Expose Edge Cases

**Response:**
- Document edge case
- Create fix if straightforward (<2 hours)
- Otherwise, create ticket and defer

### If Time-Constrained (User Deadline)

**Minimal Plan:**
- Task 1: PPUMASK tests (MUST DO)
- Task 3: Paperboy mapper (quick win)
- Task 2 Phase 1-2: MMC3 verification only
- Defer everything else

**Estimated minimal effort:** 5-7 hours

---

## Success Metrics

**Definition of Done:**
- [ ] P0 tasks complete (tests + MMC3 investigation started)
- [ ] Test suite at 100% or clear path to 100%
- [ ] All game compatibility issues understood and tracked
- [ ] Documentation accessible and consolidated
- [ ] Ready for next development phase

---

**Document Status:** Ready for Execution
**Next Review:** After P0 completion (estimated 1 week)
**Owner:** Development team
