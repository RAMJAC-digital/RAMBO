//! Vulkan Renderer Logic - Orchestration Layer
//!
//! Coordinates Vulkan initialization, rendering, and cleanup by delegating
//! to specialized modules:
//! - core: Instance, Surface, Device Management
//! - swapchain: Swapchain, Render Pass, Framebuffers
//! - pipeline: Descriptor Layouts, Graphics Pipeline, Descriptor Sets
//! - resources: Command Buffers, Memory, Textures, Synchronization
//! - rendering: Frame Rendering and Texture Upload

const std = @import("std");
const log = std.log.scoped(.vulkan);

const VulkanState = @import("VulkanState.zig").VulkanState;
const WaylandState = @import("WaylandState.zig").WaylandState;

// Vulkan modules
const core = @import("vulkan/core.zig");
const swapchain = @import("vulkan/swapchain.zig");
const pipeline = @import("vulkan/pipeline.zig");
const resources = @import("vulkan/resources.zig");
const rendering = @import("vulkan/rendering.zig");

const c = @import("VulkanBindings.zig").c;
const ENABLE_VALIDATION = @import("builtin").mode == .Debug;

// ============================================================================
// Initialization
// ============================================================================

/// Initialize Vulkan renderer
pub fn init(
    allocator: std.mem.Allocator,
    wayland: *WaylandState,
) !VulkanState {
    var state = VulkanState{
        .allocator = allocator,
        .enable_validation = ENABLE_VALIDATION,
    };

    // Create Vulkan instance
    try core.createInstance(&state);
    errdefer core.destroyInstance(&state);

    // Create Wayland surface
    try core.createSurface(&state, wayland);
    errdefer core.destroySurface(&state);

    // Select physical device
    try core.pickPhysicalDevice(&state);

    // Create logical device
    try core.createLogicalDevice(&state);
    errdefer core.destroyLogicalDevice(&state);

    // Create swapchain
    try swapchain.createSwapchain(&state);
    errdefer swapchain.destroySwapchain(&state);

    // Create render pass
    try swapchain.createRenderPass(&state);
    errdefer swapchain.destroyRenderPass(&state);

    // Create framebuffers
    try swapchain.createFramebuffers(&state);
    errdefer swapchain.destroyFramebuffers(&state);

    // Create descriptor set layout
    try pipeline.createDescriptorSetLayout(&state);
    errdefer pipeline.destroyDescriptorSetLayout(&state);

    // Create graphics pipeline
    try pipeline.createGraphicsPipeline(&state);
    errdefer pipeline.destroyGraphicsPipeline(&state);

    // Create command pool
    try resources.createCommandPool(&state);
    errdefer resources.destroyCommandPool(&state);

    // Create staging buffer for texture uploads
    try resources.createStagingBuffer(&state);
    errdefer resources.destroyStagingBuffer(&state);

    // Create texture resources
    try resources.createTextureImage(&state);
    errdefer resources.destroyTextureImage(&state);

    try resources.createTextureSampler(&state); // Must be created before image view (descriptor update needs it)
    errdefer resources.destroyTextureSampler(&state);

    // Create descriptor pool and sets (before image view update)
    try pipeline.createDescriptorPool(&state);
    errdefer pipeline.destroyDescriptorPool(&state);

    try pipeline.createDescriptorSets(&state);

    try resources.createTextureImageView(&state); // Updates descriptors, needs sampler and sets to exist
    errdefer resources.destroyTextureImageView(&state);

    // Create command buffers
    try resources.createCommandBuffers(&state);

    // Create synchronization objects
    try resources.createSyncObjects(&state);
    errdefer resources.destroySyncObjects(&state);

    log.info("Vulkan renderer initialized successfully", .{});
    return state;
}

/// Cleanup Vulkan resources
pub fn deinit(state: *VulkanState) void {
    // Wait for device to finish
    if (state.device != null) {
        _ = c.vkDeviceWaitIdle(state.device);
    }

    resources.destroySyncObjects(state);
    resources.destroyCommandPool(state); // Also destroys command buffers
    pipeline.destroyDescriptorPool(state); // Also destroys descriptor sets
    resources.destroyTextureSampler(state);
    resources.destroyTextureImageView(state);
    resources.destroyTextureImage(state);
    resources.destroyStagingBuffer(state);
    pipeline.destroyGraphicsPipeline(state);
    pipeline.destroyDescriptorSetLayout(state);
    swapchain.destroyFramebuffers(state);
    swapchain.destroyRenderPass(state);
    swapchain.destroySwapchain(state);
    core.destroyLogicalDevice(state);
    core.destroySurface(state);
    core.destroyInstance(state);

    log.info("Vulkan renderer cleaned up", .{});
}

// ============================================================================
// Rendering
// ============================================================================

/// Render a frame from FrameMailbox data
pub fn renderFrame(state: *VulkanState, frame_data: []const u32) !void {
    return rendering.renderFrame(state, frame_data);
}
