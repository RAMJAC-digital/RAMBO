# 6502 Absolute,X Addressing Mode - Hardware Timing Specification

**Source:** NESdev Wiki (https://www.nesdev.org/6502_cpu.txt)
**Last Updated:** 2025-10-06

## Overview

Absolute,X addressing mode adds the X register to a 16-bit address. The timing varies based on whether a page boundary is crossed during index addition.

---

## LDA Absolute,X (Opcode $BD) - Cycle-by-Cycle Breakdown

### Case 1: No Page Boundary Crossing (4 cycles total)

**Example:** `LDA $0130,X` with X=$05 → Effective address $0135

| Cycle | PC | Address Bus | Data Bus | Action | Notes |
|-------|------|------------|---------|--------|-------|
| 1 | $0000 | $0000 | $BD | Fetch opcode | PC → PC+1 |
| 2 | $0001 | $0001 | $30 | Fetch low byte | PC → PC+2, Calculate base_low + X |
| 3 | $0002 | $0002 | $01 | Fetch high byte | PC → PC+3, Check for carry |
| 4 | $0003 | $0135 | **$99** | **Read value + Execute** | **No carry → Read completes, LDA executes** |

**Key Insight:** Cycle 4 reads the operand AND executes the LDA instruction **in the same cycle**.

### Case 2: Page Boundary Crossed (5 cycles total)

**Example:** `LDA $01FF,X` with X=$05 → Effective address $0204

| Cycle | PC | Address Bus | Data Bus | Action | Notes |
|-------|------|------------|---------|--------|-------|
| 1 | $0000 | $0000 | $BD | Fetch opcode | PC → PC+1 |
| 2 | $0001 | $0001 | $FF | Fetch low byte | PC → PC+2, Calculate $FF + $05 = $04 (carry!) |
| 3 | $0002 | $0002 | $01 | Fetch high byte | PC → PC+3, Detect carry |
| 4 | $0003 | **$0104** | ?? | **Dummy read at wrong address** | High byte not yet fixed |
| 5 | $0003 | **$0204** | **$AA** | **Read correct value + Execute** | High byte fixed, read + execute |

**Key Insight:** Cycle 5 reads the operand AND executes the LDA instruction **in the same cycle**.

The dummy read at cycle 4 uses address $01FF+$05 = $0204, but with high byte not incremented yet ($0104).

---

## STA Absolute,X (Opcode $9D) - Always 5 Cycles

**Note:** Write instructions do NOT have conditional timing.

| Cycle | Action | Notes |
|-------|--------|-------|
| 1 | Fetch opcode | |
| 2 | Fetch low byte | Calculate base_low + X |
| 3 | Fetch high byte | Check for carry |
| 4 | **Dummy read** at potentially wrong address | Always happens |
| 5 | **Write value** at correct address | Fix high byte if needed, then write |

**Key Difference:** Write instructions always take the extra cycle because they cannot do a "dummy write" at the wrong address.

---

## Critical Hardware Behaviors

### 1. Read Combines with Execute

For **read** instructions (LDA, ADC, CMP, etc.):
- The final operand read happens **in the same cycle** as instruction execution
- There is NO separate "execute" cycle after the read
- This is why no page cross = 4 cycles, page cross = 5 cycles

### 2. Address Calculation Happens Incrementally

During cycle 3:
- High byte is being fetched from memory
- Low byte + X addition completes
- Carry detection occurs
- Decision is made: "Do we need cycle 5?"

### 3. Dummy Read at Wrong Address

When page boundary is crossed:
- Cycle 4: Reads at `(base_high << 8) | ((base_low + X) & 0xFF)`
- This is the address WITHOUT the high byte carry applied
- The value read is discarded
- Cycle 5: Reads at correct address with high byte incremented

### 4. Why Writes Don't Have Conditional Timing

Write instructions (STA, STX, STY) always take 5 cycles because:
- Cannot do a "dummy write" at wrong address (would corrupt memory)
- Must always wait for address calculation to complete
- Then perform single write at correct address

---

## Comparison: RMW Instructions (7 cycles for Absolute,X)

RMW instructions (ASL, INC, DEC, ROL, ROR, etc.) have different timing:

| Cycle | Action |
|-------|--------|
| 1 | Fetch opcode |
| 2 | Fetch low byte |
| 3 | Fetch high byte, calculate address |
| 4 | Dummy read (page cross handling) |
| 5 | Read original value |
| 6 | Write original value back (critical for hardware accuracy!) |
| 7 | Write modified value |

**Note:** Cycles 5-7 are the modify operation. Cycles 1-4 are identical to write instructions.

---

## Implementation Requirements for Cycle-Accurate Emulation

### MUST Match Hardware:
1. ✅ LDA abs,X (no page cross) = **4 cycles** (not 5!)
2. ✅ LDA abs,X (page cross) = **5 cycles** (not 6!)
3. ✅ STA abs,X (always) = **5 cycles**
4. ✅ ASL abs,X (always) = **7 cycles**

### Critical Pattern:
- **Read instructions:** Final read + execute happen in SAME cycle
- **Write instructions:** Always have dummy read, then write
- **RMW instructions:** Read, dummy write, real write (3 separate cycles)

---

## References

- NESdev 6502 CPU Reference: https://www.nesdev.org/6502_cpu.txt
- NESdev Cycle Times: https://www.nesdev.org/wiki/6502_cycle_times
- Visual 6502: http://www.visual6502.org/
- Why LDA takes extra cycle at page boundaries: https://retrocomputing.stackexchange.com/questions/145/
