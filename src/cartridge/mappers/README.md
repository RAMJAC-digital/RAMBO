# NES Mapper Implementations

**Status:** ✅ 6/6 mappers implemented (76% library coverage) - PHASE 1 COMPLETE!
**Priority:** HIGH (game compatibility)
**Reference:** `docs/sessions/2025-10-14-mapper-implementation-plan.md`, `CLAUDE.md`

## Overview

Mapper implementations for RAMBO NES Emulator using comptime generics.

**Implemented Mappers:**
- ✅ **Mapper 0 (NROM)** - `src/cartridge/mappers/Mapper0.zig` - 5% coverage (248 games)
- ✅ **Mapper 1 (MMC1)** - `src/cartridge/mappers/Mapper1.zig` - 28% coverage (681 games)
- ✅ **Mapper 2 (UxROM)** - `src/cartridge/mappers/Mapper2.zig` - 10% coverage (270 games)
- ✅ **Mapper 3 (CNROM)** - `src/cartridge/mappers/Mapper3.zig` - 6% coverage (155 games)
- ✅ **Mapper 4 (MMC3)** - `src/cartridge/mappers/Mapper4.zig` - 25% coverage (600 games)
- ✅ **Mapper 7 (AxROM)** - `src/cartridge/mappers/Mapper7.zig` - 2% coverage (~50 games)

**Total Coverage:** 76% of NES library (~2,004 games)

**Phase 1 Complete!** - Covers 3 of 4 top mappers (MMC1, UxROM, MMC3)

**Target Coverage:** ~85% of NES library

## Implementation Pattern

All mappers follow the comptime generic pattern established by Mapper 0:

```zig
// Generic cartridge type
pub fn Cartridge(comptime MapperType: type) type {
    return struct {
        mapper: MapperType,
        // ... common cartridge logic
    };
}

// Type alias for convenience
pub const Mmc1Cart = Cartridge(Mmc1);
```

## Mapper Details

### Mapper 1: MMC1

**Status:** ✅ Implemented (2025-10-14)
**Games:** The Legend of Zelda, Metroid, Mega Man 2, Kid Icarus, Final Fantasy
**nesdev.org:** https://www.nesdev.org/wiki/MMC1

**Hardware:**
- **PRG ROM:** Up to 512KB (32 banks × 16KB)
- **CHR ROM/RAM:** Up to 128KB (16 banks × 8KB)
- **PRG RAM:** Up to 32KB at $6000-$7FFF (battery-backed for saves)
- **Banking Modes:** Multiple PRG/CHR modes via control register
- **Mirroring:** Software-controlled (H/V/single-screen)
- **Protocol:** 5-bit shift register (serial writes)
- **IRQ:** None

**Serial Protocol:**
MMC1 uses a unique 5-bit shift register protocol requiring 5 sequential writes:

```zig
// Each write shifts in bit 0 (LSB-first)
// Write 5: xxxx xPPP -> bits 0-2 become PRG bank
// Write 4: xxxx xCCC -> bits 0-2 shift left
// Write 3: xxxx xBBB -> bits 0-2 shift left
// Write 2: xxxx xAAA -> bits 0-2 shift left
// Write 1: xxxx xDDD -> bits 0-2 shift left

// Bit 7 set = reset shift register
if ((value & 0x80) != 0) {
    shift_register = 0;
    shift_count = 0;
    control |= 0x0C;  // Default: PRG mode 3
}
```

**Banking Modes:**

*PRG Modes (control bits 2-3):*
- **Mode 0/1:** 32KB bank at $8000 (ignore low bit of bank select)
- **Mode 2:** Fixed first 16KB bank at $8000, switchable at $C000
- **Mode 3:** Switchable 16KB bank at $8000, fixed last at $C000 (most common)

*CHR Modes (control bit 4):*
- **8KB mode:** Single 8KB bank (ignore chr_bank_1)
- **4KB mode:** Two separate 4KB banks at $0000 and $1000

**Implementation:**
```zig
pub const Mapper1 = struct {
    // Shift register state
    shift_register: u5 = 0,
    shift_count: u3 = 0,

    // Internal registers (loaded after 5 writes)
    control: u5 = 0x0C,      // PRG mode, CHR mode, mirroring
    chr_bank_0: u5 = 0,      // CHR bank $0000-$0FFF (4KB) or $0000-$1FFF (8KB)
    chr_bank_1: u5 = 0,      // CHR bank $1000-$1FFF (4KB mode only)
    prg_bank: u5 = 0,        // PRG bank select + PRG RAM enable

    pub fn cpuWrite(self: *Mapper1, cart: anytype, address: u16, value: u8) void {
        if (address < 0x8000) return;

        // Check for reset (bit 7)
        if ((value & 0x80) != 0) {
            self.shift_register = 0;
            self.shift_count = 0;
            self.control |= 0x0C;  // Default PRG mode
            return;
        }

        // Shift in bit 0
        const bit: u5 = @truncate(value & 0x01);
        self.shift_register = (self.shift_register >> 1) | (bit << 4);
        self.shift_count += 1;

        if (self.shift_count == 5) {
            // Load target register based on address
            if (address < 0xA000) {
                self.control = self.shift_register;
            } else if (address < 0xC000) {
                self.chr_bank_0 = self.shift_register;
            } else if (address < 0xE000) {
                self.chr_bank_1 = self.shift_register;
            } else {
                self.prg_bank = self.shift_register;
            }

            // Reset for next load
            self.shift_register = 0;
            self.shift_count = 0;

            // Update cartridge mirroring
            cart.updateMirroring();
        }
    }

    pub fn cpuRead(self: *const Mapper1, cart: anytype, address: u16) u8 {
        // PRG RAM at $6000-$7FFF (if enabled and present)
        if (address >= 0x6000 and address < 0x8000) {
            if (cart.prg_ram) |ram| {
                const prg_ram_enabled = (self.prg_bank & 0x10) == 0;
                if (prg_ram_enabled) {
                    return ram[@as(usize, address - 0x6000)];
                }
            }
            return 0xFF;  // Open bus
        }

        // PRG ROM banking (4 modes)
        if (address >= 0x8000) {
            const prg_mode = (self.control >> 2) & 0x03;
            const prg_bank_num = self.prg_bank & 0x0F;

            return switch (prg_mode) {
                0, 1 => /* 32KB mode */,
                2 => /* Fixed first, switchable at $C000 */,
                3 => /* Switchable at $8000, fixed last */,
                else => 0xFF,
            };
        }

        return 0xFF;
    }
};
```

**PRG RAM Support:** MMC1 provides battery-backed PRG RAM at $6000-$7FFF for game saves (Zelda, Metroid). Bit 4 of prg_bank register enables/disables access (0 = enabled, 1 = disabled).

**Mirroring Control:** Bits 0-1 of control register set mirroring:
- 0: Single-screen lower bank
- 1: Single-screen upper bank
- 2: Vertical
- 3: Horizontal

**Common Variants:**
- **SxROM:** Standard MMC1 (Zelda, Metroid)
- **SUROM:** 512KB PRG ROM support
- **SXROM:** 32KB PRG RAM support

**Test Coverage:** 8 built-in tests
- Power-on state (control = $0C, PRG mode 3)
- Shift register protocol (5 writes required)
- Reset clears shift register (bit 7 set)
- PRG banking mode 3 (switchable + fixed last)
- CHR 4KB banking mode
- PRG RAM enable/disable
- IRQ interface stubs

**Available Test ROMs:** (26 MMC1 titles found)
- `tests/data/Adventures of Lolo (USA).nes`
- `tests/data/Adventures of Rad Gravity, The (USA).nes`
- `tests/data/Battle of Olympus, The (USA).nes`
- `tests/data/Bionic Commando (USA).nes`
- `tests/data/Bubble Bobble (USA).nes`
- `tests/data/Chip 'n Dale - Rescue Rangers (USA).nes`
- `tests/data/Clash at Demonhead (USA).nes`
- `tests/data/Darkwing Duck (USA).nes`
- `tests/data/Die Hard (USA).nes`
- `tests/data/Faxanadu (USA) (Rev 1).nes`
- `tests/data/Guerrilla War (USA).nes`
- `tests/data/Journey to Silius (USA).nes`
- `tests/data/Kid Icarus (USA, Europe) (Rev 1).nes` ⭐
- `tests/data/Lemmings (USA).nes`
- `tests/data/Magic of Scheherazade, The (USA).nes`
- `tests/data/Maniac Mansion (USA).nes`
- `tests/data/Metroid (USA).nes` ⭐
- `tests/data/Pirates! (USA).nes`
- `tests/data/Princess Tomato in the Salad Kingdom (USA).nes`
- `tests/data/Rescue - The Embassy Mission (USA).nes`
- `tests/data/Robin Hood - Prince of Thieves (USA) (Rev 1).nes`
- `tests/data/S.C.A.T. - Special Cybernetic Attack Team (USA).nes`
- `tests/data/Snake Rattle n Roll (USA).nes`
- `tests/data/Strider (USA).nes`

---

### Mapper 3: CNROM

**Status:** ✅ Implemented (2025-10-14)
**Games:** Arkanoid, Gradius, Donkey Kong 3, Legend of Kage, Paperboy
**nesdev.org:** https://www.nesdev.org/wiki/CNROM

**Hardware:**
- **PRG ROM:** 16KB or 32KB (fixed, no banking)
- **CHR ROM:** Up to 32KB (4 banks × 8KB)
- **CHR Banking:** 2-bit register ($8000-$FFFF writes)
- **Mirroring:** Fixed by hardware (H/V)
- **PRG RAM:** None
- **IRQ:** None

**Implementation:**
```zig
pub const Mapper3 = struct {
    chr_bank: u2 = 0,  // CHR bank select (0-3)

    // Any write to $8000-$FFFF sets CHR bank (bits 0-1)
    pub fn cpuWrite(self: *Mapper3, _: anytype, address: u16, value: u8) void {
        if (address >= 0x8000) {
            self.chr_bank = @truncate(value & 0x03);
        }
    }

    // CHR banking: (chr_bank * 0x2000) + (address & 0x1FFF)
    pub fn ppuRead(self: *const Mapper3, cart: anytype, address: u16) u8 {
        const bank_offset: usize = @as(usize, self.chr_bank) * 0x2000;
        const chr_offset = bank_offset + @as(usize, address & 0x1FFF);
        return cart.chr_data[chr_offset];
    }
};
```

**Bus Conflicts:** CNROM is subject to bus conflicts (CPU reads ROM value during write). Games typically write values that match ROM contents. Implementation ignores bus conflicts for compatibility.

**Test Coverage:** 11 built-in tests
- Power-on state
- CHR bank switching (4 banks)
- CHR bank masking (2-bit)
- PRG ROM mapping (16KB/32KB)
- PRG ROM mirroring (16KB)
- CHR ROM writes ignored
- Reset behavior
- No PRG RAM support
- IRQ interface stubs

**Available Test ROMs:**
- `tests/data/Legend of Kage, The (USA).nes`
- `tests/data/Mickey Mousecapade (USA).nes`
- `tests/data/Moai-kun (Japan).nes`
- `tests/data/Paperboy (USA).nes`

---

### Mapper 7: AxROM

**Status:** ✅ Implemented (2025-10-14)
**Games:** Battletoads, Wizards & Warriors, Marble Madness, Cabal, Captain Skyhawk
**nesdev.org:** https://www.nesdev.org/wiki/AxROM

**Hardware:**
- **PRG ROM:** Up to 256KB (8 banks × 32KB, switchable)
- **CHR RAM:** 8KB (writable, not ROM)
- **PRG Banking:** 3-bit register at $8000-$FFFF (bits 0-2)
- **Mirroring:** Single-screen (software-controlled via bit 4)
- **PRG RAM:** None
- **IRQ:** None

**Implementation:**
```zig
pub const Mapper7 = struct {
    prg_bank: u3 = 0,      // PRG bank select (0-7)
    mirroring: u1 = 0,     // Single-screen select (0=lower, 1=upper)

    // Any write to $8000-$FFFF sets bank + mirroring
    // Register format: xxxM xPPP
    //   Bits 0-2: PRG bank
    //   Bit 4: Mirroring (0 = $2000, 1 = $2400)
    pub fn cpuWrite(self: *Mapper7, _: anytype, address: u16, value: u8) void {
        if (address >= 0x8000) {
            self.prg_bank = @truncate(value & 0x07);
            self.mirroring = @truncate((value >> 4) & 0x01);
        }
    }

    // PRG banking: (prg_bank * 0x8000) + (address - 0x8000)
    pub fn cpuRead(_: *const Mapper7, cart: anytype, address: u16) u8 {
        if (address >= 0x8000) {
            const bank_offset: usize = @as(usize, cart.mapper.prg_bank) * 0x8000;
            const addr_offset: usize = @as(usize, address - 0x8000);
            return cart.prg_rom[bank_offset + addr_offset];
        }
        return 0xFF;
    }

    // CHR RAM is writable (unlike CNROM's CHR ROM)
    pub fn ppuWrite(_: *Mapper7, cart: anytype, address: u16, value: u8) void {
        const chr_addr = @as(usize, address & 0x1FFF);
        if (chr_addr < cart.chr_data.len) {
            cart.chr_data[chr_addr] = value;
        }
    }
};
```

**Single-Screen Mirroring:** AxROM provides single-screen mirroring where all 4 nametable addresses ($2000, $2400, $2800, $2C00) map to a single 1KB nametable. Bit 4 of the register selects which nametable:
- 0: Use lower nametable at $2000
- 1: Use upper nametable at $2400

**Bus Conflicts:** AxROM variants handle bus conflicts differently:
- **ANROM/AN1ROM:** Use 74HC02 logic to prevent bus conflicts
- **AMROM/AOROM:** May have bus conflicts (ROM value read during write)

Implementation writes regardless of ROM value for maximum compatibility.

**Test Coverage:** 10 built-in tests
- Power-on state
- PRG bank switching (8 banks)
- Single-screen mirroring switching
- Bank and mirroring together
- Bit masking (3-bit PRG, 1-bit mirror)
- CHR RAM writes (writable)
- Reset behavior
- No PRG RAM support
- IRQ interface stubs

**Available Test ROMs:**
- `tests/data/Cabal (USA).nes`
- `tests/data/Captain Skyhawk (USA) (Rev 1).nes`
- `tests/data/Marble Madness (USA).nes`
- `tests/data/Wizards & Warriors (USA) (Rev 1).nes`

---

### Mapper 2: UxROM

**Status:** ✅ Implemented (2025-10-14)
**Games:** Mega Man, Castlevania, Contra, Duck Tales, Metal Gear, Prince of Persia
**nesdev.org:** https://www.nesdev.org/wiki/UxROM

**Hardware:**
- **PRG ROM:** Up to 256KB (16 banks × 16KB)
  - $8000-$BFFF: 16KB switchable bank (bank select via register)
  - $C000-$FFFF: 16KB fixed to **last bank** (contains reset vector)
- **CHR:** 8KB CHR RAM or CHR ROM (no banking)
- **PRG Banking:** 4-bit register at $8000-$FFFF (bits 0-3)
- **Mirroring:** Fixed by solder pads (H/V, not software-controlled)
- **PRG RAM:** None
- **IRQ:** None

**Implementation:**
```zig
pub const Mapper2 = struct {
    prg_bank: u4 = 0,  // PRG bank select (0-15)

    // Switchable bank: $8000-$BFFF
    pub fn cpuRead(self: *const Mapper2, cart: anytype, address: u16) u8 {
        if (address >= 0x8000 and address < 0xC000) {
            const bank_offset: usize = @as(usize, cart.mapper.prg_bank) * 0x4000;
            const addr_offset: usize = @as(usize, address - 0x8000);
            return cart.prg_rom[bank_offset + addr_offset];
        }

        // Fixed last bank: $C000-$FFFF
        if (address >= 0xC000) {
            const num_banks = (cart.prg_rom.len + 0x3FFF) / 0x4000;
            const last_bank = if (num_banks > 0) num_banks - 1 else 0;
            const bank_offset: usize = last_bank * 0x4000;
            const addr_offset: usize = @as(usize, address - 0xC000);
            return cart.prg_rom[bank_offset + addr_offset];
        }

        return 0xFF;
    }

    // Any write to $8000-$FFFF sets bank (bits 0-3)
    pub fn cpuWrite(self: *Mapper2, _: anytype, address: u16, value: u8) void {
        if (address >= 0x8000) {
            self.prg_bank = @truncate(value & 0x0F);
        }
    }
};
```

**Split Banking Pattern:** UxROM uses a common NES pattern where:
- **Switchable bank** ($8000-$BFFF): Contains level data, graphics, variable code
- **Fixed last bank** ($C000-$FFFF): Contains reset vector ($FFFC-$FFFD), NMI/IRQ vectors, and common routines

This allows games to switch out content while keeping boot code and core routines always accessible.

**CHR RAM vs CHR ROM:** UxROM detects CHR type via header:
- `header.chr_rom_size == 0`: CHR RAM (writable)
- `header.chr_rom_size > 0`: CHR ROM (read-only, writes ignored)

**Bus Conflicts:** Like CNROM, UxROM is subject to bus conflicts where the CPU reads the ROM value during write. Games typically write values that match ROM contents.

**Variants:**
- **UNROM:** 3-bit bank select (8 banks, 128KB)
- **UOROM:** 4-bit bank select (16 banks, 256KB)

Implementation supports full 4-bit register for maximum compatibility.

**Test Coverage:** 11 built-in tests
- Power-on state
- PRG bank switching (switchable area)
- Fixed last bank (always bank 15)
- PRG bank masking (4 bits)
- 128KB ROM (8 banks)
- CHR RAM writes (writable mode)
- CHR ROM writes ignored (read-only mode)
- Reset behavior
- No PRG RAM support
- IRQ interface stubs

**Available Test ROMs:**
- `tests/data/Commando (USA).nes`
- `tests/data/DuckTales (USA).nes`
- `tests/data/Ghosts'n Goblins (USA).nes`
- `tests/data/Guardian Legend, The (USA).nes`
- `tests/data/Gun.Smoke (USA).nes`
- `tests/data/Jackal (USA).nes`
- `tests/data/Life Force (USA) (Rev 1).nes`
- `tests/data/Little Mermaid, The (USA).nes`
- `tests/data/Metal Gear (USA).nes`
- `tests/data/Prince of Persia (USA).nes`
- `tests/data/Rush'n Attack (USA).nes`
- `tests/data/Rygar (USA) (Rev 1).nes`

---

### Mapper 4: MMC3

**Status:** ✅ Implemented (2025-10-14)
**Games:** Super Mario Bros. 3, Mega Man 3-6, Kirby's Adventure, Little Samson, Metal Storm
**nesdev.org:** https://www.nesdev.org/wiki/MMC3

**Hardware:**
- **PRG ROM:** Up to 512KB (64 banks × 8KB)
- **CHR ROM/RAM:** Up to 256KB (256 banks × 1KB)
- **PRG RAM:** 8KB at $6000-$7FFF (optional battery backup)
- **Banking:** 2×8KB PRG switchable, 2×2KB + 4×1KB CHR switchable
- **IRQ:** Scanline counter via PPU A12 edge detection
- **Mirroring:** Software-controlled (H/V)

**Banking Modes:**

*PRG Modes (bit 6 of $8000):*
- **Mode 0:** $8000-$9FFF switchable, $C000-$DFFF fixed to -2nd bank
- **Mode 1:** $C000-$DFFF switchable, $8000-$9FFF fixed to -2nd bank
- **$A000-$BFFF:** Always switchable (R7)
- **$E000-$FFFF:** Always fixed to last bank

*CHR Modes (bit 7 of $8000):*
- **Mode 0:** 2KB banks at $0000-$0FFF, 1KB banks at $1000-$1FFF
- **Mode 1:** 2KB banks at $1000-$1FFF, 1KB banks at $0000-$0FFF

**Implementation:**
```zig
pub const Mapper4 = struct {
    // Bank select register ($8000)
    bank_select: u3 = 0,         // Which register to update (R0-R7)
    prg_mode: bool = false,      // PRG banking mode
    chr_mode: bool = false,      // CHR banking mode
    mirroring_horizontal: bool = false,

    // Bank registers (loaded via $8001)
    chr_banks: [6]u8 = [_]u8{0} ** 6,  // R0-R5: CHR banks
    prg_banks: [2]u8 = [_]u8{0} ** 2,  // R6-R7: PRG banks

    // IRQ scanline counter
    irq_latch: u8 = 0,          // Reload value
    irq_counter: u8 = 0,        // Current counter
    irq_reload: bool = false,   // Reload flag
    irq_enabled: bool = false,  // IRQ enable
    irq_pending: bool = false,  // IRQ pending

    pub fn cpuWrite(self: *Mapper4, cart: anytype, address: u16, value: u8) void {
        if (address >= 0x8000) {
            if ((address & 0x01) == 0) {
                // Even addresses: select register
                if (address < 0xA000) {
                    // $8000: Bank select
                    self.bank_select = @truncate(value & 0x07);
                    self.prg_mode = (value & 0x40) != 0;
                    self.chr_mode = (value & 0x80) != 0;
                } else if (address < 0xC000) {
                    // $A000: Mirroring
                    self.mirroring_horizontal = (value & 0x01) != 0;
                } else if (address < 0xE000) {
                    // $C000: IRQ latch
                    self.irq_latch = value;
                } else {
                    // $E000: IRQ disable
                    self.irq_enabled = false;
                    self.irq_pending = false;
                }
            } else {
                // Odd addresses: load data
                if (address < 0xA000) {
                    // $8001: Bank data
                    switch (self.bank_select) {
                        0...5 => self.chr_banks[self.bank_select] = value,
                        6, 7 => self.prg_banks[self.bank_select - 6] = value & 0x3F,
                    }
                } else if (address < 0xC000) {
                    // $A001: PRG RAM protect
                    self.prg_ram_enabled = (value & 0x80) != 0;
                    self.prg_ram_write_protected = (value & 0x40) != 0;
                } else if (address < 0xE000) {
                    // $C001: IRQ reload
                    self.irq_counter = 0;
                    self.irq_reload = true;
                } else {
                    // $E001: IRQ enable
                    self.irq_enabled = true;
                }
            }
        }
    }

    pub fn ppuA12Rising(self: *Mapper4) void {
        // Decrement counter on A12 rising edge
        if (self.irq_counter == 0 or self.irq_reload) {
            self.irq_counter = self.irq_latch;
            self.irq_reload = false;
        } else {
            self.irq_counter -= 1;
        }

        // Trigger IRQ when counter reaches 0
        if (self.irq_counter == 0 and self.irq_enabled) {
            self.irq_pending = true;
        }
    }
};
```

**IRQ Mechanism:**

MMC3's most complex feature is its scanline counter IRQ used for split-screen effects:

1. **A12 Edge Detection:** IRQ counter decrements on PPU A12 rising edge (0→1)
2. **Scanline Counting:** A12 typically rises 8 times per scanline during rendering
3. **IRQ Trigger:** When counter reaches 0, IRQ is asserted (if enabled)
4. **Reload:** Writing to $C001 resets counter to 0 and sets reload flag
5. **Latch:** Writing to $C000 sets reload value (loaded on next decrement)

**Common Use Cases:**
- **Split-screen scrolling** (Super Mario Bros. 3 status bar)
- **Per-scanline effects** (Mega Man 3-6 pause menu)
- **Raster effects** (changing palettes mid-frame)

**Register Map:**
- `$8000` (even): Bank select + PRG/CHR mode
- `$8001` (odd): Bank data (R0-R7)
- `$A000` (even): Mirroring control
- `$A001` (odd): PRG RAM protect
- `$C000` (even): IRQ latch value
- `$C001` (odd): IRQ reload
- `$E000` (even): IRQ disable
- `$E001` (odd): IRQ enable

**Test Coverage:** 9 built-in tests
- Power-on state
- Bank select register (R0-R7 selection, mode bits)
- Bank data loading (CHR and PRG banks)
- PRG RAM protection (enable/disable, write protect)
- IRQ latch and reload
- IRQ enable/disable
- A12 rising edge counter decrement
- IRQ disabled doesn't trigger
- Reset clears state

**Available Test ROMs:** (37 MMC3 titles found)
- `tests/data/Adventure Island II (USA).nes`
- `tests/data/Bad Dudes (USA).nes`
- `tests/data/Batman - The Video Game (USA).nes`
- `tests/data/Bucky O'Hare (USA).nes`
- `tests/data/Crystalis (USA).nes`
- `tests/data/Dragon Spirit - The New Legend (USA).nes`
- `tests/data/Felix the Cat (USA).nes`
- `tests/data/Fire 'n Ice (USA).nes`
- `tests/data/Flintstones, The - The Rescue of Dino & Hoppy (USA).nes`
- `tests/data/G.I. Joe - A Real American Hero (USA).nes`
- `tests/data/Gargoyle's Quest II (USA).nes`
- `tests/data/Gun Nac (USA).nes`
- `tests/data/KickMaster (USA).nes`
- `tests/data/Kirby's Adventure (USA) (Rev 1).nes` ⭐
- `tests/data/Little Nemo - The Dream Master (USA).nes`
- `tests/data/Little Samson (USA).nes` ⭐
- `tests/data/Metal Storm (USA).nes` ⭐
- `tests/data/Mighty Final Fight (USA).nes`
- `tests/data/Over Horizon (Japan).nes`
- `tests/data/Power Blade (USA).nes`
- `tests/data/Shadow of the Ninja (USA).nes`
- `tests/data/Shadowgate (USA).nes`
- `tests/data/Shatterhand (USA).nes`
- `tests/data/StarTropics (USA).nes`
- `tests/data/Street Fighter 2010 - The Final Fight (USA).nes`
- `tests/data/Tiny Toon Adventures (USA).nes`
- `tests/data/Vice - Project Doom (USA).nes`

---

## Mapper Priority Rationale

**Simplest First (CNROM, AxROM):**
- Quick wins for library coverage
- Establish comptime generic patterns
- Validate test infrastructure

**Popular Mappers Next (UxROM, MMC1, MMC3):**
- MMC1: 28% of NES library (Zelda, Metroid, Mega Man 2)
- MMC3: 25% of NES library (SMB3, Mega Man 3-6)
- UxROM: 10% of NES library (Mega Man, Castlevania)

See `docs/sessions/2025-10-14-mapper-implementation-plan.md` for complete implementation plan.
