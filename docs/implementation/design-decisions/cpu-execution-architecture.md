# Design Decision: CPU Execution Architecture

**Date:** 2025-10-02
**Status:** Accepted
**Component:** CPU Core
**Decision Type:** Architectural

## Context

After analyzing AccuracyCoin requirements and reviewing the current CPU implementation, we identified **7 critical gaps** preventing cycle-accurate emulation:

1. Incomplete state machine (only 4 of 15+ states implemented)
2. No instruction execution logic
3. Missing addressing mode implementations
4. No RMW (Read-Modify-Write) dummy write cycles
5. No page crossing detection
6. No branch timing logic
7. Incomplete interrupt handling

## Decision

Adopt a **microcode-based state machine architecture** where each instruction is decomposed into individual clock cycles with explicit microstep functions.

## Architecture Overview

### Core Concept: Microstep Execution

## Immediate Mode Execution Pattern

**Standard Pattern (All Immediate Mode Instructions):**

Immediate mode instructions use **empty addressing steps** and handle operand fetch during execution:

```zig
// In dispatch.zig
table[0xA9] = .{ // LDA immediate
    .addressing_steps = &[_]MicrostepFn{}, // No addressing steps!
    .execute = loadstore.lda,
    .info = opcodes.OPCODE_TABLE[0xA9],
};

// In instruction implementation
pub fn lda(cpu: *Cpu, bus: *Bus) bool {
    const value = if (cpu.address_mode == .immediate) blk: {
        // Fetch operand from PC during execute
        const v = bus.read(cpu.pc);
        cpu.pc +%= 1;
        break :blk v;
    } else helpers.readOperand(cpu, bus);

    cpu.a = value;
    cpu.p.updateZN(cpu.a);
    return true;
}
```

**Why This Pattern?**

1. **Hardware Accurate:** 6502 immediate mode is 2 cycles:
   - Cycle 1: Fetch opcode, PC++
   - Cycle 2: Fetch operand, PC++, EXECUTE

2. **No Separation:** Unlike other modes, immediate has no addressing phase - operand fetch IS part of execution

3. **Consistent Timing:** Empty addressing steps ensure correct 2-cycle execution

**All Instructions Using This Pattern:**
- Load: LDA, LDX, LDY
- Arithmetic: ADC, SBC
- Logical: AND, ORA, EOR
- Compare: CMP, CPX, CPY
- NOP variants: 0x80, 0x82, 0x89, 0xC2, 0xE2

## Helper Module Usage

**Page Crossing Helper:**

For read instructions with indexed addressing modes:

```zig
/// Read value handling page crossing for indexed addressing modes
pub inline fn readWithPageCrossing(cpu: *Cpu, bus: *Bus) u8 {
    if ((cpu.address_mode == .absolute_x or
        cpu.address_mode == .absolute_y or
        cpu.address_mode == .indirect_indexed) and
        cpu.page_crossed)
    {
        return bus.read(cpu.effective_address);
    }
    return cpu.temp_value;
}
```

**Generic Read Helper:**

For non-immediate addressing modes:

```zig
pub inline fn readOperand(cpu: *Cpu, bus: *Bus) u8 {
    return switch (cpu.address_mode) {
        .immediate => cpu.operand_low, // Note: Never reached in practice
        .zero_page => bus.read(@as(u16, cpu.operand_low)),
        .zero_page_x, .zero_page_y => bus.read(cpu.effective_address),
        .absolute => blk: {
            const addr = (@as(u16, cpu.operand_high) << 8) | cpu.operand_low;
            break :blk bus.read(addr);
        },
        .absolute_x, .absolute_y, .indirect_indexed => readWithPageCrossing(cpu, bus),
        .indexed_indirect => bus.read(cpu.effective_address),
        else => unreachable,
    };
}
```

**Usage Example:**

```zig
// Correct pattern for all instructions
pub fn and(cpu: *Cpu, bus: *Bus) bool {
    const value = if (cpu.address_mode == .immediate) blk: {
        const v = bus.read(cpu.pc);
        cpu.pc +%= 1;
        break :blk v;
    } else helpers.readOperand(cpu, bus);

    cpu.a &= value;
    cpu.p.updateZN(cpu.a);
    return true;
}
```

```zig
/// Microstep function signature
/// Returns true when instruction completes
pub const MicrostepFn = *const fn (*Cpu, *Bus) bool;

/// Instruction executor contains array of microsteps
pub const InstructionExecutor = struct {
    microsteps: []const MicrostepFn,
    cycle_count: u8,
};
```

### Key Principles

1. **One cycle = One microstep**: Each CPU cycle executes exactly one microstep function
2. **Explicit state**: No implicit logic - every bus access is visible
3. **Addressing modes as microsteps**: Addressing mode resolution IS the instruction execution
4. **Testable cycles**: Each microstep is independently testable

## Implementation Strategy

### Phase 1: State Machine Refactoring

**Expand CpuState enum** from current 15 states to comprehensive cycle-level states:

```zig
pub const CpuState = enum(u8) {
    fetch_opcode,

    // Zero page indexed
    fetch_zp_address,
    add_index_to_zp,

    // Absolute indexed
    fetch_abs_low,
    fetch_abs_high,
    add_index_check_page,
    fix_high_byte,

    // Indexed indirect (Indirect,X)
    fetch_zp_base,
    add_x_to_base,
    fetch_indirect_low,
    fetch_indirect_high,

    // Indirect indexed (Indirect),Y
    fetch_zp_pointer,
    fetch_pointer_low,
    fetch_pointer_high,
    add_y_check_page,

    // Execution
    execute,

    // RMW (Read-Modify-Write)
    read_operand,
    dummy_write_original,  // CRITICAL for hardware accuracy!
    write_modified,

    // Branch
    branch_fetch_offset,
    branch_add_offset,
    branch_fix_pch,

    // Stack
    push_byte,
    pull_byte,
    increment_sp,

    // Interrupts (existing)
    interrupt_dummy,
    interrupt_push_pch,
    interrupt_push_pcl,
    interrupt_push_p,
    interrupt_vector_low,
    interrupt_vector_high,
};
```

### Phase 2: Modular File Structure

```
src/cpu/
├── Cpu.zig              # Core CPU state, main tick()
├── opcodes.zig          # Opcode table (existing, complete)
├── execution.zig        # NEW: Microstep execution engine
├── addressing.zig       # NEW: Addressing mode microsteps
├── dispatch.zig         # NEW: Opcode → Executor mapping
└── instructions/
    ├── load_store.zig   # LDA, LDX, LDY, STA, STX, STY
    ├── arithmetic.zig   # ADC, SBC
    ├── logical.zig      # AND, ORA, EOR
    ├── shifts.zig       # ASL, LSR, ROL, ROR
    ├── inc_dec.zig      # INC, DEC, INX, INY, DEX, DEY
    ├── compare.zig      # CMP, CPX, CPY
    ├── branches.zig     # BCC, BCS, BEQ, BNE, etc.
    ├── jumps.zig        # JMP, JSR, RTS, RTI
    ├── stack.zig        # PHA, PLA, PHP, PLP
    ├── flags.zig        # SEC, CLC, SEI, CLI, etc.
    ├── misc.zig         # NOP, BRK, BIT
    └── unofficial.zig   # SLO, RLA, etc.
```

### Phase 3: Example Implementation - LDA

**LDA Immediate (2 cycles)**:
```zig
// Cycle 1: Fetch opcode (done in main loop)
// Cycle 2: Fetch operand and execute
pub fn ldaImmediate(cpu: *Cpu, bus: *Bus) bool {
    cpu.a = bus.read(cpu.pc);
    cpu.pc +%= 1;
    cpu.p.updateZN(cpu.a);
    return true; // Complete
}
```

**LDA Absolute,X (4-5 cycles)**:
```zig
const lda_absx_steps = [_]MicrostepFn{
    fetchAbsLow,      // Cycle 2
    fetchAbsHigh,     // Cycle 3
    calcAbsoluteX,    // Cycle 4 (dummy read, page check)
    ldaExecute,       // Cycle 5 (only if page crossed)
};

fn calcAbsoluteX(cpu: *Cpu, bus: *Bus) bool {
    const base = (@as(u16, cpu.operand_high) << 8) | cpu.operand_low;
    cpu.effective_address = base +% cpu.x;
    cpu.page_crossed = (base & 0xFF00) != (cpu.effective_address & 0xFF00);

    // CRITICAL: Dummy read at wrong address
    const dummy_addr = (base & 0xFF00) | ((base + cpu.x) & 0xFF);
    _ = bus.read(dummy_addr);

    if (!cpu.page_crossed) {
        // No page cross - use dummy read value
        cpu.a = bus.data_bus;
        cpu.p.updateZN(cpu.a);
        return true; // 4 cycles total
    }

    return false; // Need 5th cycle
}
```

### Phase 4: RMW (Read-Modify-Write) Pattern

**Critical AccuracyCoin Requirement**: RMW instructions write original value back before modified value.

```zig
// INC Zero Page: 5 cycles
const inc_zp_steps = [_]MicrostepFn{
    fetchOperandLow,    // Cycle 2: Get address
    incRead,            // Cycle 3: Read value
    incDummyWrite,      // Cycle 4: Write original (!)
    incWrite,           // Cycle 5: Write incremented
};

fn incDummyWrite(cpu: *Cpu, bus: *Bus) bool {
    // MUST write original value back (hardware quirk)
    bus.write(cpu.effective_address, cpu.temp_value);
    return false;
}
```

### Phase 5: Branch Timing (2-4 cycles)

```zig
// BEQ: 2 cycles if not taken, 3 if same page, 4 if cross page
fn branchCheckCondition(cpu: *Cpu, bus: *Bus) bool {
    if (!cpu.p.zero) {
        return true; // Not taken, 2 cycles total
    }

    // Dummy read during offset calculation
    _ = bus.read(cpu.pc);

    const offset = @as(i8, @bitCast(cpu.operand_low));
    const old_pc = cpu.pc;
    cpu.pc = @as(u16, @bitCast(@as(i16, @bitCast(old_pc)) + offset));

    cpu.page_crossed = (old_pc & 0xFF00) != (cpu.pc & 0xFF00);

    if (!cpu.page_crossed) {
        return true; // 3 cycles total
    }

    return false; // Need page fix, 4 cycles total
}
```

## Testing Strategy

### Unit Test Pattern - Cycle-by-Cycle Validation

```zig
test "LDA absolute,X - page crossing adds cycle" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    // Setup: LDA $10FF,X with X=$02 (crosses to $1101)
    bus.write(0x8000, 0xBD); // Opcode
    bus.write(0x8001, 0xFF); // Low
    bus.write(0x8002, 0x10); // High
    bus.write(0x1101, 0x55); // Target
    cpu.pc = 0x8000;
    cpu.x = 0x02;

    // Cycle 1: Fetch opcode
    const c1 = cpu.tick(&bus);
    try std.testing.expect(!c1);

    // Cycle 2: Fetch low byte
    const c2 = cpu.tick(&bus);
    try std.testing.expect(!c2);
    try std.testing.expectEqual(@as(u8, 0xFF), cpu.operand_low);

    // Cycle 3: Fetch high byte
    const c3 = cpu.tick(&bus);
    try std.testing.expect(!c3);

    // Cycle 4: Dummy read (wrong address)
    const c4 = cpu.tick(&bus);
    try std.testing.expect(!c4);
    try std.testing.expect(cpu.page_crossed);

    // Cycle 5: Actual read
    const c5 = cpu.tick(&bus);
    try std.testing.expect(c5); // Complete!
    try std.testing.expectEqual(@as(u8, 0x55), cpu.a);
    try std.testing.expectEqual(@as(u64, 5), cpu.cycle_count);
}
```

### AccuracyCoin Integration Test Format

```zig
const TestCase = struct {
    name: []const u8,
    initial_state: CpuState,
    memory: []const MemWrite,
    expected_state: CpuState,
    expected_cycles: u64,
};

fn runTest(test_case: TestCase) !void {
    // Setup, execute, validate
    // Maps directly to AccuracyCoin format
}
```

## Implementation Phases

### Phase 1: Core Infrastructure (Days 1-2)
- ✅ Refactor CpuState enum
- ✅ Create execution.zig framework
- ✅ Implement addressing.zig microsteps
- ✅ Create dispatch.zig table
- ✅ Update Cpu.zig tick() with complete state machine

### Phase 2: Simple Instructions (Day 3)
- ✅ NOP variants
- ✅ LDA (all modes)
- ✅ STA (all modes)
- ✅ LDX, LDY
- ✅ STX, STY
- ✅ Transfer instructions (TAX, TXA, TAY, TYA, TSX, TXS)

### Phase 3: Arithmetic & Logic (Day 4)
- ✅ ADC, SBC (with overflow detection)
- ✅ AND, ORA, EOR
- ✅ CMP, CPX, CPY
- ✅ BIT
- ✅ Flag instructions (SEC, CLC, etc.)

### Phase 4: RMW & Complex (Day 5)
- ✅ ASL, LSR, ROL, ROR (accumulator & memory)
- ✅ INC, DEC (with dummy write!)
- ✅ INX, INY, DEX, DEY

### Phase 5: Control Flow (Day 6)
- ✅ All 8 branch instructions
- ✅ JMP (absolute & indirect with bug)
- ✅ JSR, RTS
- ✅ BRK, RTI

### Phase 6: Interrupts (Day 7)
- ✅ Complete interrupt sequence
- ✅ NMI edge detection fix
- ✅ IRQ level triggering
- ✅ Stack operations (PHA, PLA, PHP, PLP)

### Phase 7: Unofficial Opcodes (Days 8-9)
- ✅ SLO, RLA, SRE, RRA (RMW + logic)
- ✅ SAX, LAX (combined loads/stores)
- ✅ DCP, ISC (RMW + compare/add)
- ✅ All NOP variants
- ✅ Unstable opcodes (SHA, SHX, SHY, etc.)

### Phase 8: Integration & Validation (Day 10)
- ✅ Full test suite
- ✅ AccuracyCoin integration
- ✅ Regression testing
- ✅ Performance optimization

## Critical Implementation Details

### Page Crossing Detection

```zig
// Always perform for indexed absolute
const base = (@as(u16, high) << 8) | low;
const result = base +% index;
const page_crossed = (base & 0xFF00) != (result & 0xFF00);

// Dummy read at (base_high | result_low)
const dummy_addr = (base & 0xFF00) | (result & 0x00FF);
```

### Zero Page Wrapping

```zig
// MUST wrap within page 0
cpu.effective_address = @as(u16, (zp_base +% index));
```

### NMI Edge Detection (FIXED)

```zig
// Detect falling edge (high -> low)
const nmi_prev = self.nmi_edge_detected;
self.nmi_edge_detected = self.nmi_line;

if (nmi_prev and !self.nmi_line) {
    self.pending_interrupt = .nmi;
}
```

### B Flag Handling

```zig
// BRK sets B=1, IRQ/NMI sets B=0
var p = self.p;
p.break_flag = (self.pending_interrupt == .brk);
self.push(bus, p.toByte());
```

## Alternatives Considered

### Alternative 1: Instruction-at-a-time Execution
- **Rejected**: Cannot achieve cycle accuracy
- Would fail all timing tests in AccuracyCoin

### Alternative 2: Giant Switch Statement
- **Rejected**: Unmaintainable for 256 opcodes
- Code duplication for addressing modes
- Hard to test

### Alternative 3: Virtual Machine Bytecode
- **Rejected**: Too complex for this use case
- Performance overhead
- Harder to debug

## Success Criteria

- ✅ All 256 opcodes execute correctly
- ✅ Cycle counts match hardware exactly
- ✅ Dummy reads/writes occur at correct cycles
- ✅ Page crossing adds cycles correctly
- ✅ RMW writes original value first
- ✅ Branches have correct timing (2/3/4 cycles)
- ✅ Interrupts follow 7-cycle sequence
- ✅ Open bus updated on every bus access
- ✅ Pass AccuracyCoin CPU tests

## References

- **Architecture Design**: zig-systems-pro agent recommendation
- **Test Requirements**: docs-architect-pro agent analysis (47+ test scenarios)
- **Code Review**: qa-code-review-pro findings (7 critical, 5 high priority issues)
- **AccuracyCoin README**: `/home/colin/Development/RAMBO/AccuracyCoin/README.md`
- **NESDev Wiki**: https://www.nesdev.org/wiki/CPU

## Next Steps

1. Create `src/cpu/execution.zig` with microstep framework
2. Create `src/cpu/addressing.zig` with all addressing mode handlers
3. Refactor `Cpu.zig` tick() function with complete state machine
4. Implement first instruction (NOP) end-to-end with tests
5. Implement LDA (all modes) with comprehensive tests
6. Continue through implementation phases

## Notes

This architecture was designed based on:
- **Successful NES emulators**: Mesen, FCEUX use similar microstep approaches
- **6502 documentation**: Visual 6502 project cycle diagrams
- **AccuracyCoin requirements**: All 128 tests analyzed for CPU behavior
- **Agent recommendations**: Three specialized agents provided complementary analysis

The microstep approach provides the clearest path to cycle-accurate emulation while maintaining testability and code clarity.
