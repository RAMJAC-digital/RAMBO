//! Picture Processing Unit (PPU) - RP2C02G NTSC
//!
//! The PPU handles all graphics rendering for the NES:
//! - Background rendering (nametables + pattern tables)
//! - Sprite rendering (OAM + sprite pattern tables)
//! - Palette management
//! - VBlank/NMI generation
//! - Scrolling and fine positioning
//!
//! Hardware Accuracy:
//! - Open bus behavior on all registers
//! - Cycle-accurate rendering pipeline
//! - Proper VBlank/sprite flag timing
//! - Register mirroring through $3FFF
//!
//! Design:
//! - Pure data structure (no hidden state)
//! - Stateless rendering data for libxev threading
//! - Zero coupling (communicates via Bus only)

const std = @import("std");
const Mirroring = @import("../cartridge/ines.zig").Mirroring;
const ChrProvider = @import("../memory/ChrProvider.zig").ChrProvider;
const palette = @import("palette.zig");

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
    nametable_x: bool = false,      // Bit 0
    nametable_y: bool = false,      // Bit 1
    vram_increment: bool = false,   // Bit 2: 0=+1, 1=+32
    sprite_pattern: bool = false,   // Bit 3: 0=$0000, 1=$1000
    bg_pattern: bool = false,       // Bit 4: 0=$0000, 1=$1000
    sprite_size: bool = false,      // Bit 5: 0=8x8, 1=8x16
    master_slave: bool = false,     // Bit 6
    nmi_enable: bool = false,       // Bit 7

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
    greyscale: bool = false,             // Bit 0
    show_bg_left: bool = false,          // Bit 1
    show_sprites_left: bool = false,     // Bit 2
    show_bg: bool = false,               // Bit 3
    show_sprites: bool = false,          // Bit 4
    emphasize_red: bool = false,         // Bit 5
    emphasize_green: bool = false,       // Bit 6
    emphasize_blue: bool = false,        // Bit 7

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
/// +--------- VBlank flag (1 if in VBlank)
pub const PpuStatus = packed struct(u8) {
    open_bus: u5 = 0,                    // Bits 0-4: Open bus
    sprite_overflow: bool = false,       // Bit 5
    sprite_0_hit: bool = false,          // Bit 6
    vblank: bool = false,                // Bit 7

    /// Convert to byte representation
    /// Open bus bits come from PPU data bus latch
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
            .vblank = (byte & 0x80) != 0,
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
    /// Same format as v register
    t: u16 = 0,

    /// Fine X scroll (0-7)
    x: u3 = 0,

    /// Write toggle (w register)
    /// Toggles between first and second writes to $2005 and $2006
    w: bool = false,

    /// PPUDATA read buffer
    /// Reads from PPUDATA are delayed by one cycle (buffered)
    read_buffer: u8 = 0,

    /// Reset write toggle (called when reading $2002)
    pub fn resetToggle(self: *InternalRegisters) void {
        self.w = false;
    }
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
    nametable_latch: u8 = 0,  // Tile index from nametable
    attribute_latch: u8 = 0,   // Palette bits from attribute table
    pattern_latch_lo: u8 = 0,  // Pattern bitplane 0
    pattern_latch_hi: u8 = 0,  // Pattern bitplane 1

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

/// Mirror nametable address based on mirroring mode
/// Returns address in 0-2047 range (2KB VRAM)
///
/// Nametable layout:
/// $2000-$23FF: Nametable 0 (1KB)
/// $2400-$27FF: Nametable 1 (1KB)
/// $2800-$2BFF: Nametable 2 (1KB)
/// $2C00-$2FFF: Nametable 3 (1KB)
///
/// Physical VRAM is only 2KB, so nametables are mirrored:
/// - Horizontal: NT0=NT1 (top), NT2=NT3 (bottom)
/// - Vertical: NT0=NT2 (left), NT1=NT3 (right)
/// - Single screen: All map to same 1KB
/// - Four screen: 4KB external VRAM (no mirroring)
fn mirrorNametableAddress(address: u16, mirroring: Mirroring) u16 {
    const addr = address & 0x0FFF; // Mask to $0000-$0FFF (4KB logical space)
    const nametable = (addr >> 10) & 0x03; // Extract nametable index (0-3)

    return switch (mirroring) {
        .horizontal => blk: {
            // Horizontal mirroring (top/bottom)
            // NT0, NT1 -> VRAM $0000-$03FF
            // NT2, NT3 -> VRAM $0400-$07FF
            if (nametable < 2) {
                break :blk addr & 0x03FF; // First 1KB
            } else {
                break :blk 0x0400 | (addr & 0x03FF); // Second 1KB
            }
        },
        .vertical => blk: {
            // Vertical mirroring (left/right)
            // NT0, NT2 -> VRAM $0000-$03FF
            // NT1, NT3 -> VRAM $0400-$07FF
            if (nametable == 0 or nametable == 2) {
                break :blk addr & 0x03FF; // First 1KB
            } else {
                break :blk 0x0400 | (addr & 0x03FF); // Second 1KB
            }
        },
        .four_screen => blk: {
            // Four-screen VRAM (no mirroring)
            // Requires 4KB external VRAM on cartridge
            // For now, mirror to 2KB (will need cartridge support later)
            break :blk addr & 0x07FF;
        },
    };
}

/// Mirror palette RAM address (handles backdrop mirroring)
/// Palette RAM is 32 bytes at $3F00-$3F1F
/// Special case: $3F10/$3F14/$3F18/$3F1C mirror $3F00/$3F04/$3F08/$3F0C
///
/// Palette layout:
/// $3F00-$3F0F: Background palettes (4 palettes, 4 colors each)
/// $3F10-$3F1F: Sprite palettes (4 palettes, 4 colors each)
/// But sprite palette backdrop colors ($3F10/$14/$18/$1C) mirror BG backdrop
fn mirrorPaletteAddress(address: u8) u8 {
    const addr = address & 0x1F; // Mask to 32-byte range

    // Mirror sprite backdrop colors to background backdrop colors
    // $3F10, $3F14, $3F18, $3F1C -> $3F00, $3F04, $3F08, $3F0C
    if (addr >= 0x10 and (addr & 0x03) == 0) {
        return addr & 0x0F; // Clear bit 4 to mirror to background
    }

    return addr;
}

/// PPU State
/// Pure data structure with no hidden state
/// Suitable for stateless rendering with libxev threading
pub const Ppu = struct {
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

    /// CHR memory provider (for CHR ROM/RAM access)
    /// Interface abstraction decouples PPU from Cartridge implementation
    /// Non-owning pointer managed by EmulationState
    chr_provider: ?ChrProvider = null,

    /// NMI occurred flag
    /// Set when VBlank starts and NMI is enabled
    /// Cleared when NMI is serviced
    nmi_occurred: bool = false,

    /// Background rendering state (shift registers and latches)
    bg_state: BackgroundState = .{},

    /// Current scanline (0-261, where 261 is pre-render line)
    scanline: u16 = 0,

    /// Current dot/cycle within scanline (0-340)
    dot: u16 = 0,

    /// Frame counter (for odd frame skip)
    frame: u64 = 0,

    /// Initialize PPU to power-on state
    pub fn init() Ppu {
        return .{};
    }

    /// Reset PPU (RESET button pressed)
    /// Some registers are not affected by RESET
    pub fn reset(self: *Ppu) void {
        self.ctrl = .{};
        self.mask = .{};
        // Status VBlank bit is random at reset
        self.internal.resetToggle();
        self.nmi_occurred = false;
    }

    /// Set CHR provider for pattern table access
    ///
    /// This method connects the CHR memory provider (typically from cartridge)
    /// to enable PPU access to pattern tables at $0000-$1FFF.
    ///
    /// Parameters:
    /// - provider: ChrProvider interface from cartridge or test implementation
    ///
    /// Notes:
    /// - Must be called after loading cartridge
    /// - Provider is a non-owning interface (cartridge lifetime managed elsewhere)
    /// - Can be set to null to disconnect (for hot-swapping cartridges)
    pub fn setChrProvider(self: *Ppu, provider: ?ChrProvider) void {
        self.chr_provider = provider;
    }

    /// Set nametable mirroring mode
    ///
    /// Updates the mirroring mode used for nametable address translation.
    /// This is typically set from the cartridge header but can change at runtime
    /// for mappers like MMC1 that support dynamic mirroring.
    ///
    /// Parameters:
    /// - mode: Mirroring mode (horizontal, vertical, or four_screen)
    ///
    /// Notes:
    /// - Horizontal: NT0/NT1 map to first 1KB, NT2/NT3 to second 1KB
    /// - Vertical: NT0/NT2 map to first 1KB, NT1/NT3 to second 1KB
    /// - Four-screen: Requires 4KB VRAM on cartridge (limited support)
    pub fn setMirroring(self: *Ppu, mode: Mirroring) void {
        self.mirroring = mode;
    }

    /// Read from PPU VRAM address space ($0000-$3FFF)
    /// Handles CHR ROM/RAM, nametables, and palette RAM with proper mirroring
    pub fn readVram(self: *Ppu, address: u16) u8 {
        const addr = address & 0x3FFF; // Mirror at $4000

        return switch (addr) {
            // CHR ROM/RAM ($0000-$1FFF) - Pattern tables
            // Accessed via CHR provider interface
            0x0000...0x1FFF => blk: {
                if (self.chr_provider) |provider| {
                    break :blk provider.read(addr);
                }
                // No CHR provider - return PPU open bus (data bus latch)
                break :blk self.open_bus.read();
            },

            // Nametables ($2000-$2FFF)
            // 4KB logical space mapped to 2KB physical VRAM via mirroring
            0x2000...0x2FFF => blk: {
                const mirrored_addr = mirrorNametableAddress(addr, self.mirroring);
                break :blk self.vram[mirrored_addr];
            },

            // Nametable mirrors ($3000-$3EFF)
            // $3000-$3EFF mirrors $2000-$2EFF
            0x3000...0x3EFF => blk: {
                break :blk self.readVram(addr - 0x1000);
            },

            // Palette RAM ($3F00-$3F1F)
            // 32 bytes with special backdrop mirroring
            0x3F00...0x3F1F => blk: {
                const palette_addr = mirrorPaletteAddress(@truncate(addr & 0x1F));
                break :blk self.palette_ram[palette_addr];
            },

            // Palette RAM mirrors ($3F20-$3FFF)
            // Mirrors $3F00-$3F1F throughout $3F20-$3FFF
            0x3F20...0x3FFF => blk: {
                break :blk self.readVram(0x3F00 | (addr & 0x1F));
            },

            else => unreachable, // addr is masked to $0000-$3FFF
        };
    }

    /// Write to PPU VRAM address space ($0000-$3FFF)
    /// Handles CHR RAM, nametables, and palette RAM (CHR ROM is read-only)
    pub fn writeVram(self: *Ppu, address: u16, value: u8) void {
        const addr = address & 0x3FFF; // Mirror at $4000

        switch (addr) {
            // CHR ROM/RAM ($0000-$1FFF)
            // CHR ROM is read-only, CHR RAM is writable via CHR provider
            0x0000...0x1FFF => {
                if (self.chr_provider) |provider| {
                    // Provider handles write (ignores if CHR ROM)
                    provider.write(addr, value);
                }
            },

            // Nametables ($2000-$2FFF)
            0x2000...0x2FFF => {
                const mirrored_addr = mirrorNametableAddress(addr, self.mirroring);
                self.vram[mirrored_addr] = value;
            },

            // Nametable mirrors ($3000-$3EFF)
            0x3000...0x3EFF => {
                self.writeVram(addr - 0x1000, value);
            },

            // Palette RAM ($3F00-$3F1F)
            0x3F00...0x3F1F => {
                const palette_addr = mirrorPaletteAddress(@truncate(addr & 0x1F));
                self.palette_ram[palette_addr] = value;
            },

            // Palette RAM mirrors ($3F20-$3FFF)
            0x3F20...0x3FFF => {
                self.writeVram(0x3F00 | (addr & 0x1F), value);
            },

            else => unreachable, // addr is masked to $0000-$3FFF
        }
    }

    /// Read from PPU register (via CPU memory bus)
    /// Handles register mirroring and open bus behavior
    pub fn readRegister(self: *Ppu, address: u16) u8 {
        // Registers are mirrored every 8 bytes through $3FFF
        const reg = address & 0x0007;

        return switch (reg) {
            0x0000 => blk: {
                // $2000 PPUCTRL - Write-only, return open bus
                break :blk self.open_bus.read();
            },
            0x0001 => blk: {
                // $2001 PPUMASK - Write-only, return open bus
                break :blk self.open_bus.read();
            },
            0x0002 => blk: {
                // $2002 PPUSTATUS - Read-only
                const value = self.status.toByte(self.open_bus.value);

                // Side effects:
                // 1. Clear VBlank flag
                self.status.vblank = false;

                // 2. Reset write toggle
                self.internal.resetToggle();

                // 3. Update open bus with status (top 3 bits)
                self.open_bus.write(value);

                break :blk value;
            },
            0x0003 => blk: {
                // $2003 OAMADDR - Write-only, return open bus
                break :blk self.open_bus.read();
            },
            0x0004 => blk: {
                // $2004 OAMDATA - Read/write
                const value = self.oam[self.oam_addr];

                // Attribute bytes have bits 2-4 as open bus
                const is_attribute_byte = (self.oam_addr & 0x03) == 0x02;
                const result = if (is_attribute_byte)
                    (value & 0xE3) | (self.open_bus.value & 0x1C)
                else
                    value;

                // Update open bus
                self.open_bus.write(result);

                break :blk result;
            },
            0x0005 => blk: {
                // $2005 PPUSCROLL - Write-only, return open bus
                break :blk self.open_bus.read();
            },
            0x0006 => blk: {
                // $2006 PPUADDR - Write-only, return open bus
                break :blk self.open_bus.read();
            },
            0x0007 => blk: {
                // $2007 PPUDATA - Buffered read from VRAM
                const addr = self.internal.v;
                const buffered_value = self.internal.read_buffer;

                // Update buffer with current VRAM value
                self.internal.read_buffer = self.readVram(addr);

                // Increment VRAM address after read
                self.internal.v +%= self.ctrl.vramIncrementAmount();

                // Palette reads are NOT buffered (return current, not buffered)
                // All other reads return the buffered value
                const value = if (addr >= 0x3F00) self.internal.read_buffer else buffered_value;

                // Update open bus
                self.open_bus.write(value);

                break :blk value;
            },
            else => unreachable,
        };
    }

    /// Write to PPU register (via CPU memory bus)
    /// Handles register mirroring and open bus updates
    pub fn writeRegister(self: *Ppu, address: u16, value: u8) void {
        // Registers are mirrored every 8 bytes through $3FFF
        const reg = address & 0x0007;

        // All writes update the open bus
        self.open_bus.write(value);

        switch (reg) {
            0x0000 => {
                // $2000 PPUCTRL
                self.ctrl = PpuCtrl.fromByte(value);

                // Update t register bits 10-11 (nametable select)
                self.internal.t = (self.internal.t & 0xF3FF) |
                    (@as(u16, value & 0x03) << 10);
            },
            0x0001 => {
                // $2001 PPUMASK
                self.mask = PpuMask.fromByte(value);
            },
            0x0002 => {
                // $2002 PPUSTATUS - Read-only, write has no effect
            },
            0x0003 => {
                // $2003 OAMADDR
                self.oam_addr = value;
            },
            0x0004 => {
                // $2004 OAMDATA
                self.oam[self.oam_addr] = value;
                self.oam_addr +%= 1; // Wraps at 256
            },
            0x0005 => {
                // $2005 PPUSCROLL
                if (!self.internal.w) {
                    // First write: X scroll
                    self.internal.t = (self.internal.t & 0xFFE0) |
                        (@as(u16, value) >> 3);
                    self.internal.x = @truncate(value & 0x07);
                    self.internal.w = true;
                } else {
                    // Second write: Y scroll
                    self.internal.t = (self.internal.t & 0x8FFF) |
                        ((@as(u16, value) & 0x07) << 12);
                    self.internal.t = (self.internal.t & 0xFC1F) |
                        ((@as(u16, value) & 0xF8) << 2);
                    self.internal.w = false;
                }
            },
            0x0006 => {
                // $2006 PPUADDR
                if (!self.internal.w) {
                    // First write: High byte
                    self.internal.t = (self.internal.t & 0x80FF) |
                        ((@as(u16, value) & 0x3F) << 8);
                    self.internal.w = true;
                } else {
                    // Second write: Low byte
                    self.internal.t = (self.internal.t & 0xFF00) |
                        @as(u16, value);
                    self.internal.v = self.internal.t;
                    self.internal.w = false;
                }
            },
            0x0007 => {
                // $2007 PPUDATA - Write to VRAM
                const addr = self.internal.v;

                // Write to VRAM
                self.writeVram(addr, value);

                // Increment VRAM address after write
                self.internal.v +%= self.ctrl.vramIncrementAmount();
            },
            else => unreachable, // reg is masked to 0-7
        }
    }

    /// Increment coarse X scroll (every 8 pixels)
    /// Handles horizontal nametable wrapping
    fn incrementScrollX(self: *Ppu) void {
        if (!self.mask.renderingEnabled()) return;

        // Coarse X is bits 0-4 of v register
        if ((self.internal.v & 0x001F) == 31) {
            // Coarse X = 31, wrap to 0 and switch horizontal nametable
            self.internal.v &= ~@as(u16, 0x001F);  // Clear coarse X
            self.internal.v ^= 0x0400;              // Switch horizontal nametable
        } else {
            // Increment coarse X
            self.internal.v += 1;
        }
    }

    /// Increment Y scroll (end of scanline)
    /// Handles vertical nametable wrapping
    fn incrementScrollY(self: *Ppu) void {
        if (!self.mask.renderingEnabled()) return;

        // Fine Y is bits 12-14 of v register
        if ((self.internal.v & 0x7000) != 0x7000) {
            // Increment fine Y
            self.internal.v += 0x1000;
        } else {
            // Fine Y = 7, reset to 0 and increment coarse Y
            self.internal.v &= ~@as(u16, 0x7000);  // Clear fine Y

            // Coarse Y is bits 5-9
            var coarse_y = (self.internal.v >> 5) & 0x1F;
            if (coarse_y == 29) {
                // Coarse Y = 29, wrap to 0 and switch vertical nametable
                coarse_y = 0;
                self.internal.v ^= 0x0800;  // Switch vertical nametable
            } else if (coarse_y == 31) {
                // Out of bounds, wrap without nametable switch
                coarse_y = 0;
            } else {
                coarse_y += 1;
            }

            // Write coarse Y back to v register
            self.internal.v = (self.internal.v & ~@as(u16, 0x03E0)) | (coarse_y << 5);
        }
    }

    /// Copy horizontal scroll bits from t to v
    /// Called at dot 257 of each visible scanline
    fn copyScrollX(self: *Ppu) void {
        if (!self.mask.renderingEnabled()) return;

        // Copy bits 0-4 (coarse X) and bit 10 (horizontal nametable)
        self.internal.v = (self.internal.v & 0xFBE0) | (self.internal.t & 0x041F);
    }

    /// Copy vertical scroll bits from t to v
    /// Called at dot 280-304 of pre-render scanline
    fn copyScrollY(self: *Ppu) void {
        if (!self.mask.renderingEnabled()) return;

        // Copy bits 5-9 (coarse Y), bits 12-14 (fine Y), bit 11 (vertical nametable)
        self.internal.v = (self.internal.v & 0x841F) | (self.internal.t & 0x7BE0);
    }

    /// Get pattern table address for current tile
    /// high_bitplane: false = bitplane 0, true = bitplane 1
    fn getPatternAddress(self: *Ppu, high_bitplane: bool) u16 {
        // Pattern table base from PPUCTRL ($0000 or $1000)
        const pattern_base: u16 = if (self.ctrl.bg_pattern) 0x1000 else 0x0000;

        // Tile index from nametable latch
        const tile_index: u16 = self.bg_state.nametable_latch;

        // Fine Y from v register (bits 12-14)
        const fine_y: u16 = (self.internal.v >> 12) & 0x07;

        // Bitplane offset (bitplane 1 is +8 bytes from bitplane 0)
        const bitplane_offset: u16 = if (high_bitplane) 8 else 0;

        // Each tile is 16 bytes (8 bytes per bitplane)
        return pattern_base + (tile_index * 16) + fine_y + bitplane_offset;
    }

    /// Get attribute table address for current tile
    fn getAttributeAddress(self: *Ppu) u16 {
        // Attribute table is at +$03C0 from nametable base
        // Each attribute byte controls a 4×4 tile area (32×32 pixels)
        const v = self.internal.v;
        return 0x23C0 |
            (v & 0x0C00) |                    // Nametable select (bits 10-11)
            ((v >> 4) & 0x38) |               // High 3 bits of coarse Y
            ((v >> 2) & 0x07);                // High 3 bits of coarse X
    }

    /// Fetch background tile data for current cycle
    /// Implements 4-cycle fetch pattern: nametable → attribute → pattern low → pattern high
    fn fetchBackgroundTile(self: *Ppu) void {
        // Tile fetching occurs in 8-cycle chunks
        // Each chunk fetches: NT byte (2 cycles), AT byte (2 cycles),
        // pattern low (2 cycles), pattern high (2 cycles)
        const fetch_cycle = self.dot & 0x07;

        switch (fetch_cycle) {
            // Cycles 1, 3, 5, 7: Idle (hardware accesses nametable but doesn't use value)
            1, 3, 5, 7 => {},

            // Cycle 0: Fetch nametable byte (tile index)
            0 => {
                const nt_addr = 0x2000 | (self.internal.v & 0x0FFF);
                self.bg_state.nametable_latch = self.readVram(nt_addr);
            },

            // Cycle 2: Fetch attribute byte (palette select)
            2 => {
                const attr_addr = self.getAttributeAddress();
                const attr_byte = self.readVram(attr_addr);

                // Extract 2-bit palette for this 16×16 pixel quadrant
                // Attribute byte layout: BR BL TR TL (2 bits each)
                const coarse_x = self.internal.v & 0x1F;
                const coarse_y = (self.internal.v >> 5) & 0x1F;
                const shift = ((coarse_y & 0x02) << 1) | (coarse_x & 0x02);
                self.bg_state.attribute_latch = (attr_byte >> @intCast(shift)) & 0x03;
            },

            // Cycle 4: Fetch pattern table tile low byte (bitplane 0)
            4 => {
                const pattern_addr = self.getPatternAddress(false);
                self.bg_state.pattern_latch_lo = self.readVram(pattern_addr);
            },

            // Cycle 6: Fetch pattern table tile high byte (bitplane 1)
            6 => {
                const pattern_addr = self.getPatternAddress(true);
                self.bg_state.pattern_latch_hi = self.readVram(pattern_addr);

                // Load shift registers with fetched data
                self.bg_state.loadShiftRegisters();

                // Increment coarse X after loading tile
                self.incrementScrollX();
            },

            else => unreachable,
        }
    }

    /// Get background pixel from shift registers
    /// Returns palette index (0-31), or 0 for transparent
    fn getBackgroundPixel(self: *Ppu) u8 {
        if (!self.mask.show_bg) return 0;

        // Apply fine X scroll (0-7)
        // Shift amount is 15 - fine_x (range: 8-15)
        const shift_amount = @as(u4, 15) - self.internal.x;

        // Extract bits from pattern shift registers
        const bit0 = (self.bg_state.pattern_shift_lo >> shift_amount) & 1;
        const bit1 = (self.bg_state.pattern_shift_hi >> shift_amount) & 1;
        const pattern: u8 = @intCast((bit1 << 1) | bit0);

        if (pattern == 0) return 0;  // Transparent

        // Extract palette bits from attribute shift registers
        const attr_bit0 = (self.bg_state.attribute_shift_lo >> 7) & 1;
        const attr_bit1 = (self.bg_state.attribute_shift_hi >> 7) & 1;
        const palette_select: u8 = @intCast((attr_bit1 << 1) | attr_bit0);

        // Combine into palette RAM index ($00-$0F for background)
        return (palette_select << 2) | pattern;
    }

    /// Get final pixel color from palette
    /// Converts palette index to RGBA8888 color
    fn getPaletteColor(self: *Ppu, palette_index: u8) u32 {
        // Read NES color index from palette RAM
        const nes_color = self.palette_ram[palette_index & 0x1F];

        // Convert to RGBA using standard NES palette
        return palette.getNesColorRgba(nes_color);
    }

    /// Tick PPU by one PPU cycle
    /// Optional framebuffer for pixel output (RGBA8888, 256×240 pixels)
    pub fn tick(self: *Ppu, framebuffer: ?[]u32) void {
        // === Cycle Advance (happens FIRST) ===
        self.dot += 1;

        // End of scanline
        if (self.dot > 340) {
            self.dot = 0;
            self.scanline += 1;

            // End of frame
            if (self.scanline > 261) {
                self.scanline = 0;
                self.frame += 1;
            }
        }

        // Odd frame skip: Skip dot 0 of scanline 0 on odd frames when rendering
        if (self.scanline == 0 and self.dot == 0 and (self.frame & 1) == 1 and self.mask.renderingEnabled()) {
            self.dot = 1;
        }

        // Capture current position AFTER advancing
        const scanline = self.scanline;
        const dot = self.dot;

        // Visible scanlines (0-239) + pre-render line (261)
        const is_visible = scanline < 240;
        const is_prerender = scanline == 261;
        const is_rendering_line = is_visible or is_prerender;

        // === Background Tile Fetching ===
        // Occurs during visible scanlines and pre-render line
        if (is_rendering_line and self.mask.renderingEnabled()) {
            // Shift registers every cycle (except dot 0)
            if (dot >= 1 and dot <= 256) {
                self.bg_state.shift();
            }

            // Tile fetching (dots 1-256 and 321-336)
            if ((dot >= 1 and dot <= 256) or (dot >= 321 and dot <= 336)) {
                self.fetchBackgroundTile();
            }

            // Dummy nametable fetches (dots 337-340)
            // Hardware fetches first two tiles of next scanline
            if (dot == 338 or dot == 340) {
                const nt_addr = 0x2000 | (self.internal.v & 0x0FFF);
                _ = self.readVram(nt_addr);
            }

            // Y increment at dot 256
            if (dot == 256) {
                self.incrementScrollY();
            }

            // Copy horizontal scroll at dot 257
            if (dot == 257) {
                self.copyScrollX();
            }

            // Copy vertical scroll during pre-render scanline
            if (is_prerender and dot >= 280 and dot <= 304) {
                self.copyScrollY();
            }
        }

        // === Pixel Output ===
        // Render pixels to framebuffer during visible scanlines
        if (is_visible and dot >= 1 and dot <= 256) {
            const pixel_x = dot - 1;
            const pixel_y = scanline;

            // Get background pixel
            const bg_pixel = self.getBackgroundPixel();

            // Determine final color
            const palette_index = if (bg_pixel != 0)
                bg_pixel
            else
                self.palette_ram[0];  // Use backdrop color for transparent

            const color = self.getPaletteColor(palette_index);

            // Write to framebuffer
            if (framebuffer) |fb| {
                const fb_index = pixel_y * 256 + pixel_x;
                fb[fb_index] = color;
            }
        }

        // === VBlank Timing ===
        // VBlank start: Scanline 241, dot 1
        if (scanline == 241 and dot == 1) {
            self.status.vblank = true;

            // Trigger NMI if enabled
            if (self.ctrl.nmi_enable) {
                self.nmi_occurred = true;
            }
        }

        // === Pre-render Scanline ===
        // Pre-render scanline: Scanline 261, dot 1
        // Clear VBlank and sprite flags
        if (scanline == 261 and dot == 1) {
            self.status.vblank = false;
            self.status.sprite_0_hit = false;
            self.status.sprite_overflow = false;
            self.nmi_occurred = false;
        }
    }

    /// Check if NMI should be triggered
    /// Called by CPU to check NMI line
    pub fn pollNmi(self: *Ppu) bool {
        const nmi = self.nmi_occurred;
        self.nmi_occurred = false; // Clear on poll
        return nmi;
    }

    /// Decay open bus value (called once per frame)
    pub fn tickFrame(self: *Ppu) void {
        self.open_bus.decay();
    }
};

// ============================================================================
// Tests
// ============================================================================

const testing = std.testing;

test "PpuCtrl: byte conversion" {
    var ctrl = PpuCtrl{};
    try testing.expectEqual(@as(u8, 0x00), ctrl.toByte());

    ctrl.nmi_enable = true;
    try testing.expectEqual(@as(u8, 0x80), ctrl.toByte());

    ctrl = PpuCtrl.fromByte(0xFF);
    try testing.expect(ctrl.nmi_enable);
    try testing.expect(ctrl.sprite_size);
    try testing.expect(ctrl.vram_increment);
}

test "PpuMask: rendering enabled" {
    var mask = PpuMask{};
    try testing.expect(!mask.renderingEnabled());

    mask.show_bg = true;
    try testing.expect(mask.renderingEnabled());

    mask.show_bg = false;
    mask.show_sprites = true;
    try testing.expect(mask.renderingEnabled());
}

test "PpuStatus: open bus behavior" {
    var status = PpuStatus{};
    status.vblank = true;

    // With data bus = 0x1F (all open bus bits set)
    const value1 = status.toByte(0x1F);
    try testing.expectEqual(@as(u8, 0x9F), value1); // VBlank + open bus

    // With data bus = 0x00
    const value2 = status.toByte(0x00);
    try testing.expectEqual(@as(u8, 0x80), value2); // VBlank only
}

test "Ppu: initialization" {
    const ppu = Ppu.init();
    try testing.expect(!ppu.ctrl.nmi_enable);
    try testing.expect(!ppu.mask.renderingEnabled());
    try testing.expect(!ppu.status.vblank);
}

test "Ppu: PPUCTRL write" {
    var ppu = Ppu.init();

    ppu.writeRegister(0x2000, 0x80); // Enable NMI
    try testing.expect(ppu.ctrl.nmi_enable);
    try testing.expectEqual(@as(u8, 0x80), ppu.open_bus.value);
}

test "Ppu: PPUSTATUS read clears VBlank" {
    var ppu = Ppu.init();
    ppu.status.vblank = true;

    const value = ppu.readRegister(0x2002);
    try testing.expectEqual(@as(u8, 0x80), value); // VBlank bit set
    try testing.expect(!ppu.status.vblank); // Cleared after read
}

test "Ppu: write-only register reads return open bus" {
    var ppu = Ppu.init();
    ppu.open_bus.write(0x42);

    try testing.expectEqual(@as(u8, 0x42), ppu.readRegister(0x2000)); // PPUCTRL
    try testing.expectEqual(@as(u8, 0x42), ppu.readRegister(0x2001)); // PPUMASK
    try testing.expectEqual(@as(u8, 0x42), ppu.readRegister(0x2005)); // PPUSCROLL
}

test "Ppu: register mirroring" {
    var ppu = Ppu.init();

    // Write to $2000
    ppu.writeRegister(0x2000, 0x80);
    try testing.expect(ppu.ctrl.nmi_enable);

    // Write to $2008 (mirror of $2000)
    ppu.writeRegister(0x2008, 0x00);
    try testing.expect(!ppu.ctrl.nmi_enable);

    // Write to $3456 (mirror of $2006)
    ppu.writeRegister(0x3456, 0x20);
    try testing.expect(ppu.internal.w); // First write to PPUADDR sets w flag
}

test "Ppu: VBlank NMI generation" {
    var ppu = Ppu.init();
    ppu.ctrl.nmi_enable = true;

    // Advance to scanline 240, dot 340
    ppu.scanline = 240;
    ppu.dot = 340;
    ppu.tick(null);
    try testing.expect(!ppu.nmi_occurred);

    // Advance to scanline 241, dot 1 (VBlank start)
    ppu.scanline = 241;
    ppu.dot = 0;
    ppu.tick(null);  // This advances to dot 1
    try testing.expect(ppu.status.vblank);
    try testing.expect(ppu.nmi_occurred);
}

test "Ppu: pre-render scanline clears flags" {
    var ppu = Ppu.init();
    ppu.status.vblank = true;
    ppu.status.sprite_0_hit = true;
    ppu.status.sprite_overflow = true;

    // Advance to scanline 261, dot 1 (pre-render)
    ppu.scanline = 261;
    ppu.dot = 0;
    ppu.tick(null);

    try testing.expect(!ppu.status.vblank);
    try testing.expect(!ppu.status.sprite_0_hit);
    try testing.expect(!ppu.status.sprite_overflow);
}

// ============================================================================
// VRAM Tests
// ============================================================================

test "VRAM: nametable read/write with horizontal mirroring" {
    var ppu = Ppu.init();
    ppu.mirroring = .horizontal;

    // NT0 ($2000-$23FF) and NT1 ($2400-$27FF) map to first 1KB
    ppu.writeVram(0x2000, 0xAA);
    try testing.expectEqual(@as(u8, 0xAA), ppu.readVram(0x2000));
    try testing.expectEqual(@as(u8, 0xAA), ppu.vram[0x0000]);

    ppu.writeVram(0x2400, 0xBB);
    try testing.expectEqual(@as(u8, 0xBB), ppu.readVram(0x2400));
    try testing.expectEqual(@as(u8, 0xBB), ppu.vram[0x0000]); // Same as NT0

    // NT2 ($2800-$2BFF) and NT3 ($2C00-$2FFF) map to second 1KB
    ppu.writeVram(0x2800, 0xCC);
    try testing.expectEqual(@as(u8, 0xCC), ppu.readVram(0x2800));
    try testing.expectEqual(@as(u8, 0xCC), ppu.vram[0x0400]);

    ppu.writeVram(0x2C00, 0xDD);
    try testing.expectEqual(@as(u8, 0xDD), ppu.readVram(0x2C00));
    try testing.expectEqual(@as(u8, 0xDD), ppu.vram[0x0400]); // Same as NT2
}

test "VRAM: nametable read/write with vertical mirroring" {
    var ppu = Ppu.init();
    ppu.mirroring = .vertical;

    // NT0 ($2000-$23FF) and NT2 ($2800-$2BFF) map to first 1KB
    ppu.writeVram(0x2000, 0xAA);
    try testing.expectEqual(@as(u8, 0xAA), ppu.readVram(0x2000));

    ppu.writeVram(0x2800, 0xBB);
    try testing.expectEqual(@as(u8, 0xBB), ppu.readVram(0x2800));
    try testing.expectEqual(@as(u8, 0xBB), ppu.vram[0x0000]); // Same as NT0

    // NT1 ($2400-$27FF) and NT3 ($2C00-$2FFF) map to second 1KB
    ppu.writeVram(0x2400, 0xCC);
    try testing.expectEqual(@as(u8, 0xCC), ppu.readVram(0x2400));

    ppu.writeVram(0x2C00, 0xDD);
    try testing.expectEqual(@as(u8, 0xDD), ppu.readVram(0x2C00));
    try testing.expectEqual(@as(u8, 0xDD), ppu.vram[0x0400]); // Same as NT1
}

test "VRAM: nametable mirrors ($3000-$3EFF)" {
    var ppu = Ppu.init();
    ppu.mirroring = .horizontal;

    // Write to nametable
    ppu.writeVram(0x2123, 0x42);

    // Read from mirror
    try testing.expectEqual(@as(u8, 0x42), ppu.readVram(0x3123));

    // Write to mirror
    ppu.writeVram(0x3456, 0x99);

    // Read from nametable
    try testing.expectEqual(@as(u8, 0x99), ppu.readVram(0x2456));
}

test "VRAM: palette RAM read/write" {
    var ppu = Ppu.init();

    // Background palette 0
    ppu.writeVram(0x3F00, 0x0F); // Backdrop
    ppu.writeVram(0x3F01, 0x30);
    ppu.writeVram(0x3F02, 0x10);
    ppu.writeVram(0x3F03, 0x00);

    try testing.expectEqual(@as(u8, 0x0F), ppu.readVram(0x3F00));
    try testing.expectEqual(@as(u8, 0x30), ppu.readVram(0x3F01));

    // Sprite palette 0
    ppu.writeVram(0x3F11, 0x38);
    try testing.expectEqual(@as(u8, 0x38), ppu.readVram(0x3F11));
}

test "VRAM: palette backdrop mirroring" {
    var ppu = Ppu.init();

    // Write to background backdrop
    ppu.writeVram(0x3F00, 0x0F);

    // Sprite palette 0 backdrop should mirror BG backdrop
    try testing.expectEqual(@as(u8, 0x0F), ppu.readVram(0x3F10));

    // Same for other sprite palettes
    ppu.writeVram(0x3F04, 0x30);
    try testing.expectEqual(@as(u8, 0x30), ppu.readVram(0x3F14));

    ppu.writeVram(0x3F08, 0x10);
    try testing.expectEqual(@as(u8, 0x10), ppu.readVram(0x3F18));

    ppu.writeVram(0x3F0C, 0x00);
    try testing.expectEqual(@as(u8, 0x00), ppu.readVram(0x3F1C));
}

test "VRAM: palette RAM mirrors ($3F20-$3FFF)" {
    var ppu = Ppu.init();

    // Write to palette RAM
    ppu.writeVram(0x3F05, 0x42);

    // Read from mirrors
    try testing.expectEqual(@as(u8, 0x42), ppu.readVram(0x3F25));
    try testing.expectEqual(@as(u8, 0x42), ppu.readVram(0x3F45));
    try testing.expectEqual(@as(u8, 0x42), ppu.readVram(0x3FE5));

    // Write to mirror
    ppu.writeVram(0x3F67, 0x99);

    // Read from base
    try testing.expectEqual(@as(u8, 0x99), ppu.readVram(0x3F07));
}

test "PPUDATA: read with buffering" {
    var ppu = Ppu.init();
    ppu.mirroring = .horizontal;

    // Write test data to VRAM
    ppu.writeVram(0x2000, 0xAA);
    ppu.writeVram(0x2001, 0xBB);
    ppu.writeVram(0x2002, 0xCC);

    // Set PPUADDR to $2000
    ppu.writeRegister(0x2006, 0x20);
    ppu.writeRegister(0x2006, 0x00);

    // First read returns buffer (0), buffer fills with $AA
    const read1 = ppu.readRegister(0x2007);
    try testing.expectEqual(@as(u8, 0x00), read1);

    // Second read returns $AA, buffer fills with $BB
    const read2 = ppu.readRegister(0x2007);
    try testing.expectEqual(@as(u8, 0xAA), read2);

    // Third read returns $BB
    const read3 = ppu.readRegister(0x2007);
    try testing.expectEqual(@as(u8, 0xBB), read3);
}

test "PPUDATA: palette reads not buffered" {
    var ppu = Ppu.init();

    // Write test data to palette
    ppu.writeVram(0x3F00, 0x0F);
    ppu.writeVram(0x3F01, 0x30);

    // Set PPUADDR to $3F00 (palette)
    ppu.writeRegister(0x2006, 0x3F);
    ppu.writeRegister(0x2006, 0x00);

    // Palette reads are NOT buffered - return immediately
    const read1 = ppu.readRegister(0x2007);
    try testing.expectEqual(@as(u8, 0x0F), read1);

    const read2 = ppu.readRegister(0x2007);
    try testing.expectEqual(@as(u8, 0x30), read2);
}

test "PPUDATA: write to VRAM" {
    var ppu = Ppu.init();
    ppu.mirroring = .horizontal;

    // Set PPUADDR to $2000
    ppu.writeRegister(0x2006, 0x20);
    ppu.writeRegister(0x2006, 0x00);

    // Write via PPUDATA
    ppu.writeRegister(0x2007, 0xAA);
    ppu.writeRegister(0x2007, 0xBB);
    ppu.writeRegister(0x2007, 0xCC);

    // Verify data written
    try testing.expectEqual(@as(u8, 0xAA), ppu.readVram(0x2000));
    try testing.expectEqual(@as(u8, 0xBB), ppu.readVram(0x2001));
    try testing.expectEqual(@as(u8, 0xCC), ppu.readVram(0x2002));
}

test "PPUDATA: VRAM increment +1" {
    var ppu = Ppu.init();

    // Set VRAM increment to +1 (PPUCTRL bit 2 = 0)
    ppu.writeRegister(0x2000, 0x00);

    // Set PPUADDR to $2000
    ppu.writeRegister(0x2006, 0x20);
    ppu.writeRegister(0x2006, 0x00);

    // Write 3 bytes
    ppu.writeRegister(0x2007, 0xAA);
    ppu.writeRegister(0x2007, 0xBB);
    ppu.writeRegister(0x2007, 0xCC);

    // VRAM address should now be $2003
    try testing.expectEqual(@as(u16, 0x2003), ppu.internal.v);
}

test "PPUDATA: VRAM increment +32" {
    var ppu = Ppu.init();

    // Set VRAM increment to +32 (PPUCTRL bit 2 = 1)
    ppu.writeRegister(0x2000, 0x04);

    // Set PPUADDR to $2000
    ppu.writeRegister(0x2006, 0x20);
    ppu.writeRegister(0x2006, 0x00);

    // Write 2 bytes
    ppu.writeRegister(0x2007, 0xAA);
    ppu.writeRegister(0x2007, 0xBB);

    // VRAM address should now be $2040 (2000 + 32 + 32)
    try testing.expectEqual(@as(u16, 0x2040), ppu.internal.v);
}

test "mirrorNametableAddress: horizontal mirroring" {
    // NT0 ($2000) -> VRAM $0000
    try testing.expectEqual(@as(u16, 0x0000), mirrorNametableAddress(0x2000, .horizontal));

    // NT1 ($2400) -> VRAM $0000 (same as NT0)
    try testing.expectEqual(@as(u16, 0x0000), mirrorNametableAddress(0x2400, .horizontal));

    // NT2 ($2800) -> VRAM $0400
    try testing.expectEqual(@as(u16, 0x0400), mirrorNametableAddress(0x2800, .horizontal));

    // NT3 ($2C00) -> VRAM $0400 (same as NT2)
    try testing.expectEqual(@as(u16, 0x0400), mirrorNametableAddress(0x2C00, .horizontal));

    // Test with offset
    try testing.expectEqual(@as(u16, 0x0123), mirrorNametableAddress(0x2123, .horizontal));
    try testing.expectEqual(@as(u16, 0x0123), mirrorNametableAddress(0x2523, .horizontal));
}

test "mirrorNametableAddress: vertical mirroring" {
    // NT0 ($2000) -> VRAM $0000
    try testing.expectEqual(@as(u16, 0x0000), mirrorNametableAddress(0x2000, .vertical));

    // NT1 ($2400) -> VRAM $0400
    try testing.expectEqual(@as(u16, 0x0400), mirrorNametableAddress(0x2400, .vertical));

    // NT2 ($2800) -> VRAM $0000 (same as NT0)
    try testing.expectEqual(@as(u16, 0x0000), mirrorNametableAddress(0x2800, .vertical));

    // NT3 ($2C00) -> VRAM $0400 (same as NT1)
    try testing.expectEqual(@as(u16, 0x0400), mirrorNametableAddress(0x2C00, .vertical));
}

test "mirrorPaletteAddress: backdrop mirroring" {
    // Background backdrops map to themselves
    try testing.expectEqual(@as(u8, 0x00), mirrorPaletteAddress(0x00));
    try testing.expectEqual(@as(u8, 0x04), mirrorPaletteAddress(0x04));
    try testing.expectEqual(@as(u8, 0x08), mirrorPaletteAddress(0x08));
    try testing.expectEqual(@as(u8, 0x0C), mirrorPaletteAddress(0x0C));

    // Sprite backdrops mirror to background backdrops
    try testing.expectEqual(@as(u8, 0x00), mirrorPaletteAddress(0x10));
    try testing.expectEqual(@as(u8, 0x04), mirrorPaletteAddress(0x14));
    try testing.expectEqual(@as(u8, 0x08), mirrorPaletteAddress(0x18));
    try testing.expectEqual(@as(u8, 0x0C), mirrorPaletteAddress(0x1C));

    // Non-backdrop colors map to themselves
    try testing.expectEqual(@as(u8, 0x01), mirrorPaletteAddress(0x01));
    try testing.expectEqual(@as(u8, 0x11), mirrorPaletteAddress(0x11));
    try testing.expectEqual(@as(u8, 0x1F), mirrorPaletteAddress(0x1F));
}
