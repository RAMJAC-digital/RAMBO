# Repository Guidelines

## Project Structure & Module Organization
RAMBO targets Zig 0.15.1. Core emulator logic lives in `src/` (CPU, PPU, APU, memory, video) with orchestration in `src/main.zig` and `src/root.zig`. Tests mirror runtime modules under `tests/`, while ROM design notes reside in `docs/`. Verified AccuracyCoin artifacts live in `AccuracyCoin/`, and Python-based asset tooling sits in `compiler/`. Build outputs land in `zig-out/`.

## Build, Test, and Development Commands
Run `zig build` for the default debug binary. Launch the emulator with `zig build run -- [options]`. Execute `zig build test` for the full matrix; use `zig build --summary all test` to pinpoint failures. Focused suites: `zig build test-unit` for modules/APU, `zig build test-integration` for CPU, PPU, bus, and ROM traces. Rebuild the canonical ROM with `uv run compiler build-accuracycoin`.

## Coding Style & Naming Conventions
Use `zig fmt src tests docs` before sending changes. The codebase assumes four-space indentation and no trailing whitespace. Types and namespaces are TitleCase, functions and locals lowerCamelCase, exported comptime toggles UpperCamelCase. Avoid allocations on hot paths; annotate deliberate micro-optimizations sparingly.

## Testing Guidelines
Place new tests beside the behavior they cover under `tests/` and name them descriptively (e.g. `test "ppu sprite overflow"`). Call out the ROM under test for integration work. Always rerun `zig build test` after timing, bus, or mapper edits, and target the subsystem suite you touched. Only refresh `tests/snapshot/` outputs after verifying against a trusted capture.

## Commit & Pull Request Guidelines
Follow Conventional Commits (`feat(cpu):`, `refactor(timing):`). Group related changes and squash noisy fixups locally. PRs should summarize behavior shifts, list `zig build`/test commands executed, link issues or roadmap items, and include screenshots, traces, or perf deltas when video or timing changes.

## ROM Tooling & Configuration Tips
Confirm Zig 0.15.1 with `zig version`. Iterate on ROM assets via `compiler/` so `uv` manages dependencies; never edit `AccuracyCoin/` artifacts directly. Update `rambo.kdl` only for new runtime wiring and document configuration changes in `docs/`.
