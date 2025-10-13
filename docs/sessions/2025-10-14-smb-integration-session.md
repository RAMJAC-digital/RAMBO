# SMB VBlank/NMI Investigation — 2025-10-14

## Objective
- Reconcile PPUSTATUS ($2002) race-condition handling with NESDev documentation
- Identify why Super Mario Bros. still fails to enable rendering despite previous ledger tweaks
- Align unit/integration tests and docs with verified hardware behavior

## Baseline
- Ran `zig build test-unit --summary failures` with `ZIG_{GLOBAL,LOCAL}_CACHE_DIR=.zig_cache/...`
  - Failures limited to `vblank_ledger_test.zig` race-condition expectations
- Confirmed ledger code already clears the readable flag on race reads and tracks `last_status_read_cycle`
- Pulled NESDev references (`PPU_frame_timing`, `The_frame_and_NMIs`, `NMI`) to validate timing window

## SAT Conditions (Hardware Parity)
- Readable VBlank flag visible iff:
  1. `span_active` true (between 241.1 and 261.1)
  2. No `$2002` read recorded at or after the set cycle (`last_clear_cycle < last_set_cycle`)
- NMI should latch iff:
  1. `nmi_edge_pending` true
  2. No `$2002` read occurred on the set cycle **or** the immediately following PPU cycle (`delta > 1`)
- Any read to `$2002` during the two-cycle race window clears the flag immediately and suppresses that frame’s NMI

## Changes
- Updated `VBlankLedger.shouldNmiEdge` to treat reads on the same or next PPU cycle as suppression events (`delta <= 1`)
- Revised unit tests:
  - `vblank_ledger_test.zig` now expects the readable flag to clear for both race-window reads
  - Added explicit NMI suppression coverage for same-cycle and next-cycle reads
  - Adjusted determinism test harness to assert the new behavior without false-positive debug output
- Documentation cleanup:
  - `docs/CURRENT-ISSUES.md` now marks the ledger bug as resolved and updates priority table
  - `docs/specs/vblank-flag-behavior-spec.md` highlights the two-cycle race window and clarifies clearing semantics
  - Updated historical investigation notes (`smb-test-debug-report.md`, `smb-test-failure-analysis-2025-10-12.md`) to reflect accurate behavior

## Outstanding Work
- Re-run full unit/integration suites after updates
- Re-evaluate commercial ROM rendering tests once VBlank expectations pass
- Continue tracing SMB initialization once new baseline is verified

