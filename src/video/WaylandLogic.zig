//! Wayland Window Logic - Simplified Phase 1 Implementation
//! Using existing mailbox APIs (lock-free ring buffer pattern)
//!
//! This is a minimal working implementation to get a window open.
//! Will expand functionality in subsequent phases.

const std = @import("std");
const log = std.log.scoped(.wayland);
const input_log = std.log.scoped(.wayland_input);
const build = @import("build_options");
const math = std.math;
const Wayland = @import("WaylandState.zig");

const WaylandState = Wayland.WaylandState;
const EventHandlerContext = Wayland.EventHandlerContext;
const posix = std.posix;
const mem = std.mem;
const XdgWindowEventMailbox = @import("../mailboxes/XdgWindowEventMailbox.zig").XdgWindowEventMailbox;
const XdgWindowEvent = @import("../mailboxes/XdgWindowEventMailbox.zig").XdgWindowEvent;
const XdgInputEventMailbox = @import("../mailboxes/XdgInputEventMailbox.zig").XdgInputEventMailbox;
const XdgInputEvent = @import("../mailboxes/XdgInputEventMailbox.zig").XdgInputEvent;

const wayland = if (build.with_wayland) @import("wayland_client") else struct {};
const wl = if (build.with_wayland) wayland.client.wl else struct {};
const xdg = if (build.with_wayland) wayland.client.xdg else struct {};
const xkb = Wayland.xkb;

// ============================================================================
// Wayland Seat & Keyboard Helpers
// ============================================================================

const seat_keyboard_bit: u32 = 1 << 1;

const SHIFT_NAME = [_:0]u8{ 'S', 'h', 'i', 'f', 't', 0 };
const CTRL_NAME = [_:0]u8{ 'C', 't', 'r', 'l', 0 };
const ALT_NAME = [_:0]u8{ 'A', 'l', 't', 0 };
const SUPER_NAME = [_:0]u8{ 'S', 'u', 'p', 'e', 'r', 0 };

fn capabilityMask(value: anytype) u32 {
    return switch (@typeInfo(@TypeOf(value))) {
        .int => |int_info| blk: {
            _ = int_info;
            const converted = math.cast(u32, value) orelse 0;
            break :blk converted;
        },
        .@"enum" => blk: {
            const raw = @intFromEnum(value);
            const converted = math.cast(u32, raw) orelse 0;
            break :blk converted;
        },
        .@"struct" => |struct_info| blk: {
            if (struct_info.layout != .@"packed" or struct_info.backing_integer == null) break :blk 0;
            const IntType = struct_info.backing_integer.?;
            const raw: IntType = @bitCast(value);
            const converted = math.cast(u32, raw) orelse 0;
            break :blk converted;
        },
        else => 0,
    };
}

fn destroyKeyboard(state: *WaylandState) void {
    state.keyboard_ctx.destroy();
    state.keyboard_ctx = .{};

    if (state.keyboard) |keyboard| {
        keyboard.release();
        state.keyboard = null;
    }

    state.keyboard_listener_ctx_active = false;
    state.keyboard_listener_ctx = EventHandlerContext{
        .state = state,
        .window_mailbox = state.window_mailbox,
        .input_mailbox = state.input_mailbox,
    };

    state.mods_depressed = 0;
    state.mods_latched = 0;
    state.mods_locked = 0;
    state.mods_group = 0;
    state.repeat_rate = 0;
    state.repeat_delay = 0;
}

fn destroySeat(state: *WaylandState) void {
    destroyKeyboard(state);

    if (state.pointer) |pointer| {
        pointer.release();
        state.pointer = null;
    }

    if (state.seat) |seat| {
        seat.release();
        state.seat = null;
    }
    state.seat_listener_ctx_active = false;
    state.seat_global_name = null;
}

fn createKeyboardListenerContext(state: *WaylandState) *EventHandlerContext {
    if (!state.keyboard_listener_ctx_active) {
        state.keyboard_listener_ctx_active = true;
        state.keyboard_listener_ctx = EventHandlerContext{
            .state = state,
            .window_mailbox = state.window_mailbox,
            .input_mailbox = state.input_mailbox,
        };
    }
    return &state.keyboard_listener_ctx;
}

fn ensureKeyboard(seat: *wl.Seat, context: *EventHandlerContext) void {
    if (context.state.keyboard != null) return;

    const keyboard = seat.getKeyboard() catch |err| {
        input_log.err("Failed to acquire wl_keyboard: {}", .{err});
        return;
    };
    context.state.keyboard = keyboard;
    input_log.info("wl_keyboard acquired (version={})", .{keyboard.getVersion()});

    const listener_ctx = createKeyboardListenerContext(context.state);
    listener_ctx.* = .{ .state = context.state, .window_mailbox = context.window_mailbox, .input_mailbox = context.input_mailbox };

    keyboard.setListener(*EventHandlerContext, keyboardListener, listener_ctx);
}

fn installKeymap(state: *WaylandState, km: anytype) void {
    var file = std.fs.File{ .handle = km.fd };
    defer file.close();

    if (km.format != .xkb_v1) {
        input_log.warn("Unsupported keymap format: {}", .{km.format});
        return;
    }

    if (km.size == 0) {
        return;
    }

    if (!state.keyboard_ctx.ensureContext()) {
        return;
    }

    const allocator = std.heap.c_allocator;
    const alloc_len = math.cast(usize, km.size) orelse return;
    if (alloc_len == 0) return;

    const mapping = posix.mmap(
        null,
        alloc_len,
        posix.PROT.READ,
        posix.MAP{ .TYPE = .SHARED },
        km.fd,
        0,
    ) catch |err| {
        input_log.err("Failed to mmap keymap: {}", .{err});
        return;
    };
    defer posix.munmap(mapping);

    const mapped = mapping[0..alloc_len];

    var buffer = allocator.alloc(u8, alloc_len + 1) catch |err| {
        input_log.err("Failed to allocate keymap buffer: {}", .{err});
        return;
    };
    defer allocator.free(buffer);

    mem.copyForwards(u8, buffer[0..alloc_len], mapped);
    buffer[alloc_len] = 0;

    const keymap_ptr = xkb.xkb_keymap_new_from_string(
        @ptrCast(state.keyboard_ctx.context.?),
        buffer.ptr,
        xkb.XKB_KEYMAP_FORMAT_TEXT_V1,
        xkb.XKB_KEYMAP_COMPILE_NO_FLAGS,
    );
    if (keymap_ptr == null) {
        input_log.err("Failed to compile keymap", .{});
        return;
    }
    input_log.info("Keymap loaded (size={} bytes)", .{alloc_len});

    const state_ptr = xkb.xkb_state_new(keymap_ptr.?);
    if (state_ptr == null) {
        input_log.err("Failed to create xkb_state", .{});
        xkb.xkb_keymap_unref(keymap_ptr.?);
        return;
    }

    state.keyboard_ctx.assignKeymap(keymap_ptr.?, state_ptr.?);
}

fn updateModifiers(state: *WaylandState, mods: anytype) void {
    state.setModifiers(mods.mods_depressed, mods.mods_latched, mods.mods_locked, mods.group);

    if (state.keyboard_ctx.state) |raw_state| {
        const xkb_state_ptr: *xkb.xkb_state = @ptrCast(raw_state);
        _ = xkb.xkb_state_update_mask(
            xkb_state_ptr,
            mods.mods_depressed,
            mods.mods_latched,
            mods.mods_locked,
            mods.group,
            0,
            0,
        );
    }
}

fn normalizedModifiers(state: *WaylandState) u32 {
    if (state.keyboard_ctx.state == null) return 0;

    const xkb_state_ptr: *xkb.xkb_state = @ptrCast(state.keyboard_ctx.state.?);
    var mask: u32 = 0;

    if (xkb.xkb_state_mod_name_is_active(xkb_state_ptr, &SHIFT_NAME, xkb.XKB_STATE_MODS_EFFECTIVE) > 0) {
        mask |= 1;
    }
    if (xkb.xkb_state_mod_name_is_active(xkb_state_ptr, &CTRL_NAME, xkb.XKB_STATE_MODS_EFFECTIVE) > 0) {
        mask |= 1 << 1;
    }
    if (xkb.xkb_state_mod_name_is_active(xkb_state_ptr, &ALT_NAME, xkb.XKB_STATE_MODS_EFFECTIVE) > 0) {
        mask |= 1 << 2;
    }
    if (xkb.xkb_state_mod_name_is_active(xkb_state_ptr, &SUPER_NAME, xkb.XKB_STATE_MODS_EFFECTIVE) > 0) {
        mask |= 1 << 3;
    }

    return mask;
}

fn postKeyEvent(
    context: *EventHandlerContext,
    keycode: u32,
    keysym: u32,
    pressed: bool,
) void {
    const modifiers = normalizedModifiers(context.state);
    const event = if (pressed)
        XdgInputEvent{ .key_press = .{ .keycode = keycode, .keysym = keysym, .modifiers = modifiers } }
    else
        XdgInputEvent{ .key_release = .{ .keycode = keycode, .keysym = keysym, .modifiers = modifiers } };

    context.input_mailbox.postEvent(event) catch |err| {
        input_log.warn("Input mailbox full (dropped key event): {}", .{err});
    };
}

fn seatListener(
    seat: *wl.Seat,
    event: wl.Seat.Event,
    context: *EventHandlerContext,
) void {
    if (!build.with_wayland) return;

    switch (event) {
        .capabilities => |caps| {
            const mask = capabilityMask(caps.capabilities);
            const has_keyboard = (mask & seat_keyboard_bit) != 0;
            if (has_keyboard) {
                ensureKeyboard(seat, context);
            } else {
                destroyKeyboard(context.state);
            }
        },
        .name => |name_event| {
            _ = name_event;
        },
    }
}

fn keyboardListener(
    keyboard: *wl.Keyboard,
    event: wl.Keyboard.Event,
    context: *EventHandlerContext,
) void {
    _ = keyboard;
    if (!build.with_wayland) return;

    switch (event) {
        .keymap => |km| installKeymap(context.state, km),
        .enter => |enter| {
            _ = enter;
        },
        .leave => |leave| {
            _ = leave;
            if (context.state.keyboard_ctx.state) |raw_state| {
                const leave_state_ptr: *xkb.xkb_state = @ptrCast(raw_state);
                _ = xkb.xkb_state_update_mask(
                    leave_state_ptr,
                    0,
                    0,
                    0,
                    0,
                    0,
                    0,
                );
            }
            context.state.setModifiers(0, 0, 0, 0);
        },
        .repeat_info => |info| {
            context.state.repeat_rate = info.rate;
            context.state.repeat_delay = info.delay;
        },
        .modifiers => |mods| updateModifiers(context.state, mods),
        .key => |key_event| {
            if (context.state.keyboard_ctx.state == null) return;

            const code = key_event.key + 8;
            const xkb_state_ptr: *xkb.xkb_state = @ptrCast(context.state.keyboard_ctx.state.?);
            const direction = switch (key_event.state) {
                .pressed => math.cast(xkb.enum_xkb_key_direction, xkb.XKB_KEY_DOWN) orelse return,
                .released => math.cast(xkb.enum_xkb_key_direction, xkb.XKB_KEY_UP) orelse return,
                else => return,
            };
            _ = xkb.xkb_state_update_key(xkb_state_ptr, code, direction);

            // Extract keysym for layout-independent key mapping
            const keysym = xkb.xkb_state_key_get_one_sym(xkb_state_ptr, code);

            input_log.debug("Key event: keycode={} keysym=0x{x:0>4} state={}", .{ code, keysym, key_event.state });
            const pressed = key_event.state == .pressed;
            postKeyEvent(context, code, keysym, pressed);
        },
    }
}

// ============================================================================
// Registry & Toplevel Listeners
// ============================================================================

fn registryListener(
    registry: *wl.Registry,
    event: wl.Registry.Event,
    context: *EventHandlerContext,
) void {
    if (!build.with_wayland) return;

    switch (event) {
        .global => |global| {
            // Simple string comparison for protocol binding
            if (std.mem.eql(u8, std.mem.span(global.interface), "wl_compositor")) {
                context.state.compositor = registry.bind(global.name, wl.Compositor, 4) catch return;
            } else if (std.mem.eql(u8, std.mem.span(global.interface), "xdg_wm_base")) {
                context.state.wm_base = registry.bind(global.name, xdg.WmBase, 2) catch return;
                context.state.wm_base.?.setListener(*EventHandlerContext, wmBaseListener, context);
            } else if (std.mem.eql(u8, std.mem.span(global.interface), "wl_seat")) {
                const seat = registry.bind(global.name, wl.Seat, 5) catch |err| {
                    input_log.err("Failed to bind wl_seat: {}", .{err});
                    return;
                };
                context.state.seat = seat;
                context.state.seat_global_name = global.name;

                context.state.seat_listener_ctx_active = true;
                context.state.seat_listener_ctx = EventHandlerContext{
                    .state = context.state,
                    .window_mailbox = context.window_mailbox,
                    .input_mailbox = context.input_mailbox,
                };

                seat.setListener(*EventHandlerContext, seatListener, &context.state.seat_listener_ctx);
            }
        },
        .global_remove => |removed| {
            if (context.state.seat_global_name != null and removed.name == context.state.seat_global_name.?) {
                destroySeat(context.state);
            }
        },
    }
}

fn wmBaseListener(
    wm_base: *xdg.WmBase,
    event: xdg.WmBase.Event,
    context: *EventHandlerContext,
) void {
    _ = context;
    if (!build.with_wayland) return;

    switch (event) {
        .ping => |p| wm_base.pong(p.serial),
    }
}

fn xdgSurfaceListener(
    surface: *xdg.Surface,
    event: xdg.Surface.Event,
    context: *EventHandlerContext,
) void {
    _ = context;
    if (!build.with_wayland) return;

    switch (event) {
        .configure => |cfg| surface.ackConfigure(cfg.serial),
    }
}

fn xdgToplevelListener(
    toplevel: *xdg.Toplevel,
    event: xdg.Toplevel.Event,
    context: *EventHandlerContext,
) void {
    _ = toplevel;
    if (!build.with_wayland) return;

    switch (event) {
        .configure => |cfg| {
            if (cfg.width > 0 and cfg.height > 0) {
                const width = @as(u32, @intCast(cfg.width));
                const height = @as(u32, @intCast(cfg.height));
                context.window_mailbox.postEvent(.{ .window_resize = .{ .width = width, .height = height } }) catch {};
            }
        },
        .close => {
            context.state.closed = true;
            context.window_mailbox.postEvent(.window_close) catch {};
        },
    }
}

// ============================================================================
// Public API
// ============================================================================

pub fn init(
    state: *WaylandState,
    allocator: std.mem.Allocator,
    window_mailbox: *XdgWindowEventMailbox,
    input_mailbox: *XdgInputEventMailbox,
) !void {
    state.* = WaylandState{
        .window_mailbox = window_mailbox,
        .input_mailbox = input_mailbox,
        .allocator = allocator,
    };

    if (!build.with_wayland) {
        log.warn("Wayland disabled at build time", .{});
        return;
    }

    // Connect to Wayland display (null = use $WAYLAND_DISPLAY)
    const display_name = std.posix.getenv("WAYLAND_DISPLAY");
    log.debug("Connecting to Wayland display: {?s}", .{display_name});

    const display = wl.Display.connect(null) catch |err| {
        log.debug("Failed to connect to Wayland display (WAYLAND_DISPLAY={?s}): {}", .{ display_name, err });
        return error.WaylandConnectFailed;
    };
    state.display = display;

    const registry = try display.getRegistry();
    state.registry = registry;

    state.registry_listener_ctx_active = true;
    state.registry_listener_ctx = EventHandlerContext{
        .state = state,
        .window_mailbox = window_mailbox,
        .input_mailbox = input_mailbox,
    };
    registry.setListener(*EventHandlerContext, registryListener, &state.registry_listener_ctx);

    _ = display.roundtrip();

    if (state.compositor == null or state.wm_base == null) {
        log.err("Required Wayland globals missing", .{});
        return error.WaylandGlobalsMissing;
    }

    const surface = try state.compositor.?.createSurface();
    state.surface = surface;

    const xdg_surface = try state.wm_base.?.getXdgSurface(surface);
    state.xdg_surface = xdg_surface;
    state.xdg_surface_listener_ctx_active = true;
    state.xdg_surface_listener_ctx = EventHandlerContext{
        .state = state,
        .window_mailbox = window_mailbox,
        .input_mailbox = input_mailbox,
    };
    xdg_surface.setListener(*EventHandlerContext, xdgSurfaceListener, &state.xdg_surface_listener_ctx);

    const toplevel = try xdg_surface.getToplevel();
    state.toplevel = toplevel;
    state.toplevel_listener_ctx_active = true;
    state.toplevel_listener_ctx = EventHandlerContext{
        .state = state,
        .window_mailbox = window_mailbox,
        .input_mailbox = input_mailbox,
    };
    toplevel.setListener(*EventHandlerContext, xdgToplevelListener, &state.toplevel_listener_ctx);

    toplevel.setTitle("RAMBO NES Emulator");
    toplevel.setAppId("rambo.nes.emulator");

    surface.commit();
    _ = display.flush();
    _ = display.roundtrip();

    log.info("Wayland window initialized successfully", .{});
    return;
}

pub fn deinit(state: *WaylandState) void {
    if (!build.with_wayland) return;

    destroySeat(state);

    if (state.toplevel) |t| t.destroy();
    if (state.xdg_surface) |xs| xs.destroy();
    if (state.surface) |s| s.destroy();
    if (state.wm_base) |wm| wm.destroy();
    if (state.compositor) |c| c.destroy();
    if (state.registry) |r| r.destroy();
    if (state.display) |dpy| wl.Display.disconnect(dpy);
}

pub fn dispatchOnce(state: *WaylandState) bool {
    if (!build.with_wayland or state.display == null) return true;

    _ = state.display.?.dispatchPending();
    _ = state.display.?.flush();
    return true;
}

pub fn rawHandles(state: *WaylandState) struct { display: ?*anyopaque, surface: ?*anyopaque } {
    if (!build.with_wayland) {
        return .{ .display = null, .surface = null };
    }

    return .{
        .display = if (state.display) |d| @as(*anyopaque, @ptrCast(d)) else null,
        .surface = if (state.surface) |s| @as(*anyopaque, @ptrCast(s)) else null,
    };
}
