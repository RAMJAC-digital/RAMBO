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

/// Advance PPU clock by one cycle
/// Hardware behavior: PPU has its own clock (341 dots × 262 scanlines)
/// Mesen2 reference: NesPpu.cpp Exec() function
///
/// Implements:
/// - Cycle increment (0-340)
/// - Scanline wrap (340→0, scanline++)
/// - Frame wrap (scanline 261→-1, frame++)
/// - Odd frame skip (cycle 339→340 when rendering enabled on odd frames)
///
/// Reference: nesdev.org/wiki/PPU_frame_timing
pub fn advanceClock(ppu: *PpuState, rendering_enabled: bool) void {
    ppu.cycle += 1;

    // Odd frame skip: cycle 339 → 340 (skips cycle 340) when rendering enabled
    // Hardware: On odd frames with rendering enabled, pre-render scanline is 1 cycle shorter
    // Mesen2: if(_scanline == -1 && _cycle == 339 && (_frameCount & 0x01) && rendering)
    if (ppu.scanline == -1 and ppu.cycle == 339 and (ppu.frame_count & 1) == 1 and rendering_enabled) {
        ppu.cycle = 340; // Will wrap to 0 on next check
    }

    // Scanline wrap: cycle 340 → 0 (advance scanline)
    if (ppu.cycle > 340) {
        ppu.cycle = 0;
        ppu.scanline += 1;

        // Frame wrap: scanline 260 → -1 (pre-render, advance frame)
        // Hardware: 262 scanlines total (scanlines -1, 0-260)
        if (ppu.scanline > 260) {
            ppu.scanline = -1; // Back to pre-render line
            ppu.frame_count += 1;
        }
    }
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
/// VBlank Migration (Phase 2): Now requires VBlankLedger
/// Race Condition Fix: Added scanline/dot for read-time VBlank masking
pub inline fn readRegister(
    state: *PpuState,
    cart: ?*AnyCartridge,
    address: u16,
    vblank_ledger: @import("../emulation/VBlankLedger.zig").VBlankLedger,
    scanline: i16,
    dot: u16,
) registers.PpuReadResult {
    return registers.readRegister(state, cart, address, vblank_ledger, scanline, dot);
}

/// Write to PPU register (via CPU memory bus)
pub inline fn writeRegister(state: *PpuState, cart: ?*AnyCartridge, address: u16, value: u8) void {
    registers.writeRegister(state, cart, address, value);
}

/// Update PPU state at cycle end (deferred state transitions)
/// Reference: Mesen2 NesPpu.cpp UpdateState()
pub inline fn updatePpuState(state: *PpuState, scanline: i16, dot: u16) void {
    registers.updatePpuState(state, scanline, dot);
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
pub inline fn fetchSprites(state: *PpuState, cart: ?*AnyCartridge, scanline: i16, dot: u16) void {
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
pub inline fn evaluateSprites(state: *PpuState, scanline: i16) void {
    sprites.evaluateSprites(state, scanline);
}

/// Initialize sprite evaluation for a new scanline
pub inline fn initSpriteEvaluation(state: *PpuState) void {
    sprites.initSpriteEvaluation(state);
}

/// Tick progressive sprite evaluation (called each cycle during dots 65-256)
pub inline fn tickSpriteEvaluation(state: *PpuState, scanline: i16, cycle: u16) void {
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
    scanline: i16,
    dot: u16,
    cart: ?*AnyCartridge,
    framebuffer: ?[]u32,
) TickFlags {
    var flags = TickFlags{
        .frame_complete = false,
        .rendering_enabled = state.mask.renderingEnabled(),
    };

    // === PPUMASK Delay Buffer Advance (Phase 2D) ===
    // Hardware behavior: Rendering enable/disable propagates through 3-4 dot delay
    // Update delay buffer every tick to maintain 3-dot sliding window
    // Reference: nesdev.org/wiki/PPU_registers#PPUMASK
    state.mask_delay_buffer[state.mask_delay_index] = state.mask;
    state.mask_delay_index = @truncate((state.mask_delay_index +% 1) & 3); // Wrap 0-3

    // No timing advancement - timing is externally controlled
    const is_visible = scanline < 240;
    const is_prerender = scanline == -1;
    const is_rendering_line = is_visible or is_prerender;
    // Use immediate mask for register updates/side effects (not delayed)
    const rendering_enabled = state.mask.renderingEnabled();

    // === A12 Edge Detection (for MMC3 IRQ timing) ===
    // A12 is bit 12 of PPU CHR address bus (from actual pattern table fetches)
    // MMC3 watches for rising edges (0→1) during background and sprite pattern fetches
    // Hardware reference: nesdev.org/wiki/MMC3#IRQ_Specifics
    //
    // CRITICAL: A12 comes from CHR address ($0000-$1FFF), NOT from v register ($2000-$3FFF)
    // The chr_address field is updated during pattern fetches (cycles 5-6, 7-8) in
    // background.zig and sprites.zig to track the actual CHR bus address
    //
    // MMC3 A12 Filter:
    // Per nesdev.org, MMC3 has internal filter requiring A12 to be low for ~6–8 PPU cycles
    // before detecting a rising edge. Count low cycles continuously (every PPU dot)
    // using the last CHR address seen; only arm a rising event during fetch cycles.
    if (is_rendering_line and rendering_enabled) {
        // Background: dots 1-256, 321-336
        // Sprite: dots 257-320
        const is_background_fetch = (dot >= 1 and dot <= 256) or (dot >= 321 and dot <= 336);
        const is_sprite_fetch = (dot >= 257 and dot <= 320);
        const is_fetch_cycle = is_background_fetch or is_sprite_fetch;

        // Use chr_address for ALL fetches (background and sprite)
        // chr_address is updated during pattern fetches in background.zig and sprites.zig
        // A12 is bit 12 of the CHR address bus ($0000-$1FFF pattern table space)
        const current_a12 = (state.chr_address & 0x1000) != 0;

        // Determine rising condition before mutating state
        const rising_condition = (!state.a12_state and current_a12 and state.a12_filter_delay >= 6);

        // Update filter delay counter (AFTER computing rising_condition)
        if (!current_a12) {
            // A12 is low - count up filter delay (max 8 PPU cycles)
            if (state.a12_filter_delay < 8) {
                state.a12_filter_delay += 1;
            }
        } else {
            // A12 is high - reset filter (ready for next low period)
            state.a12_filter_delay = 0;
        }

        // Update latched A12 level
        state.a12_state = current_a12;

        // Only signal mapper on fetch cycles (when CHR bus is actively used)
        if (is_fetch_cycle and rising_condition) {
            flags.a12_rising = true;
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
            // Secondary OAM address increments on every write (every cycle during clearing)
            // Reference: AccuracyCoin OAM corruption test documentation (lines 12336-12347)
            state.sprite_state.secondary_oam_addr = @truncate(clear_index);
        }
    }

    // Initialize evaluation at dot 1 (visible scanlines only)
    if (is_visible and rendering_enabled and dot == 1) {
        initSpriteEvaluation(state);
    }

    // OAM Corruption: Process any pending corruption at start of rendering-enabled scanlines
    // Reference: Mesen2 NesPpu.cpp ProcessScanlineFirstCycle()
    if (is_rendering_line and rendering_enabled and dot == 1) {
        registers.processOamCorruption(state);
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
            // Use delayed mask for visible rendering decisions (Phase 2D)
            const effective_mask = state.getEffectiveMask();
            const left_clip_allows_hit = pixel_x >= 8 or (effective_mask.show_bg_left and effective_mask.show_sprites_left);

            if (sprite_result.sprite_0 and
                effective_mask.show_bg and
                effective_mask.show_sprites and
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
            if (fb.len >= 61_440 and pixel_x < 256 and pixel_y >= 0 and pixel_y < 240) {
                const fb_index = @as(u16, @intCast(pixel_y)) * 256 + pixel_x;
                fb[fb_index] = color;
            }
        }
    }

    // === VBlank Flag Management ===
    // Hardware behavior (from nesdev.org + blargg's tests):
    // - VBlank flag SET during SECOND dot of scanline 241 (dot index 1, PPU cycle 82,182)
    // - VBlank flag CLEARED at scanline 261, dot 1 (PPU cycle 89,002)
    // - Also CLEARED when $2002 is read (handled in readRegister)
    //
    // CRITICAL TIMING: PPU sets flag during dot 1, but CPU reads can happen in same cycle
    // Hardware sub-cycle ordering: CPU read executes before PPU flag update in same cycle

    // === VBlank Signal Management ===
    // VBlank Migration (Phase 3): VBlank flag is now managed by VBlankLedger only
    // We only signal the events; ledger handles the actual flag state

    // Signal VBlank start (scanline 241 dot 1)
    if (scanline == 241 and dot == 1) {
        // Signal NMI edge detection to CPU
        // VBlankLedger.recordVBlankSet() will be called in EmulationState
        flags.nmi_signal = true;
    }

    // Clear sprite flags and signal VBlank end (scanline -1 dot 1, pre-render)
    if (scanline == -1 and dot == 1) {
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
    // Frame completes when wrapping back to pre-render scanline (scanline -1, dot 0)
    // Hardware: Frame spans scanlines -1 through 260 (262 total scanlines)
    // Total: 89,342 PPU cycles (262 scanlines × 341 dots, minus 1 for odd frame skip)
    // Guard with frame_count > 0 to avoid triggering on power-on initialization
    // Reference: Mesen2 increments _frameCount at scanline 240 (NesPpu.cpp:1417)
    if (scanline == -1 and dot == 0 and state.frame_count > 0) {
        flags.frame_complete = true;

        // Note: Diagnostic logging moved to EmulationState where frame number is available
        if (rendering_enabled and !state.rendering_was_enabled) {
            state.rendering_was_enabled = true;
        }
    }

    // === Deferred State Update (OAM Corruption) ===
    // Hardware behavior: Register writes set pending flag, actual state changes
    // occur at cycle end. This creates 1-cycle delay matching hardware.
    // Reference: Mesen2 NesPpu.cpp Exec() calls UpdateState() at cycle end
    updatePpuState(state, scanline, dot);

    flags.rendering_enabled = rendering_enabled;
    return flags;
}
