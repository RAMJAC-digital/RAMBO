# Code Review – 2025-10-09

## Critical Bugs

- **Hardware IRQ path leaves the BRK flag set on the stack**  
  Files: `src/emulation/cpu/microsteps.zig:184-189`  
  Details: `pushStatusInterrupt` currently derives the status byte with `state.cpu.p.toByte() | 0x20`. If `cpu.p.break_flag` was ever set (e.g. a BRK just executed or tests toggle it manually) the pushed copy still carries bit 4 = 1. Real 6502 hardware clears the BRK flag for hardware NMIs/IRQs so RTI can distinguish software BRK vs hardware interrupt sources. With the current code an IRQ that fires after a BRK leaves bit 4 high on the stack, so RTI restores an impossible status and some ROM diagnostics (including AccuracyCoin IRQ precedence tests) will fail once we start returning from interrupts mid-test.  
  Recommendation: mask the break flag before writing (`(state.cpu.p.toByte() & ~@as(u8, 0x10)) | 0x20`) and add a regression that executes an IRQ/NMI sequence, inspects `$0100` during the stack push, and checks the restored flags.

- **Frame pacing truncates the NTSC interval and re-arms the timer with an uninitialised handle**  
  Files: `src/threads/EmulationThread.zig:152-155`, `src/threads/EmulationThread.zig:334-337`, `src/timing/FrameTimer.zig:155-185`  
  Details: we reduce the 16,639,267 ns NTSC period to `u64` milliseconds (`16_639_267 / 1_000_000`), so both the emulation thread and the async frame timer sleep for exactly 16 ms. That runs the emulation ~4 % fast (62.5 fps), breaks audio/video sync, and drifts noticeably over a few seconds—exactly the kind of timing deviation we are trying to chase out. Additionally the callback builds a fresh `xev.Timer{}` (never `init()`ed) on each frame to schedule the next tick; on libxev this is undefined behaviour and has already caused missed callbacks during long AccuracyCoin runs.  
  Recommendation: keep the interval in nanoseconds (or accumulate the fractional remainder) and reuse the timer created in `threadMain`/`AsyncFrameTimer.init`. Verify with a unit test that 1000 callbacks accumulate to ~16 639 267 000 ns (within expected tolerance) and a harness test that the emulation thread no longer drifts.

## High-Priority Fixes

- **PPU debug traces spam production builds**  
  Files: `src/emulation/Ppu.zig:13-108`, `src/ppu/logic/registers.zig:14-42`  
  Details: `DEBUG_VBLANK`, `DEBUG_PPU_WRITES`, and `DEBUG_PPUSTATUS_VBLANK_ONLY` are hard-coded to `true`. That prints multi-line diagnostics on *every* `$2000/$2001/$2002` access and each VBlank transition (~90k prints per second). Besides crippling performance, the output floods stdout so aggressively that the CLI becomes unusable and framedrop telemetry is impossible to read.  
  Recommendation: default these flags to `false`, and either stitch them into the existing CLI `--verbose/--inspect` plumbing or expose them via the debugger so we can re-enable them when instrumenting.

- **Frame drop telemetry never increments when the mailbox is saturated**  
  Files: `src/threads/EmulationThread.zig:109-116`, `src/mailboxes/FrameMailbox.zig:70-152`  
  Details: when `FrameMailbox.getWriteBuffer()` returns `null` we skip rendering (good) but the thread only calls `getFramesDropped()`—a read—so the counter never changes. The host therefore thinks zero frames were dropped even though we just discarded one, and automated diagnostics cannot tell when the video path is falling behind.  
  Recommendation: add an explicit `recordDrop()` on the mailbox (atomic fetchAdd) and call it on the skip path; extend swap logic/tests so drop statistics match the number of suppressed frames.

## Test Coverage & Observability Gaps

- `tests/cpu/interrupt_logic_test.zig` exercises edge detection but never inspects the stack contents during NMI/IRQ handling. Add a regression that runs an IRQ cycle, captures the byte written to `$0100`, and asserts bit 4 is cleared.  
- There is no pacing test for `AsyncFrameTimer` / `EmulationThread`—the current unit tests only check defaults. We should add a deterministic loop that advances a fake clock or counts callbacks to ensure 16 639 267 ns per frame is honoured (and covers the fractional remainder fix).  
- The FrameMailbox overflow path is untested: add a test that fills the ring buffer, forces a skip, and verifies both the drop counter and read/write indices behave as expected.

## Suggested Next Steps

1. Patch `pushStatusInterrupt` and land a CPU regression test that covers the NMI/IRQ stack push path.
2. Rework frame pacing to operate on nanoseconds (carry the fractional remainder) and reuse the initialised timer handle, then backfill timing tests.
3. Gate PPU debug logging behind runtime flags so the default build is quiet; confirm `zig build run --verbose` still enables diagnostics.
4. Fix frame-drop accounting and add tests for both the skip path and the swap overflow guard.
5. Re-run `zig build test` and the AccuracyCoin execution harness to confirm the fixes clear the outstanding timing regressions.

## Newly Observed Failures

- **PPUSTATUS polling tests are executing from the wrong address space**  
  Files: `tests/ppu/ppustatus_polling_test.zig:309-389`, `src/emulation/bus/routing.zig:46-87`  
  Details: the tests seed `bus.test_ram` with opcodes at `$8000`, but the reset vector (`$FFFC/$FFFD`) is left as zero. After `state.reset()` the CPU starts at `$0000` and immediately executes BRK ($00 from internal RAM), so the twelve `state.tick()` calls never issue `LDA $2002`/`BIT $2002`. The assertions now fail (`A` stays `0x00` and `ppu.status.vblank` never clears) even though the register read path itself is correct.  
  Recommendation: helper should either auto-write the reset vector when `test_ram` is assigned, or each test should set `test_ram[0x7FFC] = 0x00` / `test_ram[0x7FFD] = 0x80` before calling `reset()`. Add a small harness assertion so future tests don’t forget.

- **`getBackgroundPixel` can panic when fine X exceeds the expected range**  
  Files: `src/ppu/logic/background.zig:108-118`, triggered via `zig build test` (panic at line 109)  
  Details: the code assumes `state.internal.x` ∈ [0,7] and computes `@intCast(u4, 15 - fine_x)`. If `fine_x` ever lands at 0xFF (we’ve seen this via the new warm-up refactor) the subtraction wraps to 16 and `@intCast` traps. Even if the hardware never sets values outside 0-7 we’re now seeing this under unit test, so we need to clamp or explicitly mask the value before subtracting.  
  Recommendation: mask `fine_x` (`const fine = state.internal.x & 0x07`) and guard before the cast; add a regression that writes an oversized value through the snapshot path to prove the clamp holds.

- **Integration ROM “wait for VBlank” still times out**  
  Files: `tests/integration/vblank_wait_test.zig:98-161`  
  Details: with debug prints disabled the harness still never observes bit 7 of `$2002` going high—the loop runs the full two-frame budget and raises `error.VBlankWaitTimeout`. Recorder output shows BIT hitting `$2002` (we log the “VBlank flag cleared” trace) yet the CPU keeps branching. We’re likely clearing the VBlank flag before the flag copy reaches the status byte that BIT sees, so the VBlank ledger/flag synchronisation needs another pass. Please reproduce with the ROM helper and inspect the negative flag after each BIT.

- **Test harness still spams `$2002` diagnostics**  
  Files: `src/ppu/logic/registers.zig:14-42`, `src/emulation/Ppu.zig:13-108`  
  Details: despite the recent cleanup request, the DEBUG toggles remain `true`, which drowned the regression run in `$2002` traces and forced us to abort a 51s test sweep. We need to wire these into a runtime flag before re-running suites; otherwise all future CI logs will be unreadable.
