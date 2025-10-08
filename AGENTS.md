# Repository Guidelines

## Project Structure & Module Organization
RAMBO is a Zig 0.15.1 NES emulator. Hardware logic lives in `src/` (cpu, ppu, apu, memory, video) with orchestration in `src/main.zig` and `src/root.zig`. Utilities sit in `compiler/` (Python `uv` tasks for rebuilding AccuracyCoin ROMs); verified ROM artifacts live in `AccuracyCoin/`. Tests mirror runtime layout under `tests/`, while design notes and audits are kept in `docs/`. Build products land in `zig-out/`.

## Build, Test, and Development Commands
Run `zig build` for a debug artifact and `zig build run` to launch the emulator (pass runtime flags after `--`). `zig build test` drives the 561-test matrix; one threading case is expected to stay skipped, but treat any new failure as a regression. Targeted steps: `zig build test-unit` for module and APU suites, `zig build test-integration` for CPU/PPU, bus, and AccuracyCoin traces. `zig build --summary all test` helps spot which suite failed. Asset tooling lives under `compiler/`; `uv run compiler build-accuracycoin` rebuilds the canonical ROM and verifies it against `AccuracyCoin/AccuracyCoin.nes`.

## Coding Style & Naming Conventions
Format Zig sources with `zig fmt`; run `zig fmt src tests docs` (or `zig fmt --check ...`) before committing. Use four-space indentation, avoid trailing whitespace, and follow Zig casing rules: types and namespaces TitleCase, functions and variables lowerCamelCase, exported comptime toggles UpperCamelCase. Keep hot paths allocation-free and annotate intentional micro-optimizations sparingly.

## Testing Guidelines
Add tests beside the code they cover inside `tests/`, naming them for observable behavior (`test "ppu sprite overflow"`). Call out the ROM under test in any integration description. Timing, bus, or mapper changes must re-run `zig build test` and the focused command that hits the touched subsystem. Regenerate snapshots in `tests/snapshot` only after verifying the new output against a trusted ROM capture.

## Commit & Pull Request Guidelines
Match the Conventional Commit style in history (`feat(cpu):`, `refactor(timing):`). Group logical work, then squash noisy fixups locally. PRs need a crisp behavior summary, the Zig build/test commands you executed, and links to roadmap items or issues. Provide screenshots, trace snippets, or perf deltas whenever video, debugger output, or timing shifts.

## ROM Tooling & Configuration Tips
Use Zig 0.15.1 on Linux with Wayland and Vulkan for video-phase work; confirm with `zig version`. Iterate on ROM assets via `compiler/` so `uv` manages dependencies—never hand-edit files in `AccuracyCoin/`. Touch `rambo.kdl` only when changing default runtime wiring, and document any new configuration in `docs/`.
