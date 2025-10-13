# Session: BIT timing & NMI ledger instrumentation

**Date:** 2025-10-12  
**Focus:** Improve test instrumentation around PPUSTATUS polling, VBlank ledger visibility, and SMB VBlank regression capture.

## What changed

- Added deterministic helpers to `TestHarness` (`primeCpu`, `forceVBlankStart/End`, `runPpuTicks`, `snapshotVBlank`) so tests can stage CPU/PPU timing without manually mutating the ledger.
- Refactored the BIT $2002 tests to execute against real VBlank edges and verify results using the ledger snapshots instead of direct flag toggles.
- Enhanced the SMB regression harness to log per-frame PPUCTRL/PPUMASK writes and ledger events, making the stalled NMI enable sequence obvious.
- Captured early diagnostics for BIT micro-cycles (ensuring VBlank is observed before the read) and for SMB showing the single `last_status_read_cycle` that never advances.

## Outstanding issues surfaced

- BIT timing shows the flag cleared immediately after the execute cycle, which matches hardware, but we still need to reconcile the micro-cycle ordering in the CPU implementation to remove reliance on snapshots.
- SMB continues to disable NMI after the first handler and never re-enables rendering; the new trace data confirms the missing writes and will guide the next debugging session.
- The legacy NMI sequence tests need to be aligned with the updated harness helpers; they currently over-assume the CPU micro-step values.

## Next steps

1. Use the per-cycle snapshots to cross-check the CPU microcode and ensure the execute cycle lines up with the $2002 read.
2. Compare the SMB frame trace against a known-good capture to identify which writes are missing or out of order.
3. Update the remaining NMI integration tests to use the new helpers so they assert spec behaviour instead of implementation quirks.

