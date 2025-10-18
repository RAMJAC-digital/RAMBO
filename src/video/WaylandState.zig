//! Wayland Window State
//! Pure data structure - no logic
//!
//! Pattern: State/Logic separation
//! Thread: Render thread only (owned exclusively)

const std = @import("std");
const build = @import("build_options");

// Conditional Wayland imports (build-time gating)
const wayland = if (build.with_wayland) @import("wayland_client") else struct {};
const wl = if (build.with_wayland) wayland.client.wl else struct {};
const xdg = if (build.with_wayland) wayland.client.xdg else struct {};

const XdgWindowEventMailbox = @import("../mailboxes/XdgWindowEventMailbox.zig").XdgWindowEventMailbox;
const XdgInputEventMailbox = @import("../mailboxes/XdgInputEventMailbox.zig").XdgInputEventMailbox;
pub const xkb = if (build.with_wayland)
    @cImport({
        @cInclude("xkbcommon/xkbcommon.h");
    })
else
    struct {};

/// XKB keyboard context owned by render thread
pub const KeyboardContext = struct {
    context: ?*anyopaque = null,
    keymap: ?*anyopaque = null,
    state: ?*anyopaque = null,

    pub fn destroy(self: *KeyboardContext) void {
        if (self.state) |raw_state| {
            const state_ptr: *xkb.xkb_state = @ptrCast(raw_state);
            xkb.xkb_state_unref(state_ptr);
            self.state = null;
        }
        if (self.keymap) |raw_keymap| {
            const keymap_ptr: *xkb.xkb_keymap = @ptrCast(raw_keymap);
            xkb.xkb_keymap_unref(keymap_ptr);
            self.keymap = null;
        }
        if (self.context) |raw_ctx| {
            const ctx_ptr: *xkb.xkb_context = @ptrCast(raw_ctx);
            xkb.xkb_context_unref(ctx_ptr);
            self.context = null;
        }
    }

    pub fn assignKeymap(self: *KeyboardContext, keymap_ptr: *xkb.xkb_keymap, state_ptr: *xkb.xkb_state) void {
        if (self.state) |raw_state| {
            const prev_state: *xkb.xkb_state = @ptrCast(raw_state);
            xkb.xkb_state_unref(prev_state);
        }
        if (self.keymap) |raw_keymap| {
            const prev_keymap: *xkb.xkb_keymap = @ptrCast(raw_keymap);
            xkb.xkb_keymap_unref(prev_keymap);
        }

        self.keymap = @ptrCast(keymap_ptr);
        self.state = @ptrCast(state_ptr);
    }

    pub fn ensureContext(self: *KeyboardContext) bool {
        if (!build.with_wayland) return false;
        if (self.context != null) return true;

        const ctx_ptr = xkb.xkb_context_new(xkb.XKB_CONTEXT_NO_FLAGS);
        if (ctx_ptr == null) return false;

        self.context = @ptrCast(ctx_ptr.?);
        return true;
    }
};

/// Event handler context for passing state and mailboxes to listeners
/// This is passed to all Wayland protocol listeners for dependency injection
pub const EventHandlerContext = struct {
    state: *WaylandState,
    window_mailbox: *XdgWindowEventMailbox,
    input_mailbox: *XdgInputEventMailbox,
};

/// Wayland window state
/// All fields are owned by the render thread
/// Thread safety: Not thread-safe - render thread exclusive access only
pub const WaylandState = struct {
    // Core Wayland protocol objects
    display: ?*wl.Display = null,
    registry: ?*wl.Registry = null,
    compositor: ?*wl.Compositor = null,
    wm_base: ?*xdg.WmBase = null,

    // Window surface and XDG shell
    surface: ?*wl.Surface = null,
    xdg_surface: ?*xdg.Surface = null,
    toplevel: ?*xdg.Toplevel = null,

    // Input devices
    seat: ?*wl.Seat = null,
    seat_global_name: ?u32 = null,
    keyboard: ?*wl.Keyboard = null,
    pointer: ?*wl.Pointer = null,
    seat_listener_ctx_active: bool = false,
    seat_listener_ctx: EventHandlerContext = undefined,
    keyboard_listener_ctx_active: bool = false,
    keyboard_listener_ctx: EventHandlerContext = undefined,

    // Keyboard repeat information (reported by compositor)
    repeat_rate: i32 = 0,
    repeat_delay: i32 = 0,

    // Window state tracking
    current_width: u32 = 512,
    current_height: u32 = 480,
    closed: bool = false,
    is_fullscreen: bool = false,
    is_maximized: bool = false,
    is_activated: bool = true,

    // Content area from XDG configure
    content_width: u32 = 0,
    content_height: u32 = 0,

    // Pending resize (from configure events)
    pending_width: ?u32 = null,
    pending_height: ?u32 = null,

    // Mouse state
    last_x: f32 = 0,
    last_y: f32 = 0,

    // Keyboard modifiers
    mods_depressed: u32 = 0,
    mods_latched: u32 = 0,
    mods_locked: u32 = 0,
    mods_group: u32 = 0,

    keyboard_ctx: KeyboardContext = .{},

    // Dependency injection
    window_mailbox: *XdgWindowEventMailbox,
    input_mailbox: *XdgInputEventMailbox,
    allocator: std.mem.Allocator,

    registry_listener_ctx_active: bool = false,
    registry_listener_ctx: EventHandlerContext = undefined,

    xdg_surface_listener_ctx_active: bool = false,
    xdg_surface_listener_ctx: EventHandlerContext = undefined,

    toplevel_listener_ctx_active: bool = false,
    toplevel_listener_ctx: EventHandlerContext = undefined,

    pub fn resetKeyboard(self: *WaylandState) void {
        self.keyboard = null;
        self.keyboard_ctx.destroy();
        self.keyboard_ctx = .{};
        self.mods_depressed = 0;
        self.mods_latched = 0;
        self.mods_locked = 0;
        self.mods_group = 0;
        self.repeat_rate = 0;
        self.repeat_delay = 0;
        self.keyboard_listener_ctx_active = false;
    }

    pub fn setModifiers(
        self: *WaylandState,
        depressed: u32,
        latched: u32,
        locked: u32,
        group: u32,
    ) void {
        self.mods_depressed = depressed;
        self.mods_latched = latched;
        self.mods_locked = locked;
        self.mods_group = group;
    }
};
