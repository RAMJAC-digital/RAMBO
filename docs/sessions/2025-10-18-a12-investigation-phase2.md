# MMC3 A12 Investigation - Phase 2: Deep Analysis (2025-10-18)

## Status: IN PROGRESS

**Critical Finding:** Initial fix did NOT work. chr_address is not being updated during background fetches.

## Test Evidence Analysis

### Test Output from `smb3_status_bar_test.zig` (Frame 119)

```
-- A12 edge counts frame 119 --
  SL 159: 1 edges
  SL 160: 1 edges
  [... all scanlines show 1 edge ...]
  SL 190: 1 edges

-- IRQ counter transitions frame 119 --
  Frame 119 SL 159 Dot 258 counter 162 -> 193
  Frame 119 SL 160 Dot 258 counter 193 -> 192
  Frame 119 SL 161 Dot 258 counter 192 -> 191
  [... all transitions at Dot 258 ...]
```

### What This Tells Us

1. **Only 1 A12 edge per scanline** - Expected ~8
2. **All edges at Dot 258** - This is in the sprite fetch window (257-320), NOT background (1-256)
3. **Counter transitions at Dot 258** - Confirms edges happening during sprite fetch only
4. **Counter values**: 162 -> 193 = 0xA2 -> 0xC1
   - This is the reload happening (latch=$C1)
   - Then decrements: 193, 192, 191, ... 162
   - Never reaches zero (needs to hit 0 to trigger IRQ)

### Critical Question

**WHY is chr_address only being updated during sprite fetches?**

The code in `background.zig:82` and `background.zig:89` clearly sets `state.chr_address = pattern_addr`.

But the test shows NO A12 edges during background fetch window (dots 1-256).

## Hypotheses to Investigate

### Hypothesis 1: Background Fetch Not Executing
- Is `fetchBackgroundTile()` being called during dots 1-256?
- Is rendering_enabled check preventing execution?
- Is there a conditional that blocks the pattern fetch cycles?

### Hypothesis 2: Pattern Address Calculation Wrong
- Does `getPatternAddress()` return $0xxx addresses for all tiles?
- Is bit 12 always 0 for background pattern addresses?
- Is PPUCTRL.bg_pattern stuck at 0?

### Hypothesis 3: chr_address Update Timing
- Are cycles 5 and 7 executing?
- Is the switch statement in `fetchBackgroundTile()` reaching those cases?
- Is there an early return preventing the update?

### Hypothesis 4: State Mutation Order
- Is chr_address being overwritten by sprite fetches?
- Is there a race condition in state updates?
- Are we reading stale chr_address value in A12 detection?

### Hypothesis 5: Functional Purity Violation
- Are there nested timing updates?
- Is state being mutated in unexpected places?
- Are side effects not properly isolated?

## Investigation Plan

### Phase 1: Trace Execution Flow (Agents)

**Task 1: Background Fetch Call Site Analysis**
- Agent: code-reviewer
- Verify: `fetchBackgroundTile()` is called during dots 1-256
- Trace: From `Logic.zig:tick()` → `fetchBackgroundTile()`
- Check: All conditionals and guards along the path

**Task 2: Background Fetch Internal Flow**
- Agent: code-reviewer
- Verify: Switch statement execution for cycles 5 and 7
- Trace: `cycle_in_tile` calculation → switch cases → chr_address assignment
- Check: Early returns, conditions, edge cases

**Task 3: chr_address Lifecycle Analysis**
- Agent: architect-reviewer
- Trace: All writes to `state.chr_address` throughout codebase
- Verify: No unexpected overwrites between background fetch and A12 detection
- Check: State mutation order and timing

**Task 4: A12 Detection Timing**
- Agent: code-reviewer
- Verify: When `current_a12` is computed relative to chr_address updates
- Trace: Execution order within `Logic.zig:tick()`
- Check: Is A12 detection reading stale chr_address from previous cycle?

### Phase 2: Functional Purity Review (Agents)

**Task 5: Side Effect Isolation**
- Agent: architect-reviewer
- Review: All state mutations in PPU tick path
- Verify: No nested timing updates
- Check: Pure functional separation maintained

**Task 6: State Mutation Analysis**
- Agent: code-reviewer
- Map: All writes to PpuState during one tick cycle
- Verify: No conflicting mutations
- Check: State update order is deterministic

### Phase 3: Pattern Address Analysis (Agents)

**Task 7: PPUCTRL Pattern Table Selection**
- Agent: code-reviewer
- Verify: `state.ctrl.bg_pattern` value during gameplay
- Check: Is it always 0 (meaning $0000 pattern table)?
- Analyze: Game's PPUCTRL writes

**Task 8: Pattern Address Calculation**
- Agent: code-reviewer
- Trace: `getPatternAddress()` calculation step-by-step
- Verify: Bit 12 calculation when pattern_base=$0000 vs $1000
- Check: All tiles use same pattern table or different?

## Questions That Must Be Answered

1. **Is fetchBackgroundTile() executing during dots 1-256?**
   - How to verify: Add instrumentation / check call counts

2. **Is the switch statement reaching cycles 5 and 7?**
   - How to verify: Check cycle_in_tile calculation

3. **Is chr_address being set during those cycles?**
   - How to verify: Log chr_address writes with timestamps

4. **Is the chr_address value correct (has bit 12 set)?**
   - How to verify: Log pattern_base and tile_index values

5. **When is A12 detection reading chr_address?**
   - How to verify: Trace execution order in tick()

6. **Is there a timing mismatch between update and read?**
   - How to verify: Analyze state mutation order

## Execution Order Analysis Required

We need to map the exact execution order within `Logic.zig:tick()`:

```
tick(scanline, dot, cart, framebuffer):
  1. PPUMASK delay buffer advance (line 213)
  2. A12 edge detection (lines 236-268) ← READS chr_address
  3. Background pipeline (lines 270-301) ← WRITES chr_address
  4. Sprite evaluation (lines 304-321)
  5. Sprite fetching (lines 324-331) ← WRITES chr_address
  6. Pixel output (lines 334-384)
  ...
```

**CRITICAL QUESTION:** Is A12 detection (step 2) happening BEFORE background fetch (step 3)?

If yes, then A12 detection reads chr_address from the PREVIOUS cycle, not the current one!

## Functional Purity Concerns

The user is right to emphasize functional purity. We need to verify:

1. **No nested timing updates** - Each state mutation happens once per tick
2. **Side effects isolated** - State changes explicit and traceable
3. **Deterministic execution** - Same input → same output
4. **No hidden state** - All state in PpuState structure

## Next Steps (MUST NOT SKIP)

1. ✅ Create this investigation document
2. ⏳ Launch parallel agent investigations (Tasks 1-8)
3. ⏳ Synthesize agent findings into root cause document
4. ⏳ Design fix ONLY after root cause confirmed
5. ⏳ Architectural review of proposed fix
6. ⏳ Implement fix
7. ⏳ Run full test suite
8. ⏳ Document results

## DO NOT PROCEED WITHOUT

- [ ] Confirmed root cause from agent investigations
- [ ] Consensus among reviewing agents
- [ ] Clear understanding of execution order
- [ ] Verification of functional purity
- [ ] Architectural approval of fix design

---

**Status:** Phase 1 investigations launching
**Blocked on:** Agent analysis completion
**No code changes until:** Root cause confirmed by multiple agents
