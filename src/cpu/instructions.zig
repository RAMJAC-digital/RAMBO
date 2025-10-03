//! CPU Instructions Module
//!
//! Re-exports all CPU instruction implementations.

pub const arithmetic = @import("instructions/arithmetic.zig");
pub const branch = @import("instructions/branch.zig");
pub const compare = @import("instructions/compare.zig");
pub const incdec = @import("instructions/incdec.zig");
pub const jumps = @import("instructions/jumps.zig");
pub const loadstore = @import("instructions/loadstore.zig");
pub const logical = @import("instructions/logical.zig");
pub const shifts = @import("instructions/shifts.zig");
pub const stack = @import("instructions/stack.zig");
pub const transfer = @import("instructions/transfer.zig");
pub const unofficial = @import("instructions/unofficial.zig");
