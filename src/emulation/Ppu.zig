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

// DEBUG: VBlank timing diagnostics
const DEBUG_VBLANK = true;
const DEBUG_SPRITES = false;  // Disable sprite debug to reduce noise

const AnyCartridge = RegistryModule.AnyCartridge;
const PpuState = PpuModule.State.PpuState;
const PpuLogic = PpuModule.Logic;

/// Result flags produced by a single PPU tick
/// These are EVENT signals (edge-triggered), not level signals
pub const TickFlags = struct {
    frame_complete: bool = false,
    rendering_enabled: bool,
    nmi_signal: bool = false,      // Scanline 241, dot 1 - NMI edge detection (VBlank starts)
    vblank_clear: bool = false,    // Scanline 261, dot 1 - VBlank period ends
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
    // TEMP DEBUG: Log scanline 241, dot 1 specifically
    if (scanline == 241 and dot == 1) {
        std.debug.print("[PPU ENTRY] scanline={}, dot={}\n", .{scanline, dot});
    }

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
        if (DEBUG_SPRITES and scanline == 0) {
            var sprite_count: u8 = 0;
            for (0..32) |i| {
                if (state.secondary_oam[i] != 0xFF) {
                    sprite_count += 1;
                }
            }
            std.debug.print("[SPRITE EVAL] Scanline {}, found {} sprites in secondary OAM\n", .{scanline, sprite_count / 4});
        }
    }

    // === Sprite Fetching ===
    if (is_rendering_line and rendering_enabled and dot >= 257 and dot <= 320) {
        PpuLogic.fetchSprites(state, cart, scanline, dot);
    }

    // === Pixel Output ===
    if (is_visible and dot >= 1 and dot <= 256) {
        const pixel_x = dot - 1;
        const pixel_y = scanline;

        const bg_pixel = PpuLogic.getBackgroundPixel(state, pixel_x);
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
                if (DEBUG_SPRITES and !state.status.sprite_0_hit) {
                    std.debug.print("[SPRITE 0 HIT] Detected at scanline={}, pixel_x={}, bg_pixel={}, sprite_pixel={}\n", .{scanline, pixel_x, bg_pixel, sprite_result.pixel});
                }
                state.status.sprite_0_hit = true;
            }
        }

        const color = PpuLogic.getPaletteColor(state, final_palette_index);
        if (framebuffer) |fb| {
            const fb_index = pixel_y * 256 + pixel_x;
            fb[fb_index] = color;
        }
    }

    // === VBlank Flag Management ===
    // Hardware behavior:
    // - VBlank flag SET at scanline 241, dot 1 (PPU cycle 82,181)
    // - VBlank flag CLEARED at scanline 261, dot 1 (PPU cycle 89,001)
    // - Also CLEARED when $2002 is read (handled in PpuLogic.readRegister)

    // Set VBlank flag at start of VBlank period
    if (scanline == 241 and dot == 1) {
        std.debug.print("[DEBUG] At 241.1: vblank_flag={}, about to set\n", .{state.status.vblank});
        if (!state.status.vblank) { // Only set if not already set
            if (DEBUG_VBLANK) {
                std.debug.print("[VBlank] SET at scanline={}, dot={}, nmi_enable={}, flag_before={}, ppu_state={*}\n", .{ scanline, dot, state.ctrl.nmi_enable, state.status.vblank, state });
            }
            state.status.vblank = true;
            std.debug.print("[DEBUG] VBlank flag NOW TRUE\n", .{});
            if (DEBUG_VBLANK) {
                std.debug.print("[VBlank] SET COMPLETE - flag_after={}, ppu_state={*}\n", .{state.status.vblank, state});
            }
            flags.nmi_signal = true; // Signal NMI edge detection to CPU
        } else if (DEBUG_VBLANK) {
            std.debug.print("[VBlank] SKIPPED SET at scanline={}, dot={} (flag already set), ppu_state={*}\n", .{ scanline, dot, state });
        }
    }

    // Clear VBlank and other flags at pre-render scanline
    if (scanline == 261 and dot == 1) {
        if (DEBUG_VBLANK) {
            std.debug.print("[VBlank] CLEAR at scanline={}, dot={} (flag was: {})\n", .{ scanline, dot, state.status.vblank });
        }
        state.status.vblank = false;  // VBlank DOES clear here on hardware
        state.status.sprite_0_hit = false;
        state.status.sprite_overflow = false;
        flags.vblank_clear = true; // Signal end of VBlank period
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
