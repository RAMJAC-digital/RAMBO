# NES Mapper System - Complete Implementation Plan

**Status:** READY FOR IMPLEMENTATION
**Priority:** HIGH - Enables 75%+ of NES game library
**Last Updated:** 2025-10-06

---

## Executive Summary

This plan details the complete implementation of a duck-typed mapper system with tagged union dispatch, covering **75% of licensed NES games** with mappers 0-4. The architecture maintains state isolation, deterministic execution, and zero hot-path allocations while supporting advanced features like MMC3 IRQ generation.

### Coverage Goals

**Phase 1 - Core Mappers (75% coverage):**
- ✅ **Mapper 0 (NROM)**: 248 games (~5%) - COMPLETE with PRG RAM
- **Mapper 1 (MMC1)**: 681 games (~28%) → Cumulative: **33%**
- **Mapper 2 (UxROM)**: 270 games (~11%) → Cumulative: **44%**
- **Mapper 3 (CNROM)**: 155 games (~6%) → Cumulative: **50%**
- **Mapper 4 (MMC3)**: 600 games (~25%) → Cumulative: **75%**

**Phase 2 - Extended Coverage (85% coverage):**
- **Mapper 7 (AxROM)**: 76 games (~3%) → Cumulative: **78%**
- **Mapper 9 (MMC2)**: ~20 games
- **Mapper 11 (Color Dreams)**: ~30 games
- Additional mappers as needed

---

## 1. Architecture Design

### 1.1 Duck-Typed Mapper Interface

Each mapper implements a **compile-time verified interface** using Zig's `anytype`:

```zig
// Required methods (duck-typed, no VTable):
pub fn cpuRead(self: *const Self, cart: anytype, address: u16) u8
pub fn cpuWrite(self: *Self, cart: anytype, address: u16, value: u8) void
pub fn ppuRead(self: *const Self, cart: anytype, address: u16) u8
pub fn ppuWrite(self: *Self, cart: anytype, address: u16, value: u8) void
pub fn reset(self: *Self, cart: anytype) void

// IRQ support (returns true if IRQ should be asserted):
pub fn tickIrq(self: *Self) bool             // Called every CPU cycle
pub fn ppuA12Rising(self: *Self) void        // Called on PPU A12 0→1 transition (MMC3)
pub fn acknowledgeIrq(self: *Self) void      // Called when CPU reads IRQ vector

// Serialization (for snapshots):
pub fn serializeState(self: *const Self, writer: anytype) !void
pub fn deserializeState(self: *Self, reader: anytype) !void
pub fn stateSize(self: *const Self) usize
```

### 1.2 Tagged Union Dispatch

**Central Cartridge Type:**

```zig
// src/cartridge/AnyCartridge.zig
pub const MapperId = enum(u8) {
    nrom = 0,
    mmc1 = 1,
    uxrom = 2,
    cnrom = 3,
    mmc3 = 4,
    mmc5 = 5,    // Future
    axrom = 7,   // Future
    mmc2 = 9,    // Future
    // ... extensible
};

pub const AnyCartridge = union(MapperId) {
    nrom: Cartridge(Mapper0),
    mmc1: Cartridge(Mapper1),
    uxrom: Cartridge(Mapper2),
    cnrom: Cartridge(Mapper3),
    mmc3: Cartridge(Mapper4),
    mmc5: Cartridge(Mapper5),
    axrom: Cartridge(Mapper7),
    mmc2: Cartridge(Mapper9),

    // Unified interface methods (inline switch)
    pub fn cpuRead(self: *const AnyCartridge, address: u16) u8 {
        return switch (self.*) {
            inline else => |*cart| cart.cpuRead(address),
        };
    }

    pub fn cpuWrite(self: *AnyCartridge, address: u16, value: u8) void {
        switch (self.*) {
            inline else => |*cart| cart.cpuWrite(address, value),
        }
    }

    pub fn ppuRead(self: *const AnyCartridge, address: u16) u8 {
        return switch (self.*) {
            inline else => |*cart| cart.ppuRead(address),
        };
    }

    pub fn ppuWrite(self: *AnyCartridge, address: u16, value: u8) void {
        switch (self.*) {
            inline else => |*cart| cart.ppuWrite(address, value),
        }
    }

    pub fn tickIrq(self: *AnyCartridge) bool {
        return switch (self.*) {
            inline else => |*cart| cart.mapper.tickIrq(),
        };
    }

    pub fn ppuA12Rising(self: *AnyCartridge) void {
        switch (self.*) {
            inline else => |*cart| cart.mapper.ppuA12Rising(),
        }
    }

    pub fn reset(self: *AnyCartridge) void {
        switch (self.*) {
            inline else => |*cart| cart.reset(),
        }
    }

    pub fn deinit(self: *AnyCartridge) void {
        switch (self.*) {
            inline else => |*cart| cart.deinit(),
        }
    }
};
```

**Key Benefits:**
- ✅ **Zero runtime overhead**: `inline else` compiles to direct dispatch
- ✅ **Type safety**: Compile-time verification of all mapper interfaces
- ✅ **Extensibility**: Adding mappers is a simple union variant addition
- ✅ **No VTables**: No dynamic dispatch, fully predictable branches

### 1.3 IRQ Handling Architecture

**State Isolation Principle**: IRQ state lives in mapper structs, **not** in global state.

```zig
// src/emulation/State.zig
pub const EmulationState = struct {
    cpu: CpuState,
    cart: ?AnyCartridge,

    // ... other components

    pub fn tick(self: *EmulationState) void {
        // 1. Tick CPU (executes one cycle)
        self.cpu.tick(&self.bus);

        // 2. Check mapper IRQ (called every CPU cycle)
        if (self.cart) |*cart| {
            if (cart.tickIrq()) {
                self.cpu.irq_line = true;  // Assert IRQ
            }
        }

        // 3. Tick PPU (3 PPU cycles per CPU cycle)
        for (0..3) |_| {
            const old_a12 = self.ppu_timing.a12_state;
            self.tickPpu();
            const new_a12 = self.ppu_timing.a12_state;

            // 4. Notify mapper of PPU A12 rising edge (MMC3 IRQ)
            if (!old_a12 and new_a12) {
                if (self.cart) |*cart| {
                    cart.ppuA12Rising();
                }
            }
        }

        // 5. APU/DMC ticking...
    }
};
```

**IRQ Acknowledgment (MMC3):**

```zig
// In CPU interrupt handling (src/cpu/Logic.zig)
pub fn handleInterrupt(cpu: *CpuState, bus: *BusState, irq_type: InterruptType) void {
    // ... standard IRQ/NMI sequence ...

    // Acknowledge mapper IRQ when reading interrupt vector
    if (irq_type == .irq and bus.cart) |*cart| {
        cart.acknowledgeIrq();
        cpu.irq_line = false;  // Clear IRQ line
    }
}
```

---

## 2. Mapper Specifications

### 2.1 Mapper 1 (MMC1) - 681 games

**Key Features:**
- 5-bit serial shift register write protocol
- PRG banking: 32KB or 16KB switchable
- CHR banking: 8KB or dual 4KB
- Configurable mirroring (H/V/single-screen)
- Optional PRG RAM banking

**State Structure:**

```zig
// src/cartridge/mappers/Mapper1.zig
pub const Mapper1 = struct {
    // Shift register state
    shift_register: u8 = 0x10,  // Bit 4 set = ready for first write
    write_count: u3 = 0,

    // Control register ($8000-$9FFF)
    control: u8 = 0x0C,  // Default: 16KB PRG mode, last bank fixed

    // CHR bank registers ($A000-$BFFF, $C000-$DFFF)
    chr_bank_0: u8 = 0,
    chr_bank_1: u8 = 0,

    // PRG bank register ($E000-$FFFF)
    prg_bank: u8 = 0,

    // Computed bank offsets (cached for performance)
    prg_offset_low: usize = 0,
    prg_offset_high: usize = 0,
    chr_offset_0: usize = 0,
    chr_offset_1: usize = 0,

    pub fn cpuWrite(self: *Mapper1, cart: anytype, address: u16, value: u8) void {
        if (value & 0x80 != 0) {
            // Reset shift register
            self.shift_register = 0x10;
            self.write_count = 0;
            self.control |= 0x0C;  // Set PRG mode to 3
            self.updateBankOffsets(cart);
            return;
        }

        // Shift in bit 0
        self.shift_register >>= 1;
        self.shift_register |= (value & 1) << 4;
        self.write_count += 1;

        if (self.write_count == 5) {
            // 5th write - commit to register
            const reg_value = self.shift_register;
            self.shift_register = 0x10;
            self.write_count = 0;

            switch (address & 0xE000) {
                0x8000 => {  // Control
                    self.control = reg_value;
                    self.updateBankOffsets(cart);
                },
                0xA000 => {  // CHR bank 0
                    self.chr_bank_0 = reg_value;
                    self.updateBankOffsets(cart);
                },
                0xC000 => {  // CHR bank 1
                    self.chr_bank_1 = reg_value;
                    self.updateBankOffsets(cart);
                },
                0xE000 => {  // PRG bank
                    self.prg_bank = reg_value & 0x0F;
                    self.updateBankOffsets(cart);
                },
                else => {},
            }
        }
    }

    fn updateBankOffsets(self: *Mapper1, cart: anytype) void {
        const prg_mode = (self.control >> 2) & 0x03;
        const chr_mode = (self.control >> 4) & 0x01;

        // PRG banking
        const prg_bank_count = cart.prg_rom.len / 0x4000;  // Number of 16KB banks
        switch (prg_mode) {
            0, 1 => {  // 32KB mode
                const bank = (self.prg_bank >> 1) % prg_bank_count;
                self.prg_offset_low = bank * 0x8000;
                self.prg_offset_high = bank * 0x8000 + 0x4000;
            },
            2 => {  // Fix first bank, switch $C000
                self.prg_offset_low = 0;
                self.prg_offset_high = (self.prg_bank % prg_bank_count) * 0x4000;
            },
            3 => {  // Switch $8000, fix last bank
                self.prg_offset_low = (self.prg_bank % prg_bank_count) * 0x4000;
                self.prg_offset_high = (prg_bank_count - 1) * 0x4000;
            },
            else => unreachable,
        }

        // CHR banking
        const chr_bank_count = cart.chr_data.len / 0x1000;  // Number of 4KB banks
        if (chr_mode == 0) {  // 8KB mode
            const bank = (self.chr_bank_0 >> 1) % chr_bank_count;
            self.chr_offset_0 = bank * 0x2000;
            self.chr_offset_1 = bank * 0x2000 + 0x1000;
        } else {  // Two 4KB banks
            self.chr_offset_0 = (self.chr_bank_0 % chr_bank_count) * 0x1000;
            self.chr_offset_1 = (self.chr_bank_1 % chr_bank_count) * 0x1000;
        }
    }

    // No IRQ support
    pub fn tickIrq(self: *Mapper1) bool { return false; }
    pub fn ppuA12Rising(self: *Mapper1) void {}
    pub fn acknowledgeIrq(self: *Mapper1) void {}
};
```

### 2.2 Mapper 2 (UxROM) - 270 games

**Key Features:**
- Simple 16KB PRG bank switching
- Fixed CHR (8KB RAM, no banking)
- Last PRG bank fixed at $C000

**State Structure:**

```zig
// src/cartridge/mappers/Mapper2.zig
pub const Mapper2 = struct {
    prg_bank: u8 = 0,

    pub fn cpuRead(self: *const Mapper2, cart: anytype, address: u16) u8 {
        return switch (address) {
            0x6000...0x7FFF => if (cart.prg_ram) |ram| ram[address - 0x6000] else 0xFF,
            0x8000...0xBFFF => {
                const bank_count = cart.prg_rom.len / 0x4000;
                const offset = (self.prg_bank % bank_count) * 0x4000;
                return cart.prg_rom[offset + (address - 0x8000)];
            },
            0xC000...0xFFFF => {
                const bank_count = cart.prg_rom.len / 0x4000;
                const offset = (bank_count - 1) * 0x4000;  // Last bank
                return cart.prg_rom[offset + (address - 0xC000)];
            },
            else => 0xFF,
        };
    }

    pub fn cpuWrite(self: *Mapper2, cart: anytype, address: u16, value: u8) void {
        switch (address) {
            0x6000...0x7FFF => if (cart.prg_ram) |ram| ram[address - 0x6000] = value,
            0x8000...0xFFFF => self.prg_bank = value & 0x0F,
            else => {},
        }
    }

    // No IRQ support
    pub fn tickIrq(self: *Mapper2) bool { return false; }
    pub fn ppuA12Rising(self: *Mapper2) void {}
    pub fn acknowledgeIrq(self: *Mapper2) void {}
};
```

### 2.3 Mapper 3 (CNROM) - 155 games

**Key Features:**
- 8KB CHR bank switching only
- Fixed 32KB PRG ROM
- Bus conflicts (AND-type)

**State Structure:**

```zig
// src/cartridge/mappers/Mapper3.zig
pub const Mapper3 = struct {
    chr_bank: u8 = 0,

    pub fn cpuWrite(self: *Mapper3, cart: anytype, address: u16, value: u8) void {
        if (address >= 0x8000) {
            // Bus conflict: AND written value with ROM data
            const rom_value = cart.prg_rom[address - 0x8000];
            self.chr_bank = value & rom_value & 0x03;
        }
    }

    pub fn ppuRead(self: *const Mapper3, cart: anytype, address: u16) u8 {
        const chr_addr = address & 0x1FFF;
        const bank_count = cart.chr_data.len / 0x2000;
        const offset = (self.chr_bank % bank_count) * 0x2000;
        return cart.chr_data[offset + chr_addr];
    }

    // No IRQ support
    pub fn tickIrq(self: *Mapper3) bool { return false; }
    pub fn ppuA12Rising(self: *Mapper3) void {}
    pub fn acknowledgeIrq(self: *Mapper3) void {}
};
```

### 2.4 Mapper 4 (MMC3) - 600 games ⚡ WITH IRQ

**Key Features:**
- Complex PRG/CHR banking (2x8KB PRG, 6 CHR banks)
- **IRQ counter triggered by PPU A12 rising edge**
- PRG RAM enable/protect
- Configurable PRG/CHR bank modes

**State Structure:**

```zig
// src/cartridge/mappers/Mapper4.zig
pub const Mapper4 = struct {
    // Bank select and data
    bank_select: u8 = 0,
    bank_registers: [8]u8 = [_]u8{0} ** 8,

    // Mirroring and PRG RAM
    mirroring: u8 = 0,
    prg_ram_protect: u8 = 0,

    // IRQ state
    irq_latch: u8 = 0,
    irq_counter: u8 = 0,
    irq_reload: bool = false,
    irq_enabled: bool = false,
    irq_pending: bool = false,

    // A12 edge detection (for IRQ)
    last_a12: bool = false,

    pub fn cpuWrite(self: *Mapper4, cart: anytype, address: u16, value: u8) void {
        switch (address & 0xE001) {
            0x8000 => self.bank_select = value,
            0x8001 => {
                const reg = self.bank_select & 0x07;
                self.bank_registers[reg] = value;
            },
            0xA000 => self.mirroring = value & 0x01,
            0xA001 => self.prg_ram_protect = value,
            0xC000 => self.irq_latch = value,
            0xC001 => self.irq_reload = true,
            0xE000 => {
                self.irq_enabled = false;
                self.irq_pending = false;
            },
            0xE001 => self.irq_enabled = true,
            else => {},
        }
    }

    pub fn ppuA12Rising(self: *Mapper4) void {
        // IRQ counter decrements on A12 rising edge
        if (self.irq_counter == 0 or self.irq_reload) {
            self.irq_counter = self.irq_latch;
            self.irq_reload = false;
        } else {
            self.irq_counter -= 1;
        }

        if (self.irq_counter == 0 and self.irq_enabled) {
            self.irq_pending = true;
        }
    }

    pub fn tickIrq(self: *Mapper4) bool {
        return self.irq_pending;
    }

    pub fn acknowledgeIrq(self: *Mapper4) void {
        self.irq_pending = false;
    }

    pub fn cpuRead(self: *const Mapper4, cart: anytype, address: u16) u8 {
        return switch (address) {
            0x6000...0x7FFF => blk: {
                if (self.prg_ram_protect & 0x80 != 0) {
                    if (cart.prg_ram) |ram| break :blk ram[address - 0x6000];
                }
                break :blk 0xFF;  // Open bus
            },
            0x8000...0x9FFF => blk: {
                const prg_mode = (self.bank_select >> 6) & 0x01;
                const bank = if (prg_mode == 0) self.bank_registers[6] else @as(u8, @intCast(cart.prg_rom.len / 0x2000 - 2));
                const offset = (bank % (cart.prg_rom.len / 0x2000)) * 0x2000;
                break :blk cart.prg_rom[offset + (address - 0x8000)];
            },
            0xA000...0xBFFF => blk: {
                const bank = self.bank_registers[7];
                const offset = (bank % (cart.prg_rom.len / 0x2000)) * 0x2000;
                break :blk cart.prg_rom[offset + (address - 0xA000)];
            },
            0xC000...0xDFFF => blk: {
                const prg_mode = (self.bank_select >> 6) & 0x01;
                const bank = if (prg_mode == 1) self.bank_registers[6] else @as(u8, @intCast(cart.prg_rom.len / 0x2000 - 2));
                const offset = (bank % (cart.prg_rom.len / 0x2000)) * 0x2000;
                break :blk cart.prg_rom[offset + (address - 0xC000)];
            },
            0xE000...0xFFFF => blk: {
                const last_bank = cart.prg_rom.len / 0x2000 - 1;
                const offset = last_bank * 0x2000;
                break :blk cart.prg_rom[offset + (address - 0xE000)];
            },
            else => 0xFF,
        };
    }

    pub fn ppuRead(self: *const Mapper4, cart: anytype, address: u16) u8 {
        const chr_addr = address & 0x1FFF;
        const chr_mode = (self.bank_select >> 7) & 0x01;

        const bank_num: u8 = if (chr_mode == 0) {
            // Normal mode
            switch (chr_addr) {
                0x0000...0x07FF => self.bank_registers[0] & 0xFE,
                0x0800...0x0FFF => self.bank_registers[0] | 0x01,
                0x1000...0x13FF => self.bank_registers[2],
                0x1400...0x17FF => self.bank_registers[3],
                0x1800...0x1BFF => self.bank_registers[4],
                0x1C00...0x1FFF => self.bank_registers[5],
                else => 0,
            }
        } else {
            // Inverted mode
            switch (chr_addr) {
                0x0000...0x03FF => self.bank_registers[2],
                0x0400...0x07FF => self.bank_registers[3],
                0x0800...0x0BFF => self.bank_registers[4],
                0x0C00...0x0FFF => self.bank_registers[5],
                0x1000...0x17FF => self.bank_registers[0] & 0xFE,
                0x1800...0x1FFF => self.bank_registers[0] | 0x01,
                else => 0,
            }
        };

        const bank_count = cart.chr_data.len / 0x0400;
        const bank = bank_num % bank_count;
        const offset = bank * 0x0400;
        return cart.chr_data[offset + (chr_addr % 0x0400)];
    }
};
```

---

## 3. Implementation Phases

### Phase 1: Foundation (2-3 days)

**Tasks:**

1. **Create Union Type System** (`src/cartridge/AnyCartridge.zig`)
   - Define `MapperId` enum
   - Define `AnyCartridge` tagged union
   - Implement inline dispatch methods
   - Create factory function `loadFromData(allocator, rom_data) !AnyCartridge`

2. **Update EmulationState Integration** (`src/emulation/State.zig`)
   - Change `cart: ?NromCart` → `cart: ?AnyCartridge`
   - Add PPU A12 tracking state
   - Implement `ppuA12Rising()` detection logic
   - Add mapper IRQ checking in `tick()`

3. **IRQ Infrastructure** (`src/cpu/Logic.zig`)
   - Add `acknowledgeIrq()` call in interrupt handling
   - Ensure IRQ line clearing on acknowledgment

### Phase 2: Mapper 1 (MMC1) - 3-4 days

**Tasks:**

1. **Implement Mapper1.zig**
   - Shift register write protocol
   - PRG/CHR bank calculation
   - Mirroring control
   - PRG RAM banking (optional)

2. **Create Test Suite** (`tests/cartridge/mapper1_test.zig`)
   - Shift register protocol tests (5 writes, reset on bit 7)
   - Bank switching tests (all PRG modes)
   - CHR bank switching
   - Mirroring mode tests

3. **Integration Tests**
   - Load known MMC1 ROM (e.g., Metroid, Zelda)
   - Verify bank switching behavior

### Phase 3: Mapper 2 (UxROM) - 1-2 days

**Tasks:**

1. **Implement Mapper2.zig**
   - Simple PRG bank switching
   - Fixed last bank logic

2. **Test Suite** (`tests/cartridge/mapper2_test.zig`)
   - Bank switching tests
   - Last bank fixed verification
   - Bus conflict variant tests (optional)

### Phase 4: Mapper 3 (CNROM) - 1-2 days

**Tasks:**

1. **Implement Mapper3.zig**
   - CHR bank switching
   - Bus conflict logic (AND-type)

2. **Test Suite** (`tests/cartridge/mapper3_test.zig`)
   - CHR bank switching
   - Bus conflict behavior verification

### Phase 5: Mapper 4 (MMC3) - 4-5 days ⚡

**Tasks:**

1. **Implement Mapper4.zig**
   - Complex PRG/CHR banking
   - IRQ counter mechanism
   - A12 edge detection
   - PRG RAM protect

2. **PPU A12 Detection** (`src/ppu/Logic.zig`)
   - Track A12 state (bit 12 of PPU address)
   - Detect 0→1 transitions
   - Call `cart.ppuA12Rising()` on rising edge

3. **Test Suite** (`tests/cartridge/mapper4_test.zig`)
   - PRG/CHR banking modes
   - IRQ counter behavior
   - A12 edge detection
   - IRQ acknowledgment
   - Scanline IRQ timing tests

4. **Integration Tests**
   - Load MMC3 ROM (Super Mario Bros. 3)
   - Verify IRQ timing
   - Test status bar splits

### Phase 6: Testing & Validation (2-3 days)

**Tasks:**

1. **Comprehensive Test Suite**
   - All mapper unit tests
   - Integration tests with real ROMs
   - Snapshot save/load with mapper state

2. **Regression Testing**
   - Ensure all existing tests pass
   - Verify no timing regressions

3. **Performance Validation**
   - Benchmark union dispatch overhead (should be zero)
   - Profile hot paths

---

## 4. State Isolation & Side Effects

### 4.1 State Ownership

**Principle:** All mapper state lives in mapper structs, not in global/shared state.

```zig
// ✅ CORRECT: State in mapper struct
pub const Mapper4 = struct {
    irq_counter: u8,
    irq_pending: bool,
    // ...
};

// ❌ WRONG: Global state
var mmc3_irq_pending: bool = false;  // NO!
```

### 4.2 Side Effect Containment

**All side effects go through EmulationState.tick():**

```zig
pub fn tick(self: *EmulationState) void {
    // 1. CPU tick (may write to registers)
    self.cpu.tick(&self.bus);

    // 2. Check mapper IRQ (side effect: sets cpu.irq_line)
    if (self.cart) |*cart| {
        if (cart.tickIrq()) {
            self.cpu.irq_line = true;  // ✅ Side effect contained in tick()
        }
    }

    // 3. PPU tick with A12 detection
    for (0..3) |_| {
        const old_a12 = self.ppu_timing.a12_state;
        self.tickPpu();
        const new_a12 = self.ppu_timing.a12_state;

        if (!old_a12 and new_a12) {
            if (self.cart) |*cart| {
                cart.ppuA12Rising();  // ✅ Side effect: updates mapper IRQ counter
            }
        }
    }
}
```

### 4.3 Determinism Guarantees

**Requirements:**
- ✅ All mapper state transitions are deterministic (no randomness)
- ✅ No external I/O in hot path (file/network)
- ✅ No heap allocations after initialization
- ✅ IRQ timing based on cycle-accurate PPU A12 detection

---

## 5. Verification Checklist

### Pre-Development

- [x] Mapper specifications researched (nesdev.org)
- [x] Coverage percentages calculated (75% with mappers 0-4)
- [x] IRQ mechanisms understood (MMC3 A12 edge detection)
- [x] State isolation principles defined
- [x] Union dispatch architecture designed
- [x] No open questions or blockers identified

### During Development

- [ ] Each mapper has comprehensive unit tests
- [ ] Integration tests with real ROMs
- [ ] IRQ timing verified with test ROMs
- [ ] Snapshot serialization working
- [ ] Zero regressions in existing tests
- [ ] Performance benchmarks (no overhead)

### Post-Development

- [ ] All mappers 0-4 implemented
- [ ] 75% coverage verified with ROM database
- [ ] Documentation updated (CLAUDE.md, nesdev references)
- [ ] Future mapper stubs created (5, 7, 9)

---

## 6. Risk Mitigation

### Risk 1: IRQ Timing Complexity (MMC3)

**Mitigation:**
- Implement PPU A12 tracking first, verify with tests
- Use known test ROMs (MMC3_test) for validation
- Document A12 detection logic clearly

### Risk 2: Union Dispatch Overhead

**Mitigation:**
- Use `inline else` for zero-cost dispatch
- Benchmark before/after implementation
- Profile hot paths to verify no regressions

### Risk 3: Mapper State Serialization

**Mitigation:**
- Implement `serializeState/deserializeState` for each mapper
- Test snapshot round-trip for each mapper
- Document state blob formats

### Risk 4: Bus Conflicts (CNROM, some UxROM)

**Mitigation:**
- Implement AND-type bus conflicts for CNROM
- Add submapper variants for UxROM (with/without conflicts)
- Test with ROMs known to use bus conflicts

---

## 7. Dependencies & References

### External Resources

- **Nesdev Wiki Mapper List**: https://www.nesdev.org/wiki/Mapper
- **MMC1 Spec**: https://www.nesdev.org/wiki/MMC1
- **MMC3 Spec**: https://www.nesdev.org/wiki/MMC3
- **UxROM Spec**: https://www.nesdev.org/wiki/UxROM
- **CNROM Spec**: https://www.nesdev.org/wiki/CNROM
- **IRQ Timing**: https://www.nesdev.org/wiki/MMC3#IRQ_Specifics

### Test ROMs

- **MMC1**: Metroid, Zelda, Mega Man series
- **MMC3**: Super Mario Bros. 3, Kirby's Adventure
- **UxROM**: Mega Man, Castlevania
- **CNROM**: Simple homebrew ROMs

---

## 8. Estimated Timeline

**Total Time: 14-19 days for 75% coverage**

| Phase | Duration | Coverage |
|-------|----------|----------|
| Foundation & Union System | 2-3 days | Infrastructure |
| Mapper 1 (MMC1) | 3-4 days | +28% → 33% |
| Mapper 2 (UxROM) | 1-2 days | +11% → 44% |
| Mapper 3 (CNROM) | 1-2 days | +6% → 50% |
| Mapper 4 (MMC3) | 4-5 days | +25% → 75% |
| Testing & Validation | 2-3 days | Verification |

**Future Phases (85%+ coverage):** 5-7 additional days

---

## 9. Success Criteria

✅ **Phase 1 Complete When:**
- All mappers 0-4 implemented and tested
- 741+ tests passing (no regressions)
- Snapshot system supports all mappers
- IRQ timing accurate (MMC3 test ROM passing)
- Union dispatch verified zero-overhead
- Documentation complete

✅ **Coverage Verification:**
- Load 10+ games per mapper
- Verify correct behavior (no graphical glitches, timing issues)
- AccuracyCoin test extraction working (uses NROM with PRG RAM)

---

**This plan is ready for implementation. All research complete, architecture designed, no open questions.**
