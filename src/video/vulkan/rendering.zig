//! Vulkan Rendering: Frame Rendering and Texture Upload
//!
//! Handles:
//! - Texture data upload from FrameMailbox
//! - Per-frame rendering with command buffer recording
//! - Swapchain presentation

const std = @import("std");
const log = std.log.scoped(.vulkan_rendering);

const VulkanState = @import("../VulkanState.zig").VulkanState;
const resources = @import("resources.zig");
const c = @import("../VulkanBindings.zig").c;

// NES framebuffer dimensions
const FRAME_WIDTH = 256;
const FRAME_HEIGHT = 240;

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
    try resources.transitionImageLayout(
        state,
        state.texture_image,
        c.VK_FORMAT_B8G8R8A8_UNORM,
        c.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
        c.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
    );

    // Copy staging buffer to texture
    try resources.copyBufferToImage(
        state,
        state.staging_buffer,
        state.texture_image,
        FRAME_WIDTH,
        FRAME_HEIGHT,
    );

    // Transition back to shader read layout
    try resources.transitionImageLayout(
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
