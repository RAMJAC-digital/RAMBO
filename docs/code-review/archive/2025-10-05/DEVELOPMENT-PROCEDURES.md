# RAMBO Cleanup - Development Procedures

**Last Updated:** 2025-10-05
**Purpose:** Standard operating procedures for executing cleanup phases

---

## Overview

This document defines the **exact workflow** for implementing each phase of the cleanup plan. Follow these procedures to maintain:
- Zero regressions
- Comprehensive testing
- Clear documentation
- Reproducible builds

---

## Phase Execution Workflow

### Before Starting Any Phase

1. **Review Phase Requirements**
   ```bash
   # Read the specific phase documentation
   cat docs/code-review/CLEANUP-PLAN-2025-10-05.md | grep -A 20 "Priority X"

   # Read subagent analysis for the phase
   cat docs/code-review/SUBAGENT-ANALYSIS.md | grep -A 30 "Priority X"
   ```

2. **Create Baseline**
   ```bash
   # Tag the current state
   git tag "pre-phase-N-$(date +%Y%m%d)"

   # Verify clean working directory
   git status

   # Run baseline tests
   zig build test > baseline-phase-N.log 2>&1

   # Verify expected test count (575/576)
   grep "tests passed" baseline-phase-N.log
   ```

3. **Set Up Todo Tracking**
   - Update todo list with phase-specific tasks
   - Mark current phase as "in_progress"
   - Keep todo list updated throughout

---

### During Phase Implementation

#### Step 1: TDD - Write Failing Tests First

```bash
# Example for Phase 1 (Opcode State Module)
# 1. Create test file
touch tests/cpu/opcodes/state_test.zig

# 2. Write failing test
cat > tests/cpu/opcodes/state_test.zig << 'EOF'
const std = @import("std");
const testing = std.testing;
const RAMBO = @import("RAMBO");

test "Opcode state is pure data" {
    const State = @import("opcodes/state.zig");
    const opcode_state = State.OpcodeState{
        .opcode = 0xA9,
        .cycle = 2,
        // ...
    };
    try testing.expectEqual(@as(u8, 0xA9), opcode_state.opcode);
}
EOF

# 3. Verify test fails
zig test tests/cpu/opcodes/state_test.zig  # Should fail - module doesn't exist yet
```

#### Step 2: Implement Incrementally

```bash
# Create the module
mkdir -p src/cpu/opcodes
touch src/cpu/opcodes/state.zig

# Implement minimal code to make test pass
cat > src/cpu/opcodes/state.zig << 'EOF'
pub const OpcodeState = struct {
    opcode: u8,
    cycle: u8,
    addressing_mode: AddressingMode,
    effective_address: u16,
    temp_value: u8,
};
EOF

# Verify test passes
zig test tests/cpu/opcodes/state_test.zig  # Should pass now
```

#### Step 3: Run Fast Tests After Each Change

```bash
# After each small change, run unit tests (fast)
zig build test-unit

# If unit tests pass, run full suite
zig build test

# Check for regressions
diff baseline-phase-N.log <(zig build test 2>&1)
```

#### Step 4: Commit at Milestones

**Commit every 2-4 hours or after completing a logical unit:**

```bash
# Stage changes
git add src/cpu/opcodes/state.zig tests/cpu/opcodes/state_test.zig

# Descriptive commit message
git commit -m "phase N: implement opcode state module

- Created src/cpu/opcodes/state.zig (pure data structure)
- Added tests/cpu/opcodes/state_test.zig (10 tests)
- All tests passing (575/576 maintained)
"
```

---

### After Completing Phase

#### Step 1: Comprehensive Verification

```bash
# 1. Run full test suite
zig build test

# 2. Verify test count (should be ≥ 575)
zig build test 2>&1 | grep "tests passed"

# 3. Check for compilation warnings
zig build 2>&1 | grep "warning"

# 4. Run debug tests
zig build test-debug

# 5. Verify AccuracyCoin.nes loads
zig build run 2>&1 | head -20
```

#### Step 2: Baseline Comparison

```bash
# Compare test results
diff baseline-phase-N.log <(zig build test 2>&1) > phase-N-diff.log

# Verify no regressions (diff should only show additions, not subtractions)
cat phase-N-diff.log

# For critical phases, compare CPU traces
zig test tests/cpu/trace_test.zig > trace-after.log
diff baseline-trace.log trace-after.log  # Should be identical
```

#### Step 3: Update Documentation

```bash
# 1. Mark phase complete in cleanup plan
sed -i 's/Priority N:/✅ Priority N (COMPLETE):/' docs/code-review/CLEANUP-PLAN-2025-10-05.md

# 2. Update development progress
cat >> docs/code-review/DEVELOPMENT-PROGRESS.md << 'EOF'

## Phase N: [Name] ✅ COMPLETE

**Duration:** [Date] ([Hours])
**Commit:** [Hash] - [Message]
**Status:** ✅ Complete - All objectives met

### Objectives Completed
- [x] Objective 1
- [x] Objective 2
...
EOF

# 3. Update CLAUDE.md if architecture changed
# (Edit manually to reflect new structure)
```

#### Step 4: Final Commit

```bash
# Commit all phase work
git add -A

git commit -m "$(cat <<'EOF'
feat(phase-N): [Phase Name] complete

Summary:
- [Key achievement 1]
- [Key achievement 2]
- [Key achievement 3]

Implementation:
- [File 1]: [What changed]
- [File 2]: [What changed]

Testing:
- [X]/[Y] tests passing
- Zero regressions
- [New test coverage added]

Documentation:
- Updated CLEANUP-PLAN-2025-10-05.md
- Updated DEVELOPMENT-PROGRESS.md
- [Phase-specific docs]

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"
```

---

## Phase-Specific Procedures

### Phase 0: Stateless Parser ✅ COMPLETE

**See:** [`PHASE-0-STATELESS-PARSER.md`](PHASE-0-STATELESS-PARSER.md)

**Key Steps:**
1. Create `src/config/parser.zig` (stateless function)
2. Write `tests/config/parser_test.zig` first (TDD)
3. Refactor `Config.zig` to use parser
4. Update all config tests to use parser
5. Verify 575/576 tests still pass

---

### Phase 1: Opcode State/Execution Separation

**Duration:** 6-8 hours
**Complexity:** HIGH
**Risk:** MEDIUM (requires careful refactoring)

#### Prerequisites

- [ ] Read `SUBAGENT-ANALYSIS.md` - Agent 2 findings
- [ ] Understand State/Logic pattern from `docs/code-review/01-architecture.md`
- [ ] Review existing `src/cpu/` structure

#### Implementation Steps

**1. Create Opcode State Module (1h)**
```bash
mkdir -p src/cpu/opcodes
touch src/cpu/opcodes/state.zig

# Pure data structure - no system coupling
cat > src/cpu/opcodes/state.zig << 'EOF'
pub const OpcodeState = struct {
    opcode: u8,
    cycle: u8,
    addressing_mode: AddressingMode,
    effective_address: u16,
    temp_value: u8,
};
EOF

# Write tests first
zig test tests/cpu/opcodes/state_test.zig
```

**2. Extract Pure Microsteps (2h)**
```bash
mkdir -p src/cpu/execution
touch src/cpu/execution/microsteps.zig

# Move microstep functions from execution.zig
# Make them pure (parameters only, no CpuState direct access)

# Example:
# OLD: pub fn fetchOpcode(cpu: *CpuState, bus: *BusState) void
# NEW: pub fn fetchOpcode(pc: *u16, bus: anytype) u8
```

**3. Group Opcodes by Function (3-4h)**
```bash
# Create opcode group files
touch src/cpu/opcodes/LoadStore.zig
touch src/cpu/opcodes/Arithmetic.zig
touch src/cpu/opcodes/Logical.zig
touch src/cpu/opcodes/Shifts.zig
touch src/cpu/opcodes/Branches.zig
touch src/cpu/opcodes/Jumps.zig
touch src/cpu/opcodes/Stack.zig
touch src/cpu/opcodes/Transfer.zig
touch src/cpu/opcodes/Unofficial.zig

# Move instructions from src/cpu/instructions/*.zig
# Update to use pure microsteps
# Thread config for unstable opcodes
```

**4. Refactor Dispatch (1-2h)**
```bash
# Move dispatch.zig to opcodes/
mv src/cpu/dispatch.zig src/cpu/opcodes/dispatch.zig

# Create builder functions
cat >> src/cpu/opcodes/dispatch.zig << 'EOF'
fn buildLoadStoreOpcodes() []DispatchEntry { ... }
fn buildArithmeticOpcodes() []DispatchEntry { ... }
// etc.

pub fn buildDispatchTable() [256]DispatchEntry {
    var table: [256]DispatchEntry = undefined;
    // Combine all builder results
    return table;
}
EOF
```

#### Verification Checklist

- [ ] All 256 opcodes have entries
- [ ] No null function pointers
- [ ] Dispatch table binary identical to baseline
- [ ] CPU traces match baseline exactly
- [ ] 575+ tests passing
- [ ] AccuracyCoin.nes loads

---

### Phase 2: PPU Pipeline Refactoring

**Duration:** 4-6 hours
**Complexity:** MEDIUM
**Risk:** MEDIUM (pixel accuracy critical)

#### Implementation Steps

**1. Create Pipeline Module (1h)**
```bash
touch src/ppu/pipeline.zig

# Extract stage functions
cat > src/ppu/pipeline.zig << 'EOF'
pub fn advanceCycle(state: *PpuState) void { ... }
pub fn tickBackgroundPipeline(state: *PpuState, dot: u16) void { ... }
pub fn tickSpritePipeline(state: *PpuState, dot: u16, visible: bool) void { ... }
pub fn renderPixel(state: *PpuState, fb: ?[]u32, x: u16, y: u16) void { ... }
pub fn tickVBlankTiming(state: *PpuState, scanline: u16, dot: u16) void { ... }
EOF
```

**2. Refactor PPU Logic.zig (2-3h)**
```bash
# Simplify tick() to use pipeline functions
# Keep all logic identical, just reorganize
```

**3. Write Pipeline Tests (1h)**
```bash
touch tests/ppu/pipeline_stages_test.zig

# Test each stage independently
# Verify pixel-perfect output
```

**4. Pixel-Perfect Verification (1h)**
```bash
# Capture baseline framebuffer
zig test tests/ppu/framebuffer_test.zig > baseline-ppu-frame.bin

# After refactor, compare
diff baseline-ppu-frame.bin <(zig test tests/ppu/framebuffer_test.zig)
```

---

### Phase 3: Configuration Integration

**Duration:** 3-4 hours
**Complexity:** LOW
**Risk:** LOW (config system already exists)

#### Implementation Steps

**1. Thread Config Through CPU (1h)**
```bash
# Update CpuState to include config pointer
# Non-owning pointer, managed by EmulationState
```

**2. Update Unstable Opcodes (1-2h)**
```bash
# Modify 7 opcode functions to use config
# XAA, LXA, SHA, SHX, SHY, TAS, ANE
```

**3. Write Variant Tests (1h)**
```bash
touch tests/cpu/unstable_variants_test.zig

# Test all magic values: 0x00, 0xEE, 0xFF
# Test SHA behaviors: RP2A03G vs RP2A03H
```

---

### Phase 4: Code Organization Cleanup

**Duration:** 4-6 hours
**Complexity:** LOW
**Risk:** LOW (mostly file movement)

**See cleanup plan for detailed steps.**

---

### Phase 5: Documentation Updates

**Duration:** 2-3 hours
**Complexity:** LOW

**Checklist:**
- [ ] Update `CLEANUP-PLAN-2025-10-05.md` with ✅
- [ ] Update `DEVELOPMENT-PROGRESS.md` with all phases
- [ ] Update `CLAUDE.md` with new architecture
- [ ] Create `REFACTORING-SUMMARY.md`

---

### Phase 6: Integration Verification

**Duration:** 2-3 hours
**Complexity:** LOW

#### Create Baseline Capture Script

```bash
cat > scripts/capture-baseline.sh << 'EOF'
#!/bin/bash
set -e

mkdir -p baseline

# Dispatch table
zig test tests/cpu/dispatch_debug_test.zig > baseline/dispatch.json

# CPU trace
zig test tests/integration/cpu_trace_test.zig > baseline/cpu_trace.log

# PPU framebuffer
zig test tests/ppu/framebuffer_test.zig > baseline/ppu_frame.bin

echo "Baseline captured in baseline/"
EOF

chmod +x scripts/capture-baseline.sh
```

#### Run Regression Suite

```bash
# Full test suite
zig build test

# Compare all baselines
diff baseline/dispatch.json <(zig test tests/cpu/dispatch_debug_test.zig)
diff baseline/cpu_trace.log <(zig test tests/integration/cpu_trace_test.zig)
diff baseline/ppu_frame.bin <(zig test tests/ppu/framebuffer_test.zig)
```

---

## Blocker Protocol

**If ANY of these occur, STOP and document:**

1. ❌ Test count drops below 575
2. ❌ CPU trace diverges from baseline
3. ❌ PPU framebuffer differs from baseline
4. ❌ Dispatch table structure changes
5. ❌ Memory leaks detected
6. ❌ Race conditions found
7. ❌ AccuracyCoin.nes fails to load
8. ❌ Architectural decision unclear

**Action:**
```bash
# 1. Commit current state (even if incomplete)
git add -A
git commit -m "WIP: phase N - blocker encountered

Blocker: [Description]
Context: [What was being done]
Error: [Error message or issue]
"

# 2. Document blocker
cat >> docs/code-review/BLOCKERS.md << EOF
## Blocker: [Date] - Phase N

**Issue:** [Description]

**Context:** [What was being done]

**Error/Symptoms:** [Details]

**Resolution Needed:** [What's unclear or broken]
EOF

# 3. Tag for review
git tag "blocker-phase-N-$(date +%Y%m%d)"

# 4. Request guidance
```

---

## Quality Gates

### Before Committing

- [ ] `zig build` succeeds with no errors
- [ ] `zig build test` shows 575+ passing
- [ ] No new warnings introduced
- [ ] Todo list updated
- [ ] Code follows existing patterns

### Before Merging Phase

- [ ] All phase objectives complete
- [ ] Documentation updated
- [ ] Baselines match (if applicable)
- [ ] AccuracyCoin.nes verified
- [ ] Phase summary written

### Before Moving to Next Phase

- [ ] Previous phase 100% complete
- [ ] All blockers resolved
- [ ] Tests passing (575+)
- [ ] Clean git status
- [ ] Next phase reviewed and understood

---

## Tool Reference

### Quick Commands

```bash
# Fast unit tests
zig build test-unit

# Full test suite
zig build test

# Debug tests only
zig build test-debug

# Specific test file
zig test tests/cpu/instructions_test.zig --dep RAMBO -Mroot=src/root.zig

# Build release binary
zig build -Doptimize=ReleaseFast

# Run emulator
zig build run

# Capture baseline
bash scripts/capture-baseline.sh

# Compare baselines
diff baseline/cpu_trace.log current-trace.log
```

### Git Workflow

```bash
# Create phase tag
git tag "pre-phase-N"

# Incremental commits
git add [files]
git commit -m "phase N: [what changed]"

# Phase complete
git add -A
git commit -m "feat(phase-N): [Phase Name] complete"

# Push (if remote configured)
git push origin main --tags
```

---

## References

- **Master Plan:** [`CLEANUP-PLAN-2025-10-05.md`](CLEANUP-PLAN-2025-10-05.md)
- **Progress Tracker:** [`DEVELOPMENT-PROGRESS.md`](DEVELOPMENT-PROGRESS.md)
- **Subagent Findings:** [`SUBAGENT-ANALYSIS.md`](SUBAGENT-ANALYSIS.md)
- **CLAUDE.md:** [`../../CLAUDE.md`](../../CLAUDE.md)

---

**Last Updated:** 2025-10-05
**Status:** Phase 0 complete, procedures validated ✅
