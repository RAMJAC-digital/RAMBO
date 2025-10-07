//! Vulkan Renderer Logic - Phase 1 Implementation
//! Pure functions for Vulkan initialization and rendering
//!
//! This implementation focuses on minimal working renderer:
//! - Fullscreen quad rendering
//! - 256×240 texture upload from FrameMailbox
//! - Nearest-neighbor sampling for pixel-perfect scaling

const std = @import("std");
const log = std.log.scoped(.vulkan);
const build = @import("build_options");

const VulkanState = @import("VulkanState.zig").VulkanState;
const WaylandState = @import("WaylandState.zig").WaylandState;
const WaylandLogic = @import("WaylandLogic.zig");

// Shared Vulkan C API bindings
const c = @import("VulkanBindings.zig").c;

// ============================================================================
// Constants
// ============================================================================

const VALIDATION_LAYERS = [_][*:0]const u8{
    "VK_LAYER_KHRONOS_validation",
};

const DEVICE_EXTENSIONS = [_][*:0]const u8{
    c.VK_KHR_SWAPCHAIN_EXTENSION_NAME,
};

const ENABLE_VALIDATION = @import("builtin").mode == .Debug;

// NES framebuffer dimensions
const FRAME_WIDTH = 256;
const FRAME_HEIGHT = 240;

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
    try createInstance(&state);
    errdefer destroyInstance(&state);

    // Create Wayland surface
    try createSurface(&state, wayland);
    errdefer destroySurface(&state);

    // Select physical device
    try pickPhysicalDevice(&state);

    // Create logical device
    try createLogicalDevice(&state);
    errdefer destroyLogicalDevice(&state);

    // Create swapchain
    try createSwapchain(&state);
    errdefer destroySwapchain(&state);

    // Create render pass
    try createRenderPass(&state);
    errdefer destroyRenderPass(&state);

    // Create framebuffers
    try createFramebuffers(&state);
    errdefer destroyFramebuffers(&state);

    // Create descriptor set layout
    try createDescriptorSetLayout(&state);
    errdefer destroyDescriptorSetLayout(&state);

    // Create graphics pipeline
    try createGraphicsPipeline(&state);
    errdefer destroyGraphicsPipeline(&state);

    // Create command pool
    try createCommandPool(&state);
    errdefer destroyCommandPool(&state);

    // Create staging buffer for texture uploads
    try createStagingBuffer(&state);
    errdefer destroyStagingBuffer(&state);

    // Create texture resources
    try createTextureImage(&state);
    errdefer destroyTextureImage(&state);

    try createTextureSampler(&state); // Must be created before image view (descriptor update needs it)
    errdefer destroyTextureSampler(&state);

    // Create descriptor pool and sets (before image view update)
    try createDescriptorPool(&state);
    errdefer destroyDescriptorPool(&state);

    try createDescriptorSets(&state);

    try createTextureImageView(&state); // Updates descriptors, needs sampler and sets to exist
    errdefer destroyTextureImageView(&state);

    // Create command buffers
    try createCommandBuffers(&state);

    // Create synchronization objects
    try createSyncObjects(&state);
    errdefer destroySyncObjects(&state);

    log.info("Vulkan renderer initialized successfully", .{});
    return state;
}

/// Cleanup Vulkan resources
pub fn deinit(state: *VulkanState) void {
    // Wait for device to finish
    if (state.device != null) {
        _ = c.vkDeviceWaitIdle(state.device);
    }

    destroySyncObjects(state);
    destroyCommandPool(state); // Also destroys command buffers
    destroyDescriptorPool(state); // Also destroys descriptor sets
    destroyTextureSampler(state);
    destroyTextureImageView(state);
    destroyTextureImage(state);
    destroyStagingBuffer(state);
    destroyGraphicsPipeline(state);
    destroyDescriptorSetLayout(state);
    destroyFramebuffers(state);
    destroyRenderPass(state);
    destroySwapchain(state);
    destroyLogicalDevice(state);
    destroySurface(state);
    destroyInstance(state);

    log.info("Vulkan renderer cleaned up", .{});
}

// ============================================================================
// Instance Creation
// ============================================================================

fn createInstance(state: *VulkanState) !void {
    // Application info
    const app_info = c.VkApplicationInfo{
        .sType = c.VK_STRUCTURE_TYPE_APPLICATION_INFO,
        .pNext = null,
        .pApplicationName = "RAMBO NES Emulator",
        .applicationVersion = c.VK_MAKE_VERSION(0, 1, 0),
        .pEngineName = "RAMBO",
        .engineVersion = c.VK_MAKE_VERSION(0, 1, 0),
        .apiVersion = c.VK_API_VERSION_1_0,
    };

    // Required extensions
    const extensions = [_][*:0]const u8{
        c.VK_KHR_SURFACE_EXTENSION_NAME,
        c.VK_KHR_WAYLAND_SURFACE_EXTENSION_NAME,
        c.VK_EXT_DEBUG_UTILS_EXTENSION_NAME, // For validation layer messages
    };

    // Instance create info
    var create_info = c.VkInstanceCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .pApplicationInfo = &app_info,
        .enabledExtensionCount = extensions.len,
        .ppEnabledExtensionNames = &extensions,
        .enabledLayerCount = 0,
        .ppEnabledLayerNames = null,
    };

    // Enable validation layers in debug mode
    if (state.enable_validation) {
        if (!checkValidationLayerSupport()) {
            log.warn("Validation layers requested but not available", .{});
            state.enable_validation = false;
        } else {
            create_info.enabledLayerCount = VALIDATION_LAYERS.len;
            create_info.ppEnabledLayerNames = &VALIDATION_LAYERS;
            log.debug("Validation layers enabled", .{});
        }
    }

    // Create instance
    const result = c.vkCreateInstance(&create_info, null, &state.instance);
    if (result != c.VK_SUCCESS) {
        log.err("Failed to create Vulkan instance: {d}", .{result});
        return error.VulkanInstanceCreationFailed;
    }

    log.debug("Vulkan instance created", .{});
}

fn checkValidationLayerSupport() bool {
    var layer_count: u32 = 0;
    _ = c.vkEnumerateInstanceLayerProperties(&layer_count, null);

    const allocator = std.heap.c_allocator;
    const available_layers = allocator.alloc(c.VkLayerProperties, layer_count) catch return false;
    defer allocator.free(available_layers);

    _ = c.vkEnumerateInstanceLayerProperties(&layer_count, available_layers.ptr);

    // Check if all required layers are available
    for (VALIDATION_LAYERS) |required_layer| {
        var found = false;
        for (available_layers) |layer| {
            const layer_name = @as([*:0]const u8, @ptrCast(&layer.layerName));
            if (std.mem.orderZ(u8, required_layer, layer_name) == .eq) {
                found = true;
                break;
            }
        }
        if (!found) return false;
    }
    return true;
}

fn destroyInstance(state: *VulkanState) void {
    if (state.instance != null) {
        c.vkDestroyInstance(state.instance, null);
        state.instance = null;
    }
}

// ============================================================================
// Surface Creation
// ============================================================================

fn createSurface(state: *VulkanState, wayland: *WaylandState) !void {
    const handles = WaylandLogic.rawHandles(wayland);
    if (handles.display == null or handles.surface == null) {
        log.err("Wayland display or surface not available", .{});
        return error.WaylandSurfaceUnavailable;
    }

    const surface_create_info = c.VkWaylandSurfaceCreateInfoKHR{
        .sType = c.VK_STRUCTURE_TYPE_WAYLAND_SURFACE_CREATE_INFO_KHR,
        .pNext = null,
        .flags = 0,
        .display = @ptrCast(handles.display),
        .surface = @ptrCast(handles.surface),
    };

    const result = c.vkCreateWaylandSurfaceKHR(
        state.instance,
        &surface_create_info,
        null,
        &state.surface,
    );

    if (result != c.VK_SUCCESS) {
        log.err("Failed to create Wayland surface: {d}", .{result});
        return error.VulkanSurfaceCreationFailed;
    }

    log.debug("Vulkan Wayland surface created", .{});
}

fn destroySurface(state: *VulkanState) void {
    if (state.surface != null) {
        c.vkDestroySurfaceKHR(state.instance, state.surface, null);
        state.surface = null;
    }
}

// ============================================================================
// Physical Device Selection
// ============================================================================

const QueueFamilyIndices = struct {
    graphics_family: ?u32 = null,
    present_family: ?u32 = null,

    fn isComplete(self: @This()) bool {
        return self.graphics_family != null and self.present_family != null;
    }
};

fn pickPhysicalDevice(state: *VulkanState) !void {
    var device_count: u32 = 0;
    _ = c.vkEnumeratePhysicalDevices(state.instance, &device_count, null);

    if (device_count == 0) {
        log.err("No Vulkan-capable GPUs found", .{});
        return error.NoVulkanGPU;
    }

    const devices = try state.allocator.alloc(c.VkPhysicalDevice, device_count);
    defer state.allocator.free(devices);

    _ = c.vkEnumeratePhysicalDevices(state.instance, &device_count, devices.ptr);

    // Find first suitable device
    for (devices) |device| {
        if (isDeviceSuitable(state, device)) {
            state.physical_device = device;

            // Store queue family indices
            const indices = findQueueFamilies(state, device);
            state.graphics_queue_family = indices.graphics_family.?;
            state.present_queue_family = indices.present_family.?;

            var props: c.VkPhysicalDeviceProperties = undefined;
            c.vkGetPhysicalDeviceProperties(device, &props);
            log.info("Selected GPU: {s}", .{@as([*:0]const u8, @ptrCast(&props.deviceName))});
            return;
        }
    }

    log.err("No suitable GPU found", .{});
    return error.NoSuitableGPU;
}

fn isDeviceSuitable(state: *VulkanState, device: c.VkPhysicalDevice) bool {
    const indices = findQueueFamilies(state, device);
    if (!indices.isComplete()) return false;

    if (!checkDeviceExtensionSupport(state.allocator, device)) return false;

    // Check swapchain support
    const swapchain_support = querySwapchainSupport(state.allocator, device, state.surface) catch return false;
    defer swapchain_support.deinit(state.allocator);

    return swapchain_support.formats.len > 0 and swapchain_support.present_modes.len > 0;
}

fn findQueueFamilies(state: *VulkanState, device: c.VkPhysicalDevice) QueueFamilyIndices {
    var indices = QueueFamilyIndices{};

    var queue_family_count: u32 = 0;
    c.vkGetPhysicalDeviceQueueFamilyProperties(device, &queue_family_count, null);

    const queue_families = state.allocator.alloc(c.VkQueueFamilyProperties, queue_family_count) catch return indices;
    defer state.allocator.free(queue_families);

    c.vkGetPhysicalDeviceQueueFamilyProperties(device, &queue_family_count, queue_families.ptr);

    for (queue_families, 0..) |family, i| {
        const index = @as(u32, @intCast(i));

        // Check for graphics support
        if (family.queueFlags & c.VK_QUEUE_GRAPHICS_BIT != 0) {
            indices.graphics_family = index;
        }

        // Check for present support
        var present_support: c.VkBool32 = c.VK_FALSE;
        _ = c.vkGetPhysicalDeviceSurfaceSupportKHR(device, index, state.surface, &present_support);
        if (present_support == c.VK_TRUE) {
            indices.present_family = index;
        }

        if (indices.isComplete()) break;
    }

    return indices;
}

fn checkDeviceExtensionSupport(allocator: std.mem.Allocator, device: c.VkPhysicalDevice) bool {
    var extension_count: u32 = 0;
    _ = c.vkEnumerateDeviceExtensionProperties(device, null, &extension_count, null);

    const available_extensions = allocator.alloc(c.VkExtensionProperties, extension_count) catch return false;
    defer allocator.free(available_extensions);

    _ = c.vkEnumerateDeviceExtensionProperties(device, null, &extension_count, available_extensions.ptr);

    // Check if all required extensions are available
    for (DEVICE_EXTENSIONS) |required_ext| {
        var found = false;
        for (available_extensions) |ext| {
            const ext_name = @as([*:0]const u8, @ptrCast(&ext.extensionName));
            if (std.mem.orderZ(u8, required_ext, ext_name) == .eq) {
                found = true;
                break;
            }
        }
        if (!found) return false;
    }
    return true;
}

const SwapchainSupportDetails = struct {
    capabilities: c.VkSurfaceCapabilitiesKHR,
    formats: []c.VkSurfaceFormatKHR,
    present_modes: []c.VkPresentModeKHR,

    fn deinit(self: @This(), allocator: std.mem.Allocator) void {
        allocator.free(self.formats);
        allocator.free(self.present_modes);
    }
};

fn querySwapchainSupport(
    allocator: std.mem.Allocator,
    device: c.VkPhysicalDevice,
    surface: c.VkSurfaceKHR,
) !SwapchainSupportDetails {
    var details: SwapchainSupportDetails = undefined;

    _ = c.vkGetPhysicalDeviceSurfaceCapabilitiesKHR(device, surface, &details.capabilities);

    var format_count: u32 = 0;
    _ = c.vkGetPhysicalDeviceSurfaceFormatsKHR(device, surface, &format_count, null);
    if (format_count != 0) {
        details.formats = try allocator.alloc(c.VkSurfaceFormatKHR, format_count);
        _ = c.vkGetPhysicalDeviceSurfaceFormatsKHR(device, surface, &format_count, details.formats.ptr);
    } else {
        details.formats = &.{};
    }

    var present_mode_count: u32 = 0;
    _ = c.vkGetPhysicalDeviceSurfacePresentModesKHR(device, surface, &present_mode_count, null);
    if (present_mode_count != 0) {
        details.present_modes = try allocator.alloc(c.VkPresentModeKHR, present_mode_count);
        _ = c.vkGetPhysicalDeviceSurfacePresentModesKHR(device, surface, &present_mode_count, details.present_modes.ptr);
    } else {
        details.present_modes = &.{};
    }

    return details;
}

fn createLogicalDevice(state: *VulkanState) !void {
    const indices = findQueueFamilies(state, state.physical_device);

    // Create queue create infos (handle case where graphics and present are same queue)
    const same_queue = indices.present_family.? == indices.graphics_family.?;
    const queue_family_count: usize = if (same_queue) 1 else 2;

    var queue_families_buf: [2]u32 = undefined;
    queue_families_buf[0] = indices.graphics_family.?;
    if (!same_queue) {
        queue_families_buf[1] = indices.present_family.?;
    }
    const queue_families = queue_families_buf[0..queue_family_count];

    var queue_create_infos = try state.allocator.alloc(c.VkDeviceQueueCreateInfo, queue_family_count);
    defer state.allocator.free(queue_create_infos);

    const queue_priority: f32 = 1.0;
    for (queue_families, 0..) |queue_family, i| {
        queue_create_infos[i] = c.VkDeviceQueueCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .queueFamilyIndex = queue_family,
            .queueCount = 1,
            .pQueuePriorities = &queue_priority,
        };
    }

    // Device features (none required for simple 2D rendering)
    const device_features = std.mem.zeroes(c.VkPhysicalDeviceFeatures);

    // Create logical device
    const create_info = c.VkDeviceCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .queueCreateInfoCount = @intCast(queue_create_infos.len),
        .pQueueCreateInfos = queue_create_infos.ptr,
        .pEnabledFeatures = &device_features,
        .enabledExtensionCount = DEVICE_EXTENSIONS.len,
        .ppEnabledExtensionNames = &DEVICE_EXTENSIONS,
        .enabledLayerCount = if (state.enable_validation) VALIDATION_LAYERS.len else 0,
        .ppEnabledLayerNames = if (state.enable_validation) &VALIDATION_LAYERS else null,
    };

    const result = c.vkCreateDevice(state.physical_device, &create_info, null, &state.device);
    if (result != c.VK_SUCCESS) {
        log.err("Failed to create logical device: {d}", .{result});
        return error.VulkanDeviceCreationFailed;
    }

    // Get queue handles
    c.vkGetDeviceQueue(state.device, indices.graphics_family.?, 0, &state.graphics_queue);
    c.vkGetDeviceQueue(state.device, indices.present_family.?, 0, &state.present_queue);

    log.debug("Logical device created", .{});
}

fn destroyLogicalDevice(state: *VulkanState) void {
    if (state.device != null) {
        c.vkDestroyDevice(state.device, null);
        state.device = null;
    }
}

// ============================================================================
// Swapchain
// ============================================================================

fn chooseSwapSurfaceFormat(available_formats: []const c.VkSurfaceFormatKHR) c.VkSurfaceFormatKHR {
    // Prefer BGRA8 SRGB
    for (available_formats) |format| {
        if (format.format == c.VK_FORMAT_B8G8R8A8_SRGB and
            format.colorSpace == c.VK_COLOR_SPACE_SRGB_NONLINEAR_KHR)
        {
            return format;
        }
    }
    // Fallback to first format
    return available_formats[0];
}

fn chooseSwapPresentMode(available_modes: []const c.VkPresentModeKHR) c.VkPresentModeKHR {
    // Prefer mailbox (triple buffering) if available
    for (available_modes) |mode| {
        if (mode == c.VK_PRESENT_MODE_MAILBOX_KHR) {
            return mode;
        }
    }
    // FIFO is guaranteed to be available
    return c.VK_PRESENT_MODE_FIFO_KHR;
}

fn chooseSwapExtent(capabilities: c.VkSurfaceCapabilitiesKHR) c.VkExtent2D {
    // If current extent is defined, use it
    if (capabilities.currentExtent.width != std.math.maxInt(u32)) {
        return capabilities.currentExtent;
    }

    // Otherwise clamp to supported range
    var extent = c.VkExtent2D{
        .width = 512, // Default window width
        .height = 480, // Default window height
    };

    extent.width = @max(capabilities.minImageExtent.width, @min(capabilities.maxImageExtent.width, extent.width));
    extent.height = @max(capabilities.minImageExtent.height, @min(capabilities.maxImageExtent.height, extent.height));

    return extent;
}

fn createSwapchain(state: *VulkanState) !void {
    const swapchain_support = try querySwapchainSupport(state.allocator, state.physical_device, state.surface);
    defer swapchain_support.deinit(state.allocator);

    const surface_format = chooseSwapSurfaceFormat(swapchain_support.formats);
    const present_mode = chooseSwapPresentMode(swapchain_support.present_modes);
    const extent = chooseSwapExtent(swapchain_support.capabilities);

    // Request one more than minimum for triple buffering
    var image_count = swapchain_support.capabilities.minImageCount + 1;
    if (swapchain_support.capabilities.maxImageCount > 0 and image_count > swapchain_support.capabilities.maxImageCount) {
        image_count = swapchain_support.capabilities.maxImageCount;
    }

    // Determine sharing mode based on queue families
    const indices = findQueueFamilies(state, state.physical_device);
    const queue_family_indices = [_]u32{ indices.graphics_family.?, indices.present_family.? };
    const sharing_mode: c.VkSharingMode = if (indices.graphics_family.? != indices.present_family.?)
        c.VK_SHARING_MODE_CONCURRENT
    else
        c.VK_SHARING_MODE_EXCLUSIVE;

    const create_info = c.VkSwapchainCreateInfoKHR{
        .sType = c.VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR,
        .pNext = null,
        .flags = 0,
        .surface = state.surface,
        .minImageCount = image_count,
        .imageFormat = surface_format.format,
        .imageColorSpace = surface_format.colorSpace,
        .imageExtent = extent,
        .imageArrayLayers = 1,
        .imageUsage = c.VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT,
        .imageSharingMode = sharing_mode,
        .queueFamilyIndexCount = if (sharing_mode == c.VK_SHARING_MODE_CONCURRENT) 2 else 0,
        .pQueueFamilyIndices = if (sharing_mode == c.VK_SHARING_MODE_CONCURRENT) &queue_family_indices else null,
        .preTransform = swapchain_support.capabilities.currentTransform,
        .compositeAlpha = c.VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR,
        .presentMode = present_mode,
        .clipped = c.VK_TRUE,
        .oldSwapchain = null,
    };

    const result = c.vkCreateSwapchainKHR(state.device, &create_info, null, &state.swapchain);
    if (result != c.VK_SUCCESS) {
        log.err("Failed to create swapchain: {d}", .{result});
        return error.VulkanSwapchainCreationFailed;
    }

    // Store swapchain properties
    state.swapchain_format = surface_format.format;
    state.swapchain_extent = extent;

    // Get swapchain images
    var swapchain_image_count: u32 = 0;
    _ = c.vkGetSwapchainImagesKHR(state.device, state.swapchain, &swapchain_image_count, null);
    state.swapchain_images = try state.allocator.alloc(c.VkImage, swapchain_image_count);
    _ = c.vkGetSwapchainImagesKHR(state.device, state.swapchain, &swapchain_image_count, state.swapchain_images.ptr);

    // Create image views
    state.swapchain_image_views = try state.allocator.alloc(c.VkImageView, swapchain_image_count);
    for (state.swapchain_images, 0..) |image, i| {
        const view_create_info = c.VkImageViewCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .image = image,
            .viewType = c.VK_IMAGE_VIEW_TYPE_2D,
            .format = state.swapchain_format,
            .components = .{
                .r = c.VK_COMPONENT_SWIZZLE_IDENTITY,
                .g = c.VK_COMPONENT_SWIZZLE_IDENTITY,
                .b = c.VK_COMPONENT_SWIZZLE_IDENTITY,
                .a = c.VK_COMPONENT_SWIZZLE_IDENTITY,
            },
            .subresourceRange = .{
                .aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT,
                .baseMipLevel = 0,
                .levelCount = 1,
                .baseArrayLayer = 0,
                .layerCount = 1,
            },
        };

        const view_result = c.vkCreateImageView(state.device, &view_create_info, null, &state.swapchain_image_views[i]);
        if (view_result != c.VK_SUCCESS) {
            log.err("Failed to create image view {d}: {d}", .{ i, view_result });
            return error.VulkanImageViewCreationFailed;
        }
    }

    log.debug("Swapchain created ({d}x{d}, {d} images)", .{ extent.width, extent.height, swapchain_image_count });
}

fn destroySwapchain(state: *VulkanState) void {
    // Destroy image views
    for (state.swapchain_image_views) |view| {
        c.vkDestroyImageView(state.device, view, null);
    }
    state.allocator.free(state.swapchain_image_views);
    state.swapchain_image_views = &.{};

    // Destroy swapchain
    if (state.swapchain != null) {
        c.vkDestroySwapchainKHR(state.device, state.swapchain, null);
        state.swapchain = null;
    }

    // Free images array (we don't destroy images, they're owned by swapchain)
    state.allocator.free(state.swapchain_images);
    state.swapchain_images = &.{};
}

// ============================================================================
// Render Pass
// ============================================================================

fn createRenderPass(state: *VulkanState) !void {
    // Color attachment (swapchain image)
    const color_attachment = c.VkAttachmentDescription{
        .flags = 0,
        .format = state.swapchain_format,
        .samples = c.VK_SAMPLE_COUNT_1_BIT,
        .loadOp = c.VK_ATTACHMENT_LOAD_OP_CLEAR,
        .storeOp = c.VK_ATTACHMENT_STORE_OP_STORE,
        .stencilLoadOp = c.VK_ATTACHMENT_LOAD_OP_DONT_CARE,
        .stencilStoreOp = c.VK_ATTACHMENT_STORE_OP_DONT_CARE,
        .initialLayout = c.VK_IMAGE_LAYOUT_UNDEFINED,
        .finalLayout = c.VK_IMAGE_LAYOUT_PRESENT_SRC_KHR,
    };

    const color_attachment_ref = c.VkAttachmentReference{
        .attachment = 0,
        .layout = c.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
    };

    const subpass = c.VkSubpassDescription{
        .flags = 0,
        .pipelineBindPoint = c.VK_PIPELINE_BIND_POINT_GRAPHICS,
        .inputAttachmentCount = 0,
        .pInputAttachments = null,
        .colorAttachmentCount = 1,
        .pColorAttachments = &color_attachment_ref,
        .pResolveAttachments = null,
        .pDepthStencilAttachment = null,
        .preserveAttachmentCount = 0,
        .pPreserveAttachments = null,
    };

    // Subpass dependency for layout transitions
    const dependency = c.VkSubpassDependency{
        .srcSubpass = c.VK_SUBPASS_EXTERNAL,
        .dstSubpass = 0,
        .srcStageMask = c.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
        .dstStageMask = c.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
        .srcAccessMask = 0,
        .dstAccessMask = c.VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT,
        .dependencyFlags = 0,
    };

    const render_pass_info = c.VkRenderPassCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .attachmentCount = 1,
        .pAttachments = &color_attachment,
        .subpassCount = 1,
        .pSubpasses = &subpass,
        .dependencyCount = 1,
        .pDependencies = &dependency,
    };

    const result = c.vkCreateRenderPass(state.device, &render_pass_info, null, &state.render_pass);
    if (result != c.VK_SUCCESS) {
        log.err("Failed to create render pass: {d}", .{result});
        return error.VulkanRenderPassCreationFailed;
    }

    log.debug("Render pass created", .{});
}

fn destroyRenderPass(state: *VulkanState) void {
    if (state.render_pass != null) {
        c.vkDestroyRenderPass(state.device, state.render_pass, null);
        state.render_pass = null;
    }
}

// ============================================================================
// Framebuffers
// ============================================================================

fn createFramebuffers(state: *VulkanState) !void {
    state.framebuffers = try state.allocator.alloc(c.VkFramebuffer, state.swapchain_image_views.len);

    for (state.swapchain_image_views, 0..) |view, i| {
        const attachments = [_]c.VkImageView{view};

        const framebuffer_info = c.VkFramebufferCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .renderPass = state.render_pass,
            .attachmentCount = 1,
            .pAttachments = &attachments,
            .width = state.swapchain_extent.width,
            .height = state.swapchain_extent.height,
            .layers = 1,
        };

        const result = c.vkCreateFramebuffer(state.device, &framebuffer_info, null, &state.framebuffers[i]);
        if (result != c.VK_SUCCESS) {
            log.err("Failed to create framebuffer {d}: {d}", .{ i, result});
            return error.VulkanFramebufferCreationFailed;
        }
    }

    log.debug("Created {d} framebuffers", .{state.framebuffers.len});
}

fn destroyFramebuffers(state: *VulkanState) void {
    for (state.framebuffers) |fb| {
        c.vkDestroyFramebuffer(state.device, fb, null);
    }
    state.allocator.free(state.framebuffers);
    state.framebuffers = &.{};
}

// ============================================================================
// Descriptor Set Layout
// ============================================================================

fn createDescriptorSetLayout(state: *VulkanState) !void {
    // Texture sampler binding
    const sampler_layout_binding = c.VkDescriptorSetLayoutBinding{
        .binding = 0,
        .descriptorType = c.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
        .descriptorCount = 1,
        .stageFlags = c.VK_SHADER_STAGE_FRAGMENT_BIT,
        .pImmutableSamplers = null,
    };

    const layout_info = c.VkDescriptorSetLayoutCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .bindingCount = 1,
        .pBindings = &sampler_layout_binding,
    };

    const result = c.vkCreateDescriptorSetLayout(state.device, &layout_info, null, &state.descriptor_set_layout);
    if (result != c.VK_SUCCESS) {
        log.err("Failed to create descriptor set layout: {d}", .{result});
        return error.VulkanDescriptorSetLayoutCreationFailed;
    }

    log.debug("Descriptor set layout created", .{});
}

fn destroyDescriptorSetLayout(state: *VulkanState) void {
    if (state.descriptor_set_layout != null) {
        c.vkDestroyDescriptorSetLayout(state.device, state.descriptor_set_layout, null);
        state.descriptor_set_layout = null;
    }
}

fn readShaderFile(allocator: std.mem.Allocator, path: []const u8) ![]const u8 {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    const file_size = try file.getEndPos();
    const buffer = try allocator.alloc(u8, file_size);
    _ = try file.readAll(buffer);

    return buffer;
}

fn createShaderModule(device: c.VkDevice, code: []const u8) !c.VkShaderModule {
    const create_info = c.VkShaderModuleCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .codeSize = code.len,
        .pCode = @ptrCast(@alignCast(code.ptr)),
    };

    var shader_module: c.VkShaderModule = null;
    const result = c.vkCreateShaderModule(device, &create_info, null, &shader_module);
    if (result != c.VK_SUCCESS) {
        log.err("Failed to create shader module: {d}", .{result});
        return error.VulkanShaderModuleCreationFailed;
    }

    return shader_module;
}

fn createGraphicsPipeline(state: *VulkanState) !void {
    // Load shader bytecode
    const vert_code = try readShaderFile(state.allocator, "zig-out/shaders/texture.vert.spv");
    defer state.allocator.free(vert_code);

    const frag_code = try readShaderFile(state.allocator, "zig-out/shaders/texture.frag.spv");
    defer state.allocator.free(frag_code);

    const vert_shader_module = try createShaderModule(state.device, vert_code);
    defer c.vkDestroyShaderModule(state.device, vert_shader_module, null);

    const frag_shader_module = try createShaderModule(state.device, frag_code);
    defer c.vkDestroyShaderModule(state.device, frag_shader_module, null);

    // Shader stage info
    const vert_stage_info = c.VkPipelineShaderStageCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .stage = c.VK_SHADER_STAGE_VERTEX_BIT,
        .module = vert_shader_module,
        .pName = "main",
        .pSpecializationInfo = null,
    };

    const frag_stage_info = c.VkPipelineShaderStageCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .stage = c.VK_SHADER_STAGE_FRAGMENT_BIT,
        .module = frag_shader_module,
        .pName = "main",
        .pSpecializationInfo = null,
    };

    const shader_stages = [_]c.VkPipelineShaderStageCreateInfo{ vert_stage_info, frag_stage_info };

    // Vertex input (none - fullscreen triangle in shader)
    const vertex_input_info = c.VkPipelineVertexInputStateCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .vertexBindingDescriptionCount = 0,
        .pVertexBindingDescriptions = null,
        .vertexAttributeDescriptionCount = 0,
        .pVertexAttributeDescriptions = null,
    };

    // Input assembly
    const input_assembly = c.VkPipelineInputAssemblyStateCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .topology = c.VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST,
        .primitiveRestartEnable = c.VK_FALSE,
    };

    // Viewport and scissor (dynamic)
    const viewport = c.VkViewport{
        .x = 0.0,
        .y = 0.0,
        .width = @floatFromInt(state.swapchain_extent.width),
        .height = @floatFromInt(state.swapchain_extent.height),
        .minDepth = 0.0,
        .maxDepth = 1.0,
    };

    const scissor = c.VkRect2D{
        .offset = .{ .x = 0, .y = 0 },
        .extent = state.swapchain_extent,
    };

    const viewport_state = c.VkPipelineViewportStateCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .viewportCount = 1,
        .pViewports = &viewport,
        .scissorCount = 1,
        .pScissors = &scissor,
    };

    // Rasterization
    const rasterizer = c.VkPipelineRasterizationStateCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .depthClampEnable = c.VK_FALSE,
        .rasterizerDiscardEnable = c.VK_FALSE,
        .polygonMode = c.VK_POLYGON_MODE_FILL,
        .cullMode = c.VK_CULL_MODE_BACK_BIT,
        .frontFace = c.VK_FRONT_FACE_CLOCKWISE,
        .depthBiasEnable = c.VK_FALSE,
        .depthBiasConstantFactor = 0.0,
        .depthBiasClamp = 0.0,
        .depthBiasSlopeFactor = 0.0,
        .lineWidth = 1.0,
    };

    // Multisampling (disabled)
    const multisampling = c.VkPipelineMultisampleStateCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .rasterizationSamples = c.VK_SAMPLE_COUNT_1_BIT,
        .sampleShadingEnable = c.VK_FALSE,
        .minSampleShading = 1.0,
        .pSampleMask = null,
        .alphaToCoverageEnable = c.VK_FALSE,
        .alphaToOneEnable = c.VK_FALSE,
    };

    // Color blending
    const color_blend_attachment = c.VkPipelineColorBlendAttachmentState{
        .blendEnable = c.VK_FALSE,
        .srcColorBlendFactor = c.VK_BLEND_FACTOR_ONE,
        .dstColorBlendFactor = c.VK_BLEND_FACTOR_ZERO,
        .colorBlendOp = c.VK_BLEND_OP_ADD,
        .srcAlphaBlendFactor = c.VK_BLEND_FACTOR_ONE,
        .dstAlphaBlendFactor = c.VK_BLEND_FACTOR_ZERO,
        .alphaBlendOp = c.VK_BLEND_OP_ADD,
        .colorWriteMask = c.VK_COLOR_COMPONENT_R_BIT | c.VK_COLOR_COMPONENT_G_BIT | c.VK_COLOR_COMPONENT_B_BIT | c.VK_COLOR_COMPONENT_A_BIT,
    };

    const color_blending = c.VkPipelineColorBlendStateCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .logicOpEnable = c.VK_FALSE,
        .logicOp = c.VK_LOGIC_OP_COPY,
        .attachmentCount = 1,
        .pAttachments = &color_blend_attachment,
        .blendConstants = [_]f32{ 0.0, 0.0, 0.0, 0.0 },
    };

    // Pipeline layout
    const pipeline_layout_info = c.VkPipelineLayoutCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .setLayoutCount = 1,
        .pSetLayouts = &state.descriptor_set_layout,
        .pushConstantRangeCount = 0,
        .pPushConstantRanges = null,
    };

    const layout_result = c.vkCreatePipelineLayout(state.device, &pipeline_layout_info, null, &state.pipeline_layout);
    if (layout_result != c.VK_SUCCESS) {
        log.err("Failed to create pipeline layout: {d}", .{layout_result});
        return error.VulkanPipelineLayoutCreationFailed;
    }

    // Graphics pipeline
    const pipeline_info = c.VkGraphicsPipelineCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .stageCount = 2,
        .pStages = &shader_stages,
        .pVertexInputState = &vertex_input_info,
        .pInputAssemblyState = &input_assembly,
        .pTessellationState = null,
        .pViewportState = &viewport_state,
        .pRasterizationState = &rasterizer,
        .pMultisampleState = &multisampling,
        .pDepthStencilState = null,
        .pColorBlendState = &color_blending,
        .pDynamicState = null,
        .layout = state.pipeline_layout,
        .renderPass = state.render_pass,
        .subpass = 0,
        .basePipelineHandle = null,
        .basePipelineIndex = -1,
    };

    const pipeline_result = c.vkCreateGraphicsPipelines(
        state.device,
        null,
        1,
        &pipeline_info,
        null,
        &state.graphics_pipeline,
    );
    if (pipeline_result != c.VK_SUCCESS) {
        log.err("Failed to create graphics pipeline: {d}", .{pipeline_result});
        return error.VulkanGraphicsPipelineCreationFailed;
    }

    log.debug("Graphics pipeline created", .{});
}

fn destroyGraphicsPipeline(state: *VulkanState) void {
    if (state.graphics_pipeline != null) {
        c.vkDestroyPipeline(state.device, state.graphics_pipeline, null);
        state.graphics_pipeline = null;
    }
    if (state.pipeline_layout != null) {
        c.vkDestroyPipelineLayout(state.device, state.pipeline_layout, null);
        state.pipeline_layout = null;
    }
}

// ============================================================================
// Command Pool and Buffers
// ============================================================================

fn createCommandPool(state: *VulkanState) !void {
    const pool_info = c.VkCommandPoolCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
        .pNext = null,
        .flags = c.VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT,
        .queueFamilyIndex = state.graphics_queue_family,
    };

    const result = c.vkCreateCommandPool(state.device, &pool_info, null, &state.command_pool);
    if (result != c.VK_SUCCESS) {
        log.err("Failed to create command pool: {d}", .{result});
        return error.VulkanCommandPoolCreationFailed;
    }

    log.debug("Command pool created", .{});
}

fn destroyCommandPool(state: *VulkanState) void {
    if (state.command_pool != null) {
        c.vkDestroyCommandPool(state.device, state.command_pool, null);
        state.command_pool = null;
    }
}

fn createCommandBuffers(state: *VulkanState) !void {
    state.command_buffers = try state.allocator.alloc(c.VkCommandBuffer, state.max_frames_in_flight);

    const alloc_info = c.VkCommandBufferAllocateInfo{
        .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
        .pNext = null,
        .commandPool = state.command_pool,
        .level = c.VK_COMMAND_BUFFER_LEVEL_PRIMARY,
        .commandBufferCount = @intCast(state.command_buffers.len),
    };

    const result = c.vkAllocateCommandBuffers(state.device, &alloc_info, state.command_buffers.ptr);
    if (result != c.VK_SUCCESS) {
        log.err("Failed to allocate command buffers: {d}", .{result});
        return error.VulkanCommandBufferAllocationFailed;
    }

    log.debug("Allocated {d} command buffers", .{state.command_buffers.len});
}

// ============================================================================
// Memory Helpers
// ============================================================================

fn findMemoryType(state: *VulkanState, type_filter: u32, properties: c.VkMemoryPropertyFlags) !u32 {
    var mem_properties: c.VkPhysicalDeviceMemoryProperties = undefined;
    c.vkGetPhysicalDeviceMemoryProperties(state.physical_device, &mem_properties);

    var i: u32 = 0;
    while (i < mem_properties.memoryTypeCount) : (i += 1) {
        if ((type_filter & (@as(u32, 1) << @intCast(i))) != 0 and
            (mem_properties.memoryTypes[i].propertyFlags & properties) == properties)
        {
            return i;
        }
    }

    return error.NoSuitableMemoryType;
}

fn createBuffer(
    state: *VulkanState,
    size: c.VkDeviceSize,
    usage: c.VkBufferUsageFlags,
    properties: c.VkMemoryPropertyFlags,
    buffer: *c.VkBuffer,
    buffer_memory: *c.VkDeviceMemory,
) !void {
    const buffer_info = c.VkBufferCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .size = size,
        .usage = usage,
        .sharingMode = c.VK_SHARING_MODE_EXCLUSIVE,
        .queueFamilyIndexCount = 0,
        .pQueueFamilyIndices = null,
    };

    var result = c.vkCreateBuffer(state.device, &buffer_info, null, buffer);
    if (result != c.VK_SUCCESS) {
        log.err("Failed to create buffer: {d}", .{result});
        return error.VulkanBufferCreationFailed;
    }

    var mem_requirements: c.VkMemoryRequirements = undefined;
    c.vkGetBufferMemoryRequirements(state.device, buffer.*, &mem_requirements);

    const alloc_info = c.VkMemoryAllocateInfo{
        .sType = c.VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
        .pNext = null,
        .allocationSize = mem_requirements.size,
        .memoryTypeIndex = try findMemoryType(state, mem_requirements.memoryTypeBits, properties),
    };

    result = c.vkAllocateMemory(state.device, &alloc_info, null, buffer_memory);
    if (result != c.VK_SUCCESS) {
        log.err("Failed to allocate buffer memory: {d}", .{result});
        return error.VulkanBufferMemoryAllocationFailed;
    }

    result = c.vkBindBufferMemory(state.device, buffer.*, buffer_memory.*, 0);
    if (result != c.VK_SUCCESS) {
        log.err("Failed to bind buffer memory: {d}", .{result});
        return error.VulkanBufferMemoryBindFailed;
    }
}

fn beginSingleTimeCommands(state: *VulkanState) !c.VkCommandBuffer {
    const alloc_info = c.VkCommandBufferAllocateInfo{
        .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
        .pNext = null,
        .commandPool = state.command_pool,
        .level = c.VK_COMMAND_BUFFER_LEVEL_PRIMARY,
        .commandBufferCount = 1,
    };

    var command_buffer: c.VkCommandBuffer = undefined;
    var result = c.vkAllocateCommandBuffers(state.device, &alloc_info, &command_buffer);
    if (result != c.VK_SUCCESS) {
        return error.VulkanCommandBufferAllocationFailed;
    }

    const begin_info = c.VkCommandBufferBeginInfo{
        .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
        .pNext = null,
        .flags = c.VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT,
        .pInheritanceInfo = null,
    };

    result = c.vkBeginCommandBuffer(command_buffer, &begin_info);
    if (result != c.VK_SUCCESS) {
        return error.VulkanCommandBufferBeginFailed;
    }

    return command_buffer;
}

fn endSingleTimeCommands(state: *VulkanState, command_buffer: c.VkCommandBuffer) !void {
    _ = c.vkEndCommandBuffer(command_buffer);

    const submit_info = c.VkSubmitInfo{
        .sType = c.VK_STRUCTURE_TYPE_SUBMIT_INFO,
        .pNext = null,
        .waitSemaphoreCount = 0,
        .pWaitSemaphores = null,
        .pWaitDstStageMask = null,
        .commandBufferCount = 1,
        .pCommandBuffers = &command_buffer,
        .signalSemaphoreCount = 0,
        .pSignalSemaphores = null,
    };

    const result = c.vkQueueSubmit(state.graphics_queue, 1, &submit_info, null);
    if (result != c.VK_SUCCESS) {
        return error.VulkanQueueSubmitFailed;
    }

    _ = c.vkQueueWaitIdle(state.graphics_queue);
    c.vkFreeCommandBuffers(state.device, state.command_pool, 1, &command_buffer);
}

fn transitionImageLayout(
    state: *VulkanState,
    image: c.VkImage,
    format: c.VkFormat,
    old_layout: c.VkImageLayout,
    new_layout: c.VkImageLayout,
) !void {
    _ = format; // Reserved for depth images

    const command_buffer = try beginSingleTimeCommands(state);

    var barrier = c.VkImageMemoryBarrier{
        .sType = c.VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER,
        .pNext = null,
        .srcAccessMask = 0,
        .dstAccessMask = 0,
        .oldLayout = old_layout,
        .newLayout = new_layout,
        .srcQueueFamilyIndex = c.VK_QUEUE_FAMILY_IGNORED,
        .dstQueueFamilyIndex = c.VK_QUEUE_FAMILY_IGNORED,
        .image = image,
        .subresourceRange = .{
            .aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT,
            .baseMipLevel = 0,
            .levelCount = 1,
            .baseArrayLayer = 0,
            .layerCount = 1,
        },
    };

    var source_stage: c.VkPipelineStageFlags = undefined;
    var destination_stage: c.VkPipelineStageFlags = undefined;

    if (old_layout == c.VK_IMAGE_LAYOUT_UNDEFINED and new_layout == c.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL) {
        barrier.srcAccessMask = 0;
        barrier.dstAccessMask = c.VK_ACCESS_TRANSFER_WRITE_BIT;
        source_stage = c.VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT;
        destination_stage = c.VK_PIPELINE_STAGE_TRANSFER_BIT;
    } else if (old_layout == c.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL and new_layout == c.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL) {
        barrier.srcAccessMask = c.VK_ACCESS_TRANSFER_WRITE_BIT;
        barrier.dstAccessMask = c.VK_ACCESS_SHADER_READ_BIT;
        source_stage = c.VK_PIPELINE_STAGE_TRANSFER_BIT;
        destination_stage = c.VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT;
    } else if (old_layout == c.VK_IMAGE_LAYOUT_UNDEFINED and new_layout == c.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL) {
        // Direct transition from undefined to shader read (for initial texture creation)
        barrier.srcAccessMask = 0;
        barrier.dstAccessMask = c.VK_ACCESS_SHADER_READ_BIT;
        source_stage = c.VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT;
        destination_stage = c.VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT;
    } else if (old_layout == c.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL and new_layout == c.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL) {
        // Reverse transition (for texture updates)
        barrier.srcAccessMask = c.VK_ACCESS_SHADER_READ_BIT;
        barrier.dstAccessMask = c.VK_ACCESS_TRANSFER_WRITE_BIT;
        source_stage = c.VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT;
        destination_stage = c.VK_PIPELINE_STAGE_TRANSFER_BIT;
    } else {
        return error.UnsupportedLayoutTransition;
    }

    c.vkCmdPipelineBarrier(
        command_buffer,
        source_stage,
        destination_stage,
        0,
        0,
        null,
        0,
        null,
        1,
        &barrier,
    );

    try endSingleTimeCommands(state, command_buffer);
}

fn copyBufferToImage(
    state: *VulkanState,
    buffer: c.VkBuffer,
    image: c.VkImage,
    width: u32,
    height: u32,
) !void {
    const command_buffer = try beginSingleTimeCommands(state);

    const region = c.VkBufferImageCopy{
        .bufferOffset = 0,
        .bufferRowLength = 0,
        .bufferImageHeight = 0,
        .imageSubresource = .{
            .aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT,
            .mipLevel = 0,
            .baseArrayLayer = 0,
            .layerCount = 1,
        },
        .imageOffset = .{ .x = 0, .y = 0, .z = 0 },
        .imageExtent = .{ .width = width, .height = height, .depth = 1 },
    };

    c.vkCmdCopyBufferToImage(
        command_buffer,
        buffer,
        image,
        c.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
        1,
        &region,
    );

    try endSingleTimeCommands(state, command_buffer);
}

// ============================================================================
// Staging Buffer
// ============================================================================

fn createStagingBuffer(state: *VulkanState) !void {
    const buffer_size = FRAME_WIDTH * FRAME_HEIGHT * @sizeOf(u32);

    try createBuffer(
        state,
        buffer_size,
        c.VK_BUFFER_USAGE_TRANSFER_SRC_BIT,
        c.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | c.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
        &state.staging_buffer,
        &state.staging_buffer_memory,
    );

    log.debug("Staging buffer created ({d} bytes)", .{buffer_size});
}

fn destroyStagingBuffer(state: *VulkanState) void {
    if (state.staging_buffer != null) {
        c.vkDestroyBuffer(state.device, state.staging_buffer, null);
        state.staging_buffer = null;
    }
    if (state.staging_buffer_memory != null) {
        c.vkFreeMemory(state.device, state.staging_buffer_memory, null);
        state.staging_buffer_memory = null;
    }
}

// ============================================================================
// Texture Resources
// ============================================================================

fn createTextureImage(state: *VulkanState) !void {
    // Create image
    const image_info = c.VkImageCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .imageType = c.VK_IMAGE_TYPE_2D,
        .format = c.VK_FORMAT_B8G8R8A8_UNORM, // Matches FrameMailbox format
        .extent = .{
            .width = FRAME_WIDTH,
            .height = FRAME_HEIGHT,
            .depth = 1,
        },
        .mipLevels = 1,
        .arrayLayers = 1,
        .samples = c.VK_SAMPLE_COUNT_1_BIT,
        .tiling = c.VK_IMAGE_TILING_OPTIMAL,
        .usage = c.VK_IMAGE_USAGE_TRANSFER_DST_BIT | c.VK_IMAGE_USAGE_SAMPLED_BIT,
        .sharingMode = c.VK_SHARING_MODE_EXCLUSIVE,
        .queueFamilyIndexCount = 0,
        .pQueueFamilyIndices = null,
        .initialLayout = c.VK_IMAGE_LAYOUT_UNDEFINED,
    };

    var result = c.vkCreateImage(state.device, &image_info, null, &state.texture_image);
    if (result != c.VK_SUCCESS) {
        log.err("Failed to create texture image: {d}", .{result});
        return error.VulkanTextureImageCreationFailed;
    }

    // Allocate memory
    var mem_requirements: c.VkMemoryRequirements = undefined;
    c.vkGetImageMemoryRequirements(state.device, state.texture_image, &mem_requirements);

    const alloc_info = c.VkMemoryAllocateInfo{
        .sType = c.VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
        .pNext = null,
        .allocationSize = mem_requirements.size,
        .memoryTypeIndex = try findMemoryType(state, mem_requirements.memoryTypeBits, c.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT),
    };

    result = c.vkAllocateMemory(state.device, &alloc_info, null, &state.texture_memory);
    if (result != c.VK_SUCCESS) {
        log.err("Failed to allocate texture memory: {d}", .{result});
        return error.VulkanTextureMemoryAllocationFailed;
    }

    result = c.vkBindImageMemory(state.device, state.texture_image, state.texture_memory, 0);
    if (result != c.VK_SUCCESS) {
        log.err("Failed to bind texture memory: {d}", .{result});
        return error.VulkanTextureMemoryBindFailed;
    }

    // Transition to shader read layout (will be filled with black on first upload)
    try transitionImageLayout(
        state,
        state.texture_image,
        c.VK_FORMAT_B8G8R8A8_UNORM,
        c.VK_IMAGE_LAYOUT_UNDEFINED,
        c.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
    );

    log.debug("Texture image created (256×240 BGRA, initialized to shader-read)", .{});
}

fn destroyTextureImage(state: *VulkanState) void {
    if (state.texture_image != null) {
        c.vkDestroyImage(state.device, state.texture_image, null);
        state.texture_image = null;
    }
    if (state.texture_memory != null) {
        c.vkFreeMemory(state.device, state.texture_memory, null);
        state.texture_memory = null;
    }
}

fn createTextureImageView(state: *VulkanState) !void {
    const view_info = c.VkImageViewCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .image = state.texture_image,
        .viewType = c.VK_IMAGE_VIEW_TYPE_2D,
        .format = c.VK_FORMAT_B8G8R8A8_UNORM,
        .components = .{
            .r = c.VK_COMPONENT_SWIZZLE_IDENTITY,
            .g = c.VK_COMPONENT_SWIZZLE_IDENTITY,
            .b = c.VK_COMPONENT_SWIZZLE_IDENTITY,
            .a = c.VK_COMPONENT_SWIZZLE_IDENTITY,
        },
        .subresourceRange = .{
            .aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT,
            .baseMipLevel = 0,
            .levelCount = 1,
            .baseArrayLayer = 0,
            .layerCount = 1,
        },
    };

    const result = c.vkCreateImageView(state.device, &view_info, null, &state.texture_image_view);
    if (result != c.VK_SUCCESS) {
        log.err("Failed to create texture image view: {d}", .{result});
        return error.VulkanTextureImageViewCreationFailed;
    }

    // Update all descriptor sets with the texture
    for (state.descriptor_sets) |descriptor_set| {
        const image_info = c.VkDescriptorImageInfo{
            .imageLayout = c.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
            .imageView = state.texture_image_view,
            .sampler = state.texture_sampler,
        };

        const descriptor_write = c.VkWriteDescriptorSet{
            .sType = c.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
            .pNext = null,
            .dstSet = descriptor_set,
            .dstBinding = 0,
            .dstArrayElement = 0,
            .descriptorCount = 1,
            .descriptorType = c.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
            .pImageInfo = &image_info,
            .pBufferInfo = null,
            .pTexelBufferView = null,
        };

        c.vkUpdateDescriptorSets(state.device, 1, &descriptor_write, 0, null);
    }

    log.debug("Texture image view created and descriptors updated", .{});
}

fn destroyTextureImageView(state: *VulkanState) void {
    if (state.texture_image_view != null) {
        c.vkDestroyImageView(state.device, state.texture_image_view, null);
        state.texture_image_view = null;
    }
}

fn createTextureSampler(state: *VulkanState) !void {
    const sampler_info = c.VkSamplerCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .magFilter = c.VK_FILTER_NEAREST, // Pixel-perfect scaling
        .minFilter = c.VK_FILTER_NEAREST,
        .mipmapMode = c.VK_SAMPLER_MIPMAP_MODE_LINEAR,
        .addressModeU = c.VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE,
        .addressModeV = c.VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE,
        .addressModeW = c.VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE,
        .mipLodBias = 0.0,
        .anisotropyEnable = c.VK_FALSE,
        .maxAnisotropy = 1.0,
        .compareEnable = c.VK_FALSE,
        .compareOp = c.VK_COMPARE_OP_ALWAYS,
        .minLod = 0.0,
        .maxLod = 0.0,
        .borderColor = c.VK_BORDER_COLOR_INT_OPAQUE_BLACK,
        .unnormalizedCoordinates = c.VK_FALSE,
    };

    const result = c.vkCreateSampler(state.device, &sampler_info, null, &state.texture_sampler);
    if (result != c.VK_SUCCESS) {
        log.err("Failed to create texture sampler: {d}", .{result});
        return error.VulkanTextureSamplerCreationFailed;
    }

    log.debug("Texture sampler created (nearest-neighbor filtering)", .{});
}

fn destroyTextureSampler(state: *VulkanState) void {
    if (state.texture_sampler != null) {
        c.vkDestroySampler(state.device, state.texture_sampler, null);
        state.texture_sampler = null;
    }
}

// ============================================================================
// Descriptor Pool and Sets
// ============================================================================

fn createDescriptorPool(state: *VulkanState) !void {
    const pool_size = c.VkDescriptorPoolSize{
        .type = c.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
        .descriptorCount = @intCast(state.max_frames_in_flight),
    };

    const pool_info = c.VkDescriptorPoolCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .maxSets = @intCast(state.max_frames_in_flight),
        .poolSizeCount = 1,
        .pPoolSizes = &pool_size,
    };

    const result = c.vkCreateDescriptorPool(state.device, &pool_info, null, &state.descriptor_pool);
    if (result != c.VK_SUCCESS) {
        log.err("Failed to create descriptor pool: {d}", .{result});
        return error.VulkanDescriptorPoolCreationFailed;
    }

    log.debug("Descriptor pool created", .{});
}

fn destroyDescriptorPool(state: *VulkanState) void {
    if (state.descriptor_pool != null) {
        c.vkDestroyDescriptorPool(state.device, state.descriptor_pool, null);
        state.descriptor_pool = null;
    }
}

fn createDescriptorSets(state: *VulkanState) !void {
    // Allocate layouts array
    const layouts = try state.allocator.alloc(c.VkDescriptorSetLayout, state.max_frames_in_flight);
    defer state.allocator.free(layouts);
    for (layouts) |*layout| {
        layout.* = state.descriptor_set_layout;
    }

    const alloc_info = c.VkDescriptorSetAllocateInfo{
        .sType = c.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,
        .pNext = null,
        .descriptorPool = state.descriptor_pool,
        .descriptorSetCount = @intCast(state.max_frames_in_flight),
        .pSetLayouts = layouts.ptr,
    };

    state.descriptor_sets = try state.allocator.alloc(c.VkDescriptorSet, state.max_frames_in_flight);

    const result = c.vkAllocateDescriptorSets(state.device, &alloc_info, state.descriptor_sets.ptr);
    if (result != c.VK_SUCCESS) {
        log.err("Failed to allocate descriptor sets: {d}", .{result});
        return error.VulkanDescriptorSetAllocationFailed;
    }

    // Note: Descriptor sets will be updated with texture in createTextureImage

    log.debug("Allocated {d} descriptor sets", .{state.descriptor_sets.len});
}

// ============================================================================
// Synchronization
// ============================================================================

fn createSyncObjects(state: *VulkanState) !void {
    state.image_available_semaphores = try state.allocator.alloc(c.VkSemaphore, state.max_frames_in_flight);
    state.render_finished_semaphores = try state.allocator.alloc(c.VkSemaphore, state.max_frames_in_flight);
    state.in_flight_fences = try state.allocator.alloc(c.VkFence, state.max_frames_in_flight);

    const semaphore_info = c.VkSemaphoreCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
    };

    const fence_info = c.VkFenceCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_FENCE_CREATE_INFO,
        .pNext = null,
        .flags = c.VK_FENCE_CREATE_SIGNALED_BIT, // Start signaled so first frame doesn't wait
    };

    var i: u32 = 0;
    while (i < state.max_frames_in_flight) : (i += 1) {
        var result = c.vkCreateSemaphore(state.device, &semaphore_info, null, &state.image_available_semaphores[i]);
        if (result != c.VK_SUCCESS) {
            log.err("Failed to create image available semaphore {d}: {d}", .{ i, result });
            return error.VulkanSemaphoreCreationFailed;
        }

        result = c.vkCreateSemaphore(state.device, &semaphore_info, null, &state.render_finished_semaphores[i]);
        if (result != c.VK_SUCCESS) {
            log.err("Failed to create render finished semaphore {d}: {d}", .{ i, result });
            return error.VulkanSemaphoreCreationFailed;
        }

        result = c.vkCreateFence(state.device, &fence_info, null, &state.in_flight_fences[i]);
        if (result != c.VK_SUCCESS) {
            log.err("Failed to create in-flight fence {d}: {d}", .{ i, result });
            return error.VulkanFenceCreationFailed;
        }
    }

    log.debug("Created {d} sync objects (semaphores + fences)", .{state.max_frames_in_flight});
}

fn destroySyncObjects(state: *VulkanState) void {
    for (state.image_available_semaphores) |sem| {
        c.vkDestroySemaphore(state.device, sem, null);
    }
    state.allocator.free(state.image_available_semaphores);
    state.image_available_semaphores = &.{};

    for (state.render_finished_semaphores) |sem| {
        c.vkDestroySemaphore(state.device, sem, null);
    }
    state.allocator.free(state.render_finished_semaphores);
    state.render_finished_semaphores = &.{};

    for (state.in_flight_fences) |fence| {
        c.vkDestroyFence(state.device, fence, null);
    }
    state.allocator.free(state.in_flight_fences);
    state.in_flight_fences = &.{};
}

// ============================================================================
// Texture Upload
// ============================================================================

fn uploadTextureData(state: *VulkanState, frame_data: []const u32) !void {
    // Map staging buffer and copy frame data
    var data: ?*anyopaque = undefined;
    const buffer_size = FRAME_WIDTH * FRAME_HEIGHT * @sizeOf(u32);

    const result = c.vkMapMemory(state.device, state.staging_buffer_memory, 0, buffer_size, 0, &data);
    if (result != c.VK_SUCCESS) {
        log.err("Failed to map staging buffer memory: {d}", .{result});
        return error.VulkanMemoryMapFailed;
    }

    // Copy frame data to staging buffer
    const dest_ptr: [*]u32 = @ptrCast(@alignCast(data));
    @memcpy(dest_ptr[0 .. FRAME_WIDTH * FRAME_HEIGHT], frame_data);

    c.vkUnmapMemory(state.device, state.staging_buffer_memory);

    // Transition texture to transfer dst layout
    try transitionImageLayout(
        state,
        state.texture_image,
        c.VK_FORMAT_B8G8R8A8_UNORM,
        c.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
        c.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
    );

    // Copy staging buffer to texture
    try copyBufferToImage(
        state,
        state.staging_buffer,
        state.texture_image,
        FRAME_WIDTH,
        FRAME_HEIGHT,
    );

    // Transition back to shader read layout
    try transitionImageLayout(
        state,
        state.texture_image,
        c.VK_FORMAT_B8G8R8A8_UNORM,
        c.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
        c.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
    );
}

// ============================================================================
// Rendering
// ============================================================================

/// Render a frame from FrameMailbox data
pub fn renderFrame(state: *VulkanState, frame_data: []const u32) !void {
    // Upload frame data to GPU texture
    try uploadTextureData(state, frame_data);

    // Wait for previous frame
    _ = c.vkWaitForFences(state.device, 1, &state.in_flight_fences[state.current_frame], c.VK_TRUE, std.math.maxInt(u64));

    // Acquire next swapchain image
    var image_index: u32 = 0;
    var result = c.vkAcquireNextImageKHR(
        state.device,
        state.swapchain,
        std.math.maxInt(u64),
        state.image_available_semaphores[state.current_frame],
        null,
        &image_index,
    );

    if (result == c.VK_ERROR_OUT_OF_DATE_KHR) {
        // Swapchain needs recreation (window resized)
        return error.SwapchainOutOfDate;
    } else if (result != c.VK_SUCCESS and result != c.VK_SUBOPTIMAL_KHR) {
        log.err("Failed to acquire swapchain image: {d}", .{result});
        return error.VulkanAcquireImageFailed;
    }

    // Reset fence only if we're submitting work
    _ = c.vkResetFences(state.device, 1, &state.in_flight_fences[state.current_frame]);

    // Reset and record command buffer
    const cmd_buffer = state.command_buffers[state.current_frame];
    _ = c.vkResetCommandBuffer(cmd_buffer, 0);

    const begin_info = c.VkCommandBufferBeginInfo{
        .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
        .pNext = null,
        .flags = 0,
        .pInheritanceInfo = null,
    };

    result = c.vkBeginCommandBuffer(cmd_buffer, &begin_info);
    if (result != c.VK_SUCCESS) {
        log.err("Failed to begin command buffer: {d}", .{result});
        return error.VulkanCommandBufferBeginFailed;
    }

    // Begin render pass
    const clear_color = c.VkClearValue{
        .color = .{ .float32 = [_]f32{ 0.0, 0.0, 0.0, 1.0 } }, // Black
    };

    const render_pass_info = c.VkRenderPassBeginInfo{
        .sType = c.VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO,
        .pNext = null,
        .renderPass = state.render_pass,
        .framebuffer = state.framebuffers[image_index],
        .renderArea = .{
            .offset = .{ .x = 0, .y = 0 },
            .extent = state.swapchain_extent,
        },
        .clearValueCount = 1,
        .pClearValues = &clear_color,
    };

    c.vkCmdBeginRenderPass(cmd_buffer, &render_pass_info, c.VK_SUBPASS_CONTENTS_INLINE);

    // Bind pipeline
    c.vkCmdBindPipeline(cmd_buffer, c.VK_PIPELINE_BIND_POINT_GRAPHICS, state.graphics_pipeline);

    // Bind descriptor sets (texture)
    c.vkCmdBindDescriptorSets(
        cmd_buffer,
        c.VK_PIPELINE_BIND_POINT_GRAPHICS,
        state.pipeline_layout,
        0,
        1,
        &state.descriptor_sets[state.current_frame],
        0,
        null,
    );

    // Draw fullscreen triangle
    c.vkCmdDraw(cmd_buffer, 3, 1, 0, 0);

    c.vkCmdEndRenderPass(cmd_buffer);

    result = c.vkEndCommandBuffer(cmd_buffer);
    if (result != c.VK_SUCCESS) {
        log.err("Failed to end command buffer: {d}", .{result});
        return error.VulkanCommandBufferEndFailed;
    }

    // Submit command buffer
    const wait_semaphores = [_]c.VkSemaphore{state.image_available_semaphores[state.current_frame]};
    const wait_stages = [_]c.VkPipelineStageFlags{c.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT};
    const signal_semaphores = [_]c.VkSemaphore{state.render_finished_semaphores[state.current_frame]};

    const submit_info = c.VkSubmitInfo{
        .sType = c.VK_STRUCTURE_TYPE_SUBMIT_INFO,
        .pNext = null,
        .waitSemaphoreCount = 1,
        .pWaitSemaphores = &wait_semaphores,
        .pWaitDstStageMask = &wait_stages,
        .commandBufferCount = 1,
        .pCommandBuffers = &cmd_buffer,
        .signalSemaphoreCount = 1,
        .pSignalSemaphores = &signal_semaphores,
    };

    result = c.vkQueueSubmit(state.graphics_queue, 1, &submit_info, state.in_flight_fences[state.current_frame]);
    if (result != c.VK_SUCCESS) {
        log.err("Failed to submit draw command buffer: {d}", .{result});
        return error.VulkanQueueSubmitFailed;
    }

    // Present
    const present_info = c.VkPresentInfoKHR{
        .sType = c.VK_STRUCTURE_TYPE_PRESENT_INFO_KHR,
        .pNext = null,
        .waitSemaphoreCount = 1,
        .pWaitSemaphores = &signal_semaphores,
        .swapchainCount = 1,
        .pSwapchains = &state.swapchain,
        .pImageIndices = &image_index,
        .pResults = null,
    };

    result = c.vkQueuePresentKHR(state.present_queue, &present_info);
    if (result == c.VK_ERROR_OUT_OF_DATE_KHR or result == c.VK_SUBOPTIMAL_KHR) {
        return error.SwapchainOutOfDate;
    } else if (result != c.VK_SUCCESS) {
        log.err("Failed to present swapchain image: {d}", .{result});
        return error.VulkanPresentFailed;
    }

    // Advance to next frame
    state.current_frame = (state.current_frame + 1) % state.max_frames_in_flight;
}
