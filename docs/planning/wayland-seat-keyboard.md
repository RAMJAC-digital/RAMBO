# Wayland Seat & Keyboard Integration Design

**Status:** In Progress (High Priority)  
**Owner:** TBD (Input/Render team)  
**Last Updated:** 2025-10-14

## 1. Background
- Render thread currently instantiates seat objects but does not install listeners or translate keyboard input into `XdgInputEventMailbox` events.
- `KeyboardMapper` and main-loop plumbing are complete; missing link is Wayland/XKB handling on render thread.
- Accurate modifier tracking is needed for debugger shortcuts and future hotkeys.

## 2. Goals
1. Deliver end-to-end keyboard input from Wayland compositor to controller mailbox with correct key repeat semantics.
2. Maintain accurate modifier state (depressed/latched/locked/group) for future features (e.g., Shift+F1 hotkeys).
3. Handle dynamic seat capability changes (device plug/unplug, compositor restarts) without crashing.
4. Ensure clean resource teardown when seat is removed or render thread shuts down.

## 3. Non-Goals
- Mouse pointer support beyond existing stubs.
- Configurable keybinding UI (future enhancement).
- Text input (wl_text_input, IME integration).
- SDL/X11 backend – Wayland only for now.

## 4. Current State Audit
| Component                             | Status | Notes |
|---------------------------------------|--------|-------|
| `WaylandState.seat` binding           | ✅     | Bound in `registryListener`, no listener attached |
| `WaylandState.keyboard` acquisition   | ❌     | Not requested from seat |
| XKB keymap/key state                  | ❌     | No keymap context or translation |
| `XdgInputEventMailbox` wiring         | ✅     | Mailbox drains correctly on main thread |
| Keyboard modifiers tracking           | ⚠️     | Fields exist on `WaylandState`, but never updated |
| Cleanup on capability change          | ❌     | No seat listener -> cannot respond |

## 5. Implementation Plan
1. **Seat Listener Registration**
   - Call `wl_seat.setListener` after binding.
   - Handle `wl_seat.capabilities` to detect keyboard availability.
   - On capabilities containing `keyboard`, request `wl_seat.getKeyboard`.
   - On removal, destroy keyboard and reset state.

2. **Keyboard Listener & XKB Init**
   - Create `struct KeyboardContext { keymap: *xkb_keymap, state: *xkb_state, context: *xkb_context }`.
   - On `keyboard.keymap`, read keymap fd, instantiate XKB structures.
   - On `keyboard.enter`, store modifiers and focused surface.
   - On `keyboard.leave`, clear key state.
   - On `keyboard.modifiers`, update `WaylandState.mods_*` fields.
   - On `keyboard.key`, translate keycode (Wayland keycode + 8 offset) to XKB keysym and final keycode used by `KeyboardMapper` (evdev code).

3. **Event Posting**
   - Map key press/release to `XdgInputEvent.key_press/key_release` with Wayland keycode (post-translation) and modifiers bitmask.
   - Reuse existing mailbox push; handle overflow by logging once per burst.
   - Confirm main-loop consumer keeps `ControllerInputMailbox.postController1` updates in sync every frame; adjust API if modifier-normalization requires additional data alongside `ButtonState`.

4. **Repeat Handling**
   - Track auto-repeat via `keyboard.repeat_info` (Wayland protocol v4+).
   - Emit repeated presses as additional press events or rely on main loop reading state each frame (preferred: rely on state + repeat flag for debugger?).
   - Document chosen behaviour (likely rely on state; no synthetic repeat events).

5. **Resource Management**
   - Ensure keymap fd is closed after reading.
   - Destroy XKB structures when keyboard is destroyed to prevent leaks.
   - Free listener contexts allocated in `WaylandLogic.init`.

6. **Error Handling & Logging**
   - Gracefully handle missing XKB (log warning, disable keyboard input).
   - Add scoped logger `.wayland_input` for focused diagnostics.

7. **Testing Strategy**
   - Unit tests for helper translation functions (pure Zig).
   - Extend `tests/input/keyboard_mapper_test.zig` (or add new integration tests) to assert `ControllerInputMailbox` receives expected button states when fed synthetic `XdgInputEvent` sequences.
   - Threaded integration smoke test stub (requires Wayland mocking – future). Document manual verification steps (see Section 7). 

## 6. Data Structures & APIs
- `WaylandState`: extend with `keyboard_ctx: ?KeyboardContext` and helper methods `setModifiers`, `resetKeyboard`.
- New helper module `video/WaylandInput.zig`? Optional; can inline in `WaylandLogic.zig` for now.
- Mailbox API unchanged.

## 7. Manual Verification Checklist
1. Launch RAMBO under Sway/GNOME/KDE.
2. Observe log message `Wayland input: keyboard ready (layout: ...)`.
3. Press mapped keys (Z/X/Shift/Enter/Arrow). Confirm debugger logs `Controller1` state updates.
4. Unplug/replug keyboard (if compositor emits capability changes) – no crashes.
5. Close window; ensure no `wl_display` errors and Valgrind shows no fd leaks.

## 8. Open Questions
- Do we need configurable keybindings before public release? — Not required immediately, but keep abstractions flexible so a remapping layer can slot in later without refactoring core input plumbing.
- Should modifier bits be normalized to specific flags for cross-backend parity? — Yes. Normalize modifiers into an internal backend-agnostic bitset and avoid embedding Ctrl/Alt semantics in the mailbox payload until we add explicit shortcut handling.
- Auto-repeat: rely on NES state or surface repeated press events? — Emulator must see explicit state every frame. Continue posting controller state each main-loop iteration to support sub-frame exploitation techniques (see e.g. subframe controller TAS workflows).
- How to handle multiple keyboards (seat aggregates) – treat as combined. — Aggregate multiple physical keyboards for now, but design the plumbing so future multi-controller support can distinguish devices when needed.

## 9. Schedule & Dependencies
- Estimate: 1.5 engineering days + QA.
- Depends on: availability of XKB headers (zig-wayland already exposes), logging infrastructure.
- Target milestone: Phase 8.3 (Input plumbing complete).

## 10. Follow-Up Tasks
- File tracking issue `#TBD` once owner assigned.
- Update `docs/architecture/threading.md` with finalized listener flow.
- Add manual QA script in `docs/testing/input/manual-keyboard-checklist.md` (new).
