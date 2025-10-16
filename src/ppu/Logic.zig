//! PPU Logic
//!
//! Facade module delegating to specialized PPU logic modules.
//! All functions operate on PPU state with explicit parameters.

const std = @import("std");
const StateModule = @import("State.zig");
const PpuState = StateModule.PpuState;
const SpritePixel = StateModule.SpritePixel;
const AnyCartridge = @import("../cartridge/mappers/registry.zig").AnyCartridge;

// Logic modules
const memory = @import("logic/memory.zig");
const registers = @import("logic/registers.zig");
const scrolling = @import("logic/scrolling.zig");
const background = @import("logic/background.zig");
const sprites = @import("logic/sprites.zig");

pub const PpuReadResult = registers.PpuReadResult;

/// Initialize PPU state to power-on values
pub fn init() PpuState {
    return PpuState.init();
}

/// Reset PPU (RESET button pressed)
/// Some registers are not affected by RESET
/// Note: RESET does NOT trigger the warm-up period (only power-on does)
pub fn reset(state: *PpuState) void {
    state.ctrl = .{};
    state.mask = .{};
    // Status VBlank bit is random at reset
    state.internal.resetToggle();
    state.internal.x = 0;
    state.internal.v = 0;
    state.internal.t = 0;
    // RESET skips the warm-up period (PPU already initialized)
    state.warmup_complete = true;
    // Reset A12 state (will be recalculated on next tick)
    state.a12_state = false;
}

/// Decay open bus value (called once per frame)
pub fn tickFrame(state: *PpuState) void {
    state.open_bus.decay();
}

// ============================================================================
// Memory Access (delegate to memory.zig)
// ============================================================================

/// Read from PPU VRAM address space ($0000-$3FFF)
pub inline fn readVram(state: *PpuState, cart: ?*AnyCartridge, address: u16) u8 {
    return memory.readVram(state, cart, address);
}

/// Write to PPU VRAM address space ($0000-$3FFF)
pub inline fn writeVram(state: *PpuState, cart: ?*AnyCartridge, address: u16, value: u8) void {
    memory.writeVram(state, cart, address, value);
}

// ============================================================================
// Register I/O (delegate to registers.zig)
// ============================================================================

/// Read from PPU register (via CPU memory bus)
/// VBlank Migration (Phase 2): Now requires VBlankLedger and current_cycle
pub inline fn readRegister(
    state: *PpuState,
    cart: ?*AnyCartridge,
    address: u16,
    vblank_ledger: @import("../emulation/VBlankLedger.zig").VBlankLedger,
) registers.PpuReadResult {
    return registers.readRegister(state, cart, address, vblank_ledger);
}

/// Write to PPU register (via CPU memory bus)
pub inline fn writeRegister(state: *PpuState, cart: ?*AnyCartridge, address: u16, value: u8) void {
    registers.writeRegister(state, cart, address, value);
}

// ============================================================================
// Scroll Operations (delegate to scrolling.zig)
// ============================================================================

/// Increment coarse X scroll (every 8 pixels)
pub inline fn incrementScrollX(state: *PpuState) void {
    scrolling.incrementScrollX(state);
}

/// Increment Y scroll (end of scanline)
pub inline fn incrementScrollY(state: *PpuState) void {
    scrolling.incrementScrollY(state);
}

/// Copy horizontal scroll bits from t to v
pub inline fn copyScrollX(state: *PpuState) void {
    scrolling.copyScrollX(state);
}

/// Copy vertical scroll bits from t to v
pub inline fn copyScrollY(state: *PpuState) void {
    scrolling.copyScrollY(state);
}

// ============================================================================
// Background Rendering (delegate to background.zig)
// ============================================================================

/// Fetch background tile data for current cycle
pub inline fn fetchBackgroundTile(state: *PpuState, cart: ?*AnyCartridge, dot: u16) void {
    background.fetchBackgroundTile(state, cart, dot);
}

/// Get background pixel from shift registers
pub inline fn getBackgroundPixel(state: *PpuState, pixel_x: u16) u8 {
    return background.getBackgroundPixel(state, pixel_x);
}

/// Get final pixel color from palette
pub inline fn getPaletteColor(state: *PpuState, palette_index: u8) u32 {
    return background.getPaletteColor(state, palette_index);
}

// ============================================================================
// Sprite Rendering (delegate to sprites.zig)
// ============================================================================

/// Get sprite pattern address for 8×8 sprites
pub inline fn getSpritePatternAddress(tile_index: u8, row: u8, bitplane: u1, pattern_table: bool, vertical_flip: bool) u16 {
    return sprites.getSpritePatternAddress(tile_index, row, bitplane, pattern_table, vertical_flip);
}

/// Get sprite pattern address for 8×16 sprites
pub inline fn getSprite16PatternAddress(tile_index: u8, row: u8, bitplane: u1, vertical_flip: bool) u16 {
    return sprites.getSprite16PatternAddress(tile_index, row, bitplane, vertical_flip);
}

/// Fetch sprite pattern data for visible scanline
pub inline fn fetchSprites(state: *PpuState, cart: ?*AnyCartridge, scanline: u16, dot: u16) void {
    sprites.fetchSprites(state, cart, scanline, dot);
}

/// Reverse bits in a byte (for horizontal sprite flip)
pub inline fn reverseBits(byte: u8) u8 {
    return sprites.reverseBits(byte);
}

/// Get sprite pixel for current position
pub inline fn getSpritePixel(state: *PpuState, pixel_x: u16) SpritePixel {
    return sprites.getSpritePixel(state, pixel_x);
}

/// Evaluate sprites for the current scanline (instant evaluation - legacy)
pub inline fn evaluateSprites(state: *PpuState, scanline: u16) void {
    sprites.evaluateSprites(state, scanline);
}

/// Initialize sprite evaluation for a new scanline
pub inline fn initSpriteEvaluation(state: *PpuState) void {
    sprites.initSpriteEvaluation(state);
}

/// Tick progressive sprite evaluation (called each cycle during dots 65-256)
pub inline fn tickSpriteEvaluation(state: *PpuState, scanline: u16, cycle: u16) void {
    sprites.tickSpriteEvaluation(state, scanline, cycle);
}

// ============================================================================
// PPU Orchestration (main tick function)
// ============================================================================

/// Result flags produced by a single PPU tick
/// These are EVENT signals (edge-triggered), not level signals
pub const TickFlags = struct {
    frame_complete: bool = false,
    rendering_enabled: bool,
    nmi_signal: bool = false,      // Scanline 241, dot 1 - NMI edge detection (VBlank starts)
    vblank_clear: bool = false,    // Scanline 261, dot 1 - VBlank period ends
    a12_rising: bool = false,      // A12 rising edge (0→1) for MMC3 IRQ timing
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

    // === A12 Edge Detection (for MMC3 IRQ timing) ===
    // A12 is bit 12 of PPU address bus (derived from v register during tile fetches)
    // MMC3 watches for rising edges (0→1) during background and sprite pattern fetches
    // Hardware reference: nesdev.org/wiki/MMC3#IRQ_Specifics
    if (is_rendering_line and rendering_enabled) {
        // Check A12 state during tile fetch cycles
        // Background: dots 1-256, 321-336
        // Sprite: dots 257-320
        const is_fetch_cycle = (dot >= 1 and dot <= 256) or (dot >= 257 and dot <= 320) or (dot >= 321 and dot <= 336);

        if (is_fetch_cycle) {
            const current_a12 = (state.internal.v & 0x1000) != 0;

            // Detect rising edge (0→1 transition)
            if (!state.a12_state and current_a12) {
                flags.a12_rising = true;
            }

            state.a12_state = current_a12;
        }
    }

    // === Background Pipeline ===
    if (is_rendering_line and rendering_enabled) {
        // Hardware-accurate shift timing: shift during rendering AND prefetch
        // Per nesdev forums (ulfalizer): "The shifters seem to shift between dots 2...257 and dots 322...337"
        // Dots 2-257: Shift during visible rendering (after pixel output starts at dot 1)
        // Dots 322-337: Shift during prefetch (moves tile 0 from low→high byte for tile 1)
        // Reference: https://forums.nesdev.org/viewtopic.php?t=10348
        if ((dot >= 2 and dot <= 257) or (dot >= 322 and dot <= 337)) {
            state.bg_state.shift();
        }

        // Fetch range includes dots 321-337 for prefetch (tile 0 at 329, tile 1 at 337)
        if ((dot >= 1 and dot <= 256) or (dot >= 321 and dot <= 337)) {
            fetchBackgroundTile(state, cart, dot);
        }

        if (dot == 338 or dot == 340) {
            const nt_addr = 0x2000 | (state.internal.v & 0x0FFF);
            _ = readVram(state, cart, nt_addr);
        }

        if (dot == 256) {
            incrementScrollY(state);
        }

        if (dot == 257) {
            copyScrollX(state);
        }

        if (is_prerender and dot >= 280 and dot <= 304) {
            copyScrollY(state);
        }
    }

    // === Sprite Evaluation ===
    // Cycles 1-64: Clear secondary OAM
    if (dot >= 1 and dot <= 64) {
        const clear_index = dot - 1;
        if (clear_index < 32) {
            state.secondary_oam[clear_index] = 0xFF;
        }
    }

    // Initialize evaluation at dot 1 (visible scanlines only)
    if (is_visible and rendering_enabled and dot == 1) {
        initSpriteEvaluation(state);
    }

    // Cycles 65-256: Progressive sprite evaluation (visible scanlines only)
    if (is_visible and rendering_enabled and dot >= 65 and dot <= 256) {
        tickSpriteEvaluation(state, scanline, dot);
    }

    // === Sprite Fetching ===
    if (is_rendering_line and rendering_enabled and dot >= 257 and dot <= 320) {
        // Hardware behavior: OAMADDR is set to 0 during sprite tile loading
        // Reference: https://www.nesdev.org/wiki/PPU_registers#OAMADDR
        if (dot == 257) {
            state.oam_addr = 0;
        }
        fetchSprites(state, cart, scanline, dot);
    }

    // === Pixel Output ===
    if (is_visible and dot >= 1 and dot <= 256) {
        const pixel_x = dot - 1;
        const pixel_y = scanline;

        const bg_pixel = getBackgroundPixel(state, pixel_x);
        const sprite_result = getSpritePixel(state, pixel_x);

        var final_palette_index: u8 = 0;
        if (bg_pixel == 0 and sprite_result.pixel == 0) {
            final_palette_index = 0;
        } else if (bg_pixel == 0 and sprite_result.pixel != 0) {
            final_palette_index = sprite_result.pixel;
        } else if (bg_pixel != 0 and sprite_result.pixel == 0) {
            final_palette_index = bg_pixel;
        } else {
            final_palette_index = if (sprite_result.priority) bg_pixel else sprite_result.pixel;

            // Sprite 0 hit occurs when:
            // - Both BG and sprite pixels are opaque (checked above: bg_pixel != 0 and sprite_result.pixel != 0)
            // - Rendering is enabled (BOTH BG AND sprite rendering must be on - hardware requirement)
            // - X coordinate is 0-254 (X=255 cannot trigger hit)
            // - Dot is >= 2 (sprite 0 hit timing requirement)
            // - Left-column clipping must allow both pixels to be visible (hardware requirement)
            // - Scanline is 0-239 (visible scanlines only, implicitly enforced by is_visible check)
            // Reference: https://www.nesdev.org/wiki/PPU_sprite_priority

            // Check if left clipping allows hit: either X >= 8, or clipping disabled for both BG and sprites
            const left_clip_allows_hit = pixel_x >= 8 or (state.mask.show_bg_left and state.mask.show_sprites_left);

            if (sprite_result.sprite_0 and
                state.mask.show_bg and
                state.mask.show_sprites and
                pixel_x < 255 and
                dot >= 2 and
                left_clip_allows_hit) {
                state.status.sprite_0_hit = true;
            }
        }

        const color = getPaletteColor(state, final_palette_index);
        if (framebuffer) |fb| {
            // Defensive: validate framebuffer dimensions and pixel coordinates
            // Expected: 256×240 = 61,440 pixels
            if (fb.len >= 61_440 and pixel_x < 256 and pixel_y < 240) {
                const fb_index = pixel_y * 256 + pixel_x;
                fb[fb_index] = color;
            }
        }
    }

    // === VBlank Flag Management ===
    // Hardware behavior:
    // - VBlank flag SET at scanline 241, dot 1 (PPU cycle 82,181)
    // - VBlank flag CLEARED at scanline 261, dot 1 (PPU cycle 89,001)
    // - Also CLEARED when $2002 is read (handled in readRegister)

    // === VBlank Signal Management ===
    // VBlank Migration (Phase 3): VBlank flag is now managed by VBlankLedger only
    // We only signal the events; ledger handles the actual flag state

    // Signal VBlank start (scanline 241 dot 1)
    if (scanline == 241 and dot == 1) {
        // Signal NMI edge detection to CPU
        // VBlankLedger.recordVBlankSet() will be called in EmulationState
        flags.nmi_signal = true;
    }

    // Clear sprite flags and signal VBlank end (scanline 261 dot 1)
    if (scanline == 261 and dot == 1) {
        // Clear sprite flags (these are NOT managed by VBlankLedger)
        state.status.sprite_0_hit = false;
        state.status.sprite_overflow = false;

        // Reset PPU write toggle (w register) - hardware behavior per NESDev spec
        // The write toggle is cleared at the end of VBlank along with sprite flags
        state.internal.resetToggle();

        // Signal end of VBlank period
        // VBlankLedger.recordVBlankSpanEnd() will be called in EmulationState
        flags.vblank_clear = true;
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
