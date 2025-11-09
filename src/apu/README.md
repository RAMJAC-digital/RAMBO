# Audio Processing Unit (APU)

**Status:** 86% Complete (135 tests passing)
**Last Updated:** 2025-11-08

## Overview

The APU module implements NES audio synthesis including:

- **Pulse Channel 1** - Square wave with sweep and envelope (implemented)
- **Pulse Channel 2** - Square wave with sweep and envelope (implemented)
- **Triangle Channel** - Triangle wave for bass tones (implemented)
- **Noise Channel** - Pseudo-random noise generator (implemented)
- **DMC (Delta Modulation Channel)** - Sample playback with DMA (implemented)
- **Frame Counter** - 4-step/5-step modes with IRQ generation (implemented)

## Module Structure

**State/Logic Separation Pattern:**
- `State.zig` - APU channel states, frame counter state, pure data
- `Logic.zig` - Pure functions operating on APU state
- `logic/frame_counter.zig` - Frame counter timing and IRQ logic
- `logic/registers.zig` - APU register I/O ($4000-$4017)

**Component Modules:**
- `Dmc.zig` - DMC channel implementation (separate from APU struct)
- `Envelope.zig` - Generic envelope generator component
- `Sweep.zig` - Generic sweep unit component

## Signal-Based Interface (Session 7)

**Frame Counter IRQ:**
- Function: `tickFrameCounter(state: *ApuState) void`
- Signal: `state.frame_irq_flag` (bool field)
- Pattern: Matches PPU nmi_line signal-based interface
- No return value - communicates solely via state mutation

## Implementation Status

**Completed:**
- Frame counter (4-step/5-step modes)
- DMC channel with DMA integration
- Envelope generators (all channels)
- Sweep units (pulse channels)
- Linear counter (triangle channel)
- Length counters (all channels)
- Frame IRQ generation

**Remaining Work:**
- Audio output backend (waveform generation)
- Mixer and audio buffer delivery
- Platform audio integration (SDL/ALSA/PulseAudio)
