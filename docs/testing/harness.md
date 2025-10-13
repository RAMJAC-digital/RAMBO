# Test Harness Usage Guide

These helpers sit behind `RAMBO.TestHarness.Harness` and make integration tests deterministic by staging CPU/PPU timing through the real emulator pipeline (no stubs, no hidden side effects).

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
| `seekTo(sl, dot)` | Advance emulation until reaching exact (scanline, dot) position. |
| `runCpuCycles(n)` | Advance CPU by `n` cycles (and the PPU/APU accordingly). |
| `state.tick()` | Tick entire emulator (PPU, CPU, APU) - CPU advances at 1/3 PPU rate. |
| `getScanline()`, `getDot()` | Query current PPU timing position. |

### PPU Register Access (via bus)

| Helper | Description |
| --- | --- |
| `state.busRead(addr)` | Read PPU register ($2000-$2007) through the bus (or RAM/ROM/etc.). |
| `state.busWrite(addr, val)` | Write PPU register ($2000-$2007) through the bus. |
| `ppuReadVram(addr)`, `ppuWriteVram(addr, val)` | Direct VRAM access (bypasses CPU bus). |

Notes:
- `$2002` (PPUSTATUS) reads have side effects (e.g., VBlank clear-on-read) and are modeled in `EmulationState.busRead`.
- `$2001` (PPUMASK) is write‑only; read back the value from `@bitCast(state.ppu.mask)` if needed.

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
const status = harness.state.busRead(0x2002);
const vblank_set = (status & 0x80) != 0;
```

## Typical pattern (with race semantics)

```zig
harness.state.reset();
harness.state.ppu.warmup_complete = true;

// Align BIT $2002 memory read to 241.1 (VBlank set)
harness.seekTo(240, 330);
harness.loadRam(&[_]u8{ 0x2C, 0x02, 0x20 }, 0x0000);
harness.state.cpu.pc = 0x0000;
harness.state.cpu.state = .fetch_opcode;
harness.runCpuCycles(4); // BIT abs: 4 cycles → memory read at 241.1

// Post‑condition: N flag (bit 7) reflects VBlank
try std.testing.expect(harness.state.cpu.p.negative);

// Race‑hold semantics: subsequent $2002 reads within the same VBlank still report VBlank set.
try std.testing.expect((harness.state.busRead(0x2002) & 0x80) != 0);
```

This guarantees test operations observe real PPU timing and VBlank ledger state.

## Running tests

- `zig build test` runs the full suite (unit + integration). The SMB and AccuracyCoin regressions intentionally fail until the emulator is fixed; the harness prints per-frame traces so failures are informative.
- `zig build test-integration --summary all` narrows the run to integration tests—useful when iterating on the harness.
- Individual files can be executed via `zig test path/to/test.zig` once the top-level module exports `RAMBO`.

When a test fails, inspect the structured output. For example, the SMB regression harness now prints per-frame `PPUCTRL`, `PPUMASK`, and ledger timestamps; the BIT timing tests emit timing alignment steps.
