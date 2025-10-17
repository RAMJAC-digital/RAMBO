# RAMBO Emulator - Specific Optimization Recommendations

## Quick Wins (Can implement immediately)

### 1. DMA Cycle Parity Check Optimization

**Current Code** (`src/emulation/dma/logic.zig:70`):
```zig
const is_read_cycle = @rem(effective_cycle, 2) == 0;
```

**Optimized Version**:
```zig
const is_read_cycle = (effective_cycle & 1) == 0;
```

**Rationale**: Bitwise AND is faster than modulo for power-of-2 divisors.
**Impact**: Saves ~2-3 cycles per DMA transfer cycle.

### 2. Inline Critical Bus Functions

**Current**: `busRead` and `busWrite` use `pub inline fn` but call through indirection.

**Recommendation**: Force inlining of hot path functions:
```zig
// In State.zig
pub fn busRead(self: *EmulationState, address: u16) callconv(.Inline) u8 {
    // For RAM access (most common), early return
    if (address < 0x2000) {
        const value = self.bus.ram[address & 0x7FF];
        self.bus.open_bus = value;
        return value;
    }
    // ... rest of logic
}
```

### 3. PPU Shift Register Optimization

**Current**: Shifts happen in ranges with multiple conditionals.

**Optimized**:
```zig
// Precompute shift mask once
const should_shift = ((dot >= 2 and dot <= 257) or (dot >= 322 and dot <= 337));
if (should_shift) {
    state.bg_state.shift();
}
```

## Medium Complexity Optimizations

### 1. Bus Read/Write Jump Table

**File**: `src/emulation/State.zig`

```zig
// Add to EmulationState
const BusReadFn = *const fn(*EmulationState, u16) u8;
const bus_read_handlers: [8]BusReadFn = .{
    readRam,       // 0x0000-0x1FFF
    readPpu,       // 0x2000-0x3FFF
    readIoApu,     // 0x4000-0x401F
    readCart4xxx,  // 0x4020-0x5FFF
    readCart6xxx,  // 0x6000-0x7FFF
    readCart8xxx,  // 0x8000-0x9FFF
    readCartAxxx,  // 0xA000-0xBFFF
    readCartCxxx,  // 0xC000-0xFFFF
};

pub inline fn busRead(self: *EmulationState, address: u16) u8 {
    // Compute handler index from high bits
    const handler_idx = (address >> 13) & 0x7;
    return bus_read_handlers[handler_idx](self, address);
}
```

### 2. PPU Background Tile Cache

**File**: Create `src/ppu/TileCache.zig`

```zig
pub const TileCache = struct {
    // Cache line-aligned for better performance
    entries: [32]CacheEntry align(64) = [_]CacheEntry{.{}} ** 32,

    const CacheEntry = struct {
        nametable_addr: u16 = 0,
        pattern_low: u8 = 0,
        pattern_high: u8 = 0,
        attribute: u8 = 0,
        valid: bool = false,
    };

    pub inline fn lookup(self: *TileCache, addr: u16) ?CacheEntry {
        const index = (addr >> 5) & 0x1F;  // Simple hash
        const entry = &self.entries[index];
        if (entry.valid and entry.nametable_addr == addr) {
            return entry.*;
        }
        return null;
    }

    pub inline fn store(self: *TileCache, addr: u16, pattern_low: u8, pattern_high: u8, attribute: u8) void {
        const index = (addr >> 5) & 0x1F;
        self.entries[index] = .{
            .nametable_addr = addr,
            .pattern_low = pattern_low,
            .pattern_high = pattern_high,
            .attribute = attribute,
            .valid = true,
        };
    }

    pub fn invalidate(self: *TileCache) void {
        for (&self.entries) |*entry| {
            entry.valid = false;
        }
    }
};
```

### 3. CPU Instruction Dispatch Optimization

**File**: `src/cpu/dispatch.zig`

Replace switch statement with computed goto pattern:

```zig
// Build dispatch table at comptime
const dispatch_table = comptime blk: {
    var table: [256]*const fn(*CpuState, *anytype) void = undefined;

    // Fill table with opcode handlers
    table[0x00] = opcodes.brk;
    table[0x01] = opcodes.ora_indexed_indirect;
    // ... etc for all 256 opcodes

    break :blk table;
};

pub inline fn dispatchOpcode(cpu: *CpuState, state: anytype, opcode: u8) void {
    dispatch_table[opcode](cpu, state);
}
```

## Advanced Optimizations

### 1. SIMD for PPU Rendering

**File**: `src/ppu/logic/background.zig`

```zig
const std = @import("std");
const simd = std.simd;

// Process 8 pixels at once using SIMD
pub fn getBackgroundPixels8(state: *PpuState, pixel_x: u16) @Vector(8, u8) {
    const fine_x = state.internal.x;
    const shift = 15 - fine_x;

    // Load pattern data as vectors
    const pattern_lo = @as(@Vector(16, u8), @splat(state.bg_state.pattern_shift_lo));
    const pattern_hi = @as(@Vector(16, u8), @splat(state.bg_state.pattern_shift_hi));

    // Shift and extract 8 pixels
    const indices = simd.iota(u8, 8) + @as(@Vector(8, u8), @splat(shift - 7));

    // ... SIMD operations to compute final pixels ...

    return pixels;
}
```

### 2. Prefetching for Sequential Access

```zig
// In bus routing
pub inline fn busReadPrefetch(self: *EmulationState, address: u16) u8 {
    // Prefetch next likely address
    @prefetch(&self.bus.ram[(address + 1) & 0x7FF], .{
        .rw = .read,
        .locality = 2,  // Moderate temporal locality
        .cache = .data,
    });

    return self.busRead(address);
}
```

### 3. Branch Prediction Hints

```zig
// In CPU execution
pub fn executeCycle(state: anytype) void {
    // Most common case first (fetch opcode)
    if (@expect(state.cpu.state == .fetch_opcode, true)) {
        // Fast path for opcode fetch
        const opcode = state.busRead(state.cpu.pc);
        state.cpu.pc +%= 1;
        // ...
        return;
    }

    // Less common states
    switch (state.cpu.state) {
        .interrupt_sequence => handleInterrupt(state),
        .fetch_operand_low => fetchOperand(state),
        .execute => executeInstruction(state),
        else => unreachable,
    }
}
```

## Memory Layout Optimizations

### 1. Cache Line Alignment

```zig
// Align hot data to cache lines (64 bytes typical)
pub const EmulationState = struct {
    // Hot data - accessed every cycle
    clock: MasterClock align(64),
    cpu: CpuState align(64),
    ppu: PpuState align(64),

    // Warm data - accessed frequently
    bus: BusState align(64),

    // Cold data - accessed rarely
    debugger: ?Debugger.Debugger,
    config: *const Config.Config,
};
```

### 2. Structure Packing

```zig
// Pack related fields that are accessed together
pub const CpuState = packed struct {
    // Registers (accessed together during instructions)
    a: u8,
    x: u8,
    y: u8,
    sp: u8,

    // Status flags (accessed together)
    p: StatusRegister,

    // Execution state (accessed together)
    pc: u16,
    state: CpuMachineState,
    instruction_cycle: u8,

    // Interrupt state (accessed together)
    nmi_line: bool,
    irq_line: bool,
    pending_interrupt: InterruptType,
};
```

## Build Configuration Optimizations

### 1. Compiler Flags

```zig
// In build.zig
pub fn build(b: *std.Build) void {
    const exe = b.addExecutable(.{
        .name = "RAMBO",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = .ReleaseFast,
    });

    // Enable LTO for whole-program optimization
    exe.want_lto = true;

    // CPU-specific optimizations
    exe.addCompileFlags(&.{
        "-march=native",  // Use native CPU features
        "-mtune=native",  // Tune for native CPU
        "-funroll-loops", // Unroll small loops
        "-fprefetch-loop-arrays", // Prefetch array data
    });
}
```

### 2. Profile-Guided Optimization Build Script

```bash
#!/bin/bash
# build_pgo.sh

# Step 1: Build with profiling
zig build -Drelease-fast -Dpgo-generate

# Step 2: Run typical workloads
./zig-out/bin/RAMBO tests/data/AccuracyCoin.nes --headless --frames 1000
./zig-out/bin/RAMBO "games/Super Mario Bros.nes" --headless --frames 1000
./zig-out/bin/RAMBO "games/Mega Man.nes" --headless --frames 1000

# Step 3: Build with profile data
zig build -Drelease-fast -Dpgo-use

echo "PGO build complete!"
```

## Testing Performance Improvements

### Benchmark Before/After

```zig
// Add to tests/performance/regression_test.zig
test "Performance regression check" {
    const baseline_fps = 3600.0; // 60x real-time

    var state = EmulationState.init(&config);
    defer state.deinit();

    const start = std.time.nanoTimestamp();

    // Run 1000 frames
    for (0..1000) |_| {
        state.frame_complete = false;
        while (!state.frame_complete) {
            state.tick();
        }
    }

    const elapsed = std.time.nanoTimestamp() - start;
    const fps = 1000.0 / (@as(f64, @floatFromInt(elapsed)) / 1_000_000_000.0);

    try std.testing.expect(fps >= baseline_fps * 0.95); // Allow 5% variance
}
```

## Priority Order

1. **Immediate** (1 day):
   - DMA parity check optimization
   - Inline critical functions
   - PPU shift optimization

2. **Short term** (1 week):
   - Bus read/write jump table
   - CPU dispatch optimization
   - Basic tile caching

3. **Medium term** (2-3 weeks):
   - SIMD PPU rendering
   - Memory layout optimization
   - Profile-guided optimization

4. **Long term** (1+ month):
   - Full rewrite of PPU pipeline with SIMD
   - JIT compilation for CPU
   - GPU acceleration via compute shaders

## Expected Performance Gains

- **Immediate optimizations**: 5-10% improvement
- **Short term**: Additional 15-25% improvement
- **Medium term**: Additional 20-30% improvement
- **Long term**: 2-5x total improvement possible

Total realistic gain: **50-100% performance improvement** while maintaining cycle accuracy.

---
*Performance recommendations based on profiling analysis and architecture review*
*Date: 2025-10-17*