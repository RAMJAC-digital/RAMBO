//! APU Module Re-Exports
//!
//! This module provides a clean API for the APU subsystem.

pub const State = @import("State.zig");
pub const Logic = @import("Logic.zig");
pub const Dmc = @import("Dmc.zig");
pub const Envelope = @import("Envelope.zig");
pub const Sweep = @import("Sweep.zig");

// Logic modules
pub const envelope_logic = @import("logic/envelope.zig");
pub const sweep_logic = @import("logic/sweep.zig");

// Type aliases for convenience
pub const ApuState = State.ApuState;
