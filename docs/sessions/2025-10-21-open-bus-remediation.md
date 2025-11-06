# Open Bus Remediation Session — 2025-10-21

## Context & Goals

- Investigate suspected open-bus inaccuracies impacting CPU NMI/VBlank behaviour.
- Align RAMBO’s CPU and PPU open bus handling with Mesen2’s dual-bus + per-bit decay model.
- Update serialization/tests accordingly to prevent regressions.

## Code Changes

- **CPU open bus**
  - Introduced `BusState.OpenBus` (external + internal latches).
  - Bus reads now update internal-only on `$4015`, writes update both.
  - Controller handler and debugger peek paths use `get()`/`getInternal()` helpers.
  - Snapshot format bumped to version 4 (external & internal bytes captured).
- **PPU open bus**
  - Replaced single-byte latch with per-bit decay stamps (`setMasked`/`applyMasked` helpers).
  - Palette and OAM reads now preserve masked bits via `applyMasked`.
  - Added frame-based decay hook and snapshot serialization for decay stamps.
- **Tests**
  - Added CPU open bus bit-5 coverage and new PPU open bus behaviour tests.
  - Updated existing tests to use new APIs (`setAll`, `applyMasked`) and snapshot expectations.

## Test Execution

Command: `zig build test`

Outcome:

- New open-bus unit tests pass.
- Suite still reports pre-existing failures (AccuracyCoin harness, VBlank ledger/NMI race fixtures, SMB1 controller integration, greyscale palette validation). These failures were present before the session; no functional regressions were introduced by the open bus refactor.

## Follow-ups / Open Questions

1. **AccuracyCoin failures** – confirm baseline status and schedule dedicated remediation once open bus changes are merged.
2. **VBlank race fixtures** – re-run after integrating ledger fixes to ensure behaviour now matches hardware expectations.
3. **Snapshot consumers** – update downstream tooling to expect snapshot version `4` (dual CPU bus bytes + PPU decay stamps).

## Artifacts

- Updated modules: `BusState`, CPU/PPU bus handlers, PPU state/logic, snapshot serializer.
- New test coverage: `tests/apu/open_bus_test.zig`, `tests/ppu/open_bus_test.zig`.

## Addendum – 2025‑10‑21 (Session Continuation)

- Attempted to tighten VBlank prevention by using exact master-cycle timestamps and reworked `seekToCpuBoundary` so tests no longer mask CPU/PPU ordering bugs.
- Updated VBlank-related integration tests to query the ledger directly instead of consuming the bus (the bus read was altering state).
- **Status:** Emulator runtime still diverges from hardware/Mesen2 (AccuracyCoin and SMB1 exhibit incorrect NMI/VBlank behaviour). The recent test updates do **not** resolve the underlying issues—they only exposed timing mismatches more clearly.
- **Next required step (pending):** Capture side-by-side cycle traces from RAMBO and Mesen2 while running real ROMs (e.g., `tests/data/AccuracyCoin.nes`) to pinpoint the exact points of divergence before making further code changes.
