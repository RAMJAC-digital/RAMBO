# Debugger Isolation Architecture

This document describes the complete isolation architecture between the debugger and runtime systems in RAMBO. The debugger uses an external wrapper pattern with zero shared mutable state, ensuring complete independence between debugging operations and emulation execution.

## Design Goals

### Primary Objectives

1. **Zero Shared Mutable State**: Debugger and runtime must have completely separate state with no shared mutable data structures
2. **RT-Safety Preservation**: Debugger operations must never introduce race conditions or blocking in the runtime hot path
3. **Side-Effect Isolation**: Read operations must not affect hardware state (e.g., open bus updates)
4. **Compile-Time Guarantees**: Use const parameters to enforce isolation at compile time where possible

### External Wrapper Pattern

The debugger wraps `EmulationState` without modifying its internals:

```zig
pub const Debugger = struct {
    allocator: std.mem.Allocator,
    config: *const Config,  // const pointer - read-only

    // Debugger-owned state (ISOLATED)
    breakpoints: ArrayList(Breakpoint),
    watchpoints: ArrayList(Watchpoint),
    modifications: ArrayList(StateModification),
    history: ArrayList(HistoryEntry),
    mode: DebugMode,

    // EmulationState is EXTERNAL - debugger doesn't store it
};
```

Key architectural decisions:
- **No EmulationState field**: Debugger doesn't own or store the runtime state
- **Parameters, not storage**: Functions accept `*EmulationState` or `*const EmulationState` as parameters
- **Const when possible**: Read operations use `*const EmulationState` for compile-time safety

## Isolation Guarantees

### 1. State Mutation Isolation

**Guarantee**: Debugger state changes do NOT affect runtime state.

**Implementation**:
- Breakpoints stored in `debugger.breakpoints` (separate ArrayList)
- Watchpoints stored in `debugger.watchpoints` (separate ArrayList)
- Modification history in `debugger.modifications` (separate ArrayList)
- Debug mode in `debugger.mode` (debugger-owned field)

**Test Coverage**: `test "Isolation: Debugger state changes don't affect runtime"`

```zig
// Add breakpoints, watchpoints, change mode
debugger.addBreakpoint(0x8100, .execute);
debugger.addWatchpoint(0x0200, 1, .write);
debugger.mode = .paused;

// ✅ Runtime state (PC, A, SP, open bus) UNCHANGED
```

### 2. Runtime Execution Isolation

**Guarantee**: Runtime execution does NOT corrupt debugger state.

**Implementation**:
- Breakpoints/watchpoints stored separately from runtime
- Direct runtime state changes (not via debugger) don't auto-log to modification history
- Runtime can modify CPU/bus/PPU state without affecting debugger data structures

**Test Coverage**: `test "Isolation: Runtime execution doesn't corrupt debugger state"`

```zig
// Direct runtime manipulation (NOT via debugger)
state.cpu.a = 0x99;
state.cpu.pc = 0x8050;
state.bus.write(0x0200, 0xFF);

// ✅ Breakpoint count UNCHANGED
// ✅ Modification history UNCHANGED (runtime ops don't auto-log)
```

### 3. Breakpoint Storage Isolation

**Guarantee**: Breakpoint/watchpoint data structures are isolated from runtime memory operations.

**Implementation**:
- Breakpoints stored in debugger-owned ArrayList
- Runtime memory writes/reads at breakpoint addresses don't affect breakpoint storage
- CPU execution at breakpoint PC doesn't modify breakpoint data

**Test Coverage**: `test "Isolation: Breakpoint state isolation from runtime"`

```zig
// Runtime operations at breakpoint addresses
state.cpu.pc = 0x8000;           // PC at breakpoint
state.bus.write(0x8010, 0xFF);   // Write to breakpoint
_ = state.bus.read(0x8020);      // Read from breakpoint

// Execute 100 CPU cycles
for (0..100) |_| {
    _ = CpuLogic.tick(&state.cpu, &state.bus);
}

// ✅ Breakpoint count and addresses UNCHANGED
```

### 4. Modification History Isolation

**Guarantee**: Modification history only logs debugger-initiated changes, not runtime execution.

**Implementation**:
- `logModification()` is private - only called by debugger public methods
- Direct state mutations (e.g., `state.cpu.a = 0x99`) don't trigger logging
- History is explicit tracking of debugger intent, not runtime side effects

**Test Coverage**: `test "Isolation: Modification history isolation from runtime"`

```zig
// Direct runtime operations (NOT via debugger)
state.cpu.a = 0x99;
state.cpu.x = 0x88;
state.cpu.pc = 0x9000;
state.bus.write(0x0300, 0xFF);

// ✅ Modification count UNCHANGED
// ✅ Original debugger modifications preserved
```

### 5. Side-Effect-Free Reading (Compile-Time)

**Guarantee**: Memory inspection does NOT affect hardware state (open bus).

**Implementation**:
- `readMemory()` accepts `*const EmulationState` (const pointer)
- Uses `Logic.peekMemory()` instead of `bus.read()` (no open bus update)
- Const parameter provides compile-time guarantee against mutation

**Test Coverage**: `test "Isolation: readMemory() const parameter enforces isolation"`

```zig
// const state prevents mutation (compile-time guarantee)
const const_state: *const EmulationState = &state;
const value = debugger.readMemory(const_state, 0x0200);

// ✅ Open bus value UNCHANGED
// ✅ Open bus cycle UNCHANGED
// ✅ If readMemory tried to mutate, would be compile error
```

### 6. Hook Function Isolation (Compile-Time)

**Guarantee**: Hook functions receive read-only state snapshots.

**Implementation**:
- `shouldBreak()` operates on state snapshot without mutation
- Breakpoint condition checks don't modify CPU/bus/PPU state
- Future user-defined hooks will receive `*const EmulationState`

**Test Coverage**: `test "Isolation: shouldBreak() doesn't mutate state"`

```zig
// shouldBreak checks breakpoints without mutation
const should_break = try debugger.shouldBreak(&state);

// ✅ CPU registers UNCHANGED
// ✅ Open bus UNCHANGED
// ✅ All hardware state preserved
```

## RT-Safety Through Isolation

### Zero Hot-Path Interference

Complete isolation means debugger operations can NEVER introduce:
- **Race Conditions**: No shared mutable state means no data races
- **Blocking**: Debugger has its own allocator, never blocks runtime
- **Undefined Behavior**: Const parameters prevent accidental mutation

### Allocation Separation

```zig
// Debugger uses its own allocator
debugger.allocator  // For breakpoints, history, modifications

// Runtime uses separate allocator (future: RT-safe allocator)
runtime.allocator   // For emulation state, bus, CPU
```

This allows future RT-safe runtime allocator without affecting debugger.

### Hot Path Analysis

Runtime hot path (`CpuLogic.tick()`) has:
- **Zero debugger dependencies**: No debugger imports or calls
- **Zero shared state**: CPU/bus/PPU state independent of debugger
- **Zero heap allocations**: (current implementation - to be enforced)

Debugger can `shouldBreak()` on hot path, but:
- Uses pre-allocated buffer for break reasons (no heap allocation)
- Read-only state access (const parameters)
- No runtime state mutation

## Memory Layout

### Separate Address Spaces

```
Debugger Memory:
├── breakpoints: ArrayList<Breakpoint>      (heap)
├── watchpoints: ArrayList<Watchpoint>      (heap)
├── modifications: ArrayList<Modification>  (heap)
├── history: ArrayList<HistoryEntry>        (heap)
├── break_reason_buffer: [256]u8           (stack - RT-safe)
└── (all owned by debugger.allocator)

Runtime Memory:
├── EmulationState
│   ├── cpu: CpuState                       (stack/static)
│   ├── bus: BusState                       (stack/static)
│   └── ppu: PpuState                       (stack/static)
└── (all owned by runtime.allocator)

ZERO OVERLAP - Complete Isolation
```

### Pointer Ownership

```zig
// Debugger receives state as PARAMETER (borrowed reference)
pub fn readMemory(self: *Debugger, state: *const EmulationState, address: u16) u8

// Debugger NEVER stores state pointer
// State lifetime managed externally
// No ownership, no cleanup, no corruption risk
```

## Testing Strategy

### Test Categories

1. **Zero-Shared-State Tests (4 tests)**
   - Debugger changes don't affect runtime
   - Runtime execution doesn't corrupt debugger
   - Breakpoint storage isolation
   - Modification history isolation

2. **Hook Isolation Tests (2 tests)**
   - readMemory() const parameter enforcement
   - shouldBreak() state preservation

### Verification Methods

#### Compile-Time Verification

```zig
// Const parameters prevent mutation at COMPILE TIME
pub fn readMemory(
    self: *Debugger,
    state: *const EmulationState,  // ← CONST - compile error if mutated
    address: u16,
) u8
```

If implementation tried: `state.bus.open_bus.value = 0xFF;`
Compiler error: `error: cannot assign to constant`

#### Runtime Verification

```zig
// Capture state before operation
const orig_value = state.cpu.a;

// Perform debugger operation
debugger.readMemory(&state, 0x0200);

// Verify state unchanged
try testing.expectEqual(orig_value, state.cpu.a);
```

## Future Enhancements

### User-Defined Hooks

Future callback system will maintain isolation:

```zig
pub const BreakpointHook = fn(state: *const EmulationState) bool;

pub fn setBreakpointHook(
    self: *Debugger,
    address: u16,
    hook: BreakpointHook,  // Receives CONST state
) void
```

User hooks receive `*const EmulationState`, preventing mutation.

### Parallel Execution

Isolation enables future parallel debugger:

```zig
// Runtime thread (RT-safe, no blocking)
while (true) {
    CpuLogic.tick(&state.cpu, &state.bus);
}

// Debugger thread (separate, async)
while (true) {
    if (debugger.shouldBreak(&state)) {
        // Pause runtime, inspect state
    }
}
```

Zero shared mutable state means no synchronization needed for reads.

## API Reference

### Isolated Read Operations

```zig
/// Read memory without side effects (const state)
pub fn readMemory(
    self: *Debugger,
    state: *const EmulationState,
    address: u16,
) u8

/// Read memory range without side effects (const state)
pub fn readMemoryRange(
    self: *Debugger,
    state: *const EmulationState,
    start: u16,
    length: usize,
) []const u8
```

### Isolated Write Operations

```zig
/// Write memory via debugger (logs to modification history)
pub fn writeMemory(
    self: *Debugger,
    state: *EmulationState,  // Mutable - debugger initiates change
    address: u16,
    value: u8,
) void

/// Modifications stored in debugger.modifications (ISOLATED)
pub fn getModifications(self: *const Debugger) []const StateModification
```

### Isolated Breakpoint Management

```zig
/// Add breakpoint (stored in debugger.breakpoints - ISOLATED)
pub fn addBreakpoint(
    self: *Debugger,
    address: u16,
    bp_type: BreakpointType,
) !void

/// Breakpoints stored separately from runtime memory
pub const breakpoints: ArrayList(Breakpoint)
```

## Best Practices

### For Debugger Development

1. **Never store EmulationState**: Always pass as parameter
2. **Use const for reads**: `*const EmulationState` for inspection
3. **Separate allocators**: Never mix debugger/runtime allocations
4. **Private logging**: Keep `logModification()` private

### For Runtime Development

1. **Ignore debugger**: Runtime code should never import debugger
2. **Direct mutations allowed**: `state.cpu.a = value` is fine (won't auto-log)
3. **No debugger dependencies**: Keep hot path clean

### For Integration

1. **External coordination**: Caller manages both debugger and runtime
2. **Explicit logging**: Only debugger methods log modifications
3. **Borrowed references**: State passed as parameter, not stored

## Summary

The RAMBO debugger achieves complete isolation through:

✅ **External wrapper pattern** - No EmulationState storage in debugger
✅ **Separate allocators** - Zero shared heap allocations
✅ **Const parameters** - Compile-time mutation prevention
✅ **Private logging** - Explicit modification tracking
✅ **Independent storage** - Breakpoints/history in separate data structures
✅ **Side-effect-free reads** - peekMemory() instead of read()

This architecture enables:
- **RT-safety**: No blocking, no races, no undefined behavior
- **Time-travel debugging**: Side-effect-free state inspection
- **TAS workflows**: Intentional corruption without runtime interference
- **Future parallelism**: Zero shared state enables concurrent execution

**Test Coverage**: 6 isolation tests, all passing
**Compiler Enforcement**: Const parameters prevent mutation at compile time
**Runtime Verification**: Tests confirm zero state corruption
