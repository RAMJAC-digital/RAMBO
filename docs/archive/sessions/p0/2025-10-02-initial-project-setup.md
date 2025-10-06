# Session: 2025-10-02 - Initial Project Setup

_Historical snapshot: Metrics and status values reflect the project state on 2025-10-02._

**Date:** 2025-10-02
**Duration:** ~1 hour
**Focus:** Project infrastructure setup, dependency management, directory structure

## Goals
- [x] Add libxev dependency for event loop and thread pooling
- [x] Update build.zig with proper module configuration
- [x] Create complete directory structure for source and documentation
- [x] Verify build system works with Zig 0.15.1

## Work Completed

### Build System Configuration
- **Added libxev dependency** to `build.zig.zon`
  - Using commit `34fa50878aec6e5fa8f532867001ab3c36fae23e` (latest as of 2025-09-30)
  - This commit specifically includes Zig 0.15 compatibility fixes
  - Hash: `libxev-0.0.0-86vtc4IcEwCqEYxEYoN_3KXmc6A9VLcm22aVImfvecYs`

- **Updated `build.zig`**:
  - Added libxev as a dependency to the executable
  - Included libxev in test modules
  - Verified build compiles successfully

### Directory Structure Created

#### Source Code Structure (`src/`)
```
src/
├── cpu/          # 6502 CPU emulation
├── ppu/          # Picture Processing Unit
├── apu/          # Audio Processing Unit
├── bus/          # Memory bus and mapping
├── cartridge/    # ROM loading and parsing
├── mappers/      # Cartridge mapper implementations
├── io/           # Input/Output (audio, controllers)
├── sync/         # Synchronization primitives (lock-free queues)
└── nes/          # Top-level NES system coordination
```

#### Documentation Structure (`docs/`)
```
docs/
├── 01-hardware/              # NES hardware reference
│   ├── cpu/                  # 6502 architecture docs
│   ├── ppu/                  # PPU behavior docs
│   ├── apu/                  # APU behavior docs
│   ├── memory/mappers/       # Memory mapping and mapper docs
│   ├── timing/               # Timing diagrams and specs
│   └── references/           # External references
├── 02-architecture/          # Code organization
├── 03-zig-best-practices/    # Zig 0.15.1 idioms
├── 04-development/tooling/   # Development workflows
├── 05-testing/               # Testing strategies
│   ├── test-roms/           # Test ROM documentation
│   └── test-failure-analysis/# Failure pattern analysis
├── 06-implementation-notes/  # Session notes and decisions
│   ├── sessions/            # Daily session logs
│   ├── design-decisions/    # Architectural decisions
│   ├── blockers/            # Current blockers
│   └── discoveries/         # Hardware discoveries
├── 07-todo-and-roadmap/     # Project planning
│   └── milestones/          # Milestone definitions
├── 08-api-reference/         # Auto-generated API docs
└── 09-tooling-scripts/       # Python analysis tools
```

### Code Changes
- **Files modified**:
  - `build.zig.zon`: Added libxev dependency
  - `build.zig`: Integrated libxev into build system

- **Directories created**: 35 total (9 src/, 26 docs/)

## Technical Decisions

### libxev Version Selection
**Decision:** Use latest main branch commit instead of tagged release

**Rationale:**
- libxev doesn't use semantic versioning
- Latest commit (2025-09-30) includes critical Zig 0.15 fixes
- Project is actively maintained by Mitchell Hashimoto
- Ghostty terminal uses same approach

**Alternative considered:**
- Use older stable commit - rejected because Zig 0.15.1 compatibility is critical

### Directory Structure Philosophy
**Decision:** Separate source and documentation completely, organize docs by purpose

**Rationale:**
- Clear separation makes navigation intuitive
- Documentation can scale independently of source
- Session-based workflow supports incremental development
- Hardware reference docs provide single source of truth

## Build Verification

### Build Test
```bash
$ zig build
# Success - no errors
```

### Dependency Fetch
```bash
$ zig build --fetch
# libxev downloaded and cached successfully
```

## Next Steps (Updated)
- [x] Create initial CPU data structures (StatusFlags, Cpu struct) - COMPLETED
- [x] Implement basic memory bus with RAM - COMPLETED
- [x] Create documentation templates (session notes, design decisions) - COMPLETED
- [ ] Set up Python tooling with uv
- [x] Create first unit test to verify build pipeline - COMPLETED

## Session 2: Memory Bus Implementation (Same Day)

### Additional Work Completed
- **Implemented comprehensive memory bus** (`src/bus/Bus.zig`)
  - Open bus behavior with explicit tracking
  - RAM mirroring ($0000-$1FFF → $0000-$07FF)
  - ROM write protection
  - 6502 JMP indirect bug support (`read16Bug`)

- **Comprehensive test coverage**: 16 unit tests, all passing
  - RAM mirroring (read/write/comprehensive)
  - Open bus behavior (read/write/unmapped)
  - ROM write protection
  - 16-bit reads with little-endian and wraparound
  - JMP indirect page boundary bug
  - Dummy reads updating bus

- **Created design decision document**: `memory-bus-implementation.md`
  - Detailed rationale for all design choices
  - AccuracyCoin test requirement mapping
  - Alternative approaches considered and rejected
  - Performance considerations
  - Future enhancement plans

### Test Results
```bash
$ zig test src/bus/Bus.zig
All 16 tests passed.
```

### Key Discoveries
1. **Open bus pollution in tests**: Initial tests failed because open bus state persisted between reads. Solution: Use fresh `Bus.init()` or direct `ram[]` access.
2. **Test isolation is critical**: Each test must be independent to avoid false failures.
3. **AccuracyCoin requires explicit bus tracking**: Cannot fake with zeros or random values.

## Notes

### Zig 0.15.1 Compatibility
The project is configured for Zig 0.15.1 which introduces several API changes:
- `std.atomic.Value` replaces deprecated `std.atomic.Atomic`
- File I/O API changes (affects ROM loading later)
- Build system uses `b.path()` instead of older patterns

### Project Scope Reminder
This is a **cycle-accurate** NES emulator, meaning:
- Every CPU cycle must be emulated precisely
- PPU rendering happens dot-by-dot
- APU timing matches hardware exactly
- Target: Pass all 128 AccuracyCoin tests

### Development Workflow
All future sessions should:
1. Create session note at start (`YYYY-MM-DD-topic.md`)
2. Document design decisions separately
3. Update TODO list in `07-todo-and-roadmap/`
4. Keep hardware discoveries in respective sections

## References
- libxev repository: https://github.com/mitchellh/libxev
- libxev commit used: 34fa50878aec6e5fa8f532867001ab3c36fae23e
- Zig version: 0.15.1
- Target hardware: NTSC NES (RP2A03G CPU, RP2C02G PPU)
- Primary test suite: AccuracyCoin (128 tests)
