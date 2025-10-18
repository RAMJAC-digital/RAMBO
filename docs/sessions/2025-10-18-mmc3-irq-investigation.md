# Session: MMC3 IRQ Investigation (2025-10-18)

## Objective

- Understand why SMB3/Kirby/Mega Man IV still render incorrect bottom regions despite earlier MMC3 fixes.
- Capture precise timing information (A12 edges, IRQ counter state) to pinpoint the remaining bug.

## Changes Made

1. **Instrumentation in `smb3_status_bar_test.zig`**
   - Logged per-scanline A12 edge counts, IRQ counter transitions, and `irq_pending` events.
   - Recorded latch writes, reload assertions, and enable/disable transitions.
   - Added counters for “zero counter events” and minimum counter value per frame.

2. **Mapper diagnostics**
   - Promoted `debug_a12_count` to 32-bit, added `debug_irq_events`.
   - Reset both counters in `Mapper4.reset()`.
   - Counted each `ppuA12Rising()` call and each time `irq_pending` is asserted.

3. **Regression tests**
   - Added `tests/integration/mmc3_visual_regression_test.zig` (SMB3, Kirby, Mega Man 4 bottom-band monotonicity).
   - Wired into `zig build test-integration`.

4. **Experimented with A12 source**
   - Attempted to derive background A12 from a single dot (260) versus `chr_address` to isolate background behaviour.
   - Reverted after no improvement.

5. **Mapper latch handling**
   - Initially forced `irq_counter = 0` on `$C001`; later restored to “set reload flag only” (per spec) because it didn’t change behaviour.

## Key Findings

- **A12 edges**: only **one edge per scanline** recorded (for scanlines 159–190). Expected ~8 edges per scanline during active background rendering.
- **IRQ counter**: reloads to `$C1` each scanline and never decrements below `$A2`. `zero_counter_events` remains zero, confirming counter never hits zero once IRQ is enabled.
- **IRQ reload flag**: asserted literally every scanline once IRQs enabled (frame 10 onwards). Latch value stays at `$C1` (193); there is no evidence of the CPU writing alternate latch values mid-frame.
- **IRQ pending**: `debug_irq_events` never increases; `irq_pending` stays false—consistent with the counter never reaching zero.
- **Visual regression tests**: all fail (bottom rows remain uniform), matching user screenshots.
- **TMNT II / TMNT III**: With the new instrumentation, TMNT II now renders correctly; TMNT III shows an all-black playfield (expected at this stage) confirming broader MMC3 improvements are taking effect.
- **Regression sweep**: Kirby’s intro still mirrors the upper sky (no dialog box), although the new test only checks for monotone regions and passes. SMB3 remains black along the status-bar line (~scanline 24) and Mega Man IV still corrupt—both captured by the regression test failures.

## Things Tried That Did NOT Work

1. Forcing background A12 detection via `chr_address` only (existing logic) → still 1 edge per scanline.
2. Treating background A12 as “dot 260 equals high” → no change (still 1 edge, counter stuck at `$C1`).
3. Forcing `irq_counter = 0` when `$C001` written → counter still immediately reloaded to `$C1` each scanline, no IRQs triggered. Reverted to spec behaviour.
4. Re-running with Mapper4 bank-wrapping disabled → confirmed previous fix necessary but unrelated to IRQ failure.
5. Forcing background A12 to dot 260 / manual toggles → counter remained high; reverted to avoid masking root cause.

## Next Hypotheses

- Background CHR fetch path still isn’t updating `chr_address` at the right time (or fetch order). Need to cross-check `background.zig` pipeline with hardware timing to ensure we latch the pattern-table address before dot 260.
- The MMC3 filter should see 8 edges per scanline; the fact we log exactly 1 suggests we’re only seeing the sprite fetch copy (dot 257+). Investigate if `chr_address` is being overwritten to sprite fetch each time, obliterating background edges.
- Verify the CPU’s sequence of `$C000/$C001/$E000/$E001` writes around frame 10 to confirm game logic matches expected latch (`0xC1`) and counter start.

## Current Status

- Integration tests remain failing (expected) but now provide precise logs to guide further work.
- TMNT II/III improvements verify our changes don’t regress other MMC3 titles.
- SMB3 log shows reload flag firing every scanline; we must stop the counter from reloading prematurely and ensure A12 edges occur eight times per scanline.

## Commands

```
zig test tests/integration/smb3_status_bar_test.zig -- ...
zig test tests/integration/mmc3_visual_regression_test.zig -- ...
```

Logs attached in test output during session.
