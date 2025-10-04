# Design Decision: Memory Bus Implementation

**Date:** 2025-10-02
**Status:** Accepted
**Component:** Memory Bus

## Context

The NES memory bus is critical for cycle-accurate emulation. AccuracyCoin test suite validates:
- RAM mirroring behavior
- Open bus behavior (data bus retention)
- ROM write protection
- Dummy read/write cycles

## Decision

Implemented a comprehensive memory bus (`src/bus/Bus.zig`) with:

1. **Open Bus Tracking**: Explicit `OpenBus` struct tracking last bus value
2. **RAM Mirroring**: 2KB RAM mirrored 4 times ($0000-$1FFF)
3. **Separate Read Paths**: `read()` vs `readInternal()` for bus update control
4. **6502 JMP Bug**: Dedicated `read16Bug()` for indirect JMP page wraparound
5. **Comprehensive Test Coverage**: 16 unit tests covering all AccuracyCoin requirements

## Implementation Details

### Open Bus Behavior

```zig
pub const OpenBus = struct {
    value: u8 = 0,
    last_update_cycle: u64 = 0,

    pub inline fn update(self: *OpenBus, value: u8, cycle: u64) void {
        self.value = value;
        self.last_update_cycle = cycle;
    }
};
```

**Rationale**:
- Explicit tracking ensures all reads/writes update the bus correctly
- Cycle tracking enables future decay simulation if needed
- Inline functions minimize overhead

### RAM Mirroring

```zig
// RAM: 2KB ($0000-$07FF) mirrored through $0000-$1FFF
0x0000...0x1FFF => self.ram[address & 0x07FF]
```

**Test Coverage**:
- Read mirroring: Write to $0000, read from $0800/$1000/$1800
- Write mirroring: Write to $0800, verify all mirrors updated
- Comprehensive: Test all 2KB addresses with all 4 mirrors

### ROM Write Protection

```zig
0x4020...0xFFFF => {
    // Writes ignored but open bus updated
}
```

**AccuracyCoin Requirement**: "Writing to ROM should not overwrite the byte in ROM"

### 6502 Indirect JMP Bug

```zig
pub fn read16Bug(self: *Self, address: u16) u16 {
    const low_addr = address;
    const high_addr = if ((address & 0x00FF) == 0x00FF)
        address & 0xFF00  // Wrap to page start
    else
        address +% 1;
    // ...
}
```

**Historical Bug**: JMP ($xxFF) reads low byte from $xxFF and high byte from $xx00 (not $xy00)

## Test Coverage

### Unit Tests (16 total, 100% passing)

1. **Initialization**: RAM zeroed, open bus cleared
2. **Basic R/W**: Simple read/write operations
3. **RAM Mirroring Read**: All 4 mirrors return same value
4. **RAM Mirroring Write**: Writes to mirrors update base RAM
5. **RAM Mirroring Comprehensive**: Test all 2KB addresses
6. **Open Bus - Read**: Reads update bus value
7. **Open Bus - Write**: Writes update bus value (even to ROM)
8. **Open Bus - Unmapped**: Unmapped reads return last bus value
9. **ROM Protection**: ROM writes ignored but bus updated
10. **read16**: Little-endian 16-bit reads
11. **read16 Wraparound**: Address wraparound at boundaries
12. **read16Bug**: JMP indirect page wrap bug
13. **read16Bug Normal**: Normal case behaves correctly
14. **dummyRead**: Dummy reads update open bus
15. **Cycle Counter**: Cycle tracking works
16. **Comprehensive Scenario**: Multi-operation bus behavior

### AccuracyCoin Coverage

| Test | Requirement | Status |
|------|-------------|--------|
| RAM Mirroring #1 | 13-bit mirrors 11-bit | ✅ Covered |
| RAM Mirroring #2 | Mirror writes update base | ✅ Covered |
| ROM is not Writable | ROM write protection | ✅ Covered |
| Open Bus #1 | Not all zeroes | ✅ Covered |
| Open Bus #5 | Dummy reads update bus | ✅ Covered |
| Open Bus #8 | Writes always update bus | ✅ Covered |

## Performance Considerations

### Inline Functions
All hot-path functions marked `inline`:
- `OpenBus.update()`: Called on every bus access
- `dummyRead()`: Used frequently in addressing modes
- `tick()`: Called every cycle

### Memory Layout
```zig
ram: [2048]u8,           // 2KB, cache-friendly
open_bus: OpenBus = .{}, // Small struct, likely in same cache line
cycle: u64 = 0,          // Cycle counter
```

**Rationale**: Compact layout improves cache locality for hot paths.

## Alternatives Considered

### Alternative 1: No Explicit Open Bus Tracking
**Approach**: Return zeros for unmapped regions

**Pros**: Simpler implementation

**Cons**:
- Fails AccuracyCoin open bus tests
- Not hardware-accurate
- Can't emulate games relying on open bus

**Why rejected**: Hardware accuracy is primary goal

### Alternative 2: Function Pointers for Memory Regions
**Approach**: Use function pointer table for memory regions

**Pros**: More flexible for different hardware configurations

**Cons**:
- Performance overhead (indirect calls)
- Complicates inlining
- Overkill for NES (fixed memory map)

**Why rejected**: NES memory map is fixed; switch statement is faster

### Alternative 3: Separate Bus Value for Reads/Writes
**Approach**: Track separate open bus value for reads vs writes

**Pros**: More accurate to actual hardware (read and write bus lines)

**Cons**:
- Added complexity
- NES behavior doesn't require this distinction
- AccuracyCoin doesn't test for it

**Why rejected**: YAGNI - no games or tests require this

## Testing Strategy

### Unit Test Philosophy
1. **Test one thing**: Each test validates a single behavior
2. **Avoid open bus pollution**: Fresh `Bus.init()` or direct `ram[]` access
3. **AccuracyCoin mapping**: Comments reference specific test requirements
4. **Edge cases**: Boundary conditions explicitly tested

### Regression Prevention
All tests are deterministic and run on every build:
```bash
zig test src/bus/Bus.zig
```

Future additions must maintain 100% test pass rate.

## Future Enhancements

### When PPU Added
- Integrate PPU register mirroring ($2000-$3FFF)
- PPU open bus behavior (bits 0-4 of $2002, etc.)
- Test PPU-specific bus conflicts

### When APU Added
- APU/IO register reads ($4000-$4017)
- $4015 special behavior (doesn't update bus on read)
- Controller port open bus (upper 3 bits)

### When Cartridge Added
- Mapper-specific read/write behavior
- Cartridge RAM handling
- Bus conflicts for certain mappers

## References

- AccuracyCoin README: `/home/colin/Development/RAMBO/AccuracyCoin/README.md`
- NESDev Wiki - CPU memory map: https://www.nesdev.org/wiki/CPU_memory_map
- NESDev Wiki - Open bus behavior: https://www.nesdev.org/wiki/Open_bus_behavior
- 6502 JMP bug: https://www.nesdev.org/wiki/Errata

## Validation

### Build Status
```bash
$ zig test src/bus/Bus.zig
All 16 tests passed.
```

### Code Coverage
- All public functions tested
- All memory regions covered
- All AccuracyCoin bus requirements validated

## Updates

### 2025-10-02
- Initial implementation complete
- All 16 unit tests passing
- Ready for CPU integration
