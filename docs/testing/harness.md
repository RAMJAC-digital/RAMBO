# Test Harness Usage Guide

These helpers sit behind `RAMBO.TestHarness.Harness` and make integration tests deterministic by staging CPU/PPU timing through the real emulator pipeline.

## Lifecycle

```zig
const RAMBO = @import("RAMBO");
const Harness = RAMBO.TestHarness.Harness;

var harness = try Harness.init();
defer harness.deinit();
```

`init()` resets the emulator with a fresh configuration; always run `deinit()` so any cartridge/ROM resources are released.

## Timing helpers

| Helper | Description |
| --- | --- |
| `setPpuTiming(scanline, dot)` | Reposition the master clock without running any components. |
| `tickPpu()` | Tick PPU only for 1 cycle (for precise PPU-only testing). |
| `tickPpuCycles(count)` | Tick PPU for `count` cycles (PPU-only, no CPU/APU). |
| `tickPpuWithFramebuffer(fb)` | Tick PPU with framebuffer rendering enabled. |
| `seekToScanlineDot(sl, dot)` | Advance emulation until reaching exact (scanline, dot) position. |
| `state.tick()` | Tick entire emulator (PPU, CPU, APU) - CPU advances at 1/3 PPU rate. |
| `getScanline()`, `getDot()` | Query current PPU timing position. |

### PPU Register Access

| Helper | Description |
| --- | --- |
| `ppuReadRegister(addr)` | Read PPU register ($2000-$2007) through PPU logic. |
| `ppuWriteRegister(addr, val)` | Write PPU register ($2000-$2007) through PPU logic. |
| `ppuReadVram(addr)`, `ppuWriteVram(addr, val)` | Direct VRAM access (bypasses CPU bus). |

### Common Patterns

**Force VBlank start:**
```zig
harness.setPpuTiming(241, 0);
harness.state.tick(); // Advances to 241.1, sets VBlank flag
```

**Force VBlank end:**
```zig
harness.setPpuTiming(261, 0);
harness.state.tick(); // Pre-render scanline, clears VBlank
```

**Prime CPU for execution:**
```zig
harness.state.cpu.pc = 0x8000;
harness.state.cpu.state = .fetch_opcode;
harness.state.cpu.pending_interrupt = .none;
```

**Check VBlank state:**
```zig
const vblank_set = harness.state.vblank_ledger.isReadableFlagSet(harness.state.clock.ppu_cycles);
```

## Typical pattern

```zig
harness.state.reset();
harness.state.ppu.warmup_complete = true;

// Prime CPU for execution at 0x8000
harness.state.cpu.pc = 0x8000;
harness.state.cpu.state = .fetch_opcode;

// Force VBlank to start
harness.setPpuTiming(241, 0);
harness.state.tick(); // Advances to 241.1, sets VBlank flag

// Check VBlank flag is visible
var saw_flag = false;
for (0..11) |_| {
    const vblank_set = harness.state.vblank_ledger.isReadableFlagSet(harness.state.clock.ppu_cycles);
    saw_flag = saw_flag or vblank_set;
    harness.tickPpu(); // PPU-only tick for precise timing
}
```

This guarantees test operations observe real PPU timing and VBlank ledger state.

## Running tests

- `zig build test` runs the full suite (unit + integration). The SMB and AccuracyCoin regressions intentionally fail until the emulator is fixed; the harness prints per-frame traces so failures are informative.
- `zig build test-integration --summary all` narrows the run to integration tests—useful when iterating on the harness.
- Individual files can be executed via `zig test path/to/test.zig` once the top-level module exports `RAMBO`.

When a test fails, inspect the structured output. For example, the SMB regression harness now prints per-frame `PPUCTRL`, `PPUMASK`, and ledger timestamps; the BIT timing tests emit the ledger state each micro-cycle.
