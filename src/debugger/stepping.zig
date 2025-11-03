//! Execution control and stepping logic
//! Pure functions operating on DebuggerState

const EmulationState = @import("../emulation/State.zig").EmulationState;
const types = @import("types.zig");
const DebugMode = types.DebugMode;

/// Continue execution
pub fn continue_(state: anytype) void {
    state.mode = .running;
    state.step_state = .{};
}

/// Pause execution
pub fn pause(state: anytype) void {
    state.mode = .paused;
}

/// Step one instruction
pub fn stepInstruction(state: anytype) void {
    state.mode = .step_instruction;
    state.step_state = .{};
}

/// Step over (skip subroutines)
pub fn stepOver(state: anytype, emu_state: *const EmulationState) void {
    state.mode = .step_over;
    state.step_state = .{
        .target_pc = null,
        .initial_sp = emu_state.cpu.sp,
    };
}

/// Step out (return from subroutine)
pub fn stepOut(state: anytype, emu_state: *const EmulationState) void {
    state.mode = .step_out;
    state.step_state = .{
        .initial_sp = emu_state.cpu.sp,
    };
}

/// Step one scanline
pub fn stepScanline(state: anytype, emu_state: *const EmulationState) void {
    state.mode = .step_scanline;
    state.step_state = .{
        .target_scanline = (@as(u16, @intCast(emu_state.ppu.scanline)) + 1) % 262,
    };
}

/// Step one frame
pub fn stepFrame(state: anytype, emu_state: *const EmulationState) void {
    state.mode = .step_frame;
    state.step_state = .{
        .target_frame = emu_state.ppu.frame_count + 1,
    };
}
