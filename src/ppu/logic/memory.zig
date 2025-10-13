//! PPU Memory Access and Mirroring
//!
//! Handles VRAM address space ($0000-$3FFF) including:
//! - CHR ROM/RAM access (via cartridge)
//! - Nametable mirroring (horizontal/vertical/four-screen)
//! - Palette RAM with backdrop mirroring
//! - Open bus behavior

const PpuState = @import("../State.zig").PpuState;
const Cartridge = @import("../../cartridge/Cartridge.zig");
const AnyCartridge = @import("../../cartridge/mappers/registry.zig").AnyCartridge;
const Mirroring = Cartridge.Mirroring;

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
        .single_screen => blk: {
            // Single-screen mirroring (all map to same 1KB)
            // Used by some mapper configurations
            break :blk addr & 0x03FF; // First 1KB only
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

/// Read from PPU VRAM address space ($0000-$3FFF)
/// Handles CHR ROM/RAM, nametables, and palette RAM with proper mirroring
pub fn readVram(state: *PpuState, cart: ?*AnyCartridge, address: u16) u8 {
    const addr = address & 0x3FFF; // Mirror at $4000

    return switch (addr) {
        // CHR ROM/RAM ($0000-$1FFF) - Pattern tables
        // Accessed via cartridge ppuRead() method
        0x0000...0x1FFF => blk: {
            if (cart) |c| {
                break :blk c.ppuRead(addr);
            }
            // No cartridge - return PPU open bus (data bus latch)
            break :blk state.open_bus.read();
        },

        // Nametables ($2000-$2FFF)
        // 4KB logical space mapped to 2KB physical VRAM via mirroring
        0x2000...0x2FFF => blk: {
            const mirrored_addr = mirrorNametableAddress(addr, state.mirroring);
            break :blk state.vram[mirrored_addr];
        },

        // Nametable mirrors ($3000-$3EFF)
        // $3000-$3EFF mirrors $2000-$2EFF
        0x3000...0x3EFF => blk: {
            break :blk readVram(state, cart, addr - 0x1000);
        },

        // Palette RAM ($3F00-$3F1F)
        // 32 bytes with special backdrop mirroring
        0x3F00...0x3F1F => blk: {
            const palette_addr = mirrorPaletteAddress(@truncate(addr & 0x1F));
            break :blk state.palette_ram[palette_addr];
        },

        // Palette RAM mirrors ($3F20-$3FFF)
        // Mirrors $3F00-$3F1F throughout $3F20-$3FFF
        0x3F20...0x3FFF => blk: {
            break :blk readVram(state, cart, 0x3F00 | (addr & 0x1F));
        },

        else => unreachable, // addr is masked to $0000-$3FFF
    };
}

/// Write to PPU VRAM address space ($0000-$3FFF)
/// Handles CHR RAM, nametables, and palette RAM (CHR ROM is read-only)
pub fn writeVram(state: *PpuState, cart: ?*AnyCartridge, address: u16, value: u8) void {
    const addr = address & 0x3FFF; // Mirror at $4000

    switch (addr) {
        // CHR ROM/RAM ($0000-$1FFF)
        // CHR ROM is read-only, CHR RAM is writable via cartridge
        0x0000...0x1FFF => {
            if (cart) |c| {
                // Cartridge handles write (ignores if CHR ROM)
                c.ppuWrite(addr, value);
            }
        },

        // Nametables ($2000-$2FFF)
        0x2000...0x2FFF => {
            const mirrored_addr = mirrorNametableAddress(addr, state.mirroring);
            state.vram[mirrored_addr] = value;
        },

        // Nametable mirrors ($3000-$3EFF)
        0x3000...0x3EFF => {
            writeVram(state, cart, addr - 0x1000, value);
        },

        // Palette RAM ($3F00-$3F1F)
        0x3F00...0x3F1F => {
            const palette_addr = mirrorPaletteAddress(@truncate(addr & 0x1F));
            state.palette_ram[palette_addr] = value;
        },

        // Palette RAM mirrors ($3F20-$3FFF)
        0x3F20...0x3FFF => {
            writeVram(state, cart, 0x3F00 | (addr & 0x1F), value);
        },

        else => unreachable, // addr is masked to $0000-$3FFF
    }
}
