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
    vblank_ledger: *@import("../emulation/state/VBlankLedger.zig").VBlankLedger,
    current_cycle: u64,
) u8 {
    return registers.readRegister(state, cart, address, vblank_ledger, current_cycle);
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

/// Evaluate sprites for the current scanline
pub inline fn evaluateSprites(state: *PpuState, scanline: u16) void {
    sprites.evaluateSprites(state, scanline);
}
