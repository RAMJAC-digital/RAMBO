# Debugger Quick Start Guide

**Status:** ✅ Working (Fixed 2025-10-09, commit f5d4d8c)

---

## Command-Line Debugger Usage

### Basic Flags

```bash
./zig-out/bin/RAMBO <rom-file> [flags]
```

| Flag | Shortcut | Description | Example |
|------|----------|-------------|---------|
| `--break-at` | `-b` | Execute breakpoints (hex) | `--break-at 0x8000` |
| `--watch` | `-w` | Memory watchpoints (hex) | `--watch 0x2001` |
| `--inspect` | `-i` | Print CPU state on break | `--inspect` |
| `--trace` | `-t` | Enable execution tracing | `--trace` |
| `--verbose` | `-v` | Verbose debug output | `--verbose` |

---

## Common Use Cases

### 1. Break at Reset Vector

```bash
./zig-out/bin/RAMBO "rom.nes" --break-at 0x8000 --inspect
```

**Output:**
```
=== BREAKPOINT HIT ===
Reason: Breakpoint at $8000 (hit count: 1)

=== CPU Snapshot ===
  PC: $8000  A: $00  X: $00  Y: $00
  SP: $FD   P: $24  [-----I--]
  Cycle: 1  Frame: 0
====================
```

**Use case:** Verify ROM starts at correct address

---

### 2. Watch PPU Register Writes

```bash
# Watch PPUMASK writes
./zig-out/bin/RAMBO "rom.nes" --watch 0x2001 --inspect

# Watch multiple PPU registers
./zig-out/bin/RAMBO "rom.nes" --watch 0x2000,0x2001,0x2002 --inspect
```

**Output:**
```
=== WATCHPOINT HIT ===
Reason: Write to $2001 (value: $1E)

=== CPU Snapshot ===
  PC: $C123  A: $1E  X: $00  Y: $00
  SP: $FF   P: $24  [-----I--]
  Cycle: 5432  Frame: 1
====================
```

**Use case:** Debug rendering issues (when does game enable rendering?)

---

### 3. Multiple Breakpoints

```bash
./zig-out/bin/RAMBO "rom.nes" \
  --break-at 0x8000,0xC000,0xFFFA \
  --inspect
```

**Use case:** Track execution through multiple code paths

---

### 4. Trace NMI Handler

```bash
# Break at NMI vector location
./zig-out/bin/RAMBO "rom.nes" --break-at 0xFFFA --inspect
```

**Advanced:** Check NMI vector in ROM first:
```bash
# View NMI vector (at offset 0x7FFA in iNES ROM)
xxd rom.nes | grep "7ff0:"
```

---

## CPU Snapshot Format

```
=== CPU Snapshot ===
  PC: $8046  A: $06  X: $FF  Y: $FF
  SP: $FF   P: $25  [-----I-C]
  Cycle: 92302  Frame: 3
====================
```

**Fields:**
- **PC**: Program Counter (current instruction address)
- **A/X/Y**: Accumulator and index registers
- **SP**: Stack Pointer ($0100 + SP = stack address)
- **P**: Status flags (packed byte)
- **Flags**: `[NV--DIZC]` (N=Negative, V=Overflow, D=Decimal, I=Interrupt disable, Z=Zero, C=Carry)
- **Cycle**: Total CPU cycles executed
- **Frame**: PPU frame counter

---

## Debugging Workflow Example

### Problem: ROM displays blank screen

**Step 1: Check if rendering is enabled**
```bash
./zig-out/bin/RAMBO "rom.nes" --watch 0x2001 --inspect 2>&1 | grep "show_"
```

Look for: `show_bg: false -> true` or `show_sprites: false -> true`

**Step 2: If rendering never enables, find where game is stuck**
```bash
# Set breakpoints at key locations
./zig-out/bin/RAMBO "rom.nes" \
  --break-at 0x8000,0x8100,0x8200,0x8300 \
  --inspect
```

Check which breakpoints are hit repeatedly (indicates loop)

**Step 3: Compare with working ROM**
```bash
# Run both and compare PPUMASK writes
./zig-out/bin/RAMBO "broken.nes" --watch 0x2001 > broken.log
./zig-out/bin/RAMBO "working.nes" --watch 0x2001 > working.log
diff broken.log working.log
```

---

## Real Example: Super Mario Bros Investigation

### Symptom
Blank screen, no rendering

### Investigation
```bash
timeout 3 ./zig-out/bin/RAMBO "Super Mario Bros. (World).nes" \
  --watch 0x2001 --inspect 2>&1 | grep PPUMASK
```

### Results
**Super Mario Bros (broken):**
```
[PPUMASK] Write 0x06, show_bg: false -> false, show_sprites: false -> false
[PPUMASK] Write 0x00, show_bg: false -> false, show_sprites: false -> false
[PPUMASK] Write 0x00, show_bg: false -> false, show_sprites: false -> false
# Never writes 0x1E!
```

**Mario Bros (working):**
```
[PPUMASK] Write 0x00, show_bg: false -> false, show_sprites: false -> false
[PPUMASK] Write 0x06, show_bg: false -> false, show_sprites: false -> false
[PPUMASK] Write 0x1E, show_bg: false -> true, show_sprites: false -> true
# Writes 0x1E - rendering enabled!
```

### Conclusion
SMB gets stuck in initialization loop before writing PPUMASK=0x1E. Next step: Find loop location.

---

## Limitations & Known Issues

### Execution Pauses at Breakpoints

**Current behavior:** When breakpoint/watchpoint hits, execution pauses indefinitely

**Workaround:** Use watchpoints instead of breakpoints for observation without pausing

**Future enhancement:** Add `--continue-on-break` flag for non-interactive debugging

### Multiple Watchpoint Hits

**Issue:** Watchpoint triggers can flood output if address written frequently

**Workaround:** Use `timeout` and `grep` to filter output:
```bash
timeout 5 ./zig-out/bin/RAMBO "rom.nes" --watch 0x2001 --inspect 2>&1 | \
  grep -A10 "WATCHPOINT" | head -50
```

### No Interactive Stepping

**Current:** CLI debugger is non-interactive (outputs events, then exits or times out)

**Future:** Interactive REPL with commands:
- `continue` - Resume execution
- `step` - Step one instruction
- `step 100` - Step N instructions
- `break $C000` - Add breakpoint dynamically

---

## Tips & Tricks

### 1. Find Reset Vector

```bash
# Check iNES header + 0x7FFC/0x7FFD for reset vector
xxd rom.nes | grep "7ff0:"
```

Example output:
```
00007ff0: ... ... ... ... AA BB CC DD  # Reset vector at $DDCC
```

Then break at that address:
```bash
./zig-out/bin/RAMBO "rom.nes" --break-at 0xDDCC --inspect
```

### 2. Trace First N Instructions

```bash
# Break at reset + watch key registers
./zig-out/bin/RAMBO "rom.nes" \
  --break-at 0x8000 \
  --watch 0x2000,0x2001 \
  --inspect
```

### 3. Filter Noise

```bash
# Only show watchpoint hits
timeout 10 ./zig-out/bin/RAMBO "rom.nes" --watch 0x2001 2>&1 | \
  grep -E "(WATCHPOINT|PC:|show_)"
```

### 4. Compare Two ROMs

```bash
# Create comparison logs
timeout 5 ./zig-out/bin/RAMBO "rom1.nes" --watch 0x2001 2>&1 > rom1.log
timeout 5 ./zig-out/bin/RAMBO "rom2.nes" --watch 0x2001 2>&1 > rom2.log

# Side-by-side comparison
diff -y rom1.log rom2.log | less
```

---

## Next Steps

See full debugger API documentation: `docs/api-reference/debugger-api.md`

For SMB investigation: `docs/sessions/smb-investigation-plan.md`
