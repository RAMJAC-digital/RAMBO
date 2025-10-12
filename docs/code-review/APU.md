# APU Code Review

**Audit Date:** 2025-10-11
**Status:** Needs Refactoring

## 1. Overall Assessment

The APU implementation is functional but represents a mix of architectural patterns. It appears to be mid-transition from an older, more imperative style to the project's target State/Logic separation pattern. While core components like `Envelope` and `Sweep` are well-defined, they still contain logic that directly mutates state, which is inconsistent with the pure-function approach seen in the CPU.

The primary issue is the lack of a clear, unified `ApuLogic` module that contains all pure APU functions. Instead, logic is spread across `Dmc.zig`, `Envelope.zig`, `Sweep.zig`, and a partial `logic/registers.zig` and `logic/frame_counter.zig`. This makes the data flow harder to follow and increases the difficulty of testing and maintenance.

## 2. Issues and Inconsistencies

- **Inconsistent State/Logic Separation:**
  - `Dmc.zig`, `Envelope.zig`, and `Sweep.zig` are component-specific logic modules that directly mutate the `ApuState` struct passed to them. This violates the pure-function pattern where logic should be stateless.
  - **Example:** `Dmc.tick(apu: *ApuState)` directly modifies `apu.dmc_timer`. It should instead take `*const ApuState` and return a struct describing the changes.

- **Fragmented Logic:**
  - The main `ApuLogic` module (`src/apu/Logic.zig`) is incomplete. It acts as a facade for some register and frame counter operations but doesn't contain the core channel logic (Pulse, Triangle, Noise, DMC).
  - The core logic for the Frame Counter is correctly placed in `src/apu/logic/frame_counter.zig`, but the DMC logic remains in the top-level `Dmc.zig`.

- **Legacy Stubs:**
  - `ApuState` contains `pulse1_regs`, `pulse2_regs`, etc., which are described as "stubs for Phase 1". These should be integrated into the proper channel state structs or removed if they are no longer relevant to the current audio implementation phase.

- **API Unclear:**
  - The public API of the APU is not clearly defined. `Apu.zig` re-exports everything, making it unclear what is intended for internal vs. external use. A clean `Apu.Logic` module should expose only the necessary top-level functions (`tick`, `readRegister`, `writeRegister`).

## 3. Dead Code and Legacy Artifacts

- **`ApuState.reset()`:** This function appears to be a holdover from a previous design. The reset logic should be handled within a pure `ApuLogic.reset()` function that returns a fresh `ApuState`, consistent with how `ApuLogic.init()` works.

## 4. Actionable Development Plan

1.  **Refactor `Dmc.zig`, `Envelope.zig`, and `Sweep.zig` into Pure-Logic Modules:**
    - Modify all functions in these files to accept `*const ApuState` (or relevant sub-state) and return a `struct` describing the required state changes (e.g., `DmcTickResult`, `EnvelopeClockResult`).
    - Move these refactored logic files into the `src/apu/logic/` directory.

2.  **Create Comprehensive Channel Logic Modules:**
    - Create new files in `src/apu/logic/` for each channel: `pulse.zig`, `triangle.zig`, `noise.zig`.
    - Implement the pure-logic `tick` functions for each channel within these new modules.

3.  **Consolidate Logic in `ApuLogic.zig`:**
    - Update `src/apu/Logic.zig` to be the single public facade for all APU logic.
    - It should import the new channel logic modules (`pulse`, `triangle`, `noise`, `dmc`) and orchestrate them in its own top-level `tick` function.
    - The `ApuLogic.tick` function will be responsible for calling the channel `tick` functions and aggregating their results into a single `ApuTickResult` struct.

4.  **Update `EmulationState` to Use New API:**
    - Modify `EmulationState.stepApuCycle()` to call the new, unified `ApuLogic.tick()` function.
    - `stepApuCycle` will then be responsible for applying the state changes described by the `ApuTickResult` to the `apu` state field.

5.  **Refactor Tests:**
    - Update all tests in `tests/apu/` to use the new pure-functional API. Tests should call the logic functions and verify the returned `OpcodeResult`-style structs, rather than checking for direct state mutation.
