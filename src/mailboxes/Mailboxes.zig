//! Central mailbox container for dependency injection
//! Eliminates global state by providing a single struct that owns all mailbox instances
//!
//! Based on zzt-backup's mailbox pattern with by-value ownership to prevent memory leaks.

const std = @import("std");

// Mailbox imports (re-exported for external use)
const ControllerInputMailboxMod = @import("ControllerInputMailbox.zig");
const EmulationCommandMailboxMod = @import("EmulationCommandMailbox.zig");
const SpeedControlMailboxMod = @import("SpeedControlMailbox.zig");
const FrameMailboxMod = @import("FrameMailbox.zig");
const EmulationStatusMailboxMod = @import("EmulationStatusMailbox.zig");
const XdgWindowEventMailboxMod = @import("XdgWindowEventMailbox.zig");
const XdgInputEventMailboxMod = @import("XdgInputEventMailbox.zig");
const RenderStatusMailboxMod = @import("RenderStatusMailbox.zig");
const ConfigMailboxMod = @import("ConfigMailbox.zig");
const DebugCommandMailboxMod = @import("DebugCommandMailbox.zig");
const DebugEventMailboxMod = @import("DebugEventMailbox.zig");

// Re-export mailbox types
pub const ControllerInputMailbox = ControllerInputMailboxMod.ControllerInputMailbox;
pub const EmulationCommandMailbox = EmulationCommandMailboxMod.EmulationCommandMailbox;
pub const SpeedControlMailbox = SpeedControlMailboxMod.SpeedControlMailbox;
pub const FrameMailbox = FrameMailboxMod.FrameMailbox;
pub const EmulationStatusMailbox = EmulationStatusMailboxMod.EmulationStatusMailbox;
pub const XdgWindowEventMailbox = XdgWindowEventMailboxMod.XdgWindowEventMailbox;
pub const XdgInputEventMailbox = XdgInputEventMailboxMod.XdgInputEventMailbox;
pub const RenderStatusMailbox = RenderStatusMailboxMod.RenderStatusMailbox;
pub const ConfigMailbox = ConfigMailboxMod.ConfigMailbox;
pub const DebugCommandMailbox = DebugCommandMailboxMod.DebugCommandMailbox;
pub const DebugEventMailbox = DebugEventMailboxMod.DebugEventMailbox;

// Re-export event types for convenience
pub const XdgWindowEvent = XdgWindowEventMailboxMod.XdgWindowEvent;
pub const XdgInputEvent = XdgInputEventMailboxMod.XdgInputEvent;
pub const ControllerButtonState = ControllerInputMailboxMod.ButtonState;
pub const ControllerInput = ControllerInputMailboxMod.ControllerInput;
pub const DebugCommand = DebugCommandMailboxMod.DebugCommand;
pub const DebugEvent = DebugEventMailboxMod.DebugEvent;
pub const CpuSnapshot = DebugEventMailboxMod.CpuSnapshot;

/// Container for all application mailboxes
/// Uses by-value ownership to prevent memory leaks
/// Pass pointers to threads for dependency injection
pub const Mailboxes = struct {
    // Emulation Input Mailboxes (Main → Emulation)
    controller_input: ControllerInputMailbox,
    emulation_command: EmulationCommandMailbox,
    speed_control: SpeedControlMailbox,
    debug_command: DebugCommandMailbox,

    // Emulation Output Mailboxes (Emulation → Render/Main)
    frame: FrameMailbox,
    emulation_status: EmulationStatusMailbox,
    debug_event: DebugEventMailbox,

    // Render Thread Mailboxes (Render ↔ Main)
    xdg_window_event: XdgWindowEventMailbox,
    xdg_input_event: XdgInputEventMailbox,
    render_status: RenderStatusMailbox,

    // Legacy (will be removed once replaced)
    config: ConfigMailbox,

    /// Initialize all mailboxes
    pub fn init(allocator: std.mem.Allocator) Mailboxes {
        return Mailboxes{
            .controller_input = ControllerInputMailbox.init(allocator),
            .emulation_command = EmulationCommandMailbox.init(allocator),
            .speed_control = SpeedControlMailbox.init(allocator),
            .debug_command = DebugCommandMailbox.init(),
            .frame = FrameMailbox.init(), // Pure atomic - no allocator needed
            .emulation_status = EmulationStatusMailbox.init(allocator),
            .debug_event = DebugEventMailbox.init(),
            .xdg_window_event = XdgWindowEventMailbox.init(allocator),
            .xdg_input_event = XdgInputEventMailbox.init(allocator),
            .render_status = RenderStatusMailbox.init(allocator),
            .config = ConfigMailbox.init(allocator),
        };
    }

    /// Cleanup all mailboxes
    pub fn deinit(self: *Mailboxes) void {
        self.config.deinit();
        self.render_status.deinit();
        self.xdg_input_event.deinit();
        self.xdg_window_event.deinit();
        // debug_event - no cleanup needed (stack-only)
        self.emulation_status.deinit();
        self.frame.deinit();
        // debug_command - no cleanup needed (stack-only)
        self.speed_control.deinit();
        self.emulation_command.deinit();
        self.controller_input.deinit();
    }
};

// ============================================================================
// Tests
// ============================================================================

test "mailboxes by-value memory safety" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var mailboxes = Mailboxes.init(allocator);
    defer mailboxes.deinit();

    // Verify pointers can be taken for dependency injection
    _ = &mailboxes.controller_input;
    _ = &mailboxes.emulation_command;
    _ = &mailboxes.speed_control;
    _ = &mailboxes.frame;
    _ = &mailboxes.emulation_status;
    _ = &mailboxes.xdg_window_event;
    _ = &mailboxes.xdg_input_event;
    _ = &mailboxes.render_status;
    _ = &mailboxes.config;
}
