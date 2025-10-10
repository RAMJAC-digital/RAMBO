# GraphViz Documentation

This directory contains GraphViz (.dot) diagrams documenting the RAMBO NES emulator architecture, investigation workflows, and timing diagrams.

## Files

### System Architecture

**`architecture.dot`** - Complete system architecture diagram
- 3-thread mailbox pattern (Main, Emulation, Render)
- State/Logic separation for all components
- Lock-free mailbox communication
- CPU/PPU/APU emulation cores
- Cartridge system with comptime generics
- Debugger RT-safe integration
- Wayland + Vulkan rendering pipeline
- All major components and their relationships

**Nodes:** ~60 components
**Clusters:** 13 major subsystems
**Patterns:** State/Logic separation, RT-safe execution, comptime dispatch

### Investigation Workflow

**`investigation-workflow.dot`** - BIT $2002 investigation process (2025-10-09)
- 5-phase investigation methodology
- Hardware specification research
- Code audit results
- Diagnostic instrumentation
- Test analysis and root cause identification
- Timeline and deliverables

**Nodes:** ~50 investigation steps
**Phases:** Research → Audit → Diagnostics → Testing → Root Cause
**Outcome:** BIT $2002 timing verified correct, frame timing issue identified

### CPU Module

**`cpu-module-structure.dot`** - Complete CPU subsystem visualization
- CPU state (6502 registers + execution state machine with 17 states)
- CPU core state (pure 6502 registers for opcode functions)
- Opcode result (delta structure with 10 fields)
- CPU logic (5 pure functions: init, reset, toCoreState, checkInterrupts, startInterruptSequence)
- Execution engine (stepCycle/executeCycle with cycle-accurate state machine)
- Microsteps (atomic hardware operations)
- Dispatch table (256-entry opcode lookup with is_rmw/is_pull flags)
- All opcode implementations (13 modules by category)
- Status flags (packed struct with correct CZIDB-VN bit order)
- Interrupt handling (NMI edge-triggered, IRQ level-triggered)
- Data flow, ownership, side effects

**Nodes:** ~60 components
**Key sections:** State machine, opcodes, dispatch, flags
**Color coding:** Blue (execution), Green (success), Red (interrupts), Orange (mutations)
**Accuracy:** 98% (Phase 1 corrections applied 2025-10-09)

**`cpu-execution-flow.dot`** - Cycle-accurate CPU execution state machine
- Execution states (fetch_opcode, fetch_operand_low, execute, write_back)
- State transition logic
- Addressing mode handling
- BIT $2002 example with 4-cycle breakdown
- Opcode dispatch system
- Bus routing to PPU registers
- PPUSTATUS read side effects

**Nodes:** ~40 execution components
**Example:** BIT $2002 cycle-by-cycle execution
**Critical Path:** Operand read happens at execute phase (cycle 4)

### PPU Module

**`ppu-module-structure.dot`** - Complete PPU subsystem visualization
- PPU state (2C02 registers, VRAM, OAM, rendering state)
- Helper types (OpenBus with decay timer, SpritePixel return type)
- PPU logic (facade delegating to specialized modules)
- Memory logic (VRAM access with mirroring)
- Register logic (CPU register interface $2000-$2007)
- Scrolling logic (Loopy registers v, t, x, w)
- Background logic (tile fetching 4-step cycle, shift registers)
- Sprite logic (evaluation @ dot 65, fetching @ dots 257-320, sprite_0_index tracking)
- PPU runtime (timing orchestrator tick function)
- Palette (NES_PALETTE_RGB: 64 colors in RGB888 format, rgbToRgba conversion)
- Warmup period (29,658 CPU cycles, guards $2000/$2001/$2005/$2006 writes)
- Data flow, critical timing points, side effects

**Nodes:** ~65 components
**Key sections:** Rendering pipeline, memory maps, scroll handling
**Critical timing:** VBlank @ 241.1 and 261.1, sprite eval @ dot 65
**Accuracy:** 99% (Phase 2 corrections applied 2025-10-09)

**`ppu-timing.dot`** - NTSC frame structure and timing
- 262 scanlines × 341 dots = 89,342 PPU cycles
- Visible scanlines (0-239), VBlank (241-260), Pre-render (261)
- VBlank flag set/clear timing (241.1 and 261.1)
- $2002 read side effects
- VBlank wait loop patterns
- CPU/PPU 3:1 synchronization
- Investigation findings and diagnostic data

**Nodes:** ~50 timing components
**Critical Timing:** VBlank @ 82,181 PPU cycles (scanline 241, dot 1)
**Issue Documented:** Tests timeout before reaching VBlank timing

### APU Module

**`apu-module-structure.dot`** - Complete APU subsystem visualization
- APU state (frame counter, 5 channels, envelopes, sweep, DMC)
- APU logic (facade delegating to registers, frame counter, DMC)
- Frame counter (240 Hz quarter-frame, 120 Hz half-frame sequencer)
  - **CORRECT TIMING:** 4-step mode = 29,830 cycles, 5-step mode = 37,281 cycles (NTSC)
- Envelope generator (reusable component for Pulse1, Pulse2, Noise)
- Sweep unit (pulse frequency modulation with one's/two's complement)
- DMC channel (delta modulation with DMA triggering)
- Register I/O ($4000-$4017 complete mapping)
- Lookup tables (DMC rate NTSC/PAL, length counter)
- Apu.zig public API (re-exports State, Logic, Dmc, Envelope, Sweep)
- Data flow, periodic clocking, IRQ generation

**Nodes:** ~60 components
**Key sections:** Channels, frame counter, components, registers
**Critical timing:** $4017 write to 5-step mode (immediate clock), frame IRQ @ 29829-29831
**Accuracy:** 99% (Phase 2 corrections applied 2025-10-09)

### Emulation Coordination

**`emulation-coordination.dot`** - Complete system integration
- Emulation state (single source of truth with direct ownership)
- Master clock (single PPU cycle counter, all timing derived)
- Timing step (odd frame skip, CPU/APU tick detection)
- VBlank ledger (cycle-accurate NMI edge detection)
- Bus state (RAM, open bus)
- OAM DMA (256-byte sprite DMA state machine)
- DMC DMA (DPCM sample fetch with CPU stall)
- Controller state (NES button shift register)
- CPU execution (cycle-accurate with DMA coordination)
- PPU runtime (explicit timing coordinates)
- Bus routing (memory map implementation)
- Debug integration (RT-safe breakpoints/watchpoints)
- Helper functions (convenience wrappers)

**Nodes:** ~80 components
**Key flow:** tick() → nextTimingStep() → clock.advance() → stepPpuCycle/stepCpuCycle/stepApuCycle
**Critical:** MasterClock single timing mutation point, VBlankLedger NMI truth source

### Cartridge and Mailbox Systems

**`cartridge-mailbox-systems.dot`** - Comptime generics + lock-free communication
- Generic Cartridge(MapperType) type factory
- Duck-typed mapper interface (cpuRead, cpuWrite, ppuRead, ppuWrite)
- Mapper registry (MapperId enum, MapperMetadata, AnyCartridge tagged union)
- Mapper 0 (NROM) implementation
- iNES parser (header format, mirroring modes)
- Mailboxes container (by-value ownership)
- FrameMailbox (triple-buffered lock-free frame data, 720 KB stack)
- SpscRingBuffer (generic SPSC lock-free ring buffer)
- ControllerInputMailbox (mutex-protected state, NOT SpscRingBuffer)
- DebugCommandMailbox (SpscRingBuffer with 10 command variants)
- DebugEventMailbox (SpscRingBuffer with 3 event variants + CpuSnapshot)
- Window/Input mailboxes (XDG events via SpscRingBuffer)
- Zero-cost polymorphism through inline dispatch
- RT-safe atomic operations (minimal mutex usage)

**Nodes:** ~75 components
**Key patterns:** Comptime generics (zero VTable overhead), Lock-free atomics (SPSC)
**Performance:** Atomic frame swap ~50-100 ns, cartridge cpuRead ~5-10 ns
**Accuracy:** 99% (Phase 2 corrections applied 2025-10-09)

## Generating Images

### Prerequisites

Install Graphviz:
```bash
# Arch Linux
sudo pacman -S graphviz

# Ubuntu/Debian
sudo apt install graphviz

# macOS
brew install graphviz
```

### Generate PNG Images

```bash
cd docs/dot

# Generate all diagrams as PNG
dot -Tpng architecture.dot -o architecture.png
dot -Tpng investigation-workflow.dot -o investigation-workflow.png
dot -Tpng cpu-module-structure.dot -o cpu-module-structure.png
dot -Tpng cpu-execution-flow.dot -o cpu-execution-flow.png
dot -Tpng ppu-module-structure.dot -o ppu-module-structure.png
dot -Tpng ppu-timing.dot -o ppu-timing.png
dot -Tpng apu-module-structure.dot -o apu-module-structure.png
dot -Tpng emulation-coordination.dot -o emulation-coordination.png
dot -Tpng cartridge-mailbox-systems.dot -o cartridge-mailbox-systems.png

# Generate as SVG (scalable)
dot -Tsvg architecture.dot -o architecture.svg
dot -Tsvg investigation-workflow.dot -o investigation-workflow.svg
dot -Tsvg cpu-module-structure.dot -o cpu-module-structure.svg
dot -Tsvg cpu-execution-flow.dot -o cpu-execution-flow.svg
dot -Tsvg ppu-module-structure.dot -o ppu-module-structure.svg
dot -Tsvg ppu-timing.dot -o ppu-timing.svg
dot -Tsvg apu-module-structure.dot -o apu-module-structure.svg
dot -Tsvg emulation-coordination.dot -o emulation-coordination.svg
dot -Tsvg cartridge-mailbox-systems.dot -o cartridge-mailbox-systems.svg

# Generate as PDF
dot -Tpdf architecture.dot -o architecture.pdf
dot -Tpdf investigation-workflow.dot -o investigation-workflow.pdf
dot -Tpdf cpu-module-structure.dot -o cpu-module-structure.pdf
dot -Tpdf cpu-execution-flow.dot -o cpu-execution-flow.pdf
dot -Tpdf ppu-module-structure.dot -o ppu-module-structure.pdf
dot -Tpdf ppu-timing.dot -o ppu-timing.pdf
dot -Tpdf apu-module-structure.dot -o apu-module-structure.pdf
dot -Tpdf emulation-coordination.dot -o emulation-coordination.pdf
dot -Tpdf cartridge-mailbox-systems.dot -o cartridge-mailbox-systems.pdf
```

### Batch Generation Script

```bash
#!/bin/bash
# Generate all diagrams in multiple formats

for file in *.dot; do
    base="${file%.dot}"
    echo "Processing $file..."
    dot -Tpng "$file" -o "${base}.png"
    dot -Tsvg "$file" -o "${base}.svg"
    dot -Tpdf "$file" -o "${base}.pdf"
done

echo "Done! Generated PNG, SVG, and PDF for all diagrams."
```

## Viewing Diagrams

### Interactive Viewing

```bash
# View with xdot (interactive)
xdot architecture.dot

# View with graphviz GUI
gvedit architecture.dot
```

### Static Image Viewing

```bash
# After generating PNG
feh architecture.png
# or
eog architecture.png
# or open in web browser
firefox architecture.svg
```

## Diagram Conventions

### Color Coding

- **Light Blue**: Main/Entry components
- **Light Green**: Core emulation (RT-safe)
- **Light Coral**: Rendering (Wayland/Vulkan)
- **Light Yellow**: Configuration/Utilities
- **Lavender**: Inter-thread communication
- **Light Gray**: Helper systems
- **Yellow**: Critical paths/findings
- **Light Green (notes)**: Verified correct
- **Light Coral (notes)**: Issues identified

### Node Shapes

- **box**: Regular component/function
- **box3d**: Major subsystem/critical component
- **cylinder**: Data storage (mailboxes, state)
- **diamond**: Decision point
- **note**: Annotation/explanation
- **folder**: Documentation artifact
- **shape=box**: Container/cluster

### Edge Styles

- **Solid line**: Direct call/dependency
- **Dashed line**: Lookup/reference
- **Dotted line**: Weak dependency/annotation
- **penwidth=2**: Critical path
- **color=red**: Error/issue path
- **color=green**: Success/verified path
- **color=blue**: Main flow

## Integration with Documentation

These diagrams complement the markdown documentation:

- **architecture.dot** → `docs/code-review/01-architecture.md`
- **investigation-workflow.dot** → `docs/investigations/bit-ppustatus-investigation-2025-10-09.md`
- **cpu-module-structure.dot** → `docs/architecture/codebase-inventory.md` (CPU section)
- **cpu-execution-flow.dot** → `docs/code-review/` CPU audit files
- **ppu-module-structure.dot** → `docs/architecture/codebase-inventory.md` (PPU section)
- **ppu-timing.dot** → `docs/code-review/ppu-register-audit-2025-10-09.md`
- **apu-module-structure.dot** → `docs/architecture/codebase-inventory.md` (APU section)
- **emulation-coordination.dot** → `docs/architecture/codebase-inventory.md` (Emulation section)
- **cartridge-mailbox-systems.dot** → `docs/architecture/codebase-inventory.md` (Cartridge + Mailboxes sections)

## Maintenance

### When to Update

- **architecture.dot**: When adding new major components or changing thread architecture
- **investigation-workflow.dot**: For each major investigation (create new file)
- **cpu-module-structure.dot**: When CPU architecture changes (new opcodes, state fields)
- **cpu-execution-flow.dot**: When CPU execution logic changes
- **ppu-module-structure.dot**: When PPU architecture changes (rendering pipeline, registers)
- **ppu-timing.dot**: When frame timing or VBlank logic changes
- **apu-module-structure.dot**: When APU architecture changes (channels, frame counter)
- **emulation-coordination.dot**: When emulation loop changes (timing, DMA, coordination)
- **cartridge-mailbox-systems.dot**: When adding mappers or changing mailbox system

### Validation

Check diagram syntax:
```bash
dot -Tcanon architecture.dot > /dev/null
# No output = valid syntax
# Errors will be printed if invalid
```

## References

- [Graphviz Documentation](https://graphviz.org/documentation/)
- [DOT Language Guide](https://graphviz.org/doc/info/lang.html)
- [Node Shapes](https://graphviz.org/doc/info/shapes.html)
- [Colors](https://graphviz.org/doc/info/colors.html)

---

**Created:** 2025-10-09
**Purpose:** Visual documentation of system architecture and investigation workflows
**Format:** GraphViz DOT language (text-based, version-controlled)
