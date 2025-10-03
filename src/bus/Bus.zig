//! NES Memory Bus Module
//!
//! This module implements the complete NES memory bus following the State/Logic pattern.
//! All core components in RAMBO use this separation:
//! - State: Pure data structures (State.zig)
//! - Logic: Pure functions operating on state (Logic.zig)
//! - Module: Clean re-exports (this file)
//!
//! Features:
//! - Accurate RAM mirroring ($0000-$1FFF mirrors $0000-$07FF)
//! - Open bus behavior (data bus retains last value)
//! - ROM write protection
//! - PPU/APU register mirroring
//! - Cartridge mapper support
//!
//! AccuracyCoin Test Requirements:
//! - RAM Mirroring: 13-bit address space mirrors 11-bit RAM
//! - Open Bus: Returns last value on data bus, not zeros
//! - ROM Protection: Writes to ROM are ignored
//! - Dummy reads/writes update the data bus

// Re-export State and Logic modules
pub const State = @import("State.zig");
pub const Logic = @import("Logic.zig");

// Re-export commonly used types for convenience
pub const OpenBus = State.OpenBus;
pub const BusState = State.State;

// Backward compatibility alias
// Allows existing code to use `Bus` instead of `State.State`
pub const Bus = State.State;

/// Backward compatibility: Initialize a new bus state
/// Equivalent to State.State.init() or Logic.init()
pub inline fn init() State.State {
    return State.State.init();
}
