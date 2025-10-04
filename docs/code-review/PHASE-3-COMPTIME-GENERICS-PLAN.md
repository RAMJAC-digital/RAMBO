# Phase 3: Replace VTables with Comptime Generics - REVISED Development Plan

**Status**: Planning (Revised after subagent review)
**Date Created**: 2025-10-03
**Date Revised**: 2025-10-03
**Estimated Effort**: 12-16 hours
**Risk Level**: MEDIUM-HIGH (core polymorphism + type system cascade)

## Revision History

**Original Plan Issues**:
- Circular type dependencies (Cartridge ↔ Mapper)
- Unnecessary wrapper complexity (`ComptimeMapper` type)
- Incomplete interface validation
- Non-idiomatic naming conventions
- Missing cascade effect analysis (Bus/CPU must also become generic)

**Revisions Based on Subagent Feedback**:
- Removed wrapper types - use direct duck typing
- Use `anytype` parameters to break circular dependencies
- Follow Zig stdlib conventions (no `Comptime` prefix)
- Added Phase 3.0 for proof of concept validation
- Addressed Bus/CPU generification requirements
- Proper signature validation strategy

---

## Executive Summary

Replace runtime VTable-based polymorphism with Zig's compile-time duck typing for:
1. **Mapper interface** - Cartridge memory mapping (5 methods)
2. **ChrProvider interface** - CHR ROM/RAM access (2 functions)

**Key Design Decision**: Use **direct duck typing** without wrapper types, following Zig stdlib patterns like `ArrayList(T)`.

**Approach**:
```zig
// No wrappers - just direct generic types
const cart = Cartridge(Mapper0).init(allocator, rom_data);
const ppu = Ppu(CartridgeChrProvider).init();
```

**Benefits**:
- Zero runtime overhead (VTable indirection eliminated)
- Compile-time type safety through duck typing
- Idiomatic Zig code (matches stdlib patterns)
- Better compiler optimization opportunities

**Risks**:
- Type cascade: Cartridge generic → Bus generic → CPU generic
- All mapper types must be known at compile time
- Binary size increases (each mapper type = new instantiation)

---

## Current State Analysis

### Mapper VTable Pattern (`src/cartridge/Mapper.zig`)

**Current Implementation**:
```zig
pub const Mapper = struct {
    vtable: *const VTable,

    pub const VTable = struct {
        cpuRead: *const fn (mapper: *Mapper, cart: *const Cartridge, address: u16) u8,
        cpuWrite: *const fn (mapper: *Mapper, cart: *Cartridge, address: u16, value: u8) void,
        ppuRead: *const fn (mapper: *Mapper, cart: *const Cartridge, address: u16) u8,
        ppuWrite: *const fn (mapper: *Mapper, cart: *Cartridge, address: u16, value: u8) void,
        reset: *const fn (mapper: *Mapper, cart: *Cartridge) void,
    };
};
```

**Current Mapper0 Implementation Pattern**:
```zig
// Mapper0 wraps itself in VTable
fn cpuReadImpl(mapper_ptr: *Mapper, cart: *const Cartridge, address: u16) u8 {
    _ = mapper_ptr;  // Mapper0 has no state
    // Direct ROM access
}
```

**Runtime Cost**: 1 indirect function call per access (~2-3 cycles overhead)

### ChrProvider VTable Pattern (`src/memory/ChrProvider.zig`)

**Current Implementation**:
```zig
pub const ChrProvider = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        read: *const fn (ptr: *anyopaque, address: u16) u8,
        write: *const fn (ptr: *anyopaque, address: u16, value: u8) void,
    };
};
```

**Runtime Cost**: 1 indirect call + type erasure overhead

---

## Target State: Direct Duck-Typed Generics

### Design Principles

1. **No wrapper types** - Use duck typing directly
2. **Follow Zig stdlib conventions** - `Cartridge(MapperType)` not `ComptimeCartridge(MapperType)`
3. **Use `anytype` for flexibility** - Break circular dependencies
4. **Validate at compile time** - Let Zig's type system do the heavy lifting
5. **Explicit type cascade** - Accept that generics propagate upward

### 1. Generic Cartridge Design

**File**: `src/cartridge/Cartridge.zig` (modified)

```zig
//! Generic Cartridge
//!
//! Cartridge is now a type factory parameterized by mapper implementation.
//! This enables compile-time polymorphism with zero runtime overhead.
//!
//! Required Mapper Interface (duck typing):
//! - cpuRead(self: *Self, cart: anytype, address: u16) u8
//! - cpuWrite(self: *Self, cart: anytype, address: u16, value: u8) void
//! - ppuRead(self: *Self, cart: anytype, address: u16) u8
//! - ppuWrite(self: *Self, cart: anytype, address: u16, value: u8) void
//! - reset(self: *Self, cart: anytype) void
//!
//! Usage:
//! ```zig
//! const CartType = Cartridge(Mapper0);
//! const cart = try CartType.loadFromData(allocator, rom_data);
//! defer cart.deinit(allocator);
//! const value = cart.cpuRead(0x8000);
//! ```

const std = @import("std");
const Mapper0 = @import("mappers/Mapper0.zig");

/// Creates a Cartridge type for the given mapper implementation
pub fn Cartridge(comptime MapperType: type) type {
    return struct {
        const Self = @This();

        /// Mapper instance (contains any mapper-specific state)
        mapper: MapperType,

        /// PRG ROM data (program code)
        prg_rom: []const u8,

        /// CHR ROM/RAM data (graphics)
        chr_data: []u8,

        /// Nametable mirroring mode
        mirroring: Mirroring,

        /// Allocator used for dynamic memory
        allocator: std.mem.Allocator,

        /// Load cartridge from iNES ROM data
        pub fn loadFromData(allocator: std.mem.Allocator, rom_data: []const u8) !Self {
            // Parse iNES header
            const header = try parseINesHeader(rom_data);

            // Allocate PRG ROM (immutable)
            const prg_rom = try allocator.dupe(u8, extractPrgRom(rom_data, header));
            errdefer allocator.free(prg_rom);

            // Allocate CHR data (may be RAM, so mutable)
            const chr_data = try allocator.alloc(u8, header.chr_size);
            errdefer allocator.free(chr_data);

            if (header.chr_size > 0) {
                @memcpy(chr_data, extractChrRom(rom_data, header));
            }

            return Self{
                .mapper = MapperType{},  // Default init - mappers can add init() if needed
                .prg_rom = prg_rom,
                .chr_data = chr_data,
                .mirroring = header.mirroring,
                .allocator = allocator,
            };
        }

        /// Free cartridge memory
        pub fn deinit(self: *Self) void {
            self.allocator.free(self.prg_rom);
            self.allocator.free(self.chr_data);
        }

        /// CPU reads from cartridge address space ($4020-$FFFF)
        pub fn cpuRead(self: *const Self, address: u16) u8 {
            // Direct call - compiler knows exact type, can inline
            return self.mapper.cpuRead(self, address);
        }

        /// CPU writes to cartridge address space
        pub fn cpuWrite(self: *Self, address: u16, value: u8) void {
            return self.mapper.cpuWrite(self, address, value);
        }

        /// PPU reads from CHR address space ($0000-$1FFF)
        pub fn ppuRead(self: *const Self, address: u16) u8 {
            return self.mapper.ppuRead(self, address);
        }

        /// PPU writes to CHR address space (CHR-RAM only)
        pub fn ppuWrite(self: *Self, address: u16, value: u8) void {
            self.mapper.ppuWrite(self, address, value);
        }

        /// Reset mapper to initial state
        pub fn reset(self: *Self) void {
            self.mapper.reset(self);
        }
    };
}

/// Mirroring modes
pub const Mirroring = enum {
    horizontal,
    vertical,
    four_screen,
};

// Helper functions for iNES parsing (implementation details omitted)
fn parseINesHeader(data: []const u8) !INesHeader { ... }
fn extractPrgRom(data: []const u8, header: INesHeader) []const u8 { ... }
fn extractChrRom(data: []const u8, header: INesHeader) []const u8 { ... }

const INesHeader = struct {
    prg_size: usize,
    chr_size: usize,
    mirroring: Mirroring,
    mapper_number: u8,
};
```

### 2. Updated Mapper0 Implementation

**File**: `src/cartridge/mappers/Mapper0.zig` (modified)

```zig
//! Mapper 0 (NROM) - No banking, direct ROM access
//!
//! This mapper has no state and performs simple address mapping.
//! Implements the duck-typed Mapper interface expected by Cartridge(T).

const std = @import("std");

/// Mapper 0 has no state
/// All methods receive cartridge through anytype parameter
const Mapper0 = @This();

/// CPU read from PRG ROM space ($8000-$FFFF)
pub fn cpuRead(_: *const Mapper0, cart: anytype, address: u16) u8 {
    // NROM mirrors 16KB ROM if only one bank present
    const addr = if (cart.prg_rom.len == 0x4000)
        (address - 0x8000) & 0x3FFF  // Mirror 16KB
    else
        address - 0x8000;  // Full 32KB

    return cart.prg_rom[addr];
}

/// CPU write to PRG ROM space (no effect - ROM is read-only)
pub fn cpuWrite(_: *Mapper0, _: anytype, _: u16, _: u8) void {
    // NROM has no writable registers
}

/// PPU read from CHR ROM space ($0000-$1FFF)
pub fn ppuRead(_: *const Mapper0, cart: anytype, address: u16) u8 {
    return cart.chr_data[address & 0x1FFF];
}

/// PPU write to CHR space (only if CHR-RAM)
pub fn ppuWrite(_: *Mapper0, cart: anytype, address: u16, value: u8) void {
    // Only write if CHR-RAM (determined by cartridge)
    cart.chr_data[address & 0x1FFF] = value;
}

/// Reset mapper (no state to reset for NROM)
pub fn reset(_: *Mapper0, _: anytype) void {
    // No state to reset
}
```

**Key Changes**:
- First parameter: `_: *const Mapper0` or `_: *Mapper0` (concrete type, not `*Mapper`)
- Second parameter: `cart: anytype` (structural duck typing, no import of Cartridge!)
- Accesses `cart.prg_rom`, `cart.chr_data` directly
- No VTable wrapping needed

### 3. Generic PPU with ChrProvider

**File**: `src/ppu/Ppu.zig` (modified to be generic)

```zig
//! Generic PPU with compile-time CHR provider
//!
//! PPU is parameterized by CHR provider type for zero-cost abstraction.
//!
//! Required ChrProvider Interface (duck typing):
//! - read(self: *const Self, address: u16) u8
//! - write(self: *Self, address: u16, value: u8) void

pub fn Ppu(comptime ChrProviderType: type) type {
    return struct {
        const Self = @This();

        /// Hardware state
        state: PpuState,

        /// CHR memory provider (cartridge or test mock)
        chr_provider: ChrProviderType,

        pub fn init(chr_provider: ChrProviderType) Self {
            return .{
                .state = PpuState{},
                .chr_provider = chr_provider,
            };
        }

        /// Read CHR pattern data
        pub fn readChr(self: *const Self, address: u16) u8 {
            return self.chr_provider.read(address);
        }

        /// Write CHR data (CHR-RAM only)
        pub fn writeChr(self: *Self, address: u16, value: u8) void {
            self.chr_provider.write(address, value);
        }

        // ... rest of PPU implementation
    };
}

/// Re-export State for non-generic access
pub const State = @import("State.zig");
pub const PpuState = State.PpuState;
```

### 4. Cartridge-Based CHR Provider

**File**: `src/memory/CartridgeChrProvider.zig` (new file)

```zig
//! CHR Provider that delegates to Cartridge
//!
//! This adapter allows PPU to read CHR data from a cartridge.
//! Implements the duck-typed ChrProvider interface.

const std = @import("std");

/// Creates a CHR provider for a specific cartridge type
pub fn CartridgeChrProvider(comptime CartridgeType: type) type {
    return struct {
        const Self = @This();

        /// Non-owning pointer to cartridge
        cartridge: *CartridgeType,

        pub fn init(cartridge: *CartridgeType) Self {
            return .{ .cartridge = cartridge };
        }

        /// Read CHR data from cartridge
        pub fn read(self: *const Self, address: u16) u8 {
            return self.cartridge.ppuRead(address);
        }

        /// Write CHR data to cartridge
        pub fn write(self: *Self, address: u16, value: u8) void {
            self.cartridge.ppuWrite(address, value);
        }
    };
}
```

---

## Type Cascade Strategy

### The Generic Propagation Problem

Making Cartridge generic forces upstream types to also be generic:

```zig
Cartridge(Mapper0)  →  Bus must know mapper type
                    →  CPU must know bus type
                    →  EmulationState must know CPU type
```

### Solution: Type Erasure at Bus Boundary

**Option A: Bus Uses Type Erasure (Recommended)**

```zig
// Bus.zig - stays non-generic
pub const Bus = struct {
    cartridge: *anyopaque,        // Type-erased pointer
    cartridge_vtable: CartridgeVTable,  // Minimal VTable just for Bus

    pub const CartridgeVTable = struct {
        cpuRead: *const fn (*anyopaque, u16) u8,
        cpuWrite: *const fn (*anyopaque, u16, u8) void,
    };

    pub fn setCartridge(self: *Bus, cart: anytype) void {
        self.cartridge = cart;
        self.cartridge_vtable = .{
            .cpuRead = struct {
                fn read(ptr: *anyopaque, addr: u16) u8 {
                    const c: *@TypeOf(cart.*) = @ptrCast(@alignCast(ptr));
                    return c.cpuRead(addr);
                }
            }.read,
            // ... similar for write
        };
    }
};
```

**Benefits**:
- Bus, CPU, EmulationState stay non-generic
- VTable overhead limited to Bus boundary only
- Mappers still get zero-cost comptime dispatch

**Option B: Full Generification**

```zig
// Everything becomes generic
pub fn EmulationState(comptime MapperType: type) type {
    const CartType = Cartridge(MapperType);
    const BusType = Bus(CartType);
    const CpuType = Cpu(BusType);

    return struct {
        cpu: CpuType,
        bus: BusType,
        cartridge: CartType,
    };
}
```

**Downsides**:
- Complex type signatures throughout
- Hard to mix different cartridge types
- Type explosion in tests

**Recommendation**: Use Option A (type erasure at Bus boundary) for pragmatic balance.

---

## Implementation Strategy

### Phase 3.0: Proof of Concept (NEW - 2-3 hours)

**Purpose**: Validate the design with minimal code before full migration.

**Tasks**:
1. Create `tests/poc_comptime_mapper.zig`
2. Implement minimal `Cartridge(T)` generic
3. Implement minimal `Mapper0` with duck typing
4. Verify compilation and zero-cost abstraction
5. Compare assembly output (VTable vs comptime)
6. Validate signature checking approach

**Success Criteria**:
- [ ] Proof of concept compiles
- [ ] Duck typing works with `anytype` cart parameter
- [ ] Assembly shows direct calls (no indirection)
- [ ] Approach validated before touching production code

**Example POC**:
```zig
// tests/poc_comptime_mapper.zig
const std = @import("std");
const testing = std.testing;

// Minimal generic cartridge
fn TestCartridge(comptime MapperType: type) type {
    return struct {
        mapper: MapperType,
        rom: [0x4000]u8,

        pub fn read(self: *const @This(), addr: u16) u8 {
            return self.mapper.cpuRead(self, addr);
        }
    };
}

// Minimal mapper with duck typing
const TestMapper = struct {
    pub fn cpuRead(_: *const TestMapper, cart: anytype, addr: u16) u8 {
        return cart.rom[addr & 0x3FFF];
    }
};

test "POC: comptime mapper dispatch" {
    var cart = TestCartridge(TestMapper){
        .mapper = .{},
        .rom = undefined,
    };
    cart.rom[0] = 0x42;

    try testing.expectEqual(@as(u8, 0x42), cart.read(0));
}
```

### Phase 3.1: Update Mapper0 for Duck Typing (2-3 hours)

**Tasks**:
1. Modify Mapper0 signatures: `(self: *Mapper0, cart: anytype, ...)`
2. Remove VTable wrapper code
3. Update implementation to access `cart.prg_rom` directly
4. Keep old VTable version alongside (in separate file) for Bus compatibility
5. Create comprehensive tests

**Acceptance Criteria**:
- [ ] Mapper0 implements all 5 methods with duck-typed signatures
- [ ] Tests pass using `Cartridge(Mapper0)`
- [ ] Old VTable version still available for Bus

### Phase 3.2: Implement Generic Cartridge (3-4 hours)

**Tasks**:
1. Convert `Cartridge` to `fn Cartridge(comptime MapperType: type) type`
2. Update all cartridge methods to dispatch through mapper
3. Handle allocator and resource cleanup properly
4. Update cartridge loading code
5. Create type alias for common case: `pub const NromCart = Cartridge(Mapper0);`

**Acceptance Criteria**:
- [ ] `Cartridge(Mapper0)` compiles and loads ROMs
- [ ] All cartridge tests pass
- [ ] Memory is properly managed (no leaks)

### Phase 3.3: Implement Bus Type Erasure (2-3 hours)

**Tasks**:
1. Add `CartridgeVTable` to Bus (minimal: cpuRead, cpuWrite only)
2. Implement `setCartridge(bus: *Bus, cart: anytype)` with type erasure
3. Update Bus read/write to dispatch through minimal VTable
4. Test with `Cartridge(Mapper0)`

**Acceptance Criteria**:
- [ ] Bus accepts any `Cartridge(MapperType)`
- [ ] Bus, CPU, EmulationState remain non-generic
- [ ] Type erasure overhead only at Bus boundary

### Phase 3.4: Update PPU for Generic ChrProvider (2-3 hours)

**Tasks**:
1. Convert PPU to `fn Ppu(comptime ChrProviderType: type) type`
2. Create `CartridgeChrProvider(CartType)` adapter
3. Update Bus to store generic PPU with erased type
4. Update all PPU initialization code

**Acceptance Criteria**:
- [ ] PPU compiles with generic CHR provider
- [ ] CartridgeChrProvider works correctly
- [ ] All PPU tests pass

### Phase 3.5: Testing and Validation (2-3 hours)

**Tasks**:
1. Run full test suite (`zig build test`)
2. Verify cycle counts unchanged
3. Add compile-time duck typing tests
4. Performance benchmark: VTable vs comptime
5. Check binary size impact

**Acceptance Criteria**:
- [ ] All 375+ tests passing
- [ ] No cycle count regressions
- [ ] Performance improvement measurable
- [ ] Binary size increase acceptable (<20%)

### Phase 3.6: Cleanup and Documentation (1-2 hours)

**Tasks**:
1. Remove old VTable files (Mapper.zig, ChrProvider.zig)
2. Update root.zig exports
3. Create usage guide in `docs/06-implementation-notes/comptime-generics/`
4. Document type cascade and Bus type erasure pattern
5. Update REFACTORING-ROADMAP.md

**Acceptance Criteria**:
- [ ] Old VTable code removed
- [ ] Documentation complete with examples
- [ ] Roadmap updated with Phase 3 completion

---

## Testing Strategy

### Compile-Time Duck Typing Tests

```zig
// Test: Mapper with correct interface compiles
test "Mapper interface: valid implementation compiles" {
    const ValidMapper = struct {
        pub fn cpuRead(_: *const @This(), cart: anytype, addr: u16) u8 {
            return cart.prg_rom[addr & 0x7FFF];
        }
        pub fn cpuWrite(_: *@This(), _: anytype, _: u16, _: u8) void {}
        pub fn ppuRead(_: *const @This(), cart: anytype, addr: u16) u8 {
            return cart.chr_data[addr];
        }
        pub fn ppuWrite(_: *@This(), cart: anytype, addr: u16, val: u8) void {
            cart.chr_data[addr] = val;
        }
        pub fn reset(_: *@This(), _: anytype) void {}
    };

    const CartType = Cartridge(ValidMapper);
    _ = CartType;  // Just verify it compiles
}

// Test: Missing methods cause compile error
// (This test lives in a separate file that's expected to fail)
// tests/compile_errors/incomplete_mapper.zig
const IncompleteMapper = struct {
    pub fn cpuRead(_: *const @This(), _: anytype, _: u16) u8 { return 0; }
    // Missing: cpuWrite, ppuRead, ppuWrite, reset
};

pub fn main() void {
    _ = Cartridge(IncompleteMapper);  // Should fail: missing methods
}
```

### Performance Benchmark

```zig
test "Performance: mapper dispatch overhead" {
    const iterations = 10_000_000;

    // Setup cartridges
    var cart_comptime = try Cartridge(Mapper0).loadFromData(allocator, rom_data);
    defer cart_comptime.deinit();

    var cart_vtable = try OldCartridge.loadFromData(allocator, rom_data);
    defer cart_vtable.deinit();

    // Benchmark comptime version
    var timer = try std.time.Timer.start();
    var sum_comptime: u64 = 0;
    for (0..iterations) |i| {
        sum_comptime +%= cart_comptime.cpuRead(@truncate(i));
    }
    const time_comptime = timer.lap();

    // Benchmark VTable version
    var sum_vtable: u64 = 0;
    for (0..iterations) |i| {
        sum_vtable +%= cart_vtable.cpuRead(@truncate(i));
    }
    const time_vtable = timer.read();

    std.debug.print("\nMapper Dispatch Benchmark ({} iterations):\n", .{iterations});
    std.debug.print("  Comptime: {}ns total, {}ns/call\n", .{time_comptime, time_comptime / iterations});
    std.debug.print("  VTable:   {}ns total, {}ns/call\n", .{time_vtable, time_vtable / iterations});
    std.debug.print("  Speedup:  {d:.2}x\n", .{@as(f64, @floatFromInt(time_vtable)) / @as(f64, @floatFromInt(time_comptime))});

    // Verify we're testing the same thing
    try testing.expectEqual(sum_comptime, sum_vtable);
}
```

---

## Risk Mitigation

### Risk 1: Circular Dependencies
**Mitigation**: Use `anytype` parameters in mapper methods - no import of Cartridge needed.

### Risk 2: Type Cascade Complexity
**Mitigation**: Type erasure at Bus boundary keeps upper layers simple.

### Risk 3: Binary Size Growth
**Mitigation**:
- Monitor size with each mapper added
- Use `--strip` in release builds
- Consider feature flags for mapper selection if needed

### Risk 4: Unclear Compile Errors
**Mitigation**:
- Let Zig's compiler handle duck typing errors (already clear)
- Provide clear examples in documentation
- Use type aliases to simplify common cases

### Risk 5: Performance Not Achieved
**Mitigation**:
- Phase 3.0 POC validates assembly output first
- Performance benchmark in Phase 3.5
- Abort migration if no measurable improvement

---

## Success Criteria

Phase 3 complete when:

1. ✅ Generic `Cartridge(MapperType)` implemented
2. ✅ Mapper0 uses duck typing (no VTable)
3. ✅ Bus uses type erasure for cartridge storage
4. ✅ PPU uses generic CHR provider
5. ✅ All tests passing (375+ tests, 100% pass rate)
6. ✅ Performance improvement measured and documented
7. ✅ Old VTable code removed
8. ✅ Documentation complete with migration guide
9. ✅ Binary size impact acceptable (<20% growth)

---

## Open Questions

1. **Should we validate duck typing explicitly, or trust compiler errors?**
   - **Answer**: Trust the compiler. Zig's error messages for missing/wrong methods are excellent.

2. **How to handle future mappers with complex state (MMC1, MMC3)?**
   - **Answer**: They store state as struct fields, accessed via `self.*` in methods.

3. **Should all mappers be instantiated at compile time, or support runtime loading?**
   - **Answer**: Compile-time for now. Future: tagged union of all mappers if runtime needed.

4. **What if we want to support multiple cartridges simultaneously?**
   - **Answer**: Not needed for NES (one cart slot). If needed: array of `AnyCartridge` union type.

---

## Next Steps

1. ✅ **Subagent reviews complete** - Critical issues identified
2. **Get user approval** on revised plan
3. **Begin Phase 3.0** - Proof of concept
4. **Track progress** in REFACTORING-ROADMAP.md
5. **Create comptime generics usage guide** in docs/

---

## Appendix: Naming Conventions

Following Zig stdlib patterns:

```zig
// Type Factories (generic types)
Cartridge(MapperType)      // Not: ComptimeCartridge(MapperType)
Ppu(ChrProviderType)       // Not: ComptimePpu(ChrProviderType)
CartridgeChrProvider(T)    // Adapters still descriptive

// Type Aliases (for common cases)
const NromCart = Cartridge(Mapper0);
const Mmc1Cart = Cartridge(MMC1);

// Module Names
cartridge.Cartridge(T)     // Module is lowercase, type is PascalCase
ppu.Ppu(T)                 // Matches stdlib: mem.Allocator, ArrayList(T)
```

The generic nature is obvious from `TypeName(Param)` syntax - no `Comptime` prefix needed.
