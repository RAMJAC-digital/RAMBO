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
    keyboard: ?*wl.Keyboard = null,
    pointer: ?*wl.Pointer = null,

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

    // Dependency injection
    window_mailbox: *XdgWindowEventMailbox,
    input_mailbox: *XdgInputEventMailbox,
    allocator: std.mem.Allocator,
};
