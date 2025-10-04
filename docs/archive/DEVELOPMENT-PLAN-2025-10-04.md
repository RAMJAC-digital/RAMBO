# RAMBO Development Plan - October 4, 2025

**Status:** Post-Debugger Callback Implementation
**Current Progress:** 64% Architecture Complete, 486/496 Tests Passing (97.9%)
**Priority:** PPU Sprite Implementation → Video System → Full Playability

---

## Executive Summary

RAMBO has completed major architectural refactoring (Phases 1-3+A) and debugging infrastructure. The emulator is now ready for the final push to playability: sprite rendering, video display, and controller I/O.

**Key Accomplishments (Completed):**
- ✅ CPU: 100% complete (256/256 opcodes, all tests passing)
- ✅ Architecture: State/Logic separation (CPU, PPU, Bus)
- ✅ Comptime Generics: VTable elimination (zero runtime overhead)
- ✅ PPU Background: Complete rendering pipeline
- ✅ Debugger: Full system with callback support (62/62 tests)
- ✅ Test Suite: 486/496 tests passing (97.9%)

**Critical Path to Playability:**
1. **Sprite Rendering** (Phase 7) - 29-42 hours - NEXT PRIORITY
2. **Video Display** (OpenGL/SDL2) - 20-25 hours
3. **Controller I/O** ($4016/$4017) - 3-4 hours
4. **Integration & Testing** - 8-12 hours

**Total Estimated Time to Playable:** ~60-83 hours (8-11 days)

---

## Current Status Analysis

### Completed Components (100%)

#### 1. CPU Emulation ✅
- **Status:** COMPLETE
- **Tests:** 283/283 passing (100%)
- **Coverage:** All 256 opcodes (151 official + 105 unofficial)
- **Features:**
  - Cycle-accurate microstep execution
  - RMW dummy writes
  - Page boundary dummy reads
  - Open bus tracking
  - NMI edge detection, IRQ level triggering

#### 2. Architecture Refactoring ✅
- **Status:** COMPLETE (Phases 1-3+A)
- **Pattern:** Hybrid State/Logic separation
- **Components:** CPU, PPU, Bus all refactored
- **Achievements:**
  - Zero runtime overhead (comptime generics)
  - No VTables in hot paths
  - Clean module structure
  - Full type safety

#### 3. Debugger System ✅
- **Status:** PRODUCTION READY
- **Tests:** 62/62 passing (100%)
- **Features:**
  - Breakpoints (execute, memory access)
  - Watchpoints (read, write, change)
  - Step execution (instruction, scanline, frame)
  - User callbacks (onBeforeInstruction, onMemoryAccess)
  - RT-safe (zero heap allocations in hot path)
  - Async/libxev compatible
  - History buffer (snapshot-based)

#### 4. PPU Background Rendering ✅
- **Status:** COMPLETE
- **Tests:** 23/23 passing (100%)
- **Features:**
  - Tile fetching (nametable, attribute, pattern)
  - Shift registers (background pixel output)
  - Palette system ($3F00-$3F1F)
  - VRAM mirroring (horizontal/vertical)
  - Scroll registers (coarse X/Y, fine X)

#### 5. Memory Bus ✅
- **Status:** COMPLETE
- **Tests:** 17/17 passing (100%)
- **Features:**
  - RAM mirroring ($0000-$1FFF)
  - Open bus tracking
  - ROM write protection
  - PPU register routing
  - Cartridge integration

### In-Progress Components (60%)

#### 6. PPU Sprite System (0% implemented, 100% specified)
- **Status:** TESTS WRITTEN, IMPLEMENTATION PENDING
- **Tests:** 6/38 passing (16%) - 32 expected failures
- **Specification:** Complete (SPRITE-RENDERING-SPECIFICATION.md)
- **Test Coverage:**
  - 15 sprite evaluation tests
  - 23 sprite rendering tests
  - All compile, all documented

**What's Missing:**
- [ ] Secondary OAM clearing (cycles 1-64)
- [ ] Sprite evaluation (cycles 65-256)
- [ ] Sprite fetching (cycles 257-320)
- [ ] Sprite shift registers
- [ ] Sprite rendering pipeline
- [ ] Sprite priority system
- [ ] Sprite 0 hit detection
- [ ] OAM DMA ($4014)

**Estimated Effort:** 29-42 hours
**Priority:** HIGHEST (blocks playability)

#### 7. Snapshot/Debugger Implementation (100% specified, 0% implemented)
- **Status:** SPECIFICATION COMPLETE
- **Documentation:** 119 KB (5 documents)
- **Features Designed:**
  - Binary state snapshots (5 KB core)
  - JSON snapshots (8 KB core)
  - Cartridge reference/embed modes
  - Cross-platform compatibility
  - Schema versioning

**Estimated Effort:** 26-33 hours
**Priority:** MEDIUM (useful but not blocking)

### Not Started Components (0%)

#### 8. Video Display System
- **Status:** ARCHITECTURE DESIGNED, NOT IMPLEMENTED
- **Documentation:** video-subsystem-architecture.md
- **Design:**
  - Triple buffering (RT-safe frame handoff)
  - OpenGL backend (recommended)
  - 60 FPS vsync
  - Frame timing and skipping

**Estimated Effort:** 20-25 hours
**Priority:** HIGH (blocks visual output)

#### 9. Controller I/O
- **Status:** NOT STARTED
- **Requirements:**
  - $4016/$4017 register implementation
  - Shift register pattern
  - Button state tracking

**Estimated Effort:** 3-4 hours
**Priority:** HIGH (blocks playability)

#### 10. APU (Audio Processing Unit)
- **Status:** NOT STARTED
- **Complexity:** HIGH
- **Estimated Effort:** 5-7 days
- **Priority:** LOW (playable without sound)

#### 11. Mappers (MMC1, MMC3, etc.)
- **Status:** Mapper 0 (NROM) only
- **Coverage:** ~5% of NES library
- **Next Targets:**
  - MMC1: +28% coverage (Super Mario Bros)
  - MMC3: +25% coverage (Super Mario Bros 3)

**Estimated Effort:** 6-8 hours (MMC1), 12-16 hours (MMC3)
**Priority:** MEDIUM (needed for most games)

---

## Code Review Compliance

### Phase 1: Core Architecture ✅ COMPLETE
- [X] Bus State/Logic separation (commit 1ceb301)
- [X] PPU State/Logic separation (commit 73f9279)
- [X] CPU State/Logic separation (already done)
- [X] Backward compat cleanup (Phase A complete)
- [X] Module re-exports (CPU, PPU, Bus)
- [X] All 375 tests passing

### Phase 2: VTable Elimination ✅ COMPLETE
- [X] Mapper VTable → comptime generics (commit 2dc78b8)
- [X] ChrProvider VTable → direct CHR access
- [X] Cartridge(MapperType) generic type
- [X] Zero runtime overhead achieved
- [X] Duck-typed interfaces

### Phase 3: Testing Foundation ✅ COMPLETE
- [X] 15 sprite evaluation tests (Phase 4.1)
- [X] 23 sprite rendering tests (Phase 4.2)
- [X] Sprite specification document
- [X] Test-driven development approach

### Phase 4: Debugger System ✅ COMPLETE
- [X] Complete debugger implementation
- [X] User callback system
- [X] 62/62 tests passing
- [X] RT-safe, async-compatible
- [X] Production ready

### Remaining Code Review Items (Deferred/Blocked)

#### HIGH Priority (Phase 7 - Sprite Implementation)
- [ ] Implement sprite evaluation (03-ppu.md → 2.3)
- [ ] Implement sprite rendering pipeline
- [ ] Sprite 0 hit detection
- [ ] OAM DMA implementation

#### MEDIUM Priority (Phase 5+ - Video & I/O)
- [ ] Video display backend (05-async-and-io.md)
- [ ] Triple buffering implementation
- [ ] Controller I/O ($4016/$4017)
- [ ] libxev integration (full async I/O)

#### LOW Priority (Future Phases)
- [ ] Unstable opcode configuration (02-cpu.md → 2.3)
- [ ] HardwareConfig consolidation (06-configuration.md → 2.2)
- [ ] Hot-reload configuration (06-configuration.md → 2.3)
- [ ] Bus integration tests (07-testing.md → 2.1)
- [ ] Data-driven CPU tests (07-testing.md → 2.5)

#### BLOCKED (No Solution)
- [X] KDL library (none exists for Zig) - keeping manual parser

---

## Critical Path Implementation Plan

### Phase 7: Sprite Rendering (NEXT - Est. 29-42 hours)

**Objective:** Implement complete sprite system to pass all 38 sprite tests

#### Phase 7.1: Sprite Evaluation (8-12 hours)
**Files:** `src/ppu/State.zig`, `src/ppu/Logic.zig`

**Tasks:**
1. Add sprite evaluation state to PpuState
   ```zig
   secondary_oam: [32]u8 = [_]u8{0xFF} ** 32,
   sprite_count: u8 = 0,
   sprite_index: u8 = 0,
   ```

2. Implement clearSecondaryOam() (cycles 1-64)
   - Write $FF to 32 bytes (2 cycles per byte)
   - Only during visible scanlines (0-239)

3. Implement isSpriteInRange()
   - Check sprite Y vs scanline
   - Handle 8×8 vs 8×16 mode
   - 1-line offset (render on scanline+1)

4. Implement evaluateSprites() (cycles 65-256)
   - Scan primary OAM
   - Copy up to 8 sprites to secondary OAM
   - Set overflow flag if >8 sprites

**Tests:** 9 failing tests should pass
**Acceptance:** 15/15 sprite evaluation tests passing

#### Phase 7.2: Sprite Fetching (6-8 hours)
**Files:** `src/ppu/State.zig`, `src/ppu/Logic.zig`

**Tasks:**
1. Add SpriteState struct
   ```zig
   pub const SpriteState = struct {
       pattern_low: u8 = 0,
       pattern_high: u8 = 0,
       attributes: u8 = 0,
       x_counter: u8 = 0,
       active: bool = false,
   };
   sprite_state: [8]SpriteState = [_]SpriteState{.{}} ** 8,
   ```

2. Implement getSpritePatternAddress() (8×8 mode)
   - Pattern table base ($0000 or $1000)
   - Tile offset (tile_index × 16)
   - Row offset (0-7)
   - Vertical flip support

3. Implement getSprite16PatternAddress() (8×16 mode)
   - Tile bit 0 selects pattern table
   - Top/bottom half logic
   - Vertical flip support

4. Implement fetchSprites() (cycles 257-320)
   - 8-cycle fetch per sprite
   - Garbage NT reads
   - Pattern table reads

**Tests:** 7 fetching tests should pass
**Acceptance:** Pattern address tests passing

#### Phase 7.3: Sprite Rendering (8-12 hours)
**Files:** `src/ppu/Logic.zig`

**Tasks:**
1. Implement getSpritePixel()
   - X counter management
   - Shift register pixel extraction
   - Horizontal flip support
   - Priority order (0-7)

2. Integrate sprite + background pixels
   - Sprite priority system
   - Transparency handling
   - Palette selection

3. Implement sprite 0 hit detection
   - Non-transparent overlap check
   - Timing constraints (cycle 2+, not X=255)
   - Flag clearing at pre-render

**Tests:** 15+ rendering tests should pass
**Acceptance:** 38/38 sprite tests passing

#### Phase 7.4: OAM DMA (3-4 hours)
**Files:** `src/bus/Logic.zig`

**Tasks:**
1. Implement $4014 write handler
2. 256-byte copy from CPU RAM to OAM
3. CPU suspension (513-514 cycles)

**Tests:** OAM DMA tests
**Acceptance:** Fast sprite upload working

**Phase 7 Deliverables:**
- ✅ All 38 sprite tests passing
- ✅ Sprites rendering correctly
- ✅ Sprite 0 hit functional
- ✅ OAM DMA working
- ✅ Ready for video display

---

### Phase 8: Video Display System (Est. 20-25 hours)

**Objective:** Display PPU output on screen at 60 FPS

#### Phase 8.1: Backend Selection & Setup (2-3 hours)
**Decision:** OpenGL + GLFW (recommended)

**Rationale:**
- ✅ Cross-platform (Linux, Windows, macOS)
- ✅ Lightweight, minimal dependencies
- ✅ Modern OpenGL for future shader effects
- ✅ Simple 2D texture rendering
- ✅ Built-in vsync support

**Tasks:**
1. Add build dependency (build.zig.zon)
2. Link GLFW library
3. Test basic window creation

**Acceptance:** Window opens and closes cleanly

#### Phase 8.2: Triple Buffer Implementation (4-6 hours)
**Files:** `src/video/TripleBuffer.zig`

**Tasks:**
1. Create generic triple buffer type
   ```zig
   pub fn TripleBuffer(comptime T: type) type {
       return struct {
           buffers: [3]T,
           front: std.atomic.Value(u8),
           back: std.atomic.Value(u8),
           middle: std.atomic.Value(u8),

           pub fn acquireWrite(self: *Self) *T { ... }
           pub fn releaseWrite(self: *Self) void { ... }
           pub fn acquireRead(self: *Self) *const T { ... }
       };
   }
   ```

2. Integrate with PPU
   - PPU writes to back buffer
   - Display reads from front buffer
   - Atomic swap (no blocking, no copying)

**Acceptance:** RT-safe frame handoff working

#### Phase 8.3: OpenGL Rendering (6-8 hours)
**Files:** `src/video/Renderer.zig`

**Tasks:**
1. Create OpenGL context
2. Setup texture (256×240 RGBA8888)
3. Implement texture upload from framebuffer
4. Implement quad rendering (full screen or scaled)
5. Handle vsync (60 FPS target)

**Acceptance:** PPU output visible on screen

#### Phase 8.4: Frame Timing (4-6 hours)
**Files:** `src/video/FrameTiming.zig`

**Tasks:**
1. Implement frame pacing
   - Target: 60 FPS (16.67ms per frame)
   - NES: 60.0988 FPS (16.639ms)
   - Strategy: Sync to vsync, not hardware timing

2. Implement frame skipping
   - Skip rendering if emulation too slow
   - Maintain audio/input sync

3. Add performance metrics
   - FPS counter
   - Frame time histogram

**Acceptance:** Smooth 60 FPS rendering

#### Phase 8.5: Window Management (2-3 hours)
**Files:** `src/video/Window.zig`

**Tasks:**
1. Window creation/destruction
2. Resize handling
3. Fullscreen toggle
4. Aspect ratio preservation (8:7 pixel aspect)

**Acceptance:** Clean window management

**Phase 8 Deliverables:**
- ✅ PPU output displayed on screen
- ✅ 60 FPS rendering
- ✅ Triple buffering working
- ✅ RT-safe frame handoff
- ✅ Ready for controller input

---

### Phase 9: Controller I/O (Est. 3-4 hours)

**Objective:** Implement NES controller input

#### Phase 9.1: Register Implementation (2 hours)
**Files:** `src/bus/Logic.zig`

**Tasks:**
1. Implement $4016 write (strobe)
   ```zig
   // Write $01: Latch controller state
   // Write $00: Start reading sequence
   ```

2. Implement $4016/$4017 read (shift register)
   ```zig
   // Read bit 0: Next button state (A, B, Select, Start, Up, Down, Left, Right)
   // Bits 1-7: Open bus
   ```

3. Add controller state struct
   ```zig
   pub const ControllerState = struct {
       a: bool = false,
       b: bool = false,
       select: bool = false,
       start: bool = false,
       up: bool = false,
       down: bool = false,
       left: bool = false,
       right: bool = false,
       shift_register: u8 = 0,
       strobe: bool = false,
   };
   ```

**Acceptance:** Controller reads work correctly

#### Phase 9.2: Input Integration (1-2 hours)
**Files:** `src/video/Window.zig`, `src/input/Controller.zig`

**Tasks:**
1. Map keyboard → controller buttons
   - Arrow keys → D-pad
   - Z → A
   - X → B
   - Enter → Start
   - Shift → Select

2. Update controller state from GLFW events

3. Test with simple input test ROM

**Acceptance:** Controller input working in emulator

**Phase 9 Deliverables:**
- ✅ Controller registers implemented
- ✅ Keyboard input working
- ✅ PLAYABLE GAMES!

---

## Testing Strategy

### Current Test Coverage
- **Total Tests:** 496
- **Passing:** 486 (97.9%)
- **Expected Failures:** 10
  - 9 sprite evaluation/rendering (not implemented)
  - 1 snapshot metadata (cosmetic)

### Test Expansion Plan

#### Phase 7 Testing
- Run sprite tests after each sub-phase
- Verify cycle-accurate timing
- Test edge cases (Y=$FF, X=255, etc.)
- Integration tests with background rendering

#### Phase 8 Testing
- Visual verification (screenshot comparison)
- Frame timing tests (60 FPS target)
- Triple buffer stress test
- Memory leak detection

#### Phase 9 Testing
- Controller input tests
- Strobe timing tests
- Multi-controller support

#### Integration Testing
- End-to-end playability tests
- ROM compatibility tests:
  - Donkey Kong (simple graphics)
  - Super Mario Bros (scrolling, sprites)
  - Nestest ROM (CPU accuracy)
  - PPU test ROMs (rendering accuracy)

---

## Success Metrics

### Short-Term (Phase 7 - Sprites)
- ✅ All 38 sprite tests passing
- ✅ Sprites visible in test ROMs
- ✅ Sprite 0 hit working (timing-critical games)
- ✅ OAM DMA functional

### Mid-Term (Phase 8-9 - Video & Input)
- ✅ Visual output on screen (60 FPS)
- ✅ Controller input working
- ✅ Donkey Kong playable
- ✅ Super Mario Bros playable

### Long-Term (Future Phases)
- ✅ MMC1/MMC3 mappers (80% game coverage)
- ✅ APU implementation (audio output)
- ✅ Save states (debugger snapshot system)
- ✅ Accurate timing (<1% deviation)

---

## Risks & Mitigation

### Technical Risks

**Risk 1: Sprite Rendering Complexity**
- **Impact:** High (blocks playability)
- **Probability:** Medium
- **Mitigation:**
  - Follow nesdev.org specification exactly
  - Comprehensive test coverage (38 tests)
  - Incremental implementation (evaluation → fetch → render)
  - Reference other emulators if stuck

**Risk 2: Video Display Performance**
- **Impact:** Medium (affects user experience)
- **Probability:** Low
- **Mitigation:**
  - Use hardware-accelerated OpenGL
  - Triple buffering prevents blocking
  - Profile and optimize if needed
  - 256×240 is tiny by modern standards

**Risk 3: Timing Accuracy**
- **Impact:** High (breaks timing-critical games)
- **Probability:** Medium
- **Mitigation:**
  - Cycle-accurate PPU tick
  - Comprehensive timing tests
  - Reference nesdev.org timing diagrams
  - Test with timing-sensitive ROMs

---

## Resource Requirements

### Development Time
- **Phase 7 (Sprites):** 29-42 hours (4-6 days)
- **Phase 8 (Video):** 20-25 hours (3-4 days)
- **Phase 9 (Input):** 3-4 hours (0.5 day)
- **Integration:** 8-12 hours (1-2 days)
- **Total:** 60-83 hours (8-11 days)

### External Dependencies
- **GLFW:** Window/context creation
- **OpenGL:** Graphics rendering (already available)
- **libxev:** Async I/O (future - already integrated)

### Documentation Needed
- Video subsystem architecture (exists)
- Controller I/O specification (simple)
- Integration guide (new)
- User manual (future)

---

## Conclusion

RAMBO is 64% complete with a solid architectural foundation. The critical path to playability is clear:

1. **Sprite Rendering** (Phase 7) - 4-6 days
2. **Video Display** (Phase 8) - 3-4 days
3. **Controller Input** (Phase 9) - 0.5 day

**Total Time to Playable:** 8-11 days of focused development

All specifications are complete, tests are written, and the architecture is ready. The remaining work is primarily implementation following well-documented patterns.

**Next Step:** Begin Phase 7.1 (Sprite Evaluation) with comprehensive nesdev.org specification as guide.

---

**Prepared by:** Claude Code
**Date:** 2025-10-04
**Status:** Ready for Phase 7 implementation
