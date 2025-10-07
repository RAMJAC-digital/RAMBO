# Phase 8: Video Subsystem Implementation

**Created:** 2025-10-07
**Status:** 📘 **READY FOR IMPLEMENTATION**
**Estimated Time:** 13-17 hours (1.5-2 days)

---

## 🎯 Objective

Implement Wayland window management and Vulkan rendering to display NES frames from the emulator, completing the critical path to playability.

---

## 📚 Documentation Index

Read documents in this order:

### 1. **[THREAD-SEPARATION-VERIFICATION.md](./THREAD-SEPARATION-VERIFICATION.md)**
- **Purpose:** Proves thread isolation is maintained
- **Read this first:** Verify the architecture guarantees
- **Time:** 15 minutes

### 2. **[API-REFERENCE.md](./API-REFERENCE.md)**
- **Purpose:** Complete API documentation for all modules
- **Read before coding:** Know exact signatures and patterns
- **Time:** 30 minutes

### 3. **[IMPLEMENTATION-GUIDE.md](./IMPLEMENTATION-GUIDE.md)**
- **Purpose:** Step-by-step implementation instructions
- **Use during coding:** Follow phase-by-phase
- **Time:** Reference document (keep open during implementation)

---

## ✅ Prerequisites

**System Requirements:**
- ✅ Wayland compositor running (`$WAYLAND_DISPLAY` set)
- ✅ Vulkan 1.4+ installed (`/usr/lib/libvulkan.so` exists)
- ✅ Shader compilers available (`glslc` or `glslangValidator`)

**Codebase Status:**
- ✅ All 571 tests passing
- ✅ 3-thread architecture working (Main, Emulation, Render)
- ✅ 8 mailboxes implemented and tested
- ✅ Emulation thread producing frames at 60 Hz

**Verification:**
```bash
# Check Wayland
echo $WAYLAND_DISPLAY  # Should output: wayland-1 or similar
test -S "$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY" && echo "✅ Wayland OK"

# Check Vulkan
pkg-config --modversion vulkan  # Should output: 1.4.x
ls /usr/lib/libvulkan.so && echo "✅ Vulkan OK"

# Check shader compiler
which glslc && echo "✅ Shader compiler OK"

# Check tests
cd ~/Development/RAMBO
zig build test  # Should see: 571/571 passing
```

---

## 🏗️ Architecture Summary

### Thread Model

```
Main Thread (Coordinator)
  ├─ Spawns: Emulation Thread (60 Hz timer)
  ├─ Spawns: Render Thread (Wayland + Vulkan)
  └─ Routes: Events between threads via mailboxes

Communication: ONLY via mailboxes (no shared state)
```

### Mailbox Flows

```
Render → Main:    XdgWindowEvent, XdgInputEvent
Main → Emulation: ControllerInput, EmulationCommand
Emulation → Render: FrameMailbox (double-buffered)
```

### Key Guarantee

**Emulation timing is independent of render performance**
- Timer-driven at 60.0988 Hz (NTSC)
- Non-blocking frame posts
- Render can drop frames if slow (doesn't affect emulation)

---

## 📋 Implementation Phases

| Phase | Time | Goal | Test |
|-------|------|------|------|
| **Phase 1** | 3-4h | Wayland window opens | See window on screen |
| **Phase 2** | 4-5h | Vulkan renders solid color | Blue window |
| **Phase 3** | 4-5h | NES frames display | AccuracyCoin visible |
| **Phase 4** | 2-3h | Input + polish | Playable with keyboard |
| **Total** | **13-17h** | **Complete video subsystem** | **All tests pass** |

---

## 🚀 Quick Start

### Step 1: Read Documentation (45 min)

```bash
cd ~/Development/RAMBO/docs/implementation/phase-8-video

# 1. Verify architecture (15 min)
cat THREAD-SEPARATION-VERIFICATION.md

# 2. Study APIs (30 min)
cat API-REFERENCE.md
```

### Step 2: Begin Phase 1 (3-4 hours)

```bash
# Open implementation guide
cat IMPLEMENTATION-GUIDE.md

# Create project structure
mkdir -p ~/Development/RAMBO/src/video/shaders

# Follow Phase 1 steps in IMPLEMENTATION-GUIDE.md
# - Create WaylandState.zig
# - Create WaylandLogic.zig
# - Update RenderThread.zig
# - Test: Window opens
```

### Step 3: Continue Through Phases 2-4

Follow IMPLEMENTATION-GUIDE.md phase by phase.

---

## 🔍 Key Implementation Patterns

### Pattern 1: Wayland Event to Mailbox

```zig
// Wayland listener (render thread)
fn keyboardListener(..., context: *EventHandlerContext) void {
    const event_data = WaylandEvent.EventData{
        .key_press = .{ .keycode = k.key, .modifiers = ... }
    };
    context.mailbox.postEvent(.key_press, event_data) catch {};
}
```

### Pattern 2: Frame Consumption

```zig
// Render loop
if (mailboxes.frame.hasNewFrame()) {  // Lock-free check
    const pixels = mailboxes.frame.consumeFrame();
    if (pixels) |p| {
        try VulkanLogic.uploadTexture(&vulkan, p);
        try VulkanLogic.renderFrame(&vulkan);
    }
}
```

### Pattern 3: Input Routing

```zig
// Main thread
const input_events = mailboxes.xdg_input_event.swapAndGetPendingEvents();
for (input_events) |event| {
    switch (event.data) {
        .key_press => |key| {
            const button = mapKeyToNESButton(key.keycode);
            if (button) |b| mailboxes.controller_input.pressButton(1, b);
        },
        else => {},
    }
}
```

---

## 📊 Development Workflow

### During Each Phase:

1. **Create files** (follow structure in IMPLEMENTATION-GUIDE.md)
2. **Copy proven patterns** (reference zzt-backup)
3. **Test incrementally** (compile after each file)
4. **Verify thread separation** (no cross-thread calls)
5. **Run tests** (`zig build test` should still pass)

### After Each Phase:

1. **Functional test** (window opens, renders, etc.)
2. **Performance check** (60 FPS, no validation errors)
3. **Code review** (matches API-REFERENCE.md)
4. **Commit** (document what was done)

---

## ⚠️ Critical Requirements

### Thread Isolation

- ❌ **NEVER** call EmulationState from render thread
- ❌ **NEVER** call WaylandState from emulation thread
- ✅ **ALWAYS** communicate via mailboxes only

### Wayland Protocol

- ✅ **MUST** respond to `xdg_wm_base.ping` with `pong`
- ✅ **MUST** acknowledge `xdg_surface.configure`
- ✅ **MUST** setup listeners before roundtrip

### Timing Guarantees

- ✅ Emulation timer must be independent
- ✅ Frame post must be non-blocking
- ✅ Render vsync cannot affect emulation

---

## 🎓 Reference Implementation

**Source:** `~/Projects/project_z/zzt-backup/`

**Key Files:**
- `src/lib/core/video/wayland/window_wayland.zig` - Wayland patterns
- `src/lib/core/video/wayland/event_mailbox.zig` - Mailbox pattern
- `src/lib/core/video/vulkan/context.zig` - Vulkan initialization
- `src/bin/zzt_bin.zig:105-115` - Event loop pattern

**Usage:** Copy patterns, adapt to RAMBO's architecture

---

## 🐛 Troubleshooting

### Window Doesn't Open

```bash
# Check Wayland connection
echo $WAYLAND_DISPLAY
ls -la $XDG_RUNTIME_DIR/$WAYLAND_DISPLAY

# Run with verbose logging
WAYLAND_DEBUG=1 zig build run
```

### Vulkan Errors

```bash
# Enable validation layers (Debug build)
# Check for VK_LAYER_KHRONOS_validation

# Common fixes:
# - Missing VkFence reset
# - Wrong queue family index
# - Incorrect synchronization
```

### Frame Drops

```bash
# Check emulation thread timing
# Should see: "FPS: 60.10" in output

# Check mailbox overflow
# Should NOT see: "mailbox overflow" warnings
```

---

## ✅ Completion Criteria

Phase 8 is complete when:

- ✅ Window opens at 512×480
- ✅ NES frames display correctly
- ✅ Keyboard input works (arrow keys, X/Z for A/B)
- ✅ Correct aspect ratio (8:7 pixel aspect)
- ✅ Window resize works
- ✅ 60 FPS stable (vsync)
- ✅ All 571 tests still passing
- ✅ Thread separation maintained
- ✅ No Vulkan validation errors
- ✅ Emulation timing independent of render

---

## 📝 Final Checklist

Before declaring Phase 8 complete:

- [ ] Read all 3 documentation files
- [ ] Verified system prerequisites
- [ ] Completed Phase 1 (window opens)
- [ ] Completed Phase 2 (Vulkan solid color)
- [ ] Completed Phase 3 (NES frames)
- [ ] Completed Phase 4 (input + polish)
- [ ] All tests passing (`zig build test`)
- [ ] Performance targets met (60 FPS)
- [ ] Thread separation verified (code review)
- [ ] AccuracyCoin is playable

---

## 🎮 Expected Result

When complete, you should be able to:

```bash
zig build run
# 1. Window opens showing AccuracyCoin
# 2. Can play with keyboard
# 3. 60 FPS stable
# 4. Can resize window
# 5. All emulation tests still pass
```

**You will have a working, playable NES emulator!**

---

## 📅 Timeline

**Fastest:** 13 hours (experienced, reference-heavy)
**Typical:** 15 hours (careful, test-driven)
**Conservative:** 17 hours (learning, thorough)

**Recommended approach:** 2-3 sessions of 4-6 hours each

---

## 📖 Additional Resources

- **Wayland Book:** https://wayland-book.com/
- **Vulkan Tutorial:** https://vulkan-tutorial.com/
- **zig-wayland:** https://codeberg.org/ifreund/zig-wayland
- **zzt-backup:** ~/Projects/project_z/zzt-backup/ (proven implementation)

---

**Status:** 📘 **DOCUMENTATION COMPLETE - READY TO CODE**

**Last Updated:** 2025-10-07
**Review Date:** Before starting Phase 1

**Next Action:** Read THREAD-SEPARATION-VERIFICATION.md and begin implementation
