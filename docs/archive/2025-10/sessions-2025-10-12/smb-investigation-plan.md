# Super Mario Bros Investigation Plan – 2025-10-09

## Current Status

**ROM:** `tests/data/Mario/Super Mario Bros. (World).nes`
**Symptom:** Blank screen, no rendering
**Root Cause:** Game never writes PPUMASK=0x1E (rendering enabled)

### What Works ✅
- VBlank SET/CLEAR timing (scanlines 241/261)
- $2002 polling (game sees VBlank=true)
- OAM DMA triggers correctly
- PPU warm-up period completes

### What's Broken ❌
- Game writes PPUMASK=0x06 (rendering disabled) instead of 0x1E
- Never progresses beyond initialization
- CPU appears stuck in loop or waiting for condition

---

## Investigation Approach (Using Built-In Debugger)

### ✅ Debugger Now Working (Fixed 2025-10-09)

**Status:** Debugger was broken (handleCpuSnapshot was no-op), now fixed in commit f5d4d8c

### Phase 1: Identify Stuck Loop

**Objective:** Find where CPU is executing during blank screen

**Working Commands:**

```bash
# Set breakpoint at reset vector
./zig-out/bin/RAMBO "tests/data/Mario/Super Mario Bros. (World).nes" \
  --break-at 0x8000 --inspect

# Expected output:
# === BREAKPOINT HIT ===
# Reason: Breakpoint at $8000 (hit count: 1)
#
# === CPU Snapshot ===
#   PC: $8000  A: $00  X: $00  Y: $00
#   SP: $FD   P: $24  [-----I--]
#   Cycle: 1  Frame: 0

# Watch PPUMASK writes
./zig-out/bin/RAMBO "tests/data/Mario/Super Mario Bros. (World).nes" \
  --watch 0x2001 --inspect

# Watch multiple addresses (PPUCTRL and PPUMASK)
./zig-out/bin/RAMBO "tests/data/Mario/Super Mario Bros. (World).nes" \
  --watch 0x2000,0x2001 --inspect

# Set multiple breakpoints
./zig-out/bin/RAMBO "tests/data/Mario/Super Mario Bros. (World).nes" \
  --break-at 0x8000,0x8100,0x8200 --inspect
```

### Phase 2: Set Strategic Breakpoints

**Breakpoint Locations:**

1. **PPUMASK writes:** Break on $2001 write
   - See what values are written
   - Check call stack to identify caller
   - Determine why 0x1E is never written

2. **VBlank NMI handler:** Break on NMI vector execution
   - Verify NMI fires correctly
   - Check if handler completes or hangs
   - Compare with Mario Bros (working) NMI handler

3. **Controller polling:** Break on $4016/$4017 reads
   - Check if game waits for input
   - Send START button press via debugger

### Phase 3: Compare Working vs Broken

**Test Mario Bros vs Super Mario Bros:**

| Metric | Mario Bros (✅) | SMB (❌) |
|--------|--------------|----------|
| PC at 5s runtime | ? | ? |
| PPUMASK writes | 0x1E | 0x06 |
| NMI handler runs | ? | ? |
| Controller polled | ? | ? |

Fill in unknowns using debugger trace.

---

## Hypotheses (Prioritized)

### 1. CPU Infinite Loop (HIGH)
**Evidence:** Game never writes 0x1E despite waiting multiple frames
**Test:** Check if PC increments or loops same range
**Fix:** Identify why loop doesn't exit (missing condition, hardware state)

### 2. Missing NMI Execution (MEDIUM)
**Evidence:** VBlank sets, but NMI handler may not run
**Test:** Break on NMI vector, verify handler executes
**Fix:** Check NMI edge detection in VBlankLedger

### 3. Unimplemented Hardware Read (MEDIUM)
**Evidence:** Game may poll register expecting specific value
**Test:** Watch for reads returning unexpected open bus values
**Fix:** Implement missing register or fix return value

### 4. Waiting for Controller Input (LOW)
**Evidence:** Some games wait for START before rendering
**Test:** Send controller input via debugger mailbox
**Fix:** Not a bug—user must press START

---

## ✅ Investigation Results (2025-10-09)

### Confirmed Findings

**Super Mario Bros:**
```
[PPUMASK] Write 0x06, show_bg: false -> false, show_sprites: false -> false
[PPUMASK] Write 0x00, show_bg: false -> false, show_sprites: false -> false
[PPUMASK] Write 0x00, show_bg: false -> false, show_sprites: false -> false
# Never writes 0x1E! Rendering never enabled.
```

**Mario Bros (working):**
```
[PPUMASK] Write 0x00, show_bg: false -> false, show_sprites: false -> false
[PPUMASK] Write 0x06, show_bg: false -> false, show_sprites: false -> false
[PPUMASK] Write 0x1E, show_bg: false -> true, show_sprites: false -> true
# Writes 0x1E on third write - rendering enabled!
```

**Conclusion:** SMB initialization never progresses to the point where it writes PPUMASK=0x1E. The game is stuck in an infinite loop or waiting for an unmet condition.

---

## Debugging Workflow

### Step 1: Launch with Debugger
```bash
# Build fresh
zig build

# Run with inspector (working as of f5d4d8c)
./zig-out/bin/RAMBO "tests/data/Mario/Super Mario Bros. (World).nes" \
  --watch 0x2001 --inspect
```

### Step 2: Set Breakpoints via CLI

**Execute Breakpoints:**
```bash
# Break at specific addresses
--break-at 0x8000              # Single address
--break-at 0x8000,0x8100       # Multiple addresses (comma-separated)
```

**Memory Watchpoints:**
```bash
# Watch for writes to specific addresses
--watch 0x2001                 # Watch PPUMASK writes
--watch 0x2000,0x2001,0x2002   # Watch multiple PPU registers
```

**Inspection Flag:**
```bash
# Print CPU state when breakpoint/watchpoint hits
--inspect
```

**Combined Example:**
```bash
./zig-out/bin/RAMBO "rom.nes" \
  --break-at 0x8000,0xC000 \
  --watch 0x2001 \
  --inspect
```

### Step 3: Analyze Output

**Breakpoint Hit:**
```
=== BREAKPOINT HIT ===
Reason: Breakpoint at $8000 (hit count: 1)

=== CPU Snapshot ===
  PC: $8000  A: $00  X: $00  Y: $00
  SP: $FD   P: $24  [-----I--]
  Cycle: 1  Frame: 0
====================
```

**Watchpoint Hit:**
```
=== WATCHPOINT HIT ===
Reason: Write to $2001 (value: $06)

=== CPU Snapshot ===
  PC: $8046  A: $06  X: $FF  Y: $FF
  SP: $FF   P: $25  [-----I-C]
  Cycle: 92302  Frame: 3
====================
```

### Step 4: Identify Pattern

- Is PC looping same 5-10 instructions?
- Is PC advancing but never reaching PPUMASK write?
- Does NMI handler execute or is NMI not firing?

### Step 5: Root Cause Analysis

**If stuck in loop:**
- Identify loop condition (BNE, BEQ, BPL, BMI)
- Check what flag/register it's polling
- Determine why condition never becomes true

**If NMI not firing:**
- Check VBlankLedger.nmi_edge_pending
- Verify PPUCTRL.nmi_enable is set
- Review NMI edge detection logic

**If waiting for input:**
- Send controller state via ControllerInputMailbox
- Press START button (bit 3)

---

## Code Locations

### Debugger Integration
- `src/debugger/Debugger.zig` - Breakpoints, watchpoints, stepping
- `src/emulation/debug/integration.zig` - Debugger hooks in emulation loop
- `src/mailboxes/DebugCommandMailbox.zig` - Send commands to debugger
- `src/mailboxes/DebugEventMailbox.zig` - Receive events from debugger

### NMI Handling
- `src/emulation/State.zig:376-394` - NMI edge detection
- `src/emulation/state/VBlankLedger.zig:114-140` - shouldNmiEdge()
- `src/emulation/cpu/microsteps.zig:184-196` - pushStatusInterrupt() (recently fixed!)

### PPUMASK
- `src/ppu/logic/registers.zig:136-153` - writeRegister() $2001 handler
- `src/ppu/State.zig:85-87` - renderingEnabled() check

---

## Expected Outcome

After investigation, we should have:

1. **Exact PC location** where game is stuck
2. **Disassembly** of stuck loop (5-10 instructions)
3. **Condition** being checked (flag, memory, register)
4. **Root cause** of why condition never becomes true

Then we can determine if this is:
- ❌ Emulator bug (NMI, timing, hardware state)
- ❌ Missing hardware feature
- ✅ Game waiting for valid input (press START)

---

## Success Criteria

Investigation complete when we can answer:

1. **Where is CPU executing?** (PC address range)
2. **Why is it stuck?** (Loop condition, missing NMI, waiting for input)
3. **What needs to be fixed?** (Emulator bug vs user action required)

---

## Next Session Actions

1. Run SMB with debugger
2. Break after 5s, check PC
3. Identify stuck loop or handler
4. Compare with Mario Bros execution
5. Determine root cause
6. Implement fix or document required user action

**Do NOT add more debug logging**—use the debugger mailbox system instead.
