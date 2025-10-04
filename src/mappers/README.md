# Additional Mappers - Not Yet Implemented

**Status:** Planned for future phases
**Priority:** MEDIUM (game compatibility)
**Reference:** `docs/06-implementation-notes/STATUS.md`, `CLAUDE.md`

## Overview

Additional mapper implementations beyond Mapper 0 (NROM):

**Current Status:**
- ✅ **Mapper 0 (NROM)** - Fully implemented in `src/cartridge/mappers/Mapper0.zig`

**Planned Mappers** (priority order):
1. **MMC1** (Mapper 1) - 28% game coverage, 6-8 hours
2. **MMC3** (Mapper 4) - 25% additional coverage, 12-16 hours
3. **UxROM** (Mapper 2) - Common mapper, 4-6 hours
4. **CNROM** (Mapper 3) - Simple mapper, 2-3 hours
5. **AxROM** (Mapper 7) - 2-3 hours

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

## Mapper Priority Rationale

**MMC1 First:**
- 28% of NES library
- Critical for popular titles (Zelda, Metroid, Mega Man)
- Moderate complexity (shift register, bank switching)

**MMC3 Second:**
- 25% of NES library
- Required for Super Mario Bros 3, Mega Man 3-6
- Complex (IRQ counter, CHR bank switching)

See `CLAUDE.md` section "For Mapper Development" for implementation guidelines.
