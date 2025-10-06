# Repository Guidelines

## Project Structure & Module Organization
Core emulator logic sits under `src/`, with hardware domains split into folders such as `cpu/`, `ppu/`, `bus/`, `cartridge/`, and `snapshot/`. Entry wiring lives in `src/main.zig` and `src/root.zig`, while mailboxes, timing, and I/O helpers reside in their own peer modules. Tests mirror this layout in `tests/`, and follow the same folder names to keep unit, integration, trace, and snapshot suites aligned. Reference material and phase notes are collected in `docs/`, and build artifacts land in `zig-out/`.

## Build, Test, and Development Commands
Use `zig build` for a full release-mode build and `zig build run` for the current executable. Run `zig build --summary all test` before every PR; it drives the 583-test bundle via Zig's built-in runner and prints per-suite counts. Targeted suites are available: `zig build test-unit`, `zig build test-integration`, and `zig build test-trace`. During debugging, `zig test src/cpu/*.zig` is acceptable, but finish with the orchestrated `zig build` commands.

## Coding Style & Naming Conventions
Code must be formatted with `zig fmt`; run `zig fmt src tests docs` (or `zig fmt --check ...` in CI scripts) before committing. Use four-space indentation and avoid trailing whitespace. Zig naming conventions apply: types and namespaces in TitleCase, functions and variables in lowerCamelCase, compile-time constants in UpperCamelCase when exposed. Keep hot paths allocation-free and document non-obvious micro-optimizations with a brief comment.

## Testing Guidelines
Write tests in the mirrored directory inside `tests/` and name them after the behavior under scrutiny, e.g. `test "ppu sprite overflow"`. Integration traces belong in `tests/integration` and should include the cartridge filename in the description. Any change touching CPU, PPU, or bus timing must re-run `zig build test-trace` and attach failures. Snapshot regressions live in `tests/snapshot`; update golden data only when the new behavior is verified against known-good ROMs.

## Commit & Pull Request Guidelines
Follow the Conventional Commit pattern already in history (`feat(cpu): ...`, `refactor(ppu): ...`). Commit early, but squash noisy fixups before pushing. PRs should summarize the behavior change, list the Zig build or test commands you ran, and link the relevant issue or roadmap phase. Include screenshots or trace snippets when a visual debugger or waveform changes.
