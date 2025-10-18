# 2025-10-15 – Open Bus & AccuracyCoin Catch-up

**Context**
- AccuracyCoin UI screenshots show systemic failures across CPU unofficial opcodes, open-bus handling, DMA synchronisation, and PPU VBlank pages.
- Emulator currently reports 930/966 passing tests but the AccuracyCoin ROM highlights regressions introduced after Phase 7 documentation sync.
- Goal of session: catalogue root causes, define corrective actions, and stage follow-on validation work.

---

## Failure Breakdown

| Area | AccuracyCoin Pages | Symptom | Root Cause | Notes |
|------|--------------------|---------|------------|-------|
| CPU / System Bus | `CPU Behavior`, `DMA + Open Bus`, `Unofficial Instructions`, `Instruction Timing` | Reads from $4020–$5FFF return `$FF`, breaking open-bus dependent harnesses, DMA sync helpers, and RMW verification | `Mapper0.cpuRead()` (default case) returns `$FF` for unmapped space; `busRead()` forwards cartridge result without falling back to `bus.open_bus` | Blocks: CPU dummy-write detection, DMA timing, APU register tests, controller open-bus bits |
| PPU Open Bus | `PPU Register Open Bus` (Test 4) | Open bus never decays; tests expecting decay to zero fail | `PpuLogic.tickFrame()` never invoked; `applyPpuCycleResult()` only toggles flags | Re-running tests after fix should allow dummy-write suite to re-run |
| DMA / Timing | `DMA + Open Bus`, `APU Register Activation`, `Instruction Timing` | Cycle synchronisation scaffolding fails before reaching assertions | Dependent on open-bus echo behaviour; `CycleClockBegin/End` rely on bus to hold opcode high byte during DMA stalls | Should retest once bus fix lands |
| VBlank & NMI Timing | `PPU VBlank Timing`, `CPU Interrupts` | Multiple fails & draws | Downstream impact from open-bus and DMA misbehaviour; ledger logic may still harbour issues but blocked behind prerequisites | After bus/decay fixes, re-run to isolate true ledger bugs |
| Known Timing Debt | `CPU Behavior 2` (Instruction Timing, Implied Dummy Reads) | +1 cycle vs hardware for absolute,X / absolute,Y / indirect,Y non-page-cross reads | Documented in `cpu/execution.zig`; backlog item | Not addressed in this session but tracked |

---

## Immediate Remediation Plan

1. **System Bus Open-Bus Echo**
   - Update `EmulationState.busRead()` to treat `$4020-$5FFF` the same way as other unmapped ranges when the mapper does not return a value; fall back to `self.bus.open_bus` instead of allowing mapper default to force `$FF`.
   - Ensure default mappers (`Mapper0`) mirror this behaviour so read helpers and tooling stay consistent.

2. **PPU Open-Bus Decay**
   - Call `PpuLogic.tickFrame()` when a frame boundary is detected in `applyPpuCycleResult()` to decrement the decay timer.
   - Confirm warm-up buffering continues to work (decay should not trigger during initial warm-up).

3. **Regression Exercise**
   - Re-run AccuracyCoin ROM (manual or automated) to verify:
     - CPU dummy-write and open-bus suites flip to PASS.
     - PPU open-bus page passes all four tests.
     - DMA timings unlock APU register suite and instruction timing harness.
   - Record residual failures; prioritise VBlank ledger vs. CPU +1 cycle debt.

---

## Follow-up Work Items

1. **Automation** – capture deterministic states from AccuracyCoin harness:
   - Extract key subtests (open bus, dummy write cycles, DMA sync) into scripted integration scenarios.
   - Hook into `zig build test-integration` (or dedicated `zig build test-accuracycoin`) once CLI harness is ready.

2. **CPU Timing Debt** – address long-standing +1 cycle offset for absolute,X/absolute,Y/indirect,Y reads without page crossing.

3. **VBlank Ledger Audit** – once prerequisites pass, focus on
   - Race condition persistence across multiple $2002 reads
   - NMI suppression when toggling PPUCTRL within VBlank

4. **Documentation Update** – reflect fixes and new automation plan in `docs/KNOWN-ISSUES` after verification.

---

## Test Strategy Snapshot

- **Short term**: manual AccuracyCoin runs after each open-bus/PPU change; capture screenshots & result tables in this archive.
- **Medium term**: build a harness that boots RAMBO headless, runs AccuracyCoin in scripted mode, and parses the on-screen result buffer (`$500-$5FF`) for pass/fail codes.
- **Long term**: integrate with CI once emulator supports deterministic headless runs and fast-forward.

---

## Open Questions

- Do other mappers override `cpuRead()` defaults with similar `$FF` fallbacks? Audit required to ensure new behaviour does not regress mapper-defined ROM/RAM regions.
- Should PPU open-bus decay be tied to vertical blank only, or should we emulate per real-frame behaviour (60 Hz) even when speed multiplier differs? Pending decision after observing behaviour with turbo/slowdown.
- Can we surface mini AccuracyCoin smoke tests directly from `zig build test-tooling` without shipping the full ROM? Feasible via extracted assembly snippets stored under `tests/data`.

