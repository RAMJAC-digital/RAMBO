const std = @import("std");
const RAMBO = @import("RAMBO");

const FRAME_WIDTH: u32 = 256;
const FRAME_HEIGHT: u32 = 240;
const FRAME_PIXELS: usize = FRAME_WIDTH * FRAME_HEIGHT;

const ButtonState = RAMBO.ButtonState;

const ControllerState = struct {
    controller1: ButtonState = .{},
    controller2: ButtonState = .{},
};

const wasm_allocator = std.heap.wasm_allocator;

const ErrorCode = enum(u32) {
    ok = 0,
    not_initialized = 1,
    invalid_rom = 2,
    initialization_failed = 3,
};

const Emulator = struct {
    arena: std.heap.ArenaAllocator,
    allocator: std.mem.Allocator,
    config: RAMBO.Config.Config,
    state: RAMBO.EmulationState.EmulationState,
    framebuffer: [FRAME_PIXELS]u32 = [_]u32{0} ** FRAME_PIXELS,
    controller: ControllerState = .{},

    fn init(rom_data: []const u8) !Emulator {
        var arena = std.heap.ArenaAllocator.init(wasm_allocator);
        errdefer arena.deinit();

        const allocator = arena.allocator();

        var config = RAMBO.Config.Config.init(allocator);
        errdefer config.deinit();

        var state = RAMBO.EmulationState.EmulationState.init(&config);
        errdefer state.deinit();

        const cart = try RAMBO.CartridgeLoader.loadAnyCartridgeBytes(allocator, rom_data);
        state.loadCartridge(cart);
        state.power_on();

        return Emulator{
            .arena = arena,
            .allocator = allocator,
            .config = config,
            .state = state,
        };
    }

    fn deinit(self: *Emulator) void {
        self.state.deinit();
        self.config.deinit();
        self.arena.deinit();
    }
};

var g_emulator: ?Emulator = null;
var g_pending_controller: ControllerState = .{};
var g_last_error: ErrorCode = .ok;

fn setError(code: ErrorCode) ErrorCode {
    g_last_error = code;
    return code;
}

fn getEmulator() ?*Emulator {
    return if (g_emulator) |*emu| emu else null;
}

pub export fn rambo_get_error() u32 {
    return @intFromEnum(g_last_error);
}

pub export fn rambo_init(rom_ptr: [*]const u8, rom_len: usize) u32 {
    if (rom_len == 0) return @intFromEnum(setError(.invalid_rom));

    const rom_data = rom_ptr[0..rom_len];

    if (g_emulator) |*emu| {
        emu.deinit();
        g_emulator = null;
    }

    var emulator = Emulator.init(rom_data) catch {
        return @intFromEnum(setError(.initialization_failed));
    };

    emulator.controller = g_pending_controller;

    g_emulator = emulator;
    g_last_error = .ok;
    return @intFromEnum(ErrorCode.ok);
}

pub export fn rambo_shutdown() void {
    if (g_emulator) |*emu| {
        emu.deinit();
    }
    g_emulator = null;
    g_last_error = .ok;
}

pub export fn rambo_reset() u32 {
    const emu = getEmulator() orelse return @intFromEnum(setError(.not_initialized));
    emu.state.power_on();
    g_last_error = .ok;
    return @intFromEnum(ErrorCode.ok);
}

pub export fn rambo_set_controller_state(port: u32, mask: u8) void {
    const buttons = ButtonState.fromByte(mask);

    switch (port) {
        0 => g_pending_controller.controller1 = buttons,
        1 => g_pending_controller.controller2 = buttons,
        else => return,
    }

    if (getEmulator()) |emu| {
        emu.controller = g_pending_controller;
    }
}

pub export fn rambo_step_frame() u32 {
    const emu = getEmulator() orelse return @intFromEnum(setError(.not_initialized));

    emu.state.controller.updateButtons(
        emu.controller.controller1.toByte(),
        emu.controller.controller2.toByte(),
    );

    emu.state.framebuffer = emu.framebuffer[0..];
    _ = emu.state.emulateFrame();
    emu.state.framebuffer = null;

    g_last_error = .ok;
    return @intFromEnum(ErrorCode.ok);
}

pub export fn rambo_framebuffer_ptr() usize {
    const emu = getEmulator() orelse return 0;
    return @intFromPtr(emu.framebuffer[0..].ptr);
}

pub export fn rambo_framebuffer_size() usize {
    return FRAME_PIXELS;
}

pub export fn rambo_frame_dimensions(width: *u32, height: *u32) void {
    width.* = FRAME_WIDTH;
    height.* = FRAME_HEIGHT;
}

pub export fn rambo_alloc(size: usize) usize {
    if (size == 0) return 0;
    const buf = wasm_allocator.alloc(u8, size) catch return 0;
    return @intFromPtr(buf.ptr);
}

pub export fn rambo_free(ptr: usize, size: usize) void {
    if (ptr == 0 or size == 0) return;
    const slice_ptr: [*]u8 = @ptrFromInt(ptr);
    const slice = slice_ptr[0..size];
    wasm_allocator.free(slice);
}
