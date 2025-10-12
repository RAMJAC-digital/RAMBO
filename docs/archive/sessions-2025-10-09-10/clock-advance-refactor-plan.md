# Clock Advance Refactor Plan

**Audience:** Emulator core contributors working on the VBlank/NMI timing fixes.  
**Scope:** Precise specification for pulling master-clock advancement out of `EmulationState.tick()` and into a dedicated scheduler prior to implementing the timestamp-based VBlank ledger.

## 1. Motivation

- `EmulationState.tick()` currently performs three concerns at once: deciding whether the odd-frame skip applies, mutating the `MasterClock`, and invoking CPU/PPU/APU execution (`src/emulation/State.zig:280`).
- Because the PPU skip is expressed as `self.clock.advance(if (skip_cycle) 2 else 1);`, the method advances *and* executes work in the same call. This makes it difficult to represent "skip without work" semantics, complicates unit testing, and hides timing decisions from the upcoming VBlank ledger.
- Pulling clock advancement into a first-class helper gives us a single timeline authority: `tick()` simply asks the scheduler for the next slot to run and decides which subsystems receive work, while the scheduler encapsulates skips, frame boundaries, and future timing quirks (e.g. PAL differences).

## 2. Current Behaviour (Reference)

1. `tick()` computes `skip_cycle` using the odd-frame flag, rendering flag, and current scanline/dot (`src/emulation/State.zig:286`).
2. It then advances the master clock by either 1 or 2 PPU cycles (`src/emulation/State.zig:289`).
3. After advancing, it queries `clock.isCpuTick()` and executes PPU → CPU → APU in sequence (`src/emulation/State.zig:291` onward).
4. On a skip cycle we still call `stepPpuCycle()` once with the *post-skip* scanline/dot; the skipped dot never gets a chance to run. There is currently no early return.

## 3. Design Goals

- **Deterministic scheduling:** The clock should always advance exactly once per external `tick()` invocation, and the amount advanced (1 or 2 cycles) must be visible before any component work is executed.
- **Separation of concerns:** Deciding how many PPU cycles to advance belongs to a helper that owns the timing policy. Component steps operate on already-determined scanline/dot data.
- **Skip semantics:** Odd-frame skip should result in *no* PPU/CPU/APU work for that slot. We should still advance the clock, but `tick()` must return immediately afterwards.
- **Testing hooks:** The new scheduler should expose pure helpers so unit tests can ask "given state X, what is the next slot?" without running components.
- **Readability:** The new structure must make it obvious when each state mutation occurs (before or after clock advancement) so the VBlank ledger can stamp accurate cycles.

## 4. Proposed Architecture

### 4.1 Introduce `TimingStep`

Create a small struct inside `src/emulation/State.zig` (or a new `src/emulation/state/Timing.zig`) describing the next timing slot:

```zig
const TimingStep = struct {
    scanline: u16,
    dot: u16,
    cpu_tick: bool,
    apu_tick: bool,
    skip_slot: bool,
};
```

This struct is a read-only snapshot computed before any component work takes place.

### 4.2 Add `nextTimingStep()` Helper

Add a method on `EmulationState` responsible for:

1. Inspecting the current clock state plus derived flags (`odd_frame`, `rendering_enabled`).
2. Determining whether the next step is the odd-frame skip.
3. Advancing the master clock accordingly (1 or 2 PPU cycles), returning both the *pre-advance* slot and a boolean indicating whether the slot should execute component work.

Pseudo-code:

```zig
fn nextTimingStep(self: *EmulationState) TimingStep {
    const slot = TimingStep{
        .scanline = self.clock.scanline(),
        .dot = self.clock.dot(),
        .cpu_tick = self.clock.isCpuTick(),
        .apu_tick = self.clock.isApuTick(),
        .skip_slot = self.shouldSkipOddFrame(),
    };

    self.clock.advance(if (slot.skip_slot) 1 else 1); // advance by the slot width
    if (slot.skip_slot) {
        self.clock.advance(1); // second advance to leap over dot 0
    }

    return slot;
}
```

> Note: The actual implementation will advance by 1 first (pre-render → dot 0) and by an additional 1 when `skip_slot` is true, matching hardware.

### 4.3 Update `tick()` Workflow

1. Call `const step = self.nextTimingStep();`.
2. If `step.skip_slot` is true, return early—no PPU, CPU, or APU invocations.
3. Pass `step.scanline` and `step.dot` into the PPU pipeline (they represent the slot *after* the skip, because the skip has already been accounted for by the extra advance).
4. Decide CPU/APU work using the booleans on `step` rather than querying `clock` a second time.

### 4.4 Testing Strategy

- Add unit tests in `tests/emulation/state_timing_test.zig` covering:
  - Even-frame first tick → no skip.
  - Odd-frame, rendering disabled → no skip.
  - Odd-frame, rendering enabled, at `(261, 340)` → skip flagged and `tick()` returns early.
- Provide a helper in the test harness to call `nextTimingStep()` directly, ensuring the logic remains pure.

## 5. Implementation Steps

1. **Extract helper:** Introduce `shouldSkipOddFrame()` returning the boolean currently built inline (`src/emulation/State.zig:286`).
2. **Add `TimingStep` struct and `nextTimingStep()` helper** as outlined above.
3. **Refactor `tick()`** to use the helper, returning early on `skip_slot`.
4. **Adapt PPU calls** to use the scanline/dot returned by `TimingStep` instead of re-reading the clock.
5. **Update CPU/APU logic** to rely on `step.cpu_tick` / `step.apu_tick` rather than recomputing from the clock.
6. **Extend tests** (existing `state_test`, `vblank` tests) to assert the skip behaviour, adding new coverage if necessary.
7. **Document the behaviour** by updating `docs/implementation/design-decisions/final-hybrid-architecture.md` (or equivalent) to reference the new scheduler.

## 6. Risks & Open Questions

- **Timing Off-by-One:** Ensure the scanline/dot returned in `TimingStep` represents the cycle *before* any component work. Tests must confirm PPU receives the correct coordinates across the skip boundary.
- **Integration with VBlank Ledger:** When the new ledger is implemented, it should consume `TimingStep` information directly so events are stamped prior to component execution.
- **Performance Overhead:** The helper introduces minor struct allocations. We should make it `inline` and keep data on the stack to avoid regressions.

## 7. Dependencies

- This refactor must land before the new VBlank/NMI ledger so that the ledger can rely on clean scheduling semantics.
- No mapper or DMA changes required, but DMA unit tests should be rerun because the CPU tick cadence is derived from the new helper.

## 8. Acceptance Criteria

1. `EmulationState.tick()` becomes a thin coordinator that calls `nextTimingStep()` and then executes subsystems.
2. Odd-frame skip results in zero PPU/CPU/APU work while still advancing the master clock.
3. All timing-related tests pass (`zig build test`, `zig build test-integration`, `tests/ppu/vblank_nmi_timing_test.zig`).
4. Documentation reflects the new scheduling flow.

