# Phase 1 Remaining Files - Comprehensive Analysis

**Date:** 2025-10-09
**Status:** Analysis Complete - Ready for Execution
**Baseline:** 941/951 tests passing

---

## Executive Summary

Phase 1 has achieved 82% completion with major refactorings done:
- ✅ State.zig: -77.8% (2,225 → 493 lines)
- ✅ VulkanLogic.zig: -92.2% (1,857 → 145 lines)
- ✅ Debugger.zig: -46.8% (1,243 → 661 lines)
- ✅ Config.zig: -37.1% (782 → 492 lines)

**Remaining files** (2,781 total lines):
- **P1**: PPU Logic.zig (779 lines, 20 functions)
- **P2**: APU Logic.zig (453 lines, 16 functions)
- **P2**: CPU variants.zig (563 lines, 22 functions)
- **P2**: CPU dispatch.zig (532 lines)
- **P2**: CPU decode.zig (454 lines)

---

## File 1: PPU Logic.zig (779 lines)

### Current State
**Already following Logic pattern** - pure functions operating on PpuState

**Structure:**
- 20 public functions
- 2 private helper functions
- Clear functional groupings identified

### Function Groups
1. **Initialization** (2 functions)
   - init(), reset()

2. **Memory Mirroring** (2 functions - private)
   - mirrorNametableAddress(), mirrorPaletteAddress()

3. **VRAM Access** (2 functions)
   - readVram(), writeVram()
   - Interacts with cartridge

4. **Register I/O** (2 functions)
   - readRegister(), writeRegister()
   - Handles $2000-$2007 PPU registers

5. **Scroll Management** (4 functions)
   - incrementScrollX(), incrementScrollY()
   - copyScrollX(), copyScrollY()
   - PPU address register manipulation

6. **Background Rendering** (5 functions)
   - getPatternAddress(), getAttributeAddress()
   - fetchBackgroundTile(), getBackgroundPixel()
   - getPaletteColor()

7. **Sprite Rendering** (7 functions)
   - getSpritePatternAddress(), getSprite16PatternAddress()
   - fetchSprites(), evaluateSprites()
   - getSpritePixel(), reverseBits()

8. **Frame Timing** (1 function)
   - tickFrame()

### System Interactions
- **Used by**: bus/routing.zig (register I/O)
- **Depends on**: PpuState, AnyCartridge, palette.zig
- **Side effects**: None (pure functions)

### Decomposition Strategy

**Recommended: Split into 5 modules**
```
src/ppu/
├── Logic.zig (100-150 lines) - Facade with re-exports
├── logic/
│   ├── memory.zig (~150 lines) - VRAM + mirroring
│   ├── registers.zig (~150 lines) - Register I/O
│   ├── scrolling.zig (~120 lines) - Scroll operations
│   ├── background.zig (~180 lines) - Background rendering
│   └── sprites.zig (~250 lines) - Sprite rendering + evaluation
```

**Benefits:**
- Clear separation of concerns
- Each module < 300 lines
- Maintains existing API through re-exports
- Easier to debug rendering issues

**Risk:** 🟢 LOW
- Already pure functions
- No complex state interactions
- Clear module boundaries

**Estimated Time:** 3-4 hours

---

## File 2: APU Logic.zig (453 lines)

### Current State
**Already following Logic pattern** - pure functions operating on ApuState

**Structure:**
- 16 public functions
- Timing constants and lookup tables
- Channel-specific operations

### Function Groups
1. **Initialization** (2 functions)
   - init(), reset()

2. **Register Writes** (5 functions)
   - writePulse1Reg(), writePulse2Reg()
   - writeTriangleReg(), writeNoiseReg()
   - writeDmcReg()

3. **Channel Clocking** (5 functions)
   - clockPulse1(), clockPulse2()
   - clockTriangle(), clockNoise()
   - clockDmc()

4. **Frame Counter** (2 functions)
   - writeFrameCounter()
   - clockFrameCounter()

5. **Status/Output** (2 functions)
   - readStatus()
   - outputMix() (likely - need to verify)

### System Interactions
- **Used by**: bus/routing.zig, dma/logic.zig
- **Depends on**: ApuState, Dmc.zig, Envelope.zig, Sweep.zig
- **Side effects**: DMC DMA trigger (via callback)

### Decomposition Strategy

**Recommended: Split into 4 modules**
```
src/apu/
├── Logic.zig (80-100 lines) - Facade with re-exports
├── logic/
│   ├── pulse.zig (~120 lines) - Pulse 1 & 2 channels
│   ├── triangle.zig (~80 lines) - Triangle channel
│   ├── noise.zig (~80 lines) - Noise channel
│   └── frame.zig (~100 lines) - Frame counter + DMC
```

**Benefits:**
- Channel isolation aids debugging
- Each module < 150 lines
- Matches audio hardware architecture
- Easier to implement/verify each channel

**Risk:** 🟢 LOW
- Already pure functions
- Clear channel boundaries
- Well-documented timing

**Estimated Time:** 2-3 hours

---

## File 3: CPU variants.zig (563 lines)

### Current State
**Comptime type factory** - different pattern from State/Logic

**Structure:**
- CpuVariant enum (6 variants)
- VariantConfig struct
- getVariantConfig() function
- Cpu() comptime factory (main content)
- 22 public functions (unstable opcodes with variant-specific behavior)

### Unique Characteristics
This file is fundamentally different:
- **Comptime specialization** - zero runtime overhead
- **Type factory pattern** - generates types at compile time
- **Duck typing** - variants implement interface implicitly
- **No State/Logic separation needed** - already pure

### Analysis
The file contains:
1. **Variant definitions** (~50 lines)
2. **Type factory wrapper** (~30 lines)
3. **Unstable opcode implementations** (~480 lines)
   - LXA, XAA, LAX, SAX, AHX, SHY, SHX, TAS
   - DCP, ISC, RLA, RRA, SLO, SRE
   - Each with variant-specific magic constants

### Decomposition Strategy

**Recommended: Extract unstable opcodes**
```
src/cpu/
├── variants.zig (80-100 lines) - Factory + configs
├── unstable/
│   ├── load.zig - LXA, XAA, LAX
│   ├── store.zig - SAX, AHX, SHY, SHX, TAS
│   └── rmw.zig - DCP, ISC, RLA, RRA, SLO, SRE
```

**Alternative: Leave as-is**
This file is already well-organized and the comptime factory pattern
benefits from having all variant-specific code in one place for easy
comparison and verification against hardware docs.

**Risk:** 🟡 MEDIUM
- Comptime code is tricky to refactor
- Breaking factory pattern reduces maintainability
- Current structure aids hardware verification

**Recommendation:** **DEFER** to Phase 2
- File is manageable at 563 lines
- Comptime pattern is appropriate
- Not causing maintenance issues
- Risk outweighs benefits

**Estimated Time if done:** 4-5 hours

---

## Files 4 & 5: CPU dispatch.zig (532) & decode.zig (454)

### Current State
**Opcode routing tables** - special purpose files

**dispatch.zig:**
- Maps 256 opcodes → executor functions
- Large match statement
- No decomposition needed (routing table nature)

**decode.zig:**
- Opcode decoding tables
- Addressing mode tables
- Instruction mnemonics
- No decomposition needed (data table nature)

### Analysis
These files are **intentionally large tables** that serve as lookups.
Breaking them up would harm readability and maintainability.

**Recommendation:** **LEAVE AS-IS**
- Table files should be comprehensive
- Breaking up routing tables reduces clarity
- Current structure is optimal for purpose

---

## Phase 1 Completion Strategy

### Recommended Approach

**Priority 1: PPU Logic.zig** (3-4 hours)
- Highest-priority P1 file
- Clean extraction with clear benefits
- Aids PPU bug debugging

**Priority 2: APU Logic.zig** (2-3 hours)
- Second P1 file
- Clean extraction with channel isolation
- Aids audio implementation

**Priority 3: CPU files** (DEFER)
- variants.zig: Comptime pattern best kept unified
- dispatch/decode.zig: Table files optimal as-is

### Time Estimate
- PPU decomposition: 3-4 hours
- APU decomposition: 2-3 hours
- Testing & validation: 1-2 hours
- Documentation: 1 hour
- **Total: 7-10 hours**

### Success Criteria
- ✅ PPU Logic.zig < 200 lines
- ✅ APU Logic.zig < 150 lines
- ✅ All tests pass (941/951 baseline)
- ✅ Zero API breakage
- ✅ Zero functional changes

---

## Risk Assessment

### Overall Risk: 🟢 LOW

**Mitigating Factors:**
- Both files already follow Logic pattern
- Pure functions (no hidden state)
- Clear module boundaries identified
- Established patterns from previous refactorings
- Comprehensive test coverage

**Risk Factors:**
- PPU rendering is complex (many interdependencies)
- APU has timing-sensitive operations
- Hardware accuracy critical

**Mitigation Strategy:**
1. Extract one module at a time
2. Run full test suite after each module
3. Verify AccuracyCoin still passes
4. Use inline delegation in facade
5. Maintain exact function signatures

---

## Next Steps

1. **Create detailed execution plan for PPU Logic**
   - Map exact extraction boundaries
   - Plan import structure
   - Design facade pattern

2. **Execute PPU decomposition**
   - Extract modules in dependency order
   - Test after each module
   - Commit when complete

3. **Create detailed execution plan for APU Logic**
   - Same process as PPU

4. **Execute APU decomposition**
   - Extract channel modules
   - Test thoroughly
   - Commit when complete

5. **Final Phase 1 validation**
   - Full test suite
   - Documentation update
   - Progress tracking

6. **Decision point: CPU variants**
   - Evaluate if extraction needed
   - Document decision
   - Plan for Phase 2 if deferred

---

## Appendix: Comparison with Previous Refactorings

### Pattern Comparison

| File | Pattern | Modules | Result |
|------|---------|---------|--------|
| State.zig | State/Logic | 5 logic + helpers | -77.8% |
| VulkanLogic.zig | Logic modules | 5 specialized | -92.2% |
| Debugger.zig | State/Logic facade | 6 logic + facade | -46.8% |
| Config.zig | Type extraction | 3 type modules | -37.1% |
| **PPU Logic** | **Logic modules** | **5 rendering** | **~-75% target** |
| **APU Logic** | **Logic modules** | **4 channels** | **~-70% target** |

All follow established patterns with proven success.

---

**Document Status:** Analysis Complete
**Ready for:** Execution
**Approved by:** Pending user review
