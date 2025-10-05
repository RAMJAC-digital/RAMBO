//! 6502 CPU Emulation for NES
//!
//! This module implements a cycle-accurate 6502 CPU emulator targeting
//! the AccuracyCoin test suite. Key features:
//! - Cycle-by-cycle execution (not instruction-by-instruction)
//! - Accurate dummy read/write cycles
//! - Interrupt handling with proper timing
//! - Open bus behavior simulation
//! - All official and unofficial opcodes

const std = @import("std");

pub const State = @import("State.zig");
pub const Logic = @import("Logic.zig");
pub const opcodes = @import("opcodes/mod.zig");

pub const CpuState = State.CpuState;
pub const StatusFlags = State.StatusFlags;
pub const AddressingMode = State.AddressingMode;
pub const ExecutionState = State.ExecutionState;
pub const InterruptType = State.InterruptType;
