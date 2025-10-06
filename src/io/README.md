# Input/Output (Controller) - Not Yet Implemented

**Status:** Planned for Phase 9+
**Priority:** HIGH (required for gameplay)
**Reference:** `docs/implementation/STATUS.md`, `CLAUDE.md`

## Overview

The I/O module will implement NES controller input handling:

- **Standard Controller** - D-pad, A, B, Select, Start
- **Register $4016** - Controller 1 state and strobe
- **Register $4017** - Controller 2 state and frame counter

## Implementation Requirements

Controller I/O is critical path to gameplay functionality:

1. **Shift Register Implementation** - 8-bit serial read pattern
2. **Strobe Logic** - Controller polling and latching
3. **Bus Integration** - Registers $4016/$4017 read/write

**Estimated Effort:** 3-4 hours

**Blocking:** Video subsystem should be implemented first for visual feedback during controller testing.

See `CLAUDE.md` section "For Controller Implementation" for detailed requirements.
