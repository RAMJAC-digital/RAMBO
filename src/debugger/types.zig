//! Debugger type definitions
//! All types used by the debugger system

const std = @import("std");
const EmulationState = @import("../emulation/State.zig").EmulationState;

/// User-defined callback interface
/// All callback functions are OPTIONAL - implement only what you need
/// MUST be RT-safe: no allocations, no blocking operations
///
/// Callbacks receive CONST state - they can inspect but not mutate
/// Use debugger.readMemory() for safe memory inspection
pub const DebugCallback = struct {
    /// Called before each instruction execution
    /// Return true to break, false to continue
    /// Receives const state - read-only access
    onBeforeInstruction: ?*const fn (self: *anyopaque, state: *const EmulationState) bool = null,

    /// Called on memory access (read or write)
    /// Return true to break, false to continue
    /// address: Memory address being accessed
    /// value: Value being read or written
    /// is_write: true for write, false for read
    onMemoryAccess: ?*const fn (self: *anyopaque, address: u16, value: u8, is_write: bool) bool = null,

    /// User data pointer (context for callbacks)
    userdata: *anyopaque,
};

/// Debugger execution mode
pub const DebugMode = enum {
    /// Running normally (no debugging)
    running,
    /// Paused at breakpoint
    paused,
    /// Single-step mode (step one instruction)
    step_instruction,
    /// Step over (skip subroutines)
    step_over,
    /// Step out (return from subroutine)
    step_out,
    /// Step one scanline
    step_scanline,
    /// Step one frame
    step_frame,
};

/// Breakpoint types
pub const BreakpointType = enum {
    /// Break on instruction execution at address
    execute,
    /// Break on memory read at address
    read,
    /// Break on memory write at address
    write,
    /// Break on any memory access at address
    access,
};

/// Breakpoint definition
pub const Breakpoint = struct {
    address: u16,
    type: BreakpointType,
    enabled: bool = true,
    hit_count: u64 = 0,
    condition: ?BreakCondition = null,

    pub const BreakCondition = union(enum) {
        /// Break if A register equals value
        a_equals: u8,
        /// Break if X register equals value
        x_equals: u8,
        /// Break if Y register equals value
        y_equals: u8,
        /// Break after N hits
        hit_count: u64,
    };
};

/// Watchpoint definition
pub const Watchpoint = struct {
    address: u16,
    size: u16 = 1,
    type: WatchType,
    enabled: bool = true,
    hit_count: u64 = 0,
    old_value: ?u8 = null,

    pub const WatchType = enum {
        read,
        write,
        change, // Value changed
    };
};

/// Step execution state (internal to debugger)
pub const StepState = struct {
    target_pc: ?u16 = null,
    target_sp: ?u8 = null,
    target_scanline: ?u16 = null,
    target_frame: ?u64 = null,
    initial_sp: u8 = 0,
    has_stepped: bool = false,
};

/// Execution history entry
pub const HistoryEntry = struct {
    snapshot: []u8,
    pc: u16,
    scanline: u16,
    frame: u64,
    timestamp: i64,
};

/// Debugger statistics
pub const DebugStats = struct {
    instructions_executed: u64 = 0,
    breakpoints_hit: u64 = 0,
    watchpoints_hit: u64 = 0,
    snapshots_captured: u64 = 0,
};

/// CPU status flags for manipulation
pub const StatusFlag = enum {
    carry,
    zero,
    interrupt,
    decimal,
    overflow,
    negative,
};

/// State modification record for debugging history
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
    ppu_scanline: i16,
    ppu_frame: u64,
};
