//! NES Controller Module
//!
//! Implements cycle-accurate 4021 8-bit shift register behavior.
//! Follows State/Logic separation pattern established by CPU/PPU/APU/DMA modules.
//!
//! Button order: A, B, Select, Start, Up, Down, Left, Right

pub const State = @import("State.zig");
pub const Logic = @import("Logic.zig").Logic;
pub const ButtonState = @import("ButtonState.zig").ButtonState;

pub const ControllerState = State.ControllerState;
