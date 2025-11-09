//! Bus Module
//!
//! NES memory bus implementation following State/Logic separation pattern.
//! Handles CPU memory access routing through zero-size stateless handlers.
//!
//! Architecture:
//! - State: RAM, open bus tracking, handler instances (all data)
//! - Logic: read(), write(), read16(), dummyRead() operations
//! - Inspection: peek() for debugger-safe reads without side effects
//!
//! Pattern matches CPU/PPU/APU/DMA/Controller modules.

pub const State = @import("State.zig");
pub const Logic = @import("Logic.zig");
pub const Inspection = @import("Inspection.zig");
