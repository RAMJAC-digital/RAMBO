# Debugger Enhancement Development Plan

**Status:** 🚧 **IN PROGRESS**
**Date:** 2025-10-04
**Based On:** Code Review by qa-code-review-pro (9.5/10 score)

## Executive Summary

This document outlines the development plan for enhancing the RAMBO debugger system with state manipulation, custom callbacks, and interrupt vector support. The current debugger foundation (Phase 4.2) is complete with all 21 tests passing.

**Current Status:**
- ✅ Core debugger: COMPLETE (21/21 tests)
- ✅ Code review: APPROVED (9.5/10)
- ✅ Zero critical issues
- 🟡 Minor fixes needed (2)

**Enhancement Goals:**
1. **State Manipulation API** - Enable register/memory/PPU editing during debugging
2. **Callback System** - Custom breakpoint conditions via function pointers
3. **Interrupt Vector Support** - Convenience methods for NMI/IRQ/RESET vectors
4. **RT-Safety Improvements** - Pre-allocated buffers for break reasons

## Code Review Summary

### Strengths Identified ✅

1. **Architecture (10/10)**
   - Exemplary external wrapper pattern
   - Clean separation between debugger and EmulationState
   - Zero contamination of core emulation code

2. **Correctness (10/10)**
   - All breakpoint types working correctly
   - Step execution modes properly implemented
   - Execution history via snapshot integration

3. **Test Coverage (10/10)**
   - 21/21 debugger tests passing
   - Comprehensive coverage of all features
   - Clear test structure (setup/action/assertion)

4. **Code Quality (9.5/10)**
   - Excellent naming conventions
   - Proper error handling
   - Minimal complexity

### Issues Identified 🟡

1. **Minor: Unused `self` parameter** (Line 536)
   - **Severity:** Low
   - **Fix Time:** 2 minutes
   - **Status:** ✅ FIXED

2. **Minor: Snapshot metadata size mismatch** (test failure)
   - **Severity:** Low
   - **Fix Time:** 10 minutes
   - **Status:** 🔲 TODO

3. **Design: Break reason allocation in hot path** (Lines 383-389)
   - **Severity:** Low (acceptable for debugging)
   - **RT-Safety:** Safe for interactive debugging
   - **Improvement:** Pre-allocated buffer option
   - **Status:** 🔲 Deferred (RT-safety enhancement)

### Gaps Identified 🟢

1. **State Manipulation** (HIGH PRIORITY)
   - Cannot modify registers/memory during debugging
   - Missing: setRegister(), writeMemory(), setPpuRegister()
   - **Impact:** Cannot test "what if" scenarios

2. **Custom Callbacks** (MEDIUM PRIORITY)
   - Fixed breakpoint conditions (A/X/Y only)
   - Missing: User-defined condition callbacks
   - **Impact:** Limited flexibility for complex conditions

3. **Interrupt Vector Helpers** (LOW PRIORITY)
   - Can use `.read` breakpoints at vector addresses
   - Missing: Convenience methods for NMI/IRQ/RESET
   - **Impact:** Minor - workaround exists

## Phase 1: State Manipulation API

### Objectives

Enable interactive state modification during debugging to support:
- Register manipulation (A, X, Y, SP, PC, status flags)
- Memory manipulation (RAM, ROM override)
- PPU state manipulation (registers, VRAM, palette)
- "What if" scenario testing

### Design Principles

1. **External Wrapper Pattern**: Maintain separation from EmulationState
2. **Validation**: Validate inputs to prevent invalid state
3. **Logging**: Track modifications for debugging history
4. **Testing**: Comprehensive test coverage for all manipulation types

### API Design

```zig
// ========================================================================
// State Manipulation - CPU Registers
// ========================================================================

/// Set accumulator register
pub fn setRegisterA(self: *Debugger, state: *EmulationState, value: u8) void {
    state.cpu.a = value;
    self.logModification(.{ .register_a = value });
}

/// Set X index register
pub fn setRegisterX(self: *Debugger, state: *EmulationState, value: u8) void {
    state.cpu.x = value;
    self.logModification(.{ .register_x = value });
}

/// Set Y index register
pub fn setRegisterY(self: *Debugger, state: *EmulationState, value: u8) void {
    state.cpu.y = value;
    self.logModification(.{ .register_y = value });
}

/// Set stack pointer
pub fn setStackPointer(self: *Debugger, state: *EmulationState, value: u8) void {
    state.cpu.sp = value;
    self.logModification(.{ .stack_pointer = value });
}

/// Set program counter
pub fn setProgramCounter(self: *Debugger, state: *EmulationState, value: u16) void {
    state.cpu.pc = value;
    self.logModification(.{ .program_counter = value });
}

/// Set individual status flag
pub fn setStatusFlag(
    self: *Debugger,
    state: *EmulationState,
    flag: StatusFlag,
    value: bool,
) void {
    switch (flag) {
        .carry => state.cpu.p.c = value,
        .zero => state.cpu.p.z = value,
        .interrupt => state.cpu.p.i = value,
        .decimal => state.cpu.p.d = value,
        .overflow => state.cpu.p.v = value,
        .negative => state.cpu.p.n = value,
    }
    self.logModification(.{ .status_flag = .{ .flag = flag, .value = value } });
}

/// Set complete status register
pub fn setStatusRegister(self: *Debugger, state: *EmulationState, value: u8) void {
    state.cpu.p = StatusFlags.fromByte(value);
    self.logModification(.{ .status_register = value });
}

// ========================================================================
// State Manipulation - Memory
// ========================================================================

/// Write single byte to memory (via bus)
pub fn writeMemory(
    self: *Debugger,
    state: *EmulationState,
    address: u16,
    value: u8,
) void {
    state.bus.write(address, value);
    self.logModification(.{ .memory_write = .{
        .address = address,
        .value = value,
    }});
}

/// Write byte range to memory
pub fn writeMemoryRange(
    self: *Debugger,
    state: *EmulationState,
    start_address: u16,
    data: []const u8,
) void {
    for (data, 0..) |byte, offset| {
        const addr = start_address +% @as(u16, @intCast(offset));
        state.bus.write(addr, byte);
    }
    self.logModification(.{ .memory_range = .{
        .start = start_address,
        .length = @intCast(data.len),
    }});
}

/// Read memory for inspection (non-modifying)
pub fn readMemory(
    self: *Debugger,
    state: *const EmulationState,
    address: u16,
) u8 {
    _ = self;
    return state.bus.read(address);
}

/// Read memory range for inspection
pub fn readMemoryRange(
    self: *Debugger,
    allocator: std.mem.Allocator,
    state: *const EmulationState,
    start_address: u16,
    length: u16,
) ![]u8 {
    _ = self;
    const buffer = try allocator.alloc(u8, length);
    for (0..length) |i| {
        buffer[i] = state.bus.read(start_address +% @as(u16, @intCast(i)));
    }
    return buffer;
}

// ========================================================================
// State Manipulation - PPU
// ========================================================================

/// Set PPU control register (PPUCTRL)
pub fn setPpuCtrl(self: *Debugger, state: *EmulationState, value: u8) void {
    state.ppu.ctrl = PpuCtrl.fromByte(value);
    self.logModification(.{ .ppu_ctrl = value });
}

/// Set PPU mask register (PPUMASK)
pub fn setPpuMask(self: *Debugger, state: *EmulationState, value: u8) void {
    state.ppu.mask = PpuMask.fromByte(value);
    self.logModification(.{ .ppu_mask = value });
}

/// Set PPU scroll position
pub fn setPpuScroll(self: *Debugger, state: *EmulationState, x: u8, y: u8) void {
    state.ppu.scroll_x = x;
    state.ppu.scroll_y = y;
    self.logModification(.{ .ppu_scroll = .{ .x = x, .y = y } });
}

/// Set PPU address register (for VRAM access)
pub fn setPpuAddr(self: *Debugger, state: *EmulationState, address: u16) void {
    state.ppu.v = address;
    self.logModification(.{ .ppu_addr = address });
}

/// Write to PPU VRAM directly (bypass normal write mechanism)
pub fn writePpuVram(
    self: *Debugger,
    state: *EmulationState,
    address: u16,
    value: u8,
) void {
    const vram_addr = address & 0x3FFF; // Mirror address
    if (vram_addr < 0x2000) {
        // CHR data (from cartridge)
        // Cannot write to CHR ROM directly
    } else if (vram_addr < 0x3F00) {
        // Nametable data
        const nt_addr = (vram_addr - 0x2000) % 0x1000;
        state.ppu.vram[nt_addr] = value;
    } else {
        // Palette data
        const palette_addr = (vram_addr - 0x3F00) % 0x20;
        state.ppu.palette_ram[palette_addr] = value;
    }
    self.logModification(.{ .ppu_vram = .{ .address = address, .value = value } });
}

/// Set PPU scanline (for testing)
pub fn setPpuScanline(self: *Debugger, state: *EmulationState, scanline: u16) void {
    state.ppu.scanline = scanline;
    self.logModification(.{ .ppu_scanline = scanline });
}

/// Set PPU frame counter
pub fn setPpuFrame(self: *Debugger, state: *EmulationState, frame: u64) void {
    state.ppu.frame = frame;
    self.logModification(.{ .ppu_frame = frame });
}
```

### Modification Logging

Track all state modifications for debugging history:

```zig
pub const StateModification = union(enum) {
    register_a: u8,
    register_x: u8,
    register_y: u8,
    stack_pointer: u8,
    program_counter: u16,
    status_flag: struct { flag: StatusFlag, value: bool },
    status_register: u8,
    memory_write: struct { address: u16, value: u8 },
    memory_range: struct { start: u16, length: u16 },
    ppu_ctrl: u8,
    ppu_mask: u8,
    ppu_scroll: struct { x: u8, y: u8 },
    ppu_addr: u16,
    ppu_vram: struct { address: u16, value: u8 },
    ppu_scanline: u16,
    ppu_frame: u64,
};

pub const Debugger = struct {
    // ...
    modifications: std.ArrayList(StateModification),

    fn logModification(self: *Debugger, modification: StateModification) void {
        self.modifications.append(self.allocator, modification) catch |err| {
            // Log error but don't fail - modification already applied
            std.debug.print("Failed to log modification: {}\n", .{err});
        };
    }

    /// Get modification history
    pub fn getModifications(self: *const Debugger) []const StateModification {
        return self.modifications.items;
    }

    /// Clear modification history
    pub fn clearModifications(self: *Debugger) void {
        self.modifications.clearRetainingCapacity();
    }
};
```

### Implementation Plan

**Day 1: CPU Register Manipulation**
- Implement setRegisterA/X/Y (30 min)
- Implement setStackPointer/ProgramCounter (30 min)
- Implement setStatusFlag/Register (1 hour)
- Write 7-10 tests for register manipulation (1 hour)
- **Total: 3 hours**

**Day 2: Memory Manipulation**
- Implement writeMemory/readMemory (30 min)
- Implement writeMemoryRange/readMemoryRange (30 min)
- Handle ROM write protection (30 min)
- Write 5-7 tests for memory manipulation (1 hour)
- **Total: 2.5 hours**

**Day 3: PPU State Manipulation**
- Implement setPpuCtrl/Mask/Scroll/Addr (1 hour)
- Implement writePpuVram with proper mirroring (1 hour)
- Implement setPpuScanline/Frame (30 min)
- Write 6-8 tests for PPU manipulation (1.5 hours)
- **Total: 4 hours**

**Day 4: Modification Logging**
- Implement StateModification enum (30 min)
- Implement logModification tracking (30 min)
- Add getModifications/clearModifications (30 min)
- Write 3-5 tests for modification logging (1 hour)
- **Total: 2.5 hours**

**Day 5: Integration & Documentation**
- Integration testing (1 hour)
- Update API documentation (1 hour)
- Code review & cleanup (1 hour)
- **Total: 3 hours**

**Phase 1 Total: 15 hours**

### Test Coverage

**Register Manipulation Tests:**
```zig
test "State Manipulation: set register A"
test "State Manipulation: set register X/Y"
test "State Manipulation: set stack pointer"
test "State Manipulation: set program counter"
test "State Manipulation: set individual status flag"
test "State Manipulation: set status register byte"
test "State Manipulation: status flag validation"
```

**Memory Manipulation Tests:**
```zig
test "State Manipulation: write single memory byte"
test "State Manipulation: write memory range"
test "State Manipulation: read memory for inspection"
test "State Manipulation: ROM write protection"
test "State Manipulation: zero page access"
test "State Manipulation: stack access"
```

**PPU Manipulation Tests:**
```zig
test "State Manipulation: set PPU control register"
test "State Manipulation: set PPU mask register"
test "State Manipulation: set PPU scroll position"
test "State Manipulation: write to nametable VRAM"
test "State Manipulation: write to palette RAM"
test "State Manipulation: set PPU scanline/frame"
test "State Manipulation: VRAM address mirroring"
```

**Modification Logging Tests:**
```zig
test "State Manipulation: track register modifications"
test "State Manipulation: track memory modifications"
test "State Manipulation: get modification history"
test "State Manipulation: clear modification history"
```

**Expected Test Count:** 25-30 new tests

## Phase 2: Callback System

### Objectives

Enable custom breakpoint conditions via function pointers to support:
- Complex condition evaluation (e.g., `cpu.a + cpu.x > 100`)
- Multi-register conditions
- PPU state-based conditions
- User-defined logic

### Design Principles

1. **Type Safety**: Use function pointers with clear signatures
2. **Performance**: Inline-able callback checks
3. **Flexibility**: Support arbitrary condition logic
4. **Testing**: Comprehensive test coverage

### API Design

```zig
// ========================================================================
// Callback System
// ========================================================================

/// Callback function signature for custom breakpoint conditions
/// Returns true if breakpoint should trigger
pub const BreakCallback = *const fn (state: *const EmulationState) bool;

/// Extended breakpoint condition with callback support
pub const BreakCondition = union(enum) {
    a_equals: u8,
    x_equals: u8,
    y_equals: u8,
    hit_count: u64,
    custom: BreakCallback, // NEW: Custom callback
};

/// Helper: Create breakpoint with custom condition
pub fn addBreakpointWithCallback(
    self: *Debugger,
    address: u16,
    bp_type: BreakpointType,
    callback: BreakCallback,
) !void {
    try self.addBreakpoint(address, bp_type);

    // Find the breakpoint we just added and set its condition
    for (self.breakpoints.items) |*bp| {
        if (bp.address == address and bp.type == bp_type) {
            bp.condition = .{ .custom = callback };
            break;
        }
    }
}

// Update checkBreakCondition to handle callbacks
fn checkBreakCondition(condition: BreakCondition, state: *const EmulationState) bool {
    return switch (condition) {
        .a_equals => |val| state.cpu.a == val,
        .x_equals => |val| state.cpu.x == val,
        .y_equals => |val| state.cpu.y == val,
        .hit_count => |_| true,
        .custom => |callback| callback(state), // NEW: Invoke callback
    };
}
```

### Example Callbacks

```zig
// Example: Break when A + X > 100
fn breakOnSumGreaterThan100(state: *const EmulationState) bool {
    const sum = @as(u16, state.cpu.a) + @as(u16, state.cpu.x);
    return sum > 100;
}

// Example: Break when on specific scanline range
fn breakOnScanlineRange(state: *const EmulationState) bool {
    return state.ppu.scanline >= 100 and state.ppu.scanline < 200;
}

// Example: Break when zero page value changes
fn breakOnZeroPageChange(state: *const EmulationState) bool {
    const value = state.bus.read(0x00);
    // Would need to track previous value - complex case
    _ = value;
    return false; // Simplified
}

// Usage:
try debugger.addBreakpointWithCallback(0x8000, .execute, &breakOnSumGreaterThan100);
```

### Implementation Plan

**Day 1: Callback Infrastructure**
- Add BreakCallback type definition (30 min)
- Extend BreakCondition with .custom (30 min)
- Update checkBreakCondition (30 min)
- Write 3-5 basic callback tests (1 hour)
- **Total: 2.5 hours**

**Day 2: Callback Helper Methods**
- Implement addBreakpointWithCallback (1 hour)
- Add example callback functions (30 min)
- Write 5-7 advanced callback tests (1.5 hours)
- **Total: 3 hours**

**Day 3: Integration & Documentation**
- Integration testing (1 hour)
- Update API documentation (1 hour)
- Code review & cleanup (30 min)
- **Total: 2.5 hours**

**Phase 2 Total: 8 hours**

### Test Coverage

**Callback Tests:**
```zig
test "Callback: simple custom condition"
test "Callback: register sum condition"
test "Callback: PPU state condition"
test "Callback: memory value condition"
test "Callback: complex multi-condition"
test "Callback: callback returning false"
test "Callback: callback with watchpoint"
test "Callback: multiple callbacks on different breakpoints"
```

**Expected Test Count:** 8-10 new tests

## Phase 3: Interrupt Vector Support

### Objectives

Provide convenience methods for interrupt vector debugging:
- NMI vector ($FFFA-$FFFB)
- RESET vector ($FFFC-$FFFD)
- IRQ/BRK vector ($FFFE-$FFFF)

### Design Principles

1. **Convenience**: Sugar over existing breakpoint system
2. **Clarity**: Clear intent (vector vs. arbitrary address)
3. **Compatibility**: Works with existing breakpoint features

### API Design

```zig
// ========================================================================
// Interrupt Vector Support
// ========================================================================

pub const InterruptVector = enum {
    nmi,    // $FFFA-$FFFB
    reset,  // $FFFC-$FFFD
    irq,    // $FFFE-$FFFF (also BRK)
};

/// Add breakpoint at interrupt vector read
pub fn addVectorBreakpoint(
    self: *Debugger,
    vector: InterruptVector,
) !void {
    const address = switch (vector) {
        .nmi => 0xFFFA,
        .reset => 0xFFFC,
        .irq => 0xFFFE,
    };

    // Break when vector is read (during interrupt)
    try self.addBreakpoint(address, .read);
}

/// Remove vector breakpoint
pub fn removeVectorBreakpoint(
    self: *Debugger,
    vector: InterruptVector,
) bool {
    const address = switch (vector) {
        .nmi => 0xFFFA,
        .reset => 0xFFFC,
        .irq => 0xFFFE,
    };

    return self.removeBreakpoint(address, .read);
}

/// Check if vector breakpoint is set
pub fn hasVectorBreakpoint(
    self: *const Debugger,
    vector: InterruptVector,
) bool {
    const address = switch (vector) {
        .nmi => 0xFFFA,
        .reset => 0xFFFC,
        .irq => 0xFFFE,
    };

    for (self.breakpoints.items) |bp| {
        if (bp.address == address and bp.type == .read) {
            return true;
        }
    }

    return false;
}
```

### Implementation Plan

**Day 1: Interrupt Vector Support**
- Implement InterruptVector enum (15 min)
- Implement addVectorBreakpoint (30 min)
- Implement removeVectorBreakpoint (15 min)
- Implement hasVectorBreakpoint (15 min)
- Write 5-7 tests (1 hour)
- **Total: 2.5 hours**

**Phase 3 Total: 2.5 hours**

### Test Coverage

**Vector Tests:**
```zig
test "Interrupt Vector: add NMI vector breakpoint"
test "Interrupt Vector: add RESET vector breakpoint"
test "Interrupt Vector: add IRQ vector breakpoint"
test "Interrupt Vector: remove vector breakpoint"
test "Interrupt Vector: check has vector breakpoint"
test "Interrupt Vector: vector breakpoint triggers on read"
```

**Expected Test Count:** 6-8 new tests

## Phase 4: RT-Safety Enhancements (Optional)

### Objectives

Improve RT-safety for use in real-time emulation loops:
- Pre-allocated break reason buffers
- Lock-free breakpoint lookup
- Zero-allocation hot paths

### Design Principles

1. **Optional**: Keep current API for debugging, add RT-safe variants
2. **Performance**: Benchmark-driven optimization
3. **Compatibility**: Don't break existing code

### API Design

```zig
// ========================================================================
// RT-Safe Variants
// ========================================================================

pub const Debugger = struct {
    // ...

    /// Pre-allocated buffer for break reasons (RT-safe)
    break_reason_buffer: [256]u8 = undefined,
    break_reason_len: usize = 0,

    /// Set break reason without allocation (RT-safe)
    fn setBreakReasonRT(self: *Debugger, comptime fmt: []const u8, args: anytype) void {
        const slice = std.fmt.bufPrint(&self.break_reason_buffer, fmt, args)
            catch {
                @memcpy(self.break_reason_buffer[0..], "Break reason formatting failed");
                self.break_reason_len = 32;
                return;
            };
        self.break_reason_len = slice.len;
        self.last_break_reason = self.break_reason_buffer[0..self.break_reason_len];
    }

    /// Get last break reason (RT-safe)
    pub fn getBreakReasonRT(self: *const Debugger) []const u8 {
        return self.break_reason_buffer[0..self.break_reason_len];
    }
};
```

### Implementation Plan

**Deferred to Future Phase** - Not critical for current debugging use case

**Priority:** Low

## Implementation Timeline

### Week 1: State Manipulation
- **Day 1:** CPU register manipulation (3 hours)
- **Day 2:** Memory manipulation (2.5 hours)
- **Day 3:** PPU state manipulation (4 hours)
- **Day 4:** Modification logging (2.5 hours)
- **Day 5:** Integration & docs (3 hours)

**Week 1 Total: 15 hours**

### Week 2: Callback System & Interrupt Vectors
- **Day 1:** Callback infrastructure (2.5 hours)
- **Day 2:** Callback helpers (3 hours)
- **Day 3:** Callback integration (2.5 hours)
- **Day 4:** Interrupt vector support (2.5 hours)
- **Day 5:** Final integration & docs (2 hours)

**Week 2 Total: 12.5 hours**

### Week 3: Polish & Optimization
- **Day 1:** Fix snapshot metadata test (1 hour)
- **Day 2:** Add edge case tests (2 hours)
- **Day 3:** Performance benchmarking (2 hours)
- **Day 4:** Documentation updates (2 hours)
- **Day 5:** Final code review & sign-off (2 hours)

**Week 3 Total: 9 hours**

**Grand Total: 36.5 hours (~5 working days)**

## Success Criteria

### Phase 1: State Manipulation
- ✅ All register manipulation methods implemented
- ✅ All memory manipulation methods implemented
- ✅ All PPU manipulation methods implemented
- ✅ Modification logging functional
- ✅ 25-30 new tests passing
- ✅ Documentation updated

### Phase 2: Callback System
- ✅ BreakCallback type defined
- ✅ Custom condition support added
- ✅ Example callbacks provided
- ✅ 8-10 new tests passing
- ✅ Documentation updated

### Phase 3: Interrupt Vector Support
- ✅ Vector enum and methods implemented
- ✅ 6-8 new tests passing
- ✅ Documentation updated

### Overall Success
- ✅ All existing tests still passing (21/21)
- ✅ All new tests passing (~45 total new tests)
- ✅ Code review score maintained (>9/10)
- ✅ Zero RT-safety violations
- ✅ No performance regressions

## Risk Assessment

### Low Risk ✅
- **State Manipulation:** Simple field assignments, well-defined API
- **Callback System:** Proven pattern (function pointers)
- **Interrupt Vectors:** Thin wrapper over existing breakpoints

### Medium Risk 🟡
- **Modification Logging:** Potential memory overhead if many modifications
- **Test Coverage:** Need comprehensive tests for all manipulation types

### Mitigation Strategies
1. **Incremental Implementation:** Complete each phase fully before moving to next
2. **Test-Driven Development:** Write tests before implementation
3. **Code Reviews:** Review each phase completion
4. **Benchmarking:** Measure performance impact

## Dependencies

### Internal Dependencies
- ✅ EmulationState structure (defined)
- ✅ Snapshot system (functional)
- ✅ Bus memory interface (functional)
- ✅ PPU register interfaces (functional)

### External Dependencies
- ✅ Zig 0.15.1 compiler
- ✅ Test infrastructure (working)

**No Blockers Identified** ✅

## Deliverables

### Code
1. `src/debugger/Debugger.zig` - Enhanced with state manipulation, callbacks, vectors
2. `tests/debugger/debugger_test.zig` - ~45 additional tests

### Documentation
1. `docs/debugger-api-guide.md` - Updated with new APIs
2. `docs/DEBUGGER-STATUS.md` - Updated with enhancement status
3. `docs/DEBUGGER-ENHANCEMENT-PLAN.md` - This document

### Validation
1. All tests passing (66+ total debugger tests)
2. Code review approval
3. Performance benchmarks documented

---

**Plan Status:** ✅ APPROVED
**Ready to Implement:** ✅ YES
**Estimated Completion:** 2025-10-11 (1 week at 5 hours/day)

**Next Step:** Begin Phase 1 - CPU Register Manipulation
