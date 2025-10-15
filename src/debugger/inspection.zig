//! State inspection logic
//! Pure read-only functions operating on DebuggerState and EmulationState

const std = @import("std");
const EmulationState = @import("../emulation/State.zig").EmulationState;
const types = @import("types.zig");
const StateModification = types.StateModification;

/// Read memory for inspection WITHOUT side effects
/// Does NOT update open bus - safe for debugger inspection
/// Uses EmulationState.peekMemory() to avoid side effects
pub fn readMemory(
    state: anytype,
    emu_state: *const EmulationState,
    address: u16,
) u8 {
    _ = state;
    // Use peekMemory() which does NOT update open_bus
    return emu_state.peekMemory(address);
}

/// Read memory range for inspection WITHOUT side effects
/// Does not update open bus - safe for debugger inspection
pub fn readMemoryRange(
    state: anytype,
    allocator: std.mem.Allocator,
    emu_state: *const EmulationState,
    start_address: u16,
    length: u16,
) ![]u8 {
    _ = state;
    const buffer = try allocator.alloc(u8, length);
    // Use peekMemory() which does NOT update open_bus
    for (0..length) |i| {
        buffer[i] = emu_state.peekMemory(start_address +% @as(u16, @intCast(i)));
    }
    return buffer;
}

/// Get current break reason (returns slice into static buffer)
pub fn getBreakReason(state: anytype) ?[]const u8 {
    if (state.break_reason_len == 0) return null;
    return state.break_reason_buffer[0..state.break_reason_len];
}

/// Check if debugger is currently paused
pub fn isPaused(state: anytype) bool {
    return state.mode == .paused;
}

/// Fast check for any active memory breakpoints or watchpoints
pub fn hasMemoryTriggers(state: anytype) bool {
    return state.memory_breakpoint_enabled_count > 0 or state.watchpoint_enabled_count > 0;
}

/// Fast check for any registered callbacks
pub fn hasCallbacks(state: anytype) bool {
    return state.callback_count > 0;
}

/// Get modification history
pub fn getModifications(state: anytype) []const StateModification {
    return state.modifications.items;
}

/// PPU State Inspection
pub const PpuSnapshot = struct {
    ctrl: u8,
    mask: u8,
    status: u8,
    oam_addr: u8,
    scroll_x: u8,
    scroll_y: u8,
    vram_addr: u16,
    temp_addr: u16,
    fine_x: u3,
    write_toggle: bool,
    scanline: u16,
    dot: u16,
    frame: u64,
    rendering_enabled: bool,
    warmup_complete: bool,
};

/// Capture complete PPU state for inspection
pub fn inspectPpu(emu_state: *const EmulationState) PpuSnapshot {
    const ppu = &emu_state.ppu;
    const clock = &emu_state.clock;

    return .{
        .ctrl = @bitCast(ppu.ctrl),
        .mask = @bitCast(ppu.mask),
        .status = buildStatusByte(ppu),
        .oam_addr = ppu.oam_addr,
        .scroll_x = @intCast(ppu.internal.x),
        .scroll_y = @intCast(ppu.internal.v >> 12), // coarse Y from v register
        .vram_addr = ppu.internal.v,
        .temp_addr = ppu.internal.t,
        .fine_x = ppu.internal.x,
        .write_toggle = ppu.internal.w,
        .scanline = clock.scanline(),
        .dot = clock.dot(),
        .frame = clock.frame(),
        .rendering_enabled = emu_state.rendering_enabled,
        .warmup_complete = ppu.warmup_complete,
    };
}

fn buildStatusByte(ppu: anytype) u8 {
    var result: u8 = 0;
    if (ppu.status.sprite_overflow) result |= 0x20;
    if (ppu.status.sprite_0_hit) result |= 0x40;
    // VBlank bit requires ledger, approximating with 0 for now
    return result | (ppu.open_bus.value & 0x1F);
}

/// Print PPU snapshot in human-readable format
pub fn printPpuSnapshot(snapshot: PpuSnapshot) void {
    std.debug.print("=== PPU State ===\n", .{});
    std.debug.print("PPUCTRL:  ${X:0>2}  (NMI:{} BaseNT:{} SprSize:{} BGTable:{} SprTable:{} Inc:{} NT:{})\n", .{
        snapshot.ctrl,
        (snapshot.ctrl >> 7) & 1,
        snapshot.ctrl & 3,
        (snapshot.ctrl >> 5) & 1,
        (snapshot.ctrl >> 4) & 1,
        (snapshot.ctrl >> 3) & 1,
        (snapshot.ctrl >> 2) & 1,
        snapshot.ctrl & 3,
    });
    std.debug.print("PPUMASK:  ${X:0>2}  (ShowBG:{} ShowSpr:{} ShowLeft:{} Greyscale:{})\n", .{
        snapshot.mask,
        (snapshot.mask >> 3) & 1,
        (snapshot.mask >> 4) & 1,
        ((snapshot.mask >> 1) & 1) | ((snapshot.mask >> 2) & 1),
        snapshot.mask & 1,
    });
    std.debug.print("PPUSTATUS: ${X:0>2}\n", .{snapshot.status});
    std.debug.print("Scanline: {d}  Dot: {d}  Frame: {d}\n", .{ snapshot.scanline, snapshot.dot, snapshot.frame });
    std.debug.print("VRAM Addr: ${X:0>4}  Temp: ${X:0>4}  Fine X: {d}  W: {}\n", .{
        snapshot.vram_addr,
        snapshot.temp_addr,
        snapshot.fine_x,
        snapshot.write_toggle,
    });
    std.debug.print("Rendering: {}  Warmup Complete: {}\n", .{ snapshot.rendering_enabled, snapshot.warmup_complete });
    std.debug.print("=================\n", .{});
}

/// CPU State Inspection
pub const CpuSnapshot = struct {
    pc: u16,
    a: u8,
    x: u8,
    y: u8,
    sp: u8,
    p: u8,
    cycle: u64,
};

/// Capture CPU state for inspection
pub fn inspectCpu(emu_state: *const EmulationState) CpuSnapshot {
    const cpu = &emu_state.cpu;
    const clock = &emu_state.clock;

    return .{
        .pc = cpu.pc,
        .a = cpu.a,
        .x = cpu.x,
        .y = cpu.y,
        .sp = cpu.sp,
        .p = @bitCast(cpu.p),
        .cycle = clock.cpuCycles(),
    };
}

/// Print CPU snapshot
pub fn printCpuSnapshot(snapshot: CpuSnapshot) void {
    std.debug.print("=== CPU State ===\n", .{});
    std.debug.print("PC: ${X:0>4}  A: ${X:0>2}  X: ${X:0>2}  Y: ${X:0>2}\n", .{
        snapshot.pc, snapshot.a, snapshot.x, snapshot.y
    });
    std.debug.print("SP: ${X:0>2}   P: ${X:0>2}  ", .{ snapshot.sp, snapshot.p });

    const n = (snapshot.p & 0x80) != 0;
    const v = (snapshot.p & 0x40) != 0;
    const d = (snapshot.p & 0x08) != 0;
    const i = (snapshot.p & 0x04) != 0;
    const z = (snapshot.p & 0x02) != 0;
    const c = (snapshot.p & 0x01) != 0;
    std.debug.print("[{s}{s}--{s}{s}{s}{s}]\n", .{
        if (n) "N" else "-",
        if (v) "V" else "-",
        if (d) "D" else "-",
        if (i) "I" else "-",
        if (z) "Z" else "-",
        if (c) "C" else "-",
    });
    std.debug.print("Cycle: {}\n", .{snapshot.cycle});
    std.debug.print("=================\n", .{});
}

/// Combined snapshot for frame-to-frame comparison
pub const FrameSnapshot = struct {
    frame: u64,
    cpu: CpuSnapshot,
    ppu: PpuSnapshot,
};

/// Capture complete frame state
pub fn captureFrameSnapshot(emu_state: *const EmulationState) FrameSnapshot {
    return .{
        .frame = emu_state.clock.frame(),
        .cpu = inspectCpu(emu_state),
        .ppu = inspectPpu(emu_state),
    };
}

/// Print frame snapshot
pub fn printFrameSnapshot(snapshot: FrameSnapshot) void {
    std.debug.print("\n========== FRAME {} ==========\n", .{snapshot.frame});
    printCpuSnapshot(snapshot.cpu);
    std.debug.print("\n", .{});
    printPpuSnapshot(snapshot.ppu);
    std.debug.print("==============================\n\n", .{});
}

/// Compare two frame snapshots and report differences
pub fn compareFrames(prev: FrameSnapshot, curr: FrameSnapshot) void {
    std.debug.print("\n=== Frame {} -> {} (delta: {}) ===\n", .{
        prev.frame, curr.frame, curr.frame - prev.frame
    });

    // CPU changes
    if (prev.cpu.pc != curr.cpu.pc) {
        std.debug.print("PC:    ${X:0>4} -> ${X:0>4}\n", .{prev.cpu.pc, curr.cpu.pc});
    } else {
        std.debug.print("PC:    ${X:0>4} (STUCK)\n", .{curr.cpu.pc});
    }

    const cycle_delta = curr.cpu.cycle - prev.cpu.cycle;
    std.debug.print("Cycles: {} -> {} (+{})\n", .{prev.cpu.cycle, curr.cpu.cycle, cycle_delta});

    if (prev.cpu.a != curr.cpu.a) std.debug.print("A:     ${X:0>2} -> ${X:0>2}\n", .{prev.cpu.a, curr.cpu.a});
    if (prev.cpu.x != curr.cpu.x) std.debug.print("X:     ${X:0>2} -> ${X:0>2}\n", .{prev.cpu.x, curr.cpu.x});
    if (prev.cpu.y != curr.cpu.y) std.debug.print("Y:     ${X:0>2} -> ${X:0>2}\n", .{prev.cpu.y, curr.cpu.y});
    if (prev.cpu.sp != curr.cpu.sp) std.debug.print("SP:    ${X:0>2} -> ${X:0>2}\n", .{prev.cpu.sp, curr.cpu.sp});

    // PPU changes
    if (prev.ppu.mask != curr.ppu.mask) {
        std.debug.print("PPUMASK: ${X:0>2} -> ${X:0>2}\n", .{prev.ppu.mask, curr.ppu.mask});
    }
    if (prev.ppu.ctrl != curr.ppu.ctrl) {
        std.debug.print("PPUCTRL: ${X:0>2} -> ${X:0>2}\n", .{prev.ppu.ctrl, curr.ppu.ctrl});
    }

    std.debug.print("=================================\n", .{});
}
