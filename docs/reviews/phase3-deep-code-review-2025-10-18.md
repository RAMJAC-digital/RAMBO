# RAMBO Deep Code Review — Phase 3 (2025-10-18)

Status: Active review focused on commercial ROM correctness (MMC3-heavy titles), input reliability, test coverage shape, and code cleanup. This document aggregates concrete issues, suspected root causes with file references, and a prioritized remediation plan.

## Executive Summary

- Strengths: Clear State/Logic split, strong mapper coverage (0/1/2/3/4/7), RT-safe threading, mailbox architecture, detailed PPU pipeline with progressive sprite evaluation, VBlank ledger migration, greyscale mode implemented. Test harnesses and docs are excellent.
- Highest-impact gaps discovered:
  - MMC3 scanline IRQ timing fed by an incorrect A12 source (uses `v` register bit instead of the actual CHR bus address) → split/status-bar corruption in MMC3 titles (SMB3, Kirby, Mega Man 4).
  - Input portability: key handling uses layout-dependent keycodes; SMB1 reports “no input” on some systems due to keycode/keysym mismatch.
  - A few dead/unused fields and small inconsistencies that can be cleaned up safely.

If we address the A12 source bug and normalize keyboard input, we should see a step-function jump in commercial game correctness (esp. MMC3 splits, status bars, mid-frame CHR bank effects).

---

## P0 Issues (Fix First)

### 1) MMC3 A12 Edge Source Is Incorrect (root cause for SMB3/Kirby/Mega Man 4 issues)

Symptoms observed by user:
- SMB3: Bottom-of-screen/status-bar corruption and disappearing elements
- Kirby: “Mirroring” artifacts and bottom region issues
- Mega Man 4: Vertical seams/columns and level rendering desync

Root cause hypothesis (very high confidence):
- A12 rising edge detection is derived from `state.internal.v` instead of the actual PPU address used for CHR fetches.
  - Reference: `src/ppu/Logic.zig:228` and `src/ppu/Logic.zig:243` compute `current_a12` as `(state.internal.v & 0x1000) != 0`.
  - The real MMC3 observes PPU A12 on the CHR address bus ($0000–$1FFF) during pattern fetches (background and sprites). It does not come from the VRAM address register `v`. Using `v` misses the per-tile toggling that happens in the pattern address space and will under/over-count edges, breaking the scanline counter.

Why this explains the screenshots:
- MMC3 splits rely on IRQs at precise scanlines. If A12 edges are miscounted or suppressed, the split is late/early/never, causing the bottom HUD or dialogue band to use wrong scroll/CHR banks → exactly the corrupted bottoms and seams seen.

Evidence in code:
- A12 detection path: `src/ppu/Logic.zig:223`–`src/ppu/Logic.zig:260` computes edges from `v`.
- Pattern fetch actually happens here with real CHR addresses we can use: `src/ppu/logic/background.zig:57`, `src/ppu/logic/background.zig:73`, `src/ppu/logic/background.zig:79` (getPatternAddress + memory.readVram).
- Mapper IRQ hook is already in place: `src/emulation/State.zig:682` calls `cart.ppuA12Rising()` when PPU flags it.
- Mapper state has an unused A12 tracker field we can delete after refactor: `src/cartridge/mappers/Mapper4.zig:56` (`a12_low_count` not used).

Fix design (low-risk, targeted):
- Move A12 edge detection to the points where CHR pattern fetch addresses are known and used.
  - On each pattern fetch (both BG and sprites), compute `a12 = (addr & 0x1000) != 0` from the actual CHR address (`getPatternAddress`, `getSpritePatternAddress`, and `getSprite16PatternAddress`).
  - Maintain a small A12 state in `PpuState` (already present: `a12_state`, `a12_filter_delay`) but update it using the CHR address bit, not `v`.
  - Apply the MMC3 filter (require A12 low for ≥ 6–8 PPU cycles) before raising the edge. Current filter fields can be reused; only the sampling source changes.
  - Set `flags.a12_rising = true` in the exact cycles where the pattern fetch finishes (cycles 5–6 for low, 7–8 for high) when the filter accepts the 0→1 transition.
- Remove or repurpose any now-redundant A12 logic in `PpuLogic.tick()` to avoid double-counting. The authoritative source should be the fetch sites.

Status in code (verified):
- A12 detection already migrated to CHR address (`chr_address`) and wired at pattern fetch sites (BG and Sprites).
- Additional refinement implemented now: filter low-cycle counter updates every PPU dot, with rising events armed only during fetch cycles. This avoids under-counting low time and stabilizes scanline IRQs.
  - Code: src/ppu/Logic.zig (A12 filter moved outside fetch-only block)
- Instrumentation results (new SMB3 test command below) show **only 1 A12 edge per scanline (159–190)** and the IRQ counter reloading to `$C1` then counting down to ~$A2 each frame; it **never reaches 0**, so irq_pending is never set. We still miss the 8 edges per scanline required for MMC3.
  - Command used: `zig test tests/integration/smb3_status_bar_test.zig ...` (see output in session)
  - Game writes `$C001` every scanline once IRQs are enabled; reload flag toggles continuously, so the counter is reset before it can reach zero. Need to ensure only one reload per scanline instead of continuous strobes.


Acceptance criteria:
- SMB3 status bar correctly split/positioned across frames.
- Kirby intro still exhibits mirrored top-half and missing dialog box; bottom band test does not catch this yet (visual inspection required).
- Mega Man 4 level renders without column seams and split timing is stable.
- Add a unit/diagnostic that increments a counter when `ppuA12Rising()` is called; verify we get 8 rises per visible scanline during active rendering in typical BG configurations. Tie this to an MMC3 “scanline IRQ demo” in `zig build mmc3-diagnostic`.

References:
- Wrong source: `src/ppu/Logic.zig:228`
- Correct places to derive A12:
  - BG pattern fetch: `src/ppu/logic/background.zig:73` and `src/ppu/logic/background.zig:79`
  - Sprite pattern fetch: `src/ppu/logic/sprites.zig:49`, `src/ppu/logic/sprites.zig:67` (8×8) and `src/ppu/logic/sprites.zig:20` (8×16 helper)


### 2) Keyboard Input Uses Layout-Dependent Keycodes (SMB1 “no input” on some systems)

Symptoms:
- On some environments SMB1 reports no input.

Root cause:
- We pass XKB keycodes through the pipeline and map them as if they were portable. Keycodes depend on layout and may not match our hard-coded constants.
  - Wayland event: `src/video/WaylandLogic.zig:345` computes `code = key_event.key + 8` and posts it as “keycode”.
  - Mapping uses fixed keycodes like `KEY_Z=52`, `KEY_ENTER=36` in `src/input/KeyboardMapper.zig:21`.
  - On non-US layouts (or certain compositor translations), these codes can differ.

Fix design:
- Switch to keysym-based mapping (layout-aware, portable):
  - In `WaylandLogic.zig`, after updating the XKB state, call `xkb_state_key_get_one_sym()` to obtain a keysym for the key event, and post that symbol through the input mailbox instead of (or in addition to) the raw keycode.
  - Update `XdgInputEventMailbox` to optionally carry a keysym.
  - Update `KeyboardMapper` to match on keysyms (e.g., `XKB_KEY_Up`, `XKB_KEY_z`, `XKB_KEY_x`, `XKB_KEY_Return`, `XKB_KEY_Shift_R`). Keep legacy keycode mapping as fallback.
- Optional: Provide a simple config-based remapping table in the future.

Acceptance criteria:
- SMB1 reliably receives input on US and non-US layouts (quick manual verification).
- Add a small integration sanity test that feeds synthetic key events into the mailbox and verifies the controller’s `buttons1` latch/shift reads via $4016 behave as expected.

References:
- Posting code path: `src/video/WaylandLogic.zig:345`
- Mapper: `src/input/KeyboardMapper.zig:21`

---

## P1 Issues (High Priority)

### 3) MMC3 IRQ lifecycle polish

Status: Core enable/disable/pending logic looks correct, including the “enable clears pending” nuance (see tests in `src/cartridge/mappers/Mapper4.zig:617`).

What to verify after A12 fix:
- IRQ firing rate and phase relative to the scroll split for SMB3/Kirby (no double-IRQs, stable split line).
- Acknowledge semantics: games typically clear with $E000/$E001; we do not auto-ack on CPU IRQ entry, which is correct.
- Mapper-wide “pending” should not stick across frames incorrectly.

Suggested instrumentation:
- Temporary counters in `Mapper4` for “irqs_raised” and “irqs_acknowledged” (gated behind a debug flag) to compare against expected per-frame patterns on SMB3 title and in-game.


### 4) Sprite/OAM pipeline correctness regression guardrails

Context:
- Progressive sprite evaluation was recently implemented and looks solid. Given the MMC3 changes, we should guard against regressions.

Action:
- Add focused tests around sprite overflow behavior and left-clip with status bar splits enabled (post-A12 fix), since many games combine these paths.
- Validate sprite 0 hit logic remains correct with PPUMASK delayed mask usage: `src/ppu/Logic.zig:300`.

---

## P2 Issues (Medium Priority)

### 5) Cleanups and minor correctness

- Remove unused Mapper4 field: `src/cartridge/mappers/Mapper4.zig:56` (`a12_low_count`). It’s not referenced.
- Consolidate mirroring getters to always return the enum type (`Cartridge.Mirroring`) rather than u1/u2 encodings:
  - Example: `src/cartridge/mappers/Mapper4.zig:167` returns `u1`. It works today, but aligning types reduces friction and makes switch exhaustiveness safer.
- Ensure four-screen mirroring path is either fully supported or clearly guarded/documented; today it mirrors to 2KB in `src/ppu/logic/memory.zig:42` (acceptable as a stopgap, but document that Mapper 4 never uses 4-screen so this path is for future mappers).
- Mask/clip MMC3 bank numbers to available ROM/RAM size (prevents OOB → 0xFF tiles/bytes causing visual garbage):
  - Implemented for CHR (1KB banks) and PRG (8KB banks) at read/write sites.
  - Code: src/cartridge/mappers/Mapper4.zig (ppuRead/ppuWrite and cpuRead now wrap bank indices).


### 6) Input ergonomics

- Add alternative default bindings (e.g., `J/K` for B/A), and show current mappings on startup in the console.
- Add a `--input-diagnostics` flag that prints raw keycode and keysym for a few events to quickly confirm correct mapping.

### 7) SMB1-specific input anomaly (others OK)

Observations provided by user:
- SMB3, Kirby, and Mega Man register input (despite visual corruption), but SMB1 does not.

Why this likely isn’t a global key mapping issue:
- The same Wayland→KeyboardMapper→Mailbox→Controller pipeline is used for all titles; success in MMC3 titles suggests the path is functional on the user system.

Targeted hypotheses specific to SMB1:
- H1: Strobe latch semantics are too edge-dependent.
  - Current code latches only on a rising edge: `src/emulation/state/peripherals/ControllerState.zig:writeStrobe()` sets `rising_edge = new_strobe and !self.strobe` and latches only then.
  - Hardware behavior per nesdev: writing a 1 to $4016 continuously latches while high; many games (including SMB1) briefly write 1 then 0, but some code paths assume latching occurs on any write with bit0=1, not strictly a 0→1 transition.
  - Proposed remedial change (safe): latch on any write with bit0=1 (level), not only on rising edge; keep “reads while strobe=1 return A” behavior.
    - Pseudocode:
      - if (value & 1) { strobe = true; latch(); } else { strobe = false; }
    - File: `src/emulation/state/peripherals/ControllerState.zig`.

- H2: Input posting cadence (main thread sleep) can drop short taps in SMB1’s narrow sampling window.
  - Main loop posts controller state once per iteration and then sleeps 100ms: `src/main.zig:302` (approx.).
  - Emulation thread samples input every frame (~16.7ms). A quick tap shorter than the 100ms main-loop period can be missed if it occurs between posts. Other games may read for longer windows or interpret repeated samples, masking the issue.
  - Low-risk improvement: post immediately on each input event (already done) AND reduce the main-loop sleep to, e.g., 5–10ms, or gate posting on actual changes. Alternatively, migrate input posting to a dedicated event-driven loop without the coarse sleep.

- H3: Return vs KP_Enter key ambiguity specific to SMB1 “Start”.
  - Mapping uses XKB keycodes; `KEY_ENTER = 36` (Return). If the user presses keypad Enter (keysym KP_Enter), it won’t match. Other games may be started with A/B or different flow, which hides the issue.
  - Keysym migration (see P0/P2 items above) eliminates this confusion by mapping `XKB_KEY_Return` and `XKB_KEY_KP_Enter` explicitly.

Triage plan for SMB1:
- Instrument $4016 writes/reads to confirm strobe sequence and button bits during SMB1 title, first 300 frames.
- Apply the “level-based latch on write=1” change and retest. IMPLEMENTED.
- Reduce main-loop sleep to 5–10ms and retest quick-tap detection. IMPLEMENTED (10ms).
- After keysym migration, verify Start via Return and KP_Enter both work.

Changes applied in this phase:
- Controller strobe latch semantics updated to level-based while high.
  - Code: src/emulation/state/peripherals/ControllerState.zig:writeStrobe()
  - Behavior: writing 1 to $4016 now latches immediately (even if already high), writing 0 enables shifting.
- Added unit test to guard behavior:
  - tests/emulation/state/peripherals/controller_state_test.zig: “writeStrobe(1) while high re-latches current buttons”
- Main loop input cadence improved:
  - Code: src/main.zig: sleep reduced 100ms → 10ms
  - Rationale: SMB1 likely samples a short strobe window; improving latch semantics and posting cadence reduces missed taps while preserving existing controller protocol tests.

---

## Investigation Synthesis (sessions cross-check)

Reviewed sessions:
- docs/sessions/2025-10-17-phase3-investigation-synthesis.md
- docs/sessions/2025-10-17-phase3-bug1-a12-detection-fix.md
- docs/sessions/2025-10-17-phase3-bug2-mmc3-irq-acknowledge-fix.md

Findings vs code:
- Bug #1 (A12 source): Implemented (chr_address) and now refined to count low cycles continuously. Good.
- Bug #2 (IRQ acknowledge): Code matches doc — $E000 disables + acknowledges; $E001 enables without clearing pending. Verified at src/cartridge/mappers/Mapper4.zig:116–151.
- Persistent glitches (SMB3 floor drop, Kirby dialog missing, Mega Man IV corruption) likely stemmed from two gaps:
  1) A12 low-time filter previously updated only during fetch cycles (under-counting) — fixed as above.
  2) Missing CHR/PRG bank wrapping for out-of-range values causing reads to fall off into 0xFF — now wrapped modulo available banks.

Next triage steps:
- Instrument per-scanline counters for A12 rises and IRQ triggers while running SMB3/Kirby intros; confirm consistent 8 rises per active scanline and one IRQ at the intended split.
- Dump MMC3 CHR bank registers R0–R5 at vblank and mid-frame to ensure expected values; verify modulo wrapping changes remove transient 0xFF reads.
- If anomalies remain, add a temporary trace to log when irq_pending transitions and when CPU writes $E000/$E001 (ack/enable) to see if handlers execute too late/early.

### New guard tests (mixed results)
- Added MMC3 visual regression tests to capture bottom-of-screen blanking:
  - tests/integration/mmc3_visual_regression_test.zig covers SMB3, Kirby, Mega Man 4.
  - Kirby currently passes the “non-monotone bottom” check, but the intro still mirrors the sky into the lower half—test needs refinement. SMB3 and Mega Man 4 continue to fail (bottom rows remain uniform/black).
- Existing `tests/integration/smb3_status_bar_test.zig` still fails (no MMC3 IRQs detected). Instrumentation prints:
  - A12 edges: only 1 per scanline (should be ~8).
  - IRQ counter: reloads to `$C1` every scanline, never reaches zero; reload flag triggered constantly by game code (`$C001` writes each scanline).
  - Forcing background A12 to dot 260 or zeroing the counter on `$C001` did **not** restore IRQs; rolled back to avoid masking the underlying bug (see `docs/sessions/2025-10-18-mmc3-irq-investigation.md`).

---

## Test Coverage and Tooling

- MMC3 diagnostics: Ensure `zig build mmc3-diagnostic` exercises both BG and sprite fetch phases and prints A12 rise counts per scanline. Use this during the A12 source refactor.
- Controller diagnostics: Two utilities already exist at workspace root: `test_controller_diagnostic.zig` and `test_controller_reads.zig`. After keysym migration, update them to log both code and symbol for transparency.
- Keep AccuracyCoin as a CPU baseline; consider adding a tiny “PPU A12” synthetic to confirm filter thresholds.

---

## Risk Assessment and Rollout Plan

1) Implement A12-from-CHR-address refactor (isolated change):
   - Touch points: BG and sprite fetchers; remove A12 block in `PpuLogic.tick()`; keep the existing `flags.a12_rising` plumbing.
   - Verify on SMB3 title first (status bar split stable), then Kirby and Mega Man 4 levels.

2) Switch input to keysyms (additive first):
   - Carry both keycode and keysym for one cycle; prefer keysym; keep keycode fallback.
   - Provide minimal console diagnostics to help users validate input in their environment quickly.

3) Minor cleanups (dead fields, type alignment) as separate commits after the above land to minimize risk.

---

## Concrete File References (starting lines)

- Wrong A12 source (uses `v` register): `src/ppu/Logic.zig:228`
- BG pattern fetch address use sites: `src/ppu/logic/background.zig:57`, `src/ppu/logic/background.zig:73`, `src/ppu/logic/background.zig:79`
- Sprite pattern address helpers: `src/ppu/logic/sprites.zig:20`, `src/ppu/logic/sprites.zig:49`, `src/ppu/logic/sprites.zig:67`
- Mapper IRQ hook point in emulation: `src/emulation/State.zig:682`
- Unused field in MMC3: `src/cartridge/mappers/Mapper4.zig:56`
- Keyboard keycode posting: `src/video/WaylandLogic.zig:345`
- Keyboard mapping constants (layout-dependent): `src/input/KeyboardMapper.zig:21`

---

## Summary Checklist

- [ ] Replace A12 source with CHR-bus-derived bit and keep MMC3 filter; verify SMB3/Kirby/Mega Man 4
- [ ] Migrate input to keysym mapping; keep code fallback; add diagnostics
- [ ] Remove `Mapper4.a12_low_count`; align mirroring getters to enum
- [ ] Add MMC3 A12 and controller integration diagnostics
- [ ] Optional: alternative default bindings (J/K), print mapping on startup

Estimated impact: Fixes the user-reported visual artifacts in MMC3 games and resolves SMB1 input reports on varied setups. Should materially improve commercial ROM compatibility without touching unrelated subsystems.
