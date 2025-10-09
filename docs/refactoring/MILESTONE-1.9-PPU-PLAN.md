# Milestone 1.9 - PPU Logic Decomposition Plan

**Date:** 2025-10-09
**Target File:** src/ppu/Logic.zig (779 lines)
**Estimated Time:** 3-4 hours
**Risk:** 🟢 LOW

---

## Current Structure Analysis

### File Breakdown by Line Numbers

| Section | Lines | Functions | Visibility |
|---------|-------|-----------|------------|
| **Header + Init** | 1-34 | init(), reset() | Public |
| **Memory Mirroring** | 36-102 | 2 helpers | Private |
| **VRAM Access** | 104-189 | readVram(), writeVram() | Public |
| **Register I/O** | 190-361 | readRegister(), writeRegister() | Public |
| **Scrolling** | 363-426 | 4 functions | Public |
| **Background** | 428-544 | 6 functions (2 private) | Mixed |
| **Sprites** | 546-779 | 7 functions | Public |
| **Total** | **779** | **22 functions** | **20 public** |

### Dependencies Map

```
registers.zig
    ↓ calls
memory.zig (readVram, writeVram)

background.zig
    ↓ calls
memory.zig (readVram)

sprites.zig
    ↓ calls
memory.zig (readVram)

scrolling.zig
    → No dependencies (pure register bit manipulation)
```

---

## Target Module Structure

```
src/ppu/
├── Logic.zig (60-80 lines) - Facade with re-exports and delegation
├── logic/
│   ├── memory.zig (~180 lines) - VRAM access + mirroring
│   ├── scrolling.zig (~70 lines) - Scroll register operations
│   ├── background.zig (~125 lines) - Background tile fetching/rendering
│   ├── sprites.zig (~245 lines) - Sprite evaluation/rendering
│   └── registers.zig (~180 lines) - Register I/O ($2000-$2007)
```

**Total extracted:** ~800 lines (includes added module headers)
**Facade:** ~70 lines
**Net change:** +90 lines (+11% overhead for modularity)

---

## Extraction Order (Dependency-First)

### Phase 1: memory.zig (NO dependencies)
**Lines:** 36-189 (154 lines)
**Functions:**
- `mirrorNametableAddress()` (private → pub)
- `mirrorPaletteAddress()` (private → pub)
- `readVram()` (public)
- `writeVram()` (public)

**Module signature:**
```zig
const PpuState = @import("../State.zig").PpuState;
const AnyCartridge = @import("../../cartridge/mappers/registry.zig").AnyCartridge;
const Mirroring = @import("../../cartridge/ines.zig").Mirroring;

pub fn mirrorNametableAddress(address: u16, mirroring: Mirroring) u16
pub fn mirrorPaletteAddress(address: u8) u8
pub fn readVram(state: *PpuState, cart: ?*AnyCartridge, address: u16) u8
pub fn writeVram(state: *PpuState, cart: ?*AnyCartridge, address: u16, value: u8) void
```

### Phase 2: scrolling.zig (NO dependencies)
**Lines:** 363-426 (64 lines)
**Functions:**
- `incrementScrollX()` (public)
- `incrementScrollY()` (public)
- `copyScrollX()` (public)
- `copyScrollY()` (public)

**Module signature:**
```zig
const PpuState = @import("../State.zig").PpuState;

pub fn incrementScrollX(state: *PpuState) void
pub fn incrementScrollY(state: *PpuState) void
pub fn copyScrollX(state: *PpuState) void
pub fn copyScrollY(state: *PpuState) void
```

### Phase 3: background.zig (depends on memory)
**Lines:** 428-544 (117 lines)
**Functions:**
- `getPatternAddress()` (private → keep internal)
- `getAttributeAddress()` (private → keep internal)
- `fetchBackgroundTile()` (public)
- `getBackgroundPixel()` (public)
- `getPaletteColor()` (public)

**Module signature:**
```zig
const PpuState = @import("../State.zig").PpuState;
const AnyCartridge = @import("../../cartridge/mappers/registry.zig").AnyCartridge;
const memory = @import("memory.zig");
const palette = @import("../palette.zig");

fn getPatternAddress(state: *PpuState, high_bitplane: bool) u16
fn getAttributeAddress(state: *PpuState) u16
pub fn fetchBackgroundTile(state: *PpuState, cart: ?*AnyCartridge, dot: u16) void
pub fn getBackgroundPixel(state: *PpuState) u8
pub fn getPaletteColor(state: *PpuState, palette_index: u8) u32
```

**Note:** Calls `memory.readVram()`, references `scrolling.incrementScrollX()` at line 504

### Phase 4: sprites.zig (depends on memory)
**Lines:** 546-779 (234 lines)
**Functions:**
- `getSpritePatternAddress()` (public)
- `getSprite16PatternAddress()` (public)
- `fetchSprites()` (public)
- `reverseBits()` (public)
- `getSpritePixel()` (public)
- `evaluateSprites()` (public)

**Module signature:**
```zig
const PpuState = @import("../State.zig").PpuState;
const AnyCartridge = @import("../../cartridge/mappers/registry.zig").AnyCartridge;
const memory = @import("memory.zig");

pub fn getSpritePatternAddress(tile_index: u8, row: u8, bitplane: u1, pattern_table: bool, vertical_flip: bool) u16
pub fn getSprite16PatternAddress(tile_index: u8, row: u8, bitplane: u1, vertical_flip: bool) u16
pub fn fetchSprites(state: *PpuState, cart: ?*AnyCartridge, scanline: u16, dot: u16) void
pub fn reverseBits(byte: u8) u8
pub fn getSpritePixel(state: *PpuState, pixel_x: u16) struct { pixel: u8, priority: bool, sprite_0: bool }
pub fn evaluateSprites(state: *PpuState, scanline: u16) void
```

**Note:** Calls `memory.readVram()` multiple times

### Phase 5: registers.zig (depends on memory)
**Lines:** 190-361 (172 lines)
**Functions:**
- `readRegister()` (public)
- `writeRegister()` (public)

**Module signature:**
```zig
const PpuState = @import("../State.zig").PpuState;
const AnyCartridge = @import("../../cartridge/mappers/registry.zig").AnyCartridge;
const memory = @import("memory.zig");
const PpuCtrl = @import("../State.zig").PpuCtrl;
const PpuMask = @import("../State.zig").PpuMask;

pub fn readRegister(state: *PpuState, cart: ?*AnyCartridge, address: u16) u8
pub fn writeRegister(state: *PpuState, cart: ?*AnyCartridge, address: u16, value: u8) void
```

**Note:** Calls `memory.readVram()` and `memory.writeVram()`

### Phase 6: Refactor Logic.zig to facade
**Target:** 60-80 lines
**Content:**
- Header comment
- Import all logic modules
- Re-export common types (if needed)
- init(), reset(), tickFrame() implementations
- Inline delegation wrappers for all 20 public functions

**Facade structure:**
```zig
//! PPU Logic - Facade module delegating to specialized logic modules

const std = @import("std");
const StateModule = @import("State.zig");
const PpuState = StateModule.PpuState;
const AnyCartridge = @import("../cartridge/mappers/registry.zig").AnyCartridge;

// Logic modules
const memory = @import("logic/memory.zig");
const registers = @import("logic/registers.zig");
const scrolling = @import("logic/scrolling.zig");
const background = @import("logic/background.zig");
const sprites = @import("logic/sprites.zig");

/// Initialize PPU state to power-on values
pub fn init() PpuState {
    return PpuState.init();
}

/// Reset PPU
pub fn reset(state: *PpuState) void {
    // ... implementation (stays in facade)
}

/// Memory access (inline delegation)
pub inline fn readVram(state: *PpuState, cart: ?*AnyCartridge, address: u16) u8 {
    return memory.readVram(state, cart, address);
}

pub inline fn writeVram(state: *PpuState, cart: ?*AnyCartridge, address: u16, value: u8) void {
    memory.writeVram(state, cart, address, value);
}

// ... (all other inline delegations)
```

---

## Special Considerations

### 1. Cross-Module Function Calls

**background.fetchBackgroundTile() → scrolling.incrementScrollX()**
- Line 504: `incrementScrollX(state);`
- Solution: Import scrolling module, call `scrolling.incrementScrollX(state)`

**All modules → memory.readVram/writeVram**
- Multiple callsites throughout
- Solution: Import memory module at top of each dependent module

### 2. Private Helper Functions

**mirrorNametableAddress** and **mirrorPaletteAddress**
- Currently private (fn, not pub fn)
- Only used within memory module
- Decision: Keep internal to memory.zig (no pub needed)

**getPatternAddress** and **getAttributeAddress**
- Currently private
- Only used within background module
- Decision: Keep internal to background.zig (no pub needed)

### 3. Open Bus Access

Multiple functions access `state.open_bus`:
- registers.readRegister() - reads and writes
- registers.writeRegister() - writes
- memory.readVram() - reads (CHR unmapped case)

No special handling needed - all access through state parameter

### 4. State Structure Dependencies

All modules access various PpuState fields:
- `state.ctrl`, `state.mask`, `state.status`
- `state.internal.v`, `state.internal.t`, `state.internal.w`, `state.internal.x`
- `state.vram`, `state.palette_ram`, `state.oam`, `state.secondary_oam`
- `state.bg_state.*`, `state.sprite_state.*`
- `state.mirroring`, `state.warmup_complete`

All fields remain accessible through state parameter - no refactoring needed

---

## Testing Strategy

### After Each Phase
1. Run full test suite: `zig build test`
2. Expected: 941/951 passing (baseline)
3. If failures: Investigate immediately, fix before continuing

### After Complete Extraction
1. Full test suite
2. AccuracyCoin verification: `zig build run -- tests/accuracycoin.nes`
3. Visual verification: Test with Bomberman or other game
4. Performance check: `zig build bench-release`

### Test Files to Watch
- `tests/ppu/*.zig` (all PPU tests)
- `tests/integration/accuracycoin_execution_test.zig`
- `tests/emulation/state_test.zig` (uses PPU through EmulationState)

---

## Execution Checklist

- [ ] Phase 1: Extract memory.zig
  - [ ] Create file with header
  - [ ] Copy functions (lines 36-189)
  - [ ] Adjust imports (relative paths)
  - [ ] Test: `zig build test`

- [ ] Phase 2: Extract scrolling.zig
  - [ ] Create file with header
  - [ ] Copy functions (lines 363-426)
  - [ ] Test: `zig build test`

- [ ] Phase 3: Extract background.zig
  - [ ] Create file with header
  - [ ] Copy functions (lines 428-544)
  - [ ] Import memory module
  - [ ] Import scrolling module (for incrementScrollX call)
  - [ ] Test: `zig build test`

- [ ] Phase 4: Extract sprites.zig
  - [ ] Create file with header
  - [ ] Copy functions (lines 546-779)
  - [ ] Import memory module
  - [ ] Test: `zig build test`

- [ ] Phase 5: Extract registers.zig
  - [ ] Create file with header
  - [ ] Copy functions (lines 190-361)
  - [ ] Import memory module
  - [ ] Test: `zig build test`

- [ ] Phase 6: Refactor Logic.zig
  - [ ] Keep init(), reset(), tickFrame()
  - [ ] Add module imports
  - [ ] Replace all function implementations with inline delegation
  - [ ] Test: `zig build test`

- [ ] Final Validation
  - [ ] Full test suite: 941/951
  - [ ] AccuracyCoin test
  - [ ] Visual test
  - [ ] Commit with detailed message

---

## Success Criteria

- ✅ All 941/951 tests passing
- ✅ Logic.zig reduced to ~60-80 lines
- ✅ 5 logic modules created (~800 total lines)
- ✅ Zero API changes (all functions preserved)
- ✅ Zero functional changes (bit-identical behavior)
- ✅ Clean module boundaries (clear separation of concerns)

---

## Risk Mitigation

**Risk:** Breaking test suite
- **Mitigation:** Test after EVERY phase, not just at end

**Risk:** Missing cross-module dependencies
- **Mitigation:** Carefully traced all function calls in analysis

**Risk:** Import path errors
- **Mitigation:** Use relative paths, verify each import

**Risk:** Forgetting to delegate a function
- **Mitigation:** Checklist of all 20 public functions

---

**Status:** Ready for execution
**Next:** Phase 1 - Extract memory.zig
