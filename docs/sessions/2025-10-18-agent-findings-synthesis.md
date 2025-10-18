# Agent Findings Synthesis: MMC3 A12 Investigation (2025-10-18)

## Status: ANALYZING CONFLICTING REPORTS

## Agent Reports Summary

### Agent 1: Background Fetch Execution Flow
**Conclusion:** Execution order bug - A12 detection reads chr_address BEFORE background fetch writes it

**Key Finding:**
```
Current order (BROKEN):
  236-268: A12 detection (reads chr_address)
  270-301: Background fetch (writes chr_address)
```

**Evidence:**
- fetchBackgroundTile() executes during dots 1-256 ✓
- Cycles 5 and 7 execute correctly ✓
- chr_address is written at lines 82, 89 ✓
- BUT A12 detection happens BEFORE these writes

### Agent 2: chr_address Lifecycle
**Conclusion:** Confirms execution order bug, functional purity violation (temporal consistency)

**Key Finding:**
- chr_address writes happen at:
  - background.zig:82,89 (32 times/scanline during dots 1-256)
  - sprites.zig:102,120 (8 times/scanline during dots 257-320)
- A12 detection reads chr_address at Logic.zig:246
- Read happens BEFORE writes in tick() execution order

**Purity Assessment:**
- ❌ Temporal consistency violated (read-before-write)
- ✅ No nested state updates
- ✅ Side effects isolated
- ✅ No global state

### Agent 3: Pattern Address Calculation
**Conclusion:** Behavior is EXPECTED and CORRECT for SMB3's static pattern table allocation

**Key Finding:**
- SMB3 uses standard NES configuration:
  - Background: Pattern table 0 ($0000-$0FFF, A12=0)
  - Sprites: Pattern table 1 ($1000-$1FFF, A12=1)
- Result: Only 1 A12 rising edge per scanline (background→sprite transition at dot 258)
- This matches test output EXACTLY

**Calculation Verification:**
- pattern_base calculation: ✓ CORRECT
- Address calculation: ✓ CORRECT
- Bit 12 extraction: ✓ CORRECT

## Conflict Analysis

### The Contradiction

**Agent 1 & 2:** There's a bug (execution order)
**Agent 3:** Behavior is correct (static pattern tables)

### Resolution

**Both are partially correct!**

1. **Execution order bug EXISTS:**
   - A12 detection at lines 236-268 runs BEFORE background fetch at 270-301
   - This means A12 detection reads chr_address from PREVIOUS tick
   - This is a functional purity violation

2. **For SMB3, static pattern tables mean:**
   - All background tiles use pattern table 0 ($0xxx, A12=0)
   - All sprites use pattern table 1 ($1xxx, A12=1)
   - Only 1 transition per scanline: background→sprite at dot ~258
   - Even with execution order bug, this still produces 1 edge/scanline

3. **The execution order bug MIGHT NOT MATTER for SMB3 specifically**
   - Because background tiles all have A12=0 anyway
   - The transition happens during sprite fetch (which already works)
   - But this is ACCIDENTAL, not correct design

## Critical Questions Remaining

### Q1: Why does the test show counter stuck at 162-193?

Test output:
```
Frame 119 SL 159 Dot 258 counter 162 -> 193
Frame 119 SL 160 Dot 258 counter 193 -> 192
...
Min IRQ counter observed this frame: 162
```

The counter:
- Jumps from 162→193 at scanline 159 (RELOAD)
- Then decrements: 193→192→191→...→162
- Decrements by 31 per frame (~32 scanlines)
- Never reaches 0 (would need to start at 31 or less)

**Issue:** Counter decrements correctly BUT starts too high (193 = $C1 latch value)

### Q2: Why is reload happening at scanline 159?

Investigation notes show:
```
>>> IRQ reload set at frame 10 SL 248 Dot 303
```

The reload flag is set by CPU writing to $C001. But why at every frame?

### Q3: Is 1 edge per scanline sufficient for MMC3 IRQ?

**Hypothesis:** MMC3 is designed to trigger IRQ after N scanlines, not N tile fetches.

If game sets latch to 31 and enables IRQ:
- Counter starts at 31
- Decrements once per scanline (1 A12 edge)
- After 32 scanlines, counter hits 0 → IRQ fires

**This would be CORRECT if we're getting 1 edge per scanline consistently.**

But test shows counter starts at 162 (too high for 32 scanlines).

## Test Evidence Re-Analysis

### What the test ACTUALLY shows:

```
SL 159: 1 edge at dot 258 → counter 162->193 (RELOAD)
SL 160: 1 edge at dot 258 → counter 193->192 (decrement)
SL 161: 1 edge at dot 258 → counter 192->191 (decrement)
...
SL 190: 1 edge at dot 258 → counter 163->162 (decrement)
```

**Observations:**
1. Getting 1 A12 edge per scanline ✓
2. Counter IS decrementing (one per edge) ✓
3. Counter RELOADS at scanline 159 (why?)
4. Starting value 193 too high (needs ≤31 for 32-scanline split)

## New Hypothesis: Game Logic Issue?

**Could the problem be in how SMB3 is using the MMC3?**

Possible scenarios:
1. Game sets latch too high ($C1 = 193 instead of ~$1F = 31)
2. Game writes $C001 (reload) every frame instead of once
3. Game enables IRQ too late in the frame
4. Our emulation timing is off (IRQ enabling/disabling)

## Questions for Further Investigation

### Must Answer Before Implementing Fix:

1. **Is the execution order bug relevant for games that DO switch pattern tables mid-frame?**
   - Some games might alternate tiles between $0xxx and $1xxx
   - Would need multiple A12 edges during background fetch
   - Execution order bug WOULD break those games

2. **What is the correct IRQ counter behavior?**
   - Should counter decrement once per scanline or once per A12 edge?
   - If once per edge, then execution order matters
   - If once per scanline, maybe 1 edge is enough?

3. **Why does SMB3 set latch to $C1 (193)?**
   - Status bar is at scanline ~24
   - From scanline 24 to end of visible (239) = 215 scanlines
   - 193 is close to 215... coincidence?

4. **When should the IRQ fire for status bar split?**
   - Status bar is visible (top of screen)
   - Playfield should start around scanline 24-32
   - IRQ should fire around scanline 24 to switch scroll

## Architectural Concerns

### Execution Order

Even if SMB3 works accidentally, the execution order IS wrong architecturally:

**Current (WRONG):**
```zig
1. Read chr_address (A12 detection)
2. Write chr_address (background fetch)
```

**Should be (RIGHT):**
```zig
1. Write chr_address (background fetch)
2. Read chr_address (A12 detection)
```

**Why it matters:**
- Violates temporal consistency
- Reads stale data from previous cycle
- May break games that switch pattern tables dynamically
- Functionally impure design

### Recommendation

**Fix the execution order bug REGARDLESS of whether it fixes SMB3.**

Reasons:
1. Architectural correctness (functional purity)
2. Future-proofing (games with dynamic pattern switching)
3. Temporal consistency (reads should see current cycle's writes)
4. Matches hardware behavior (A12 reflects current fetch)

## Next Steps (MUST NOT SKIP)

1. ✅ Synthesize agent findings (this document)
2. ⏳ **Verify pattern table switching hypothesis**
   - Check if ANY NES games switch PPUCTRL.bg_pattern mid-frame
   - Research nesdev forums for MMC3 IRQ usage patterns
3. ⏳ **Analyze SMB3 ROM IRQ setup code**
   - Why is latch set to $C1?
   - When is reload written?
   - When is IRQ enabled?
4. ⏳ **Test execution order fix in isolation**
   - Move A12 detection after background fetch
   - Run test and observe edge count changes
   - Does it break anything or just change edge timing?
5. ⏳ **Decision point: Fix execution order or accept current behavior?**

## Blocked On

- [ ] Pattern table switching research
- [ ] SMB3 ROM analysis (IRQ setup code)
- [ ] Test of execution order fix
- [ ] Consensus on whether 1 edge/scanline is sufficient

**NO CODE CHANGES UNTIL CONSENSUS REACHED.**

---

**Status:** Synthesis complete, awaiting further investigation
**Updated:** 2025-10-18
