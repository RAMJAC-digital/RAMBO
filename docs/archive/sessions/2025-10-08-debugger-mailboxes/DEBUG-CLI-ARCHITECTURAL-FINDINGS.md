# Debug CLI Integration - Architectural Findings & Implementation Plan

**Date:** 2025-10-08
**Status:** 📋 **PLANNING** - Research Complete, Ready for Test-First Implementation
**Agent Reviews:** 3 agents (architect-reviewer, performance-engineer, test-automator)

---

## Executive Summary

**Problem:** Commercial ROMs don't run despite complete NMI/IRQ implementation. Need debug CLI to investigate.

**Initial Approach (WRONG):** Rushed into zli integration without understanding threading model, RT-safety constraints, or proper debugger integration patterns.

**Findings:** The architecture is well-designed for debugging, but requires:
1. Passing Debugger pointer through EmulationThread spawn
2. Adding hook points in emulation loop
3. Maintaining RT-safety (no heap allocations in hot path)
4. Test-first development with 36 tests

**Key Insight:** `zli.mainExec` IS the real main function - blocking is normal and correct.

---

## 1. Threading Architecture (From architect-reviewer)

### Current 3-Thread Model

```
Main Thread (Coordinator)
├── Runs libxev event loop (non-blocking poll)
├── Orchestrates mailbox communication
├── Handles input events → ButtonState mailbox
└── Spawns:
    ├── EmulationThread (libxev timer-driven, 60Hz RT loop)
    └── RenderThread (Wayland/Vulkan)
```

### Key Architectural Facts

**✅ Main Thread CAN Block:**
- `main.zig:244`: Creates libxev loop
- `main.zig:307`: Runs `loop.run(.no_wait)` in polling loop
- `main.zig:310`: Uses `std.Thread.sleep(100_000_000)` - 100ms polling interval
- **Implication:** zli blocking in main() before thread spawn is acceptable

**✅ EmulationThread is RT-Safe:**
- `EmulationThread.zig:229`: Uses libxev timer callbacks
- No heap allocations after initialization
- Timer-driven at 60Hz (16.6ms per frame)
- All communication via lock-free mailboxes

**✅ Communication is Unidirectional:**
- Mailboxes use atomics (SPSC lock-free)
- No shared mutable state between threads
- Main → Emulation: Controller input, config updates
- Emulation → Main: Frame data, statistics

### Critical Constraint: libxev Consistency

**User requirement:** "We need to make sure our threading model uses the libxev api"

- ✅ Main thread: libxev event loop
- ✅ EmulationThread: libxev timer callbacks
- ✅ RenderThread: libxev Wayland integration
- ❌ Avoid: Raw `std.Thread.sleep()` should only be in coordination loops

---

## 2. Debugger Integration Pattern (From architect-reviewer)

### Correct Usage (from `tests/debugger/debugger_test.zig`)

```zig
// 1. Create Debugger OUTSIDE EmulationState (in main thread)
var debugger = Debugger.init(allocator, &config);
defer debugger.deinit();

// 2. Set breakpoints BEFORE spawning threads (setup phase)
try debugger.addBreakpoint(0x8000, .execute);
try debugger.addWatchpoint(0x2000, 1, .write);

// 3. Pass pointer to EmulationThread
const emulation_thread = try EmulationThread.spawn(
    &emu_state,
    &mailboxes,
    &running,
    &debugger  // ← Pass debugger pointer
);

// 4. Hook into execution loop (RT-safe checks)
fn timerCallback(...) {
    if (ctx.debugger) |dbg| {
        if (dbg.shouldBreak(&ctx.state) catch false) {
            // Breakpoint hit - handle it
        }
    }
}
```

### Why This Design?

**External Wrapper Pattern** (`Debugger.zig:1-30`):
- Does NOT modify EmulationState internals
- Read-only access to state (`*const EmulationState`)
- Uses callbacks for user hooks
- Designed for minimal overhead

**RT-Safe Constraints:**
- `shouldBreak()`: Uses stack buffers, no allocations
- `checkMemoryAccess()`: No allocations
- Callbacks receive const state only
- Break reason stored in fixed 128-byte buffer

---

## 3. RT-Safety Violations Found (From performance-engineer)

### ❌ CRITICAL: Debugger is NOT RT-Safe

**Problem** (`Debugger.zig:175, 178`):
```zig
breakpoints: std.ArrayList(Breakpoint),  // ← Heap allocations
watchpoints: std.ArrayList(Watchpoint),  // ← Heap allocations
```

**Impact:**
- `addBreakpoint()` calls `ArrayList.append()` - allocates
- `removeBreakpoint()` reallocates array
- Violates RT-safety if called from EmulationThread

**Solution:**
- Pre-allocate fixed arrays: `breakpoints: [256]?Breakpoint = .{null} ** 256`
- Add breakpoints in main thread BEFORE spawning EmulationThread
- Never add/remove breakpoints from RT thread

### ⚠️ MINOR: Debug Prints in Hot Path

**Found in:**
- `EmulationState.zig:703` - Rendering enable detection
- `EmulationState.zig:1050-1053` - RMW error handling
- `EmulationThread.zig:108-123, 139-143` - Frame statistics

**Impact:**
- `std.debug.print()` can block on I/O
- Causes timing jitter in RT loop
- Breaks determinism

**Solution:**
- Use comptime debug flags
- Buffer debug output, flush periodically from main thread
- Or remove entirely for production builds

### ⚠️ MINOR: Main Thread Polling Too Slow

**Problem** (`main.zig:310`):
```zig
std.Thread.sleep(100_000_000); // 100ms
```

**Impact:**
- Input latency: 100ms vs 16.6ms frame time
- 6 frames of input lag at 60 FPS
- Unresponsive controls

**Solution:**
```zig
std.Thread.sleep(16_666_666); // 16.6ms for 60Hz polling
```

---

## 4. CLI Integration Architecture (Corrected)

### ✅ CORRECT: zli Blocks in main()

```zig
pub fn main() !void {
    // Setup stdout writer
    const stdout_file = std.fs.File{ .handle = std.posix.STDOUT_FILENO };
    var buffer: [4096]u8 = undefined;
    var file_writer = stdout_file.writer(&buffer);

    // Create zli command
    const app = try zli.Command.init(&file_writer.interface, allocator, ...);

    // This BLOCKS until mainExec returns - THAT'S CORRECT!
    try app.execute(.{});

    // Flush output
    try file_writer.interface.flush();
}
```

**Why This is Correct:**
- `app.execute()` parses args → calls `mainExec` → waits for return
- `mainExec` IS the real main function - it spawns threads and runs emulation
- zli's blocking is ONE-TIME at startup, not in runtime loop
- Entire emulation runs INSIDE the command handler

### State Management Flow

```
main()
  ↓
zli.execute() [BLOCKS]
  ↓
mainExec(ctx: CommandContext)
  ↓
1. Parse debug flags from ctx
2. Create Debugger (if needed)
3. Set breakpoints from --break-at
4. Set limits from --cycles/--frames
5. Spawn EmulationThread (pass Debugger pointer)
6. Spawn RenderThread
7. Run libxev loop (coordinator)
8. Wait for threads
9. RETURN (unblocks zli.execute)
  ↓
Flush output
  ↓
Exit
```

---

## 5. Implementation Architecture

### Thread Communication Model

```
┌─────────────────────────────────────┐
│         Main Thread                 │
│  - Parse CLI args (zli)             │
│  - Create Debugger                  │
│  - Set breakpoints (setup phase)    │
│  - Spawn threads                    │
│  - Run libxev coordinator loop      │
└────────────┬────────────────────────┘
             │
             │ Pass Debugger pointer
             ↓
┌─────────────────────────────────────┐
│      EmulationThread (RT-safe)      │
│  - libxev timer callback (60Hz)     │
│  - Call debugger.shouldBreak()      │
│  - Check cycle/frame limits         │
│  - Emulate frame with debug hooks   │
│  - NEVER add/remove breakpoints     │
└─────────────────────────────────────┘
```

### File Modifications Required

#### 1. `src/threads/EmulationThread.zig`

**Changes:**
```zig
// Add Debugger pointer to context
pub const EmulationContext = struct {
    state: *EmulationState,
    mailboxes: *Mailboxes,
    running: *std.atomic.Value(bool),
    debugger: ?*Debugger = null,  // ← ADD THIS
    total_cycles: u64 = 0,        // ← ADD THIS (for cycle limit)
};

// Update spawn signature
pub fn spawn(
    state: *EmulationState,
    mailboxes: *Mailboxes,
    running: *std.atomic.Value(bool),
    debugger: ?*Debugger,  // ← ADD THIS
) !std.Thread {
    // ... pass debugger to context
}

// Update timerCallback to check debug limits
fn timerCallback(...) xev.CallbackAction {
    // Check cycle limit BEFORE emulating frame
    if (ctx.debugger) |dbg| {
        if (dbg.cycle_limit) |limit| {
            if (ctx.total_cycles >= limit) {
                std.debug.print("[Debug] Cycle limit reached\n", .{});
                ctx.running.store(false, .release);
                return .disarm;
            }
        }
    }

    // Emulate frame with or without debugger
    const cycles = if (ctx.debugger) |dbg|
        ctx.state.emulateFrameWithDebugger(dbg)
    else
        ctx.state.emulateFrame();

    ctx.total_cycles += cycles;
    // ...
}
```

**Lines to modify:** ~50 lines total

#### 2. `src/emulation/State.zig`

**Add method:**
```zig
/// Emulate one frame with debugger hooks (RT-safe)
pub fn emulateFrameWithDebugger(self: *EmulationState, debugger: *Debugger) u64 {
    const start_frame = self.clock.frame();
    const start_cycles = self.clock.cpuCycles();

    while (self.clock.frame() == start_frame) {
        // Check breakpoints before each instruction
        if (self.cpu.state == .fetch_opcode) {
            if (debugger.shouldBreak(self) catch false) {
                std.debug.print("[Debug] Break at PC=${X:0>4}\n", .{self.cpu.pc});
                // Could set flag or return early
                break;
            }
        }

        self.tick();
    }

    return self.clock.cpuCycles() - start_cycles;
}
```

**Lines to add:** ~25 lines

#### 3. `src/main.zig` (mainExec function)

**Changes:**
```zig
fn mainExec(ctx: zli.CommandContext) !void {
    // ... parse debug flags (ALREADY DONE) ...

    // Create Debugger if any debug flags set
    var debugger: ?Debugger = null;
    defer if (debugger) |*dbg| dbg.deinit();

    if (debug_flags.trace or debug_flags.break_at != null or
        debug_flags.watch != null or debug_flags.cycles != null or
        debug_flags.frames != null) {

        debugger = Debugger.init(allocator, &config);

        // Set breakpoints from CLI
        if (debug_flags.break_at) |addrs| {
            for (addrs) |addr| {
                try debugger.?.addBreakpoint(addr, .execute);
            }
        }

        // Set watchpoints from CLI
        if (debug_flags.watch) |addrs| {
            for (addrs) |addr| {
                try debugger.?.addWatchpoint(addr, 1, .write);
            }
        }

        // Set limits (stored in Debugger for timerCallback access)
        debugger.?.cycle_limit = debug_flags.cycles;
        debugger.?.frame_limit = debug_flags.frames;

        if (debug_flags.verbose) {
            std.debug.print("[Debug] Debugger initialized\n", .{});
            if (debug_flags.break_at) |addrs| {
                std.debug.print("[Debug] Breakpoints: ", .{});
                for (addrs) |addr| std.debug.print("${X:0>4} ", .{addr});
                std.debug.print("\n", .{});
            }
        }
    }

    // ... initialize emulation state ...

    // Spawn threads with Debugger pointer
    const emulation_thread = try EmulationThread.spawn(
        &emu_state,
        &mailboxes,
        &running,
        if (debugger) |*dbg| dbg else null  // ← Pass pointer
    );

    // ... rest of main loop ...

    // On exit, if --inspect flag set, print final state
    if (debug_flags.inspect and debugger != null) {
        printDebugState(&emu_state, &debugger.?);
    }
}

fn printDebugState(state: *const EmulationState, debugger: *const Debugger) void {
    std.debug.print("\n=== Final Emulation State ===\n", .{});
    std.debug.print("CPU:\n", .{});
    std.debug.print("  PC: ${X:0>4}\n", .{state.cpu.pc});
    std.debug.print("  A:  ${X:0>2}\n", .{state.cpu.a});
    std.debug.print("  X:  ${X:0>2}\n", .{state.cpu.x});
    std.debug.print("  Y:  ${X:0>2}\n", .{state.cpu.y});
    std.debug.print("  SP: ${X:0>2}\n", .{state.cpu.sp});
    std.debug.print("  P:  ${X:0>2} [", .{@as(u8, @bitCast(state.cpu.p))});
    if (state.cpu.p.n) std.debug.print("N", .{}) else std.debug.print("-", .{});
    if (state.cpu.p.v) std.debug.print("V", .{}) else std.debug.print("-", .{});
    std.debug.print("-", .{}); // Unused
    if (state.cpu.p.b) std.debug.print("B", .{}) else std.debug.print("-", .{});
    if (state.cpu.p.d) std.debug.print("D", .{}) else std.debug.print("-", .{});
    if (state.cpu.p.i) std.debug.print("I", .{}) else std.debug.print("-", .{});
    if (state.cpu.p.z) std.debug.print("Z", .{}) else std.debug.print("-", .{});
    if (state.cpu.p.c) std.debug.print("C", .{}) else std.debug.print("-", .{});
    std.debug.print("]\n", .{});

    std.debug.print("\nPPU:\n", .{});
    std.debug.print("  Scanline: {d}\n", .{state.ppu.scanline});
    std.debug.print("  Dot:      {d}\n", .{state.ppu.dot});
    std.debug.print("  Frame:    {d}\n", .{state.clock.frame()});

    std.debug.print("\nDebugger Stats:\n", .{});
    std.debug.print("  Breakpoints hit: {d}\n", .{debugger.stats.breakpoints_hit});
    std.debug.print("  Watchpoints hit: {d}\n", .{debugger.stats.watchpoints_hit});
}
```

**Lines to add:** ~100 lines

#### 4. `src/debugger/Debugger.zig`

**Add fields:**
```zig
pub const Debugger = struct {
    // ... existing fields ...

    // Add cycle/frame limits (accessible from EmulationThread)
    cycle_limit: ?u64 = null,
    frame_limit: ?u64 = null,

    // ... rest of struct ...
};
```

**Lines to add:** 2 lines

---

## 6. Test-First Development Plan (From test-automator)

### Test File Structure (36 tests total)

```
tests/cli/                                # 24 tests
├── args_parsing_test.zig                 # 11 tests - parseHexArray validation
├── debug_flags_test.zig                  # 6 tests - Flag combinations
└── error_handling_test.zig               # 7 tests - Error conditions

tests/integration/                        # 12 tests
├── debug_cli_integration_test.zig        # 4 tests - Full workflows
├── debug_limits_test.zig                 # 3 tests - Cycle/frame limits
├── debug_rt_safety_test.zig              # 3 tests - Allocation tracking
└── debug_performance_test.zig            # 2 tests - Benchmarks
```

### Critical Tests (Must Pass Before Merge)

**RT-Safety:**
```zig
test "RT-Safety: debugger check uses no heap allocation" {
    // Track allocations before/after shouldBreak()
    const allocations_before = testing.allocator_instance.total_requested_bytes;
    const should_break = try debugger.shouldBreak(&state);
    const allocations_after = testing.allocator_instance.total_requested_bytes;

    try testing.expectEqual(allocations_before, allocations_after);
}
```

**Performance:**
```zig
test "Performance: <1% overhead with no breakpoints" {
    // Baseline: 10,000 instructions without debugger
    // Test: 10,000 instructions with debugger (no breakpoints)
    // Assert: overhead < 1%
}

test "Performance: 60 FPS maintained with 10 breakpoints" {
    // Execute one frame (29,780 cycles) with 10 active breakpoints
    // Assert: completes within 16.6ms frame budget
}
```

### Test Data Requirements

**Minimal Test ROM** (`tests/fixtures/debug_test.nes`):
```
iNES Header: Mapper 0, 16KB PRG, 8KB CHR
Program at $8000:
  LDA #$42      ; $8000
  STA $10       ; $8002
  LDA #$00      ; $8004
  STA $11       ; $8006
  JMP $8000     ; $8008 (infinite loop)
```

---

## 7. Implementation Phases (Test-First)

### Phase 1: Create Tests (4-5 hours)

**Task:** Implement all 36 tests BEFORE any code changes

**Files to create:**
1. `tests/cli/args_parsing_test.zig` - 11 tests
2. `tests/cli/debug_flags_test.zig` - 6 tests
3. `tests/cli/error_handling_test.zig` - 7 tests (manual verification)
4. `tests/integration/debug_cli_integration_test.zig` - 4 tests
5. `tests/integration/debug_limits_test.zig` - 3 tests
6. `tests/integration/debug_rt_safety_test.zig` - 3 tests
7. `tests/integration/debug_performance_test.zig` - 2 tests
8. `tests/fixtures/debug_test.nes` - Minimal test ROM

**Acceptance:** All tests compile but fail (red phase)

### Phase 2: CLI Argument Parsing (1 hour)

**Task:** Make `args_parsing_test.zig` and `debug_flags_test.zig` pass

**Changes:**
- `src/main.zig`: Fix `parseHexArray` edge cases
- `src/main.zig`: Verify `DebugFlags.deinit()` cleanup

**Acceptance:** 17/36 tests passing

### Phase 3: Thread Integration (2-3 hours)

**Task:** Make integration tests pass

**Changes:**
1. Modify `EmulationThread.zig` - Add Debugger pointer
2. Add `emulateFrameWithDebugger()` to `EmulationState.zig`
3. Integrate Debugger creation in `mainExec()`

**Acceptance:** 29/36 tests passing (all except performance)

### Phase 4: RT-Safety Verification (1 hour)

**Task:** Make RT-safety tests pass

**Changes:**
- Remove `std.debug.print()` from hot paths
- Verify no allocations in `shouldBreak()`

**Acceptance:** 32/36 tests passing

### Phase 5: Performance Optimization (1-2 hours)

**Task:** Make performance tests pass

**Changes:**
- Fix main thread sleep (100ms → 16ms)
- Optimize breakpoint checks if needed

**Acceptance:** 36/36 tests passing ✅

### Phase 6: Manual Testing & Documentation (1 hour)

**Task:** Test with real ROMs and document

**Commands to test:**
```bash
# Test basic execution
./zig-out/bin/RAMBO mario.nes

# Test tracing
./zig-out/bin/RAMBO mario.nes --trace --cycles 1000

# Test breakpoints
./zig-out/bin/RAMBO mario.nes --break-at 0x8000 --inspect

# Test limits
./zig-out/bin/RAMBO mario.nes --frames 10 --inspect
```

**Acceptance:** Commercial ROMs can be debugged

---

## 8. Success Criteria

### Functional Requirements

- [ ] `--help` displays usage correctly
- [ ] `--trace` logs instruction execution
- [ ] `--break-at 0x8000` stops at breakpoint
- [ ] `--watch 0x2000` detects memory writes
- [ ] `--cycles 10000` stops after cycle limit
- [ ] `--frames 100` stops after frame limit
- [ ] `--inspect` prints final state
- [ ] `--verbose` shows debug configuration

### Non-Functional Requirements

- [ ] 36/36 tests passing
- [ ] Zero heap allocations in RT path
- [ ] <1% performance overhead (no breakpoints)
- [ ] 60 FPS maintained with ≤10 breakpoints
- [ ] Main thread input polling ≤16ms
- [ ] All `std.debug.print()` removed from hot paths
- [ ] No regressions (896/900 tests still pass)

### Documentation Requirements

- [ ] Update `CLAUDE.md` with debug CLI usage
- [ ] Create `docs/implementation/DEBUG-CLI-USAGE.md`
- [ ] Add examples to README
- [ ] Document RT-safety guarantees

---

## 9. Risk Mitigation

### Risk 1: Breaking Existing Tests

**Mitigation:**
- Run full test suite after each phase
- Use git branches for isolation
- Automated regression testing

### Risk 2: RT-Safety Violations

**Mitigation:**
- Allocation tracking tests
- Performance benchmarks
- Code review by performance-engineer agent

### Risk 3: Input Latency Issues

**Mitigation:**
- Fix main thread sleep to 16ms
- Benchmark input responsiveness
- User testing with real games

---

## 10. Next Steps

**Immediate Actions:**

1. ✅ Review agent reports (DONE)
2. ✅ Document findings (THIS FILE)
3. ⏳ Create all 36 tests (NEXT - 4-5 hours)
4. ⏳ Implement Phase 2-5 (6-8 hours)
5. ⏳ Manual testing (1 hour)
6. ⏳ Commit and document (30 min)

**Total Estimated Time:** 12-15 hours

**Critical Path:** Tests → Thread Integration → RT-Safety → Performance → Manual Testing

---

## 11. Key Takeaways

1. **zli blocking is NORMAL** - `mainExec` IS the real main function
2. **Debugger must be created in main thread** - passed as pointer to EmulationThread
3. **Never allocate in RT path** - pre-allocate all debugger structures
4. **Test-first is mandatory** - 36 tests before implementation
5. **RT-safety is non-negotiable** - allocation tracking tests must pass
6. **Performance budget is tight** - 16.6ms per frame with debug overhead
7. **libxev is the threading model** - stay consistent with architecture

---

**Status:** ✅ **READY FOR TEST-FIRST IMPLEMENTATION**
**Next Phase:** Create 36 tests (4-5 hours)
**Final Goal:** Investigate why commercial ROMs don't run with proper debug tooling
