# Snapshot System API Guide

Complete guide to using the RAMBO snapshot system for state persistence and debugging.

## Table of Contents

1. [Overview](#overview)
2. [Quick Start](#quick-start)
3. [API Reference](#api-reference)
4. [Binary Format](#binary-format)
5. [Usage Examples](#usage-examples)
6. [Best Practices](#best-practices)
7. [Troubleshooting](#troubleshooting)

## Overview

The RAMBO snapshot system provides complete EmulationState serialization to binary format, enabling:

- **Save States**: Persist complete emulation state for resumption
- **Debugging**: Capture state at specific execution points
- **Testing**: Verify state transitions with known-good snapshots
- **Time Travel**: Save state history for replay/analysis

### Key Features

- **Complete State**: CPU, PPU, Bus, Clock, Config - everything serialized
- **Cross-Platform**: Little-endian format works on any architecture
- **Integrity**: CRC32 checksum detects corruption
- **Flexible Cartridge**: Reference mode (ROM path+hash) or Embed mode (full ROM data)
- **Optional Framebuffer**: Include rendered output (~250KB) or skip (~5KB)
- **Fast**: ~5ms to save/load on modern hardware

### Architecture

```
EmulationState (pure data)
    ↓
saveBinary() → Binary format (72-byte header + state data)
    ↓
File/Network/Memory
    ↓
loadBinary() → Reconstruct EmulationState
    ↓
connectComponents() → Wire internal pointers
```

## Quick Start

### Saving a Snapshot

```zig
const std = @import("std");
const RAMBO = @import("RAMBO");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Setup emulation state
    var config = RAMBO.Config.Config.init(allocator);
    defer config.deinit();

    var state: RAMBO.EmulationState.EmulationState = // ... initialize
    state.connectComponents();

    // Save snapshot (reference mode, no framebuffer)
    const snapshot = try RAMBO.Snapshot.saveBinary(
        allocator,
        &state,
        &config,
        .reference,  // Cartridge mode
        false,       // Include framebuffer
        null,        // Framebuffer data
    );
    defer allocator.free(snapshot);

    // Write to file
    try std.fs.cwd().writeFile(.{
        .sub_path = "save.rambo",
        .data = snapshot,
    });
}
```

### Loading a Snapshot

```zig
pub fn loadSaveState(allocator: std.mem.Allocator, cartridge: *RAMBO.Cartridge.NromCart) !RAMBO.EmulationState.EmulationState {
    // Read snapshot file
    const snapshot = try std.fs.cwd().readFileAlloc(
        allocator,
        "save.rambo",
        10 * 1024 * 1024, // 10MB max
    );
    defer allocator.free(snapshot);

    // Verify integrity
    try RAMBO.Snapshot.verify(snapshot);

    // Setup config (must match snapshot)
    var config = RAMBO.Config.Config.init(allocator);
    defer config.deinit();

    // Load snapshot
    const state = try RAMBO.Snapshot.loadBinary(
        allocator,
        snapshot,
        &config,
        cartridge,  // Provide matching cartridge for reference mode
    );

    return state;
}
```

## API Reference

### `saveBinary()`

Save EmulationState to binary format.

```zig
pub fn saveBinary(
    allocator: std.mem.Allocator,
    state: *const EmulationState,
    config: *const Config.Config,
    cartridge_mode: CartridgeSnapshotMode,
    include_framebuffer: bool,
    framebuffer: ?[]const u8,
) ![]u8
```

**Parameters:**

- `allocator`: Memory allocator for snapshot buffer
- `state`: Emulation state to save
- `config`: Hardware configuration
- `cartridge_mode`:
  - `.reference`: Store ROM path/hash only (~5KB snapshots)
  - `.embed`: Store full ROM data (~40KB+ snapshots, portable)
- `include_framebuffer`: Whether to include rendered frame
- `framebuffer`: Optional 256×240×4 RGBA buffer (required if `include_framebuffer=true`)

**Returns:** Allocated snapshot buffer (caller owns memory)

**Errors:**
- `error.FramebufferRequired`: `include_framebuffer=true` but `framebuffer=null`
- `error.InvalidFramebufferSize`: Framebuffer not exactly 245,760 bytes
- `error.OutOfMemory`: Allocation failure

### `loadBinary()`

Load EmulationState from binary format.

```zig
pub fn loadBinary(
    allocator: std.mem.Allocator,
    data: []const u8,
    config: *const Config.Config,
    cartridge: anytype, // ?*NromCart or *NromCart
) !EmulationState
```

**Parameters:**

- `allocator`: Memory allocator for any dynamic allocations
- `data`: Complete snapshot buffer
- `config`: Hardware configuration (must match snapshot)
- `cartridge`: Optional or non-optional pointer to cartridge
  - For reference mode: Required (unless empty reference)
  - For embed mode: Currently required (TODO: reconstruct from data)

**Returns:** Fully reconstructed EmulationState with pointers connected

**Errors:**
- `error.InvalidSnapshot`: Data too small (<72 bytes)
- `error.InvalidMagic`: Header magic doesn't match "RAMBO\x00\x00\x00"
- `error.UnsupportedVersion`: Version mismatch
- `error.ChecksumMismatch`: Data corruption detected
- `error.ConfigMismatch`: Config incompatible with snapshot
- `error.CartridgeRequired`: Non-empty reference without cartridge

### `verify()`

Verify snapshot integrity without full load.

```zig
pub fn verify(data: []const u8) !void
```

**Parameters:**

- `data`: Snapshot buffer to verify

**Errors:**
- `error.InvalidSnapshot`: Data too small
- `error.InvalidMagic`: Invalid header magic
- `error.UnsupportedVersion`: Version mismatch
- `error.ChecksumMismatch`: CRC32 verification failed

### `getMetadata()`

Get snapshot metadata without full load.

```zig
pub fn getMetadata(data: []const u8) !SnapshotMetadata
```

**Parameters:**

- `data`: Snapshot buffer

**Returns:**

```zig
pub const SnapshotMetadata = struct {
    version: u32,
    timestamp: i64,
    emulator_version: [16]u8,
    total_size: u64,
    state_size: u32,
    cartridge_size: u32,
    framebuffer_size: u32,
    flags: SnapshotFlags,
};
```

**Errors:**
- `error.InvalidSnapshot`: Data too small
- `error.InvalidMagic`: Invalid header
- `error.UnsupportedVersion`: Version mismatch

## Binary Format

### Header (72 bytes)

| Offset | Size | Field | Type | Description |
|--------|------|-------|------|-------------|
| 0 | 8 | Magic | `[8]u8` | "RAMBO\x00\x00\x00" |
| 8 | 4 | Version | `u32` | Format version (1) |
| 12 | 8 | Timestamp | `i64` | Unix timestamp |
| 20 | 16 | Emulator Version | `[16]u8` | "RAMBO-0.1.0" padded |
| 36 | 8 | Total Size | `u64` | Complete snapshot size |
| 44 | 4 | State Size | `u32` | EmulationState size |
| 48 | 4 | Cartridge Size | `u32` | Cartridge snapshot size |
| 52 | 4 | Framebuffer Size | `u32` | Framebuffer size (0 if none) |
| 56 | 4 | Flags | `u32` | Feature flags |
| 60 | 4 | Checksum | `u32` | CRC32 of data after header |
| 64 | 8 | Reserved | `[8]u8` | Future use |

All multi-byte values stored in **little-endian** format.

### Feature Flags

| Bit | Name | Description |
|-----|------|-------------|
| 0 | `has_framebuffer` | Framebuffer included |
| 1 | `cartridge_embedded` | Full ROM data embedded |
| 2 | `compressed` | Data compressed (reserved) |
| 3-31 | Reserved | Future use |

### Data Section

After the 72-byte header:

1. **Config Values** (10 bytes)
   - Console variant, CPU variant, region, PPU variant, etc.

2. **MasterClock** (8 bytes)
   - ppu_cycles (u64)

3. **CpuState** (33 bytes)
   - Registers (7B): A, X, Y, SP, PC, P
   - Cycle tracking (10B): cycle_count, instruction_cycle, state
   - Instruction context (7B): opcode, operands, address, mode, page_crossed
   - Data bus (1B)
   - Interrupts (4B): pending, NMI line, IRQ line
   - Misc (4B): halted, temp values

4. **PpuState** (~2,407 bytes)
   - Registers (4B): PPUCTRL, PPUMASK, PPUSTATUS, OAMADDR
   - Open bus (3B)
   - Internal registers (10B): v, t, x, w, read_buffer
   - Background state (10B): shift registers, latches
   - OAM (256B): Primary OAM
   - Secondary OAM (32B)
   - VRAM (2048B): Nametables
   - Palette RAM (32B)
   - Metadata (15B): mirroring, NMI flag, scanline, dot, frame

5. **BusState** (~2,065 bytes)
   - RAM (2048B): Internal RAM
   - Cycle (8B): Bus cycle counter
   - Open bus (9B): value + last_update_cycle

6. **EmulationState Flags** (3 bytes)
   - frame_complete, odd_frame, rendering_enabled

7. **Cartridge Snapshot** (variable)
   - Reference mode: ~41 bytes (path + hash + state)
   - Embed mode: Full ROM size + state

8. **Framebuffer** (optional, 245,760 bytes)
   - 256×240×4 RGBA pixels

**Total Size Examples:**
- Minimal (no cart, no FB): ~4,639 bytes
- Reference mode: ~4,680 bytes
- With framebuffer: ~250,439 bytes
- Embed mode (32KB ROM): ~37,680 bytes

## Usage Examples

### Save State System

```zig
const SaveStateManager = struct {
    allocator: std.mem.Allocator,
    slots: [10]?[]u8 = [_]?[]u8{null} ** 10,

    pub fn init(allocator: std.mem.Allocator) SaveStateManager {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *SaveStateManager) void {
        for (&self.slots) |*slot| {
            if (slot.*) |data| {
                self.allocator.free(data);
            }
        }
    }

    pub fn save(
        self: *SaveStateManager,
        slot: usize,
        state: *const EmulationState,
        config: *const Config.Config,
    ) !void {
        if (slot >= self.slots.len) return error.InvalidSlot;

        // Free existing save
        if (self.slots[slot]) |old| {
            self.allocator.free(old);
        }

        // Save new state
        self.slots[slot] = try RAMBO.Snapshot.saveBinary(
            self.allocator,
            state,
            config,
            .reference,
            false,
            null,
        );
    }

    pub fn load(
        self: *SaveStateManager,
        slot: usize,
        config: *const Config.Config,
        cartridge: anytype,
    ) !EmulationState {
        if (slot >= self.slots.len) return error.InvalidSlot;
        const data = self.slots[slot] orelse return error.EmptySlot;

        return try RAMBO.Snapshot.loadBinary(
            self.allocator,
            data,
            config,
            cartridge,
        );
    }
};
```

### Debugging Workflow

```zig
pub const Debugger = struct {
    snapshots: std.ArrayList([]u8),
    allocator: std.mem.Allocator,

    pub fn captureState(
        self: *Debugger,
        state: *const EmulationState,
        config: *const Config.Config,
    ) !void {
        const snapshot = try RAMBO.Snapshot.saveBinary(
            self.allocator,
            state,
            config,
            .reference,
            true,  // Include framebuffer for visual debugging
            state.getFramebuffer(),
        );
        try self.snapshots.append(snapshot);
    }

    pub fn rewindTo(
        self: *Debugger,
        index: usize,
        config: *const Config.Config,
        cartridge: anytype,
    ) !EmulationState {
        if (index >= self.snapshots.items.len) return error.InvalidIndex;

        return try RAMBO.Snapshot.loadBinary(
            self.allocator,
            self.snapshots.items[index],
            config,
            cartridge,
        );
    }
};
```

### State Comparison

```zig
pub fn compareStates(
    state1: *const EmulationState,
    state2: *const EmulationState,
    allocator: std.mem.Allocator,
    config: *const Config.Config,
) !bool {
    // Serialize both states
    const snap1 = try RAMBO.Snapshot.saveBinary(
        allocator,
        state1,
        config,
        .reference,
        false,
        null,
    );
    defer allocator.free(snap1);

    const snap2 = try RAMBO.Snapshot.saveBinary(
        allocator,
        state2,
        config,
        .reference,
        false,
        null,
    );
    defer allocator.free(snap2);

    // Skip header (72 bytes) and compare data
    return std.mem.eql(u8, snap1[72..], snap2[72..]);
}
```

## Best Practices

### When to Use Reference Mode

Use `.reference` mode when:
- ✅ Debugging with known ROM location
- ✅ Save states for single-user systems
- ✅ Network play (both sides have ROM)
- ✅ Minimizing snapshot size (~5KB)

### When to Use Embed Mode

Use `.embed` mode when:
- ✅ Sharing save states (portable)
- ✅ Archiving complete state
- ✅ ROM might not be available later
- ❌ Network transmission (large size ~40KB+)

### Including Framebuffer

Include framebuffer when:
- ✅ Visual debugging (see exact frame)
- ✅ Replay analysis
- ✅ Test verification
- ❌ Frequent snapshots (adds 245KB)
- ❌ Storage-constrained systems

### Config Management

**Critical:** Config must match between save and load!

```zig
// Save config with snapshot for verification
const ConfigSnapshot = struct {
    snapshot: []u8,
    console: Config.ConsoleVariant,
    cpu_variant: Config.CpuVariant,
    ppu_variant: Config.PpuVariant,
    // ... other critical fields
};

pub fn saveWithConfig(
    allocator: std.mem.Allocator,
    state: *const EmulationState,
    config: *const Config.Config,
) !ConfigSnapshot {
    return .{
        .snapshot = try RAMBO.Snapshot.saveBinary(allocator, state, config, .reference, false, null),
        .console = config.console,
        .cpu_variant = config.cpu.variant,
        .ppu_variant = config.ppu.variant,
    };
}
```

## Troubleshooting

### `error.ChecksumMismatch`

**Cause:** Snapshot data corrupted
**Solutions:**
- Verify file integrity (re-download)
- Check memory/disk errors
- Ensure complete file transfer

### `error.ConfigMismatch`

**Cause:** Config doesn't match snapshot
**Solutions:**
- Use same console variant (NTSC vs PAL)
- Match CPU/PPU variants
- Check region settings

### `error.CartridgeRequired`

**Cause:** Reference mode snapshot needs matching ROM
**Solutions:**
- Provide cartridge pointer
- Use embed mode for portability
- Verify ROM hash matches (future feature)

### Large Snapshot Files

**Issue:** Snapshots unexpectedly large
**Check:**
- Framebuffer included? (adds 245KB)
- Embed mode used? (adds ROM size)
- Expected: ~5KB (ref) or ~250KB (ref+fb) or ~40KB+ (embed)

### Pointer Reconstruction Failures

**Issue:** Crashes after `loadBinary()`
**Fix:** Always call `state.connectComponents()` (done automatically by `loadBinary`)

## Implementation Notes

### Pointer Handling

EmulationState contains no allocator, so pointers must be reconstructed externally:

1. Load pure state data
2. Assign external pointers (config, cartridge)
3. Call `connectComponents()` to wire internal pointers

### Empty Reference Snapshots

Snapshots without cartridges use empty references:
- `rom_path = ""`
- `rom_hash = [0] ** 32`
- No error on load with `null` cartridge

### Type Safety

`loadBinary()` accepts both `?*Cartridge` and `*Cartridge`:
- Optional pointers: Checked for null
- Non-optional pointers: Always valid
- Uses `@typeInfo` for runtime type inspection

### Cross-Platform Compatibility

All multi-byte values serialized in little-endian:
- Works on x86, ARM, RISC-V, etc.
- Snapshots portable across platforms
- No byte-swapping needed on little-endian systems

---

**Last Updated:** 2025-10-04
**Version:** 1.0
**RAMBO Version:** 0.1.0
