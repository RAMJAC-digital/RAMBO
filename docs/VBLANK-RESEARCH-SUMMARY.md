# NES VBlank Race Condition - Quick Reference

## The 5 Key Answers

### 1. CPU Read vs PPU VBlank Set (Same Cycle)

**When both happen at scanline 241 dot 1:**
- CPU reads $2002 and gets **0** (not 1)
- CPU does NOT see the VBlank flag being set
- **NMI is suppressed** for that frame

**Why?** If the CPU read happens during the same PPU dot that the VBlank flag is set, the read sees the cleared state (due to the complex timing of sub-cycle positions within the dot).

---

### 2. How Chips Coordinate (Phase Relationship)

**Master Clock Mechanism:**
- Single master clock drives both CPU and PPU
- CPU divides by 12, PPU divides by 4 (NTSC)
- Results in 3 PPU dots per CPU cycle
- Creates **4 possible alignment states at power-on** (NTSC)

**Sub-Cycle Alignment:**
- CPU memory operations can occur at 5 different sub-cycle positions within a PPU dot
- Position cycles through: 0, 1, 2, 3, 4, 0, 1, 2... (repeats every 5 CPU cycles)
- Alignment state is **random at power-on, then fixed for entire session**

**Effect on VBlank:** The sub-cycle position affects whether CPU sees flag as being set or not during dot 1 of scanline 241.

---

### 3. Exact Behavior at Different Dots

| Dot Relative to VBlank Set | Read Result | Flag Visible | NMI Suppressed |
|---------------------------|-------------|---|---|
| **Dot 0** (1 before) | 0x?? | No | Yes |
| **Dot 1** (same) | 0x?? | No | Yes |
| **Dot 2** (1 after) | 0x8? | Yes | Yes |
| **Dot 3+** (2+ after) | 0x8? | Yes | No |

**Key Insight:** Reads at dots 0, 1, or 2 suppress NMI. Only reads at dot 3 or later allow NMI to be detected by CPU.

---

### 4. Flag Clearing: Before or After?

**The sequence:**
1. CPU initiates memory read of $2002
2. PPU places current PPUSTATUS value on data bus (flag is either 0 or 1)
3. CPU reads the value
4. PPU processes clear-flag-on-read logic
5. PPU clears VBlank flag to 0

**Answer:** Flag is cleared AFTER the value is returned to CPU.

**However:** If the read is poorly timed (during dot 1 when flag is being set), the CPU may not see the flag set in the first place—it reads 0 and the flag is "cleared" (which means stays at 0, since it wasn't set yet).

---

### 5. Hardware Test ROMs

**AccuracyCoin** (Best for this)
- 129 comprehensive accuracy tests
- Includes $2002 timing validation
- Targets NTSC RP2A03G/RP2C02G
- Repository: https://github.com/100thCoin/AccuracyCoin

**vbl_nmi_timing** (Specialized)
- 7 sequential test ROMs
- Single-clock accuracy validation
- Tests race condition edge cases
- Validated on real hardware
- Repository: https://github.com/christopherpow/nes-test-roms/tree/master/vbl_nmi_timing

---

## The Core Problem (Why Games Stutter)

Games that poll PPUSTATUS waiting for VBlank can miss the flag entirely:

```
Game loop:
  Loop: LDA $2002      ; Read PPUSTATUS
        BMI Loop       ; Branch if bit 7 set (VBlank)
        BPL *          ; Wait for active display
        ; Do game logic during VBlank
```

**If the read happens on dot 0 of scanline 241:** Flag is still 0, CPU misses the entire VBlank period.

**If the read happens on dot 1 of scanline 241:** Flag gets set during the read, but CPU sees 0, misses VBlank again.

**Solution:** Games should use NMI instead of polling. NMI fires reliably on every frame.

---

## Critical Implementation Points

1. **VBlank flag is set at scanline 241 dot 1.** Period. No variation.

2. **CPU/PPU phase alignment is deterministic but random.** Defined at power-on, fixed thereafter.

3. **The race window is very tight:** dots -1, 0, 1, 2 relative to set event.

4. **Sub-cycle timing matters enormously:** Different alignments cause reads on the same dot to see different values.

5. **This is why test ROMs are essential:** Sub-cycle timing is practically impossible to get right without validation.

---

## Documentation Sources

**Primary Authority:** nesdev.org Wiki
- PPU registers: https://www.nesdev.org/wiki/PPU_registers
- PPU frame timing: https://www.nesdev.org/wiki/PPU_frame_timing
- NMI: https://www.nesdev.org/wiki/NMI

**Technical Forums:** nesdev.org Forums
- CPU - PPU clock alignment: https://forums.nesdev.org/viewtopic.php?t=6186
- CPU/PPU timing: https://forums.nesdev.org/viewtopic.php?t=10029
- Archived discussions: https://archive.nes.science/

**Practical Validation:** Test ROM Source Code
- AccuracyCoin on GitHub
- vbl_nmi_timing test suite with commented source

---

## Alignment State Complexity Warning

The behavior described above is for **one specific alignment state** (the "easiest" one). Different power-on alignment states may cause:
- Reads to see changes 1 dot earlier or later
- Different NMI suppression windows
- Different timing of edge cases

This is why:
- Test ROMs may fail on different NES units
- Emulators need to handle multiple alignment scenarios
- Some games work on real hardware but fail on emulators (and vice versa)

**Citation:** nesdev.org PPU_frame_timing: "The results only cover one particular set of alignments, namely the one which gives the fewest number of special cases..."

---

## For RAMBO Implementation

Check `/src/ppu/` for current VBlank handling:
- `State.zig` - PPU state including VBlank flag
- `Logic.zig` - VBlank flag setting at scanline 241 dot 1
- Test validation against AccuracyCoin and vbl_nmi_timing

The key questions for your implementation:
1. Is VBlank flag set EXACTLY at scanline 241 dot 1? ✓
2. Does $2002 read clear the flag AFTER returning the value? ✓
3. Is NMI properly suppressed in the -1 to +1 dot window? ✓
4. Are you handling sub-cycle alignment states? (Critical for edge cases)
