# 2025-10-19 Dummy Write & NMI Accuracy Investigation

## Context
- Triggered by AccuracyCoin integration failures:
  - `dummy_write_cycles_test` returns result `0x80` (never clears RUNNING), `ErrorCode=0x02`, CPU ends at `$0602` executing `BRK`.
  - `nmi_control_test` returns `result=0x80`, `ErrorCode=0x06`.
- Emulator already includes VBlank ledger refactor from previous session; need to validate remaining gaps.

## Reproduction & Instrumentation
- Harness-driven diag (`zig test diagnose_dummywrite.zig`) confirms harness completes stage 2 setup, but exits early:
  - CPU hits `BRK` at cycle `184640`, accumulator `0x0A` (`ErrorCode << 2 | 0x02` with `ErrorCode=0x02`).
  - VRAM probes show pre-seeded values intact at targets `0x2E5C/5D/17/97/2D/2F` (values `8D/A5/F0/36/98/4F`).
  - Stage 3 never reached; failure occurs in stage 2 (non-indexed RMW).
- Manual simulation of an `ASL $2006` RMW using the emulator core reproduces correct behaviour (dummy write 0x2E, final write 0x5C, `PPUDATA` returns `0x8D`). That isolates the problem to the CPU execution pipeline rather than PPU register logic.
- Runtime instrumentation (temporary logging in `EmulationState.busWrite`) showed no `0x2006` bus writes attributed to `0x1E/0x3E/...` opcodes during the failing AccuracyCoin run— only housekeeping code touched `0x2006`. Indicates our RMW instruction flow is not issuing the dummy/final writes for absolute addressing.
- `ErrorCode` trace reveals lifecycle:
  - `0x00→0x01→0x02→0x03` during test setup (stage 1 + stage 2 pre-pass).
  - `ErrorCode` later reset to `0x01`, then `0x02` immediately before halt, matching ROM comment “FAIL 2”.
  - CPU sits at `$A35D` (opcode `0x06`) when final `ErrorCode=0x02` recorded, pointing at zero-page helper sequence rather than the expected absolute,X block. Suspect the test replays a zeropage verification that never progresses to the absolute addressing opcodes because the first RMW assertion still fails.

### Hypothesis – Dummy Write Failure Path
1. The ROM performs `JSR TEST_DummyWritePrep_PPUADDR2DFA` then `ASL $2006`.
2. Execution should call `rmwDummyWrite` (original value 0x2D/0x2E) followed by `aslMem` writing the shifted value.
3. Logging shows these bus writes never happen; the instruction likely bails before reaching the execute state or masks the write because `state.cpu.execute` uses a zeroed `bus_write`.
4. Inspection of `emulation/cpu/execution.zig` shows that during `execute`, we recompute the operand for `.absolute` instructions via `state.busRead(...)` unless the instruction is in the write-only list (STA/STX/STY only). **RMW instructions are not exempt**, so `ASL $2006` triggers an extra `busRead` in execute which resets `state.cpu.temp_value` (open bus) and may short-circuit the write when the opcode logic uses the now incorrect operand.
5. This read also means the execute stage runs with `state.cpu.address_mode == .absolute`, not `.absolute_x`, because the dispatch entry for `0x0E` is absolute; for `0x1E` we rely on cached `temp_value`. Need to audit whether our operand fetch path zeroes out the value for RMW before `aslMem` sees it.

### NMI Control Findings
- Diagnostic run recorded `ErrorCode` increments 1→6, so all subtests execute sequentially.
- Subtests 5 & 6 (where NMI re-enable timing is checked) show:
  - `nmi_line` still asserted when ROM expects suppression.
  - `last_read_cycle` remains `528912` even after subsequent `$2002` reads, meaning our ledger sometimes misses the read timestamp under certain access patterns (likely when the read happens via indexed dummy cycles or after CPU reconfigures NMI mid-instruction).
- Failure signature: by the time `ErrorCode` hits `0x06`, `vblank_visible` is still `true` and `nmi_line` stays asserted even though ROM wrote `$2000` with bit7 clear followed by a read of `$2002`. Suggests we need to persist the “read-while-vblank-set” sticky more than one cycle (NES keeps suppression until next vblank) or ensure `$2002` reads that occur via indirect/dummy paths update `last_read_cycle`.

## Potential Root Causes
1. **RMW execute path double-reading**: `execute` stage re-reads absolute operands unless opcodes are STA/STX/STY. RMW instructions should bypass that read; otherwise we lose the original operand and the write occurs with zero/garbage, breaking write side effects.
2. **Instruction fallthrough assumption**: For RMW, after addressing finishes we always run execute on the next tick. Ensure no conditional fallthrough is skipping the execute stage for absolute / absolute,X RMW.
3. **NMI ledger read detection**: `last_read_cycle` only updates when `read_2002` flag returned by `PpuLogic.readRegister`. Need to confirm all `$2002` read codepaths (including test harness and DMA introspection) route through `busRead` so the ledger sees them. Session logs show `last_read_cycle` stuck, implying a path bypassing the ledger.

## Remediation Plan (Next Steps)
1. **CPU RMW audit**
   - Update `execute` operand resolution to skip the extra `busRead` for all RMW opcodes (add them to the write-only list or guard by `entry.is_rmw`).
   - Re-run `diagnose_dummywrite.zig` to verify `DoubleLDA2007` reads expected values and `ErrorCode` advances past `0x02`.
   - Add focused unit test covering `ASL $2006` / `ROL $2006` dummy writes (simulate harness scenario) to protect regression.

2. **NMI ledger fixes**
   - Investigate paths where `$2002` is read but `last_read_cycle` not set (maybe due to CPU state machine calling `busRead` while `state.cpu.state != .execute`?).
   - Ensure race flag (`last_race_cycle`) survives multiple reads during the same frame; current implementation resets on first `$2002` read, which might clear suppression too early.
   - Build micro diagnostic replicating AccuracyCoin subtest 6: enable NMI mid-vblank, read `$2002`, re-enable, check whether emulator queues new NMI immediately. Adjust ledger logic accordingly.

3. **Testing**
   - Once fixes applied, rerun both integration tests plus `zig build test-unit` (the failing `jmp_indirect_test` needs to be rechecked after CPU pipeline edits).

## Notes
- Removed all temporary debugging scripts (`diagnose_*.zig`) after investigation.
- No project code changes committed during this session.
- NMI debugging indicates ledger improvements still needed despite cycle timestamp refactor; keep an eye on `last_read_cycle` across dummy reads and DMA side effects.
