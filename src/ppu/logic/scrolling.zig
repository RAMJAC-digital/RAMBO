//! PPU Scroll Register Operations
//!
//! Handles manipulation of the PPU internal registers (v, t, x) for scrolling.
//! These operations update the scroll position during rendering.

const PpuState = @import("../State.zig").PpuState;

/// Increment coarse X scroll (every 8 pixels)
/// Handles horizontal nametable wrapping
pub fn incrementScrollX(state: *PpuState) void {
    if (!state.mask.renderingEnabled()) return;

    // Coarse X is bits 0-4 of v register
    if ((state.internal.v & 0x001F) == 31) {
        // Coarse X = 31, wrap to 0 and switch horizontal nametable
        state.internal.v &= ~@as(u16, 0x001F); // Clear coarse X
        state.internal.v ^= 0x0400; // Switch horizontal nametable
    } else {
        // Increment coarse X
        state.internal.v += 1;
    }
}

/// Increment Y scroll (end of scanline)
/// Handles vertical nametable wrapping
pub fn incrementScrollY(state: *PpuState) void {
    if (!state.mask.renderingEnabled()) return;

    // Fine Y is bits 12-14 of v register
    if ((state.internal.v & 0x7000) != 0x7000) {
        // Increment fine Y
        state.internal.v += 0x1000;
    } else {
        // Fine Y = 7, reset to 0 and increment coarse Y
        state.internal.v &= ~@as(u16, 0x7000); // Clear fine Y

        // Coarse Y is bits 5-9
        var coarse_y = (state.internal.v >> 5) & 0x1F;
        if (coarse_y == 29) {
            // Coarse Y = 29, wrap to 0 and switch vertical nametable
            coarse_y = 0;
            state.internal.v ^= 0x0800; // Switch vertical nametable
        } else if (coarse_y == 31) {
            // Out of bounds, wrap without nametable switch
            coarse_y = 0;
        } else {
            coarse_y += 1;
        }

        // Write coarse Y back to v register
        state.internal.v = (state.internal.v & ~@as(u16, 0x03E0)) | (coarse_y << 5);
    }
}

/// Copy horizontal scroll bits from t to v
/// Called at dot 257 of each visible scanline
pub fn copyScrollX(state: *PpuState) void {
    if (!state.mask.renderingEnabled()) return;

    // Copy bits 0-4 (coarse X) and bit 10 (horizontal nametable)
    state.internal.v = (state.internal.v & 0xFBE0) | (state.internal.t & 0x041F);
}

/// Copy vertical scroll bits from t to v
/// Called at dot 280-304 of pre-render scanline
pub fn copyScrollY(state: *PpuState) void {
    if (!state.mask.renderingEnabled()) return;

    // Copy bits 5-9 (coarse Y), bits 12-14 (fine Y), bit 11 (vertical nametable)
    state.internal.v = (state.internal.v & 0x841F) | (state.internal.t & 0x7BE0);
}
