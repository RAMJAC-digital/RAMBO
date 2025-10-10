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

### CPU Execution

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

### PPU Timing

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
dot -Tpng cpu-execution-flow.dot -o cpu-execution-flow.png
dot -Tpng ppu-timing.dot -o ppu-timing.png

# Generate as SVG (scalable)
dot -Tsvg architecture.dot -o architecture.svg
dot -Tsvg investigation-workflow.dot -o investigation-workflow.svg
dot -Tsvg cpu-execution-flow.dot -o cpu-execution-flow.svg
dot -Tsvg ppu-timing.dot -o ppu-timing.svg

# Generate as PDF
dot -Tpdf architecture.dot -o architecture.pdf
dot -Tpdf investigation-workflow.dot -o investigation-workflow.pdf
dot -Tpdf cpu-execution-flow.dot -o cpu-execution-flow.pdf
dot -Tpdf ppu-timing.dot -o ppu-timing.pdf
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
- **cpu-execution-flow.dot** → `docs/code-review/` CPU audit files
- **ppu-timing.dot** → `docs/code-review/ppu-register-audit-2025-10-09.md`

## Maintenance

### When to Update

- **architecture.dot**: When adding new major components or changing thread architecture
- **investigation-workflow.dot**: For each major investigation (create new file)
- **cpu-execution-flow.dot**: When CPU execution logic changes
- **ppu-timing.dot**: When frame timing or VBlank logic changes

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
