# Phase 3: Replace VTables with Comptime Generics - Development Plan

**Status**: Planning
**Date Created**: 2025-10-03
**Estimated Effort**: 8-12 hours
**Risk Level**: MEDIUM (core polymorphism mechanism change)

## Executive Summary

Replace runtime VTable-based polymorphism with Zig's compile-time duck typing (comptime generics) for:
1. **Mapper interface** - Cartridge memory mapping (5 functions)
2. **ChrProvider interface** - CHR ROM/RAM access (2 functions)

**Benefits**:
- Zero runtime overhead (VTable indirection eliminated)
- Compile-time type safety and validation
- Clearer API with explicit type requirements
- Better optimization opportunities for compiler

**Risks**:
- Type system complexity increases
- All mapper implementations must be known at compile time
- Requires careful migration to avoid breaking existing code

---

## Current State Analysis

### 1. Mapper VTable Pattern (`src/cartridge/Mapper.zig`)

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

    pub inline fn cpuRead(self: *Mapper, cart: *const Cartridge, address: u16) u8 {
        return self.vtable.cpuRead(self, cart, address);
    }
    // ... delegation methods for other functions
};
```

**Runtime Cost**: 1 pointer dereference per function call
**Current Usage**: Cartridge.zig stores `mapper: Mapper` and calls through VTable
**Implementations**: Mapper0 (NROM) - more planned (MMC1, MMC3, etc.)

### 2. ChrProvider VTable Pattern (`src/memory/ChrProvider.zig`)

**Current Implementation**:
```zig
pub const ChrProvider = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        read: *const fn (ptr: *anyopaque, address: u16) u8,
        write: *const fn (ptr: *anyopaque, address: u16, value: u8) void,
    };

    pub inline fn read(self: ChrProvider, address: u16) u8 {
        return self.vtable.read(self.ptr, address);
    }
    // ... delegation for write
};
```

**Runtime Cost**: 1 pointer dereference + type erasure overhead
**Current Usage**: PPU stores `chr_provider: ChrProvider` for CHR memory access
**Implementations**: Test mock, Cartridge CHR ROM/RAM providers

---

## Target State: Comptime Generic Design

### Naming Convention

All comptime-generic interfaces use `Comptime` prefix to clearly indicate compile-time polymorphism:

- `ComptimeMapper` - Generic mapper interface (replaces Mapper VTable)
- `ComptimeChrProvider` - Generic CHR provider interface (replaces ChrProvider VTable)

**Rationale**:
- Clear distinction from runtime polymorphism
- Obvious to developers and AI agents that type is resolved at compile time
- Consistent with Zig conventions (e.g., `std.ArrayList`)
- Aids code navigation by making intent explicit

### 1. ComptimeMapper Interface Design

**File**: `src/cartridge/ComptimeMapper.zig` (new file)

```zig
//! Comptime Mapper Interface
//!
//! This module provides compile-time duck-typed polymorphism for cartridge mappers.
//! Unlike the VTable approach, mapper type is resolved at compile time, eliminating
//! runtime indirection and enabling better optimization.
//!
//! Required Methods (duck typing):
//! - cpuRead(self: *Self, cart: *const Cartridge, address: u16) u8
//! - cpuWrite(self: *Self, cart: *Cartridge, address: u16, value: u8) void
//! - ppuRead(self: *Self, cart: *const Cartridge, address: u16) u8
//! - ppuWrite(self: *Self, cart: *Cartridge, address: u16, value: u8) void
//! - reset(self: *Self, cart: *Cartridge) void
//!
//! Usage Example:
//! ```zig
//! const cartridge = Cartridge(Mapper0).init(rom_data);
//! const value = cartridge.mapper.cpuRead(&cartridge, 0x8000);
//! ```

const std = @import("std");
const Cartridge = @import("Cartridge.zig").Cartridge;

/// Validates that a type implements the Mapper interface at compile time
pub fn validateMapper(comptime MapperType: type) void {
    // Verify required methods exist with correct signatures
    const info = @typeInfo(MapperType);

    // Check for cpuRead method
    if (!@hasDecl(MapperType, "cpuRead")) {
        @compileError("Mapper type '" ++ @typeName(MapperType) ++ "' missing required method: cpuRead");
    }

    // Check for cpuWrite method
    if (!@hasDecl(MapperType, "cpuWrite")) {
        @compileError("Mapper type '" ++ @typeName(MapperType) ++ "' missing required method: cpuWrite");
    }

    // Check for ppuRead method
    if (!@hasDecl(MapperType, "ppuRead")) {
        @compileError("Mapper type '" ++ @typeName(MapperType) ++ "' missing required method: ppuRead");
    }

    // Check for ppuWrite method
    if (!@hasDecl(MapperType, "ppuWrite")) {
        @compileError("Mapper type '" ++ @typeName(MapperType) ++ "' missing required method: ppuWrite");
    }

    // Check for reset method
    if (!@hasDecl(MapperType, "reset")) {
        @compileError("Mapper type '" ++ @typeName(MapperType) ++ "' missing required method: reset");
    }

    // All checks passed - type is a valid Mapper
}

/// Generic mapper wrapper for compile-time polymorphism
/// Usage: const MyMapper = ComptimeMapper(Mapper0);
pub fn ComptimeMapper(comptime MapperType: type) type {
    // Validate interface at compile time
    validateMapper(MapperType);

    return struct {
        const Self = @This();

        mapper: MapperType,

        pub fn init() Self {
            return .{
                .mapper = MapperType{},
            };
        }

        /// CPU read from cartridge address space
        pub inline fn cpuRead(self: *Self, cart: *const Cartridge(MapperType), address: u16) u8 {
            return self.mapper.cpuRead(&self.mapper, cart, address);
        }

        /// CPU write to cartridge address space
        pub inline fn cpuWrite(self: *Self, cart: *Cartridge(MapperType), address: u16, value: u8) void {
            self.mapper.cpuWrite(&self.mapper, cart, address, value);
        }

        /// PPU read from CHR address space
        pub inline fn ppuRead(self: *Self, cart: *const Cartridge(MapperType), address: u16) u8 {
            return self.mapper.ppuRead(&self.mapper, cart, address);
        }

        /// PPU write to CHR address space
        pub inline fn ppuWrite(self: *Self, cart: *Cartridge(MapperType), address: u16, value: u8) void {
            self.mapper.ppuWrite(&self.mapper, cart, address, value);
        }

        /// Reset mapper state
        pub inline fn reset(self: *Self, cart: *Cartridge(MapperType)) void {
            self.mapper.reset(&self.mapper, cart);
        }
    };
}
```

### 2. ComptimeChrProvider Interface Design

**File**: `src/memory/ComptimeChrProvider.zig` (new file)

```zig
//! Comptime CHR Provider Interface
//!
//! This module provides compile-time duck-typed polymorphism for CHR memory providers.
//! CHR providers supply pattern table data to the PPU (character/sprite graphics).
//!
//! Required Methods (duck typing):
//! - read(self: *const Self, address: u16) u8
//! - write(self: *Self, address: u16, value: u8) void
//!
//! Usage Example:
//! ```zig
//! const ppu = Ppu(CartridgeChrProvider).init();
//! const tile_data = ppu.chr_provider.read(0x0000);
//! ```

const std = @import("std");

/// Validates that a type implements the ChrProvider interface at compile time
pub fn validateChrProvider(comptime ProviderType: type) void {
    // Check for read method
    if (!@hasDecl(ProviderType, "read")) {
        @compileError("CHR Provider type '" ++ @typeName(ProviderType) ++ "' missing required method: read");
    }

    // Check for write method
    if (!@hasDecl(ProviderType, "write")) {
        @compileError("CHR Provider type '" ++ @typeName(ProviderType) ++ "' missing required method: write");
    }
}

/// Generic CHR provider wrapper for compile-time polymorphism
/// Usage: const MyChrProvider = ComptimeChrProvider(CartridgeChrProvider);
pub fn ComptimeChrProvider(comptime ProviderType: type) type {
    // Validate interface at compile time
    validateChrProvider(ProviderType);

    return struct {
        const Self = @This();

        provider: ProviderType,

        pub fn init(provider: ProviderType) Self {
            return .{
                .provider = provider,
            };
        }

        /// Read CHR data at address
        pub inline fn read(self: *const Self, address: u16) u8 {
            return self.provider.read(address);
        }

        /// Write CHR data at address (CHR-RAM only)
        pub inline fn write(self: *Self, address: u16, value: u8) void {
            self.provider.write(address, value);
        }
    };
}
```

### 3. Updated Cartridge Structure

**File**: `src/cartridge/Cartridge.zig` (modified)

```zig
//! Cartridge with Comptime Mapper
//!
//! The cartridge is now a generic type parameterized by mapper implementation.
//! This eliminates runtime VTable overhead and enables full compile-time optimization.

pub fn Cartridge(comptime MapperType: type) type {
    const ComptimeMapper = @import("ComptimeMapper.zig").ComptimeMapper;

    return struct {
        const Self = @This();

        // ROM data
        prg_rom: []const u8,
        chr_rom: []const u8,

        // Mapper (compile-time type)
        mapper: ComptimeMapper(MapperType),

        // ... other fields

        pub fn init(rom_data: []const u8) !Self {
            // ... ROM parsing logic ...

            return Self{
                .prg_rom = prg_rom,
                .chr_rom = chr_rom,
                .mapper = ComptimeMapper(MapperType).init(),
            };
        }

        /// CPU reads from cartridge space ($4020-$FFFF)
        pub fn cpuRead(self: *const Self, address: u16) u8 {
            return self.mapper.cpuRead(self, address);
        }

        /// CPU writes to cartridge space
        pub fn cpuWrite(self: *Self, address: u16, value: u8) void {
            self.mapper.cpuWrite(self, address, value);
        }
    };
}
```

---

## Implementation Strategy

### Phase 3.1: Create Comptime Interface Infrastructure (2-3 hours)

**Tasks**:
1. Create `src/cartridge/ComptimeMapper.zig`
   - Implement `validateMapper()` compile-time checker
   - Implement `ComptimeMapper()` generic wrapper
   - Add comprehensive documentation with usage examples

2. Create `src/memory/ComptimeChrProvider.zig`
   - Implement `validateChrProvider()` compile-time checker
   - Implement `ComptimeChrProvider()` generic wrapper
   - Add comprehensive documentation

3. Create `docs/06-implementation-notes/comptime-generics/README.md`
   - Explain comptime polymorphism concepts
   - Show before/after code examples
   - Document naming conventions
   - Provide troubleshooting guide

**Acceptance Criteria**:
- [ ] Both comptime interface files compile successfully
- [ ] Documentation clearly explains usage and benefits
- [ ] Compile-time validation catches missing methods

### Phase 3.2: Update Mapper0 Implementation (1-2 hours)

**Tasks**:
1. Update `src/cartridge/mappers/Mapper0.zig`
   - Remove VTable references
   - Implement methods with correct signatures for duck typing
   - Update documentation

2. Create test for comptime validation
   - Verify Mapper0 passes `validateMapper()`
   - Test compile errors for incomplete implementations

**Acceptance Criteria**:
- [ ] Mapper0 implements all required methods
- [ ] Mapper0 compiles with `ComptimeMapper(Mapper0)`
- [ ] Tests verify interface compliance

### Phase 3.3: Update Cartridge to Use Comptime Mapper (2-3 hours)

**Tasks**:
1. Convert `Cartridge` to generic `Cartridge(MapperType)`
2. Update all cartridge methods to use comptime mapper
3. Update cartridge loading code to specify mapper type
4. Update Bus integration to use `Cartridge(Mapper0)`

**Acceptance Criteria**:
- [ ] Cartridge is generic over mapper type
- [ ] All existing tests pass with `Cartridge(Mapper0)`
- [ ] No VTable references remain in cartridge code

### Phase 3.4: Update ChrProvider to Comptime (2-3 hours)

**Tasks**:
1. Create cartridge-based CHR provider implementation
2. Update PPU to be generic over CHR provider type
3. Update PPU initialization to use comptime provider
4. Remove old VTable-based ChrProvider

**Acceptance Criteria**:
- [ ] PPU uses comptime CHR provider
- [ ] All PPU tests pass with new provider
- [ ] Old VTable code removed

### Phase 3.5: Testing and Validation (1-2 hours)

**Tasks**:
1. Run full test suite (`zig build test`)
2. Verify cycle counts unchanged (no regression)
3. Add compile-time validation tests
4. Update integration tests

**Acceptance Criteria**:
- [ ] All 375+ tests passing
- [ ] No performance regressions
- [ ] Compile-time errors are clear and helpful

### Phase 3.6: Documentation and Cleanup (1 hour)

**Tasks**:
1. Update `REFACTORING-ROADMAP.md` with Phase 3 completion
2. Create usage guide in `docs/06-implementation-notes/comptime-generics/`
3. Add migration notes for future mapper implementations
4. Remove old VTable files

**Acceptance Criteria**:
- [ ] Documentation complete and accurate
- [ ] Old VTable code removed
- [ ] Roadmap updated

---

## Testing Strategy

### Compile-Time Tests

```zig
// Test: Incomplete mapper fails validation
test "ComptimeMapper: compile error for missing methods" {
    const IncompleteMapper = struct {
        pub fn cpuRead(self: *@This(), cart: *const Cartridge, address: u16) u8 {
            _ = self; _ = cart; _ = address;
            return 0;
        }
        // Missing: cpuWrite, ppuRead, ppuWrite, reset
    };

    // This should fail to compile with clear error message
    // _ = ComptimeMapper(IncompleteMapper);
}

// Test: Complete mapper passes validation
test "ComptimeMapper: valid mapper compiles" {
    const ValidMapper = struct {
        pub fn cpuRead(self: *@This(), cart: *const Cartridge, address: u16) u8 { ... }
        pub fn cpuWrite(self: *@This(), cart: *Cartridge, address: u16, value: u8) void { ... }
        pub fn ppuRead(self: *@This(), cart: *const Cartridge, address: u16) u8 { ... }
        pub fn ppuWrite(self: *@This(), cart: *Cartridge, address: u16, value: u8) void { ... }
        pub fn reset(self: *@This(), cart: *Cartridge) void { ... }
    };

    const mapper = ComptimeMapper(ValidMapper).init();
    _ = mapper;
}
```

### Runtime Tests

All existing tests must pass:
- Mapper0 functionality tests
- Cartridge loading tests
- PPU CHR access tests
- Integration tests with full emulation

**Target**: 100% test pass rate (all 375+ tests)

---

## Risk Mitigation

### Risk 1: Breaking Existing Code
**Mitigation**:
- Implement in new files alongside old VTable code
- Migrate incrementally (Mapper first, then ChrProvider)
- Keep tests running throughout migration
- Only delete VTable code after all tests pass

### Risk 2: Unclear Compile Errors
**Mitigation**:
- Implement comprehensive `@compileError` messages
- Document common errors in troubleshooting guide
- Provide example implementations as reference

### Risk 3: Performance Regression
**Mitigation**:
- Verify inline functions are actually inlined (check assembly)
- Compare cycle counts before/after
- Benchmark critical hot paths

### Risk 4: Complex Type System
**Mitigation**:
- Clear naming conventions (Comptime prefix)
- Comprehensive documentation with examples
- Helper functions for common patterns

---

## Success Criteria

Phase 3 is complete when:

1. ✅ All VTable code removed (Mapper.zig, ChrProvider.zig)
2. ✅ Comptime interfaces implemented and documented
3. ✅ All mappers use comptime generics
4. ✅ All tests passing (375+ tests, 100% pass rate)
5. ✅ Documentation complete with usage examples
6. ✅ No performance regressions
7. ✅ Naming consistently uses `Comptime` prefix
8. ✅ Future mapper development pattern clearly documented

---

## Open Questions for Review

1. **Naming**: Is `ComptimeMapper` clear enough, or should we use `GenericMapper`, `StaticMapper`, or `TemplatedMapper`?

2. **Validation**: Should we validate method signatures at compile time, or just check method existence?

3. **Flexibility**: Should we support runtime mapper switching (e.g., for multi-cart scenarios), or fully commit to compile-time?

4. **Testing**: Do we need a test suite specifically for comptime validation errors?

5. **Migration**: Should we migrate both Mapper and ChrProvider simultaneously, or one at a time?

---

## Next Steps

1. **Submit this plan to subagents for review**:
   - Architecture reviewer: Pattern consistency with hybrid architecture
   - Code reviewer: Implementation correctness and completeness
   - Documentation reviewer: Clarity for future developers

2. **Address feedback and refine plan**

3. **Begin implementation with Phase 3.1**

4. **Track progress in REFACTORING-ROADMAP.md**
