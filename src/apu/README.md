# Audio Processing Unit (APU) - Not Yet Implemented

**Status:** Planned for future phase
**Priority:** LOW
**Reference:** `docs/06-implementation-notes/STATUS.md`

## Overview

The APU module will implement NES audio synthesis including:

- **Pulse Channel 1** - Square wave with sweep and envelope
- **Pulse Channel 2** - Square wave with sweep and envelope
- **Triangle Channel** - Triangle wave for bass tones
- **Noise Channel** - Pseudo-random noise generator
- **DMC (Delta Modulation Channel)** - Sample playback

## Implementation Notes

APU implementation is not required for basic emulation functionality. The emulator can run games without audio output.

**Priority Order:**
1. Video subsystem (Phase 8) - Required for visual output
2. Controller I/O - Required for gameplay
3. Additional mappers - Required for game compatibility
4. APU - Quality of life feature

See `docs/07-todo-and-roadmap/` for implementation timeline.
