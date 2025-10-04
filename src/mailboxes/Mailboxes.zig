//! Central mailbox container for dependency injection
//! Eliminates global state by providing a single struct that owns all mailbox instances
//!
//! Based on zzt-backup's mailbox pattern with by-value ownership to prevent memory leaks.

const std = @import("std");

// Forward declarations for mailbox types
const WaylandEventMailbox = @import("WaylandEventMailbox.zig").WaylandEventMailbox;
const FrameMailbox = @import("FrameMailbox.zig").FrameMailbox;
const ConfigMailbox = @import("ConfigMailbox.zig").ConfigMailbox;

/// Container for all application mailboxes
/// Uses by-value ownership to prevent memory leaks
/// Pass pointers to threads for dependency injection
pub const Mailboxes = struct {
    /// Wayland window events (Wayland thread → Main thread)
    wayland: WaylandEventMailbox,

    /// Frame buffers (Emulation thread → Render thread)
    frame: FrameMailbox,

    /// Configuration updates (Main thread → Emulation thread)
    config: ConfigMailbox,

    /// Initialize all mailboxes
    pub fn init(allocator: std.mem.Allocator) !Mailboxes {
        return Mailboxes{
            .wayland = try WaylandEventMailbox.init(allocator),
            .frame = try FrameMailbox.init(allocator),
            .config = ConfigMailbox.init(allocator),
        };
    }

    /// Cleanup all mailboxes
    pub fn deinit(self: *Mailboxes) void {
        self.config.deinit();
        self.frame.deinit();
        self.wayland.deinit();
    }
};

// ============================================================================
// Tests
// ============================================================================

test "mailboxes by-value memory safety" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var mailboxes = try Mailboxes.init(allocator);
    defer mailboxes.deinit();

    // Verify pointers can be taken for dependency injection
    _ = &mailboxes.wayland;
    _ = &mailboxes.frame;
    _ = &mailboxes.config;
}
