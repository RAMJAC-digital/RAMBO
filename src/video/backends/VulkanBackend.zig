//! Vulkan rendering backend implementation
//!
//! Thin adapter layer that wraps existing Wayland + Vulkan rendering stack
//! to conform to the Backend interface.
//!
//! Architecture:
//! - Wayland window management (XDG shell protocol)
//! - Vulkan rendering pipeline (texture upload + fullscreen quad)
//! - Input events posted to XdgInputEventMailbox
//!
//! Note: This is just an adapter - actual rendering logic remains in
//! VulkanLogic.zig and WaylandLogic.zig (zero code duplication)

const std = @import("std");
const WaylandState = @import("../WaylandState.zig").WaylandState;
const WaylandLogic = @import("../WaylandLogic.zig");
const VulkanLogic = @import("../VulkanLogic.zig");
const VulkanState = @import("../VulkanState.zig").VulkanState;
const BackendConfig = @import("../Backend.zig").BackendConfig;
const Mailboxes = @import("../../mailboxes/Mailboxes.zig").Mailboxes;

/// Vulkan backend state
pub const VulkanBackend = struct {
    allocator: std.mem.Allocator,
    wayland: WaylandState,
    vulkan: VulkanState,

    /// Initialize Wayland + Vulkan rendering backend
    pub fn init(allocator: std.mem.Allocator, config: BackendConfig, mailboxes: *Mailboxes) !VulkanBackend {
        _ = config; // Config currently unused, Wayland/Vulkan use defaults

        // Initialize Wayland window with mailbox dependency injection
        var wayland: WaylandState = undefined;
        try WaylandLogic.init(&wayland, allocator, &mailboxes.xdg_window_event, &mailboxes.xdg_input_event);
        errdefer WaylandLogic.deinit(&wayland);

        // Initialize Vulkan renderer
        const vulkan = try VulkanLogic.init(allocator, &wayland);

        return .{
            .allocator = allocator,
            .wayland = wayland,
            .vulkan = vulkan,
        };
    }

    /// Clean up Wayland and Vulkan resources
    pub fn deinit(self: *VulkanBackend) void {
        VulkanLogic.deinit(&self.vulkan);
        WaylandLogic.deinit(&self.wayland);
    }

    /// Render frame using Vulkan
    /// frame_data: 256×240 RGBA pixels (0xAABBGGRR little-endian)
    pub fn renderFrame(self: *VulkanBackend, frame_data: []const u32) !void {
        return VulkanLogic.renderFrame(&self.vulkan, frame_data);
    }

    /// Check if Wayland window was closed
    pub fn shouldClose(self: *const VulkanBackend) bool {
        return self.wayland.closed;
    }

    /// Poll Wayland events (non-blocking)
    /// Events are posted to XdgInputEventMailbox by WaylandLogic
    pub fn pollInput(self: *VulkanBackend) !void {
        _ = WaylandLogic.dispatchOnce(&self.wayland);
    }
};
