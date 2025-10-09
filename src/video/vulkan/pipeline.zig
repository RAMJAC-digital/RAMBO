//! Vulkan Pipeline: Descriptor Layouts, Graphics Pipeline, and Descriptor Sets
//!
//! Handles:
//! - Descriptor set layouts for texture sampling
//! - Graphics pipeline creation with shader modules
//! - Descriptor pool and set allocation

const std = @import("std");
const log = std.log.scoped(.vulkan_pipeline);

const VulkanState = @import("../VulkanState.zig").VulkanState;
const c = @import("../VulkanBindings.zig").c;

// ============================================================================
// Descriptor Set Layout
// ============================================================================

pub fn createDescriptorSetLayout(state: *VulkanState) !void {
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

pub fn destroyDescriptorSetLayout(state: *VulkanState) void {
    if (state.descriptor_set_layout != null) {
        c.vkDestroyDescriptorSetLayout(state.device, state.descriptor_set_layout, null);
        state.descriptor_set_layout = null;
    }
}

// ============================================================================
// Shader Module Helpers
// ============================================================================

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

// ============================================================================
// Graphics Pipeline
// ============================================================================

pub fn createGraphicsPipeline(state: *VulkanState) !void {
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

pub fn destroyGraphicsPipeline(state: *VulkanState) void {
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
// Descriptor Pool and Sets
// ============================================================================

pub fn createDescriptorPool(state: *VulkanState) !void {
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

pub fn destroyDescriptorPool(state: *VulkanState) void {
    if (state.descriptor_pool != null) {
        c.vkDestroyDescriptorPool(state.device, state.descriptor_pool, null);
        state.descriptor_pool = null;
    }
}

pub fn createDescriptorSets(state: *VulkanState) !void {
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

    // Note: Descriptor sets will be updated with texture in createTextureImageView

    log.debug("Allocated {d} descriptor sets", .{state.descriptor_sets.len});
}
