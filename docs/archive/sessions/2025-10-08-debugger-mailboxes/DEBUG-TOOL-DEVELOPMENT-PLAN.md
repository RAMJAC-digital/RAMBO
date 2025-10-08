# Debug Tool Development Plan - Commercial ROM Investigation

**Date:** 2025-10-08
**Status:** 🔍 **PLANNING**
**Estimated Time:** 8-12 hours
**Priority:** P0 - Blocking commercial game playability

---

## Problem Statement

Commercial ROMs (Mario 1, Donkey Kong, BurgerTime) are not running despite:
- ✅ NMI interrupt implementation complete (928/935 tests passing)
- ✅ Interrupt mechanism proven correct via integration tests
- ✅ PPU warm-up period implemented
- ✅ Controller input wired

**Symptoms:**
- PC stuck in vector table area ($fff7, $fffe, $fffa)
- Rendering never enabled (PPUMASK=$00)
- NMI count = 0 (NMI never executes)

**Root Cause:** Unknown - requires systematic debugging

---

## Solution: Interactive Debug CLI

### Infrastructure Available

**1. Debugger Module** (`src/debugger/Debugger.zig`)
- ✅ 62/62 tests passing
- Breakpoints (execute, read, write, access)
- Watchpoints (memory change tracking)
- Step execution (instruction, scanline, frame)
- State inspection and manipulation
- User callbacks (RT-safe)
- Execution history (snapshot-based)

**2. zli Framework** (v4.1.1)
- CLI command organization
- Type-safe flag parsing
- Auto-generated help
- Spinners for progress
- Multi-step processes

**3. Snapshot System**
- Full state serialization
- Time-travel debugging capability
- History buffer support

---

## Architecture

### Debug CLI Tool: `rambo-debug`

```
rambo-debug [ROM] [COMMAND] [FLAGS]

Commands:
  run          Run emulation with breakpoints
  step         Step through execution
  inspect      Inspect emulation state
  trace        Generate execution trace
  analyze      Analyze ROM behavior

Flags:
  --cycles N      Run for N CPU cycles
  --frames N      Run for N frames
  --break ADDR    Set breakpoint at address
  --watch ADDR    Watch memory address
  --output FILE   Output trace to file
  --verbose       Verbose logging
```

### Integration Points

```
┌─────────────────┐
│   rambo-debug   │ (zli CLI)
│    (main)       │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│    Debugger     │ (Debugger.zig)
│   (wrapper)     │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ EmulationState  │ (State.zig)
│  (core logic)   │
└─────────────────┘
```

---

## Implementation Phases

### Phase 1: Debug CLI Skeleton (2-3 hours)

**Objective:** Create `src/debug_cli.zig` with zli integration

**Tasks:**
1. Create `src/debug_cli.zig` with zli command structure
2. Add `debug_cli` executable to `build.zig`
3. Implement basic commands:
   - `run` - Run emulation
   - `inspect` - Print state
   - `help` - Auto-generated help

**Files:**
- NEW: `src/debug_cli.zig` (~200 lines)
- UPDATE: `build.zig` - Add debug_cli executable

**Example Code:**
```zig
const std = @import("std");
const zli = @import("zli");
const RAMBO = @import("RAMBO");

const DebugCli = struct {
    config: *RAMBO.Config.Config,
    emu_state: *RAMBO.EmulationState.EmulationState,
    debugger: RAMBO.Debugger.Debugger,

    pub fn init(allocator: std.mem.Allocator) !DebugCli {
        var config = try allocator.create(RAMBO.Config.Config);
        config.* = RAMBO.Config.Config.init(allocator);
        // ... initialization
    }
};

pub fn main() !void {
    const app = zli.App{
        .name = "rambo-debug",
        .version = "0.1.0",
        .description = "RAMBO NES Emulator - Interactive Debugger",
    };

    try app.addCommand(RunCommand);
    try app.addCommand(InspectCommand);
    try app.run();
}
```

**Deliverable:** `rambo-debug --help` works and shows commands

---

### Phase 2: Run Command with Breakpoints (3-4 hours)

**Objective:** Implement `rambo-debug [ROM] run --cycles N --break ADDR`

**Tasks:**
1. Load ROM into EmulationState
2. Wrap with Debugger
3. Set breakpoints from CLI flags
4. Run emulation loop with debug callbacks
5. Print state when breakpoint hit

**Commands:**
```bash
# Run for 10000 cycles with breakpoint at $8000
rambo-debug mario.nes run --cycles 10000 --break 0x8000

# Run for 3 frames with breakpoint at NMI vector
rambo-debug mario.nes run --frames 3 --break 0xFFFA
```

**Output Format:**
```
RAMBO Debug CLI v0.1.0
======================
Loading ROM: mario.nes
NMI vector: $0700
Reset vector: $8004
Starting PC: $8004

Running for 10000 cycles...
[Cycle    156] Breakpoint hit at $8000
  PC=$8000  A=$00  X=$00  Y=$00  SP=$FD  P=$24 [--I---Z-]
  Scanline=0  Dot=468  Frame=0

Next instruction: LDA #$10  (A9 10)
```

**Integration with Debugger:**
```zig
// Set breakpoint
try debugger.addBreakpoint(.{
    .address = 0x8000,
    .type = .execute,
});

// Run loop
while (cycles < max_cycles) {
    // Check if should break
    if (debugger.shouldBreak(&emu_state)) {
        printState(&emu_state, &debugger);
        break;
    }

    // Execute one instruction
    emu_state.tick();
    cycles += 1;
}
```

**Deliverable:** Can run ROM and break at specific addresses

---

### Phase 3: Trace Command for Execution Analysis (2-3 hours)

**Objective:** Generate detailed execution traces for offline analysis

**Tasks:**
1. Implement `trace` command
2. Log every instruction execution
3. Track state changes (registers, PPU, memory)
4. Output to file or stdout

**Commands:**
```bash
# Trace first 1000 instructions to file
rambo-debug mario.nes trace --instructions 1000 --output mario_trace.txt

# Trace first 3 frames with memory access log
rambo-debug mario.nes trace --frames 3 --memory --output mario_init.txt
```

**Trace Format:**
```
===== Execution Trace =====
ROM: mario.nes
NMI Vector: $0700
Reset Vector: $8004
Starting PC: $8004

[Frame 0, Scanline 0, Dot 0]
  Cycle     0: PC=$8004  A=$00  X=$00  Y=$00  SP=$FD  P=$24  |  78     SEI           ; Set interrupt disable
  Cycle     2: PC=$8005  A=$00  X=$00  Y=$00  SP=$FD  P=$24  |  D8     CLD           ; Clear decimal mode
  Cycle     4: PC=$8006  A=$00  X=$00  Y=$00  SP=$FD  P=$24  |  A9 10  LDA #$10      ; Load $10
  Cycle     6: PC=$8008  A=$10  X=$00  Y=$00  SP=$FD  P=$04  |  8D 00 20  STA $2000 ; Write to PPUCTRL

[Memory Write] $2000 <- $10  (PPUCTRL: NMI enabled)
[PPU State] PPUCTRL=$10, PPUMASK=$00, warmup_complete=false

[Frame 0, Scanline 241, Dot 1]
[VBlank Started] scanline=241, nmi_enable=true, warmup=false
[NMI Check] nmi_line=false (warmup period - writes ignored)
```

**File Output:** Structured for grep/awk analysis

**Deliverable:** Can generate comprehensive execution traces

---

### Phase 4: Inspect Command for State Analysis (1-2 hours)

**Objective:** Inspect emulation state at any point

**Tasks:**
1. Print CPU state (registers, flags)
2. Print PPU state (CTRL, MASK, scroll, scanline)
3. Print memory ranges
4. Disassemble instructions

**Commands:**
```bash
# Inspect state after 10000 cycles
rambo-debug mario.nes run --cycles 10000 --inspect

# Inspect specific memory range
rambo-debug mario.nes run --cycles 10000 --inspect --memory 0x2000-0x2007

# Disassemble at PC
rambo-debug mario.nes run --cycles 10000 --disasm 20
```

**Output:**
```
===== CPU State =====
PC:  $8111
A:   $00
X:   $00
Y:   $00
SP:  $FD
P:   $24 [--I---Z-]

===== PPU State =====
CTRL:      $80 [NMI=1, Master=0, SpriteSize=0, BG=$0000, Sprite=$0000]
MASK:      $08 [Grayscale=0, ShowBG=0, ShowSprite=0, Emph=$0]
STATUS:    $00 [VBlank=0, Sprite0=0, Overflow=0]
Scanline:  15
Dot:       128
Frame:     0
Warmup:    complete=false (cycles=3000/29658)

===== Memory (PPU Registers) =====
$2000 (CTRL):   $80
$2001 (MASK):   $08
$2002 (STATUS): $00
$2003 (OAMADDR):$00
$2005 (SCROLL): $00, $00
$2006 (ADDR):   $00

===== Disassembly @ $8111 =====
$8111:  A9 10     LDA #$10
$8113:  8D 00 20  STA $2000
$8116:  A9 00     LDA #$00
```

**Deliverable:** Can inspect state comprehensively

---

### Phase 5: Step Command for Interactive Debugging (2-3 hours)

**Objective:** Interactive stepping through execution

**Tasks:**
1. Implement REPL-style interface
2. Commands: `step`, `next`, `continue`, `break`, `watch`, `print`
3. Show state after each step
4. Save/restore history

**Commands:**
```bash
# Enter interactive mode
rambo-debug mario.nes step

# Interactive REPL:
(rambo-debug) break 0x8000
(rambo-debug) run
(rambo-debug) step      # Execute one instruction
(rambo-debug) next      # Step over subroutines
(rambo-debug) continue  # Run until next breakpoint
(rambo-debug) print a   # Print A register
(rambo-debug) watch 0x2000  # Watch PPUCTRL
```

**REPL Features:**
- Command history (readline-style)
- Tab completion
- State persistence between commands

**Deliverable:** Interactive debugging experience

---

## Investigation Strategy

### Stage 1: Understand Initialization (Priority 1)

**Goal:** Determine why games don't enable rendering

**Approach:**
```bash
# 1. Trace Mario 1 initialization
rambo-debug mario.nes trace --cycles 30000 --output mario_init.txt

# 2. Search for PPUMASK writes
grep "STA \$2001" mario_init.txt

# 3. Check warmup period behavior
grep "warmup" mario_init.txt

# 4. Verify NMI execution
grep "NMI" mario_init.txt
```

**Questions to Answer:**
- When does Mario write to PPUMASK?
- Is warmup period preventing register writes?
- Are writes being ignored?
- Does PC ever jump to NMI vector?

---

### Stage 2: Compare Against Working Emulator (Priority 2)

**Goal:** Identify divergence point from correct behavior

**Approach:**
1. Generate trace from known-working emulator (e.g., FCEUX with Lua scripting)
2. Generate trace from RAMBO
3. Compare line-by-line until divergence

**Tools:**
- FCEUX Lua script to log every instruction
- `diff` to find divergence point
- Binary search to narrow down issue

---

### Stage 3: Deep Dive at Divergence (Priority 3)

**Goal:** Fix root cause

**Approach:**
```bash
# Set breakpoint at divergence point
rambo-debug mario.nes run --break 0x<divergence_pc>

# Inspect state
rambo-debug mario.nes run --cycles <divergence_cycle> --inspect

# Step through problematic section
rambo-debug mario.nes step
(rambo-debug) break 0x<divergence_pc>
(rambo-debug) run
(rambo-debug) step 10  # Step through 10 instructions
```

**Fix and Verify:**
1. Identify incorrect behavior
2. Fix implementation
3. Re-run trace
4. Verify games work

---

## Success Criteria

### Phase 1-2: Basic Debugging (Must Have)
- [ ] `rambo-debug --help` shows commands
- [ ] Can load ROM and run for N cycles
- [ ] Can set breakpoints and inspect state
- [ ] Output is readable and informative

### Phase 3-4: Analysis Tools (Must Have)
- [ ] Can generate execution traces
- [ ] Can inspect CPU/PPU state
- [ ] Can analyze memory contents
- [ ] Output suitable for offline analysis

### Phase 5: Interactive Debugging (Nice to Have)
- [ ] REPL interface works
- [ ] Can step through execution
- [ ] Can set watchpoints dynamically

### Investigation Results (Critical)
- [ ] Understand why Mario doesn't enable rendering
- [ ] Identify root cause of issue
- [ ] Fix implementation
- [ ] Mario displays title screen
- [ ] Tests still pass (no regressions)

---

## File Structure

```
src/
├── debug_cli.zig          # NEW - Main debug CLI entry point
├── debug/                 # NEW - Debug CLI commands
│   ├── run.zig           # Run command
│   ├── trace.zig         # Trace command
│   ├── inspect.zig       # Inspect command
│   ├── step.zig          # Step command (REPL)
│   └── common.zig        # Shared utilities
├── debugger/
│   └── Debugger.zig      # EXISTING - Debugger wrapper
└── ...

build.zig                  # UPDATE - Add debug_cli executable

docs/sessions/2025-10-08-nmi-interrupt-investigation/
├── DEBUG-TOOL-DEVELOPMENT-PLAN.md  # This file
└── INVESTIGATION-RESULTS.md        # NEW - Investigation findings
```

---

## Timeline

**Phase 1:** 2-3 hours (CLI skeleton)
**Phase 2:** 3-4 hours (Run command + breakpoints)
**Phase 3:** 2-3 hours (Trace generation)
**Phase 4:** 1-2 hours (Inspect command)
**Phase 5:** 2-3 hours (Interactive stepping - optional)

**Total:** 10-15 hours (8-12 without Phase 5)

**Investigation:** 2-4 hours (depends on issue complexity)

**Grand Total:** 12-16 hours to resolution

---

## Next Steps

1. **Review this plan** - Ensure approach is sound
2. **Prioritize phases** - Decide if Phase 5 is needed
3. **Begin Phase 1** - Create CLI skeleton
4. **Iterate quickly** - Get to investigation ASAP

---

**Status:** ✅ **PLAN COMPLETE - READY FOR APPROVAL**
**Next:** Begin Phase 1 implementation after review
