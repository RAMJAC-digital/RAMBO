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

    /// Palette RAM - 32 bytes
    /// $3F00-$3F1F (with mirroring)
    palette_ram: [32]u8 = [_]u8{0} ** 32,

    /// NMI occurred flag
    /// Set when VBlank starts and NMI is enabled
    /// Cleared when NMI is serviced
    nmi_occurred: bool = false,

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
                // $2007 PPUDATA - Read/write
                // TODO Phase 4: Implement PPUDATA read with buffer
                const value = self.internal.read_buffer;
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
                // $2007 PPUDATA
                // TODO Phase 4: Implement PPUDATA write to VRAM
                self.internal.v +%= self.ctrl.vramIncrementAmount();
            },
            else => unreachable, // reg is masked to 0-7
        }
    }

    /// Tick PPU by one PPU cycle
    /// Called from EmulationState.tick()
    pub fn tick(self: *Ppu, scanline: u16, dot: u16) void {
        // VBlank start: Scanline 241, dot 1
        if (scanline == 241 and dot == 1) {
            self.status.vblank = true;

            // Trigger NMI if enabled
            if (self.ctrl.nmi_enable) {
                self.nmi_occurred = true;
            }
        }

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

    // Before VBlank
    ppu.tick(240, 340);
    try testing.expect(!ppu.nmi_occurred);

    // VBlank start
    ppu.tick(241, 1);
    try testing.expect(ppu.status.vblank);
    try testing.expect(ppu.nmi_occurred);
}

test "Ppu: pre-render scanline clears flags" {
    var ppu = Ppu.init();
    ppu.status.vblank = true;
    ppu.status.sprite_0_hit = true;
    ppu.status.sprite_overflow = true;

    ppu.tick(261, 1);

    try testing.expect(!ppu.status.vblank);
    try testing.expect(!ppu.status.sprite_0_hit);
    try testing.expect(!ppu.status.sprite_overflow);
}
