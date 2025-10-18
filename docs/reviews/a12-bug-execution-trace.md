# A12 Edge Detection Bug - Detailed Execution Trace

**Purpose:** Cycle-accurate trace of PPU execution showing exactly when chr_address is read vs. written

---

## Scanline 1, Dots 1-10 - Background Tile 0 Fetch

### Initial State (Dot 0 - End of Previous Scanline)
```
state.chr_address = 0x0000 (reset or last sprite fetch from dot 320)
state.a12_state = false (A12 low)
state.a12_filter_delay = 8 (A12 was low for full filter period)
```

---

### Dot 1 - Nametable Fetch (Cycle 0 in tile)

**Logic.zig tick() execution:**

```
1. Lines 236-268: A12 Edge Detection
   - is_rendering_line = true ✓
   - rendering_enabled = true ✓
   - is_background_fetch = (1 >= 1 and 1 <= 256) = true ✓
   - is_fetch_cycle = true ✓
   - current_a12 = (0x0000 & 0x1000) != 0 = false
   - rising_condition = (!false and false and 8 >= 6) = false
   - Filter update: current_a12 = false, so delay++ → 8 (capped)
   - state.a12_state = false
   - A12 edge: NO

2. Lines 270-301: Background Pipeline
   - (dot >= 1 and dot <= 256) = true ✓
   - fetchBackgroundTile(state, cart, 1)
     - cycle_in_tile = (1 - 1) % 8 = 0
     - Case 0: Reload shift registers
       - Skip: dot == 1 (guard condition)
   - NO chr_address update

3. Lines 305+: Sprite Evaluation
   - Not relevant for dots 1-256
```

**Result:**
```
chr_address: 0x0000 (unchanged)
a12_state: false
A12 edge detected: NO
```

---

### Dot 2 - Nametable Fetch Complete (Cycle 1 in tile)

**Logic.zig tick() execution:**

```
1. Lines 236-268: A12 Edge Detection
   - current_a12 = (0x0000 & 0x1000) != 0 = false
   - rising_condition = false
   - Filter update: delay++ → 8 (capped)
   - A12 edge: NO

2. Lines 270-301: Background Pipeline
   - fetchBackgroundTile(state, cart, 2)
     - cycle_in_tile = (2 - 1) % 8 = 1
     - Case 1: Nametable fetch
       - nt_addr = 0x2000 | (v & 0x0FFF) = 0x2000 (tile 0,0)
       - nametable_latch = readVram(state, cart, 0x2000)
   - NO chr_address update (nametable is VRAM, not CHR)
```

**Result:**
```
chr_address: 0x0000 (unchanged - nametable fetch doesn't use CHR bus)
a12_state: false
A12 edge detected: NO
```

---

### Dot 3 - Idle (Cycle 2 in tile)

**Logic.zig tick() execution:**

```
1. A12 Detection: current_a12 = false, NO edge
2. Background: cycle_in_tile = 2 → else (idle)
3. NO chr_address update
```

**Result:**
```
chr_address: 0x0000 (unchanged)
a12_state: false
A12 edge: NO
```

---

### Dot 4 - Attribute Fetch Complete (Cycle 3 in tile)

**Logic.zig tick() execution:**

```
1. A12 Detection: current_a12 = false, NO edge
2. Background:
   - cycle_in_tile = 3
   - Case 3: Attribute fetch
     - attr_addr = 0x23C0 (attribute table)
     - attr_byte = readVram(state, cart, 0x23C0)
3. NO chr_address update (attribute is VRAM, not CHR)
```

**Result:**
```
chr_address: 0x0000 (unchanged - attribute fetch doesn't use CHR bus)
a12_state: false
A12 edge: NO
```

---

### Dot 5 - Idle (Cycle 4 in tile)

**Logic.zig tick() execution:**

```
1. A12 Detection: current_a12 = false, NO edge
2. Background: cycle_in_tile = 4 → else (idle)
3. NO chr_address update
```

**Result:**
```
chr_address: 0x0000 (unchanged)
a12_state: false
A12 edge: NO
```

---

### Dot 6 - Pattern Low Fetch (Cycle 5 in tile) **← THE BUG**

**Logic.zig tick() execution:**

```
1. Lines 236-268: A12 Edge Detection
   ┌──────────────────────────────────────────────────────────┐
   │ current_a12 = (state.chr_address & 0x1000) != 0          │
   │             = (0x0000 & 0x1000) != 0                     │
   │             = false                                      │
   │                                                          │
   │ ← READS STALE chr_address (still 0x0000 from dot 0)!    │
   └──────────────────────────────────────────────────────────┘
   - rising_condition = (!false and false and 8 >= 6) = false
   - Filter update: delay++ → 8 (capped)
   - state.a12_state = false
   - A12 edge: NO ❌ (SHOULD BE YES!)

2. Lines 270-301: Background Pipeline
   - fetchBackgroundTile(state, cart, 6)
     - cycle_in_tile = (6 - 1) % 8 = 5
     - Case 5: Pattern low fetch
       ┌────────────────────────────────────────────────────┐
       │ pattern_addr = getPatternAddress(state, false)    │
       │              = 0x1000 (pattern table 1, tile 0)   │
       │                                                   │
       │ state.chr_address = 0x1000  ← WRITTEN TOO LATE!  │
       │                                                   │
       │ ← A12 detection already ran with old value!      │
       └────────────────────────────────────────────────────┘
       - pattern_latch_lo = readVram(state, cart, 0x1000)
```

**Result:**
```
chr_address: 0x1000 (UPDATED - but A12 detection missed it!)
a12_state: false (WRONG - should be true!)
A12 edge: NO ❌ (SHOULD BE YES - 0→1 transition!)
```

**HARDWARE BEHAVIOR (for comparison):**
```
Hardware Dot 6:
1. Address Setup: CHR bus = 0x1000 (IMMEDIATE)
2. A12 Line: bit 12 = 1 (IMMEDIATE - combinational logic)
3. MMC3 Filter: Sees 0→1 transition, delay >= 6 → RISING EDGE ✓
4. Memory Read: CHR ROM returns pattern data
```

**SOFTWARE BUG:**
```
chr_address was 0x0000 when A12 detection read it
chr_address became 0x1000 AFTER A12 detection finished
Result: A12 edge MISSED
```

---

### Dot 7 - Idle (Cycle 6 in tile)

**Logic.zig tick() execution:**

```
1. Lines 236-268: A12 Edge Detection
   - current_a12 = (0x1000 & 0x1000) != 0 = true
   ┌──────────────────────────────────────────────────────────┐
   │ ← NOW sees chr_address from dot 6, but ONE DOT LATE!    │
   └──────────────────────────────────────────────────────────┘
   - rising_condition = (!false and true and ...)
     Wait, state.a12_state is still false from dot 6!
     rising_condition = (!false and true and 0 >= 6) = false
   - Filter update: current_a12 = true, so delay = 0 (RESET)
   - state.a12_state = true
   - A12 edge: NO (filter delay reset to 0, needs 6+ cycles)

2. Background: cycle_in_tile = 6 → else (idle)
   - NO chr_address update
```

**Result:**
```
chr_address: 0x1000 (unchanged)
a12_state: true (now updated, but edge already missed)
a12_filter_delay: 0 (reset because A12 went high)
A12 edge: NO (missed the 0→1 transition at dot 6)
```

**NOTE:** Filter was reset because A12 is now high. The rising edge detection requires:
- A12 was low for 6+ cycles (filter_delay >= 6) ✓
- A12 goes high (current_a12 = true) ✓
- a12_state was low (!a12_state) ✓ (dot 6 state)

**But at dot 7:**
- a12_state is now true (updated at dot 6)
- Filter delay reset to 0 (A12 high)
- Next edge won't trigger until A12 goes low for 6 cycles, then high again

---

### Dot 8 - Pattern High Fetch (Cycle 7 in tile)

**Logic.zig tick() execution:**

```
1. A12 Detection:
   - current_a12 = (0x1000 & 0x1000) != 0 = true (still high)
   - rising_condition = (!true and true and 0 >= 6) = false
   - Filter update: delay = 0 (still high, no change)
   - A12 edge: NO

2. Background Pipeline:
   - cycle_in_tile = 7
   - Case 7: Pattern high fetch
     - pattern_addr = getPatternAddress(state, true)
                    = 0x1008 (pattern table 1, tile 0, plane 1)
     - state.chr_address = 0x1008
     - pattern_latch_hi = readVram(state, cart, 0x1008)
```

**Result:**
```
chr_address: 0x1008 (pattern high plane address)
a12_state: true (A12 still high)
A12 edge: NO (A12 remained high, no transition)
```

**NOTE:** No edge expected here - A12 remained 1 (both 0x1000 and 0x1008 have bit 12 set).

---

### Dot 9 - Reload Shift Registers (Cycle 0 in tile)

**Logic.zig tick() execution:**

```
1. A12 Detection:
   - current_a12 = (0x1008 & 0x1000) != 0 = true
   - A12 edge: NO (still high)

2. Background:
   - cycle_in_tile = 0
   - Case 0: Reload
     - loadShiftRegisters()
     - incrementScrollX()
   - NO chr_address update
```

**Result:**
```
chr_address: 0x1008 (unchanged)
a12_state: true
A12 edge: NO
```

---

### Dot 10 - Nametable Fetch for Tile 1 (Cycle 1 in next tile)

**Logic.zig tick() execution:**

```
1. A12 Detection:
   - current_a12 = (0x1008 & 0x1000) != 0 = true
   - A12 edge: NO

2. Background:
   - cycle_in_tile = 1
   - Case 1: Nametable fetch
     - nt_addr = 0x2001 (tile 1,0 after incrementScrollX)
   - NO chr_address update (nametable is VRAM)
```

**Result:**
```
chr_address: 0x1008 (unchanged - nametable uses VRAM, not CHR)
a12_state: true
A12 edge: NO
```

---

## Summary of Dots 1-10

### chr_address Timeline

```
Dot | Phase              | chr_address | A12 Read | A12 Write | Edge? | Expected?
────┼────────────────────┼─────────────┼──────────┼───────────┼───────┼──────────
 0  | (previous scanline)| 0x0000      | -        | -         | -     | -
 1  | Nametable setup    | 0x0000      | 0x0000   | -         | NO    | NO
 2  | Nametable fetch    | 0x0000      | 0x0000   | -         | NO    | NO
 3  | Idle               | 0x0000      | 0x0000   | -         | NO    | NO
 4  | Attribute fetch    | 0x0000      | 0x0000   | -         | NO    | NO
 5  | Idle               | 0x0000      | 0x0000   | -         | NO    | NO
 6  | Pattern low fetch  | 0x0000→1000 | 0x0000❌ | 0x1000    | NO❌  | YES✓ (0→1)
 7  | Idle               | 0x1000      | 0x1000   | -         | NO    | NO
 8  | Pattern high fetch | 0x1000→1008 | 0x1000   | 0x1008    | NO    | NO
 9  | Reload             | 0x1008      | 0x1008   | -         | NO    | NO
10  | Nametable (tile 1) | 0x1008      | 0x1008   | -         | NO    | NO
```

**Legend:**
- `A12 Read`: Value of chr_address when A12 detection reads it
- `A12 Write`: Value written to chr_address by background fetch
- `Edge?`: Did A12 detection trigger a rising edge?
- `Expected?`: Should an edge have been detected?

**THE BUG IS VISIBLE AT DOT 6:**
- A12 detection reads chr_address = 0x0000 (A12 = 0)
- Background fetch writes chr_address = 0x1000 (A12 = 1) **AFTER** A12 detection
- Expected: 0→1 edge detected ✓
- Actual: NO edge detected ❌

---

## Pattern Continues for Remaining Tiles

### Dots 14, 22, 30, 38... (Every 8 dots)

Each tile fetch follows the same pattern:

```
Dot 14 (Tile 1 pattern low):
  A12 reads: 0x1008 (from dot 10 nametable fetch, A12=1)
  Background writes: 0x1018 (tile 1 pattern, A12=1)
  Expected edge: NO (1→1, no transition)
  Actual edge: NO ✓

Dot 22 (Tile 2 pattern low):
  A12 reads: 0x1018 (A12=1)
  Background writes: 0x1028 (A12=1)
  Expected edge: NO
  Actual edge: NO ✓
```

**All remaining background fetches stay in pattern table 1 (A12=1), so no more 0→1 edges expected.**

**However, if background switched pattern tables mid-scanline:**
```
Hypothetical Dot 54 (if PPUCTRL.4 changed to use table 0):
  A12 reads: chr_address from dot 53 (old table, A12=1)
  Background writes: 0x0xxx (new table, A12=0)
  Expected edge: NO (1→0 is falling, not rising)

Hypothetical Dot 62 (if switched back to table 1):
  A12 reads: 0x0xxx from dot 61 (A12=0)
  Background writes: 0x1xxx (A12=1)
  Expected edge: YES (0→1 rising edge)
  Actual edge: NO ❌ (SAME BUG - read before write!)
```

---

## Sprite Fetch Behavior (Why Sprites Work)

### Dot 257 - First Sprite Fetch

**Logic.zig tick() execution:**

```
1. A12 Detection:
   - current_a12 = (chr_address & 0x1000)
                 = (0x1xxx & 0x1000) = true (from dot 256 background)
   - A12 edge: Depends on previous state

2. Background Pipeline:
   - NOT executed (dot > 256)

3. Sprite Evaluation (lines 305+):
   - fetchSprites(state, cart, scanline, 257)
     - fetch_cycle = (257 - 257) = 0
     - Loads sprite data from secondary OAM
     - May write chr_address if sprite 0 exists
     - Example: state.chr_address = 0x0080 (sprite pattern)
   ┌────────────────────────────────────────────────────────┐
   │ ← chr_address written LAST in tick()                  │
   │ ← Becomes visible to NEXT dot's A12 detection         │
   └────────────────────────────────────────────────────────┘
```

### Dot 258 - Second Sprite Fetch

**Logic.zig tick() execution:**

```
1. A12 Detection:
   ┌────────────────────────────────────────────────────────┐
   │ current_a12 = (state.chr_address & 0x1000)            │
   │             = (0x0080 & 0x1000) = false               │
   │                                                       │
   │ ← Reads chr_address from dot 257 sprite eval ✓       │
   └────────────────────────────────────────────────────────┘
   - Previous state: a12_state = true (from background)
   - rising_condition = (!true and false and ...) = false
   - BUT: A12 went 1→0 (falling edge, not rising)
   - state.a12_state = false
   - Filter update: delay++ (A12 now low)
   - A12 edge: NO (falling edge, not rising)

2. Sprite Evaluation:
   - fetchSprites() continues
   - May write new chr_address
```

**NOTE:** First sprite fetch (dot 258) shows A12 detection correctly reading sprite's chr_address from dot 257. This proves the one-cycle delay is consistent, and if sprite uses pattern table 1 while background used table 0, a rising edge WOULD be detected.

---

## Conclusion

**Root Cause Demonstrated:**

At **Dot 6** (and every pattern fetch dot):
1. A12 detection **reads** chr_address (old value)
2. Background fetch **writes** chr_address (new value)
3. Edge detection uses **old value** (MISSED!)

**One-cycle delay:** A12 detection always sees chr_address from the PREVIOUS dot.

**Why sprites work:** Sprite evaluation is LAST in tick(), so sprite's chr_address write becomes visible on the NEXT dot's A12 detection (consistent one-cycle delay).

**Fix:** Move A12 detection AFTER background/sprite pipelines so it reads chr_address AFTER the current dot's fetch writes it.

---

## Files Referenced

- `/home/colin/Development/RAMBO/src/ppu/Logic.zig` (tick() function)
- `/home/colin/Development/RAMBO/src/ppu/logic/background.zig` (fetchBackgroundTile())
- `/home/colin/Development/RAMBO/src/ppu/logic/sprites.zig` (fetchSprites())
