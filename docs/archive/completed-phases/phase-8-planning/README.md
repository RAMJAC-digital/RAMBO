# Wayland Planning Archive - 2025-10-06

**Status:** ARCHIVED - Superseded by `docs/COMPLETE-ARCHITECTURE-AND-PLAN.md`

---

## Contents

This directory contains **superseded** Wayland/Vulkan planning documents that went through multiple iterations before the final architecture was established.

### Archived Documents

1. **`WAYLAND-DEVELOPMENT-PLAN.md`** (First iteration)
   - **Issue:** Attempted free-running emulation paced by vsync backpressure
   - **Why Wrong:** Breaks speed control, fast-forward, stepping modes
   - **Superseded By:** COMPLETE-ARCHITECTURE-AND-PLAN.md

2. **`WAYLAND-DEVELOPMENT-PLAN-REVISED.md`** (Second iteration)
   - **Issue:** Still had timer-based emulation but correct thread model
   - **Why Incomplete:** Missing libxev primitive clarification
   - **Superseded By:** COMPLETE-ARCHITECTURE-AND-PLAN.md

3. **`WAYLAND-DEVELOPMENT-PLAN-FINAL.md`** (Third iteration)
   - **Issue:** Good structure but lacked library primitive details
   - **Why Incomplete:** Didn't specify std.Thread.Mutex vs libxev primitives
   - **Superseded By:** COMPLETE-ARCHITECTURE-AND-PLAN.md

4. **`video-system.md`** (Original architecture proposal)
   - **Issue:** Proposed 3-thread model critiqued by architecture review
   - **Why Wrong:** Triple-buffering, timer-based vsync, complexity
   - **Superseded By:** COMPLETE-ARCHITECTURE-AND-PLAN.md

### Key Learnings (Preserved)

These iterations helped establish the correct architecture:

**✅ Emulation Must Be Isolated**
- Timer-driven cycle-accurate execution
- Independent of display performance
- Configurable speed (realtime, fast-forward, slow-mo, step)

**✅ Correct Thread Model**
- Exactly 3 threads (Main coordinator, Emulation RT-safe, Render Wayland+Vulkan)
- Each thread has own libxev.Loop where needed
- No shared state except via mailboxes

**✅ Mailbox Pattern**
- Double-buffering (not triple)
- std.Thread.Mutex for synchronization
- std.atomic.Value for lock-free flags
- NO libxev primitives in mailboxes

**✅ libxev Usage**
- Event loops (xev.Loop)
- Timers for emulation pacing (xev.Timer)
- File descriptor monitoring (Wayland socket)
- NOT for mutexes or thread spawning

**✅ Architectural Reviews Matter**
- `archive/video-architecture-review.md` identified critical flaws
- Comparison to zzt-backup prevented bad patterns
- Multiple iterations required to get it right

---

## Current Authoritative Document

**📘 [`../COMPLETE-ARCHITECTURE-AND-PLAN.md`](../COMPLETE-ARCHITECTURE-AND-PLAN.md)**

This document has:
- ✅ Zero outstanding questions
- ✅ Complete library usage specifications
- ✅ All primitives defined (std.Thread.Mutex, std.atomic, libxev.Loop)
- ✅ 8 mailboxes catalogued with synchronization patterns
- ✅ 3-thread architecture with clear responsibilities
- ✅ 5-phase development plan (40-54 hours)
- ✅ State isolation strategy
- ✅ No conflicts, no ambiguity

---

## Why These Were Archived

1. **Superseded:** Final architecture is significantly different
2. **Confusing:** Multiple versions create ambiguity
3. **Incorrect:** First iteration had fundamental flaws
4. **Historical Value:** Preserved to show evolution of design

---

**Archived:** 2025-10-06
**Reason:** Consolidated into COMPLETE-ARCHITECTURE-AND-PLAN.md
**Read Instead:** `docs/COMPLETE-ARCHITECTURE-AND-PLAN.md`
