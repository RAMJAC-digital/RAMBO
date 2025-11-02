//! Generic rendering backend interface using comptime duck typing
//!
//! This module provides a zero-cost abstraction for rendering backends
//! following RAMBO's comptime polymorphism pattern (similar to Cartridge mappers).
//!
//! Backend implementations must provide:
//! - init(allocator, config) !Backend
//! - deinit(*Self) void
//! - renderFrame(*Self, frame_data: []const u32) !void
//! - shouldClose(*const Self) bool
//! - pollInput(*Self) !void
//!
//! The Backend wrapper performs compile-time verification that the implementation
//! provides all required methods with correct signatures.

const std = @import("std");

/// Configuration for backend initialization
pub const BackendConfig = struct {
    /// Window/screen title
    title: []const u8 = "RAMBO NES Emulator",

    /// Initial width (implementation-dependent interpretation)
    width: u32 = 512,

    /// Initial height (implementation-dependent interpretation)
    height: u32 = 480,

    /// Verbose logging
    verbose: bool = false,
};

/// Generic backend wrapper using comptime duck typing
///
/// Usage:
/// ```zig
/// const VulkanBackend = Backend(VulkanBackendImpl);
/// var backend = try VulkanBackend.init(allocator, config);
/// defer backend.deinit();
/// try backend.renderFrame(frame_data);
/// ```
pub fn Backend(comptime Impl: type) type {
    // Compile-time interface verification
    comptime {
        if (!@hasDecl(Impl, "init")) {
            @compileError("Backend implementation must have 'init' function");
        }
        if (!@hasDecl(Impl, "deinit")) {
            @compileError("Backend implementation must have 'deinit' function");
        }
        if (!@hasDecl(Impl, "renderFrame")) {
            @compileError("Backend implementation must have 'renderFrame' function");
        }
        if (!@hasDecl(Impl, "shouldClose")) {
            @compileError("Backend implementation must have 'shouldClose' function");
        }
        if (!@hasDecl(Impl, "pollInput")) {
            @compileError("Backend implementation must have 'pollInput' function");
        }
    }

    return struct {
        const Self = @This();

        /// Backend implementation state
        impl: Impl,

        /// Initialize backend
        /// Returns error if backend initialization fails (e.g., Wayland not available)
        pub fn init(allocator: std.mem.Allocator, config: BackendConfig) !Self {
            return .{
                .impl = try Impl.init(allocator, config),
            };
        }

        /// Clean up backend resources
        pub fn deinit(self: *Self) void {
            self.impl.deinit();
        }

        /// Render a frame from emulation thread
        /// frame_data: 256×240 RGBA pixels (0xAABBGGRR little-endian)
        pub fn renderFrame(self: *Self, frame_data: []const u32) !void {
            return self.impl.renderFrame(frame_data);
        }

        /// Check if backend should close (window closed, escape pressed, etc.)
        pub fn shouldClose(self: *const Self) bool {
            return self.impl.shouldClose();
        }

        /// Poll for input events (non-blocking)
        /// Backend posts events to mailboxes as needed
        pub fn pollInput(self: *Self) !void {
            return self.impl.pollInput();
        }
    };
}
