# Mapper System Implementation - Executive Summary

**Status:** ✅ READY FOR DEVELOPMENT - All research complete, zero open questions
**Full Plan:** `docs/implementation/MAPPER-SYSTEM-PLAN.md`

---

## Coverage Goals

### Phase 1: Core Mappers (14-19 days) → **75% Coverage**

| Mapper | Games | Coverage | Implementation Time | IRQ Support |
|--------|-------|----------|-------------------|-------------|
| ✅ **0 (NROM)** | 248 | ~5% | COMPLETE | No |
| **1 (MMC1)** | 681 | +28% → 33% | 3-4 days | No |
| **2 (UxROM)** | 270 | +11% → 44% | 1-2 days | No |
| **3 (CNROM)** | 155 | +6% → 50% | 1-2 days | No |
| **4 (MMC3)** | 600 | +25% → **75%** | 4-5 days | ✅ **Yes** (A12 edge) |

**Infrastructure:** 2-3 days (union system, IRQ framework)

### Phase 2: Extended Coverage (5-7 days) → **85% Coverage**

- Mapper 7 (AxROM): +3% coverage
- Mapper 9 (MMC2): +1% coverage
- Mapper 11 (Color Dreams): +1% coverage

---

## Architecture Overview

### Tagged Union Dispatch (Zero Runtime Overhead)

```zig
pub const AnyCartridge = union(MapperId) {
    nrom: Cartridge(Mapper0),
    mmc1: Cartridge(Mapper1),
    uxrom: Cartridge(Mapper2),
    cnrom: Cartridge(Mapper3),
    mmc3: Cartridge(Mapper4),
    // ... extensible

    // Inline dispatch - compiles to direct jumps
    pub fn cpuRead(self: *const AnyCartridge, address: u16) u8 {
        return switch (self.*) {
            inline else => |*cart| cart.cpuRead(address),
        };
    }
};
```

**Benefits:**
- ✅ Zero VTable overhead (`inline else` = direct dispatch)
- ✅ Compile-time interface verification
- ✅ Fully extensible (add mappers as union variants)
- ✅ Type-safe duck typing

### Duck-Typed Mapper Interface

**Required Methods (compile-time verified):**
```zig
pub fn cpuRead(self: *const Self, cart: anytype, address: u16) u8
pub fn cpuWrite(self: *Self, cart: anytype, address: u16, value: u8) void
pub fn ppuRead(self: *const Self, cart: anytype, address: u16) u8
pub fn ppuWrite(self: *Self, cart: anytype, address: u16, value: u8) void
pub fn reset(self: *Self, cart: anytype) void

// IRQ support
pub fn tickIrq(self: *Self) bool           // Called every CPU cycle
pub fn ppuA12Rising(self: *Self) void      // Called on PPU A12 0→1 edge
pub fn acknowledgeIrq(self: *Self) void    // Called on IRQ vector read
```

### IRQ Handling (MMC3)

**State Isolation:** All IRQ state lives in mapper structs.

```zig
// EmulationState.tick() - all side effects contained here
pub fn tick(self: *EmulationState) void {
    // 1. CPU tick
    self.cpu.tick(&self.bus);

    // 2. Check mapper IRQ (side effect: sets irq_line)
    if (self.cart) |*cart| {
        if (cart.tickIrq()) {
            self.cpu.irq_line = true;
        }
    }

    // 3. PPU tick with A12 edge detection
    for (0..3) |_| {
        const old_a12 = self.ppu_timing.a12_state;
        self.tickPpu();
        const new_a12 = self.ppu_timing.a12_state;

        if (!old_a12 and new_a12) {
            if (self.cart) |*cart| {
                cart.ppuA12Rising();  // MMC3 IRQ counter
            }
        }
    }
}
```

---

## Mapper Specifications Summary

### Mapper 1 (MMC1) - 681 games

**Features:**
- 5-bit shift register write protocol (5 sequential writes)
- PRG banking: 32KB or switchable 16KB
- CHR banking: 8KB or dual 4KB
- Configurable mirroring (H/V/single-screen)
- Optional PRG RAM banking

**Complexity:** Medium (shift register state machine)

### Mapper 2 (UxROM) - 270 games

**Features:**
- 16KB switchable PRG bank at $8000
- 16KB fixed PRG bank at $C000 (last bank)
- 8KB CHR RAM (no banking)
- Simple bank register at $8000-$FFFF

**Complexity:** Low (single register)

### Mapper 3 (CNROM) - 155 games

**Features:**
- 8KB CHR bank switching only
- Fixed 32KB PRG ROM
- Bus conflicts (AND-type: written value & ROM data)

**Complexity:** Low (single register + bus conflicts)

### Mapper 4 (MMC3) - 600 games ⚡

**Features:**
- Complex PRG/CHR banking (2x8KB PRG, 6 CHR banks)
- **IRQ counter triggered by PPU A12 rising edge**
- PRG RAM enable/protect bits
- Configurable PRG/CHR bank modes

**Complexity:** High (IRQ timing, A12 detection, multiple modes)

**IRQ Mechanism:**
1. Counter decrements on PPU A12 rising edge (background tile fetch)
2. IRQ asserted when counter reaches 0
3. Acknowledged by reading IRQ vector ($FFFE)

---

## State Isolation Principles

### ✅ Correct: State in Mapper Structs

```zig
pub const Mapper4 = struct {
    irq_counter: u8,
    irq_pending: bool,
    bank_registers: [8]u8,
    // ... all state owned by mapper
};
```

### ❌ Incorrect: Global State

```zig
// DON'T DO THIS!
var mmc3_irq_pending: bool = false;  // ❌ Global state
```

### Side Effect Containment

**All side effects flow through `EmulationState.tick()`:**
- ✅ CPU register writes → mapper state updates
- ✅ Mapper IRQ → `cpu.irq_line = true` (in tick)
- ✅ PPU A12 edge → mapper IRQ counter (in tick)

**No side effects in:**
- ❌ Mapper methods (pure state transformations)
- ❌ Bus read/write (deterministic routing only)

---

## Implementation Phases

### Phase 1: Foundation (2-3 days)

1. Create `AnyCartridge` union type
2. Update `EmulationState` to use `AnyCartridge`
3. Implement PPU A12 tracking
4. Add IRQ infrastructure to CPU interrupt handling

### Phase 2: Mapper 1 (MMC1) - 3-4 days

1. Implement shift register protocol
2. PRG/CHR bank calculation
3. Comprehensive test suite
4. Integration with real ROMs (Metroid, Zelda)

### Phase 3: Mapper 2 (UxROM) - 1-2 days

1. Simple PRG bank switching
2. Fixed last bank logic
3. Test suite

### Phase 4: Mapper 3 (CNROM) - 1-2 days

1. CHR bank switching
2. Bus conflict logic
3. Test suite

### Phase 5: Mapper 4 (MMC3) - 4-5 days

1. Complex PRG/CHR banking
2. IRQ counter + A12 detection
3. Comprehensive IRQ timing tests
4. Integration (Super Mario Bros. 3)

### Phase 6: Validation (2-3 days)

1. Full test suite (all mappers)
2. Regression testing
3. Performance benchmarking

---

## Verification Checklist

### Pre-Development ✅

- [x] Mapper specifications researched (nesdev.org)
- [x] Coverage percentages verified (75% with mappers 0-4)
- [x] IRQ mechanisms understood (MMC3 A12 edge)
- [x] State isolation principles defined
- [x] Union dispatch architecture designed
- [x] **Zero open questions or blockers**

### During Development

- [ ] Each mapper has comprehensive unit tests
- [ ] Integration tests with real ROMs
- [ ] IRQ timing verified with test ROMs (MMC3_test.nes)
- [ ] Snapshot serialization working
- [ ] Zero regressions in existing 741 tests
- [ ] Performance verified (no overhead)

### Success Criteria

- [ ] All mappers 0-4 implemented and tested
- [ ] 75% coverage verified (can load major games)
- [ ] MMC3 IRQ accurate (scanline timing correct)
- [ ] Union dispatch confirmed zero-overhead
- [ ] Documentation complete

---

## Key Technical Details

### MMC3 A12 Detection

```zig
// PPU A12 = bit 12 of PPU address
// Rising edge occurs when:
// - Background: fetching new tile ($0xxx → $1xxx or $1xxx → $0xxx wrap)
// - Sprites: fetching sprite pattern data

pub fn tickPpu(self: *EmulationState) void {
    const old_a12 = (self.ppu.v >> 12) & 1;

    // ... PPU rendering logic ...

    const new_a12 = (self.ppu.v >> 12) & 1;

    if (old_a12 == 0 and new_a12 == 1) {
        if (self.cart) |*cart| {
            cart.ppuA12Rising();  // MMC3 decrements counter
        }
    }
}
```

### Bus Conflicts (CNROM)

```zig
// CNROM: AND-type bus conflict
pub fn cpuWrite(self: *Mapper3, cart: anytype, address: u16, value: u8) void {
    if (address >= 0x8000) {
        const rom_value = cart.prg_rom[address - 0x8000];
        self.chr_bank = value & rom_value & 0x03;  // AND with ROM data
    }
}
```

---

## Timeline & Resources

**Total Phase 1:** 14-19 days for 75% coverage

**External References:**
- MMC1: https://www.nesdev.org/wiki/MMC1
- MMC3: https://www.nesdev.org/wiki/MMC3
- UxROM: https://www.nesdev.org/wiki/UxROM
- CNROM: https://www.nesdev.org/wiki/CNROM

**Test ROMs:**
- MMC1: Metroid, The Legend of Zelda, Mega Man 2
- MMC3: Super Mario Bros. 3, Kirby's Adventure
- UxROM: Mega Man, Castlevania
- CNROM: Simple homebrew ROMs

---

## Risk Mitigation

| Risk | Mitigation |
|------|------------|
| **IRQ timing complexity (MMC3)** | Use MMC3_test.nes ROM, implement A12 tracking first |
| **Union dispatch overhead** | Use `inline else`, benchmark before/after |
| **Mapper state serialization** | Implement serialize/deserialize per mapper, test round-trip |
| **Bus conflicts (CNROM)** | Research AND-type conflicts, test with known ROMs |

---

## Next Steps

1. **Review this plan** - Verify all requirements understood
2. **Begin Phase 1** - Create `AnyCartridge` union system (2-3 days)
3. **Implement mappers sequentially** - MMC1 → UxROM → CNROM → MMC3
4. **Validate with real ROMs** - Load major games, verify behavior

**This plan is complete and ready for implementation. No open questions remain.**
