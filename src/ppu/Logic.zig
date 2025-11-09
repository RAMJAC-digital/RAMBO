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

pub fn init() PpuState {
    return PpuState.init();
}

/// Power-on PPU (system power-on)
/// Hardware requires warm-up period before PPUMASK writes take effect
/// Resets all PPU state to initial values
pub fn power_on(state: *PpuState) void {
    // Preserve external state (set by emulation environment)
    const fb = state.framebuffer;
    const mirror = state.mirroring;

    // Reset to clean power-on state (all fields to defaults)
    state.* = PpuState.init();

    // Restore external state
    state.framebuffer = fb;
    state.mirroring = mirror;
    // warmup_complete = false is already set by init()
}

/// Reset PPU (RESET button pressed)
/// Hardware: RESET preserves RAM (OAM, VRAM, palette) and timing state
/// Only resets registers and clears warmup requirement
///
/// Reference: [PPU Power Up](https://nesdev.org/wiki/PPU_power_up_state)
pub fn reset(state: *PpuState) void {
    // Reset registers
    state.ctrl = .{};
    state.mask = .{};
    state.internal.resetToggle();
    state.internal.x = 0;
    state.internal.v = 0;
    state.internal.t = 0;

    // Reset status flags
    state.status = .{};
    state.vblank.reset();
    state.nmi_line = false;

    // RESET skips warm-up (PPU already initialized)
    state.warmup_complete = true;

    // Reset A12 state
    state.a12_state = false;
}

/// Advance PPU clock (341 dots × 262 scanlines, odd frame skip on rendering)
///
/// Reference: [PPU Frame Timing](https://nesdev.org/wiki/PPU_frame_timing)
pub fn advanceClock(ppu: *PpuState, master_cycles: u64) void {
    ppu.dot += 1;

    // Odd frame skip: pre-render scanline is 1 dot shorter when rendering enabled
    const rendering_enabled = ppu.mask.renderingEnabled();
    if (ppu.scanline == -1 and ppu.dot == 339 and (ppu.frame_count & 1) == 1 and rendering_enabled) {
        ppu.dot = 340;
    }

    if (ppu.dot > 340) {
        ppu.dot = 0;
        ppu.scanline += 1;

        // Hardware: 262 scanlines total (scanlines -1, 0-260)
        if (ppu.scanline > 260) {
            ppu.scanline = -1;
            ppu.frame_count += 1;
        }
    }

    manageVBlank(ppu, ppu.scanline, ppu.dot, master_cycles);
    // Frame boundary detection
    checkFrameComplete(ppu, ppu.scanline, ppu.dot, rendering_enabled);
}

pub fn tickFrame(state: *PpuState) void {
    state.open_bus.decay(state.frame_count);
}

// ============================================================================
// Memory Access (delegate to memory.zig)
// ============================================================================

pub inline fn readVram(state: *PpuState, cart: ?*AnyCartridge, address: u16) u8 {
    return memory.readVram(state, cart, address);
}

pub inline fn writeVram(state: *PpuState, cart: ?*AnyCartridge, address: u16, value: u8) void {
    memory.writeVram(state, cart, address, value);
}

// ============================================================================
// Register I/O (delegate to registers.zig)
// ============================================================================

pub inline fn readRegister(
    state: *PpuState,
    cart: ?*AnyCartridge,
    address: u16,
    master_cycles: u64,
) registers.PpuReadResult {
    return registers.readRegister(state, cart, address, master_cycles);
}

pub inline fn writeRegister(state: *PpuState, cart: ?*AnyCartridge, address: u16, value: u8) void {
    registers.writeRegister(state, cart, address, value);
}

/// Reference: Mesen2 NesPpu.cpp UpdateState()
pub inline fn updatePpuState(state: *PpuState, scanline: i16, dot: u16) void {
    registers.updatePpuState(state, scanline, dot);
}

// ============================================================================
// Scroll Operations (delegate to scrolling.zig)
// ============================================================================

pub inline fn incrementScrollX(state: *PpuState) void {
    scrolling.incrementScrollX(state);
}

pub inline fn incrementScrollY(state: *PpuState) void {
    scrolling.incrementScrollY(state);
}

pub inline fn copyScrollX(state: *PpuState) void {
    scrolling.copyScrollX(state);
}

pub inline fn copyScrollY(state: *PpuState) void {
    scrolling.copyScrollY(state);
}

// ============================================================================
// Background Rendering (delegate to background.zig)
// ============================================================================

pub inline fn fetchBackgroundTile(state: *PpuState, cart: ?*AnyCartridge, dot: u16) void {
    background.fetchBackgroundTile(state, cart, dot);
}

pub inline fn getBackgroundPixel(state: *PpuState, pixel_x: u16) u8 {
    return background.getBackgroundPixel(state, pixel_x);
}

pub inline fn getPaletteColor(state: *PpuState, palette_index: u8) u32 {
    return background.getPaletteColor(state, palette_index);
}

// ============================================================================
// Sprite Rendering (delegate to sprites.zig)
// ============================================================================

pub inline fn getSpritePatternAddress(tile_index: u8, row: u8, bitplane: u1, pattern_table: bool, vertical_flip: bool) u16 {
    return sprites.getSpritePatternAddress(tile_index, row, bitplane, pattern_table, vertical_flip);
}

pub inline fn getSprite16PatternAddress(tile_index: u8, row: u8, bitplane: u1, vertical_flip: bool) u16 {
    return sprites.getSprite16PatternAddress(tile_index, row, bitplane, vertical_flip);
}

pub inline fn fetchSprites(state: *PpuState, cart: ?*AnyCartridge, scanline: i16, dot: u16) void {
    sprites.fetchSprites(state, cart, scanline, dot);
}

pub inline fn reverseBits(byte: u8) u8 {
    return sprites.reverseBits(byte);
}

pub inline fn getSpritePixel(state: *PpuState, pixel_x: u16) SpritePixel {
    return sprites.getSpritePixel(state, pixel_x);
}

pub inline fn evaluateSprites(state: *PpuState, scanline: i16) void {
    sprites.evaluateSprites(state, scanline);
}

pub inline fn initSpriteEvaluation(state: *PpuState) void {
    sprites.initSpriteEvaluation(state);
}

pub inline fn tickSpriteEvaluation(state: *PpuState, scanline: i16, cycle: u16) void {
    sprites.tickSpriteEvaluation(state, scanline, cycle);
}

// ============================================================================
// PPU Component Functions
// ============================================================================

/// Update PPUMASK delay buffer (3-4 dot delay)
/// Hardware behavior: Rendering enable/disable propagates through delay
/// Reference: nesdev.org/wiki/PPU_registers#PPUMASK
fn updateMaskDelay(state: *PpuState) void {
    state.mask_delay_buffer[state.mask_delay_index] = state.mask;
    state.mask_delay_index = @truncate((state.mask_delay_index +% 1) & 3); // Wrap 0-3
}

/// Check and complete PPU warmup
/// Hardware: PPU warmup takes ~29658 CPU cycles after power-on
fn checkWarmup(state: *PpuState, master_cycles: u64) void {
    if (!state.warmup_complete) {
        const cpu_cycles = master_cycles / 3;
        if (cpu_cycles >= 29658) {
            state.warmup_complete = true;

            // Apply buffered PPUMASK write if present
            if (state.warmup_ppumask_buffer) |buffered_value| {
                state.mask = StateModule.PpuMask.fromByte(buffered_value);
                state.warmup_ppumask_buffer = null;
            }
        }
    }
}

/// A12 Edge Detection (for MMC3 IRQ timing)
/// A12 is bit 12 of PPU CHR address bus (from actual pattern table fetches)
/// MMC3 watches for rising edges (0→1) during background and sprite pattern fetches
/// Hardware reference: nesdev.org/wiki/MMC3#IRQ_Specifics
fn tickA12Detection(state: *PpuState, dot: u16, is_rendering_line: bool, rendering_enabled: bool, cart: ?*AnyCartridge) void {
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
            // Notify cartridge mapper directly
            if (cart) |c| c.ppuA12Rising();
        }
    }
}

/// Background rendering pipeline (shifts, fetches, scroll)
/// Hardware-accurate shift timing and tile fetching
/// Reference: https://forums.nesdev.org/viewtopic.php?t=10348
fn tickBackgroundPipeline(state: *PpuState, dot: u16, is_rendering_line: bool, rendering_enabled: bool, is_prerender: bool, cart: ?*AnyCartridge) void {
    if (is_rendering_line and rendering_enabled) {
        // Hardware-accurate shift timing: shift during rendering AND prefetch
        // Per nesdev forums (ulfalizer): "The shifters seem to shift between dots 2...257 and dots 322...337"
        // Dots 2-257: Shift during visible rendering (after pixel output starts at dot 1)
        // Dots 322-337: Shift during prefetch (moves tile 0 from low→high byte for tile 1)
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
}

/// Sprite evaluation and fetching system
/// Handles secondary OAM clearing, sprite evaluation, OAM corruption, and sprite fetching
/// Reference: https://www.nesdev.org/wiki/PPU_sprite_evaluation
fn tickSpriteSystem(state: *PpuState, scanline: i16, dot: u16, is_visible: bool, is_rendering_line: bool, rendering_enabled: bool, cart: ?*AnyCartridge) void {
    // Cycles 1-64: Clear secondary OAM
    if (dot >= 1 and dot <= 64) {
        const clear_index = dot - 1;
        if (clear_index < 32) {
            state.secondary_oam[clear_index] = 0xFF;
            // Secondary OAM address increments on every write (every cycle during clearing)
            // Reference: AccuracyCoin OAM corruption test documentation
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

    // Sprite Fetching (dots 257-320)
    if (is_rendering_line and rendering_enabled and dot >= 257 and dot <= 320) {
        // Hardware behavior: OAMADDR is set to 0 during sprite tile loading
        // Reference: https://www.nesdev.org/wiki/PPU_registers#OAMADDR
        if (dot == 257) {
            state.oam_addr = 0;
        }
        fetchSprites(state, cart, scanline, dot);
    }
}

/// Pixel output to framebuffer (BG+sprite priority, sprite 0 hit)
/// Reference: [PPU Sprite Priority](https://www.nesdev.org/wiki/PPU_sprite_priority)
fn renderPixel(state: *PpuState, scanline: i16, dot: u16, is_visible: bool, framebuffer: ?[]u32) void {
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

            // Sprite 0 hit detection
            // Check if left clipping allows hit: either X >= 8, or clipping disabled for both BG and sprites
            // Use delayed mask for visible rendering decisions (Phase 2D)
            const effective_mask = state.getEffectiveMask();
            const left_clip_allows_hit = pixel_x >= 8 or (effective_mask.show_bg_left and effective_mask.show_sprites_left);

            if (sprite_result.sprite_0 and
                effective_mask.show_bg and
                effective_mask.show_sprites and
                pixel_x < 255 and
                dot >= 2 and
                left_clip_allows_hit)
            {
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
}

/// VBlank flag and NMI line management
/// Reference: [PPU Frame Timing](https://nesdev.org/wiki/PPU_frame_timing)
fn manageVBlank(state: *PpuState, scanline: i16, dot: u16, master_cycles: u64) void {
    // VBlank start (scanline 241 dot 1)
    if (scanline == 241 and dot == 1) {
        const prevent_cycle = state.vblank.prevent_vbl_set_cycle;
        const should_prevent = prevent_cycle != 0 and prevent_cycle == master_cycles;

        state.vblank.vblank_span_active = true;

        if (!should_prevent) {
            state.vblank.vblank_flag = true;
            state.vblank.last_set_cycle = master_cycles;
            state.nmi_line = state.ctrl.nmi_enable;
        }

        state.vblank.prevent_vbl_set_cycle = 0;
    }

    // VBlank end (scanline -1 dot 1, pre-render)
    if (scanline == -1 and dot == 1) {
        state.status.sprite_0_hit = false;
        state.status.sprite_overflow = false;
        state.internal.resetToggle();

        state.vblank.vblank_span_active = false;
        state.vblank.vblank_flag = false;
        state.vblank.last_clear_cycle = master_cycles;

        state.nmi_line = false;
    }
}

/// Frame boundary detection
/// Reference: Mesen2 NesPpu.cpp:1417
fn checkFrameComplete(state: *PpuState, scanline: i16, dot: u16, rendering_enabled: bool) void {
    if (scanline == -1 and dot == 0 and state.frame_count > 0) {
        state.frame_complete = true;

        if (rendering_enabled and !state.rendering_was_enabled) {
            state.rendering_was_enabled = true;
        }

        state.vblank.prevent_vbl_set_cycle = 0;
    }
}

/// OAM corruption deferred updates
/// Reference: Mesen2 NesPpu.cpp Exec() calls UpdateState() at cycle end
fn applyDeferredState(state: *PpuState, scanline: i16, dot: u16) void {
    updatePpuState(state, scanline, dot);
}

// ============================================================================
// PPU Orchestration (main tick function)
// ============================================================================

/// Advance the PPU by one cycle.
/// PPU manages its own timing (scanline/dot) internally.
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
/// Advance the PPU by one cycle, performing rendering and signaling.
/// All state changes and signals are managed internally.
pub fn updatePPU(
    state: *PpuState,
    master_cycles: u64,
    cart: ?*AnyCartridge,
) void {
    // Read timing from PPU state (before advancing)
    const scanline = state.scanline;
    const dot = state.dot;
    const framebuffer = state.framebuffer;

    // Compute derived timing flags
    const is_visible = scanline < 240;
    const is_prerender = scanline == -1;
    const is_rendering_line = is_visible or is_prerender;
    const rendering_enabled = state.mask.renderingEnabled();

    // Check warmup completion (before any rendering)
    checkWarmup(state, master_cycles);

    // Update PPUMASK delay buffer
    updateMaskDelay(state);

    // A12 Edge Detection (MMC3 IRQ timing)
    tickA12Detection(state, dot, is_rendering_line, rendering_enabled, cart);

    // Background rendering pipeline
    tickBackgroundPipeline(state, dot, is_rendering_line, rendering_enabled, is_prerender, cart);

    // Sprite evaluation and fetching system
    tickSpriteSystem(state, scanline, dot, is_visible, is_rendering_line, rendering_enabled, cart);

    // Pixel output to framebuffer
    renderPixel(state, scanline, dot, is_visible, framebuffer);

    // VBlank flag and NMI line management

    // OAM corruption deferred updates
    applyDeferredState(state, scanline, dot);
}

// ============================================================================
// Tests
// ============================================================================

const testing = @import("std").testing;
