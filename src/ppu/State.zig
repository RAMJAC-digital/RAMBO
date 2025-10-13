//! PPU State
//!
//! This module defines the pure data structures for the PPU state.
//! Following the hybrid architecture pattern: State contains data + convenience methods.

const std = @import("std");
const Cartridge = @import("../cartridge/Cartridge.zig");
const Mirroring = Cartridge.Mirroring;
const NromCart = Cartridge.NromCart;

/// PPU Control Register ($2000)
/// VPHB SINN
/// |||| ||||
/// |||| ||++- Base nametable address (0=$2000, 1=$2400, 2=$2800, 3=$2C00)
/// |||| |+--- VRAM address increment (0: add 1 going across, 1: add 32 going down)
/// |||| +---- Sprite pattern table address (0: $0000, 1: $1000)
/// |||+------ Background pattern table address (0: $0000, 1: $1000)
/// ||+------- Sprite size (0: 8x8, 1: 8x16)
/// |+-------- PPU master/slave select (0: read backdrop from EXT, 1: output color on EXT)
/// +--------- Generate NMI at start of VBlank (0: off, 1: on)
pub const PpuCtrl = packed struct(u8) {
    nametable_x: bool = false, // Bit 0
    nametable_y: bool = false, // Bit 1
    vram_increment: bool = false, // Bit 2: 0=+1, 1=+32
    sprite_pattern: bool = false, // Bit 3: 0=$0000, 1=$1000
    bg_pattern: bool = false, // Bit 4: 0=$0000, 1=$1000
    sprite_size: bool = false, // Bit 5: 0=8x8, 1=8x16
    master_slave: bool = false, // Bit 6
    nmi_enable: bool = false, // Bit 7

    /// Convert to byte representation
    pub fn toByte(self: PpuCtrl) u8 {
        return @bitCast(self);
    }

    /// Create from byte
    pub fn fromByte(byte: u8) PpuCtrl {
        return @bitCast(byte);
    }

    /// Get base nametable address
    pub fn nametableAddress(self: PpuCtrl) u16 {
        const x: u16 = if (self.nametable_x) 1 else 0;
        const y: u16 = if (self.nametable_y) 1 else 0;
        return 0x2000 + (x * 0x400) + (y * 0x800);
    }

    /// Get VRAM increment amount
    pub fn vramIncrementAmount(self: PpuCtrl) u16 {
        return if (self.vram_increment) 32 else 1;
    }
};

/// PPU Mask Register ($2001)
/// BGRs bMmG
/// |||| ||||
/// |||| |||+- Greyscale (0: normal, 1: greyscale)
/// |||| ||+-- Show background in leftmost 8 pixels (0: hide, 1: show)
/// |||| |+--- Show sprites in leftmost 8 pixels (0: hide, 1: show)
/// |||| +---- Show background (0: hide, 1: show)
/// |||+------ Show sprites (0: hide, 1: show)
/// ||+------- Emphasize red
/// |+-------- Emphasize green
/// +--------- Emphasize blue
pub const PpuMask = packed struct(u8) {
    greyscale: bool = false, // Bit 0
    show_bg_left: bool = false, // Bit 1
    show_sprites_left: bool = false, // Bit 2
    show_bg: bool = false, // Bit 3
    show_sprites: bool = false, // Bit 4
    emphasize_red: bool = false, // Bit 5
    emphasize_green: bool = false, // Bit 6
    emphasize_blue: bool = false, // Bit 7

    /// Convert to byte representation
    pub fn toByte(self: PpuMask) u8 {
        return @bitCast(self);
    }

    /// Create from byte
    pub fn fromByte(byte: u8) PpuMask {
        return @bitCast(byte);
    }

    /// Check if rendering is enabled (either BG or sprites)
    pub fn renderingEnabled(self: PpuMask) bool {
        return self.show_bg or self.show_sprites;
    }
};

/// PPU Status Register ($2002)
/// VSO- ----
/// |||| ||||
/// |||+-++++- Open bus (returns PPU data bus latch)
/// ||+------- Sprite overflow flag
/// |+-------- Sprite 0 hit flag
/// +--------- VBlank flag (REMOVED - now managed by VBlankLedger)
///
/// VBlank Migration (Phase 4): The vblank field has been removed.
/// VBlank flag state is now queried from VBlankLedger.isReadableFlagSet()
/// This struct only contains sprite-related status flags.
pub const PpuStatus = packed struct(u8) {
    open_bus: u5 = 0, // Bits 0-4: Open bus
    sprite_overflow: bool = false, // Bit 5
    sprite_0_hit: bool = false, // Bit 6
    _unused: bool = false, // Bit 7: Unused (VBlank flag moved to VBlankLedger)

    /// Convert to byte representation
    /// Open bus bits come from PPU data bus latch
    /// NOTE: VBlank flag is NOT included - use buildStatusByte() in registers.zig
    pub fn toByte(self: PpuStatus, data_bus: u8) u8 {
        var result: u8 = @bitCast(self);
        // Replace open bus bits with data bus latch
        result = (result & 0xE0) | (data_bus & 0x1F);
        return result;
    }

    /// Create from byte (only top 3 bits matter, rest is open bus)
    pub fn fromByte(byte: u8) PpuStatus {
        return .{
            .open_bus = 0,
            .sprite_overflow = (byte & 0x20) != 0,
            .sprite_0_hit = (byte & 0x40) != 0,
        };
    }
};

/// PPU Open Bus (Data Bus Latch)
/// The PPU has an internal 8-bit data bus that acts as a dynamic latch.
/// Any write to a PPU register fills this latch.
/// Reads from "write-only" registers return the current latch value.
pub const OpenBus = struct {
    /// Current value on the data bus
    value: u8 = 0,

    /// Decay timer (in frames)
    /// Open bus values decay to 0 after ~1 second of no access
    decay_timer: u16 = 0,

    /// Update the data bus latch (called on any PPU write)
    pub fn write(self: *OpenBus, value: u8) void {
        self.value = value;
        self.decay_timer = 60; // Reset decay timer (60 frames = 1 second)
    }

    /// Read the data bus latch (called on reads from write-only registers)
    pub fn read(self: *const OpenBus) u8 {
        return self.value;
    }

    /// Decay the open bus value (called once per frame)
    pub fn decay(self: *OpenBus) void {
        if (self.decay_timer > 0) {
            self.decay_timer -= 1;
        } else {
            // Decay to 0 after timeout
            self.value = 0;
        }
    }
};

/// PPU Internal Registers
pub const InternalRegisters = struct {
    /// Current VRAM address (v register)
    /// yyy NN YYYYY XXXXX
    /// ||| || ||||| +++++- Coarse X scroll
    /// ||| || +++++------- Coarse Y scroll
    /// ||| ++------------- Nametable select
    /// +++---------------- Fine Y scroll
    v: u16 = 0,

    /// Temporary VRAM address (t register)
    /// Same format as v, used during rendering
    t: u16 = 0,

    /// Fine X scroll (x register, 3 bits)
    /// Separate from v/t for horizontal fine scrolling
    x: u3 = 0,

    /// Write toggle (w register)
    /// 0 = first write, 1 = second write
    /// Used for $2005 and $2006 which require two writes
    w: bool = false,

    /// PPUDATA read buffer
    /// VRAM reads are buffered - reading returns previous buffer value
    /// Buffer is updated with current read on each access
    read_buffer: u8 = 0,

    /// Reset write toggle to first write
    pub fn resetToggle(self: *InternalRegisters) void {
        self.w = false;
    }
};

/// Result from sprite pixel lookup
/// Used by sprite rendering logic to communicate pixel data
pub const SpritePixel = struct {
    pixel: u8,
    priority: bool,
    sprite_0: bool,
};

/// Sprite rendering state
/// Contains shift registers and latches for sprite rendering
///
/// NES PPU supports up to 8 sprites per scanline:
/// - Sprite shift registers hold pattern data for each sprite
/// - X counters track horizontal position
/// - Attributes store palette, priority, and flip flags
pub const SpriteState = struct {
    /// Pattern shift registers (low bitplane) for 8 sprites
    /// Each byte represents one row of one sprite
    pattern_shift_lo: [8]u8 = [_]u8{0} ** 8,

    /// Pattern shift registers (high bitplane) for 8 sprites
    pattern_shift_hi: [8]u8 = [_]u8{0} ** 8,

    /// Attribute bytes for 8 sprites
    /// Bits: PPH..SPP
    /// P = palette (bits 0-1)
    /// bit 5 = priority (0 = front, 1 = behind background)
    /// H = horizontal flip (bit 6)
    /// V = vertical flip (bit 7)
    attributes: [8]u8 = [_]u8{0} ** 8,

    /// X position counters for 8 sprites
    /// Counts down from X position, sprite becomes active when counter reaches 0
    x_counters: [8]u8 = [_]u8{0} ** 8,

    /// OAM source indices for each secondary OAM slot (0-63, or 0xFF if empty)
    /// Tracks which primary OAM sprite (0-63) is in each secondary OAM slot (0-7)
    /// This is critical for sprite 0 hit detection - sprite 0 can be in ANY slot
    oam_source_index: [8]u8 = [_]u8{0xFF} ** 8,

    /// Number of sprites loaded for current scanline (0-8)
    sprite_count: u8 = 0,

    /// Sprite 0 is in secondary OAM (for sprite 0 hit detection)
    sprite_0_present: bool = false,

    /// Sprite 0 index in shift registers (0-7, or 0xFF if not present)
    sprite_0_index: u8 = 0xFF,
};

/// Background rendering state
/// Contains shift registers and latches for tile fetching pipeline
///
/// NES PPU fetches tiles 2 tiles ahead of rendering (pipelined):
/// - Shift registers contain current + next tile data
/// - Every 8 pixels, latches are loaded into shift registers
/// - Every cycle, shift registers shift by 1 bit to output next pixel
pub const BackgroundState = struct {
    /// Pattern shift registers (16 bits = 2 tiles)
    /// Shift left every cycle, reload low 8 bits every 8 cycles
    pattern_shift_lo: u16 = 0,
    pattern_shift_hi: u16 = 0,

    /// Attribute shift registers (8 bits with internal latch)
    /// Duplicates attribute bits for 8 pixels
    attribute_shift_lo: u8 = 0,
    attribute_shift_hi: u8 = 0,

    /// Tile data latches (loaded during fetch, transferred to shift regs)
    nametable_latch: u8 = 0, // Tile index from nametable
    attribute_latch: u8 = 0, // Palette bits from attribute table
    pattern_latch_lo: u8 = 0, // Pattern bitplane 0
    pattern_latch_hi: u8 = 0, // Pattern bitplane 1

    /// Load shift registers from latches
    /// Called every 8 pixels after fetching next tile
    pub fn loadShiftRegisters(self: *BackgroundState) void {
        // Load pattern data into low 8 bits of shift registers
        self.pattern_shift_lo = (self.pattern_shift_lo & 0xFF00) | self.pattern_latch_lo;
        self.pattern_shift_hi = (self.pattern_shift_hi & 0xFF00) | self.pattern_latch_hi;

        // Extend attribute bits to cover 8 pixels
        // Each attribute bit controls 8 pixels, so duplicate it
        self.attribute_shift_lo = if ((self.attribute_latch & 0x01) != 0) 0xFF else 0x00;
        self.attribute_shift_hi = if ((self.attribute_latch & 0x02) != 0) 0xFF else 0x00;
    }

    /// Shift registers by 1 pixel
    /// Called every PPU cycle during visible scanline
    pub fn shift(self: *BackgroundState) void {
        self.pattern_shift_lo <<= 1;
        self.pattern_shift_hi <<= 1;
        self.attribute_shift_lo <<= 1;
        self.attribute_shift_hi <<= 1;
    }
};

/// Complete PPU State
/// Pure data structure with no hidden state
/// Suitable for stateless rendering with libxev threading
pub const PpuState = struct {
    /// PPU Control Register ($2000)
    ctrl: PpuCtrl = .{},

    /// PPU Mask Register ($2001)
    mask: PpuMask = .{},

    /// PPU Status Register ($2002)
    status: PpuStatus = .{},

    /// OAM Address Register ($2003)
    oam_addr: u8 = 0,

    /// PPU Open Bus (data bus latch)
    open_bus: OpenBus = .{},

    /// Internal registers (v, t, x, w)
    internal: InternalRegisters = .{},

    /// Object Attribute Memory (OAM) - 256 bytes
    /// Stores sprite data (Y pos, tile, attributes, X pos)
    oam: [256]u8 = [_]u8{0} ** 256,

    /// Secondary OAM - 32 bytes
    /// Used during sprite evaluation
    secondary_oam: [32]u8 = [_]u8{0} ** 32,

    /// Internal VRAM for nametables (2KB)
    /// $2000-$27FF: Nametable storage (with mirroring)
    /// Mirroring mode determines how logical nametables map to physical VRAM
    vram: [2048]u8 = [_]u8{0} ** 2048,

    /// Palette RAM - 32 bytes
    /// $3F00-$3F1F (with mirroring)
    palette_ram: [32]u8 = [_]u8{0} ** 32,

    /// Nametable mirroring mode (set from cartridge)
    /// Determines how nametable addresses map to physical VRAM
    mirroring: Mirroring = .horizontal,

    /// PPU warm-up complete flag
    /// The PPU ignores writes to $2000/$2001/$2005/$2006 for the first ~29,658 CPU cycles
    /// after power-on. This flag is set by EmulationState after the warm-up period.
    /// Reference: nesdev.org/wiki/PPU_power_up_state
    warmup_complete: bool = false,

    /// Debug flag: Track when rendering first enables (for logging)
    rendering_was_enabled: bool = false,

    /// Background rendering state (shift registers and latches)
    bg_state: BackgroundState = .{},

    /// Sprite rendering state (shift registers, X counters, attributes)
    sprite_state: SpriteState = .{},

    /// Initialize PPU state to power-on values
    pub fn init() PpuState {
        return .{};
    }
};
