//! Vulkan Core: Instance, Surface, and Device Management
//!
//! Handles:
//! - Vulkan instance creation with validation layers
//! - Wayland surface creation
//! - Physical device selection
//! - Logical device creation with queue families

const std = @import("std");
const log = std.log.scoped(.vulkan_core);

const VulkanState = @import("../VulkanState.zig").VulkanState;
const WaylandState = @import("../WaylandState.zig").WaylandState;
const WaylandLogic = @import("../WaylandLogic.zig");

const c = @import("../VulkanBindings.zig").c;

// ============================================================================
// Constants
// ============================================================================

const VALIDATION_LAYERS = [_][*:0]const u8{
    "VK_LAYER_KHRONOS_validation",
};

const DEVICE_EXTENSIONS = [_][*:0]const u8{
    c.VK_KHR_SWAPCHAIN_EXTENSION_NAME,
};

// ============================================================================
// Instance Management
// ============================================================================

pub fn createInstance(state: *VulkanState) !void {
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

pub fn destroyInstance(state: *VulkanState) void {
    if (state.instance != null) {
        c.vkDestroyInstance(state.instance, null);
        state.instance = null;
    }
}

// ============================================================================
// Surface Management
// ============================================================================

pub fn createSurface(state: *VulkanState, wayland: *WaylandState) !void {
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

pub fn destroySurface(state: *VulkanState) void {
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

pub fn pickPhysicalDevice(state: *VulkanState) !void {
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

pub const SwapchainSupportDetails = struct {
    capabilities: c.VkSurfaceCapabilitiesKHR,
    formats: []c.VkSurfaceFormatKHR,
    present_modes: []c.VkPresentModeKHR,

    pub fn deinit(self: @This(), allocator: std.mem.Allocator) void {
        allocator.free(self.formats);
        allocator.free(self.present_modes);
    }
};

pub fn querySwapchainSupport(
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

// ============================================================================
// Logical Device Management
// ============================================================================

pub fn createLogicalDevice(state: *VulkanState) !void {
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

pub fn destroyLogicalDevice(state: *VulkanState) void {
    if (state.device != null) {
        c.vkDestroyDevice(state.device, null);
        state.device = null;
    }
}
