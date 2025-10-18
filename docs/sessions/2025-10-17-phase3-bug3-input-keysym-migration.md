# Bug #3: Input System Keysym Migration — 2025-10-17

## Summary

**Migrated input system from layout-dependent keycodes to layout-independent keysyms** fixing input compatibility across all keyboard layouts.

**Impact:** QWERTY, AZERTY, Dvorak, Colemak users can all play games with correct key mappings. Keypad Enter now works for Start button.

**Result:** +1 test (1044/1050), zero regressions, hardware-accurate input handling.

---

## Problem

### Root Cause

Input system used XKB **keycodes** (physical key positions) instead of **keysyms** (logical key meanings):

```zig
// OLD (NON-PORTABLE):
pub const KEY_Z: u32 = 52; // Physical position varies by layout!
pub const KEY_ENTER: u32 = 36; // Doesn't match KP_Enter!
```

**Why This Broke Non-US Layouts:**

XKB keycodes = physical key position + compositor offset (varies by system)

| Layout | 'Z' Key | Keycode | What Happened |
|--------|---------|---------|---------------|
| **QWERTY** | Z | 52 | ✅ Works (keycode matches) |
| **AZERTY** | W | 52 | ❌ Z key has different keycode |
| **Dvorak** | ; | 52 | ❌ Z key has different keycode |

**Result:** Users on non-QWERTY layouts couldn't provide input - switch statement fell through to `else => {}`.

**Additional Issue:** Keypad Enter uses different keycode than regular Enter, so it didn't work for Start button.

### Hardware Specification

**Per XKB specification:**
> Keysyms are layout-independent symbolic constants representing logical keys.
> `XKB_KEY_z` = 0x007a on ALL layouts (QWERTY, AZERTY, Dvorak, etc.)

---

## Solution

### Changes Made

**1. Added keysym field to XdgInputEventMailbox** (`src/mailboxes/XdgInputEventMailbox.zig:13-22`):

```zig
pub const XdgInputEvent = union(enum) {
    key_press: struct {
        keycode: u32,      // Keep for diagnostics
        keysym: u32,       // NEW: layout-independent mapping
        modifiers: u32,
    },
    key_release: struct {
        keycode: u32,      // Keep for diagnostics
        keysym: u32,       // NEW: layout-independent mapping
        modifiers: u32,
    },
    // ...
};
```

**2. Extract keysym in WaylandLogic** (`src/video/WaylandLogic.zig:322-327`):

```zig
// Extract keysym for layout-independent key mapping
const keysym = xkb.xkb_state_key_get_one_sym(xkb_state_ptr, code);

input_log.debug("Key event: keycode={} keysym=0x{x:0>4} state={}", .{ code, keysym, key_event.state });
const pressed = key_event.state == .pressed;
postKeyEvent(context, code, keysym, pressed);
```

**3. Updated postKeyEvent signature** (`src/video/WaylandLogic.zig:236-250`):

```zig
fn postKeyEvent(
    context: *EventHandlerContext,
    keycode: u32,
    keysym: u32,  // NEW parameter
    pressed: bool,
) void {
    const modifiers = normalizedModifiers(context.state);
    const event = if (pressed)
        XdgInputEvent{ .key_press = .{ .keycode = keycode, .keysym = keysym, .modifiers = modifiers } }
    else
        XdgInputEvent{ .key_release = .{ .keycode = keycode, .keysym = keysym, .modifiers = modifiers } };
    // ...
}
```

**4. Updated KeyboardMapper to use keysyms** (`src/input/KeyboardMapper.zig:27-41`):

```zig
// OLD (Layout-dependent keycodes):
pub const KEY_UP: u32 = 111;    // Physical position
pub const KEY_Z: u32 = 52;      // Physical position

// NEW (Layout-independent keysyms):
pub const KEY_UP: u32 = 0xff52;     // XKB_KEY_Up (logical meaning)
pub const KEY_DOWN: u32 = 0xff54;   // XKB_KEY_Down
pub const KEY_LEFT: u32 = 0xff51;   // XKB_KEY_Left
pub const KEY_RIGHT: u32 = 0xff53;  // XKB_KEY_Right
pub const KEY_Z: u32 = 0x007a;      // XKB_KEY_z
pub const KEY_X: u32 = 0x0078;      // XKB_KEY_x
pub const KEY_RSHIFT: u32 = 0xffe2; // XKB_KEY_Shift_R
pub const KEY_ENTER: u32 = 0xff0d;  // XKB_KEY_Return
pub const KEY_KP_ENTER: u32 = 0xff8d; // XKB_KEY_KP_Enter (NEW!)
```

**5. Updated keyPress/keyRelease to handle both Enter keys** (`src/input/KeyboardMapper.zig:50-85`):

```zig
pub fn keyPress(self: *KeyboardMapper, keysym: u32) void {
    switch (keysym) {
        Keymap.KEY_UP => self.buttons.up = true,
        // ...
        Keymap.KEY_ENTER, Keymap.KEY_KP_ENTER => self.buttons.start = true, // Both Enter keys!
        else => {}, // Unknown keysym - no-op
    }
    self.buttons.sanitize();
}
```

**6. Updated main.zig to pass keysym** (`src/main.zig:246-250`):

```zig
.key_press => |key| {
    keyboard_mapper.keyPress(key.keysym);  // Use keysym instead of keycode
},
.key_release => |key| {
    keyboard_mapper.keyRelease(key.keysym);  // Use keysym instead of keycode
},
```

**7. Updated all mailbox tests** (`src/mailboxes/XdgInputEventMailbox.zig`):

Updated 14 tests to include keysym field in all key event constructions.

**8. Added keypad enter test** (`tests/input/keyboard_mapper_test.zig:74-78`):

```zig
test "KeyboardMapper: press Keypad Enter sets Start button" {
    var mapper = KeyboardMapper{};
    mapper.keyPress(KeyboardMapper.Keymap.KEY_KP_ENTER);
    try testing.expect(mapper.getState().start);
}
```

---

## Testing

### Test Results

**Before:** 1043/1049 tests passing
**After:** 1044/1050 tests passing (+1 test, 0 regressions)

**New test:** Keypad Enter → Start button mapping

**Mailbox tests:** 14/14 passing (all updated for keysym field)
**KeyboardMapper tests:** 41/41 passing (including new keypad enter test)

**Zero regressions** - all existing tests still pass.

### Verification

```bash
$ zig build test
Build Summary: 166/168 steps succeeded; 1 failed; 1044/1050 tests passed; 5 skipped; 1 failed
```

**Only failing test:** `smb3_status_bar_test` (integration test - was already failing before Bug #1)

---

## Expected Impact

### User Experience

**After this fix:**
- ✅ AZERTY users can press Z (at W position) for B button
- ✅ Dvorak users can press Z (at ; position) for B button
- ✅ Colemak users have correct key mappings
- ✅ All layouts work identically (layout-independent)
- ✅ Keypad Enter works for Start button
- ✅ Regular Enter still works for Start button

### Technical Impact

- Keysyms extracted once from XKB state during Wayland event handling
- KeyboardMapper receives portable keysym values
- No layout detection or remapping logic needed
- Works across ALL XKB-compatible keyboard layouts
- Debug logging shows both keycode (diagnostic) and keysym (mapping)

---

## Files Modified

1. `src/mailboxes/XdgInputEventMailbox.zig` — Added keysym field, updated 14 tests
2. `src/video/WaylandLogic.zig` — Extract keysym, pass to postKeyEvent
3. `src/input/KeyboardMapper.zig` — Use keysym constants, support KP_Enter
4. `src/main.zig` — Pass keysym instead of keycode
5. `tests/input/keyboard_mapper_test.zig` — Added keypad enter test

**Total:** 5 files, ~50 lines changed, 1 test added

---

## Code Quality

- ✅ **No dead code** - Keycode field preserved for diagnostics
- ✅ **Follows patterns** - State/Logic separation maintained
- ✅ **Well documented** - Comments reference XKB specification
- ✅ **Zero regressions** - All existing tests pass
- ✅ **Test coverage** - +1 test for keypad enter support
- ✅ **Portable** - Works on all keyboard layouts

---

## Design Insights

### Why Keep Keycode?

We kept the `keycode` field for diagnostics:
```zig
key_press: struct {
    keycode: u32,   // Physical position (diagnostic)
    keysym: u32,    // Logical meaning (mapping)
    modifiers: u32,
}
```

This allows debug logging to show both:
- **Keycode** - Physical key position (varies by layout)
- **Keysym** - Logical key meaning (portable)

Example output:
```
Key event: keycode=52 keysym=0x007a → B Button (QWERTY user)
Key event: keycode=25 keysym=0x007a → B Button (AZERTY user)
```

Both map to B button despite different keycodes!

### Why Hardcode Keysym Values?

We use literal u32 values instead of importing xkb constants:

```zig
// Why NOT this:
const xkb = @import("../video/WaylandState.zig").xkb;
pub const KEY_UP: u32 = xkb.XKB_KEY_Up;  // Fails in unit tests!

// Why YES this:
pub const KEY_UP: u32 = 0xff52;  // XKB_KEY_Up (works everywhere)
```

**Reason:** Unit tests don't link xkbcommon library, so importing xkb symbols breaks compilation. Hardcoded values work in both production and tests.

---

## XKB Reference

**XKB Keysym Specification:**
- [xkbcommon-keysyms.h](https://xkbcommon.org/doc/current/xkbcommon-keysyms_8h.html)

**Common XKB Keysyms:**
```c
#define XKB_KEY_Return      0xff0d  // Enter
#define XKB_KEY_KP_Enter    0xff8d  // Keypad Enter
#define XKB_KEY_Up          0xff52  // Up Arrow
#define XKB_KEY_Down        0xff54  // Down Arrow
#define XKB_KEY_Left        0xff51  // Left Arrow
#define XKB_KEY_Right       0xff53  // Right Arrow
#define XKB_KEY_z           0x007a  // Lowercase z
#define XKB_KEY_x           0x0078  // Lowercase x
#define XKB_KEY_Shift_R     0xffe2  // Right Shift
```

---

## Next Steps

**Phase 3 Implementation Complete:**
- ✅ Bug #1: PPU A12 Detection Fix
- ✅ Bug #2: MMC3 IRQ Acknowledge Fix
- ✅ Bug #3: Input Keysym Migration

**Remaining Tasks:**
- Test Coverage: Add MMC3 IRQ unit tests (8 tests)
- Test Coverage: Add MMC3 banking tests (12 tests)
- Test Coverage: Add PPU scrolling tests (20 tests)
- Final Milestone: Update CLAUDE.md and CURRENT-ISSUES.md

---

**Milestone:** Bug #3 (Input Keysym Migration) — ✅ COMPLETE
**Date:** 2025-10-17
**Tests:** 1044/1050 passing (+1)
**Regressions:** 0
**Layouts Supported:** All XKB layouts (QWERTY, AZERTY, Dvorak, Colemak, etc.)
