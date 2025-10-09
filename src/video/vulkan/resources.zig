//! Vulkan Resources: Command Buffers, Memory, Textures, and Synchronization
//!
//! Handles:
//! - Command pool and buffer management
//! - Memory allocation and buffer creation
//! - Texture image creation and management
//! - Synchronization primitives (semaphores, fences)

const std = @import("std");
const log = std.log.scoped(.vulkan_resources);

const VulkanState = @import("../VulkanState.zig").VulkanState;
const c = @import("../VulkanBindings.zig").c;

// NES framebuffer dimensions
const FRAME_WIDTH = 256;
const FRAME_HEIGHT = 240;

// ============================================================================
// Command Pool and Buffers
// ============================================================================

pub fn createCommandPool(state: *VulkanState) !void {
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

pub fn destroyCommandPool(state: *VulkanState) void {
    if (state.command_pool != null) {
        c.vkDestroyCommandPool(state.device, state.command_pool, null);
        state.command_pool = null;
    }
}

pub fn createCommandBuffers(state: *VulkanState) !void {
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

pub fn findMemoryType(state: *VulkanState, type_filter: u32, properties: c.VkMemoryPropertyFlags) !u32 {
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

pub fn createBuffer(
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

pub fn beginSingleTimeCommands(state: *VulkanState) !c.VkCommandBuffer {
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

pub fn endSingleTimeCommands(state: *VulkanState, command_buffer: c.VkCommandBuffer) !void {
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

pub fn transitionImageLayout(
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

pub fn copyBufferToImage(
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

pub fn createStagingBuffer(state: *VulkanState) !void {
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

pub fn destroyStagingBuffer(state: *VulkanState) void {
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

pub fn createTextureImage(state: *VulkanState) !void {
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

pub fn destroyTextureImage(state: *VulkanState) void {
    if (state.texture_image != null) {
        c.vkDestroyImage(state.device, state.texture_image, null);
        state.texture_image = null;
    }
    if (state.texture_memory != null) {
        c.vkFreeMemory(state.device, state.texture_memory, null);
        state.texture_memory = null;
    }
}

pub fn createTextureImageView(state: *VulkanState) !void {
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

pub fn destroyTextureImageView(state: *VulkanState) void {
    if (state.texture_image_view != null) {
        c.vkDestroyImageView(state.device, state.texture_image_view, null);
        state.texture_image_view = null;
    }
}

pub fn createTextureSampler(state: *VulkanState) !void {
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

pub fn destroyTextureSampler(state: *VulkanState) void {
    if (state.texture_sampler != null) {
        c.vkDestroySampler(state.device, state.texture_sampler, null);
        state.texture_sampler = null;
    }
}

// ============================================================================
// Synchronization
// ============================================================================

pub fn createSyncObjects(state: *VulkanState) !void {
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

pub fn destroySyncObjects(state: *VulkanState) void {
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
