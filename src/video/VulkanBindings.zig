//! Shared Vulkan C API Bindings
//!
//! IMPORTANT: Only this file should contain the cImport for Vulkan.
//! All other files must import from here to ensure type compatibility.

pub const c = @cImport({
    @cInclude("vulkan/vulkan.h");
    @cInclude("vulkan/vulkan_wayland.h");
});
