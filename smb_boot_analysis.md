# Super Mario Bros Boot Analysis

## Problem Summary
SMB displays blank screen and never enables rendering (PPUMASK stays 0x00, never becomes 0x1E).

## Log Evidence

### SMB Boot Sequence (from your logs):
```
[VBlank] SET at scanline=241, dot=1, nmi_enable=false
[VBlank] CLEAR at scanline=261, dot=1 (flag was: true)
[PPUMASK] Write 0x06, show_bg: false -> false, show_sprites: false -> false
[$2002 READ] value=0x06  ← WRONG! This should be 0x8X or 0x0X, NOT 0x06!
[VBlank] SET at scanline=241, dot=1, nmi_enable=true
[PPUMASK] Write 0x00
[$2002 READ] value=0x80
[$2002 READ] value=0x00
[PPUMASK] Write 0x00
... endless loop with nmi_enable=false ...
```

### Critical Bug Found:
**`[$2002 READ] value=0x06`** - This is reading **PPUMASK value** instead of PPUSTATUS!

The value 0x06 is exactly the PPUMASK value that was just written. This indicates:
1. Open bus is being corrupted
2. OR: $2002 read is returning wrong register data
3. OR: Register mirroring is broken

## Hypothesis

SMB's init code likely does:
```
LDA #$06
STA $2001  ; Write PPUMASK = 0x06 (rendering off for init)
LDA $2002  ; Read PPUSTATUS to clear VBlank flag
; Expects: A = 0x80 (VBlank set) or 0x00 (VBlank clear)
; Actually gets: A = 0x06 (previous PPUMASK write!)
; Game logic: if A != expected_value, infinite loop
```

## Next Steps

1. **Verify open bus handling in PPUSTATUS reads**
   - File: `src/ppu/logic/registers.zig:35`
   - Check: `state.status.toByte(state.open_bus.value)`

2. **Verify bus routing doesn't corrupt open bus**
   - File: `src/emulation/bus/routing.zig:23`
   - Check: Is `reg` being passed correctly to `readRegister`?

3. **Check if PPUMASK write corrupts PPU open bus improperly**
   - Open bus should preserve lower 5 bits
   - PPUSTATUS should return (status_bits[7:5] | open_bus[4:0])

## Expected PPUSTATUS Behavior

Reading $2002 should return:
```
Bit 7: VBlank flag (1 if in VBlank, 0 otherwise)
Bit 6: Sprite 0 hit
Bit 5: Sprite overflow
Bits 4-0: Open bus (last value on bus)
```

**NOT** the last written PPUMASK value!

## Action Items

- [ ] Add debug logging to track open_bus.value before PPUSTATUS read
- [ ] Verify `PpuStatus.toByte()` is correctly merging bits
- [ ] Check if writes to $2001 are incorrectly updating PPU open bus
- [ ] Compare with working Mario Bros to see if it avoids this bug
