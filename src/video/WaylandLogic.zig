//! Wayland Window Logic - Simplified Phase 1 Implementation
//! Using existing mailbox APIs (lock-free ring buffer pattern)
//!
//! This is a minimal working implementation to get a window open.
//! Will expand functionality in subsequent phases.

const std = @import("std");
const log = std.log.scoped(.wayland);
const build = @import("build_options");

const WaylandState = @import("WaylandState.zig").WaylandState;
const EventHandlerContext = @import("WaylandState.zig").EventHandlerContext;
const XdgWindowEventMailbox = @import("../mailboxes/XdgWindowEventMailbox.zig").XdgWindowEventMailbox;
const XdgWindowEvent = @import("../mailboxes/XdgWindowEventMailbox.zig").XdgWindowEvent;
const XdgInputEventMailbox = @import("../mailboxes/XdgInputEventMailbox.zig").XdgInputEventMailbox;
const XdgInputEvent = @import("../mailboxes/XdgInputEventMailbox.zig").XdgInputEvent;

const wayland = if (build.with_wayland) @import("wayland_client") else struct {};
const wl = if (build.with_wayland) wayland.client.wl else struct {};
const xdg = if (build.with_wayland) wayland.client.xdg else struct {};

// ============================================================================
// Minimal Listener Stubs (Phase 1 - Just get window open)
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
                context.state.seat = registry.bind(global.name, wl.Seat, 5) catch return;
            }
        },
        .global_remove => {},
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
    allocator: std.mem.Allocator,
    window_mailbox: *XdgWindowEventMailbox,
    input_mailbox: *XdgInputEventMailbox,
) !WaylandState {
    var state = WaylandState{
        .window_mailbox = window_mailbox,
        .input_mailbox = input_mailbox,
        .allocator = allocator,
    };

    if (!build.with_wayland) {
        log.warn("Wayland disabled at build time", .{});
        return state;
    }

    // Connect to Wayland display (null = use $WAYLAND_DISPLAY)
    const display_name = std.posix.getenv("WAYLAND_DISPLAY");
    log.debug("Connecting to Wayland display: {?s}", .{display_name});

    const display = wl.Display.connect(null) catch |err| {
        log.debug("Failed to connect to Wayland display (WAYLAND_DISPLAY={?s}): {}", .{display_name, err});
        return error.WaylandConnectFailed;
    };
    state.display = display;

    const registry = try display.getRegistry();
    state.registry = registry;

    const registry_context = try allocator.create(EventHandlerContext);
    registry_context.* = .{ .state = &state, .window_mailbox = window_mailbox, .input_mailbox = input_mailbox };
    registry.setListener(*EventHandlerContext, registryListener, registry_context);

    _ = display.roundtrip();

    if (state.compositor == null or state.wm_base == null) {
        log.err("Required Wayland globals missing", .{});
        return error.WaylandGlobalsMissing;
    }

    const surface = try state.compositor.?.createSurface();
    state.surface = surface;

    const xdg_surface = try state.wm_base.?.getXdgSurface(surface);
    state.xdg_surface = xdg_surface;
    const xdg_context = try allocator.create(EventHandlerContext);
    xdg_context.* = .{ .state = &state, .window_mailbox = window_mailbox, .input_mailbox = input_mailbox };
    xdg_surface.setListener(*EventHandlerContext, xdgSurfaceListener, xdg_context);

    const toplevel = try xdg_surface.getToplevel();
    state.toplevel = toplevel;
    const toplevel_context = try allocator.create(EventHandlerContext);
    toplevel_context.* = .{ .state = &state, .window_mailbox = window_mailbox, .input_mailbox = input_mailbox };
    toplevel.setListener(*EventHandlerContext, xdgToplevelListener, toplevel_context);

    toplevel.setTitle("RAMBO NES Emulator");
    toplevel.setAppId("rambo.nes.emulator");

    surface.commit();
    _ = display.flush();

    log.info("Wayland window initialized successfully", .{});
    return state;
}

pub fn deinit(state: *WaylandState) void {
    if (!build.with_wayland) return;

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
