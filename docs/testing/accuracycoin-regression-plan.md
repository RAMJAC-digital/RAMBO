# AccuracyCoin Regression Plan

**Objective**: turn the AccuracyCoin ROM into a repeatable regression suite that runs (at least partially) during development to catch bus, DMA, and timing regressions early.

## 1. Short-Term Smoke Harness

- **Manual workflow** (in place now): boot ROM with `zig build run -- AccuracyCoin.nes --inspect`, capture screenshots of each page.
- **Next action**: add scripted helper (`zig build test-tooling accuracycoin-smoke`) that
  1. boots emulator in headless mode,
  2. fast-forwards to the summary table,
  3. dumps result codes written to `$0500-$05FF`, and
  4. fails if any expected PASS entry reports `FAIL` or `DRAW`.
- **Data needed**: map of page/subtest → expected status (use codes from `tests/data/AccuracyCoin/AccuracyCoin.asm`). Store under `tests/reference/accuracycoin.json`.

## 2. Incremental Coverage

| Milestone | Scope | Notes |
|-----------|-------|-------|
| M1 | Open bus + dummy-write suites (pages 1–5, 16) | Blocks most cascading failures; requires deterministic DMA alignment.
| M2 | DMA/APU timing (pages 13–14) | Needs DMC sample playback to be deterministic without audio output.
| M3 | VBlank/NMI timing (page 17) | Depends on VBlankLedger fixes; validate race-hold semantics.
| M4 | CPU timing (page 20) | Requires eliminating +1 cycle debt for non-page-crossing absolute,X/Y/indirect,Y.

Each milestone adds expected results to the JSON manifest; the harness should tolerate `DRAW` entries for unimplemented/unstable tests until milestones complete.

## 3. Tooling Requirements

- **Headless runner**: expose CLI flag `--no-video --fast-forward` that drives emulator without Wayland.
- **Frame advance API**: extend `emulation/helpers.zig` so tests can run the core for N CPU/PPU cycles deterministically.
- **Memory snapshot**: reuse `Snapshot.writeState` to capture `$0500-$05FF` without disturbing open-bus state.

## 4. Automation Targets

- **Pre-commit**: optional local smoke run (`zig build accuracycoin-smoke`), fast (<30 s).
- **CI nightly**: full ROM run with video disabled; store result diff relative to baseline.
- **Release gate**: require MISS/FAIL count = 0 except for documented exclusions in `docs/CURRENT-ISSUES.md`.

## 5. Outstanding Questions

1. How do we detect that the ROM reached the summary screen deterministically? (Candidate: poll `$00F0` flag used by harness when tests complete.)
2. Should we strip a minimal AccuracyCoin subset into a custom ROM to avoid distributing the full binary? Investigate licensing & size constraints.
3. Can we piggy-back on existing `compiler/` Python tooling to assemble smaller targeted ROM slices?

---

**Next Steps**
- [ ] Implement prototype headless runner entry point.
- [ ] Script milestone M1 smoke harness and land expected manifest.
- [ ] Update `docs/CURRENT-ISSUES.md` with AccuracyCoin tracking column once harness reports PASS.

