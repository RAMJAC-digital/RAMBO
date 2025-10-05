//! Pure CPU Opcode Functions - OpcodeResult Pattern
//!
//! ============================================================================
//! ARCHITECTURE: Separation of Computation from Coordination
//! ============================================================================
//!
//! This module contains ALL 256 6502 opcodes as pure functions.
//! Each opcode returns an OpcodeResult describing state changes.
//! The execution engine (Logic.zig) applies these changes via applyOpcodeResult().
//!
//! DESIGN PRINCIPLES:
//!
//! 1. PURE FUNCTIONS - No side effects, no mutations
//!    - Opcodes receive: current CPU state + operand
//!    - Opcodes return: OpcodeResult (delta describing changes)
//!    - Execution engine applies delta to actual state
//!
//! 2. DELTA PATTERN - Return only what changes
//!    - Register update? Set result.a = new_value
//!    - Flags update? Set result.flags = new_flags
//!    - Bus write? Set result.bus_write = .{ .address, .value }
//!    - Everything else? Leave as null (unchanged)
//!
//! 3. ZERO BUS ACCESS - Opcodes never touch the bus
//!    - Execution engine reads operands before calling opcode
//!    - Execution engine writes results after opcode returns
//!    - This enables testing without mocking
//!
//! 4. TESTABILITY - Pure functions are trivially testable
//!    ```zig
//!    const result = lda(CpuState.init(), 0x42);
//!    try testing.expectEqual(@as(?u8, 0x42), result.a);
//!    // No BusState needed!
//!    ```
//!
//! OPCODE CATEGORIES:
//!
//! - LOAD (LDA, LDX, LDY): Update register + flags
//! - STORE (STA, STX, STY): Return bus_write descriptor
//! - ARITHMETIC (ADC, SBC): Update A + flags (carry, overflow)
//! - LOGICAL (AND, ORA, EOR): Update A + N/Z flags
//! - COMPARE (CMP, CPX, CPY, BIT): Update flags only
//! - SHIFTS (ASL, LSR, ROL, ROR): Accumulator OR memory+bus_write
//! - INC/DEC: Memory (bus_write) OR register
//! - TRANSFER (TAX, etc.): Update register + flags
//! - FLAGS (CLC, SEC, etc.): Update flags only
//! - STACK (PHA, PHP): Return push descriptor
//! - STACK (PLA, PLP): Update register/flags (pull handled by engine)
//! - UNOFFICIAL: Same patterns as official opcodes
//!
//! EXECUTION FLOW:
//!
//! 1. Addressing microsteps populate operand/effective_address
//! 2. Execution engine extracts operand from bus/state
//! 3. Execution engine calls pure opcode: result = opcode(state, operand)
//! 4. Execution engine applies: applyOpcodeResult(state, bus, result)
//!
//! BENEFITS:
//!
//! - 📊 Testability: No mocking required
//! - 🔍 Clarity: Explicit about what changes
//! - 🚀 Performance: Delta pattern ~24 bytes vs 139 byte state copy
//! - 🧩 Composability: Can chain operations conceptually
//! - 🛡️ Safety: Immutability prevents accidental mutations
//!
//! See: tests/cpu/opcode_result_reference_test.zig for usage examples

const std = @import("std");
const StateModule = @import("../State.zig");

pub const CpuState = StateModule.PureCpuState;
pub const StatusFlags = StateModule.StatusFlags;
pub const OpcodeResult = StateModule.OpcodeResult;

// ============================================================================
// Submodule Imports
// ============================================================================

const loadstore = @import("loadstore.zig");
const arithmetic = @import("arithmetic.zig");
const logical = @import("logical.zig");
const compare = @import("compare.zig");
const flags = @import("flags.zig");
const transfer = @import("transfer.zig");
const stack = @import("stack.zig");
const incdec = @import("incdec.zig");
const shifts = @import("shifts.zig");
const branch = @import("branch.zig");
const control = @import("control.zig");
const unofficial = @import("unofficial.zig");

// ============================================================================
// Load/Store Instructions - Re-exports
// ============================================================================

pub const lda = loadstore.lda;
pub const ldx = loadstore.ldx;
pub const ldy = loadstore.ldy;
pub const sta = loadstore.sta;
pub const stx = loadstore.stx;
pub const sty = loadstore.sty;

// ============================================================================
// Arithmetic Instructions - Re-exports
// ============================================================================

pub const adc = arithmetic.adc;
pub const sbc = arithmetic.sbc;

// ============================================================================
// Logical Instructions - Re-exports
// ============================================================================

pub const logicalAnd = logical.logicalAnd;
pub const logicalOr = logical.logicalOr;
pub const logicalXor = logical.logicalXor;

// ============================================================================
// Compare Instructions - Re-exports
// ============================================================================

pub const cmp = compare.cmp;
pub const cpx = compare.cpx;
pub const cpy = compare.cpy;
pub const bit = compare.bit;

// ============================================================================
// Shift/Rotate Instructions - Re-exports
// ============================================================================

pub const aslAcc = shifts.aslAcc;
pub const aslMem = shifts.aslMem;
pub const lsrAcc = shifts.lsrAcc;
pub const lsrMem = shifts.lsrMem;
pub const rolAcc = shifts.rolAcc;
pub const rolMem = shifts.rolMem;
pub const rorAcc = shifts.rorAcc;
pub const rorMem = shifts.rorMem;

// ============================================================================
// Increment/Decrement Instructions - Re-exports
// ============================================================================

pub const inc = incdec.inc;
pub const dec = incdec.dec;
pub const inx = incdec.inx;
pub const iny = incdec.iny;
pub const dex = incdec.dex;
pub const dey = incdec.dey;

// ============================================================================
// Transfer Instructions - Re-exports
// ============================================================================

pub const tax = transfer.tax;
pub const tay = transfer.tay;
pub const txa = transfer.txa;
pub const tya = transfer.tya;
pub const tsx = transfer.tsx;
pub const txs = transfer.txs;

// ============================================================================
// Flag Instructions - Re-exports
// ============================================================================

pub const clc = flags.clc;
pub const cld = flags.cld;
pub const cli = flags.cli;
pub const clv = flags.clv;
pub const sec = flags.sec;
pub const sed = flags.sed;
pub const sei = flags.sei;

// ============================================================================
// Stack Instructions - Re-exports
// ============================================================================

pub const pha = stack.pha;
pub const php = stack.php;
pub const pla = stack.pla;
pub const plp = stack.plp;

// ============================================================================
// Branch Instructions - Re-exports
// ============================================================================

pub const bcc = branch.bcc;
pub const bcs = branch.bcs;
pub const beq = branch.beq;
pub const bne = branch.bne;
pub const bmi = branch.bmi;
pub const bpl = branch.bpl;
pub const bvc = branch.bvc;
pub const bvs = branch.bvs;

// ============================================================================
// Control Flow Instructions - Re-exports
// ============================================================================

pub const jmp = control.jmp;
pub const nop = control.nop;

// ============================================================================
// Unofficial/Undocumented Instructions - Re-exports
// ============================================================================

pub const lax = unofficial.lax;
pub const sax = unofficial.sax;
pub const lae = unofficial.lae;
pub const anc = unofficial.anc;
pub const alr = unofficial.alr;
pub const arr = unofficial.arr;
pub const axs = unofficial.axs;
pub const sha = unofficial.sha;
pub const shx = unofficial.shx;
pub const shy = unofficial.shy;
pub const tas = unofficial.tas;
pub const xaa = unofficial.xaa;
pub const lxa = unofficial.lxa;
pub const jam = unofficial.jam;
pub const slo = unofficial.slo;
pub const rla = unofficial.rla;
pub const sre = unofficial.sre;
pub const rra = unofficial.rra;
pub const dcp = unofficial.dcp;
pub const isc = unofficial.isc;
