//! Movy terminal rendering backend implementation
//!
//! Renders NES frames to terminal using movy's half-block rendering.
//! Converts RAMBO's RGBA u32 format to movy's separate RGB arrays.
//!
//! Architecture:
//! - Terminal raw mode + alternate screen
//! - Movy Screen and RenderSurface for rendering
//! - Keyboard input converted to XKB keysyms for mailbox posting
//!
//! Note: This is a development/debugging backend - frame rate and visual
//! quality are secondary to being able to see emulator output in terminal.

const std = @import("std");
const build_options = @import("build_options");

// Only import movy if enabled
const movy = if (build_options.with_movy) @import("movy") else struct {};

const BackendConfig = @import("../Backend.zig").BackendConfig;
const Mailboxes = @import("../../mailboxes/Mailboxes.zig").Mailboxes;
const KeyboardMapper = @import("../../input/KeyboardMapper.zig").KeyboardMapper;

// NES frame dimensions (full PPU output)
const FRAME_WIDTH = 256;
const FRAME_HEIGHT = 240;

// NES overscan crop (TV-safe area, 8px cropped from each edge)
// CRT TVs typically overscan ~8 pixels on all edges
const OVERSCAN_CROP_LEFT = 8;
const OVERSCAN_CROP_RIGHT = 8;
const OVERSCAN_CROP_TOP = 8;
const OVERSCAN_CROP_BOTTOM = 8;

// Display dimensions after overscan crop
const DISPLAY_WIDTH = FRAME_WIDTH - OVERSCAN_CROP_LEFT - OVERSCAN_CROP_RIGHT;   // 240 pixels
const DISPLAY_HEIGHT = FRAME_HEIGHT - OVERSCAN_CROP_TOP - OVERSCAN_CROP_BOTTOM; // 224 pixels

/// XKB keysym constants (from KeyboardMapper)
const Keymap = struct {
    // Arrow keys (D-pad)
    const KEY_UP: u32 = 0xff52;
    const KEY_DOWN: u32 = 0xff54;
    const KEY_LEFT: u32 = 0xff51;
    const KEY_RIGHT: u32 = 0xff53;

    // Action buttons
    const KEY_Z: u32 = 0x007a; // B button
    const KEY_X: u32 = 0x0078; // A button

    // System buttons
    const KEY_RSHIFT: u32 = 0xffe2; // Select
    const KEY_ENTER: u32 = 0xff0d; // Start
    const KEY_ESCAPE: u32 = 0xff1b; // Escape

    // Menu confirmation
    const KEY_Y: u32 = 0x0079; // Yes
    const KEY_N: u32 = 0x006e; // No
};

/// Menu state for overlay menu system
const MenuState = enum {
    Hidden,      // Menu not visible, game input active
    MainMenu,    // Main menu visible (Exit option)
    ConfirmExit, // Confirmation dialog visible (Y/N)
};

pub const MovyBackend = struct {
    allocator: std.mem.Allocator,
    screen: if (build_options.with_movy) movy.Screen else void,
    render_surface: if (build_options.with_movy) *movy.RenderSurface else void,
    mailboxes: *Mailboxes,
    should_close: bool,
    terminal_width: usize,
    terminal_height: usize,
    verbose: bool,

    // Performance monitoring
    frame_count: u64,
    total_frame_time_ns: u64,
    min_frame_time_ns: u64,
    max_frame_time_ns: u64,
    last_perf_report_time: i128,

    // Input handling (direct ButtonState management, bypasses XDG mailbox)
    keyboard_mapper: KeyboardMapper,
    button_press_frames: [8]u64, // Track when each button was pressed for auto-release
    auto_release_frames: u64, // Auto-release buttons after N frames (handles terminal press-only input)

    // Menu system
    menu_state: MenuState,
    menu_window: if (build_options.with_movy) ?*movy.ui.TextWindow else void,
    confirmation_window: if (build_options.with_movy) ?*movy.ui.TextWindow else void,
    menu_theme: if (build_options.with_movy) movy.ui.ColorTheme else void,
    menu_style: if (build_options.with_movy) movy.ui.Style else void,

    pub fn init(allocator: std.mem.Allocator, config: BackendConfig, mailboxes: *Mailboxes) !MovyBackend {
        if (!build_options.with_movy) {
            return error.MovyNotEnabled;
        }

        // Initialize terminal raw mode and alternate screen
        try movy.terminal.beginRawMode();
        errdefer movy.terminal.endRawMode();

        try movy.terminal.beginAlternateScreen();
        errdefer movy.terminal.endAlternateScreen();

        // Get terminal size for centering
        const term_size = try movy.terminal.getSize();
        const display_rows = DISPLAY_HEIGHT / 2; // Convert pixels to terminal rows (half-blocks)

        // Calculate center position
        const center_x: i32 = @intCast(@divTrunc(term_size.width -| DISPLAY_WIDTH, 2));
        const center_y: i32 = @intCast(@divTrunc(term_size.height -| display_rows, 2));

        // Log terminal info if verbose
        if (config.verbose) {
            std.log.info("Terminal size: {}×{} cells", .{ term_size.width, term_size.height });
            std.log.info("Display size: {}×{} pixels ({}×{} cells with half-blocks)", .{
                DISPLAY_WIDTH,
                DISPLAY_HEIGHT,
                DISPLAY_WIDTH,
                display_rows,
            });
            std.log.info("Display position: ({}, {}) - centered", .{ center_x, center_y });
            if (term_size.width < DISPLAY_WIDTH or term_size.height < display_rows) {
                std.log.warn("Terminal too small! Display will be clipped. Recommended: at least {}×{} cells", .{
                    DISPLAY_WIDTH,
                    display_rows,
                });
            }
        }

        // Create screen with overscan-cropped dimensions (240×224 pixels, TV-safe area)
        // Screen.init expects terminal rows, not pixels. Each row renders 2 pixels via half-blocks.
        // 224 pixels ÷ 2 = 112 terminal rows → Screen internally does 112 × 2 = 224 pixels
        var screen = try movy.Screen.init(allocator, DISPLAY_WIDTH, DISPLAY_HEIGHT / 2);
        errdefer screen.deinit(allocator);

        // Center the screen within the terminal
        screen.setXY(center_x, center_y * 2); // Multiply by 2 because setXY uses pixel coordinates

        screen.setScreenMode(.bgcolor);

        // Create render surface for frame conversion (cropped display size)
        const render_surface = try movy.RenderSurface.init(
            allocator,
            DISPLAY_WIDTH,
            DISPLAY_HEIGHT,
            .{ .r = 0, .g = 0, .b = 0 },
        );

        // Initialize menu theme and style
        const menu_theme = movy.ui.ColorTheme.initTokyoNightStorm();
        const menu_style = movy.ui.Style.initDefault();

        var backend = MovyBackend{
            .allocator = allocator,
            .screen = screen,
            .render_surface = render_surface,
            .mailboxes = mailboxes,
            .should_close = false,
            .terminal_width = term_size.width,
            .terminal_height = term_size.height,
            .verbose = config.verbose,
            .frame_count = 0,
            .total_frame_time_ns = 0,
            .min_frame_time_ns = std.math.maxInt(u64),
            .max_frame_time_ns = 0,
            .last_perf_report_time = std.time.nanoTimestamp(),
            .keyboard_mapper = KeyboardMapper{},
            .button_press_frames = [_]u64{0} ** 8,
            .auto_release_frames = 3, // Auto-release after 3 frames for responsive input
            .menu_state = .Hidden,
            .menu_window = null,
            .confirmation_window = null,
            .menu_theme = menu_theme,
            .menu_style = menu_style,
        };

        // Create menu windows (will be shown/hidden via menu_state)
        try backend.createMenuWindows();

        return backend;
    }

    /// Create menu and confirmation windows (called once during init)
    fn createMenuWindows(self: *MovyBackend) !void {
        if (!build_options.with_movy) return;

        const menu_width = 32;
        const menu_height = 8;
        const menu_x: i32 = @intCast(@divTrunc(self.terminal_width -| menu_width, 2));
        const menu_y: i32 = @intCast(@divTrunc(self.terminal_height -| (menu_height / 2), 2));

        // Create main menu window
        self.menu_window = try movy.ui.TextWindow.init(
            self.allocator,
            menu_x,
            menu_y,
            menu_width,
            menu_height,
            "RAMBO NES MENU",
            "> Exit",
            &self.menu_theme,
            &self.menu_style,
        );
        self.menu_window.?.base_widget.output_surface.z = 1; // Above game (z=0)

        // Create confirmation dialog window
        const confirm_width = 28;
        const confirm_height = 6;
        const confirm_x: i32 = @intCast(@divTrunc(self.terminal_width -| confirm_width, 2));
        const confirm_y: i32 = @intCast(@divTrunc(self.terminal_height -| (confirm_height / 2), 2) + 2);

        self.confirmation_window = try movy.ui.TextWindow.init(
            self.allocator,
            confirm_x,
            confirm_y,
            confirm_width,
            confirm_height,
            "Confirm Exit",
            "Exit RAMBO?\n\n(Y) Yes  (N) No",
            &self.menu_theme,
            &self.menu_style,
        );
        self.confirmation_window.?.base_widget.output_surface.z = 2; // Above menu (z=1)
    }

    pub fn deinit(self: *MovyBackend) void {
        if (!build_options.with_movy) return;

        // Cleanup menu windows
        if (self.menu_window) |menu| {
            menu.deinit(self.allocator);
        }
        if (self.confirmation_window) |confirm| {
            confirm.deinit(self.allocator);
        }

        self.render_surface.deinit(self.allocator);
        self.screen.deinit(self.allocator);
        movy.terminal.endAlternateScreen();
        movy.terminal.endRawMode();
    }

    pub fn renderFrame(self: *MovyBackend, frame_data: []const u32) !void {
        if (!build_options.with_movy) return;

        const start_time = std.time.nanoTimestamp();

        // Convert RAMBO's BGRA u32 (0xAARRGGBB) to movy's RGB format with overscan cropping
        // Vulkan uses VK_FORMAT_B8G8R8A8_UNORM: Blue=byte0, Green=byte1, Red=byte2, Alpha=byte3
        // Crop 8 pixels from each edge for TV-safe display area
        var dest_idx: usize = 0;
        var src_y: usize = OVERSCAN_CROP_TOP;
        while (src_y < FRAME_HEIGHT - OVERSCAN_CROP_BOTTOM) : (src_y += 1) {
            var src_x: usize = OVERSCAN_CROP_LEFT;
            while (src_x < FRAME_WIDTH - OVERSCAN_CROP_RIGHT) : (src_x += 1) {
                const src_idx = src_y * FRAME_WIDTH + src_x;
                const pixel = frame_data[src_idx];

                const b: u8 = @truncate(pixel & 0xFF);         // Byte 0: Blue
                const g: u8 = @truncate((pixel >> 8) & 0xFF);  // Byte 1: Green
                const r: u8 = @truncate((pixel >> 16) & 0xFF); // Byte 2: Red
                // Alpha (byte 3) is ignored

                self.render_surface.color_map[dest_idx] = .{ .r = r, .g = g, .b = b };
                self.render_surface.shadow_map[dest_idx] = 1; // Fully opaque
                dest_idx += 1;
            }
        }

        // Clear screen and render surface
        try self.screen.colorClear(self.allocator);

        // Add game surface to screen for rendering (z=0, background)
        self.screen.output_surfaces.clearRetainingCapacity();
        try self.screen.addRenderSurface(self.allocator, self.render_surface);

        // Add menu overlays if visible (z=1 for menu, z=2 for confirmation)
        if (self.menu_state == .MainMenu and self.menu_window != null) {
            _ = self.menu_window.?.render(); // Render text content to output_surface
            try self.screen.addRenderSurface(self.allocator, self.menu_window.?.base_widget.output_surface);
        } else if (self.menu_state == .ConfirmExit) {
            if (self.menu_window != null) {
                _ = self.menu_window.?.render(); // Render menu
                try self.screen.addRenderSurface(self.allocator, self.menu_window.?.base_widget.output_surface);
            }
            if (self.confirmation_window != null) {
                _ = self.confirmation_window.?.render(); // Render confirmation dialog
                try self.screen.addRenderSurface(self.allocator, self.confirmation_window.?.base_widget.output_surface);
            }
        }

        // Render to screen output surface (RenderEngine handles z-ordering)
        self.screen.render();

        // Output to terminal
        try self.screen.output();

        // Performance monitoring
        const end_time = std.time.nanoTimestamp();
        const frame_time_ns: u64 = @intCast(end_time - start_time);

        self.frame_count += 1;
        self.total_frame_time_ns += frame_time_ns;
        self.min_frame_time_ns = @min(self.min_frame_time_ns, frame_time_ns);
        self.max_frame_time_ns = @max(self.max_frame_time_ns, frame_time_ns);

        // Report performance every 60 frames (~1 second at 60 FPS)
        if (self.verbose and self.frame_count % 60 == 0) {
            const now = std.time.nanoTimestamp();
            const elapsed_sec = @as(f64, @floatFromInt(now - self.last_perf_report_time)) / 1_000_000_000.0;

            if (elapsed_sec >= 1.0) {
                const avg_frame_time_us = @as(f64, @floatFromInt(self.total_frame_time_ns)) / @as(f64, @floatFromInt(self.frame_count)) / 1000.0;
                const min_frame_time_us = @as(f64, @floatFromInt(self.min_frame_time_ns)) / 1000.0;
                const max_frame_time_us = @as(f64, @floatFromInt(self.max_frame_time_ns)) / 1000.0;
                const fps = @as(f64, @floatFromInt(self.frame_count)) / elapsed_sec;

                std.log.info("Terminal rendering: {d:.1} FPS | Frame time: avg={d:.1}µs min={d:.1}µs max={d:.1}µs", .{
                    fps,
                    avg_frame_time_us,
                    min_frame_time_us,
                    max_frame_time_us,
                });

                // Reset counters
                self.frame_count = 0;
                self.total_frame_time_ns = 0;
                self.min_frame_time_ns = std.math.maxInt(u64);
                self.max_frame_time_ns = 0;
                self.last_perf_report_time = now;
            }
        }
    }

    pub fn shouldClose(self: *const MovyBackend) bool {
        return self.should_close;
    }

    /// Map XKB keysym to button index for tracking
    fn keysymToButtonIndex(keysym: u32) ?u3 {
        return switch (keysym) {
            Keymap.KEY_X => 0,      // A button
            Keymap.KEY_Z => 1,      // B button
            Keymap.KEY_RSHIFT => 2, // Select
            Keymap.KEY_ENTER => 3,  // Start
            Keymap.KEY_UP => 4,     // D-pad Up
            Keymap.KEY_DOWN => 5,   // D-pad Down
            Keymap.KEY_LEFT => 6,   // D-pad Left
            Keymap.KEY_RIGHT => 7,  // D-pad Right
            else => null,
        };
    }

    /// Map button index back to XKB keysym for auto-release
    fn buttonIndexToKeysym(index: u3) u32 {
        return switch (index) {
            0 => Keymap.KEY_X,
            1 => Keymap.KEY_Z,
            2 => Keymap.KEY_RSHIFT,
            3 => Keymap.KEY_ENTER,
            4 => Keymap.KEY_UP,
            5 => Keymap.KEY_DOWN,
            6 => Keymap.KEY_LEFT,
            7 => Keymap.KEY_RIGHT,
        };
    }

    pub fn pollInput(self: *MovyBackend) !void {
        if (!build_options.with_movy) return;

        const current_frame = self.frame_count;

        // Step 1: Process all pending movy input events
        while (try movy.input.get()) |event| {
            switch (event) {
                .key => |key| {
                    const keysym = movyKeyToXkb(key);

                    // Handle ESC key - toggle menu visibility
                    if (keysym == Keymap.KEY_ESCAPE) {
                        switch (self.menu_state) {
                            .Hidden => self.menu_state = .MainMenu,
                            .MainMenu, .ConfirmExit => self.menu_state = .Hidden,
                        }
                        continue; // Process next event
                    }

                    // If menu is visible, handle menu input
                    if (self.menu_state != .Hidden) {
                        try self.handleMenuInput(keysym);
                        continue; // Process next event
                    }

                    // Game input: Update KeyboardMapper directly (bypasses XDG mailbox)
                    self.keyboard_mapper.keyPress(keysym);

                    // Track button press frame for auto-release
                    if (keysymToButtonIndex(keysym)) |btn_idx| {
                        self.button_press_frames[btn_idx] = current_frame;
                    }
                },
                else => {}, // Ignore non-keyboard events
            }
        }

        // Step 2: Auto-release buttons held for too long
        // Terminal can't provide key release events, so we simulate them
        inline for (0..8) |btn_idx| {
            const press_frame = self.button_press_frames[btn_idx];
            if (press_frame > 0 and current_frame >= press_frame + self.auto_release_frames) {
                const keysym = buttonIndexToKeysym(@intCast(btn_idx));
                self.keyboard_mapper.keyRelease(keysym);
                self.button_press_frames[btn_idx] = 0; // Clear tracking
            }
        }

        // Step 3: Post current button state directly to ControllerInputMailbox
        // This bypasses the XDG input event layer entirely
        const button_state = self.keyboard_mapper.getState();
        self.mailboxes.controller_input.postController1(button_state);
    }

    /// Handle menu input based on current menu state
    fn handleMenuInput(self: *MovyBackend, keysym: u32) !void {
        switch (self.menu_state) {
            .Hidden => {}, // Should never reach here

            .MainMenu => {
                // ENTER key - transition to confirmation dialog
                if (keysym == Keymap.KEY_ENTER) {
                    self.menu_state = .ConfirmExit;
                }
            },

            .ConfirmExit => {
                // Y key - confirm exit (movyKeyToXkb already handles both 'y' and 'Y')
                if (keysym == Keymap.KEY_Y) {
                    self.should_close = true;
                }
                // N key - return to main menu (movyKeyToXkb already handles both 'n' and 'N')
                else if (keysym == Keymap.KEY_N) {
                    self.menu_state = .MainMenu;
                }
            },
        }
    }

    /// Convert movy key event to XKB keysym
    fn movyKeyToXkb(key: if (build_options.with_movy) movy.input.Key else void) u32 {
        if (!build_options.with_movy) return 0;

        return switch (key.type) {
            .Up => Keymap.KEY_UP,
            .Down => Keymap.KEY_DOWN,
            .Left => Keymap.KEY_LEFT,
            .Right => Keymap.KEY_RIGHT,
            .Escape => Keymap.KEY_ESCAPE,
            .Enter => Keymap.KEY_ENTER,
            .Char => blk: {
                const char = key.sequence[0];
                if (char == 'z' or char == 'Z') break :blk Keymap.KEY_Z;
                if (char == 'x' or char == 'X') break :blk Keymap.KEY_X;
                if (char == 'y' or char == 'Y') break :blk Keymap.KEY_Y;
                if (char == 'n' or char == 'N') break :blk Keymap.KEY_N;
                if (char == '\r' or char == '\n') break :blk Keymap.KEY_ENTER;
                break :blk 0; // Unknown key
            },
            else => 0, // Unknown key type
        };
    }
};
