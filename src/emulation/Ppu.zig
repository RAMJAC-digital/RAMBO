//! Emulator-facing PPU runtime helpers
//!
//! TIMING MIGRATION: This module has been refactored to remove timing mutation.
//! Timing is now externally controlled by MasterClock in EmulationState.
//! PPU tick is now a pure function that receives timing as read-only parameters.

const std = @import("std");
const Config = @import("../config/Config.zig");
const Cartridge = @import("../cartridge/Cartridge.zig");
const PpuModule = @import("../ppu/Ppu.zig");
const RegistryModule = @import("../cartridge/mappers/registry.zig");

const AnyCartridge = RegistryModule.AnyCartridge;
const PpuState = PpuModule.State.PpuState;
const PpuLogic = PpuModule.Logic;

/// Result flags produced by a single PPU tick
pub const TickFlags = struct {
    frame_complete: bool = false,
    rendering_enabled: bool,
};

/// Advance the PPU by one cycle.
/// Timing is externally controlled - this function receives current scanline/dot
/// as read-only parameters and performs pure state updates.
///
/// Hardware correspondence (nesdev.org):
/// - PPU runs at 5.369318 MHz (NTSC)
/// - 341 dots per scanline (0-340)
/// - 262 scanlines per frame (0-261)
/// - Scanlines 0-239: Visible (240 scanlines)
/// - Scanline 240: Post-render
/// - Scanlines 241-260: VBlank (20 scanlines)
/// - Scanline 261: Pre-render
///
/// Returns tick flags indicating frame boundary and rendering state.
pub fn tick(
    state: *PpuState,
    scanline: u16,
    dot: u16,
    cart: ?*AnyCartridge,
    framebuffer: ?[]u32,
) TickFlags {
    var flags = TickFlags{
        .frame_complete = false,
        .rendering_enabled = state.mask.renderingEnabled(),
    };

    // No timing advancement - timing is externally controlled
    const is_visible = scanline < 240;
    const is_prerender = scanline == 261;
    const is_rendering_line = is_visible or is_prerender;
    const rendering_enabled = state.mask.renderingEnabled();

    // === Background Pipeline ===
    if (is_rendering_line and rendering_enabled) {
        if (dot >= 1 and dot <= 256) {
            state.bg_state.shift();
        }

        if ((dot >= 1 and dot <= 256) or (dot >= 321 and dot <= 336)) {
            PpuLogic.fetchBackgroundTile(state, cart, dot);
        }

        if (dot == 338 or dot == 340) {
            const nt_addr = 0x2000 | (state.internal.v & 0x0FFF);
            _ = PpuLogic.readVram(state, cart, nt_addr);
        }

        if (dot == 256) {
            PpuLogic.incrementScrollY(state);
        }

        if (dot == 257) {
            PpuLogic.copyScrollX(state);
        }

        if (is_prerender and dot >= 280 and dot <= 304) {
            PpuLogic.copyScrollY(state);
        }
    }

    // === Sprite Evaluation ===
    if (dot >= 1 and dot <= 64) {
        const clear_index = dot - 1;
        if (clear_index < 32) {
            state.secondary_oam[clear_index] = 0xFF;
        }
    }

    if (is_visible and rendering_enabled and dot == 65) {
        PpuLogic.evaluateSprites(state, scanline);
    }

    // === Sprite Fetching ===
    if (is_rendering_line and rendering_enabled and dot >= 257 and dot <= 320) {
        PpuLogic.fetchSprites(state, cart, scanline, dot);
    }

    // === Pixel Output ===
    if (is_visible and dot >= 1 and dot <= 256) {
        const pixel_x = dot - 1;
        const pixel_y = scanline;

        const bg_pixel = PpuLogic.getBackgroundPixel(state);
        const sprite_result = PpuLogic.getSpritePixel(state, pixel_x);

        var final_palette_index: u8 = 0;
        if (bg_pixel == 0 and sprite_result.pixel == 0) {
            final_palette_index = 0;
        } else if (bg_pixel == 0 and sprite_result.pixel != 0) {
            final_palette_index = sprite_result.pixel;
        } else if (bg_pixel != 0 and sprite_result.pixel == 0) {
            final_palette_index = bg_pixel;
        } else {
            final_palette_index = if (sprite_result.priority) bg_pixel else sprite_result.pixel;
            if (sprite_result.sprite_0 and pixel_x < 255 and dot >= 2) {
                state.status.sprite_0_hit = true;
            }
        }

        const color = PpuLogic.getPaletteColor(state, final_palette_index);
        if (framebuffer) |fb| {
            const fb_index = pixel_y * 256 + pixel_x;
            fb[fb_index] = color;
        }
    }

    // === VBlank ===
    if (scanline == 241 and dot == 1) {
        state.status.vblank = true;
        if (state.ctrl.nmi_enable) {
            state.nmi_occurred = true;
        }
        // NOTE: Do NOT set frame_complete here! Frame continues through VBlank.
    }

    // === Pre-render clearing ===
    if (scanline == 261 and dot == 1) {
        state.status.vblank = false;
        state.status.sprite_0_hit = false;
        state.status.sprite_overflow = false;
        state.nmi_occurred = false;
    }

    // === Frame Complete ===
    // Frame ends at the last dot of scanline 261 (just before wrapping to scanline 0)
    if (scanline == 261 and dot == 340) {
        flags.frame_complete = true;

        // Note: Diagnostic logging moved to EmulationState where frame number is available
        if (rendering_enabled and !state.rendering_was_enabled) {
            state.rendering_was_enabled = true;
        }
    }

    flags.rendering_enabled = rendering_enabled;
    return flags;
}

