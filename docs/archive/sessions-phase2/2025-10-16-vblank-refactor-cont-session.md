# VBlank Refactor - Test Suite Remediation — 2025-10-16

## Objective
To complete the VBlank logic refactoring by repairing the test suite to validate the new, simplified architecture and fix the Super Mario Bros. rendering bug.

## Work Completed (Core Refactor)

The primary architectural goals of the refactoring are complete:

1.  **`VBlankLedger.zig` is now a pure data struct**, containing only timestamps for `last_set_cycle`, `last_clear_cycle`, and `last_read_cycle`.
2.  **`ppu/logic/registers.zig` is now stateless.** The `readRegister` function is a pure consumer of the `VBlankLedger` state and signals `$2002` reads upwards via a return value.
3.  **`emulation/State.zig` is the single orchestrator.** It is now solely responsible for mutating the `VBlankLedger` based on events from the PPU and CPU, creating a clear, deterministic data flow.
4.  Several key test files were rewritten to align with this new architecture.

## Current Roadblock: Failing Test Suite

The architectural changes have broken the test suite, which is preventing final verification. The build is currently failing with numerous compilation errors and panics originating from the test files.

**Root Causes:**

1.  **Test Harness Instability:** There are inconsistent methods for importing and using the test harness (`src/test/Harness.zig`) across the test suite, leading to compilation errors.
2.  **Missing Test Helpers:** The rewritten tests rely on new helper functions like `seekTo` and `loadRam`, which are not universally available or correctly implemented for all test cases.
3.  **Invalid Memory Access:** At least one test (`bit_ppustatus_test.zig`) panics because it attempts to load test code into an invalid memory address (`0x8000`), which is outside the CPU RAM allocated by the harness.
4.  **Legacy API Usage:** Many test files have not yet been updated and still call the old, now-removed functions from the previous `VBlankLedger` implementation (e.g., `isReadableFlagSet`, `recordVBlankSet`).

## Path Forward

To resolve this, the following methodical steps will be taken:

1.  **Stabilize Test Harness:**
    *   **Action:** Review `build.zig` and `src/test/Harness.zig`.
    *   **Goal:** Establish a single, canonical way to import and use the harness. Add or fix helper functions (`seekTo`, `loadRam`, `runCpuCycles`) to be robust and available to all tests.

2.  **Fix Invalid Memory Access:**
    *   **Action:** Modify the test harness to correctly handle loading test code into a simulated PRG ROM region, or adjust the affected tests to load code into valid RAM addresses (e.g., `$0000`).

3.  **Systematically Update Failing Tests:**
    *   **Action:** Work through the remaining list of failing test files from the `zig build test` output.
    *   **Goal:** For each file, remove all calls to the old VBlank API and rewrite the tests to use the new harness and validation methods (i.e., calling `busRead(0x2002)` and checking the result).

4.  **Final Verification:**
    *   **Action:** Run `zig build test --summary all`.
    *   **Goal:** Achieve a clean compile and a passing test suite, which will validate the VBlank refactor and confirm the fix for the SMB bug.

---

## 2025‑10‑16 — Follow‑up (Race‑Hold + Harness Unification)

### What changed

- Added `race_hold` to `VBlankLedger` and wired it across `EmulationState.busRead()` and PPUSTATUS logic so the 241.1 race behaves like hardware.
- All `$2002` reads route through bus; destructive side effects and race‑hold are applied centrally (PPU logic remains pure).
- Test harness unified: `runCpuCycles()` advances CPU/PPU/APU; PPU registers are accessed via bus; `$4015` read no longer updates CPU open bus.

### Current status (tests)

- VBlank/PPU/NMI tests are green with race‑hold semantics.
- Commercial ROM tests still fail render‑enable checks (expected per current issue tracker).
- Threading tests occasionally fail due to a debugger callback GPF during frame loops; infra work needed (guard or disable callbacks in those tests).

### Remaining conversions to RAMBO harness

- `tests/bus/bus_integration_test.zig` — local `TestHarness` → `RAMBO.TestHarness.Harness`
- `tests/cartridge/accuracycoin_test.zig` — local `TestHarness` → RAMBO harness
- `tests/cpu/microsteps/jmp_indirect_test.zig` — local harness → RAMBO harness

### Guidance: converting to the RAMBO harness

Import & lifecycle:
```zig
const RAMBO = @import("RAMBO");
const Harness = RAMBO.TestHarness.Harness;
var h = try Harness.init();
defer h.deinit();
```

Timing & alignment:
```zig
h.seekTo(241, 1);                          // exact VBlank set
h.state.cpu.state = .fetch_opcode;
h.state.cpu.instruction_cycle = 0;
h.runCpuCycles(4);                          // advance one 4‑cycle instruction
```

PPU registers via bus:
```zig
const status = h.state.busRead(0x2002);     // PPUSTATUS
h.state.busWrite(0x2000, 0x80);             // PPUCTRL
```

RAM writes & vectors:
```zig
h.loadRam(&[_]u8{ 0x4C, 0x00, 0xC0 }, 0x0000); // JMP $C000 at $0000
if (h.state.bus.test_ram == null) {
    const tr = try std.testing.allocator.alloc(u8, 0x8000);
    @memset(tr, 0xEA);
    h.state.bus.test_ram = tr;
    tr[0x7FFA] = 0x00; tr[0x7FFB] = 0xC0;       // $FFFA/$FFFB
}
```

Race‑hold semantics:
```zig
// 241.1: first read sees VBlank set
try std.testing.expect((h.state.busRead(0x2002) & 0x80) != 0);
// Subsequent reads in the same VBlank remain set
try std.testing.expect((h.state.busRead(0x2002) & 0x80) != 0);
```

### Environment notes (Wayland/Vulkan)

- Threading tests spin up emulation and render threads. On XDG/Wayland systems without Vulkan validation layers, warnings are expected. Add a guard in `Debugger.checkMemoryAccess()` (skip null callbacks) or disable debugger hooks for the threading suite to prevent GPF during frame loops.

### Next steps

1) Convert the three remaining local harness tests to the RAMBO harness.
2) Add the debugger callback guard for threading tests.
3) Re‑run `zig build test --summary all` with ROMs under `tests/data/` to confirm baseline; proceed with the SMB render‑enable investigation on this foundation.
