# NES Mapper Implementations

**Status:** ✅ 3/6 mappers implemented (13% library coverage)
**Priority:** HIGH (game compatibility)
**Reference:** `docs/sessions/2025-10-14-mapper-implementation-plan.md`, `CLAUDE.md`

## Overview

Mapper implementations for RAMBO NES Emulator using comptime generics.

**Implemented Mappers:**
- ✅ **Mapper 0 (NROM)** - `src/cartridge/mappers/Mapper0.zig` - 5% coverage (248 games)
- ✅ **Mapper 3 (CNROM)** - `src/cartridge/mappers/Mapper3.zig` - 6% coverage (155 games)
- ✅ **Mapper 7 (AxROM)** - `src/cartridge/mappers/Mapper7.zig` - 2% coverage (~50 games)

**Total Coverage:** 13% of NES library (~453 games)

**Planned Mappers** (priority order):
1. **UxROM** (Mapper 2) - 10% coverage, 4-6 hours
2. **MMC1** (Mapper 1) - 28% coverage, 6-8 hours
3. **MMC3** (Mapper 4) - 25% coverage, 12-16 hours

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
