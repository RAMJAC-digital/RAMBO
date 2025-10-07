//! Vulkan Rendering State
//! Pure data structure - no logic
//!
//! Pattern: State/Logic separation
//! Thread: Render thread only (owned exclusively)

const std = @import("std");
const build = @import("build_options");

// Shared Vulkan C API bindings
const c = @import("VulkanBindings.zig").c;

/// Vulkan rendering state
/// All fields are owned by the render thread
/// Thread safety: Not thread-safe - render thread exclusive access only
pub const VulkanState = struct {
    // Core Vulkan objects
    instance: c.VkInstance = null,
    physical_device: c.VkPhysicalDevice = null,
    device: c.VkDevice = null,

    // Queue handles
    graphics_queue: c.VkQueue = null,
    present_queue: c.VkQueue = null,
    graphics_queue_family: u32 = 0,
    present_queue_family: u32 = 0,

    // Surface and swapchain
    surface: c.VkSurfaceKHR = null,
    swapchain: c.VkSwapchainKHR = null,
    swapchain_images: []c.VkImage = &.{},
    swapchain_image_views: []c.VkImageView = &.{},
    swapchain_extent: c.VkExtent2D = .{ .width = 0, .height = 0 },
    swapchain_format: c.VkFormat = c.VK_FORMAT_UNDEFINED,

    // Render pass and framebuffers
    render_pass: c.VkRenderPass = null,
    framebuffers: []c.VkFramebuffer = &.{},

    // Pipeline
    pipeline_layout: c.VkPipelineLayout = null,
    graphics_pipeline: c.VkPipeline = null,

    // Descriptor sets for texture binding
    descriptor_set_layout: c.VkDescriptorSetLayout = null,
    descriptor_pool: c.VkDescriptorPool = null,
    descriptor_sets: []c.VkDescriptorSet = &.{},

    // NES frame texture (256×240 RGBA)
    texture_image: c.VkImage = null,
    texture_memory: c.VkDeviceMemory = null,
    texture_image_view: c.VkImageView = null,
    texture_sampler: c.VkSampler = null,

    // Staging buffer for texture uploads
    staging_buffer: c.VkBuffer = null,
    staging_buffer_memory: c.VkDeviceMemory = null,

    // Command pools and buffers
    command_pool: c.VkCommandPool = null,
    command_buffers: []c.VkCommandBuffer = &.{},

    // Synchronization primitives
    image_available_semaphores: []c.VkSemaphore = &.{},
    render_finished_semaphores: []c.VkSemaphore = &.{},
    in_flight_fences: []c.VkFence = &.{},
    current_frame: u32 = 0,

    // Validation layers (debug builds only)
    debug_messenger: c.VkDebugUtilsMessengerEXT = null,

    // Memory allocator
    allocator: std.mem.Allocator,

    // Configuration
    max_frames_in_flight: u32 = 2, // Double-buffering
    enable_validation: bool = false,
};
