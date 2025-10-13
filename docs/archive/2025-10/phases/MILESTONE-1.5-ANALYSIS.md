# Milestone 1.5: VulkanLogic Decomposition - Analysis

**Date:** 2025-10-09
**Status:** Research Phase
**Risk Level:** 🟡 MEDIUM (Large file, but clear sequential structure)

---

## Executive Summary

**Target File:** `VulkanLogic.zig` (1,857 lines, 53 functions)
**Location:** `/home/colin/Development/RAMBO/src/video/VulkanLogic.zig`
**Complexity:** MEDIUM - Sequential imperative code with clear functional groupings
**External Dependencies:**
- Wayland (only in createSurface for display/surface handles)
- FrameMailbox (only in renderFrame for frame data)

### Key Characteristics

1. **Sequential & Imperative:** Vulkan initialization follows a strict order
2. **Natural Groupings:** Functions cluster by Vulkan object lifecycle
3. **Minimal Interconnection:** Most functions operate on VulkanState independently
4. **Clear Boundaries:** Create/destroy pairs with helper functions

---

## File Structure Analysis

### Function Count & Organization

**Total Functions:** 53
- **Public Functions:** 3 (init, deinit, renderFrame)
- **Private Functions:** 50 (initialization, cleanup, helpers)

**Line Distribution:**
- Total: 1,857 lines
- init(): 77 lines (sequential create* calls with errdefer)
- deinit(): 28 lines (sequential destroy* calls)
- renderFrame(): 138 lines (render loop)
- Helper functions: ~1,600 lines (create/destroy/utility functions)

---

## Functional Groupings

### 1. Instance & Surface (5 functions, ~150 lines)

**Functions:**
- `createInstance()` - Create Vulkan instance with validation layers
- `destroyInstance()` - Cleanup Vulkan instance
- `checkValidationLayerSupport()` - Validate debug layer availability
- `createSurface()` - Create Wayland surface (ONLY Wayland dependency!)
- `destroySurface()` - Cleanup surface

**Dependencies:**
- **Wayland:** `createSurface()` calls `WaylandLogic.rawHandles(wayland)` to get display/surface
- **State:** Mutates `state.instance`, `state.surface`

**Extraction Target:** `vulkan/instance.zig`

### 2. Device Selection (4 functions, ~180 lines)

**Functions:**
- `pickPhysicalDevice()` - Select GPU from available devices
- `isDeviceSuitable()` - Check if GPU meets requirements
- `findQueueFamilies()` - Find graphics/present queue families
- `checkDeviceExtensionSupport()` - Validate swapchain extension

**Dependencies:**
- **State:** Reads `state.surface`, `state.instance`
- **State:** Mutates `state.physical_device`, `state.graphics_family`, `state.present_family`

**Extraction Target:** `vulkan/device_selection.zig`

### 3. Logical Device & Queues (2 functions, ~70 lines)

**Functions:**
- `createLogicalDevice()` - Create logical device and get queue handles
- `destroyLogicalDevice()` - Cleanup logical device

**Dependencies:**
- **State:** Reads `state.physical_device`, queue families
- **State:** Mutates `state.device`, `state.graphics_queue`, `state.present_queue`

**Extraction Target:** `vulkan/device.zig`

### 4. Swapchain Management (6 functions, ~220 lines)

**Functions:**
- `createSwapchain()` - Create swapchain with chosen format/mode/extent
- `destroySwapchain()` - Cleanup swapchain and image views
- `querySwapchainSupport()` - Query surface capabilities
- `chooseSwapSurfaceFormat()` - Select BGRA8 format
- `chooseSwapPresentMode()` - Select mailbox/FIFO mode
- `chooseSwapExtent()` - Calculate swapchain dimensions

**Dependencies:**
- **State:** Reads `state.device`, `state.physical_device`, `state.surface`
- **State:** Mutates `state.swapchain`, `state.swapchain_images`, `state.swapchain_image_views`, `state.swapchain_image_format`, `state.swapchain_extent`

**Extraction Target:** `vulkan/swapchain.zig`

### 5. Render Pass (2 functions, ~75 lines)

**Functions:**
- `createRenderPass()` - Define rendering operations
- `destroyRenderPass()` - Cleanup render pass

**Dependencies:**
- **State:** Reads `state.device`, `state.swapchain_image_format`
- **State:** Mutates `state.render_pass`

**Extraction Target:** `vulkan/render_pass.zig`

### 6. Framebuffers (2 functions, ~40 lines)

**Functions:**
- `createFramebuffers()` - Create framebuffer for each swapchain image
- `destroyFramebuffers()` - Cleanup all framebuffers

**Dependencies:**
- **State:** Reads `state.device`, `state.swapchain_image_views`, `state.render_pass`, `state.swapchain_extent`
- **State:** Mutates `state.framebuffers`

**Extraction Target:** `vulkan/framebuffers.zig`

### 7. Descriptor Set Layout (2 functions, ~40 lines)

**Functions:**
- `createDescriptorSetLayout()` - Define texture sampler binding
- `destroyDescriptorSetLayout()` - Cleanup descriptor set layout

**Dependencies:**
- **State:** Reads `state.device`
- **State:** Mutates `state.descriptor_set_layout`

**Extraction Target:** `vulkan/descriptors.zig` (part 1)

### 8. Graphics Pipeline (4 functions, ~210 lines)

**Functions:**
- `createGraphicsPipeline()` - Build graphics pipeline with shaders
- `destroyGraphicsPipeline()` - Cleanup pipeline and layout
- `readShaderFile()` - Load SPIR-V shader bytecode
- `createShaderModule()` - Create VkShaderModule from bytecode

**Dependencies:**
- **State:** Reads `state.device`, `state.render_pass`, `state.descriptor_set_layout`, `state.swapchain_extent`
- **State:** Mutates `state.graphics_pipeline`, `state.pipeline_layout`
- **Files:** Reads `shaders/texture.vert.spv`, `shaders/texture.frag.spv`

**Extraction Target:** `vulkan/pipeline.zig`

### 9. Command Pool & Buffers (5 functions, ~150 lines)

**Functions:**
- `createCommandPool()` - Create command pool for graphics queue
- `destroyCommandPool()` - Cleanup command pool
- `createCommandBuffers()` - Allocate command buffers
- `beginSingleTimeCommands()` - Start one-time command recording
- `endSingleTimeCommands()` - Submit and wait for one-time command

**Dependencies:**
- **State:** Reads `state.device`, `state.graphics_family`, `state.command_pool`, `state.graphics_queue`
- **State:** Mutates `state.command_pool`, `state.command_buffers`

**Extraction Target:** `vulkan/commands.zig`

### 10. Memory & Buffers (5 functions, ~200 lines)

**Functions:**
- `findMemoryType()` - Find suitable memory type for allocation
- `createBuffer()` - Create VkBuffer with memory
- `createStagingBuffer()` - Create staging buffer for uploads
- `destroyStagingBuffer()` - Cleanup staging buffer
- `transitionImageLayout()` - Pipeline barrier for image layout transitions
- `copyBufferToImage()` - Copy staging buffer to image

**Dependencies:**
- **State:** Reads `state.device`, `state.physical_device`, `state.command_pool`, `state.graphics_queue`
- **State:** Mutates `state.staging_buffer`, `state.staging_buffer_memory`

**Extraction Target:** `vulkan/buffers.zig`

### 11. Texture Resources (8 functions, ~250 lines)

**Functions:**
- `createTextureImage()` - Create 256×240 BGRA texture
- `destroyTextureImage()` - Cleanup texture image
- `createTextureImageView()` - Create image view for shader access
- `destroyTextureImageView()` - Cleanup image view
- `createTextureSampler()` - Create nearest-neighbor sampler
- `destroyTextureSampler()` - Cleanup sampler

**Dependencies:**
- **State:** Reads `state.device`, `state.physical_device`, `state.command_pool`, `state.graphics_queue`
- **State:** Mutates `state.texture_image`, `state.texture_image_memory`, `state.texture_image_view`, `state.texture_sampler`

**Extraction Target:** `vulkan/texture.zig`

### 12. Descriptor Pool & Sets (4 functions, ~100 lines)

**Functions:**
- `createDescriptorPool()` - Create descriptor pool
- `destroyDescriptorPool()` - Cleanup descriptor pool
- `createDescriptorSets()` - Allocate and update descriptor sets

**Dependencies:**
- **State:** Reads `state.device`, `state.descriptor_set_layout`, `state.max_frames_in_flight`
- **State:** Mutates `state.descriptor_pool`, `state.descriptor_sets`
- **Note:** Updates descriptors after texture sampler/view created

**Extraction Target:** `vulkan/descriptors.zig` (part 2)

### 13. Synchronization (2 functions, ~45 lines)

**Functions:**
- `createSyncObjects()` - Create semaphores and fences
- `destroySyncObjects()` - Cleanup sync objects

**Dependencies:**
- **State:** Reads `state.device`, `state.max_frames_in_flight`
- **State:** Mutates `state.image_available_semaphores`, `state.render_finished_semaphores`, `state.in_flight_fences`

**Extraction Target:** `vulkan/sync.zig`

### 14. Rendering (2 functions, ~150 lines)

**Functions:**
- `renderFrame()` - Main render loop (PUBLIC)
- `uploadTextureData()` - Upload frame data to GPU texture

**Dependencies:**
- **State:** Reads ALL Vulkan state
- **FrameMailbox:** `frame_data` parameter from mailbox
- **Orchestrates:** Uses command buffers, swapchain, pipeline, descriptors, sync objects

**Extraction Target:** Keep in main `VulkanLogic.zig` OR `vulkan/rendering.zig`

---

## Wayland & Mailbox Dependencies

### Wayland Connection

**Single Point of Contact:** `createSurface()`

```zig
fn createSurface(state: *VulkanState, wayland: *WaylandState) !void {
    const handles = WaylandLogic.rawHandles(wayland);
    // Create VkSurfaceKHR from Wayland display/surface
}
```

**Isolation:**
- Only `init()` passes `wayland` parameter to `createSurface()`
- All other functions operate on `state.surface` (VkSurfaceKHR)
- **No other Wayland dependencies in VulkanLogic**

### Mailbox Connection

**Single Point of Contact:** `renderFrame()` and `uploadTextureData()`

```zig
pub fn renderFrame(state: *VulkanState, frame_data: []const u32) !void {
    try uploadTextureData(state, frame_data); // Upload to GPU
    // Render to screen
}
```

**Isolation:**
- Render thread reads from FrameMailbox
- Passes `frame_data` slice to `renderFrame()`
- **No direct mailbox access in VulkanLogic**

---

## Extraction Strategy

### Option A: Functional Grouping (RECOMMENDED)

**Create 14 modules organized by Vulkan object type:**

```
src/video/vulkan/
├── instance.zig         (5 functions, ~150 lines)
├── device_selection.zig (4 functions, ~180 lines)
├── device.zig           (2 functions, ~70 lines)
├── swapchain.zig        (6 functions, ~220 lines)
├── render_pass.zig      (2 functions, ~75 lines)
├── framebuffers.zig     (2 functions, ~40 lines)
├── descriptors.zig      (6 functions, ~140 lines)
├── pipeline.zig         (4 functions, ~210 lines)
├── commands.zig         (5 functions, ~150 lines)
├── buffers.zig          (5 functions, ~200 lines)
├── texture.zig          (8 functions, ~250 lines)
├── sync.zig             (2 functions, ~45 lines)
└── rendering.zig        (2 functions, ~150 lines) [OPTIONAL]
```

**VulkanLogic.zig becomes orchestrator:**
```zig
// src/video/VulkanLogic.zig (reduced to ~200 lines)
const Instance = @import("vulkan/instance.zig");
const DeviceSelection = @import("vulkan/device_selection.zig");
const Device = @import("vulkan/device.zig");
// ... etc

pub fn init(...) !VulkanState {
    try Instance.create(&state);
    try Instance.createSurface(&state, wayland); // Wayland dependency isolated here
    try DeviceSelection.pick(&state);
    try Device.createLogical(&state);
    try Swapchain.create(&state);
    // ... etc
}

pub fn deinit(state: *VulkanState) void {
    Sync.destroy(state);
    // ... etc (reverse order)
    Instance.destroy(state);
}

pub fn renderFrame(state: *VulkanState, frame_data: []const u32) !void {
    // Keep here or move to rendering.zig
}
```

**Pros:**
- Natural organization by Vulkan object lifecycle
- Each module is self-contained (~40-250 lines)
- Easy to navigate and understand
- Matches Vulkan API structure

**Cons:**
- 13-14 new files (many modules)
- Need to manage imports in VulkanLogic orchestrator

### Option B: Lifecycle Phases (SIMPLER)

**Create 3 modules organized by initialization phase:**

```
src/video/vulkan/
├── initialization.zig  (~1200 lines, 40 functions)
├── rendering.zig       (~150 lines, 2 functions)
└── cleanup.zig         (~200 lines, 11 destroy functions)
```

**Pros:**
- Fewer files (3 modules)
- Clear separation: init, render, cleanup
- Less import management

**Cons:**
- initialization.zig still large (~1200 lines)
- Less modular than Option A
- Harder to find specific functionality

---

## Recommended Approach: Option A with Staged Extraction

### Phase 1: High-Level Grouping (THIS MILESTONE)

**Create 5 logical groups:**

1. **`vulkan/init_core.zig`** - Instance, Surface, Device Selection, Logical Device
   - Functions: 13 (~470 lines)
   - Groups: Instance & Surface, Device Selection, Logical Device

2. **`vulkan/init_swapchain.zig`** - Swapchain, Render Pass, Framebuffers
   - Functions: 10 (~335 lines)
   - Groups: Swapchain, Render Pass, Framebuffers

3. **`vulkan/init_pipeline.zig`** - Descriptors, Pipeline, Shaders
   - Functions: 10 (~350 lines)
   - Groups: Descriptor Set Layout, Pipeline, Descriptor Pool/Sets

4. **`vulkan/init_resources.zig`** - Commands, Buffers, Textures, Sync
   - Functions: 20 (~745 lines)
   - Groups: Command Pool/Buffers, Memory/Buffers, Texture Resources, Sync

5. **`vulkan/rendering.zig`** - Render loop
   - Functions: 2 (~150 lines)
   - renderFrame(), uploadTextureData()

**Result:**
- VulkanLogic.zig: 1,857 → ~100 lines (orchestrator only)
- New files: 5 (+2,050 lines with comprehensive docs)
- Net: +193 lines (documentation overhead)

### Phase 2: Fine-Grained Decomposition (FUTURE)

Split the 5 high-level modules into 14 fine-grained modules (Option A structure).

**Defer to Phase 2 of refactoring plan:**
- More complex import management
- Diminishing returns for initial modularity goals
- Can be done incrementally as needed

---

## Implementation Plan

### Step 1: Create Module Structure

```bash
mkdir -p src/video/vulkan
```

### Step 2: Extract in Dependency Order

**Order is critical - functions depend on earlier groups:**

1. `vulkan/init_core.zig` (instance, surface, device)
2. `vulkan/init_swapchain.zig` (swapchain, render pass, framebuffers)
3. `vulkan/init_pipeline.zig` (descriptors, pipeline)
4. `vulkan/init_resources.zig` (commands, buffers, textures, sync)
5. `vulkan/rendering.zig` (render loop)

### Step 3: Update VulkanLogic.zig

Replace function implementations with module imports and delegation:

```zig
const InitCore = @import("vulkan/init_core.zig");
const InitSwapchain = @import("vulkan/init_swapchain.zig");
const InitPipeline = @import("vulkan/init_pipeline.zig");
const InitResources = @import("vulkan/init_resources.zig");
const Rendering = @import("vulkan/rendering.zig");

pub fn init(...) !VulkanState {
    var state = VulkanState{ .allocator = allocator, ... };

    // Core initialization
    try InitCore.createInstance(&state);
    errdefer InitCore.destroyInstance(&state);

    try InitCore.createSurface(&state, wayland);
    errdefer InitCore.destroySurface(&state);

    try InitCore.pickPhysicalDevice(&state);
    try InitCore.createLogicalDevice(&state);
    errdefer InitCore.destroyLogicalDevice(&state);

    // Swapchain initialization
    try InitSwapchain.createSwapchain(&state);
    errdefer InitSwapchain.destroySwapchain(&state);

    try InitSwapchain.createRenderPass(&state);
    errdefer InitSwapchain.destroyRenderPass(&state);

    try InitSwapchain.createFramebuffers(&state);
    errdefer InitSwapchain.destroyFramebuffers(&state);

    // Pipeline initialization
    try InitPipeline.createDescriptorSetLayout(&state);
    errdefer InitPipeline.destroyDescriptorSetLayout(&state);

    try InitPipeline.createGraphicsPipeline(&state);
    errdefer InitPipeline.destroyGraphicsPipeline(&state);

    // Resources initialization
    try InitResources.createCommandPool(&state);
    errdefer InitResources.destroyCommandPool(&state);

    try InitResources.createStagingBuffer(&state);
    errdefer InitResources.destroyStagingBuffer(&state);

    try InitResources.createTextureImage(&state);
    errdefer InitResources.destroyTextureImage(&state);

    try InitResources.createTextureSampler(&state);
    errdefer InitResources.destroyTextureSampler(&state);

    try InitPipeline.createDescriptorPool(&state);
    errdefer InitPipeline.destroyDescriptorPool(&state);

    try InitPipeline.createDescriptorSets(&state);

    try InitResources.createTextureImageView(&state);
    errdefer InitResources.destroyTextureImageView(&state);

    try InitResources.createCommandBuffers(&state);

    try InitResources.createSyncObjects(&state);
    errdefer InitResources.destroySyncObjects(&state);

    return state;
}

pub fn deinit(state: *VulkanState) void {
    InitResources.destroySyncObjects(state);
    InitResources.destroyCommandPool(state);
    InitResources.destroyTextureSampler(state);
    InitResources.destroyTextureImageView(state);
    InitResources.destroyTextureImage(state);
    InitPipeline.destroyDescriptorPool(state);
    InitPipeline.destroyGraphicsPipeline(state);
    InitPipeline.destroyDescriptorSetLayout(state);
    InitResources.destroyStagingBuffer(state);
    InitSwapchain.destroyFramebuffers(state);
    InitSwapchain.destroyRenderPass(state);
    InitSwapchain.destroySwapchain(state);
    InitCore.destroyLogicalDevice(state);
    InitCore.destroySurface(state);
    InitCore.destroyInstance(state);
}

pub fn renderFrame(state: *VulkanState, frame_data: []const u32) !void {
    return Rendering.renderFrame(state, frame_data);
}
```

### Step 4: Validation

```bash
zig build                    # Must compile
zig build test               # Must pass (940/950 baseline)
timeout 5 zig-out/bin/RAMBO "tests/data/Bomberman/..." # Must run
```

---

## Side Effects & State Mutations

### VulkanState Mutations

**All functions mutate VulkanState fields:**
- Instance & Surface: `instance`, `surface`
- Device Selection: `physical_device`, `graphics_family`, `present_family`
- Logical Device: `device`, `graphics_queue`, `present_queue`
- Swapchain: `swapchain`, `swapchain_images`, `swapchain_image_views`, `swapchain_image_format`, `swapchain_extent`
- Render Pass: `render_pass`
- Framebuffers: `framebuffers`
- Descriptors: `descriptor_set_layout`, `descriptor_pool`, `descriptor_sets`
- Pipeline: `graphics_pipeline`, `pipeline_layout`
- Commands: `command_pool`, `command_buffers`
- Buffers: `staging_buffer`, `staging_buffer_memory`
- Texture: `texture_image`, `texture_image_memory`, `texture_image_view`, `texture_sampler`
- Sync: `image_available_semaphores`, `render_finished_semaphores`, `in_flight_fences`, `current_frame`

### No Hidden State

**All state is explicit:**
- ✅ Everything stored in VulkanState
- ✅ No global variables
- ✅ No hidden Vulkan object caches
- ✅ Deterministic initialization order

### No Aliasing

**Single ownership:**
- ✅ VulkanState owns all Vulkan objects
- ✅ Functions receive `state: *VulkanState` pointer
- ✅ No subcomponent pointers extracted
- ✅ Clean lifetime management via init/deinit

---

## Risk Assessment

### Low Risk Areas

1. **Instance & Surface** - Minimal dependencies, called once at startup
2. **Device Selection** - Pure query functions, no side effects beyond device selection
3. **Swapchain** - Self-contained, clear dependencies
4. **Render Pass** - Small, well-defined
5. **Framebuffers** - Simple wrapper around swapchain images
6. **Descriptors** - Clear lifecycle, well-isolated
7. **Sync** - Independent, no complex dependencies

### Medium Risk Areas

1. **Pipeline Creation** - Large function (~200 lines), reads shader files
2. **Texture Management** - Multiple interdependent steps (image, view, sampler)
3. **Command Buffers** - Used by multiple other systems (texture uploads, rendering)

### Mitigation Strategies

1. **Preserve Exact Initialization Order** - Maintain errdefer cleanup chains
2. **Test After Each Module** - Run Bomberman ROM to verify rendering works
3. **Keep renderFrame Intact Initially** - Don't split render loop until later
4. **Document Dependencies** - Clear comments about what depends on what

---

## Testing Strategy

### Baseline Validation

**Current Baseline:**
- Build: SUCCESS
- Tests: 940/950 passing
- Bomberman ROM: Runs and displays correctly

### Validation Steps After Extraction

1. **Build Check:**
   ```bash
   zig build
   ```
   Must compile without errors.

2. **Test Suite:**
   ```bash
   zig build test
   ```
   Must maintain 940/950 passing tests.

3. **Functional Test:**
   ```bash
   timeout 5 zig-out/bin/RAMBO "tests/data/Bomberman/..."
   ```
   Must display Vulkan initialization logs and render frames.

4. **Visual Verification:**
   - Window opens
   - NES frame renders correctly
   - No Vulkan validation errors
   - Smooth rendering (60 FPS)

### No Regression Tolerance

**Zero tolerance for:**
- Build failures
- Test regressions
- Vulkan initialization failures
- Rendering errors

**Acceptable:**
- Threading test flakiness (known issue)
- Existing test failures (4 known)

---

## Documentation Updates Needed

1. Update `PHASE-1-PROGRESS.md` with Milestone 1.5 start
2. Create function reference guide for each module
3. Document Vulkan initialization order requirements
4. Add Wayland/Mailbox integration notes
5. Update `PHASE-1-DEVELOPMENT-GUIDE.md` with extraction notes

---

## Next Steps

**After review and approval:**

1. Create `src/video/vulkan/` directory structure
2. Extract functions in dependency order (5 modules)
3. Update VulkanLogic.zig with orchestration code
4. Run full validation suite (build, test, Bomberman)
5. Update documentation
6. Git commit with detailed message

**Questions for user:**
None - structure is clear and straightforward!

---

## Estimated Time

**Phase 1 (5 modules):** 2-3 hours
- Extraction: 1 hour
- Testing: 30 minutes
- Documentation: 1 hour

**Much faster than CPU execution because:**
- Clear function boundaries (no complex control flow)
- No side effect ordering constraints (just init/cleanup)
- Sequential and imperative (easy to understand)
- Natural groupings (Vulkan objects)
