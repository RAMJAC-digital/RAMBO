# Wayland Development Plan - FINAL
## Phase 0: Mailbox Testing First, Then Video Implementation

**Created:** 2025-10-06 (Final Revision)
**Status:** 🟢 **Ready for Implementation**
**Total Time:** 34-46 hours

---

## Critical Architecture Document

**⚠️ REQUIRED READING:** [`docs/MAILBOX-ARCHITECTURE.md`](MAILBOX-ARCHITECTURE.md)

This plan depends on the complete mailbox architecture defined in that document. All communication channels, data flows, and XDG integration are specified there.

---

## Implementation Order (CORRECTED)

### Phase 0: Mailbox Architecture & Testing (8-12 hours) ← START HERE

**Purpose:** Implement and test all mailbox communication before any video/render work

**Why First:**
- Mailboxes are the foundation of all thread communication
- Must verify thread-safety before building on top
- Can test emulation control (speed, pause, reset) without video
- Prevents integration bugs later

**Tasks:**

#### Phase 0.1: Implement New Mailboxes (4-6 hours)

1. **EmulationCommandMailbox** (1-2 hours)
   - File: `src/mailboxes/EmulationCommandMailbox.zig`
   - Ring buffer for lifecycle commands (power, reset, pause, resume)
   - FIFO ordering guarantee
   - Command enum: power_on, reset, pause, resume, save_state, load_state, shutdown

2. **SpeedControlMailbox** (1-2 hours)
   - File: `src/mailboxes/SpeedControlMailbox.zig`
   - Atomic swap for speed configuration
   - Config: mode, timing (NTSC/PAL), speed_multiplier, hard_sync
   - Latest-value-wins semantics

3. **XdgInputEventMailbox** (1 hour)
   - File: `src/mailboxes/XdgInputEventMailbox.zig`
   - Event queue for keyboard/mouse from Wayland seat
   - Events: key_press, key_release, mouse_move, mouse_button
   - Batch processing (swap and drain)

4. **Rename WaylandEventMailbox** (30 min)
   - Rename: `WaylandEventMailbox.zig` → `XdgWindowEventMailbox.zig`
   - Clarifies purpose (window events only, not input)
   - Update references in Mailboxes.zig

5. **Status Mailboxes** (1-2 hours)
   - `EmulationStatusMailbox.zig`: FPS, frame count, errors
   - `RenderStatusMailbox.zig`: Display FPS, Vulkan status
   - Atomic status updates

6. **Enhance FrameMailbox** (1 hour)
   - Add `has_new_frame: std.atomic.Value(bool)`
   - Implement `hasNewFrame()` (lock-free check)
   - Implement `postFrame()` (sets flag on swap)
   - Implement `consumeFrame()` (clears flag, returns buffer)

7. **Update Mailboxes Container** (30 min)
   - File: `src/mailboxes/Mailboxes.zig`
   - Add all new mailboxes
   - Update init/deinit
   - Document ownership and data flow

**Deliverable:** All 8 mailboxes implemented

#### Phase 0.2: Mailbox Testing (4-6 hours)

1. **Unit Tests** (2-3 hours)
   - Test isolation (no cross-contamination)
   - Test each mailbox API
   - Edge cases (empty, full, overflow)
   - Files: `tests/mailboxes/*_test.zig`

2. **Integration Tests** (2-3 hours)
   - Controller input flow (XDG input → Main → Controller mailbox → Emulation)
   - Command flow (Main → EmulationCommand → Emulation executes)
   - Frame flow (Emulation → FrameMailbox → Render)
   - Speed control flow (Main → SpeedControl → Emulation timing)

3. **Multi-Threaded Stress Tests** (1 hour)
   - Spawn 3 threads posting/consuming simultaneously
   - Run 1000+ iterations
   - Verify no deadlocks, no race conditions
   - Verify data integrity

**Deliverable:** Comprehensive test suite, all tests passing

#### Phase 0.3: Update Existing Code (2-3 hours)

1. **Update main.zig** (1-2 hours)
   - Initialize all new mailboxes
   - Add command processing loop
   - Add speed control updates
   - Prepare for render thread spawn (still commented out)

2. **Update Emulation Thread** (1 hour)
   - Poll EmulationCommandMailbox
   - Poll SpeedControlMailbox
   - Handle commands (pause, reset, etc.)
   - Update FrameMailbox usage (use new API)

3. **Fix Existing Tests** (30 min)
   - Update any tests broken by mailbox changes
   - Verify all 571 tests still pass

**Deliverable:** Mailbox architecture integrated, all tests passing

**Phase 0 Success Criteria:**
- ✅ All 8 mailboxes implemented with clear names
- ✅ Each mailbox has unit tests
- ✅ Multi-threaded stress tests pass (1000+ iterations)
- ✅ No deadlocks, no race conditions
- ✅ All 571 existing tests still pass
- ✅ Documentation complete
- ✅ Can test emulation control without video

---

### Phase 1: SpeedController Implementation (6-8 hours)

**Purpose:** Implement comprehensive emulation speed control

**Prerequisites:** Phase 0 complete (SpeedControlMailbox exists)

**Tasks:**

#### Phase 1.1: SpeedController Module (4-5 hours)

1. **Create SpeedController** (3-4 hours)
   - File: `src/emulation/SpeedController.zig`
   - Implement all speed modes (realtime, fast_forward, slow_motion, paused, stepping)
   - Wall time sync with catchup/drop logic
   - PAL/NTSC timing support
   - Hard sync enable/disable

2. **Integrate with Emulation Thread** (1 hour)
   - Create SpeedController in emulation thread
   - Call `shouldTick()` in timer callback
   - Handle wait/proceed/skip decisions
   - Update timer duration based on mode

3. **Debugger Integration** (1 hour)
   - Connect SpeedController with existing Debugger
   - Stepping mode delegates to debugger
   - Debugger step commands work with speed control

**Deliverable:** Full speed control system operational

#### Phase 1.2: Testing & Validation (2-3 hours)

1. **Speed Mode Tests** (1-2 hours)
   - Test real-time mode (60.0988 Hz NTSC)
   - Test fast-forward (2×, 4×, unlimited)
   - Test slow motion (0.5×, 0.25×)
   - Test paused mode
   - Test PAL/NTSC switching

2. **Wall Time Sync Tests** (1 hour)
   - Test hard sync catchup
   - Test frame drop on overload
   - Test timing stability (no drift over 60 seconds)

3. **Integration Tests** (30 min)
   - Test speed control via SpeedControlMailbox
   - Test debugger stepping
   - Test mode transitions

**Deliverable:** Speed control fully tested and validated

**Phase 1 Success Criteria:**
- ✅ SpeedController supports all modes
- ✅ Hard sync to wall time works (no drift)
- ✅ Debugger integration functional
- ✅ Can test emulation at various speeds without video
- ✅ All tests pass

---

### Phase 2: Wayland Window & XDG Events (8-10 hours)

**Purpose:** Implement Wayland connection and XDG protocol handling

**Prerequisites:** Phase 0 complete (XdgWindowEventMailbox, XdgInputEventMailbox exist)

**Tasks:**

#### Phase 2.1: Wayland State Module (4-5 hours)

1. **Create WaylandState** (3-4 hours)
   - File: `src/video/WaylandState.zig`
   - Pure state struct (no logic)
   - Fields: display, registry, compositor, xdg_wm_base, seat, surface, xdg_surface, xdg_toplevel, keyboard
   - Isolation: NO emulation state references

2. **Create WaylandLogic** (1 hour)
   - File: `src/video/WaylandLogic.zig`
   - Pure functions for Wayland operations
   - `connect()`, `bindProtocols()`, `createSurface()`, `dispatch()`
   - State/Logic separation pattern

3. **Create Video Module** (30 min)
   - File: `src/video/Video.zig`
   - Module re-exports (like Cpu.zig, Ppu.zig, Bus.zig)

**Deliverable:** Wayland state module following project patterns

#### Phase 2.2: XDG Protocol Integration (2-3 hours)

1. **XDG Surface Callbacks** (1 hour)
   - Configure callback
   - Close callback
   - Resize callback
   - Post to XdgWindowEventMailbox

2. **Input Callbacks** (1-2 hours)
   - Keyboard key press/release
   - Mouse move/button
   - Post to XdgInputEventMailbox

3. **Event Dispatch** (1 hour)
   - libxev fd monitoring for Wayland socket
   - Non-blocking dispatch in render loop
   - Flush requests after each iteration

**Deliverable:** Wayland window opens, events flow to mailboxes

#### Phase 2.3: Main Thread Event Processing (2 hours)

1. **Window Event Router** (1 hour)
   - Process XdgWindowEventMailbox in main thread
   - Handle resize, close, focus
   - Update running flag on close

2. **Input Event Router** (1 hour)
   - Process XdgInputEventMailbox in main thread
   - Map keys to NES buttons → ControllerInputMailbox
   - Map hotkeys to commands → EmulationCommandMailbox
   - Map hotkeys to speed → SpeedControlMailbox

**Deliverable:** Complete event routing

**Phase 2 Success Criteria:**
- ✅ Wayland window opens at 800×600
- ✅ Window title shows "RAMBO NES Emulator"
- ✅ Window events posted to XdgWindowEventMailbox
- ✅ Input events posted to XdgInputEventMailbox
- ✅ Main thread routes events correctly
- ✅ Can close window cleanly

---

### Phase 3: Vulkan Renderer (10-12 hours)

**Purpose:** Implement Vulkan rendering backend

**Prerequisites:** Phase 0 (FrameMailbox), Phase 2 (WaylandState)

**Tasks:**

#### Phase 3.1: Vulkan State Module (5-6 hours)

1. **Create VulkanState** (4-5 hours)
   - File: `src/video/VulkanState.zig`
   - Pure state struct
   - Fields: instance, physical_device, device, surface, swapchain, render_pass, pipeline, texture, etc.
   - Isolation: No emulation references

2. **Create VulkanLogic** (1 hour)
   - File: `src/video/VulkanLogic.zig`
   - Pure functions for Vulkan operations
   - `initInstance()`, `createDevice()`, `createSwapchain()`, etc.

**Deliverable:** Vulkan state module

#### Phase 3.2: Vulkan Initialization (3-4 hours)

1. **Instance & Device** (1-2 hours)
   - Create Vulkan instance
   - Select physical device (GPU)
   - Create logical device and queues
   - Create Wayland surface

2. **Swapchain** (1 hour)
   - Create swapchain with FIFO present mode (vsync)
   - Image views
   - Framebuffers

3. **Render Pass & Pipeline** (1-2 hours)
   - Create render pass
   - Compile shaders (fullscreen quad + texture sample)
   - Create graphics pipeline
   - Create descriptor sets for texture

**Deliverable:** Vulkan renderer initialized

#### Phase 3.3: Texture Upload & Rendering (2-3 hours)

1. **Texture Upload** (1-2 hours)
   - Create staging buffer
   - Upload from FrameMailbox (256×240 RGBA)
   - Transition image layouts
   - Copy to GPU texture

2. **Render Loop** (1 hour)
   - Acquire swapchain image
   - Begin/end render pass
   - Draw fullscreen quad
   - Present with vsync

3. **Swapchain Recreation** (1 hour)
   - Handle window resize
   - Recreate swapchain on resize event
   - Coalesce rapid resizes

**Deliverable:** Vulkan renders frames to window

**Phase 3 Success Criteria:**
- ✅ Vulkan instance and device created
- ✅ Swapchain with vsync (FIFO mode)
- ✅ Texture upload from FrameMailbox works
- ✅ Fullscreen quad renders
- ✅ Window resize handled gracefully

---

### Phase 4: Render Thread Integration (4-6 hours)

**Purpose:** Spawn render thread and integrate all components

**Prerequisites:** All previous phases complete

**Tasks:**

#### Phase 4.1: Render Thread Function (2-3 hours)

1. **Create Render Thread** (1-2 hours)
   - File: Update `src/main.zig`
   - `renderThreadFn()` implementation
   - Initialize Wayland and Vulkan
   - Own libxev loop for Wayland fd

2. **Frame Consumption** (1 hour)
   - Poll FrameMailbox.hasNewFrame() (lock-free)
   - consumeFrame() when available
   - Upload to Vulkan texture
   - Present with vsync

3. **Event Posting** (30 min)
   - Post window events to XdgWindowEventMailbox
   - Post input events to XdgInputEventMailbox
   - Update RenderStatusMailbox

**Deliverable:** Render thread fully functional

#### Phase 4.2: Three-Thread Coordination (1-2 hours)

1. **Main Thread Updates** (1 hour)
   - Spawn render thread
   - Process mailboxes from render thread
   - Coordinate shutdown (join all threads)

2. **Shutdown Handling** (1 hour)
   - Clean shutdown on window close
   - Join threads in correct order
   - Cleanup Vulkan resources
   - Close Wayland connection

**Deliverable:** Three threads coordinate correctly

#### Phase 4.3: Full Pipeline Testing (1-2 hours)

1. **End-to-End Test** (1 hour)
   - Run AccuracyCoin.nes
   - Verify visual output correct
   - Verify background tiles render
   - Verify sprites render
   - Verify controller input works

2. **Performance Validation** (30 min)
   - Measure emulation FPS (should match target)
   - Measure display FPS (should be 60 Hz with vsync)
   - Verify independence (emulation at 240 FPS, display at 60 FPS in fast-forward)

3. **Edge Cases** (30 min)
   - Test window minimize
   - Test rapid resize
   - Test focus loss
   - Test fast-forward overflow

**Deliverable:** Full system working end-to-end

**Phase 4 Success Criteria:**
- ✅ Three threads running (Main, Emulation, Render)
- ✅ AccuracyCoin displays correctly
- ✅ Controller input works
- ✅ Speed control works (can fast-forward, slow-mo, pause)
- ✅ Window events handled correctly
- ✅ Clean shutdown on window close

---

### Phase 5: Polish & Production Features (4-6 hours)

**Purpose:** Final touches for production readiness

**Tasks:**

#### Phase 5.1: Hotkey System (2 hours)

1. **Define Hotkeys** (1 hour)
   - Tab: Fast forward (hold)
   - Space: Pause/resume
   - F: Frame advance (when paused)
   - R: Reset
   - +/-: Adjust speed multiplier
   - F11: Fullscreen toggle

2. **Implement Mapping** (1 hour)
   - In main thread input event processing
   - Map keys to mailbox posts
   - Handle hold vs press

**Deliverable:** Hotkeys functional

#### Phase 5.2: Status Overlay (1-2 hours)

1. **Terminal Output** (30 min)
   - FPS counter in terminal
   - Speed mode indicator
   - Frame count

2. **Future: On-Screen Overlay** (1-2 hours)
   - Simple text rendering in Vulkan
   - Display FPS, speed, mode
   - Toggle with hotkey

**Deliverable:** Status information visible

#### Phase 5.3: Aspect Ratio & Scaling (1-2 hours)

1. **Aspect Ratio Correction** (1 hour)
   - NES 8:7 pixel aspect calculation
   - Letterboxing for non-matching windows
   - Update viewport on resize

2. **Integer Scaling Option** (1 hour)
   - Optional integer-only scaling (2×, 3×, 4×)
   - Crisp pixels for pixel-perfect display

**Deliverable:** Proper aspect ratio and scaling

**Phase 5 Success Criteria:**
- ✅ All hotkeys work
- ✅ Status information displays
- ✅ Aspect ratio correct (8:7 pixel aspect)
- ✅ Scaling options available
- ✅ Production-ready user experience

---

## Total Timeline

| Phase | Description | Hours |
|-------|-------------|-------|
| **Phase 0** | Mailbox Architecture & Testing | 8-12 |
| **Phase 1** | SpeedController Implementation | 6-8 |
| **Phase 2** | Wayland Window & XDG Events | 8-10 |
| **Phase 3** | Vulkan Renderer | 10-12 |
| **Phase 4** | Render Thread Integration | 4-6 |
| **Phase 5** | Polish & Production Features | 4-6 |
| **TOTAL** | | **40-54 hours** |

**Revised Estimate:** 40-54 hours (5-7 days full-time)

---

## Communication Flow Summary

(See [`MAILBOX-ARCHITECTURE.md`](MAILBOX-ARCHITECTURE.md) for complete details)

### Emulation Input (Main → Emulation)
- **ControllerInputMailbox** ✅ EXISTS: NES button states
- **EmulationCommandMailbox** 🆕 NEW: Lifecycle commands (power, reset, pause)
- **SpeedControlMailbox** 🆕 NEW: Speed/timing configuration

### Emulation Output (Emulation → Render/Main)
- **FrameMailbox** ✅ EXISTS (enhanced): Video frames
- **EmulationStatusMailbox** 🆕 NEW: Status and statistics

### Render Thread (Render → Main)
- **XdgWindowEventMailbox** ✅ EXISTS (renamed): Window events
- **XdgInputEventMailbox** 🆕 NEW: Keyboard/mouse input
- **RenderStatusMailbox** 🆕 NEW: Render status

### XDG Communication Isolation

**ONLY Render Thread talks to XDG/Wayland:**
- Initializes Wayland connection
- Binds XDG protocols (xdg_wm_base, wl_seat, wl_compositor)
- Registers callbacks
- Dispatches events
- Posts to mailboxes

**Main Thread:**
- Receives events via mailboxes
- Routes to appropriate destinations
- Never touches Wayland directly

**Emulation Thread:**
- Completely isolated
- Only knows about mailboxes
- No XDG/Wayland knowledge

---

## Key Architectural Decisions

1. **✅ Three Threads:** Main coordinator, Emulation (timer-driven), Render (Wayland + Vulkan)
2. **✅ Phase 0 First:** Test mailbox architecture before building on it
3. **✅ Clear Mailbox Names:** Each mailbox has descriptive, unambiguous name
4. **✅ XDG Isolation:** Only render thread touches Wayland/XDG
5. **✅ Separate Input Channels:** Window events ≠ Input events ≠ Controller input
6. **✅ Lifecycle Commands:** Dedicated EmulationCommandMailbox for power/reset
7. **✅ Speed Control:** Independent SpeedController with mailbox-based config
8. **✅ State/Logic Separation:** WaylandState/Logic, VulkanState/Logic (project pattern)
9. **✅ Lock-Free Where Possible:** FrameMailbox.hasNewFrame(), status checks
10. **✅ Testing First:** Comprehensive test suite before integration

---

## Success Criteria - Full Project

- ✅ All 8 mailboxes implemented and tested
- ✅ Three threads running correctly
- ✅ Emulation isolated with full speed control
- ✅ Wayland window opens and handles events
- ✅ Vulkan renders frames with vsync
- ✅ Controller input works
- ✅ Can play AccuracyCoin with visual output
- ✅ Can fast-forward, pause, reset, step
- ✅ Window resize works gracefully
- ✅ Clean shutdown
- ✅ All 571+ tests pass
- ✅ Production-ready user experience

---

**Status:** 🟢 **Ready for Phase 0 Implementation**
**Next:** Begin Phase 0.1 - Implement new mailboxes
