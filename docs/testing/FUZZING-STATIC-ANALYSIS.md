# Fuzzing & Static Analysis Plan (Zig 0.15.1)

**Last Updated:** 2025-10-06  
**Status:** READY FOR IMPLEMENTATION  
**Scope:** Add fuzz testing and lightweight static analysis to RAMBO using Zig 0.15.1 tooling.

---

## 1. Objectives
- Integrate Zig's built-in fuzzer (`std.testing.fuzz`) to stress bus, cartridge, and mapper invariants.  
- Provide a `zig build fuzz` pipeline that builds with `-ffuzz`, runs under the test runner, and stores corpus artifacts in `zig-cache/`.  
- Establish a repeatable static analysis step (`zig build lint`) that performs syntax checks, formatting validation, and optional sanitiser runs.  
- Keep the RT loop hot path unaffected: fuzz targets operate on isolated harnesses; static analysis runs outside performance-critical builds.

Success metrics:
1. `zig build fuzz` compiles with `.root_module.fuzz = true`, runs using the test runner (automatically passing `--cache-dir`) and exits 0 after exploring corpus seeds.  
2. Fuzz harnesses exist for bus mirroring, cartridge PRG/CHR routing, and mapper bank switching; each asserts invariants without mutating shared emulator state.  
3. `zig build lint` includes formatting check, AST validation, and sanitizer-enabled unit tests (`-fsanitize-thread` on CPU/APU heavy suites).  
4. CI documentation updated so contributors know how to run both steps before PRs.

---

## 2. Zig 0.15.1 Capabilities Reference
- **Fuzz instrumentation:** enable via `.root_module.fuzz = true` (build system) or CLI `-ffuzz`. Requires test runner mode to supply `--cache-dir`.  
- **API:** `std.testing.fuzz(context, testOne, .{ .corpus = &.{ ... } })` registers fuzz targets inside `test` blocks.  
  - The `context` value is copied into each invocation; keep it small (e.g., allocator ref).  
  - `testOne` receives `[]const u8` input; decode using deterministic schema.  
- **Execution:** `zig build addRunArtifact(test).enableTestRunnerMode()` handles `--cache-dir` and seeds. Direct `zig test -ffuzz` requires manual cache args; using the build runner avoids crashes.  
- **Corpora:** Place initial seeds under `tests/fuzz/corpus/<target>/` and pass them through `FuzzInputOptions`. Coverage-guided mutations are written back into the build cache automatically.  
- **Static checks:**
  - `zig fmt --check` for formatting.  
  - `zig ast-check <file>` ensures syntax-only validation without generating code.  
  - Sanitizers: `compile.root_module.sanitize_thread = true` (ThreadSanitizer), `stack_check`, `stack_protector`.  
  - `zig build test` already respects `.sanitize_thread`; combine with `-fsanitize-thread` for C interop if added.

References:  
- `lib/std/testing.zig` (fuzz API).  
- `lib/std/Build/Module.zig` (`CreateOptions.fuzz`).  
- `lib/std/Build/Step/Run.zig` (`enableTestRunnerMode` passes `--cache-dir`).

---

## 3. Implementation Tasks

### 3.1 Build System
- **Add fuzz targets** in `build.zig`:
  - Create `const fuzz_tests = b.addTest(.{ ... })` with `.root_module = b.createModule(.{ .root_source_file = b.path("tests/fuzz/main.zig"), .fuzz = true, ... })`.  
  - Mirror imports used by other tests (`RAMBO`, config module, etc.).  
  - `const run_fuzz_tests = b.addRunArtifact(fuzz_tests);` and expose via `const fuzz_step = b.step("fuzz", "Run fuzz harnesses (Debug + -ffuzz)"); fuzz_step.dependOn(&run_fuzz_tests.step);`.  
  - Set output dir: `run_fuzz_tests.addArgs(&.{"--cache-dir=zig-cache/fuzz"});` (or rely on default by `enableTestRunnerMode`).  
  - Provide optional `-Drelease-fuzz` to compile harnesses in `ReleaseSafe` for speed when triaging.

- **Static analysis step:**
  - Add `const lint_step = b.step("lint", "Static analysis (format, ast, sanitizers)");`.  
  - Attach sub-steps:
    1. `b.addSystemCommand(&.{"zig", "fmt", "--check", "src", "tests", "docs"});`.  
    2. `b.addSystemCommand` for `zig ast-check $(rg -g'*.zig' -l src tests docs)` (generate file list via helper script).  
    3. Optional: `const tsan_tests = b.addTest(.{ .root_module = ..., .optimize = .Debug }); tsan_tests.root_module.sanitize_thread = true; lint_step.dependOn(&b.addRunArtifact(tsan_tests).step);`.  
  - Document environment variables (`ZIG_AST_CHECK=1`) for CI caching.

### 3.2 Fuzz Harness Layout (`tests/fuzz/`)
- `main.zig`: registers fuzz suites, reuses `std.testing.refAllDecls` to ensure linking. Each suite in separate module for clarity.
- Targets:
  1. **Bus RAM mirroring:** mutate address/value pairs; ensure `busRead` mirrors across 0x0800/0x1000/0x1800. Assert using existing helper functions.  
  2. **Cartridge PRG RAM** (post-implementation): random writes within $6000–$7FFF, confirm data persists, open bus when disabled.  
  3. **Mapper state transitions:** for Mapper0, random ROM size + address; ensure `cpuRead` never out-of-bounds and `ppuWrite` obeys CHR RAM flag. Additional mappers add invariants as they land.  
  - Each harness initialises a fresh `EmulationState`/`Cartridge` per call; avoid global state to ensure determinism.  
  - Provide `corpus` seeds capturing edge cases (boundary addresses, zero length input).  
  - Guard loops against long inputs (cap iterations) to keep per-test runtime low.

### 3.3 Static Analysis Enhancements
- Add `scripts/zig-ast-check.sh` (bash) to enumerate Zig files and invoke `zig ast-check`. Called from build step; ensures consistent results locally and in CI.  
- Extend documentation (`docs/testing/README.md`) with instructions for `zig build fuzz`, `zig build lint`, and tips for triaging fuzz crashes (reproducing with saved inputs from `zig-cache/fuzz/crashes`).  
- For sanitizers: update `build.zig` optional flag `-Dsanitizers=thread` toggling `.sanitize_thread = true` across core unit tests; mention runtime cost.

### 3.4 CI Integration (Follow-up)
- Add `fuzz` and `lint` jobs in CI matrix (nightly fuzz for N minutes; lint per PR).  
- Artifacts: stash `zig-cache/fuzz/crashes` on failure for analysis.  
- Ensure CI machines use Linux/macOS (Windows fuzz not yet supported; `std.Build.WebServer` prints "--fuzz not yet implemented" for Windows).

---

## 4. Development Notes & Constraints
- **Runtime isolation:** fuzz harnesses must not mutate global emulator state; instantiate fresh `EmulationState` per iteration.  
- **Deterministic seeds:** rely on Zig test runner seed (printed on crashes) for reproduction via `zig build fuzz -Dseed=...` (extend build step to accept option if needed).  
- **Crash triage:** On failure, Zig writes crashing input to `zig-cache/fuzz/corpus/crashes/{hash}`; document reproduction command (`zig build fuzz -- --stdin < crash`).  
- **Performance:** Fuzz instrumentation increases binary size & slows tests; keep harnesses focused and avoid expensive loops.  
- **Static analysis coverage:** `zig ast-check` only handles Zig files; ensure generated files (if any) excluded or generated prior to lint step.  
- **ThreadSanitizer limitations:** only available on Tier-1 (Linux/macOS). Guard lint step so it skips gracefully on unsupported targets (use `builtin.os.tag` checks).

---

## 5. Verification Checklist
- [ ] `zig build fuzz` runs for baseline duration, logs coverage progress, and stops without crash.  
- [ ] Crash reproduction documented; sample failing corpus triggers targeted test.  
- [ ] `zig build lint` passes on clean tree; fails with descriptive message for formatting or syntax errors.  
- [ ] Documentation updated (`docs/testing/README.md`, CI guide).  
- [ ] Optional: nightly job confirming fuzz step executes for N minutes (config TBD).

---

## 6. Risk Assessment
- **API stability:** `std.testing.fuzz` still evolving; verify against Zig 0.15.1 release notes for breaking changes between minor updates. Mitigation: keep harnesses lightweight; update on Zig upgrades.  
- **Flaky fuzz runs:** enforce deterministic harness (bounded loops, no timers). If flakiness observed, reduce iteration cap or add kill-switch after `N` instructions.  
- **Sanitizer overhead:** TSan increases runtime 3–5×; ensure lint step documented as heavier job, maybe optional via build flag.  
- **Developer adoption:** Provide quick-start instructions (commands, expected output) to encourage usage.

With this plan, RAMBO gains a reproducible fuzzing workflow and a static analysis gate tailored to Zig 0.15.1 tooling while keeping emulator hot paths untouched.
