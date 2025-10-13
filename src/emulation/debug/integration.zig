//! Debugger Integration Logic - Breakpoints, Watchpoints, and Pause Management
//!
//! This module provides the integration layer between EmulationState and the Debugger subsystem.
//! Functions here handle:
//! - Debugger pause state queries
//! - Memory access watchpoint triggers
//! - Breakpoint evaluation during emulation
//!
//! Side Effects:
//! - checkMemoryAccess() may set state.debug_break_occurred flag
//! - All other functions are read-only

/// Determine if debugger is attached and currently holding execution
///
/// Parameters:
///   - state: Const pointer to emulation state (read-only)
///
/// Returns: true if debugger is paused, false otherwise
pub fn shouldHalt(state: anytype) bool {
    if (state.debugger) |*debugger| {
        return debugger.isPaused();
    }
    return false;
}

/// Public helper for external threads to query pause state
///
/// Parameters:
///   - state: Const pointer to emulation state (read-only)
///
/// Returns: true if debugger is paused, false otherwise
pub fn isPaused(state: anytype) bool {
    return shouldHalt(state);
}

/// Notify debugger about memory accesses (breakpoint/watchpoint handling)
///
/// Side Effects:
/// - May set state.debug_break_occurred = true if watchpoint triggers
///
/// Parameters:
///   - state: Mutable pointer to emulation state (may modify debug_break_occurred)
///   - address: Memory address being accessed
///   - value: Byte value being read/written
///   - is_write: true for writes, false for reads
pub fn checkMemoryAccess(state: anytype, address: u16, value: u8, is_write: bool) void {
    if (state.debugger) |*debugger| {
        // Fast bail-out: no breakpoints/watchpoints and no callbacks registered
        if (!debugger.hasMemoryTriggers() and !debugger.hasCallbacks()) return;

        const should_break = debugger.checkMemoryAccess(state, address, value, is_write) catch false;
        if (should_break) {
            state.debug_break_occurred = true;
        }
    }
}
