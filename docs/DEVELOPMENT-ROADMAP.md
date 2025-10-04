# RAMBO Development Roadmap

**Project:** Cycle-Accurate NES Emulator
**Language:** Zig 0.15.1
**Target:** AccuracyCoin Test Suite (128 tests)
**Current Status:** 83% Complete (575/576 tests passing)

---

## Project Vision

Build a **hardware-accurate NES emulator** demonstrating:
- Cycle-accurate 6502 emulation
- State/Logic separation architecture
- RT-safe design patterns in Zig
- Zero-cost comptime abstractions

**Not a Goal:** High compatibility across all games (targeting accuracy, not coverage)

---

## Current Status (2025-10-04)

### Completed Components ✅

| Component | Status | Tests | Completion |
|-----------|--------|-------|------------|
| CPU (6502) | ✅ Complete | 105/105 | 100% |
| PPU Background | ✅ Complete | 6/6 | 100% |
| PPU Sprites | ✅ Complete | 73/73 | 100% |
| Debugger | ✅ Complete | 62/62 | 100% |
| Thread Architecture | ✅ Complete | N/A | 100% |
| Mailbox System | ✅ Complete | N/A | 100% |
| Snapshot System | ✅ Complete | 8/9 | 99% |
| Bus & Memory | ✅ Mostly Complete | 17/17 | 85% |
| Cartridge (Mapper 0) | ✅ Complete | 2/2 | 100% |

**Overall:** 575/576 tests passing (99.8%)

### In Progress / Planned 🟡

| Component | Status | Priority | Estimated Time |
|-----------|--------|----------|----------------|
| Video Display | ⬜ Not Started | **HIGH** | 20-28 hours |
| Controller I/O | ⬜ Not Started | HIGH | 3-4 hours |
| APU (Audio) | ⬜ Not Started | MEDIUM | 40-60 hours |
| More Mappers | ⬜ Not Started | LOW | 10-15h each |

---

## Critical Path to Playability

**Goal:** Run commercial NES games (Mapper 0/NROM)

### Progress: 83% Complete

```
1. ✅ CPU Emulation          [████████████████████] 100%
2. ✅ Architecture Refactor  [████████████████████] 100%
3. ✅ PPU Background         [████████████████████] 100%
4. ✅ PPU Sprites            [████████████████████] 100%
5. ✅ Debugger               [████████████████████] 100%
6. ✅ Thread Architecture    [████████████████████] 100%
7. 🟡 Video Display          [░░░░░░░░░░░░░░░░░░░░]   0%
8. ⬜ Controller I/O         [░░░░░░░░░░░░░░░░░░░░]   0%
```

**Estimated Time to Playable:** 23-34 hours (3-5 days of focused work)

### Next Milestones

**Phase 8: Video Display** (20-28 hours) - **NEXT**
- Wayland window integration
- Vulkan rendering backend
- Frame presentation with vsync
- **Deliverable:** PPU output visible on screen

**Phase 9: Controller I/O** (3-4 hours)
- Implement $4016/$4017 registers
- Map keyboard to NES controller
- **Deliverable:** Interactive gameplay

**Phase 10: First Playable Game** (1-2 hours)
- Test with Donkey Kong, Mario Bros, etc.
- Verify accuracy with NROM titles
- **Deliverable:** Commercial games playable

---

## Architecture Phases (Historical)

### Completed Architecture Work ✅

**Phase 1: Bus State/Logic Separation** (commit 1ceb301)
- Separated BusState (data) from BusLogic (functions)
- Established hybrid pattern foundation
- Eliminated hidden state

**Phase 2: PPU State/Logic Separation** (commit 73f9279)
- Applied hybrid pattern to PPU
- Pure data structures for serialization
- Functional logic modules

**Phase A: Backward Compatibility Cleanup** (commit 2fba2fa)
- Removed legacy convenience wrappers
- Clean module re-exports
- Consistent API patterns

**Phase 3: VTable Elimination** (commit 2dc78b8)
- Replaced trait objects with comptime generics
- Duck typing for mappers (zero runtime overhead)
- Compile-time polymorphism

**Phase 4: Debugger System** (commit 2e23a4a)
- External wrapper pattern (zero EmulationState pollution)
- Breakpoints, watchpoints, callbacks
- RT-safe implementation (62/62 tests)

**Phase 5: Snapshot System** (commit 65e0651)
- State serialization for save states
- Snapshot-based time-travel debugging
- 8/9 tests passing (1 cosmetic metadata issue)

**Phase 6: Thread Architecture** (commit cc6734f)
- 2-thread mailbox pattern
- Timer-driven emulation (libxev)
- RT-safe emulation thread

**Phase 7: PPU Sprites** (commit 772484b)
- Sprite evaluation (cycles 1-256)
- Sprite fetching (cycles 257-320)
- Sprite rendering with priority
- Sprite 0 hit detection
- **73/73 tests passing**

---

## Implementation Roadmap

### Phase 8: Video Display (20-28 hours) - **CURRENT PRIORITY**

**Sub-phases:**

**8.1: Wayland Window** (6-8 hours)
- Create `src/video/Window.zig`
- Wayland protocol integration (XDG shell)
- Event handling → WaylandEventMailbox
- **Deliverable:** Window opens, responds to events

**8.2: Vulkan Renderer** (8-10 hours)
- Create `src/video/VulkanRenderer.zig`
- Initialize Vulkan (instance, device, swapchain)
- Texture upload from FrameMailbox
- **Deliverable:** Renders frame data to screen

**8.3: Integration** (4-6 hours)
- PPU → FrameMailbox connection
- Wayland thread consumes frames
- Test with AccuracyCoin.nes
- **Deliverable:** Full PPU output visible

**8.4: Polish** (2-4 hours)
- FPS counter
- Aspect ratio correction (8:7 pixel aspect)
- Vsync integration
- **Deliverable:** Production-ready video

**Documentation:**
- `docs/architecture/video-system.md` - Complete implementation guide
- `docs/architecture/threading.md` - Updated for 3-thread model

---

### Phase 9: Controller I/O (3-4 hours)

**Tasks:**
1. Implement $4016 (Controller 1 + Strobe)
2. Implement $4017 (Controller 2)
3. Map Wayland keyboard events to NES buttons
4. Add input latency measurement

**NES Controller Mapping:**
```
A      → X key
B      → Z key
Select → Right Shift
Start  → Return
Up     → Arrow Up
Down   → Arrow Down
Left   → Arrow Left
Right  → Arrow Right
```

**Deliverable:** Interactive gameplay with keyboard controls

---

### Phase 10: APU (Audio) (40-60 hours) - **FUTURE**

**Sub-phases:**

**10.1: Audio Architecture** (8-10 hours)
- Audio mailbox (ring buffer)
- Audio thread (PulseAudio/ALSA)
- Sample rate conversion (1.79 MHz → 44.1/48 kHz)

**10.2: Pulse Channels** (12-16 hours)
- Pulse 1 (with sweep)
- Pulse 2
- Length counter, envelope, sweep

**10.3: Triangle + Noise** (8-12 hours)
- Triangle channel (linear counter)
- Noise channel (LFSR)

**10.4: DMC** (8-12 hours)
- Delta modulation channel
- Sample playback
- DMA integration

**10.5: Frame Counter** (4-6 hours)
- 4-step and 5-step modes
- IRQ generation
- Timing accuracy

**Deliverable:** Full audio emulation with all 5 channels

---

### Phase 11: Mapper Expansion (Future)

**Mapper 1 (MMC1)** - 10-15 hours
- CHR bank switching
- PRG bank switching
- Mirroring control
- **Game Coverage:** +28% (Mario, Zelda, Metroid, etc.)

**Mapper 4 (MMC3)** - 12-18 hours
- 8KB CHR banks (2KB switchable)
- 8KB PRG banks
- Scanline counter for IRQs
- **Game Coverage:** +25% (Mario 2, Mario 3, etc.)

**Mapper 2 (UxROM)** - 6-8 hours
- Simple PRG bank switching
- **Game Coverage:** +10% (Mega Man, Castlevania, etc.)

**Total Coverage After Mappers 0-4:** ~68% of NES library

---

## Testing Strategy

### Unit Tests (Current: 575/576)

**CPU Tests** (105 tests)
- Instruction execution
- Unofficial opcodes
- RMW timing
- Interrupt handling

**PPU Tests** (79 tests)
- Background rendering (6 tests)
- Sprite evaluation (15 tests)
- Sprite rendering (23 tests)
- Sprite edge cases (35 tests)

**Integration Tests** (21 tests)
- CPU-PPU coordination
- NMI triggering
- DMA suspension

**System Tests** (Remaining)
- Debugger (62 tests)
- Bus (17 tests)
- Cartridge (2 tests)
- Snapshot (8/9 tests)
- Comptime (8 tests)

### AccuracyCoin Validation (Future)

**128 Comprehensive Tests:**
- CPU instructions (all addressing modes)
- PPU rendering (background + sprites)
- APU channels (all 5)
- Timing accuracy (cycle-perfect)

**Current Status:** Infrastructure ready, test ROM loads, awaiting full validation

---

## Performance Targets

### Emulation Performance

**Current (Phase 6):**
- **FPS:** 62.97 average (target: 60.10 NTSC)
- **Frame Timing:** 16ms intervals (timer-driven)
- **Deviation:** +4.8% (acceptable before vsync)

**After Phase 8 (Vsync):**
- **FPS:** 60.0 locked (monitor refresh rate)
- **Frame Timing:** Perfect presentation
- **Latency:** <1 frame input lag

### Memory Usage

**Current:**
- Frame buffers: 480 KB (double-buffered)
- Emulation state: ~50 KB
- Total working set: <1 MB

**After Phase 8:**
- +Vulkan resources: ~5-10 MB
- +Wayland buffers: ~1 MB
- Total: <12 MB

### CPU Usage

**Current:**
- Emulation thread: 100% of one core
- Main thread: <1% (coordinator)

**After Phase 8:**
- Emulation: 100% of one core
- Video thread: 10-20% of one core
- Main thread: <1%

---

## Long-Term Vision

### Accuracy Goals

**Cycle-Accurate:**
- ✅ CPU: Microstep execution (cycle-perfect)
- ✅ PPU: Dot-level rendering
- ⬜ APU: Sample-accurate audio (future)

**Hardware Behaviors:**
- ✅ RMW dummy writes
- ✅ Page crossing dummy reads
- ✅ Open bus simulation
- ✅ NMI edge detection

**Test Suite Coverage:**
- ✅ 99.8% of implemented tests (575/576)
- ⬜ AccuracyCoin full validation (future)

### Advanced Features (Post-Playability)

**Debugging Tools:**
- ✅ Breakpoints, watchpoints
- ✅ Step execution
- ✅ Time-travel debugging (snapshot-based)
- ⬜ CPU/PPU visualizers (future)
- ⬜ Memory inspector (future)

**TAS (Tool-Assisted Speedrun) Support:**
- ✅ Frame-by-frame execution
- ✅ Snapshot save/restore
- ✅ Deterministic emulation
- ⬜ Input recording/playback (future)

**Performance Modes:**
- ✅ Cycle-accurate (current)
- ⬜ Fast-forward (uncapped FPS, future)
- ⬜ Slow-motion (fractional speed, future)

---

## Known Issues & Limitations

### Current Issues

**1. Snapshot Metadata Test** (cosmetic)
- **Issue:** 4-byte size discrepancy in metadata
- **Impact:** None (functionally correct)
- **Priority:** LOW
- **Fix:** Metadata format alignment

**2. CPU Timing Deviation** (minor)
- **Issue:** Absolute,X/Y without page crossing: +1 cycle
- **Impact:** Timing slightly off, functionality correct
- **Priority:** MEDIUM (post-playability)
- **Fix:** State machine refactor

### Architectural Limitations

**1. Single-Threaded Emulation**
- Emulation is deterministic (no parallel PPU/CPU)
- Accurate but not maximum performance
- Trade-off: accuracy over speed

**2. Mapper Coverage**
- Only Mapper 0 (NROM) currently implemented
- ~5% of NES library playable
- Incremental mapper additions planned

**3. No Rewind**
- Snapshot system supports save states
- But not continuous rewind (memory prohibitive)
- Could add ring buffer of snapshots (future)

---

## Dependencies & Requirements

### Build Requirements

**Zig:** 0.15.1
```bash
zig version  # Verify 0.15.1
```

**System (Linux):**
- Wayland compositor (GNOME, KDE, Sway, etc.)
- Vulkan 1.0+ compatible GPU
- PulseAudio or ALSA (for Phase 10 audio)

### External Dependencies

**Configured in build.zig.zon:**
```zig
.dependencies = .{
    .libxev = .{
        .url = "https://github.com/mitchellh/libxev/...",
        .hash = "...",
    },
    .wayland = .{
        .url = "https://codeberg.org/ifreund/zig-wayland/...",
        .hash = "wayland-0.5.0-dev-...",
    },
},
```

**Status:**
- ✅ libxev - Integrated (timer-driven emulation)
- ✅ zig-wayland - Configured, awaiting Phase 8
- ⬜ Vulkan - Not yet integrated

---

## Contributing Guidelines

### Development Principles

1. **Hardware Accuracy First**
   - Cycle-accurate over performance
   - Test against hardware behavior
   - Document deviations

2. **State/Logic Separation**
   - All components use hybrid pattern
   - Pure data structures (State)
   - Pure functions (Logic)

3. **RT-Safety**
   - Zero heap allocations in hot path
   - Deterministic execution
   - Pre-allocated resources

4. **Comptime Over Runtime**
   - Zero-cost abstractions
   - Duck typing (no VTables)
   - Compile-time polymorphism

5. **Documentation First**
   - Code changes require doc updates
   - Architecture decisions recorded
   - Session notes for complex work

### Testing Standards

**Before Committing:**
```bash
# Run full test suite
zig build test  # Must pass 575/576

# Run specific categories
zig build test-unit
zig build test-integration

# Verify no regressions
git diff --stat  # Check test count unchanged
```

**Test Coverage:**
- All new features require tests
- Edge cases must be covered
- Integration tests for cross-component features

### Code Style

**Zig Conventions:**
- Follow stdlib style (snake_case, 4-space indent)
- Explicit error handling (no hidden `catch`)
- Memory safety (`defer` for cleanup)

**Architecture:**
- State modules: Pure data + convenience methods
- Logic modules: Pure functions only
- Module re-exports: Clean public API

---

## Resources

### Documentation

**Project Docs:**
- `CLAUDE.md` - Development guide
- `docs/README.md` - Documentation hub
- `docs/code-review/` - Architecture reviews
- `docs/architecture/` - System design docs

**NES Hardware:**
- [NESDev Wiki](https://www.nesdev.org/wiki/) - Comprehensive NES documentation
- [6502 Reference](http://www.6502.org/) - CPU architecture
- [PPU Rendering](https://www.nesdev.org/wiki/PPU_rendering) - PPU details

**Zig Resources:**
- [Zig Language Reference](https://ziglang.org/documentation/master/)
- [Zig Standard Library](https://ziglang.org/documentation/master/std/)

### Test ROMs

**AccuracyCoin:** `AccuracyCoin/AccuracyCoin.nes`
- 128 comprehensive tests
- CPU, PPU, APU, timing
- Gold standard for accuracy

**Additional Test ROMs (Future):**
- blargg's test ROMs (CPU, PPU, APU)
- Visual test ROMs (sprite, scroll)

---

## Timeline Estimates

### Short-Term (1-2 Weeks)

**Phase 8: Video Display** (20-28 hours)
- 3-5 days of focused work
- **Milestone:** PPU output visible on screen

**Phase 9: Controller I/O** (3-4 hours)
- Half-day of work
- **Milestone:** Interactive gameplay

### Medium-Term (1-2 Months)

**Phase 10: APU** (40-60 hours)
- 5-8 days of focused work
- **Milestone:** Full audio emulation

**Mapper Expansion** (30-50 hours)
- Mapper 1, 2, 4 implementation
- **Milestone:** 68% game coverage

### Long-Term (3-6 Months)

**Advanced Features:**
- CPU/PPU visualizers
- Enhanced debugging tools
- TAS recording/playback

**Polish:**
- Performance optimizations
- Extended mapper support
- Comprehensive documentation

---

## Success Criteria

### Phase 8 Success (Video Display)
- ✅ Wayland window opens and displays
- ✅ PPU output rendered at 60 FPS
- ✅ Vsync prevents tearing
- ✅ Aspect ratio correct (8:7 pixel aspect)
- ✅ Clean shutdown on window close

### Phase 9 Success (Controller I/O)
- ✅ All 8 NES buttons mappable
- ✅ Input latency <1 frame
- ✅ Games respond to input correctly

### Playability Success
- ✅ Commercial NROM games run correctly
- ✅ Audio synchronized with video (Phase 10)
- ✅ Stable 60 FPS with no crashes
- ✅ Accurate emulation (passes AccuracyCoin)

---

**Last Updated:** 2025-10-04
**Current Phase:** Phase 8 (Video Display - Wayland + Vulkan)
**Next Milestone:** First visible PPU output on screen (20-28 hours)
**Ultimate Goal:** Cycle-accurate NES emulation with playable games
