//! Vulkan Swapchain: Swapchain, Render Pass, and Framebuffer Management
//!
//! Handles:
//! - Swapchain creation with format/mode selection
//! - Render pass configuration
//! - Framebuffer creation for swapchain images

const std = @import("std");
const log = std.log.scoped(.vulkan_swapchain);

const VulkanState = @import("../VulkanState.zig").VulkanState;
const core = @import("core.zig");
const c = @import("../VulkanBindings.zig").c;

// ============================================================================
// Swapchain Management
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

pub fn createSwapchain(state: *VulkanState) !void {
    const swapchain_support = try core.querySwapchainSupport(state.allocator, state.physical_device, state.surface);
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
    const queue_family_indices = [_]u32{ state.graphics_queue_family, state.present_queue_family };
    const sharing_mode: c.VkSharingMode = if (state.graphics_queue_family != state.present_queue_family)
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

pub fn destroySwapchain(state: *VulkanState) void {
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
// Render Pass Management
// ============================================================================

pub fn createRenderPass(state: *VulkanState) !void {
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

pub fn destroyRenderPass(state: *VulkanState) void {
    if (state.render_pass != null) {
        c.vkDestroyRenderPass(state.device, state.render_pass, null);
        state.render_pass = null;
    }
}

// ============================================================================
// Framebuffer Management
// ============================================================================

pub fn createFramebuffers(state: *VulkanState) !void {
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

pub fn destroyFramebuffers(state: *VulkanState) void {
    for (state.framebuffers) |fb| {
        c.vkDestroyFramebuffer(state.device, fb, null);
    }
    state.allocator.free(state.framebuffers);
    state.framebuffers = &.{};
}
