# Nametable Mirroring Investigation Report

**Date:** 2025-10-17
**Investigation:** PPU nametable mirroring implementation audit
**Request:** User reported potential screen duplication/mirroring artifacts
**Status:** ✅ NO BUGS FOUND - Implementation is hardware-accurate

---

## Executive Summary

**Finding:** The PPU nametable mirroring implementation in RAMBO is **CORRECT** and **hardware-accurate**.

- Horizontal mirroring math is correct
- Vertical mirroring math is correct
- Cartridge mirroring mode is properly synchronized
- Dynamic mirroring changes are supported
- Existing tests validate the implementation

**Conclusion:** If visual artifacts exist, they are **NOT** caused by nametable mirroring bugs. Look elsewhere (scrolling registers, attribute table handling, CHR banking, etc.).

---

## Investigation Details

### 1. Nametable Mirroring Implementation

**Location:** `/home/colin/Development/RAMBO/src/ppu/logic/memory.zig:28-85`

#### Algorithm Analysis

The `mirrorNametableAddress()` function correctly implements hardware-accurate nametable mirroring:

```zig
fn mirrorNametableAddress(address: u16, mirroring: Mirroring) u16 {
    const addr = address & 0x0FFF;      // Mask to 4KB logical space
    const nametable = (addr >> 10) & 0x03;  // Extract NT index (0-3)

    // Horizontal mirroring
    if (mirroring_value == 0) {
        if (nametable < 2) {
            return addr & 0x03FF;  // NT0, NT1 -> VRAM $0000-$03FF
        } else {
            return 0x0400 | (addr & 0x03FF);  // NT2, NT3 -> VRAM $0400-$07FF
        }
    }

    // Vertical mirroring
    if (mirroring_value == 1) {
        if (nametable == 0 or nametable == 2) {
            return addr & 0x03FF;  // NT0, NT2 -> VRAM $0000-$03FF
        } else {
            return 0x0400 | (addr & 0x03FF);  // NT1, NT3 -> VRAM $0400-$07FF
        }
    }

    // Four-screen, single-screen modes also supported...
}
```

**Verification:** Tested with comprehensive test suite (24 test cases covering all edge cases):

```
HORIZONTAL MIRRORING: 12/12 tests passed ✓
VERTICAL MIRRORING:   12/12 tests passed ✓
```

### 2. Mirroring Mode Synchronization

**Cartridge → PPU Sync:** Mirroring mode is properly synchronized from cartridge to PPU state.

#### Initial Load

**Location:** `/home/colin/Development/RAMBO/src/emulation/State.zig:176`

```zig
pub fn loadCartridge(self: *EmulationState, cart: AnyCartridge) void {
    self.cart = cart;
    self.ppu.mirroring = cart.getMirroring();  // ✓ Synced on load
}
```

#### Dynamic Mirroring Changes

**Location:** `/home/colin/Development/RAMBO/src/emulation/State.zig:444`

```zig
pub fn write(self: *EmulationState, address: u16, value: u8) void {
    switch (address) {
        0x8000...0xFFFF => {
            if (self.cart) |*cart| {
                cart.cpuWrite(address, value);

                // Sync PPU mirroring after cartridge write
                // Handles mappers that can change mirroring dynamically
                // (e.g., Mapper 7/AxROM, Mapper 1/MMC1, Mapper 4/MMC3)
                self.ppu.mirroring = cart.getMirroring();  // ✓ Synced on mapper write
            }
        }
    }
}
```

**Supported Mappers:**
- Mapper 0 (NROM): Fixed mirroring from header
- Mapper 1 (MMC1): Dynamic mirroring via `getMirroring()`
- Mapper 4 (MMC3): Dynamic mirroring via `getMirroring()`
- Mapper 7 (AxROM): Single-screen mirroring via `getMirroring()`

### 3. VRAM Access Points

**Read Path:** `/home/colin/Development/RAMBO/src/ppu/logic/memory.zig:109-151`

```zig
pub fn readVram(state: *PpuState, cart: ?*AnyCartridge, address: u16) u8 {
    return switch (addr) {
        0x2000...0x2FFF => blk: {
            const mirrored_addr = mirrorNametableAddress(addr, state.mirroring);
            break :blk state.vram[mirrored_addr];  // ✓ Uses mirrored address
        },
        // ... other cases
    };
}
```

**Write Path:** `/home/colin/Development/RAMBO/src/ppu/logic/memory.zig:155-192`

```zig
pub fn writeVram(state: *PpuState, cart: ?*AnyCartridge, address: u16, value: u8) void {
    switch (addr) {
        0x2000...0x2FFF => {
            const mirrored_addr = mirrorNametableAddress(addr, state.mirroring);
            state.vram[mirrored_addr] = value;  // ✓ Uses mirrored address
        },
        // ... other cases
    }
}
```

**Both read and write paths use the same mirroring function - no asymmetry bugs.**

### 4. Existing Test Coverage

**Test:** `tests/ppu/chr_integration_test.zig:98-133`

```zig
test "PPU VRAM: Mirroring from cartridge header" {
    // Create ROM with VERTICAL mirroring
    rom_data[6] = 0x01; // Mapper 0, VERTICAL mirroring (bit 0 = 1)

    const cart = try Cartridge.loadFromData(allocator, &rom_data);

    // Verify vertical mirroring is set from cartridge header
    try testing.expectEqual(.vertical, cart.mirroring);

    var harness = try Harness.init();
    harness.loadNromCartridge(cart);

    // Test vertical mirroring behavior
    // NT0 ($2000) and NT2 ($2800) should map to same VRAM
    harness.ppuWriteVram(0x2000, 0xAA);
    try testing.expectEqual(0xAA, harness.ppuReadVram(0x2800)); // ✓ Pass

    // NT1 ($2400) and NT3 ($2C00) should map to same VRAM
    harness.ppuWriteVram(0x2400, 0xBB);
    try testing.expectEqual(0xBB, harness.ppuReadVram(0x2C00)); // ✓ Pass
}
```

**Status:** Test passes - validates vertical mirroring works correctly.

---

## Mirroring Behavior Reference

### Horizontal Mirroring (Top/Bottom)

Used by games with horizontal scrolling (e.g., Super Mario Bros.)

```
Nametable Layout (logical):
+-------+-------+
| NT0   | NT1   |  Top half (mirrored)
+-------+-------+
| NT2   | NT3   |  Bottom half (mirrored)
+-------+-------+

Physical VRAM Mapping:
NT0 ($2000-$23FF) → VRAM $0000-$03FF
NT1 ($2400-$27FF) → VRAM $0000-$03FF  (mirrors NT0)
NT2 ($2800-$2BFF) → VRAM $0400-$07FF
NT3 ($2C00-$2FFF) → VRAM $0400-$07FF  (mirrors NT2)
```

**Result:** Writing to NT0 is visible in NT1, writing to NT2 is visible in NT3.

### Vertical Mirroring (Left/Right)

Used by games with vertical scrolling (e.g., Ice Climber)

```
Nametable Layout (logical):
+-------+-------+
| NT0   | NT1   |
+-------+-------+
| NT2   | NT3   |
+-------+-------+
  Left     Right
  (mirror) (mirror)

Physical VRAM Mapping:
NT0 ($2000-$23FF) → VRAM $0000-$03FF
NT1 ($2400-$27FF) → VRAM $0400-$07FF
NT2 ($2800-$2BFF) → VRAM $0000-$03FF  (mirrors NT0)
NT3 ($2C00-$2FFF) → VRAM $0400-$07FF  (mirrors NT1)
```

**Result:** Writing to NT0 is visible in NT2, writing to NT1 is visible in NT3.

---

## Comprehensive Test Results

**Test Command:**
```bash
zig run /tmp/test_nt_mirroring_comprehensive.zig
```

**Results:**

### Horizontal Mirroring Tests (12/12 passed)
```
✓ NT0 start: $2000 -> $0000
✓ NT0 middle: $2123 -> $0123
✓ NT0 end: $23FF -> $03FF
✓ NT1 start (mirrors NT0): $2400 -> $0000
✓ NT1 middle (mirrors NT0): $2523 -> $0123
✓ NT1 end (mirrors NT0): $27FF -> $03FF
✓ NT2 start: $2800 -> $0400
✓ NT2 middle: $2923 -> $0523
✓ NT2 end: $2BFF -> $07FF
✓ NT3 start (mirrors NT2): $2C00 -> $0400
✓ NT3 middle (mirrors NT2): $2D23 -> $0523
✓ NT3 end (mirrors NT2): $2FFF -> $07FF
```

### Vertical Mirroring Tests (12/12 passed)
```
✓ NT0 start: $2000 -> $0000
✓ NT0 middle: $2123 -> $0123
✓ NT0 end: $23FF -> $03FF
✓ NT1 start: $2400 -> $0400
✓ NT1 middle: $2523 -> $0523
✓ NT1 end: $27FF -> $07FF
✓ NT2 start (mirrors NT0): $2800 -> $0000
✓ NT2 middle (mirrors NT0): $2923 -> $0123
✓ NT2 end (mirrors NT0): $2BFF -> $03FF
✓ NT3 start (mirrors NT1): $2C00 -> $0400
✓ NT3 middle (mirrors NT1): $2D23 -> $0523
✓ NT3 end (mirrors NT1): $2FFF -> $07FF
```

**Conclusion:** ALL TESTS PASSED ✅

---

## Potential Alternative Causes for Visual Artifacts

If screen duplication/mirroring artifacts are observed, investigate these areas instead:

### 1. Scrolling Register Issues
- **PPUSCROLL ($2005)** - Fine X/Y scroll position
- **PPUADDR ($2006)** - Coarse X/Y and nametable select bits
- **PPUCTRL bit 0-1** - Base nametable address
- **Mid-scanline scroll changes** - Split-screen effects

**Files to check:**
- `src/ppu/logic/scrolling.zig`
- `src/ppu/logic/registers.zig`

### 2. Attribute Table Handling
- Attribute bytes control palette selection for 4x4 tile blocks
- Wrong attribute fetching could cause color bleeding artifacts
- Check attribute address calculation

**Files to check:**
- `src/ppu/logic/background.zig:36` (attribute address calculation)

### 3. CHR Banking Issues
- Mappers can switch CHR banks mid-frame
- Wrong bank selection could show wrong tiles
- PPU A12 rising edge detection timing

**Files to check:**
- `src/cartridge/mappers/Mapper*.zig` (CHR bank switching)
- `src/emulation/State.zig:ppuA12RisingEdge()`

### 4. Sprite Rendering
- Sprite palette vs background palette confusion
- Sprite priority issues
- Sprite overflow flag handling

**Files to check:**
- `src/ppu/logic/sprites.zig`

### 5. Palette RAM
- Palette mirroring issues ($3F10/$3F14/$3F18/$3F1C)
- Greyscale mode
- Color emphasis bits

**Files to check:**
- `src/ppu/logic/memory.zig:95-105` (palette mirroring)
- `src/ppu/palette.zig`

---

## Recommendations

1. **Do NOT modify nametable mirroring code** - It is correct and well-tested
2. **Collect specific visual examples** - Screenshots showing the artifact
3. **Identify which games exhibit the issue** - Different games stress different features
4. **Check scrolling behavior first** - Most visual glitches are scroll-related
5. **Verify mapper-specific logic** - CHR banking and dynamic mirroring

---

## Code Locations

**Nametable Mirroring:**
- Implementation: `src/ppu/logic/memory.zig:28-85`
- Read path: `src/ppu/logic/memory.zig:109-151`
- Write path: `src/ppu/logic/memory.zig:155-192`

**Mirroring Synchronization:**
- Initial load: `src/emulation/State.zig:176`
- Dynamic updates: `src/emulation/State.zig:444`

**Mapper Mirroring:**
- Generic interface: `src/cartridge/Cartridge.zig:221-230`
- Mapper 0: Fixed from header
- Mapper 1: `src/cartridge/mappers/Mapper1.zig:321`
- Mapper 4: `src/cartridge/mappers/Mapper4.zig:183`
- Mapper 7: `src/cartridge/mappers/Mapper7.zig:160`

**Tests:**
- Integration test: `tests/ppu/chr_integration_test.zig:98-133`

---

## Appendix: Hardware Reference

**NES PPU Address Space ($0000-$3FFF):**
```
$0000-$0FFF: Pattern Table 0 (CHR ROM/RAM)
$1000-$1FFF: Pattern Table 1 (CHR ROM/RAM)
$2000-$23FF: Nametable 0
$2400-$27FF: Nametable 1
$2800-$2BFF: Nametable 2
$2C00-$2FFF: Nametable 3
$3000-$3EFF: Mirror of $2000-$2EFF
$3F00-$3F1F: Palette RAM
$3F20-$3FFF: Mirror of $3F00-$3F1F
```

**Physical VRAM:** Only 2KB ($0000-$07FF)
- Nametables 0-3 (4KB logical) must map to 2KB physical via mirroring

**Mirroring Modes:**
- Horizontal: Top/bottom pairs mirror
- Vertical: Left/right pairs mirror
- Four-screen: 4KB external VRAM on cartridge (no mirroring)
- Single-screen: All nametables map to same 1KB

**References:**
- https://www.nesdev.org/wiki/Mirroring
- https://www.nesdev.org/wiki/PPU_memory_map
- https://www.nesdev.org/wiki/PPU_nametables

---

**Investigation Complete:** No bugs found in nametable mirroring implementation.
